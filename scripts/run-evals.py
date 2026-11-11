"""LLM evals for a skill.

Per eval, every expectation must hold in a majority of EVAL_RUNS runs with the skill
and must fail in a majority without it (baseline), plus the skill's trigger evals.
Evals marked "negative": true (good code that must stay untouched) only run with
the skill. Needs `claude` on PATH and authentication. Run from the repo root.

Environment:
  SKILL_DIR     skill under test (default skills/wire-haskell-developer)
  EVAL_MODEL    model for solving and grading (default sonnet)
  EVAL_EFFORT   effort level (default medium)
  EVAL_RUNS     runs per eval and config (default 3)
  EVAL_JOBS     parallel `claude -p` calls (default 16)
  EVAL_ONLY     comma separated eval ids to run, e.g. 12,15; add `trigger` for
                the trigger evals. Unset: all evals and the trigger evals.
  EVAL_WORKERS  parallel trigger-eval workers (default 1)
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

GRADER_SCHEMA = {
    "type": "object",
    "required": ["expectations"],
    "properties": {
        "expectations": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["text", "passed", "evidence"],
                "properties": {
                    "text": {"type": "string"},
                    "passed": {"type": "boolean"},
                    "evidence": {"type": "string"},
                },
            },
        }
    },
}

repo = Path.cwd()
skill_dir = Path(os.environ.get("SKILL_DIR", "skills/wire-haskell-developer"))
skill_name = skill_dir.name
model = os.environ.get("EVAL_MODEL", "sonnet")
effort = os.environ.get("EVAL_EFFORT", "medium")
runs = int(os.environ.get("EVAL_RUNS", "3"))
jobs = int(os.environ.get("EVAL_JOBS", "16"))
trigger_workers = os.environ.get("EVAL_WORKERS", "1")
only = [s for s in os.environ.get("EVAL_ONLY", "").split(",") if s]
claude_flags = ["--model", model, "--effort", effort]


def die(message):
    sys.exit(f"run-evals: {message}")


def claude(project, prompt, *flags):
    """Run `claude -p` in `project`; return its stdout."""
    result = subprocess.run(
        ["claude", "-p", prompt, *claude_flags, *flags],
        cwd=project, capture_output=True, text=True,
    )
    if result.returncode != 0:
        die(f"claude failed in {project}: {result.stderr.strip()}")
    return result.stdout


def grade(project, grader_prompt, expectations, output):
    """Pass/fail per expectation (matched by position) for one solver output."""
    prompt = (
        f"{grader_prompt}\n\n---\n"
        "Grade the output below. No files exist; the output text is the whole transcript and result.\n"
        f"Expectations: {json.dumps(expectations)}\n\nOutput:\n{output}"
    )
    out = claude(project, prompt, "--output-format", "json",
                 "--json-schema", json.dumps(GRADER_SCHEMA))
    graded = json.loads(out).get("structured_output", {}).get("expectations", [])
    if len(graded) != len(expectations):
        die("grader did not return one result per expectation")
    return [g["passed"] for g in graded]


def setup(work):
    """Projects the evals run in: with only the skill under test, and with nothing."""
    # All claude calls (incl. skill-creator's run_eval) go through a wrapper:
    # - project settings only: no user CLAUDE.md, hooks, plugins or skills, so results match across machines
    # - a real executable: python's Popen cannot run a shebang-less `claude` wrapper
    bin_dir = work / "bin"
    bin_dir.mkdir()
    wrapper = bin_dir / "claude"
    real = shutil.which("claude") or die("claude not on PATH")
    wrapper.write_text(f'#!/usr/bin/env bash\nexec "{real}" --setting-sources project "$@"\n')
    wrapper.chmod(0o755)
    os.environ["PATH"] = f"{bin_dir}{os.pathsep}{os.environ['PATH']}"

    # Copied, not symlinked: claude does not discover skill symlinks pointing outside the project.
    # The evals are removed so the model cannot read the expected answers.
    with_skill = work / "with-skill"
    shutil.copytree(repo / skill_dir, with_skill / ".claude" / "skills" / skill_name,
                    ignore=shutil.ignore_patterns("evals", ".claude"))
    (work / "baseline").mkdir()
    return {"skill": with_skill, "baseline": work / "baseline"}


def run_evals(evals, projects, grader_prompt):
    """Report lines (in eval order) for the solve+grade runs, all run in parallel."""
    tasks = [(e, config, n)
             for e in evals
             for config in (["skill"] if e.get("negative") else ["skill", "baseline"])
             for n in range(runs)]

    def job(task):
        e, config, _ = task
        output = claude(projects[config], e["prompt"])
        return grade(projects[config], grader_prompt, e["expectations"], output)

    results = {}
    with ThreadPoolExecutor(jobs) as pool:
        futures = {pool.submit(job, task): task for task in tasks}
        for i, future in enumerate(as_completed(futures), 1):
            e, config, n = futures[future]
            results.setdefault((e["id"], config), []).append(future.result())
            print(f"[{i}/{len(tasks)}] eval {e['id']} {config} run {n + 1}", file=sys.stderr, flush=True)

    lines = []
    for e in evals:
        for config in (["skill"] if e.get("negative") else ["skill", "baseline"]):
            for key, text in enumerate(e["expectations"]):
                p = sum(run[key] for run in results[(e["id"], config)])
                # With the skill an expectation must pass in a majority of runs, without it fail in one.
                ok = p * 2 > runs if config == "skill" else p * 2 < runs
                label = "with skill" if config == "skill" else "without skill"
                lines.append(f"{'PASS' if ok else 'FAIL'} eval {e['id']} {label} [{p}/{runs} pass]: {text}")
    return lines


def run_triggers(work):
    """Trigger evals via skill-creator's run_eval, sequential by default.

    Run in an empty project: run_eval installs a synthetic skill there; the real one would compete.
    Parallel `claude -p` runs made every query miss locally (cause not diagnosed).
    """
    project = work / "trigger"
    (project / ".claude").mkdir(parents=True)
    env = {**os.environ, "PYTHONPATH": str(repo / ".claude/skills/skill-creator")}
    result = subprocess.run(
        [sys.executable, "-m", "scripts.run_eval",
         "--eval-set", str(repo / skill_dir / "evals/trigger.json"),
         "--skill-path", str(repo / skill_dir),
         "--runs-per-query", str(runs), "--num-workers", trigger_workers,
         "--timeout", "90", "--model", model, "--verbose"],
        cwd=project, env=env, capture_output=True, text=True,
    )
    if result.returncode != 0:
        die(f"trigger evals failed: {result.stderr.strip()}")
    return [f"{'PASS' if r['pass'] else 'FAIL'} trigger [{r['triggers']}/{r['runs']}]: {r['query']}"
            for r in json.loads(result.stdout)["results"]]


def main():
    evals = json.loads((skill_dir / "evals/evals.json").read_text())["evals"]
    if only:
        unknown = set(only) - {str(e["id"]) for e in evals} - {"trigger"}
        if unknown:
            die(f"unknown EVAL_ONLY ids: {', '.join(sorted(unknown))}")
        evals = [e for e in evals if str(e["id"]) in only]
    with_triggers = not only or "trigger" in only
    grader_prompt = (repo / ".claude/skills/skill-creator/agents/grader.md").read_text()

    print(f"model={model} effort={effort} runs={runs} jobs={jobs}")
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        projects = setup(work)
        lines = run_evals(evals, projects, grader_prompt)
        print("\n".join(lines))
        if with_triggers:
            print("trigger evals")
            trigger_lines = run_triggers(work)
            print("\n".join(trigger_lines))
            lines += trigger_lines
    sys.exit(any(line.startswith("FAIL") for line in lines))


main()
