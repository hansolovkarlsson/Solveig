# Journal

*What a day of work on Phoenix actually consisted of, newest first.*

[CHANGELOG.md](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. [POSTMORTEM.md](POSTMORTEM.md)
records the failures. Neither of the first two holds the shape of a *day* — what
was picked up and why, what turned out to be wrong, and the decisions that
produced no code because they were decisions.

---

## 2026-08-31 — the whole of it: nineteen commits, eight versions, and two programs that disagreed with the roadmap

The day began with a question rather than a task: *a meta-language, with
compiler directives designing the syntax of the language above it.* It ended
with 0.8.0, two real programs, three shipped dialects, and a retraction.

### What shipped

Phoenix 0.1.0 through 0.8.0. `lib/arith.phx`, `lib/control.phx`,
`lib/clike.phx`. `programs/ember`, a compiler from a small language to ARM64
assembly. `programs/grammar`, a grammar toolkit. Five design notes:
[targets.md](targets.md), [rules-and-logic.md](rules-and-logic.md),
[solveig-notes.md](solveig-notes.md), and this document set. 5,187 lines of C11,
103 unit checks, five examples and four programs run by `make test`.

### The first hour was spent not writing code

The opening question was answered with prior art — Racket, Terra, Forth, Rebol,
Seed7 — and one decision was pressed on before anything else: **where syntax is
allowed to change.** Three positions were laid out; the middle one, per-module
declared grammar, was chosen, and it is the reason every later decision was
cheap. A file's syntax is settled by that file's own header, so a tool can parse
it by reading it top to bottom and never has to run anything.

The second decision was where Phoenix lives. Solveig existed already, and
solveig-sdl's Makefile had written the rule down about itself — *this is an
extension, so it is not part of Solveig* — so Phoenix went beside it rather than
inside it. That was argued from something stronger than tidiness: a front end
with privileged access to the compiler it targets proves only that Solveig's
author can write a front end for Solveig.

`solas/include/solas/compiler.h` decided the rest. `sol_compile(source, chunk)`
is single-pass with no tree, so Phoenix owns one, and that settles what Phoenix
is: a second compiler that happens to target Solveig.

### Three things went into 0.1.0 that nothing used

Spans on every node, `introduced_by`, and `scope`. Two of the three were read by
nothing at all. They went in because each is impossible to add later without
touching every constructor — and the return came fast: 0.2.0's expander was
written in one sitting rather than three, and 0.4.0's *a span carries its file*
was a field rather than a rewrite.

### The collision question, and the answer that was already written

From 0.2.0 onward everything queued behind one question: what happens when two
dialects declare the same operator. Racket answers it with modules and scoped
bindings and it was worth reading how — but Solveig's `REFERENCE.md` had already
answered it for two files claiming one global. *The later wins, and the compiler
warns rather than letting it pass.* And it warns on a **claim** and not on an
**update**, which is a distinction about who could have known.

Applied to syntax that gives four cases, and 0.4.0 shipped them. **A language
should not hold two philosophies about one question**, and the hour spent
reading Solveig's reference was the cheapest hour of the day.

### The roadmap had been lying for four versions

Asked *what's next?*, the file was read rather than remembered, and it still
called the expander *next* — four versions after it shipped — and still asked the
collision question two versions after it was answered. Three edits between 0.2.0
and 0.5.0 had matched nothing and reported success; em dashes against two
hyphens.

Fixed in `5bf83af`, which says so in its own subject line. The method changed
with it: every replacement asserts its match now, and it caught two more the
same day.

### Then the programs, which is where the day turned

Six versions in, nothing had been written in the language. `lib/text.sol` over
in Solveig states the rule — *one customer, satisfied in six lines, is not a
reason to grow a surface* — and its converse is what the project had been
ignoring.

`programs/ember` was written with five predictions recorded first. Three right,
one did not bite, **one wrong**: Solveig was predicted to bite first, most likely
3.1, and did not bite at all. Two things nobody predicted, and one of them —
six hand-written `(a == b):and({ … })` because `&&` could not be declared —
became 0.7.0 the same afternoon. That is the whole argument for `programs/` in
one example: the feature was found by a program, not by thinking about features.

`programs/grammar` was written second, and deliberately: it is the program most
likely to want repetition, which the roadmap had wanted for four versions with
nobody asking. It wants repetition, and **a repeated pattern part would not have
helped** — a grammar cannot be written as forms at all, so the repetition wanted
is one level down. The item was declined a second time, with a reason instead of
a shrug. 3.1 bit this time, exactly as predicted, and cost four lines because it
was predicted.

### And the day ended by taking something back

Both programs had reported that a form's trailing hole swallows what follows.
Asked *what's next?* again, the plan was to build the fix — and checking the
claim first showed there was nothing to fix. Both had declared an application as
a pattern. A call ends at its closing parenthesis; `ember`'s own README states
the rule, and `grammar` was written afterwards by the author of that sentence
and broke it in five forms.

The retraction is `d90ea08`. What is real is smaller and better: **choosing the
shape wrongly is silent**, both readings being legal. The rule moved from a
program's note into `GRAMMAR.md`, where somebody choosing a shape would look —
which is the most likely reason it was not followed.

### What was decided and not built

`@language` still records a name and acts on nothing, eight versions in. It is
the only inert directive and it should either select something — a reader, or an
emitter, as [targets.md](targets.md) argues — or stop existing. That is a
decision, not a build.

A guard on a rule was designed and not built: `solum/embed.h` is the door, and
the rule to fix before writing any of it is that **a guard validates, it does not
select** — otherwise parsing depends on evaluation and no tool can read a `.phx`
without running it. [rules-and-logic.md](rules-and-logic.md) carries the whole
argument.

### The number worth keeping

Eleven defects, and **two were found by tests** — one of those two by a test that
was itself wrong. Three came from writing programs, three from reading something
rather than running it, and one from re-checking a claim before acting on it.
The tally is in [POSTMORTEM.md](POSTMORTEM.md), and it is the reason the next
step is more likely to be a third program than a ninth feature.
