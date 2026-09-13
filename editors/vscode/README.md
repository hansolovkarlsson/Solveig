# Solveig for VS Code

Syntax colouring, bracket matching and comment toggling for `.sol` files, and
completion of the selector after a colon: every message the reference
documents and every selector the shipped libraries export, each with what it
answers. Type `#3:` and `add` is at the top of the list; type `a:` and the
whole list is offered, because what `a` is cannot be known without running
the program, which is the boundary the last section is about.

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
| `entity.name.type.object` | every other name: the receiver of a send, an argument, a bound name. An object is a prototype, so it is coloured as a type |
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

The objects are coloured as types because that is the scope every theme
gives a colour of its own; unscoped they took the editor's foreground and
vanished among the punctuation. A different colour is a setting rather than a
grammar change:

```json
"editor.tokenColorCustomizations": {
  "textMateRules": [
    { "scope": "entity.name.type.object.solveig", "settings": { "foreground": "#C586C0" } }
  ]
}
```

One limit: a block's parameters and temporaries are read with the brace they
follow, or, for temporaries, at the start of the next line, which is where
`{ n, p, q |` then `| it |` puts them. A parameter list wrapped across two
lines, or a temporaries list wrapped across three, is left plain rather than
coloured wrong.

## What completion knows

`selectors.json` is written by `messages.py` from two places and typed in
from none:

- **The Message index** in [REFERENCE.md](../../docs/REFERENCE.md#message-index),
  which the build holds to `builtins.c`, gives the list; the per-type tables
  give each message its signature and its *Answers* cell. Where a type's own
  table lacks a row (`float` says *everything integer has*), the row is
  borrowed and marked as such.
- **`lib/*.sol`**, for every `receiver:name := { params |` a library binds,
  less any name its object's `exports` leaves out, with the one line the
  comment above it says.

The provider offers after a colon and nowhere else, not inside a string or a
comment, and not at the `:=` of a binding. When the text before the colon is
a literal, `#3`, `"a"`, `[...]`, `{...}`, or a prototype's name, `integer`,
`re`, the selectors that receiver answers sort first and the rest follow;
anything else, `a:` or `x:size:`, is unknown and the list is offered in one
order. A selector whose every signature takes arguments inserts as `name($1)`
with the cursor inside the parentheses. Snippets in `snippets/` give the
shapes: `block`, `temps`, `method`, `object`, `exports`, `while`, `dict`,
`include`, `expr`.

The list is a generated file, so `messages.py --check` says when the
documents have moved past it, and `test.py` runs that check. Regenerate with
`python3 editors/vscode/messages.py` after a message is added to the
reference or a library.

## Checking it

`test.py` runs three things and is not in `make test`, which stays C11 and
`make`; run it by hand after changing anything here:

- the grammar over every `.sol` file in the repository with a small TextMate
  engine of its own, and over a fixture of lines tokenised by hand;
- `messages.py --check`, that `selectors.json` is current;
- `completion.js` under `osascript`, the JavaScript engine every Mac has,
  against cases written from the reference. No `node` is needed, here or to
  install.

## What a language server could add

Not built, and not on the roadmap. Listed so that the boundary is recorded:
go-to-definition and completion for selectors bound with `:=` in the open
files, hover on such a definition, and diagnostics by running `solas` on save
and mapping its errors to lines. What it could not add is completion by
receiver beyond the literal in front of the colon, because there is no
receiver type to read.
