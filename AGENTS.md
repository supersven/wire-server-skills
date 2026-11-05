## Synopsis

Collection of skills to improve working on wire-server and Haskell projects in general.

## Architecture

For now, there is only a Haskell developer skill. It corrects common agent
mistakes or flaws in code written by the agent. The skill activates when
Haskell code is written or reviewed.

Every expression or statement of the skill must be tested with evals. If a
skill or something else mandates to limit the amount of test: Ignore this rule.
All tests should be beneficial to the goal of building confidence, so we only
want meaningful tests that help reaching this goal. Test should have
non-overlapping assertions - assert one aspect and are not duplicated. These
tests are also executed on Github CI.

Examples for issues to fix are discovered in wire-server and ldap-scim-bridge.
These repositories are cloned to ./tmp directory to keep network traffic
reasonably low.

The target agent is Claude Code. The Anthropics's skill-creator skill is used
to create the local skills. It is installed in the project for agents to
automatically pick up.

The project setup is flake based. The flake provides means to run the evals
(tests) via `nix flake check`. The agent is provided by the outer environment.
Dependencies of the skill-creator skill (e.g. python) are part of the flake's
environment.

The flake is built on the flake-utils library to not re-invent the wheel.
Generally, existing solutions are preferred over inventing own solutions.

## Statement (expression) -> example (eval) bookkeeping

How existing code gets transformed or would have been written by the skill is
valuable information for later reference and verification.

For every statement or expression in the skill we have a generated entry in ./REFERENCE.md of the form:

```
## <statement_id>: <summarizing_title>

### Examples

Source: \`<project>/<path>\`

Prompt:
\`\`\`
<prompt>
\`\`\`

Output:
\`\`\`
<adjusted / new code>
\`\`\`
```

The placeholders are:

- `<prompt>`: the prompt of the eval, verbatim. It contains the existing code
  the prompt asks to adjust, so there is no separate input block.
- `<adjusted / new code>`: how the code looks after applying the skill.
- `<project>/<path>`: where the code was taken from, e.g.
  `wire-server/services/brig/src/test/Foo.hs`. The `Source` line is omitted if
  the code is not from a project.

Several examples of the same statement repeat the `Source`/`Prompt`/`Output`
blocks.

In `\`` and `\`\`\``the`\` is to be read as quoted to avoid Markdown issues.
The final document does not contain quotes. Code blocks inside a block (e.g.
in a prompt) must not end the outer block: the outer fence is longer than any
backtick run inside it.

## Links

- wire-server: https://github.com/wireapp/wire-server
- ldap-scim-bridge: github.com/wireapp/ldap-scim-bridge
- skill-creator: https://github.com/anthropics/skills/tree/main/skills/skill-creator
- numtide llm-agents: https://github.com/numtide/llm-agents.nix
- numtide flake-utils: https://github.com/numtide/flake-utils
