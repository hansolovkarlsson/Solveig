# Reference

*Everything you look up rather than read. One page, mostly tables.*

[README.md](../README.md) argues the design and [GRAMMAR.md](GRAMMAR.md) states
the formal grammar. This is neither: it is the surface you check a spelling
against. Where the two disagree with this page, they are right and this page is
a defect.

---

## The command line

```sh
parasol [options] <file.psol>
```

| | |
| --- | --- |
| `-o <file>` | where to write it; the default is the source name with `.sol` for `.psol`, or `.sob` with `--sob` |
| `-I <dir>` | where a `@use` falls back to; repeatable, first wins. With `--sob`, handed to `solas` as well, for `@include` |
| `--sob` | run `solas` on the generated source, the one beside this binary or else the one on PATH; the `.sol` is kept beside the `.sob`, and `@expr` is never turned on |
| `--dump` | with `--sob`, have `solas` disassemble the chunk as well; alone, a usage error |
| `--map` | write the source map beside the output, as `<output>.map` |
| `--tree` | print the expanded tree and stop, writing nothing, whatever else was asked |
| `--version` | show the version and stop |
| `--help`, `-h` | show usage and stop |

One file at a time. Exit 0 on success, 64 on a usage error, 65 on a source
error. With `--sob`, a Parasol error is still 65 and writes nothing; once the
`.sol` is written the status is `solas`'s own, 127 when no `solas` could be
run, and the `.sol` stays where the map can be read against it.

```sh
parasol --map examples/vectors.psol     # -> examples/vectors.sol + .sol.map
solas examples/vectors.sol -o examples/vectors.sob
solvm examples/vectors.sob
```

or, the first two lines as one:

```sh
parasol --sob --map examples/vectors.psol   # -> .sol, .sol.map and .sob
```

**With `--sob`, `-o` names the `.sob`**, and the `.sol` goes beside it with the
extension swapped rather than beside the source: `-o build/v.sob` writes
`build/v.sol`, `build/v.sob` and, with `--map`, `build/v.sol.map`. The pair is
the output and the map points into the `.sol`, so the three stay together.
Which `solas`: the one in the directory `argv[0]` names, when it names one and
a `solas` is there, which is every `bin/` this repository makes; otherwise
`execvp`'s, off PATH. `PARASOL_PATH` is not handed on, being about `@use`;
`SOLUM_PATH` is `solas`'s to read, and it does.

### make

From Solveig's root, whose Makefile has held the Parasol rules since
2026-09-14 in a section of its own; there is no Makefile in this directory.

| | |
| --- | --- |
| `make` | `bin/parasol`, beside Solveig's four binaries. A C11 compiler and `make`, and nothing else. |
| `make test` | Solveig's suite, then this one: the unit tests, plus every example and program through `solas` and `solvm` |
| `make sanitize` | the whole suite under AddressSanitizer and UBSan, from a clean build. **Worth doing before a release** — see [POSTMORTEM.md](POSTMORTEM.md) 15. It leaves an instrumented `bin/`; `make clean` restores a normal one. |
| `make examples` | every example, Solveig's and Parasol's, to a `.sob` |
| `make ember` / `grammar` / `digest` / `ledger` / `prose` / `basic` / `bignum` | one program at a time, built and run |
| `make install` | `bin/parasol` to `$PREFIX/bin` with the four, `lib/*.psol` to `$PREFIX/lib/solum` with Solveig's library; it prints the `PARASOL_PATH` to export |
| `make clean` | remove `build/`, `bin/` and everything generated here |

The build needs no Solveig. `make test`, `make examples` and the program
targets do, and hand it the `solas` and `solvm` the same run built. What the
rules enforce, so that the claim does not depend on anybody remembering it:
Parasol objects are compiled with Parasol's include path only, `bin/parasol`
is linked against `libparasol.a` only, and `make test` refuses a `bin/parasol`
that exports a `sol_` symbol.

---

## The header

Directives come before every statement, and are the only thing that changes how
the rest of the file parses. A directive after code is an error.

| | |
| --- | --- |
| `@use "<file>".` | read that dialect file's header into this module |
| `@infix <op> <prec> <message>.` | infix operator, grouping left; becomes `left:<message>(right)` |
| `@infix <op> <prec> => <template>.` | the same, standing for a template; operands are `left` and `right` |
| `@infixr <op> <prec> <message>.` | the same, grouping right |
| `@prefix <op> <message>.` | prefix operator; becomes `operand:<message>` |
| `@prefix <op> => <template>.` | the same, as a template; the operand is `operand` |
| `@syntax <name>(<params>) => <template>.` | a form that reads like a call |
| `@syntax <name> <hole> <word> … => <template>.` | a form that reads like a statement |

`@include "<file>.sol".` is **not** a header directive — it is Solveig's own, so
Parasol treats it as a statement and passes it straight through.

**Higher precedence binds tighter.** A prefix operator binds tighter than any
infix and looser than a send, so `~x & z` is `(~x) & z` and `~a:b` is `~(a:b)`.

**A template's arguments arrive unevaluated**, which is the whole reason forms
exist: the template may put an argument somewhere the caller never wrote. A
short circuit needs this — Solveig's `and` takes a *block*, so
`@infix && 30 and.` compiles to `a:and(b)` and is refused at run time, while
`@infix && 30 => left:and({ right }).` is right.

**`@infixr` is declared, tested and has no customer.** Nothing in the repository
uses it.

### Which shape a form should have

A **call** if its answer is used; a **pattern** if it is a step. A pattern's
trailing hole takes an expression and an expression continues through sends and
infix operators, so nothing written after a pattern applies to its result. A
call ends at its closing parenthesis. Both parse, and choosing wrongly is
silent — [GRAMMAR.md](GRAMMAR.md) argues it at length.

### What a hole accepts

`<name: kind>`; the kind is optional and defaults to `expression`. All five are
decided by looking at what was parsed, so none needs an evaluator.

| | |
| --- | --- |
| `expression` | anything at all, and the default |
| `name` | an identifier |
| `literal` | an integer, float, string or symbol |
| `block` | `{ … }` |
| `place` | something that may be assigned to |

**A hole asks for what the template does not supply.** `while <t> do <b>` puts
its own braces on, so its holes take expressions; `repeat <n> times <b: block>`
hands its hole straight over, so it must ask.

**A `block` that is not one says how to become one.** Since 0.16.0 the
diagnostic carries `wrap it in braces`, because braces make a block out of
anything and that is the fix every time. The other four say what they wanted
and stop: nothing turns `#1` into a `place`, and a note prescribing there would
be advice that does not work.

**A pattern begins with a word, and needs a word between two holes** unless the
second is a `block`. That is what lets one token decide, and is why the matcher
never backtracks.

---

## Tokens

A dialect declares operators, precedence and meaning. **It does not declare
tokens.** No `.psol` can change this table.

| | |
| --- | --- |
| name | `[A-Za-z_][A-Za-z0-9_]*` |
| integer | `#` then an optional `-` then digits, `$` and hexadecimal digits, or `%` and binary digits |
| float | digits, optionally a `.` and more digits, optionally `e`/`E` with an optional sign and more digits |
| string | `"…"`, with `\"` `\\` `\n` `\t` `\r` and no other escape |
| dictionary | `#[` opens one; `]` closes it, and `=` separates a pair |
| symbol | `'` and then a name |
| directive | `@` and then a name |
| operator | one or more of `+ - * / < > = ! & ^ % ~ ? \`, or `\|\|` — except a `%` immediately before `0` or `1`, which begins a binary integer |
| comment | `;` to the end of the line |

**Operator characters run together as far as they go.** `a<=b` is one operator
`<=`, and `#6 \-#1` is `\-` — undeclared, and an error rather than a misparse.
`:=` is taken before any of this and is always itself.

**`|`, `:`, `.` and `,` are not operator characters and cannot become any.**
`|` separates a block's parameters from its body; a dialect that could spell an
operator `|` would be one where `{ a | b }` has two readings. `||` is two
bars and not a bar, taken by the lexer before the bar, and belongs to every
dialect rather than to any declaration.

---

## What is not here: the messages

**Parasol documents how a module's notation becomes sends. It does not document
what sends exist**, and it should not — that is
[Solveig's reference](https://hansolovkarlsson.github.io/Solveig/docs/REFERENCE.html),
which lists every message on every type.

Saying so is new, and it is here because a reader who had never seen this
language got the whole notation right on their first attempt and then spent
every one of their remaining cycles on the other side of the line: `concat`,
`asString` and `display` are messages **this repository names nowhere**, and
`string does not understand 'show'` tells you a name is wrong without telling
you what is right. See [second-reader.md](second-reader.md).

**A dialect gives you syntax; Solveig gives you the library.** `@use` reaches
the first and `@include` the second, and neither reaches the other.

## The shipped dialects

In `lib/`, installed to `$PREFIX/lib/parasol` by `make install`. A dialect file
holds directives and nothing else; a statement in one is an error.

### `lib/arith.psol` — arithmetic and logic

Standalone.

| | | |
| --- | --- | --- |
| `*` `/` `%` | 70 | `mul` `div` `mod` |
| `+` `-` | 60 | `add` `sub` |
| `<` `>` `<=` `>=` | 40 | `lessThan` `greaterThan` `lessOrEqual` `greaterOrEqual` |
| `==` `!=` | 40 | `equals` `notEquals` |
| `&&` | 30 | `left:and({ right })` — a template, for the short circuit |
| `\|\|` | 25 | `left:or({ right })` — likewise |
| `!` | prefix | `not` |

### `lib/control.psol` — statements

`@use "arith.psol"`, so everything above comes with it.

| | |
| --- | --- |
| `if <c> then <a>` | `c:ifTrue({ a })` |
| `if <c> then <a> else <b>` | `c:ifElse({ a }, { b })` |
| `unless <c> then <a>` | `c:not:ifTrue({ a })` |
| `while <t> do <b>` | `{ t }:whileTrue({ b })` |
| `repeat <n> times <b: block>` | `n:repeat(b)` |
| `swap <a: place> and <b: place>` | exchanges them, via a hygienic temporary |

### `lib/clike.psol` — C's operators and C's control flow

Standalone, and deliberately so. It shares `&&`, `||`, `!` and — since
2026-09-02 — the full comparison set with arith.psol; what still differs is `=`
for assignment and control flow written with parentheses and braces rather than
as words.

| | | |
| --- | --- | --- |
| `*` `/` `%` | 70 | `mul` `div` `mod` |
| `+` `-` | 60 | `add` `sub` |
| `==` `<` `>` | 40 | `equals` `lessThan` `greaterThan` |
| `!=` `<=` `>=` | 40 | `notEquals` `lessOrEqual` `greaterOrEqual` |
| `&&` | 30 | `left:and({ right })` |
| `\|\|` | 25 | `left:or({ right })` |
| `=` | 10 | `left := right` |
| `!` | prefix | `operand:not` |

| | |
| --- | --- |
| `if <c> <t: block>` | `c:ifTrue(t)` |
| `if <c> <t: block> else <e: block>` | `c:ifElse(t, e)` |
| `while <c> <b: block>` | `{ c }:whileTrue(b)` |
| `do <b: block> while <c>` | runs the block once, then loops |

**What C has that it cannot**, and the file says why for each: `;` between
statements (`;` opens a comment); `42` without the `#` (a bare number is a
*float* in Solveig); `x++`, `a[i]` and `p->f` (there are no postfix
operators); and a lone `|` (see *Tokens*).

### One spelling per operation

Across every dialect in this repository:

| | logical | bitwise |
| --- | --- | --- |
| and | `&&` | `&` |
| or | `\|\|` | `\|` |
| not | `!` | `~` |
| xor | **none** — and `!=` is xor for booleans | `^` |

**C's table exactly**, since 0.14.0. A lone `|` is not an operator *character*
and cannot be, but it may be *declared* — a bar is a token of its own and the
parser looks one up, so `{ a | b }` stays a parameter and a body in every
module. The bitwise column is declared per file rather than in `lib/`, because a
file doing bitwise work wants its own rungs: `examples/utf8.psol` and
`programs/digest/sha2.psol` both declare `&` and `|`, at different precedences,
against different neighbours.

`\` is free and unused. It was the bitwise `or` from 0.1.0 to 0.13.0, when a
bar could not be had.

**There is no logical xor, and there is no symbol for one to have.** C has no
`^^`; the languages that offer boolean xor reuse something — Java and Python
take `^`, Pascal and Perl take an `xor` keyword. Solveig's boolean understands
`not`, `and`, `or`, `ifTrue`, `ifFalse` and `ifElse`, and `^` is `bitXor`, which
is integer-only: *boolean does not understand 'bitXor'*.

**What there is, is `!=`.** For booleans, xor and not-equals are the same
operation, which is why nobody invents a symbol for it. `lib/clike.psol` and, since 2026-09-02,
`lib/arith.psol` both declare `!=` as `notEquals`, so `a != b` on two booleans is
already an xor in either dialect. Nothing has to write `a:notEquals(b)` as a
send any more.

**If it were ever spelled as its own operator it would be `^^`** — the doubled
form, beside `&&` and `||`, for the same reason those are doubled: the single
character is the bitwise one and the pair is the logical one. It is a
declaration and nothing more:

```
@infix  ^^  35 notEquals.        ; between && at 30 and || at 25
```

**`lib/` does not declare `^^`**, because nothing has wanted one — and `!=`
arriving in arith.psol has made it less likely to, not more: the spelling that
was missing is there now, under the name Solveig gives it. Recorded so the
spelling is settled if something ever does.

---

## Where a `@use` is looked for

1. beside the file using it
2. each `-I` directory, in order
3. each entry of `PARASOL_PATH`, colon-separated

The order `@include` uses over in Solveig. **Read once**, so a diamond costs
nothing and a dialect's declarations cannot collide with themselves. A file
still being read is a cycle, and is an error naming the whole chain.

**A `@use`d file is read into the header of the module using it**, which is why
a dialect file may hold no statements, and why two dialects declaring one
operator collide in the file that used them both rather than in either of
themselves. The later declaration wins, and Parasol says so rather than letting it
pass.

---

## What comes out

A `.sol` of Solveig source, beginning with a banner naming the version, and —
with `--map` — a `.sol.map` beside it.

```
# parasol source map 1
# from examples/vectors.psol
# to   examples/vectors.sol
#
# generated  source   offset  [file, when not the one above]
3:1  23:1  917
```

`generated` and `source` are `line:column`; `offset` is into the unit's shared
text; the fourth field appears when the position is in a `@use`d file rather
than the module. One generated line may name several origins — a template's and
its arguments' — which is what expansion carries spans for.

**A generated name is `t__1`.** Hygiene renames every name a *template* binds,
per expansion, to one nothing in the module uses — checked against every file
the module is made of, not just the one on the command line.

---

## Where everything is

Descriptions of what each thing *found* live with the thing. This is only the
map.

Paths from Solveig's root. Since 2026-09-14 the compiler's C is laid out as
`solas/`, `solid/` and the others are, and its tests are beside theirs.

```
parasol/cmd/      main.c, the command line
parasol/include/  the public headers, under parasol/
parasol/src/      the compiler          lex, reader, dialect, tree, expand, emit
parasol/lib/      dialect files         arith.psol, control.psol, clike.psol
parasol/examples/ five, run by `make test`
parasol/programs/ seven real programs, each with its own README
tests/            test_parasol_reader, _expand, _map, _use, _sob, among Solveig's
parasol/docs/     the documents below
editors/          VS Code colours a .psol file and completes its directives: editors/vscode/README.md
```

| example | |
| --- | --- |
| [`vectors.psol`](../examples/vectors.psol) | precedence, associativity, a prefix operator, and where a send binds |
| [`utf8.psol`](../examples/utf8.psol) | Solveig's `integer:asUtf8`, written in operators |
| [`forms.psol`](../examples/forms.psol) | `unless`, `while` and `swap` declared by the module; hygiene shown by running |
| [`dialect.psol`](../examples/dialect.psol) | a one-line header, everything else out of `lib/`, with a diamond |
| [`clike.psol`](../examples/clike.psol) | C's shape, out of `lib/clike.psol` |

| program | |
| --- | --- |
| [`programs/ember`](../programs/ember) | a small language compiled to ARM64 assembly, to a running binary |
| [`programs/grammar`](../programs/grammar) | a grammar toolkit, and two grammars written over it |
| [`programs/digest`](../programs/digest) | SHA-256, agreeing with `shasum -a 256` |
| [`programs/ledger`](../programs/ledger) | a statement in fixed-point decimal, against figures computed elsewhere |
| [`programs/prose`](../programs/prose) | a document written in its own dialect, rendered to text |

Each program carries predictions recorded **before** it was written and a *What
it found* section written after. Predictions that were wrong stay in, marked
wrong.

| document | |
| --- | --- |
| [does-it-pay.md](does-it-pay.md) | what seven programs and four strangers say about whether a declared grammar is worth it |
| [what-is-parasol.md](what-is-parasol.md) | how the parts fit together, as five questions |
| [pipeline.html](pipeline.html) | the same path drawn |
| [GRAMMAR.md](GRAMMAR.md) | the core grammar, and which shape a form should have |
| [ROADMAP.md](ROADMAP.md) | what is outstanding, and what is refused |
| [COMPLETED.md](COMPLETED.md) | the case for each finished piece, as argued before it |
| [CHANGELOG.md](CHANGELOG.md) | what landed, per version, with the commit |
| [POSTMORTEM.md](POSTMORTEM.md) | every defect found here, and **what found it** |
| [journal.md](journal.md) | what a day consisted of |
| [conventions.md](conventions.md) | the standing agreements and the method |
| [targets.md](targets.md) | what Parasol targets, and what a program in Parasol targets |
| [rules-and-logic.md](rules-and-logic.md) | how far the rules could go, and where they stop |
| [solveig-notes.md](solveig-notes.md) | what Parasol has found in Solveig |
