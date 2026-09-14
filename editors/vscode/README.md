# Solveig for VS Code

Syntax colouring, bracket matching and comment toggling for Solveig's `.sol`
files and Parasol's `.psol` files, and completion of the selector after a colon: every message the reference
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

## What the Parasol grammar knows

`syntaxes/parasol.tmLanguage.json` is Parasol's token table from
[its reference](../../parasol/docs/REFERENCE.md#tokens), which no dialect can
change, and that is the whole reason a grammar can colour a language whose
syntax arrives with the file. Solveig's tokens with three differences:

- **Operators are tokens everywhere**: a run of `+ - * / < > = ! & ^ % ~ ? \`,
  or `||`, is `keyword.operator`. Whether the run is *declared* is the
  compiler's to know, so an undeclared one looks like a declared one. A lone
  `|` is an operator only by declaration, and one that no block or group
  header claimed is coloured as one.
- **`-3` is an operator and a literal**, since a float has no sign in Parasol;
  `#-3` keeps its sign, as in Solveig.
- **The header directives have parts.** `@use`, `@infix`, `@infixr`, `@prefix`
  and `@syntax` are `keyword.control.directive`; a declared operator is
  `keyword.operator.declared`, a precedence `constant.numeric.precedence`, a
  message `entity.name.function.send`, `=>` `keyword.operator.template` and
  the template after it is code, with `left`, `right` and `operand` as
  `variable.parameter.operand`. In `@syntax`, the form's name is
  `entity.name.function.syntax`, the words between holes are
  `keyword.control.syntax-word`, a hole's name `variable.parameter.hole` and
  its kind `storage.type.kind`; a kind that is not one of the five is
  `invalid.illegal.kind`. `@expr` is refused by Parasol and coloured as
  `invalid`; `@include` passes through and is a directive; any other
  `@word`, or a declaration the grammar could not read whole, is `invalid`.

What it gets wrong, and cannot help: in `while (n < #20) {`, `while` is a
word that `lib/clike.psol` made into syntax through `@use`, and a grammar
cannot read another file. It is coloured as a form used, since a name before
a parenthesis is that in either shape, `swap(a, b)` or `while (c)`; a
syntax word with no parenthesis after it, `then`, `do`, `else`, is coloured as
an object. In the file that declares it, `@syntax while ...`, the word is
coloured as syntax. What the grammar cannot read, the next section can.

## What the dialect gives

`dialect.js` reads the header of the open module and of everything it
`@use`s, resolved the way Parasol resolves it: beside the file using it, then
each entry of `PARASOL_PATH`. The command line's `-I` has no counterpart here.
A file is read once, so a diamond costs nothing and a cycle is not followed;
a `@use` that cannot be found is skipped, and the header ends at the first
statement, as Parasol's does. From that, in a `.psol` file:

- **A bare word offers the dialect's forms**, each as a snippet built from
  its declaration: `while <c> <b: block>` inserts `while c { }` with the
  hole a tab stop and the block its braces; `swap(a, b)` inserts
  `swap(a, b)` with a stop per parameter. The detail is the declaration's
  head, and the documentation is the declaration as written, with the file
  that said it.
- **Hover on an operator or a syntax word** shows the declaration that gave
  it its meaning and the file it came from: which file said `*` is 70, and
  against what. An operator nothing declared shows nothing, which is what
  the compiler would then refuse.

`test.py` parses every `.psol` file's header with it, checks that it found as
many declarations as the file has directive lines and that every `@use`
resolves beside the file, and runs its cases against `lib/clike.psol` through
the example that uses it.

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

In a Parasol module two more places offer: after `@`, the eight directive
forms from [the header table](../../parasol/docs/REFERENCE.md#the-header), each
inserting as a snippet with a tab stop per part; and after the colon inside
a hole, `<t: `, the five kinds. Both lists come from Parasol's reference by the
same generator.

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

- both grammars over every `.sol` and `.psol` file in the repository with a
  small TextMate engine of its own, and over fixtures of lines tokenised by
  hand;
- `messages.py --check`, that `selectors.json` is current;
- `completion.js` and `dialect.js` under `osascript`, the JavaScript engine
  every Mac has, against cases written from the two references, and the
  dialect reader over every `.psol` header. No `node` is needed, here or to
  install.

## What a language server could add

Not built, and not on the roadmap. Listed so that the boundary is recorded:
go-to-definition and completion for selectors bound with `:=` in the open
files, hover on such a definition, and diagnostics by running `solas` or
`parasol` on save and mapping their errors to lines. What it could not add is
completion by receiver beyond the literal in front of the colon, because
there is no receiver type to read. The dialect reader above is the one piece
of a server's work that needed no server: a header is small, declarative and
read whole.
