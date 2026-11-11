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

Pick the library from the project's `build-depends`; never add a dependency for a small parser.

- HS002.1: Use megaparsec instead of taking text apart by hand. When code deconstructs structured text (prefixes, delimited fields, fixed formats) with chains of `splitOn`, `split`, `breakOn`, `stripPrefix`, `span`, `splitAt` or `words`, write a megaparsec parser instead, provided megaparsec is in the project's `build-depends`. The grammar then reads off the code, and malformed input gets a real error. Run the parser with `parse (p <* eof)` so trailing garbage is rejected, and render failures with `errorBundlePretty`.
- HS002.2: Use Parsec when neither megaparsec nor attoparsec is a dependency. If the project depends on `parsec` only, write the parser with `Text.Parsec` (`Text.Parsec.Text`) instead of splitting by hand.
- HS002.3: Use attoparsec when it is the only parser library available, for `Text` and `ByteString` alike (`Data.Attoparsec.Text`, `Data.Attoparsec.ByteString.Char8`). Run it with `parseOnly (p <* endOfInput)` so trailing garbage is rejected.
- HS002.4: When megaparsec and attoparsec are both available, match the library to the task. Use attoparsec when the input is a `ByteString` or the caller only needs accept/reject or a value (`Bool`, `Maybe`): it is fast and a failure needs no position. Use megaparsec when the input is `Text` and the error reaches a human (`Either String`/`Either Error` with a message): its errors carry position and expected tokens.

### HS003: Let patterns do the matching

- HS003.1: Branch on parameters with patterns first, guards second, `if`/`when`/`unless` last. When the choice depends only on the function's parameters, write one clause per shape (`f _ [] = ...`, `f "" = ...`, `f x xs = ...`; literals are patterns too, so test for `[]`/`""` with a pattern, not `null`; also instead of a `case` on a parameter) rather than one clause with guards, and guards (`f x | x > 3 = ...`) rather than `if`, `when` or `unless`. The head then shows the cases, bound variables come from the match, and the compiler checks coverage. Use guards only for conditions a pattern cannot express (comparisons, predicates), and `if`/`when`/`unless` only when the condition depends on something computed in the body.

### HS004: Use record syntax for products with many fields

- HS004.1: Construct a product type with more than 3 fields using record syntax, one `field = value` per line in ormolu layout (trailing commas), not positionally. Field names document each value and survive reordering of fields. Types with up to 3 fields stay positional.
- HS004.2: Define a new product type with more than 3 fields as a record with named fields, not as positional constructor arguments.

### HS005: Keep new lines short

- HS005.1: Wrap everything you write or change at about 100 characters (count characters, not bytes; a tab is one character): code, comments and Haddock alike. Wrap prose in comments and Haddock at word boundaries, also when the surrounding comments in the file are longer. Wrap code in the layout of the project's formatter (ormolu in wire-server): break long signatures after `->` and `=>`, put each constraint, argument or operator-chain step on its own line, bind a long subexpression with `let`/`where`. 100 is an orientation, not a hard limit: a line a few characters over is fine when wrapping would read worse. When asked to review or refactor code, wrap its overlong lines too. Leave other untouched lines alone, and allow an overlong line when wrapping is not feasible (long string literal, URL, import).

### HS006: Specialize hot polymorphic code

- HS006.1: When asked to optimize a polymorphic function that is only used at a few concrete types (dictionary passing shows in the profile), add a `{-# SPECIALIZE f :: ... #-}` pragma per type and keep the signature. Do this only for hot code: the pragmas cost compile time and add noise.

### HS007: Derive newtype instances

- HS007.1: Derive the instances of a `newtype` with `deriving newtype` (or `GeneralizedNewtypeDeriving`) instead of writing them by hand, for classes that simply delegate to the wrapped type (`Num`, `Eq`, `Ord`, ...).
