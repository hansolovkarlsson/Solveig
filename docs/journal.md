# Journal

*What a day of work on Proto actually consisted of, newest first.*

[CHANGELOG.md](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. [POSTMORTEM.md](POSTMORTEM.md)
records the failures. Neither of the first two holds the shape of a *day* — what
was picked up and why, what turned out to be wrong, and the decisions that
produced no code because they were decisions.

---

## 2026-09-01 — the project changed its name, and nothing else

A rename is a strange thing to give a journal entry. This one gets one because
the reason was outside the repository, and because the checking was the whole of
the work.

### It was renamed twice, and the first one was wrong in an interesting way

Hans had already moved folder and repository to **Phoenix Proto** before the
session opened, to mark the tree as a prototype restart. The session's first job
was small: the local `origin` still pointed at the old URL, redirected by GitHub
and working, and would have broken the day somebody else claimed the name.

Then the decision changed — drop the qualifier, and the name is **Proto**, plain.
The prototype framing is the honest description of the thing rather than a
modifier on a name that was leaving anyway.

**The discarded step is what made the second one clear.** The first pass had
deliberately left `phx_`, `Phx` and `.phx` alone, on the reasoning that "Proto"
marked a restart of the *project* and not a rename of what was being built — the
language was still Phoenix. That distinction was written down as a standing note
and had to be deleted the same day. It was a real reading of a real instruction
and it was wrong, which is the argument for asking rather than inferring when a
name is doing two jobs.

### The name had been promised to something else, in writing, three days earlier

`hansolovkarlsson/Solveig`, `docs/ideas.md:4451`: *Trigger: wanting a library
that Solum consumes and that is not written in Solum. Nothing has wanted one.
The name, should it happen, is Phoenix.*

Dated 2026-08-28 — three days before this project had an expander. The idea it
names is genuinely a different language: it earns its place by publishing a
**library** Solum consumes, and that entry refuses in advance *a nicer skin on
this one*. Proto emits a program's source.

So the collision was real and had been sitting in two repositories at once, with
the unbuilt idea holding the name by reservation and the shipped compiler holding
it by use. The rename ends that. **The reservation in `ideas.md` was left exactly
as it stands**, which is the point of having gone and read it before rewriting
anything — a search-and-replace across two repositories would have taken it.

### What the rename was checked against

`conventions.md` says **every text replacement asserts its match**, and three of
the recorded defects are that rule being skipped. So the suite was run green
first, to have a number rather than an impression to compare against. Afterwards
it reported the same 58, 6, 34 and 10 checks over the same ten examples and
programs, with no new warnings.

Two checks were worth more than the suite, and neither is a test:

**The diff is 1,435 insertions against 1,435 deletions.** A pure respelling
cannot be any other shape. A replacement that swallowed a line would show up
here and nowhere in the tests, because the tests only run what still compiles.

**The ambiguous matches were looked for before the `sed` ran, not after.** Every
`.phx` in the tree turned out to be a file extension; there was no bare `PHX`;
and the only odd identifier among the hundred and thirty-six was `has_phx` in
`default_output_path`, which compares `length - 4` against `".phx"`. `.pro` is
also four characters, so that line survived **by luck rather than by design** —
worth writing down, because `.proto` would have broken it silently and only the
examples would have caught it.

### One thing it cost

`git log --follow` no longer walks `lex.h` past today on its own. That header is
dense enough in identifiers that respelling them all dropped it under git's 50%
similarity threshold, so it records as a delete and a create where the other
thirty-five moves record as renames. The history is not gone —
`git log --follow --find-renames=30%` walks it back through 0.4.0 to the first
commit — but the default is now wrong for one file in thirty-six.

### A stale number, found and then fixed

**ROADMAP.md said `@language` was inert "eight versions in".** The changelog has
nine, 0.1.0 through 0.9.0: the sentence was written at 0.8.0 and 0.9.0 landed
under it without disturbing it. It is the same failure as the heading in
`edcf4a0` — a number true when written and not re-read when the thing beside it
moved — and it is the third time this document set has been caught holding one.

It went in here as *found and not fixed*, on the reasoning that the day's job
was a rename and this is a correction to an argument rather than to a spelling.
Hans asked for it the same hour, so it reads **nine** now. The identical phrase
in the 2026-08-31 entry below is deliberately untouched: eight was true on the
day that entry describes.

### The afternoon: putting what only the session knew into the documents

`conventions.md` opens by saying its contents are written down *so that neither
depends on anybody remembering them*. The rename made that concrete in a way
that had already gone wrong once without being noticed.

Standing notes had been accumulating in a per-directory store keyed by the
project's path on disk. Renaming the folder moves the key. **The previous
rename, the day before, had already orphaned three of them** — that Solveig's
README does not link here and why, that Solveig findings get written up in a
shape liftable into that project, and that `scratch/` is not to be read — and
nothing announced it. They were live rules that had quietly stopped applying to
anything, and they were only found because today's rename was about to do it
again.

All three were already in `conventions.md`, which is why nothing was actually
lost, and which is the argument for that file existing. The one that was **not**
written down anywhere is now the fourth standing agreement: *the name Phoenix
belongs to a different project*, with the consequence that costs something if
forgotten — **Solveig's `ideas.md` entry is that project's reservation and is not
to be rewritten.** A search-and-replace across two repositories would have taken
it, and would have looked like tidying.

Two defects went into [POSTMORTEM.md](POSTMORTEM.md), 13 and 14, and neither is
a defect in Proto. **13** is the stale version count: a number correct on the day
it was written, in a document that had no way to notice when the document it
described moved — a fourth kind in the *In the documents* cohort, where the
other three are edits that ran and did nothing and this one is no edit at all.
**14** is the Phoenix-Proto misreading, recorded although it cost nothing,
because what it cost *could* have been large: an inference written into a
standing note is indistinguishable from something Hans said. Both were found by
a person rather than by a check, which is a first for a pair.

[COMPLETED.md](COMPLETED.md) 13 keeps the case — the three extension schemes
that were on the table, and why full-word identifiers with a short `.pro`
extension beat being consistent.

**Adding 13 and 14 immediately produced a fourth copy of 13.** Three live
documents said *three of twelve recorded defects* are the unasserted-replacement
mistake, and the total went wrong the moment the count did. Bumping them to
fourteen would have bought a year, maybe. They say *three of the recorded
defects* now: the fraction is the point, the denominator was never load-bearing,
and `POSTMORTEM.md` is the one file allowed to know it. The identical sentence
in the 2026-08-31 entry below keeps its *twelve*, being a record of a day.

The first attempt at that removal deleted the word and left the preposition —
*three of recorded defects* — in two files. Caught by reading the result rather
than trusting the three assertions that had all correctly reported one match
each. **A replacement asserting its match proves it fired, not that it was
right**, which is defect 6 in miniature and the reason that rule has a second
half.

### What is still open

The folder is `~/Projects/Proto` now, moved at the end of the day rather than
during it: a directory cannot be moved out from under the session working inside
it.

Nothing on the roadmap moved. A rename is not progress on any of it, and the two
decisions that are Hans's — what `@language` should select or whether it should
stop existing, and whether Solveig's README links here now that the hold is met —
are open exactly as they were yesterday.

## 2026-08-31, later — a question about `|`, and the third program

The day did not end where the entry below says it did.

### It started by reading the documents rather than remembering them

The session opened with *check the documents and list tasks*, which is the same
move that caught the four-versions-stale roadmap in `5bf83af` — and it caught a
smaller version of the identical thing. `ROADMAP.md` still had a section headed
**Next — optional and repeated parts** over a body explaining that the item
*moves below whatever the next program finds*. The body had been updated when
`programs/grammar` declined the item; the heading was four words of the old plan,
left standing.

A heading outliving its section is the cheap form of the failure that document
set exists to prevent, and somebody skimming headings reads it as current. It is
`edcf4a0`, and the section is called *Waiting on a customer* now, borrowing the
vocabulary already at the foot of COMPLETED.md.

### A confusion that was worth having

The question was why `|` could not be an operator, and the proposal was a
`@token` directive: name a token, bind a spelling to it, and let `@infix` name
the token instead of the characters. It was refused, and working out *why* took
longer than the feature that came out of it.

The proposal does not reach the blocker. What stops `|` is not that `@infix`
cannot spell it — `\/` needs no help and declares fine — it is that
`{ a | b }` has two complete legal readings once `|` means something, and the
declaration is not on that line to disambiguate them. **A collision between core
syntax and declared syntax happens at the use, and no spelling of the
declaration reaches it.** The split the proposal wanted already existed:
`PROTO_TOK_OPERATOR` is spelling only and `@infix` is meaning, so the real question
was never *how does a file name a token* but *which spellings are in the
vocabulary*.

So the vocabulary grew. **`||` is two bars and not a bar** — the lexer takes it
before the bar, hands it to every dialect and lets none of them declare it, and
`{ a || b }` was already an error so nothing legal was taken. The one casualty
was `{ || … }`, an empty temporary list that emitted nothing and appeared
nowhere. That is 0.9.0, and `lib/clike.pro` stopped apologising for `\/`.

**What made it cheap was checking rather than reasoning.** Both risky cases were
compiled before the change was written. One of them turned out to be a real cost
and the other turned out to be already-illegal, and neither was obvious from
reading the parser.

### The third program, and the first one that measured anything

`programs/digest` — SHA-256 — was chosen because Solveig's own `sha256sum` wrote
the gap down in its findings: *`@expr` has no bit operators, so the one file here
that is nothing but shifts, xors and masks is the one file that cannot use the
notation at all.* Proto's ROADMAP has claimed the answer to that since 0.1.0
with nothing to point at. Same algorithm, same substrate, one file with a fixed
infix region and one that declares its own.

Five predictions, recorded first. Three right, one right and duller than hoped,
**one wrong** — and the wrong one is the whole value of the program.

The claim was *a form is a method that costs nothing at run time*, since a
template expands rather than calls. It is not true. Measured by binary search on
`--steps`, the way Solveig's own program measured its version: the template
saves **2.03 instructions per rotation** by not calling, and spends **2.00**
recomputing a `#32:sub(#17)` that nothing folds. **It gives back 98% of what it
saves.** Two predictions that were written as separate lines turned out to be one
finding with the numbers meeting in the middle.

That is now a roadmap item with a measurement attached, and deliberately not a
patch: folding a send at expand time means deciding which sends are safe to run,
and `integer:sub` is a slot a Solveig program may assign. It is the guard
question one size smaller, and it gets the same treatment.

**What the program found that nobody predicted** was three things, and the best
of them is that **a wrong precedence is silent**. `*` was declared on `+`'s rung,
`at + i * #4` became `(at + i) * #4`, it compiled, it ran, and it failed as an
array index four calls deep in generated code. A module declares its own ladder,
so there is no ladder to be wrong against. It is defect 11's shape one level
over: both readings legal, nothing at the declaration able to warn.

The other two: **a dialect ends at its domain and cannot say where** — `+`
masking to 32 bits is right for SHA-256 and a trap for the loop counter beside
it — and **0.4.0's collision rules got their first real customer**, four
collisions against `lib/control.pro`, reported exactly as designed, and the
answer was to not compose.

### What was written down rather than built

Three things went into the documents and not into the compiler. **Constant
folding in the expander** is now a roadmap entry with a measurement instead of a
patch, because folding a send means deciding which sends are safe to run.
**A dialect ends at its domain and cannot say where** is recorded with no
proposal at all, because one program is an anecdote. And the `@token` refusal is
in ROADMAP under *a dialect that changes the lexer*, where the next version of
that request will be read — with a note that the want was real and `||` is the
shape an answer should take.

`docs/solveig-notes.md` gained a third entry: **the machine counts instructions
and will not say how many.** `--steps=N` stops a run, so the count exists; a run
that finishes reports nothing, and the exact figure costs 28 executions of a
binary search. Two of the three suggested fixes are one `fprintf`.

### The number, again

Twelve defects now, and still **two found by tests**. Four have come from
writing programs in the language. The third program cost an afternoon and moved
one roadmap item from a claim to a measurement, which is what the first two did
and is the reason there will be a fourth.

## 2026-08-31 — the whole of it: nineteen commits, eight versions, and two programs that disagreed with the roadmap

The day began with a question rather than a task: *a meta-language, with
compiler directives designing the syntax of the language above it.* It ended
with 0.8.0, two real programs, three shipped dialects, and a retraction.

### What shipped

Proto 0.1.0 through 0.8.0. `lib/arith.pro`, `lib/control.pro`,
`lib/clike.pro`. `programs/ember`, a compiler from a small language to ARM64
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

The second decision was where Proto lives. Solveig existed already, and
solveig-sdl's Makefile had written the rule down about itself — *this is an
extension, so it is not part of Solveig* — so Proto went beside it rather than
inside it. That was argued from something stronger than tidiness: a front end
with privileged access to the compiler it targets proves only that Solveig's
author can write a front end for Solveig.

`solas/include/solas/compiler.h` decided the rest. `sol_compile(source, chunk)`
is single-pass with no tree, so Proto owns one, and that settles what Proto
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
select** — otherwise parsing depends on evaluation and no tool can read a `.pro`
without running it. [rules-and-logic.md](rules-and-logic.md) carries the whole
argument.

### The number worth keeping

Eleven defects, and **two were found by tests** — one of those two by a test that
was itself wrong. Three came from writing programs, three from reading something
rather than running it, and one from re-checking a claim before acting on it.
The tally is in [POSTMORTEM.md](POSTMORTEM.md), and it is the reason the next
step is more likely to be a third program than a ninth feature.
