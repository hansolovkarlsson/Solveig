# Solveig for VS Code

Syntax colouring, bracket matching and comment toggling for `.sol` files, and
nothing else. Completion is the editor's own word-based kind, which VS Code
gives every registered language for free: it offers the words already in the
buffer, and `wordPattern` in `language-configuration.json` is what makes a
selector one word and `#10` none.

There is no language server. Solveig is prototype-based and every send is
dynamic, so what a receiver can answer is a run-time question, and a tool
that guessed would be wrong often enough to be worse than none. What a server
could honestly do is listed at the end.

## Installing

The extension is not on the marketplace. Two ways in, neither needing `node`:

1. In VS Code, run **Developer: Install Extension from Location...** from the
   command palette and pick this folder.
2. Or link the folder into the extensions directory and reload the window:

   ```sh
   ln -s ~/Projects/Solveig/editors/vscode ~/.vscode/extensions/hansolovkarlsson.solveig-0.1.0
   ```

Either way VS Code reads the folder in place, so a change to the grammar here
is live after **Developer: Reload Window**.

`.sol` is also Solidity's extension. If a Solidity extension is installed the
two compete for the file, and the one to win is chosen per file with
**Change Language Mode**, or per workspace with `files.associations`.

## What the grammar knows

It is the lexical half of [GRAMMAR.md](../../docs/GRAMMAR.md), as TextMate
regexes in `syntaxes/solveig.tmLanguage.json`:

| Scope | What |
| --- | --- |
| `comment.line.semicolon` | `;` to the end of the line |
| `string.quoted.double`, `constant.character.escape` | `"..."` and the four escapes; a fifth is `invalid.illegal.escape` |
| `constant.numeric.integer`, `.hex`, `.binary`, `.float` | `#45`, `$FF08`, `%1010`, `45.5e3` |
| `constant.other.symbol` | `'name` |
| `keyword.control.directive` | `@include`, `@expr`; any other `@word` is `invalid.illegal.directive` |
| `keyword.operator.assignment` | `:=` |
| `entity.name.function.send` | the selector of `x:selector` |
| `entity.name.function.definition` | the selector of `x:selector := ...` |
| `variable.parameter`, `variable.other.temporary` | `{ a, b \| ... }` and `\| t \|` |
| `variable.language`, `constant.language` | `self`; `nil`, `true`, `false` |
| `keyword.operator` | the ladder, inside `@expr` only |
| `entity.name.function.call` | `sin(x)`, inside `@expr` only |

Two things follow from the grammar page and are worth knowing when the colour
looks wrong:

- **There are no keywords**, so `ifTrue`, `whileTrue` and `do` are coloured as
  the sends they are, and `self`, `nil`, `true` and `false` are coloured only
  because every reader expects it.
- **Operators exist only inside `@expr`**, and a region is lexical, so the
  grammar keeps a second set of bracket rules for use inside one. A `-`
  outside a region belongs to the number after it; inside one it is the
  operator.

One limit: a block's parameters and temporaries are read with the brace they
follow, or, for temporaries, at the start of the next line, which is where
`{ n, p, q |` then `| it |` puts them. A parameter list wrapped across two
lines, or a temporaries list wrapped across three, is left plain rather than
coloured wrong.

`test.py` runs the grammar over every `.sol` file in the repository with a
small TextMate engine of its own and checks the tokens it expects. It is not
in `make test`; run it by hand after changing the grammar.

## What a language server could add

Not built, and not on the roadmap. Listed so that the boundary is recorded:
go-to-definition and completion for selectors bound with `:=` in the open
files and `lib/`, hover on such a definition, and diagnostics by running
`solas` on save and mapping its errors to lines. What it could not add is
completion by receiver, because there is no receiver type to read.
