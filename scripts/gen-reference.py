"""Print REFERENCE.md, generated from SKILL.md statements and evals.json.

One section per statement ("- HSnnn.n: <Title>. <body>"), title = first sentence.
Each eval of the statement contributes an optional Source, the Prompt (which
contains any input code) and the Output.
"""

import json
import re
import sys
from pathlib import Path

skill_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "skills/wire-haskell-developer")


def fence(text):
    """Code fence longer than any backtick run inside, so inner blocks stay inner."""
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    ticks = "`" * max(3, longest + 1)
    return f"{ticks}\n{text}\n{ticks}"


def block(label, text):
    return f"{label}:\n{fence(text)}"


def example(eval_):
    ref = eval_["reference"]
    parts = []
    if "source" in ref:
        parts.append("Source: " + ", ".join(f"`{path}`" for path in ref["source"]))
    parts.append(block("Prompt", eval_["prompt"]))
    parts.append(block("Output", ref["output"]))
    return "\n\n".join(parts)


def section(statement_id, title, evals):
    examples = "\n\n".join(example(e) for e in evals if e["statement"] == statement_id)
    return f"## {statement_id}: {title}\n\n### Examples\n\n{examples}"


evals = json.loads((skill_dir / "evals/evals.json").read_text())["evals"]
statements = re.findall(
    r"^- (HS\d+\.\d+): ([^.]*)\.", (skill_dir / "SKILL.md").read_text(), re.MULTILINE
)
print("\n\n".join(section(sid, title, evals) for sid, title in statements))
