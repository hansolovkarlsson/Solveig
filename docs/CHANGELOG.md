# Changelog

Notable changes to Phoenix, newest first.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md); the case for each
piece of work as it was argued *before* the work is in
[COMPLETED.md](COMPLETED.md); what a day actually consisted of is in
[journal.md](journal.md).

---

### `||`, in the fixed lexer — 0.9.0, 2026-08-31

**`|` is still the block's own and always will be; `||` is two bars and not a
bar.** The lexer takes it before the bar and hands it to every dialect, so
`lib/clike.phx` now spells C's *or* the way C spells it and the paragraph
apologising for `\/` is gone from that file.

The proposal this answers was a `@token` directive letting a file bind a
spelling to a named token. Refused: it does not decide the ambiguity that
actually blocks `|`, and a declarable token stream would make every downstream
tool implement the directive before it could lex at all. The vocabulary grew
instead of becoming declarable, which is the same answer *a dialect that changes
the lexer* has always had in [ROADMAP.md](ROADMAP.md).

`\/` keeps its job: single `|` is still unavailable, so a bitwise *or* is still
spelled that way, as `examples/utf8.phx` does. `lib/arith.phx` keeps `/\` and
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
such behaviour. Five forms in `programs/grammar/peg.phx` and one in
`programs/ember/asm.phx` moved to the call shape; the parentheses that existed
only to work around it are gone from both grammars.

The rule — *a pattern for something that reads as a step, a call for something
that reads as an application* — moved from a program's README into
[GRAMMAR.md](GRAMMAR.md), where somebody choosing a shape would look. The real
finding is that **choosing wrongly is silent**: both readings are legal, so
nothing at the declaration can warn.

### `programs/grammar` — `ec302d8`, 2026-08-31

A grammar toolkit, and the second program written in Phoenix. `examples/calc`
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

`lib/clike.phx` and `examples/clike.phx` land with it.

### A diagnostic for a pattern that read no parts — `f489359`, 2026-08-31

`@syntax vec { <x> }` got *needs `=>`* rather than the message about patterns,
because the better message only fired once a part had been read.

### `/\` and `\/`, and the fix for what that broke — `31d0ffc`, `f0af7c0`, 2026-08-31

A spelling change in `lib/arith.phx`. The first commit replaced `&&` in
`emberc.phx` with a blind global substitution and caught a shell command inside
a comment; the second fixed that and four documents that still spelled the new
operator the old way.

### 0.7.0 — an operator that stands for a template — `23f0cbe`, 2026-08-31

`@infix /\ 30 => left:and({ right }).` The only way to declare an operator whose
right-hand side must not always be evaluated — Solveig's `and` takes a block, and
an operator naming a *message* hands over an argument already evaluated.

**The two extension points did not compose and this is the seam.** `programs/ember`
is what found it.

### `programs/ember` — `e3f1288`, 2026-08-31

The first program written in Phoenix. A small language compiled to ARM64
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

`@use "arith.phx".` **The collision rule, which everything was queuing behind**,
and the answer was Solveig's: the later wins and the compiler says so. A span
carries its file, which is the refactor the rest needed.

### 0.3.0 — the other half of hygiene — `8101c11`, 2026-08-31

A template's *free* references are protected: the caller's local is renamed
throughout its own frame. One pass rather than a resolver, because only
parameters and `| … |` temporaries are locals in Solveig.

### `docs/solveig-notes.md` — `ef43f60`, 2026-08-31

A running log of what Phoenix finds in Solveig. Two entries at the time; a third
added later recording a prediction about Solveig that was wrong.

### 0.2.0 — forms, hygiene and expansion trails — `2af48cf`, 2026-08-31

`@syntax unless(test, body) => … .` Hygiene in the same commit rather than after
it. Expansion terminates without a counter, because a template may mention only
the forms declared above it.

### `docs/targets.md` — `55dbd72`, 2026-08-31

What Phoenix targets, and what a program written in Phoenix targets — two
unrelated questions, and only the first is a Phoenix question.

### 0.1.0 — the first commit — `5d332a2`, 2026-08-31

A tree of Phoenix's own, spans on every node, the map, a grammar declared per
module, and a build that takes nothing from Solveig.
