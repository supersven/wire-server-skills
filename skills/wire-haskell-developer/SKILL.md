---
name: wire-haskell-developer
description: Use whenever writing, editing, reviewing or refactoring any Haskell code, including short snippets and one-liners (.hs files, cabal/Haskell projects, wire-server). Corrects common agent mistakes in Haskell code.
---

# Wire Haskell developer

Rules correcting common agent mistakes in Haskell code. Apply when writing or reviewing Haskell.
Each rule consists of statements with IDs (used to tie them to evals).

### HS001: Avoid partial functions

- HS001.1: Replace partial functions in existing code. When refactoring or reviewing, replace `head`, `tail`, `init`, `last`, `fromJust`, `!!` by pattern matching or total alternatives (`listToMaybe`, `uncons`, `maybe`, `NonEmpty`).
- HS001.2: Make the empty case explicit in the type. If the empty case has no sensible default, change the result type (e.g. to `Maybe`) instead of keeping a partial call (`error`) or inventing a default.
