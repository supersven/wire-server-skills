#!/usr/bin/env bash
# Every rule needs statements, every statement (- HSnnn.m: ...) in SKILL.md needs an eval,
# evals cite exactly one known statement; no duplicate expectations/ids.
set -euo pipefail

skill_dir=${1:-skills/wire-haskell-developer}
evals=$skill_dir/evals/evals.json
skill=$skill_dir/SKILL.md

# Plain assignments (not one big $(...)) so a failing command aborts the script.
jq -e '.evals | all(has("id", "statement", "prompt", "expectations", "reference"))' "$evals" >/dev/null ||
  { echo "$evals: eval without id/statement/prompt/expectations/reference"; exit 1; }
dups() { jq -r "[$1] | group_by(.) | map(select(length > 1) | .[0])[]" "$evals"; }

rules=$(sed -nE 's/^### (HS[0-9]+):.*/\1/p' "$skill" | sort -u)
statements=$(sed -nE 's/^- (HS[0-9]+\.[0-9]+):.*/\1/p' "$skill" | sort -u)
with_statements=$(echo "$statements" | sed -E 's/\..*//' | sort -u)
cited=$(jq -r '.evals[].statement' "$evals" | sort -u)

no_statement=$(comm -23 <(echo "$rules") <(echo "$with_statements") | sed 's/^/rule without statement: /')
no_eval=$(comm -23 <(echo "$statements") <(echo "$cited") | sed 's/^/statement without eval: /')
unknown=$(comm -13 <(echo "$statements") <(echo "$cited") | sed 's/^/eval cites unknown statement: /')
dup_expectations=$(dups '.evals[].expectations[]' | sed 's/^/duplicate expectation: /')
dup_ids=$(dups '.evals[].id' | sed 's/^/duplicate eval id: /')

problems=$(printf '%s\n' "$no_statement" "$no_eval" "$unknown" "$dup_expectations" "$dup_ids" | sed '/^$/d')
[ -z "$problems" ] || { echo "$problems"; exit 1; }
