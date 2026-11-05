#!/usr/bin/env bash
# Print REFERENCE.md generated from SKILL.md rules + evals.json references.
set -euo pipefail

skill_dir=${1:-skills/wire-haskell-developer}
evals=$skill_dir/evals/evals.json

sed -nE 's/^### (HS[0-9]+): (.*)/\1\t\2/p' "$skill_dir/SKILL.md" |
while IFS=$'\t' read -r id title; do
  printf '## %s\n\n### Examples\n' "$title"
  jq -r --arg id "$id" '
    .evals[] | select((.statement | split(".")[0]) == $id) |
    .reference as $r |
    "```\n\($r.example)\n```\n" +
    "- " + (if $r.kind == "rewritten" then "rewritten (`\(.prompt)`)" else "refactored" end) + " ->\n" +
    "```\n\($r.transformed)\n```"
  ' "$evals"
  echo
done
