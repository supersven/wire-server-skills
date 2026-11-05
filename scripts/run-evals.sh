#!/usr/bin/env bash
# LLM evals: per eval, expectations must hold in a majority of EVAL_RUNS with the skill and
# must fail in a majority without it (baseline), plus skill trigger evals.
# Needs `claude` on PATH and authentication. Run from repo root.
set -euo pipefail

skill_dir=${SKILL_DIR:-skills/wire-haskell-developer}
model=${EVAL_MODEL:-sonnet}
effort=${EVAL_EFFORT:-medium}
runs=${EVAL_RUNS:-3}
repo=$PWD
skill_name=$(basename "$skill_dir")
evals=$skill_dir/evals/evals.json
claude_flags=(--model "$model" --effort "$effort")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# All claude calls (incl. skill-creator's run_eval) go through this wrapper:
# - project settings only: no user CLAUDE.md, hooks, plugins or skills, so results match across machines
# - a real executable: python's Popen cannot run a shebang-less `claude` wrapper
mkdir "$work/bin"
printf '#!/usr/bin/env bash\nexec %q --setting-sources project "$@"\n' "$(command -v claude)" > "$work/bin/claude"
chmod +x "$work/bin/claude"
export PATH=$work/bin:$PATH

# Projects the evals run in: with only the skill under test, and with nothing.
# Copied, not symlinked: claude does not discover skill symlinks pointing outside the project.
# The evals are removed so the model cannot read the expected answers.
mkdir -p "$work/with-skill/.claude/skills" "$work/baseline"
cp -r "$repo/$skill_dir" "$work/with-skill/.claude/skills/$skill_name"
rm -rf "$work/with-skill/.claude/skills/$skill_name/evals"

grader_prompt=$(cat "$repo/.claude/skills/skill-creator/agents/grader.md")
grader_schema='{"type":"object","required":["expectations"],"properties":{"expectations":{"type":"array","items":{"type":"object","required":["text","passed","evidence"],"properties":{"text":{"type":"string"},"passed":{"type":"boolean"},"evidence":{"type":"string"}}}}}}'
report=$work/report

# run_graded <project dir> <prompt> <expectations json>
# Prints per run a JSON array of pass/fail booleans, one per expectation (matched by position).
run_graded() {
  local dir=$1 prompt=$2 expectations=$3 output
  for _ in $(seq "$runs"); do
    output=$(cd "$dir" && claude -p "$prompt" "${claude_flags[@]}")
    (cd "$dir" && claude -p "$grader_prompt

---
Grade the output below. No files exist; the output text is the whole transcript and result.
Expectations: $expectations

Output:
$output" "${claude_flags[@]}" --output-format json --json-schema "$grader_schema") |
      jq -ce --argjson n "$(jq length <<<"$expectations")" \
        '.structured_output.expectations | select(length == $n) | map(.passed)' ||
      { echo "grader did not return one result per expectation" >&2; return 1; }
  done
}

# report_eval <skill|baseline> <id> <expectations json>; stdin: run_graded output
# With the skill an expectation must pass in a majority of runs, without it fail in a majority.
report_eval() {
  jq -s -r --arg mode "$1" --arg id "$2" --argjson e "$3" --argjson runs "$runs" '
    [transpose[] | map(select(.)) | length] | to_entries[] |
    .value as $p | $e[.key] as $text |
    if $mode == "skill"
    then "\(if $p * 2 > $runs then "PASS" else "FAIL" end) eval \($id) with skill [\($p)/\($runs) pass]: \($text)"
    else "\(if $p * 2 < $runs then "PASS" else "FAIL" end) eval \($id) without skill [\($p)/\($runs) pass]: \($text)"
    end' | tee -a "$report"
}

echo "model=$model effort=$effort runs=$runs"

mapfile -t eval_list < <(jq -c '.evals[]' "$evals")
for e in "${eval_list[@]}"; do
  id=$(jq -r .id <<<"$e")
  prompt=$(jq -r .prompt <<<"$e")
  expectations=$(jq -c .expectations <<<"$e")
  # Assignments, not process substitution, so a failing grader aborts the script.
  grades=$(run_graded "$work/with-skill" "$prompt" "$expectations")
  report_eval skill "$id" "$expectations" <<<"$grades"
  grades=$(run_graded "$work/baseline" "$prompt" "$expectations")
  report_eval baseline "$id" "$expectations" <<<"$grades"
done

echo "trigger evals"
# Empty project: run_eval installs a synthetic skill there; the real one would compete with it.
# Sequential by default: parallel `claude -p` runs made every query miss locally (cause not diagnosed).
mkdir -p "$work/trigger/.claude"
(cd "$work/trigger" && PYTHONPATH="$repo/.claude/skills/skill-creator" \
  python -m scripts.run_eval \
    --eval-set "$repo/$skill_dir/evals/trigger.json" --skill-path "$repo/$skill_dir" \
    --runs-per-query "$runs" --num-workers "${EVAL_WORKERS:-1}" --timeout 90 \
    --model "$model" --verbose) > "$work/trigger.json"
jq -r '.results[] | "\(if .pass then "PASS" else "FAIL" end) trigger [\(.triggers)/\(.runs)]: \(.query)"' \
  "$work/trigger.json" | tee -a "$report"

! grep -q '^FAIL' "$report"
