# Changelog

Notable changes to Proto, newest first.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md); the case for each
piece of work as it was argued *before* the work is in
[COMPLETED.md](COMPLETED.md); what a day actually consisted of is in
[journal.md](journal.md).

---

### `@language`, removed — 0.10.0, 2026-09-02

**The only directive that did nothing, gone.** It parsed, recorded a name in
`ProtoDialect`, and nothing ever read it back. It was optional, ignored and
written by every `.pro` in the tree, which is a ritual rather than a feature.

**It was removed rather than made to act on something.** The roadmap had wanted
it to select a reader or an emitter for nine versions, and neither exists to be
selected. The near-miss option was to make it *assert* — one reader, one
emitter, any other name an error — and that was rejected because it prices the
change without asking whether the directive is right:

> `@language solveig.` at the top of `examples/forms.pro` says the body below is
> Solveig. That file declares `+`, `<`, `>`, `unless`, `while` and `swap`. Its
> body is not Solveig and Solveig cannot read it.

The reading under which the line was true — *the substrate is Solveig* — is the
same for every `.pro` and is already carried by the extension. The thing that
could differ between two files is the output, and the word for that is
`@target`, which is what gets added if a second emitter is ever built.
COMPLETED.md 14 carries the whole argument; [targets.md](targets.md) is amended
where it used to argue the other way.

| | |
| --- | --- |
| the header now takes | `@use`, `@infix`, `@infixr`, `@prefix`, `@syntax` |
| an old file gets | `'@language' is not a directive Proto knows`, and a note naming the five |
| `ProtoDialect` loses | `name` and `declared_at` |

**Nothing else in the language changed.** The suite reports the same 58, 6, 34
and 10 checks over the same ten examples and programs. `tests/test_map.c` needed
its line-number comments renumbered and nothing else: a directive emits nothing,
so dropping a header line moves no generated line.

### Phoenix is Proto — 2026-09-01

**No version, and nothing in the language changed.** The compiler, the library,
the headers, the repository and the source extension are spelled differently and
do the same things in the same order: the suite reports the same 58, 6, 34 and
10 checks over the same ten examples and programs it reported the day before.

**The name was already promised elsewhere.** Solveig's `docs/ideas.md` has held
it since 2026-08-28 for a deferred idea — *a second language whose output Solum
uses* — closing that entry with *the name, should it happen, is Phoenix*. That
language is not this one: it would earn its place by publishing a **library**
Solum consumes, and the entry explicitly refuses *a nicer skin on this one*.
Proto emits a program's source and always has. Until today the word named both,
and the one that had shipped was holding it.

The scheme the code already had is kept, and only respelled:

| | |
| --- | --- |
| `PhxToken` | `ProtoToken` |
| `phx_lex_init` | `proto_lex_init` |
| `PHX_TOK_BAR` | `PROTO_TOK_BAR` |
| `phoenix/include/phoenix/` | `proto/include/proto/` |
| `bin/phoenix`, `libphoenix.a` | `bin/proto`, `libproto.a` |
| `PHOENIX_PATH` | `PROTO_PATH` |
| `.phx` | `.pro` |

**A module is `.pro` and not `.proto`**, which is the one choice here that is not
mechanical. `.proto` belongs to Protocol Buffers, and Linguist and most editors
would have highlighted every module in this tree as protobuf — against a README
that opens by arguing a tool can tell what language a file is in. The extension
is four characters either way, so the suffix arithmetic in `default_output_path`
is untouched.

**The replacement asserted its match**, as [conventions.md](conventions.md)
requires and as three recorded defects come from skipping. The suite
was run green *before* the rename, to compare against a number rather than an
impression; the staged diff is **1,435 lines out and 1,435 back in**, which is
the only shape a pure respelling can have; and a case-insensitive search for the
old name returns nothing outside `scratch/`, which is Hans's.

`7ccd6bc`. The repository is `hansolovkarlsson/Proto` now, and the four commits
that had been sitting unpushed since 2026-08-31 went up with it.

### `programs/digest` — 2026-08-31

**No version.** SHA-256, and the third program written in Proto. It agrees
with `shasum -a 256` on the three FIPS 180-4 vectors and five block-boundary
cases, all eight checked against an independent oracle before the expected file
was written, and its file mode is byte-identical to the system tool.

**The first customer for the operator half.** `ember` and `grammar` both leaned
on `@syntax` patterns; this is nothing but shifts, rotations, exclusive-ors and
masked additions. It was chosen because Solveig's own `programs/sha256sum` wrote
the gap down — *`@expr` has no bit operators, so the one file here that is
nothing but shifts, xors and masks is the one file that cannot use the notation
at all* — and Proto has claimed the answer to that in the abstract since
0.1.0 with nothing to point at.

**What it found**, in full in [its README](../programs/digest/README.md):

- **A dialect can carry a rule rather than a spelling.** Solveig's version needs
  twenty-three `bitAnd`s written by hand because integers trap rather than
  wrapping. This one needs none: `+` *is* addition modulo 2³², declared once in
  a header. That is new in kind — ember's and grammar's dialects only ever saved
  typing.
- **A template costs less than a method, and not much less.** Measured by binary
  search on `--steps`: 1,362,533 instructions against 1,437,417. The template
  saves 2.03 instructions per rotation by not calling, and spends 2.00
  recomputing the `#32:sub(#17)` that nothing folds. **It gives back 98% of what
  it saves**, which is now an open roadmap item with a number attached.
- **A wrong precedence is silent.** `*` declared on `+`'s rung made `at + i * #4`
  into `(at + i) * #4`; it compiled, ran, and failed as an array index four
  calls deep. The operator half's version of *choosing the shape wrongly is
  silent*.
- **The 0.4.0 collision rules got their first real customer**, and the answer was
  not to compose: `sha2.pro` beside `lib/control.pro` collides on four operators
  and the losing order hashes wrongly.

### `||`, in the fixed lexer — 0.9.0, 2026-08-31

**`|` is still the block's own and always will be; `||` is two bars and not a
bar.** The lexer takes it before the bar and hands it to every dialect, so
`lib/clike.pro` now spells C's *or* the way C spells it and the paragraph
apologising for `\/` is gone from that file.

The proposal this answers was a `@token` directive letting a file bind a
spelling to a named token. Refused: it does not decide the ambiguity that
actually blocks `|`, and a declarable token stream would make every downstream
tool implement the directive before it could lex at all. The vocabulary grew
instead of becoming declarable, which is the same answer *a dialect that changes
the lexer* has always had in [ROADMAP.md](ROADMAP.md).

`\/` keeps its job: single `|` is still unavailable, so a bitwise *or* is still
spelled that way, as `examples/utf8.pro` does. `lib/arith.pro` keeps `/\` and
`\/` by choice now rather than by force, and says so.

**What it cost**, checked by compiling it: `{ || … }` used to parse as an empty
list of temporaries and emit nothing. It is `{ | | … }` now. It appeared nowhere
in the repository, and `{ a || b }` was an error before this existed, so nothing
else changed meaning. Five checks in `test_reader.c` hold the line, one of them
on the thing that was taken away.

### The trailing-hole finding, retracted — `d90ea08`, 2026-08-31

**No version.** Two programs had reported that a form's trailing hole swallows
what follows it, and both were the same mistake: a form declared as a *pattern*
when it was an *application*. A call ends at its closing parenthesis and has no
such behaviour. Five forms in `programs/grammar/peg.pro` and one in
`programs/ember/asm.pro` moved to the call shape; the parentheses that existed
only to work around it are gone from both grammars.

The rule — *a pattern for something that reads as a step, a call for something
that reads as an application* — moved from a program's README into
[GRAMMAR.md](GRAMMAR.md), where somebody choosing a shape would look. The real
finding is that **choosing wrongly is silent**: both readings are legal, so
nothing at the declaration can warn.

### `programs/grammar` — `ec302d8`, 2026-08-31

A grammar toolkit, and the second program written in Proto. `examples/calc`
evaluates `100 / 5 - 3 * 4` with precedence; `examples/sexpr` parses
`(a (b c) d)` into nested arrays. Five predictions recorded before it was
written; three right, one right and sharper, one right about the want and wrong
about the level.

**Declined the roadmap's repetition item a second time, with a reason**: a
grammar cannot be written as forms at all, because a template cannot declare a
form, so the rules live in a table as data and the repetition wanted is one
level down in the object language.

### 0.8.0 — two holes in a row when the second is a block — `bed7b37`, 2026-08-31

`@syntax while <c> <b: block> => { c }:whileTrue(b).`, so `while (n < #20) { … }`
is a form. The ban was justified as *no boundary between them*, which was wrong;
the rule is really about **greed**, and a delimited hole has no such problem.
Could not have been relaxed before 0.6.0 gave holes kinds.

`lib/clike.pro` and `examples/clike.pro` land with it.

### A diagnostic for a pattern that read no parts — `f489359`, 2026-08-31

`@syntax vec { <x> }` got *needs `=>`* rather than the message about patterns,
because the better message only fired once a part had been read.

### `/\` and `\/`, and the fix for what that broke — `31d0ffc`, `f0af7c0`, 2026-08-31

A spelling change in `lib/arith.pro`. The first commit replaced `&&` in
`emberc.pro` with a blind global substitution and caught a shell command inside
a comment; the second fixed that and four documents that still spelled the new
operator the old way.

### 0.7.0 — an operator that stands for a template — `23f0cbe`, 2026-08-31

`@infix /\ 30 => left:and({ right }).` The only way to declare an operator whose
right-hand side must not always be evaluated — Solveig's `and` takes a block, and
an operator naming a *message* hands over an argument already evaluated.

**The two extension points did not compose and this is the seam.** `programs/ember`
is what found it.

### `programs/ember` — `e3f1288`, 2026-08-31

The first program written in Proto. A small language compiled to ARM64
assembly, all the way to a running binary. Five predictions recorded first;
three right, one did not bite, one wrong. Two things nobody predicted, one of
which became 0.7.0.

### 0.6.0 — a hole that says what it wants — `f1c8c36`, 2026-08-31

`<a: place>`, `<n: name>`, `<l: literal>`, `<b: block>`, `expression` by default.
All decided by looking at what was parsed, so none needs an evaluator.

Also fixed an infinite loop present since 0.1.0: `synchronize` halts *at* a
closing bracket without consuming it, and the statement loop read it, failed,
synchronised to it and read it again.

### The roadmap, four versions stale — `5bf83af`, 2026-08-31

Three edits to `ROADMAP.md` between 0.2.0 and 0.5.0 had silently done nothing.
The file still called the expander *next*, four versions after it shipped.

### Two design notes — `5c631b8`, `410b8e4`, 2026-08-31

[rules-and-logic.md](rules-and-logic.md): how much of EBNF `@syntax` could grow,
what it must refuse, and why a guard on a rule is the tower question rather than
a feature. Then the other half: if the evaluator is Solveig, `solum/embed.h` is
the door, and **a guard validates, it does not select.**

### 0.5.0 — a form that reads as a statement — `60e6d95`, 2026-08-31

`@syntax unless <test> then <body> => … .` Two forms may share a leading word —
`if <c> then <a>` beside `if <c> then <a> else <b>` — matched together with no
backtracking, because a hole is parsed once and shared.

### 0.4.0 — a dialect that is a file — `c63e1d2`, 2026-08-31

`@use "arith.pro".` **The collision rule, which everything was queuing behind**,
and the answer was Solveig's: the later wins and the compiler says so. A span
carries its file, which is the refactor the rest needed.

### 0.3.0 — the other half of hygiene — `8101c11`, 2026-08-31

A template's *free* references are protected: the caller's local is renamed
throughout its own frame. One pass rather than a resolver, because only
parameters and `| … |` temporaries are locals in Solveig.

### `docs/solveig-notes.md` — `ef43f60`, 2026-08-31

A running log of what Proto finds in Solveig. Two entries at the time; a third
added later recording a prediction about Solveig that was wrong.

### 0.2.0 — forms, hygiene and expansion trails — `2af48cf`, 2026-08-31

`@syntax unless(test, body) => … .` Hygiene in the same commit rather than after
it. Expansion terminates without a counter, because a template may mention only
the forms declared above it.

### `docs/targets.md` — `55dbd72`, 2026-08-31

What Proto targets, and what a program written in Proto targets — two
unrelated questions, and only the first is a Proto question.

### 0.1.0 — the first commit — `5d332a2`, 2026-08-31

A tree of Proto's own, spans on every node, the map, a grammar declared per
module, and a build that takes nothing from Solveig.
