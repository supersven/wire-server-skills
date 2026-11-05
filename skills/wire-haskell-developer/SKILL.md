---
name: wire-haskell-developer
description: Use whenever writing, editing, reviewing or refactoring any Haskell code, including short snippets and one-liners (.hs files, cabal/Haskell projects, wire-server). Corrects common agent mistakes in Haskell code.
---

# Wire Haskell developer

Rules correcting common agent mistakes in Haskell code. Apply when writing or reviewing Haskell.
Each rule consists of statements with IDs (used to tie them to evals).

### HS001: Avoid partial functions

- HS001.2: Make the empty case explicit in the type. If the empty case has no sensible default, change the result type (e.g. to `Maybe`) instead of keeping a partial call (`error`) or inventing a default (`minBound`, `0`). A signature handed to you does not change this: when it cannot express the empty case, change it and say so in one line.

### HS002: Parse structured text with a parser library

- HS002.1: Use megaparsec instead of taking text apart by hand. When code deconstructs structured text (prefixes, delimited fields, fixed formats) with chains of `splitOn`, `split`, `breakOn`, `stripPrefix`, `span`, `splitAt` or `words`, write a megaparsec parser instead, provided megaparsec is in the project's `build-depends`. The grammar then reads off the code, and malformed input gets a real error. Run the parser with `parse (p <* eof)` so trailing garbage is rejected, and render failures with `errorBundlePretty`.
- HS002.2: Use Parsec when megaparsec is not a dependency. If the project depends on `parsec` but not on `megaparsec`, write the parser with `Text.Parsec` (`Text.Parsec.Text`) instead of splitting by hand. Do not add a new dependency for a small parser.

### HS003: Let patterns do the matching

- HS003.1: Branch on parameters with patterns first, guards second, `if`/`when`/`unless` last. When the choice depends only on the function's parameters, write one clause per shape (`f _ [] = ...`, `f x xs = ...`; also instead of a `case` on a parameter) rather than one clause with guards, and guards (`f x | x > 3 = ...`) rather than `if`, `when` or `unless`. The head then shows the cases, bound variables come from the match, and the compiler checks coverage. Use guards only for conditions a pattern cannot express (comparisons, predicates), and `if`/`when`/`unless` only when the condition depends on something computed in the body.
- HS003.2: Flatten nested `case`/`if` into one pattern. When a `case` branch immediately does another `case` or `if` on a value, combine them with nested patterns, literals, or a tuple scrutinee (`case (a, b) of`), so every outcome is one line of one `case`.
