# Journal

*What a day of work on Proto actually consisted of, newest first.*

[CHANGELOG.md](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. [POSTMORTEM.md](POSTMORTEM.md)
records the failures. Neither of the first two holds the shape of a *day* — what
was picked up and why, what turned out to be wrong, and the decisions that
produced no code because they were decisions.

---

## 2026-09-13: a program written to find a boundary, and the boundary was not there

**Hans asked what was outstanding, then for a program to write, then for the
bignum**, with one instruction beside it: pay attention to whether Solveig
wants a maths extension in the shape of `net`, and whether Python's `math`
library is the measure of what *advanced maths* would mean. The program was
chosen because every one of the six before it is one code module and one
dialect file, and the roadmap's only entry with no proposal, *a dialect ends
at its domain and cannot say where*, has the design's own answer sitting
untested in `examples/vectors.pro`: a second file may declare `+` to mean
something else, and neither file has to know.

### The predictions went in first, with bc's answers beside them

Six predictions, committed with `bignum.expected` before a line of code, the
expected file produced by `bc` so that the program could not be its own
oracle. The sharpest was the second: that `lib/arith.pro` would serve the
driver unchanged for integers and bignums alike, because `+` names a message
and a message dispatches. The one that was going to be wrong was the sixth,
which put a number on the speed.

### The program ran right the first time, and the two modules did not disagree

`limbs.pro` came out at five lines: the base, its width, `digit(t)` and
`carry(t)`, over `lib/control.pro` unchanged. The library is 126 lines, the
driver 27, and the first run matched `bc` on every line. Prediction 2 reached
further than it was written: inside the library, `ai * b:at(j)` is an integer
product and `result * b` two methods down is a bignum one, under the same
declaration in the same file. The two modules were built to disagree about
`+` and had nothing to disagree about, and that is the finding. `digest` and
`ledger` invented a `+` and a `*` because their values are Solveig's own
integers wearing a rule, and a rule on an integer has nowhere to live but a
template on the spelling, which cannot look at its receiver and so reaches
the loop counter beside the domain. A bignum is an object, so the rule lives
in `big:add` and the header has nothing to add. **A dialect traps its
scaffolding exactly when its domain's values are the substrate's own.** The
roadmap entry has that as its proposal now, and it is a question to ask before
writing a domain dialect rather than a feature to build.

### What was measured

By binary search on `--steps`: 11,291,573 instructions for `1000!` and
444,565 for one product of two 100-limb numbers, which is 44 per limb product.
The disassembly says fifteen of the 44 are sends, four on the array and eleven
arithmetic, and four of the eleven are `i + j - #1` computed twice. Prediction
6 had said the cost was the array access; the index arithmetic costs the same.
By wall clock, `1000!` is 40 ms at `-O2`, the build `performance.md`
measures, and 190 ms at the default `-g` build; CPython's `int` takes 0.24 ms.
That is 170×, and the prediction said two orders of magnitude. The `-O2`
measurement meant a clean rebuild of the parent and a second one to put `-g`
back, which is what the memory about benchmarks says to do and why.

**So the answer to Hans's question is in two halves, and both are in the
README.** A large-number library is a library: correct with nothing missing
from the machine, and `@include` reaches it. The case for a C extension is
the ratio and nothing else, and no program has waited 40 ms for it. Python's
`math` is a different question from a bignum, and `solveig-notes.md` 5 sorts
its contents into what would be primitives by 3.14's own argument and what
would be `lib/math.sol`; nothing in it was wanted by this program.

### What the exercise found that nobody predicted

A misspelled message in a copy of the library reported `[bignum.sol:27]` over
`[calc.sol:16]`, one frame per generated file, and each map took its line
back: 27 to `bignum.pro:55`, 16 to `calc.pro:51`. Prediction 5 held and Proto
was not changed. But 27 is also lines 54, 56 and 57, because a `while` body is
emitted on one generated line and a run-time trace carries a line and no
column, so the map's column, which `tests/test_map.c` checks harder than
anything else here, had nothing to apply itself to. Sixteen of the library's
103 generated lines are spans of the module's own lines, every one a loop body
or an `if` arm. A four-line span is a recovery and not the exact one the map
was built for. Two fixes, neither built: Proto keeping a line break inside an
expanded hole, or Solveig's trace carrying the column its compile errors
already have. A row under *Rough edges*, checked on the day, and
`solveig-notes.md` 4.

`n(#2)` had to be a form, because `f(x)` on a name is `x:f` in Solveig. And
nothing in Solveig bit, for the third program in a row.

### What moved in the records

Seven programs where there were six, everywhere a running count is kept;
`does-it-pay.md` gained a row and a section; the roadmap's folding entry a
third customer declining, its boundary entry a proposal, and its rough-edges
table a fifth row. The parent's journal has a paragraph pointing here. No
version: nothing in the compiler changed.

---

## 2026-09-12, later: the second decision of 0.1.0, reversed

**Proto lives in Solveig's tree now**, as `proto/`, with this history intact
under it. The 0.1.0 entry below records the decision this reverses: solveig-sdl
had written the rule about itself, *an extension is not part of Solveig*, and
Proto went beside Solveig rather than inside it, argued from something stronger
than tidiness. A front end with privileged access to the compiler it targets
proves only that Solveig's author can write a front end for Solveig.

### What was argued, and what decided it

The argument for staying out was made again today, from this project's own
Makefile and from Solveig's own habits, and it was recommended. Hans's answer
was the other half of the same fact: Proto emits Solveig and nothing else, so
every change to the substrate is a change Proto has to follow, and two
repositories meant discovering the breakage one suite run late. A sibling
checkout gives one-way sync, this suite against `../Solveig`, and nothing the
other way. One tree makes the follow-up one commit and one green run. That is
a judgement about the cost of keeping up, and it is his to make.

### What the boundary still is

Nothing about it moved. This Makefile builds without Solveig, includes no
Solveig header, links no Solveig archive, and reaches the parent only through
`../bin/solas` and `../bin/solvm` from the targets that hand them a file. What
went is the minimum-version check in `make check`: the parent is the version
this speaks to by construction, and `PROTO_SOLVEIG_MINIMUM` stays in
`common.h` as the record of the language level, reported by `--version`, for
anybody building against a Solveig that is not the parent. `SOLVEIG` defaults
to `..`. The parent's `make` builds `bin/proto`, its `make test` runs this
suite after its own, and its `make install` installs `proto` and `lib/*.pro`.

The records stay here as Proto's own: this journal, [CHANGELOG.md](CHANGELOG.md)
at 0.17.0, [COMPLETED.md](COMPLETED.md), [ROADMAP.md](ROADMAP.md) and
[POSTMORTEM.md](POSTMORTEM.md), which Solveig's `docs/` refuses for itself and
does not refuse for this directory. The version number stays Proto's until
there is a reason to fold it in. The standup is the parent's. The repository at
github.com/hansolovkarlsson/Proto is archived with a pointer to `Solveig/proto`.

---

## 2026-09-12: an audit after eight days, and a closeout that had to be reviewed

**Nothing had landed since 2026-09-04.** The day opened on a standup eight days
old that was still exactly true: tree clean, level with origin, 0.17.0. Two
sweeps were run against it, one paragraph of the README was rewritten, the
closeout was written, and a review of the closeout sent most of it back.

### The setup sweep found nothing to add

`/project-setup` in its ensure mode matched the records by role and found all
five filled, each opening with its own note, the standup in `scratch/` and
ignored, the licence and the three Makefile targets in place. It wrote nothing.
The one divergence it named and left: this journal is a single file where the
newer convention is a directory of dated files. Seven tracked files mention
`journal.md`, six of them with a link, and this file's own note already settles
the ordering question the directory shape exists to avoid. Not worth doing
unless Hans wants it.

### The audit found the day's work recorded, and one sentence left behind

The segment was the twelve commits of 2026-09-04, since the previous closeout
drew that line and nothing follows it: seven pieces of work by grouping. Six
have entries in [CHANGELOG.md](CHANGELOG.md); the seventh, `CLAUDE.md` arriving
in the repository and being corrected, has none, and the changelog's note leaves
that kind of thing to this file, where 2026-09-04's entry has it. The one
roadmap item that closed is [COMPLETED.md](COMPLETED.md) 17, and the defect
shipped as 0.17.0 is [POSTMORTEM.md](POSTMORTEM.md) 24. The code diff read
clean: identity and path separated everywhere they were compared, both faces of
the defect tested, one exit from `proto_source_read`. Suite **63, 6, 69 and
13**, 151, no skips; `make sanitize` the same. Every open item in the standup
was already on the roadmap or in `solveig-notes.md`.

Three claims were off. `ROADMAP.md`'s map row says *see below* about a
paragraph above it, and stands. `POSTMORTEM.md`'s scope said *four cohorts*
over five bullets since at least 2026-09-03; that paragraph was being rewritten
for entry 28 anyway and now says five. The third is the README.

### The README said two readers, and the sweep that should have caught it knew a different word

`README.md`'s *Where to start* opened: *Two readers who had never seen this
language were put in front of it, and neither opened this page.* Written at
10:42 on 2026-09-04 and true of runs 1 and 2. At 11:33 the third reader was
recorded opening the page first, reading *Not here*, and stopping, and the same
commit did what [conventions.md](conventions.md) says to do: it grepped for the
claim rather than opening documents, found *two strangers* in four places,
including the README's own table of documents at line 721, and corrected all
four. Then `d01ad10` moved them to four. Line 37 spelled the same count *Two
readers* and neither sweep reached it, nor did the five overtaken claims
corrected at 12:01.

That is POSTMORTEM 13's class, a count that is a fact about another document,
and what it adds is narrow: the sweep was run, on the right day, for the right
claim, and the claim had two nouns. **A grep for a phrase finds the phrase.**
The count was not corrected until somebody looked for the thing counted rather
than for one spelling of it, which an audit did eight days later while checking
the section's file references for a different reason.

The sentence now names the first two readers as they were, the third with the
date, and gives no total: a total is the count that went stale, and
`second-reader.md` declines to put run 4 on the reader axis at all. POSTMORTEM
28.

### The closeout got the geometry wrong, and a review caught it before the commit

The first draft of today's records said the count had been bumped **six lines
below the sentence**, in the table under *Where to start*, and built 28's cause
on that adjacency: the same shape as 25, a sentence outlived by something
within sight of it, and therefore the *second day* the 2026-09-04 standup had
asked for before promoting its last-paragraph rule to a standing agreement.
The hunk was at line 721. The table six lines below the sentence lists three
files and carries no count. Every part of the argument built on adjacency was
wrong, and so was the filing: 25 defines itself against exactly this case, a
claim about *another* document, and 13 already names the class and its defence.

A code review of the four uncommitted files found that, and eleven smaller
things beside it: a claim that no reader had seen the page since, when run 4
was handed the README after the sentence went stale; *went to those files*
about a reader the record says was sent to two of them; *every one is in
CHANGELOG.md* about seven pieces of work of which six are; *one week later* in
one record against *eight days* in two; an em dash inherited into an edited
line; a defect described in the present tense against this repository's own
rule. The four files were restored from `HEAD` and rewritten.

**What the day actually establishes is smaller than what the draft claimed.**
The standup's proposed rule, read a document's last paragraph against its
middle, has one instance behind it still, and this is not a second. What this
is a second instance of is 19's observation that a defence applied is not a
defence that reached, and the narrowing it offers is the one in 28: grep for
the thing counted under every noun the documents give it, not for the phrase
that was just changed. Whether that goes into `conventions.md` is Hans's call.
The other thing the day establishes is about this record: the draft stated a
fact about a diff from a glance at its hunk header, which is the documents
cohort's failure one level up, and the review that caught it was the same
re-derivation 13 prescribes, applied to the closeout's own output.

## 2026-09-04, later — two more readers, and both of them argued with the morning

**The morning's closeout said the day was work the documents had already
written down.** The afternoon was the opposite: two experiments whose results
were not in any document, and both of them took something back.

### The third reader was aimed at a diagnostic and hit an example

0.16.0 shipped in the morning **on an argument and no measurement** — the
hole-kind error prescribes `wrap it in braces` now, and prediction 9, that the
message says nothing about what to do, had been untested twice because nobody
reached it. Run 3 was designed to reach it by a route the dialect's eleven-line
essay does not cover: **a single-statement body with no braces**, which is what
a C programmer types without thinking.

**The reader braced it.** Correct output first compile-and-run, no diagnostic,
and the reason is the prediction written down as a hedge — *if the reader
brackets everything anyway it will be because the example braces every body.*
`examples/clike.pro` braces every body, the reader took their syntax *by direct
analogy* from it, and the hedge is the only prediction of the six that paid.

### And it falsified a sentence written the evening before

**The `print`-is-a-repr trap fired on a reader who had read the warning about
it.** They quoted the comment back accurately and wrote `:print` anyway. Run 2
had earned this the previous evening:

> A limitation explained where it is declared is not a limitation a reader pays
> for.

**It was generalised from one reader and one limitation into four documents the
same evening**, in a repository whose loudest standing rule is that *one
customer is not enough* — a bar this project applies to features and had never
thought to apply to a conclusion. POSTMORTEM 26.

What survives is narrower and better. `else if` is a **refusal**: a warning read
beforehand removes an option the reader was about to take. `:print` is a
**silence**: it compiles, runs, and looks right.

> **A warning prevents a failure you would have chosen. It does not prevent one
> you would have walked into believing you had succeeded.**

Which is [does-it-pay.md](does-it-pay.md)'s own silence category arriving from
the documentation side, and it took a third reader because the second produced
a sentence good enough to stop looking.

### The fourth run changed who the reader was, and refused the easy version

Three runs had failed to reach a diagnostic. **The reliable way to force one is
to hand a reader `lib/clike.pro` with its warning removed, and that was refused
twice** — it would measure a file written for the measurement.

So the *role* changed instead, to a customer 0.16.0 names in its own
justification and no run had contained: **an author declaring a form**, rather
than a user of somebody else's dialect. Nothing in the published surface models
it — `examples/forms.pro` declares four forms and types no hole at all.

**They typed `<b: block>`, copying `lib/control.pro`'s `repeat`, and then braced
every use anyway** — the model this time being `examples/dialect.pro`'s
`repeat #3 times { "tick":display }`, a one-statement body wearing braces. Run
3's finding one level up.

### Four runs, and no reader has ever seen a Proto diagnostic

**Two of the four tasks were built specifically to produce one.** Prediction 21
is retired unmeasured rather than asked a fifth time, and 0.16.0 stays justified
by argument — **which is now a settled fact about it rather than a pending
measurement.**

**What did happen is the failure this project says it exists to prevent.**
`proto` exited 0, `solas` exited 0, and `solvm` reported `undefined name
'total'` at `banner.sol:8` — a line in the *generated* file, after seven lines
of correct output. **No map had been written**, the map being opt-in. With one
the recovery is exact: generated `8:5` is source `10:5`.

The reader got out on **Solveig's** error text alone.

> **A declared grammar's cost to a reader is paid in the substrate, and so is
> the rescue.** Four readers have been served by Solveig's documentation and
> Solveig's diagnostics at every point where Proto's own would have had to work.

### And the experiment was part of what it measured

**POSTMORTEM 27, and it is mine.** The prompt handed both readers a
three-command toolchain that omits `--map`, where `README.md`'s own quickstart
includes it. The write-up was one edit from reading a missing map as the
reader's choice; it was the experimenter's.

> **What the experimenter hands over is part of the surface under test.**

The cost of the minimal invocation is measured. A reader's likelihood of
choosing it is not, and *the default should probably change* is left exactly as
unsettled as it was. The method cohort had one entry and now has two.

### What the afternoon says about the ritual

**Both experiments were designed to measure a thing and neither did.** Run 3
was aimed at a diagnostic and found a rule that had been over-generalised; run 4
was aimed at the same diagnostic and found the characteristic failure arriving
from the substrate with a mechanism switched off.

**Both findings came from predictions written down before the run** — one from
the hedge, one from the confound noticed while scoring. Neither was the point of
its experiment.

> **An experiment that answers its own question tells you what you already
> suspected. The ones here have paid, four times out of four, in what they
> found on the way.**

## 2026-09-04 — the records were right and two of them were read wrongly

**This entry was written at the closeout and ended there.** It was true when it
was written and describes **the first half of the day**. Four more commits
followed, two of them reader runs, and one of those contradicted a sentence
written that morning — *2026-09-04, later* is above, and the numbers here are
corrected in place with the earlier reading kept. The same treatment 2026-09-03
got, for the same reason, on the entry that learned it.

**Nothing was designed today.** Four commits, two versions, and every one of
them was work some document had already written down and nobody had done. That
is the day's shape and it is worth naming, because it is what a good set of
records is *for* and it is also how the day's two mistakes happened.

### It opened cold, and the catch-up was wrong

There was no `scratch/daily-standup.md`. 2026-09-03 had been closed out three
times and the standup was not among what survived, so the way in was `git log`
and `docs/` — which is what [CLAUDE.md](../CLAUDE.md) says to do, and it worked
for everything except one item.

**The catch-up reported the substrate documentation gap as the next thing to
fix. It had been fixed and measured the previous afternoon.**
[second-reader.md](second-reader.md)'s run 2 put the one-line `REFERENCE.md`
pointer in front of a reader and got **zero** `does not understand` probes
against run 1's six. That is in the middle of the file. Its **last sentence**
still called the gap *the thing to fix first*, undated and present tense, and
the last sentence is what a reader carries away.

POSTMORTEM 25, and the cohort it joins is the one about documents rather than
the one about the compiler. It is 19, 20 and 21's failure arriving from a new
direction: those are a claim about *another* document going stale, and this is a
claim about **the same document**, overtaken by a section appended below it.
Three sweeps on 2026-09-03 grepped `docs/` for stale claims and none found this,
because **a sweep looks for a claim it can check against something else, and
this one is only wrong against a later paragraph of itself.**

### `CLAUDE.md`, and the line in it that described a document wrongly

The file had been written and left untracked. Committing it turned up its own
error: it glossed `POSTMORTEM.md` as *predictions scored*, which is not what
that document is — it is every defect found, what caused it, and what found it,
and predictions are scored in the journal and in `does-it-pay.md`. The wrong
gloss sat four lines above the sentence saying each document's own italic note
outranks anything said about it from outside.

### The README was fixed for the readers who never opened it

Two strangers used this language on 2026-09-03 and **neither opened the front
page**. That was recorded in [second-reader.md](second-reader.md), again in
[does-it-pay.md](does-it-pay.md), and a third time in yesterday's journal entry
noting it was *not on the roadmap and probably should be*.

**A roadmap entry was the wrong shape for it**: the fix is twenty-five lines and
there was nothing to decide. `README.md` opens with *Where to start* now,
naming the dialect file, the example and `REFERENCE.md`, then Solveig's
reference for the library — and it says **not here** in its first two words,
because a signpost that will not say what it is not is the thing that was
already wrong.

**Two claims in that new table were wrong on the first draft and were caught by
checking them.** `examples/clike.pro` was called the shortest complete example
and is not — `dialect.pro` is 41 lines to its 45. And `lib/clike.pro` was
credited with explaining each limitation at its declaration, which undersells
one half and oversells the other: it carries a header note listing what C has
that it cannot, *and* the eleven lines at the `else` form. Both were rewritten
to what the files actually are.

### 0.16.0 — a diagnostic that prescribes, on an argument and not a measurement

Both second-reader runs named *a diagnostic that points correctly and prescribes
nothing* as the next thing to fix. **Neither reached it.** Run 1's task had no
cascade; run 2's reader was warned off by `lib/clike.pro`'s eleven lines and
said so unprompted.

So the evidence this entry was waiting for never arrived, and the work was done
anyway. **That is stated in the commit and in [COMPLETED.md](COMPLETED.md) 17
rather than dressed up**, because the argument is a generalisation and not a
measurement:

> A limitation explained where it is declared is not a limitation a reader pays
> for. It is one its author paid for once — **once per dialect.**

`lib/clike.pro`'s author paid it. The next dialect with a `block` hole has an
author who has not, and a diagnostic is the only part of this system that
reaches somebody who has read nothing.

**The restraint is the design.** Only `block` gets a prescription, because
braces make a block out of anything and the advice is therefore right every
time; nothing makes a `place` out of `#1`, and a note that prescribed there
would be advice that fails, which is how a reader learns to skip the notes. A
check holds that half.

**And the placement turned out to be part of the fix.** Put third, the note
printed the reader's own line a third time — `diag.c` drops a repeated caret
only for a note about the span the line above underlined. Put second, between
the error and the declaration note, it prints once and the fix sits beside the
problem.

**The advice was run rather than assumed**: `else { if (…) { … } else { … } }`
gave `low`, `mid` and `high` for `n` of 1, 5 and 10 — checked against the
`{ { … } }` trap the dialect warns about, which fails silently and would have
made the prescription worse than none.

### 0.17.0 — the rough edge that was not cosmetic

`README.md`'s known-gaps table had carried this for four days:

> A `@use` path is not normalised. `examples/../lib/control.pro` is what a
> diagnostic shows, and two spellings of one file are two files.

**The first clause is about display. The second is about identity, and nobody
had asked what else compared those strings.** Both `@use` rules did:

- **A diamond spelled two ways warned that a file collided with itself** — one
  path named as the offender, the same file's other spelling named as where it
  was declared. Correct code, false warning, and what it cost is confidence in
  the collision warnings, which are the 0.4.0 feature the composition story
  rests on.
- **A cycle spelled two ways was not reported as a cycle.** Every hop appends
  another `./`, so no path repeats and the check never fires. What stopped it
  was the 64-deep recursion limit: the wrong diagnostic under sixty-four lines
  of `././././` trail.

**The limit is what stood between this and a hang, and that is why the defect
was quiet.** A guard that turns an infinite loop into a bad error message makes
a bug survivable and therefore invisible. It held exactly as designed and it
hid the thing it was protecting against.

A `ProtoSource` carries `identity` beside `path` now — `realpath`, falling back
to a copy where there is nothing on disk to resolve. **Display is unchanged and
deliberately so**: the cycle error still names `./././a.pro`, because that is
what the file says and where somebody can look. Only the two comparisons moved.

The fix also produced a leak in the same hour it was written — `fopen`'s failure
path had its own copy of the cleanup and did not gain the new field when the
struct did. `proto_source_read` has one exit now, which is the argument against
remembering.

### What the two mistakes have in common

One document said a fixed thing was open; another said an open thing was
cosmetic. **Both were read as summaries and both were right about the facts and
wrong about the state.** Checking each against what it described took minutes
and neither had been checked in four days of sweeps.

> **A sweep verifies that a document agrees with the tree. Neither of today's
> two disagreed with anything — they disagreed with what the reader would do
> next.**

Which is the one thing this day suggests changing about the ritual, and it is
not written into [conventions.md](conventions.md) yet because one day is an
anecdote and this project's own rule is that one customer is not enough.

### The numbers, written last

**This section read *four commits, and two versions* when it was written**, and
said that the closeout's own records were uncommitted and that a fifth commit
was somebody else's to make. That was accurate. **It is ten now**, and the
afternoon is the entry above.

**Ten commits, two versions — 0.16.0 and 0.17.0 — and four reader runs' worth
of documents.** `fe94694..d01ad10`, all pushed. The suite went from **61, 6, 69
and 11** — 147 — to **63, 6, 69 and 13** — 151, and has not moved since 0.17.0
landed before lunch: **the afternoon produced four commits and not one line of
compiler code.**

**Four defects, and none from a test.** Two before the closeout — a compiler
one found by checking how a rough edge was filed, a documents one found by a
reader acting on a document and being contradicted by the rest of it. Two after
— a rule generalised from one reader, and a method failure that is the
experiment's own. **Five days running with nothing found by the suite.**

The suite went from **61, 6, 69 and 11** — 147 — to **63, 6, 69 and 13** — 151.
Four new checks, two per version, and all four are negative controls that were
watched failing against the unfixed compiler with `make clean` between the
builds. 0.17.0 was additionally run clean under `make sanitize`.

**Two defects, and neither came from a test.** One in the compiler, found by
checking how a rough edge had been filed; one in the documents, found by a
reader acting on one and being contradicted by the rest of it. **That is four
days running with nothing found by the suite**, which is now long enough to be
the pattern rather than a run of luck — and both of today's have new rows in the
tally, which is the fourth day in a row that has been true too.



## 2026-09-03 — an empty day that did not stay empty: a link, a defect, and the second reader

**This entry was written at midday and said the day had no work in it.** That
was true when it was written and false four hours later. It is corrected in
place rather than rewritten, because the first half is a finding and the second
half is what happened next — and because a record that quietly stops saying
what it said teaches nothing.

### The morning: a day with no work in it, swept anyway

**The shortest section here, and it was not empty**, which was the finding.

The day opened with the previous one already closed and pushed. `git status`
clean, no branches, no worktrees, no stashes, nothing touched outside git since
19:40 the night before. Asked to close out the day, the honest answer was
**there is nothing to close out** — writing a journal entry for a day with no
commits in it would be inventing one.

That answer was given, and then overruled, and **the sweep found three defects.**

### What it found

**One of them had been false since the commit that wrote it.** POSTMORTEM 20's
write-up says, of the entry below it:

> The entry below **reports** the suite as "58, 6, 60 and 11" …

and the same commit changed that entry to read 69. The sentence describing the
defect was falsified by the fix it was describing, in the same diff.

**Two more were in the `programs/prose` CHANGELOG entry**, which still read
*`lib/arith.pro` has no `<=`* and *one is still not enough*. Both were overtaken
by `programs/basic` the same evening, by a commit that had no reason to open
that entry and did not.

### Which is a different failure from 19's and 20's

Those two are about a claim going stale **while nobody looks**. This is the
opposite: the claim went stale **because somebody looked**, and fixed the thing
it described.

> **Write what a document *read*, not what it *reports*.** A record of a defect
> is history the moment the defect is fixed, and past tense survives the fix.

A present-tense sentence about another document's current state has a lifetime
of one edit, and the edit that ends it is usually in the same commit — because
describing a defect and correcting it are one piece of work. Three of the day's
three are that, one of them inside the entry about documents going stale.

### And the ritual is not about the day's work

**A sweep audits the documents, not the day.** Nothing was written on
2026-09-03 and three things were wrong in `docs/` anyway, because they had been
wrong since the night before and a clean `git status` says nothing about that.

So *there is nothing to close out* was the wrong answer, and it was wrong for a
reason worth writing down rather than a slip: it treated the closeout as a
report on work done, when what it actually is is an audit of what the documents
claim. **An empty day is not a reason to skip one**, and
[conventions.md](conventions.md) says so now.

The grep agreement earned last night was what found two of the three, on its
first use in anger. The third came from re-reading the entry that agreement was
written into.

### Then Solveig's README began linking Proto

The hold was set on 2026-08-31 and expired the same day the expander landed;
`conventions.md` had carried it since as **Hans's decision, not one to make
unasked**. It was made, six programs in.

**Where it went is the part worth keeping.** Not into the table with
`solveig-gtk` and `solveig-sdl` — those live outside Solveig so that *no
dependencies beyond a C11 compiler and `make`* stays true, and **Proto lives
outside so that it cannot reach in.** Same shelf, opposite reasons, and folding
it into a table captioned *both are built against `extend.h`* would have said
the wrong thing about what it is. It gets a paragraph of its own saying it takes
no header, archive or symbol, and that the coupling is a file format and a
command line.

The three-line invocation in that paragraph was run before it was written.

### Which made the second reader real, so the question was designed

[does-it-pay.md](does-it-pay.md) has ended on the same sentence since it was
written: what no program had tried is a dialect used by somebody who did not
write it. **A stranger arriving from Solveig's front page stopped being
hypothetical the moment the link landed**, so the design and six predictions
went in first, per the rule.

### And checking a prediction instead of asserting it found a defect

The fourth prediction was going to be *the else-if diagnostic will not name the
fix*. Checking it found that it did not name the **file**:

```
/…/lib/clike.pro:72:43: error: 'if' wants a block here, and this is a send
proto: chain.pro -- 1 error
```

A hole-kind failure whose argument is **itself a form use** reported the
position of the template it expanded into. No trail, and the reader's own file
named only in the summary count. **There was no line to go back to** — the one
failure `README.md`'s first commit names as characteristic of a per-module
grammar, and the thing the map and the diagnostics exist to stand in front of.
0.15.0, and POSTMORTEM 22.

**Nine versions missed it because a form in a hole is the case a dialect's users
hit and its author does not.** The author knows the chain wants braces and never
writes the version that does not. The check that was already there could not
have caught it either: asserting that something is *rejected* says nothing about
where the caret went.

### The negative control passed, and it should not have

**The worst half-hour of the day.** With the fix written, the new checks were run
against the unfixed compiler — the discipline `tests/test_expand.c` states in
its own opening comment. It reported **60 checks, 0 failed**, and the conclusion
written down was that the checks did not catch the bug.

`git stash` restores a file with its **original timestamp**, older than the
object built from it, so `make` rebuilt nothing and the control ran the fixed
compiler. **The failure mode of a stale negative control is that it passes**,
which is the one that gets believed.

Rerun with `make clean` between the builds it failed at once — and watching it
fail showed the first attempt tested a *milder* shape than the reported defect,
so a third check was added for a template that **builds** the node. POSTMORTEM
23, and `make clean between the two builds` is a standing agreement now.

### The measurement, and what it turned inside out

A reader with no knowledge of the language, four published files in a directory
of their own, and a task with a nested loop and a counter that
`examples/clike.pro` has neither of.

**Correct output on the first compile-and-run**, the syntax taken from one
example and one table, the README never opened in full. **And they declared an
operator of their own in that first program** — `@infix ++ 55 concat.`, at a
precedence chosen to sit under `+`, mixed into a module that also `@use`s a
dialect. The claim this whole project exists to test, taken up correctly and
unasked by the first stranger to touch it.

**Every cost was on the other side of the compiler**, and that is what turns the
cost table inside out. Six programs found four silences and **all four are things
a dialect does.** A reader met none of them. They met a `print` that is a repr
and an example that taught it wrongly, and a published surface that documents
how operators become sends and never says what sends exist.

> **A declared grammar's cost to its author is the dialect. Its cost to a reader
> is the substrate.** Six programs measured the first and could not have found
> the second, because an author already knows what sends exist.

**Two predictions were wrong and stay in.** The bare-integer silence never
happened — `#` came out of the example in the first minute, so the prediction
described a reader who skips an example that was provided. And the `else if`
chain was never written, the task not needing one, **which is a fault in the
design rather than a result.**

**The caveat earned its place.** The design said in advance that a no-context
session still knows Smalltalk, so anything untraceable to a document is an
assist. `concat` and `asString` were guessed from zero documentation. Correcting
for it makes the finding **worse** than the run makes it look, which is what
writing the caveat before the run was for.

### And then the same reader again, sent at the one rough edge

Run 1 had left its fourth prediction untested — the task needed no cascade — so
a second run was designed to force it: three mutually exclusive ranges, which in
C is `else if`. Predictions 7 to 11 went in first.

**The reader never wrote the chain.** Nested braces on the first attempt,
correct output on the first compile-and-run, **no diagnostic emitted at any
stage**, and the reason volunteered without being asked: *I would have tried
`else if` first if the dialect file had not spent a paragraph on it.*

It has. `lib/clike.pro` spends eleven lines at the `else` form's own
declaration on why a chain cannot chain — the `{ { … } }` that answers instead
of running, the `#54` where `#40` was right, and the spelling of the fix.

> **A limitation explained where it is declared is not a limitation a reader
> pays for. It is one its author paid for once.**

**So prediction 9 is untested for the second time, and now for a better
reason.** The first run missed it because the task had no cascade; the second
missed it because the documentation prevented the failure. The diagnostic's
unhelpfulness is real and stays unmeasured, and two runs agree on why: **nobody
reaches it.**

**And the alternation entry has been answered by a customer declining to need
it** — the fourth time on that page, and the first by a customer being *told* in
advance rather than working it out.

### The run was also a control, and both of the morning's fixes held

Not designed as one and it is the cleaner result. Run 1 found two things, each
got one line, and neither touched the compiler:

| | run 1 | run 2 |
| --- | --- | --- |
| `REFERENCE.md` names the message set as Solveig's | six probes against `does not understand` | **zero**, and cited as *the decisive signpost* |
| the example shows what `:print` really prints | cost a cycle | caught — *the one that would have bitten me* |

**Two sentences removed every cost the first reader met**, which is the sharpest
thing said all day about where a declared grammar's cost actually lives.

### Neither reader opened the README

One grepped it after the fact. One never opened it and said so unprompted:
*worth knowing if you were expecting the front page to be load-bearing.*

**Two for two**, and the entry point in practice is the dialect file, the
example and the reference. Six programs' worth of argument sits on a page the
only two strangers to use this language did not read — and Solveig's front page
now points at it. That is not on the roadmap and probably should be.

### The numbers, written last

**This section read *one commit, this one, and no version* at midday, and *six
commits* at teatime.** It is wrong for the second time in one day, in the entry
whose own lesson is that this happens, four hours after
[conventions.md](conventions.md) gained the sentence **write the narrative to
last and the numbers to be replaced.** The agreement was vindicated faster than
anything else written here.

**Nine commits, this one included** — a number cannot count itself and has to be
told to — **and one version, 0.15.0.** `c61680a..69a2878` went to `origin/main`
in the morning; Solveig took `bf07077`, and nothing else there is this session's.
The suite went from **58, 6, 69 and 11** to **61, 6, 69 and 11** — 147 — the
three new checks being the whole of the change, and it has not moved since
lunch.

**Five defects, three before lunch and two after**, from a day that opened with
nothing to do: three stale claims found by a sweep on an empty day, one
misdirected diagnostic found by checking a prediction, and one negative control
found by not believing it. **The afternoon added none** — two readers, four
compile-and-run cycles between them, and nothing broken. **Not one finding from
a test**, for the third day running.

**Two experiments, four predictions wrong.** Run 1 was wrong about the bare
integer and never reached the chain; run 2 was wrong that the chain would be
written at all, and wrong that two readers hitting one wall would prove it was
the wall. **Every one of the four was wrong in the same direction: they assumed
a reader would meet the notation's edges, and both readers were carried past
them by a document.**

The tally has two rows it did not have this morning: **checking a prediction
instead of asserting it**, at one, and **not believing a control that agreed
with the code**, at one.

## 2026-09-02, later — a sixth program, and the sweep that closed the day was wrong about the tests

**The day had already been closed out.** `c61680a` wrote the entry below, landed
POSTMORTEM 19 and two standing agreements, and reported the day's counts. This
session reopened it, and one of the things it found is in that entry.

The numbers are at the foot, for the reason the entry below spent three attempts
learning.

### It began as a question, again

> Can proto be used to create an interpreted language like BASIC?

**Two questions wearing one sentence**, which is what [targets.md](targets.md)
had to untangle a day earlier for the *compiler* version of the same ask. So the
first answer was to separate them and then check both by running them:

- A BASIC **interpreter written in Proto** — yes, and `programs/ember` was
  already 90% of the shape.
- **BASIC as a Proto dialect** — partly, and compiled rather than interpreted.
  A `@syntax`-declared `PRINT`/`LET`/`IF`/`FOR` compiles and runs. What it
  cannot have is `LET x = 3`, because `=` is an operator and a pattern is words
  and holes — the wall `ember` hit with `mov <d>, <s>` — and it cannot have line
  numbers, because **a pattern begins with a word** and `10 PRINT "HI"` begins
  with an integer.

**Both halves were tested before either was claimed**, which took ten minutes
and is the only reason the second half's two limits are stated as errors the
compiler actually prints rather than as things that sounded true.

### The sixth program

Predictions first, in `92be288`, before a line existed. Then the interpreter:
line numbers, `LET`, `PRINT`, `INPUT`, `IF`/`THEN`, `GOTO`, `GOSUB`/`RETURN`,
`FOR`/`NEXT`/`STEP`, `END`, `REM`, and a prompt with `RUN`, `LIST` and `BYE`.

**It was picked for the thing five programs had not been.** Every one of them
walks its input end to end in the order it is written. An interpreter has a
counter that can go backwards, an environment outliving every statement, and
statements running a number of times the source does not say.

Five of six predictions were right. **The two that matter were right for the
wrong reason**, and the wrong reason is the finding.

Prediction 2 said BASIC's `+` would go undeclared because the interpreter's own
counting outnumbers BASIC's adding. It goes undeclared, and not for that:
**there is nothing to declare it for.** The interpreter never writes `a + b` on
two BASIC values anywhere. It writes `binop:value(op, a, b)` with `op` a string
that came from the input, and every branch is a send that already knows its
operation. Two `+` survive in the whole file and both are `pc + #1`.

So prediction 1's reason covers prediction 2 as well, and `grammar`'s ceiling
was never about recursion:

> **Notation is fixed when a file is read. An interpreter's every decision is
> made after that.**

**That dissolves the question the program was picked to ask** rather than
answering it. It was picked as the first program with two domains in one file —
a domain of steps and a domain of values — to see whether *steps want forms,
values want operators* could hold twice inside one dialect. The value domain
never reached the dialect. It is one level down, where no header can see it. **A
program can contain a domain without being one**, so the split five programs
found is a taxonomy of domains a dialect can *see*.

### Two things nothing had tested

**A form's word and a message selector do not collide.** `@syntax step` sits in
the same program as six sends of `s:step` to a `scan` cursor, and both compile
correctly, because a selector is never in primary position and the matcher never
looks there. The README's rule that *a word in a pattern is not reserved
anywhere else* was written about variables. Something depends on it for
selectors now.

**And it is the first program that needed hygiene.** `take`'s template has a
temporary `t`; `parseAtom` has a local `t` and calls `take` into it. The
generated source renames the template's. Without hygiene the parser loses the
token it just read, four lines before it uses it. **Nobody noticed while writing
it** — which is exactly what the argument for putting hygiene in with forms in
0.2.0 rather than after predicted, and, being a thing that does not happen, the
only evidence that argument could ever have.

### The bar was met, and Hans took it

`lib/arith.pro` shipped `<`, `>` and `==` alone from the first commit. The entry
keeping the other three out is the one *a surface does not grow without a
customer* was written down against. `programs/prose` was the first customer a
day earlier and wrote around the gap; this program wanted `<=` and `>=` five
times and `!=` four.

**The count did not settle it cleanly and that was reported rather than
smoothed over**: two customers for `<=`, one each for `>=` and `!=`. Hans's
answer was to take all three, and the argument now sits at the declarations:

> **A customer count is per surface, and a comparison set is one surface.**

An arith with `<=` and no `>=` is a worse trap than an arith with neither,
because the missing one is missing for no reason a reader can see. **Both
customers were rewritten the same day**, which is the check that they were real.

### And then the sweep, which found the last session's sweep

POSTMORTEM 19 was written last night about nine stale claims and landed the
agreement that everything is read once at the end of a day. **Tonight's sweep
corrected fifteen**, and how they divide is the whole of
[POSTMORTEM.md](POSTMORTEM.md) 20.

**Six were stale before last night's sweep ran, and it missed all six.**

- `targets.md` carried the *same sentence* 19 corrected in `README.md` and
  `REFERENCE.md` — *does-it-pay.md is what four programs have said* — in a third
  file the sweep did not open.
- The entry below **read** "58, 6, 60 and 11", which is 135, six paragraphs
  above the same entry reporting the total as 144. Nothing had touched `tests/`;
  the figure was 69 and had been all day. It carries the correction in place
  now, per the rule that a finding is retracted where it stands.
- `conventions.md` says "all three programs" twice, against six — **in the file
  that holds the sweep agreement.**
- `does-it-pay.md`'s heading reads *What the four declared* over five rows.
- And one that is not a count at all: `REFERENCE.md` described `lib/clike.pro`'s
  `!=`, `<=` and `>=` as *templates over the three above*. They have been plain
  messages since 0.6.0 — **wrong for eight versions**, invisible to every sweep
  because nothing about it looks like a number, and found only because that
  table was being edited for the arith change.

**Nine more went stale during today's own work** — a sixth program and three
operators in a shipped dialect ripple further than they look — and were caught
the same day.

**What found most of them is the thing worth keeping.** Not reading everything,
which 19 already prescribed and which `targets.md` passed: it *was* read, for
what it says about targets, which is what it is for. What found them was
**grepping for the claim instead of opening the documents.** One search for
*five programs* returned every instance at once, including three in
`does-it-pay.md`; one for *declined twice* returned four files. A claim
repeated in three documents is one claim.

That is a standing agreement now, beside the sweep it sharpens. And the file it
was added to was two of the six, which is the part to remember: **a document
stating a rule is the least likely of all to be opened while the rule is being
applied.**

### What the tests did today

Nothing, and correctly so — not one line of C changed. The suite sat at
**58, 6, 69 and 11** all day, which is what it should do when the work is a
program written *in* the language rather than a change *to* it.

**The one number that moved was in a document**, and it moved backwards: the
entry below had recorded 60 where the suite has printed 69 on every run since.

### The numbers, written last

**Four commits, this one included**, and **no version** — nothing in
`proto/` was touched. One program, one shipped dialect completed, one roadmap
entry closed by a customer, and one postmortem entry with nine instances in it.

`programs/basic` is 251 lines over a 16-line dialect: **15 forms, 0 operators,
93 uses.** It is the fourth of six programs to declare no operators, and the
prediction had said seven or eight forms — wrong by half, and the only one of
the six predictions that was wrong about a number rather than a reason.

**Not one finding came from a test, for the second day running.** One came from
a question asked in the first message. Two came from writing the program. Most
of the fifteen corrections came from a `grep`, and the oldest of them — a
description wrong for eight versions — came from editing a table for an
unrelated reason.

The tally has a row it did not have this morning: **grepping for a claim rather
than opening the documents**, at one — and it is the row that found the most.

## 2026-09-02 — a directive removed, a survey that was partial, a fifth program, and the bar

**Every number in this entry is at the foot**, and this is the third attempt at
saying why.

The opening first read *five commits, one version*. Corrected to nineteen.
Corrected again with the commit count moved to the foot and the sentence *this
opening carries only what stopped changing* — and then the version range
changed, in the paragraph claiming to have fixed the problem.

So the rule is harder than it looked: **nothing about a running day has stopped
changing, and the only stable thing in a journal entry is its date.** Not the
commits, not the versions, not the range, not the heading. Everything countable
goes at the bottom where it can be written last, and the top carries only what
happened. [POSTMORTEM.md](POSTMORTEM.md) 13 three times over, in the entry that
kept quoting it.

The day opened with *what's next todo?* and built none of the four things that
question was answered with. It closed having closed seven of nine differences
nobody knew were there at breakfast.

### It began as a roadmap review and went somewhere else

The answer to *what's next* ranked the open items and recommended constant
folding: the only entry with a measurement behind it, and the only one where the
case was already made. That item is still untouched tonight.

What happened instead is that Hans asked how the thing works, four times, and
each answer turned into work. **The roadmap describes what is known to be
missing. It has nothing to say about what is unclear**, and unclear is where the
day's whole output came from.

### Two of the questions were misreadings, and both were productive

> Proto runs the rules on the code and replaces the parts that matches?

No — matching happens *during* parsing, inside the reader, against a table the
header built before a statement was read. There is no pass over finished code.

> if the body was a different programming language, then the clash might not
> happen with the `|`, say Pascal for instance?

No — `|` is the *reader's* constraint, not the body's and not the emitter's. A
Pascal compiler written in Proto still cannot declare `|`, and a Proto that
emitted Pascal still could not either, because the ambiguity is in `{ a | b }`
and that is Proto's own syntax.

**Neither misreading is one a document written from the inside would think to
correct.** GRAMMAR.md says what the syntax is; the README argues why. Nothing
said *matching is not a scan*, because nobody on the inside would imagine it
was. Both are now in [what-is-proto.md](what-is-proto.md), kept as the questions
they were rather than rewritten into statements, and the pipeline is drawn four
times in [pipeline.html](pipeline.html) — `3156d26`.

### `@language` went, and a question is what unstuck it

The roadmap had said for nine versions that it should select the reader, or the
emitter, or stop existing. It had not moved because **two of those three depend
on a build this project has already declined** — [targets.md](targets.md)
refuses a second emitter, and a second reader is larger still. The entry was
not waiting on a decision. It was waiting on something that was never coming.

What settled it was Hans asking what `@language Pascal` would actually declare.
The answer is *nothing anyone would expect*, and following that out gives the
argument the roadmap never had:

> `@language solveig.` at the top of `examples/forms.pro` says the body below is
> Solveig. That file declares `+`, `<`, `>`, `unless`, `while` and `swap`. Its
> body is not Solveig and Solveig cannot read it.

The line was false in every file that declared anything, which is every file
worth writing. Removed in 0.10.0 — `eb07046`, [COMPLETED.md](COMPLETED.md) 14.

### The near-miss is the part worth keeping

The first recommendation was **not** to remove it. It was to make it *assert*:
one reader, one emitter, so any name but `solveig` is an error at line 1.
Fifteen lines, touching no `.pro`, and the exact code a selector would need
later. The argument for it was reversibility — asserting is cheap and deleting
is not.

That argument prices a change. It does not ask whether the thing is right, and
the thing was not right. **A directive whose plainest reading is false is not
fixed by checking its spelling.** The reversal came from taking Hans's question
seriously rather than from any new fact.

### One spelling per operation

`\/` had been doing two jobs — logical *or* in `lib/arith.pro`, bitwise *or* in
`examples/utf8.pro` and `programs/digest/sha2.pro` — and `~` two as well,
logical *not* in arith and bitwise *not* in sha2, which is C's meaning. A reader
had to know which file they were in before they could read a line.

Hans proposed `&&`, `||`, `!` and asked whether `\` was free for the bitwise or.
It is, and it is the right answer: one character, where C writes `|`, which is
the one character a dialect can never have. **The single irregularity left is
forced by the design rather than chosen**, which is the best kind to be left
holding — it points at the constraint instead of hiding it. `b57aa31`.

`!` for bitwise or was proposed and refused on the way, for the same reason
`@language` had gone an hour earlier: `!` reads as *not* everywhere, and
`lib/clike.pro` already declares it prefix-not.

[POSTMORTEM.md](POSTMORTEM.md) 6 is a blind replace of these same operators that
mangled a shell command in a comment — *a rename applied to a file rather than
to a language*. This one ran only on the code portion of each line, never inside
a string or after a `;`, printed all 27 changed lines to be read, and then
proved itself the way that entry wishes it could have: **every generated `.sol`
in the tree is byte-identical across the change.** Same messages; only the
spelling moved.

### A segfault from 0.1.0, found by checking a sentence

`programs/digest/README.md` says composing `sha2.pro` with `lib/control.pro`
collides on four operators. Before repeating that in another document, it was
run. `proto` segfaulted.

`proto_dialect_add_infix` answers the entry a redeclaration displaced, so the
reader can say *previously declared here* — and it looked that entry up
**before** growing the array, so a `realloc` that relocates leaves the caller
reading freed memory. `add_prefix` and `add_macro` had it too. Latent since
0.1.0. `f8b219a`, [POSTMORTEM.md](POSTMORTEM.md) 15.

It hid because it needs three things in one call: a collision, a capacity
crossing, and a realloc that moves rather than extends. Every example and
program in this tree composes dialects that agree. `programs/digest` is the
first thing here with a dialect that redefines `+` — and its README says
composing it collides, having reasoned about it rather than run it.

**And the claim was wrong anyway.** Proto reported nine redeclarations, not
four: the four whose meaning differs, plus two declared identically in both and
three on a different rung. It is seven now, the spelling change having removed
`~` and `\/` from the overlap.

### `make sanitize`, because the tool was already there

The regression check that came with the segfault only guards under a sanitizer:
whether a stale pointer lands on freed memory is the allocator's business, and
in `test_use`'s process it does not. It fails under
`make test SANITIZE="-fsanitize=address"` and is clean with the fix.

Which is the finding that should sting. **That invocation had been in the
Makefile since the first commit and nothing had ever been run under it.** Not a
missing test — a tool sitting in a comment, never picked up. It is a target now
and a standing agreement in [conventions.md](conventions.md), and the suite is
clean under `-fsanitize=address,undefined`.

### The fourth program, which argued against both entries it was written for

`programs/ledger` was picked to answer two roadmap items at once: the
domain-boundary entry wanted a second program, and the folding entry wanted a
second customer. Predictions went in first, in their own commit, so the ordering
is in the history rather than in a claim.

**Both answers went the other way.**

The domain boundary is a pattern now — `digest` trapped on `+`, `ledger` on `/`
— but the second instance narrowed what the entry may promise, twice. **Which
operator turns traitor is not predictable from outside the domain**: this
program predicted `*` and was bitten by `/`. And the boundary is not only at the
domain's edge — `ratio interest to subtotal` answers `0.07` where the exact
value is `0.074995…`, because a ledger has amounts wanting two places and rates
wanting five, and a dialect has one scale to give.

Folding got its second customer and the customer voted against: **4,258
instructions against 4,250 hand-folded. Eight, or 0.19%**, where `digest` was
5.4%. Identical shape, different bill, and the reason is not the dialect — *a
dialect's constants cost per use, and this dialect's uses are outside the loop.*
One measurement had made folding look larger than it is.

### The survey was partial, which is the thing to remember about today

`ledger` found that `#-1225` is an error in Proto and a valid integer in
Solveig. That went into POSTMORTEM.md 16 as a missing integer literal, and it
would have stayed that size if Hans had not asked whether the survey behind it
had been complete.

It had not. Comparing every form in Solveig's grammar against Proto, one file
each, gives **nine divergences out of eighteen**. Four versions came out of that
in an afternoon: the sign on `#-45`, `$FF08`, float exponents and the escape set
in 0.11.0; `#[a = b]` in 0.12.0; `%1011` in 0.13.0.

Three of those are worth keeping past the version numbers.

**`"\q"` was the only one pointing the other way.** Every other difference was
Proto refusing something Solveig takes — a smaller language and an honest error.
That one was Proto *accepting* something Solveig refuses, and emitting it, so a
`.pro` compiled clean and produced a `.sol` `solas` rejected. **Proto emitting
invalid Solveig** is the single failure the map and the run-every-example
discipline exist to prevent, and neither caught it, because no example has a bad
escape.

**`#[a = b]` was mis-sorted as free and was not.** The lexer was never the
obstacle. Solveig settles what `=` means in a key by precedence *level*, which
Proto cannot copy because a dialect may declare `=` anywhere — `lib/clike.pro`
puts it at 10. It needed a rule saying **a context shadows a declaration**, the
first in this language, confined to the top level of a key so that
`#[(b = c) = d]` still uses the declared one.

**`%1011` cost something, and it is the first spelling here that did.** `||` in
0.9.0 grew the fixed vocabulary and took only `{ || … }` out of the *core*, and
COMPLETED.md 12 held that up as the shape any future request should take. This
is the second instance with a different bill: **growing the fixed vocabulary
took something from what a dialect may declare.** A module declaring `%` can no
longer write `a %1` without a space. Small, unused here, and loud — and the next
one might be none of those.

**And `-3` cannot be had at all.** Solveig's scanner gives the sign to the
number outside a `@expr` region and treats it as the operator inside one. Proto
has no regions and cannot take `-3` as a literal either, because then `a -3`
stops being a subtraction in every dialect that declares `-`. So *everything but
`operator` is Solveig's own spelling* was never achievable, and 0.1.0 chose
against it without recording that it had.

### And a last hour of putting things back the way they should have been

Asked whether `lib/arith.pro` should be completed with the bitwise operators:
**no**, and the tree makes the case rather than taste. Bitwise has one usable
customer rather than two — `sha2.pro` cannot share a file, its `<<` being masked
and the file standalone because it redefines `+` — and the two existing
customers chose different rungs for `&` and `>>` against their own neighbours.
`<=`, `>=` and `!=` have no customer at all: every one of arith's five users
declares no operator of its own.

The neighbourhood turned up something else, though. **Seven templates were
standing in for messages Solveig already had** — `notEquals`, `lessOrEqual`,
`greaterOrEqual`, and a `not` that `arith.pro` had been spelling plainly all
along while `clike.pro` wrapped it. `digest` runs 920 instructions fewer, and
what is left in `clike.pro` is three templates, each one a message cannot be.

### Somebody built the thing that could not be built

A second session, running against this same working copy, made a branch and
declared `|` as an infix operator. It worked: two hunks in `reader.c`, **no
change to the lexer**, the whole suite green, every block form intact, and an
example whose commented values all came out right.

**Three documents said that was impossible**, in nearly the same words, and I
had said it twice more during the day. `README.md`, `lex.c` and
[COMPLETED.md](COMPLETED.md) 12: *`{ a | b }` would have two readings, and
naming the ambiguity does not decide it.*

**Two questions had been run together and given one answer.** *May `|` join the
operator characters?* — no, and that stands, because characters in that set run
together and a `|` there would make `|=` a spelling. *May `|` be declared?* — a
different question, a bar being a token of its own that a parser may look up
without it entering the set at all.

And the resolution was already in the language. `{ a | b }` is a parameter and a
body **by rule**, and `{ (a) | b }` escapes — which is `#[(b = c) = d]` in a
different bracket, **landed four hours earlier the same day.** The mechanism was
in that morning's commit message and the argument against `|` was not re-read in
its light.

**The cause was misattributed in both directions**, which is the part worth
keeping. Entry 12 blamed the ambiguity and stopped. The session that built it
reported removing *Solveig's* constraint and had removed nothing of Solveig's —
`lex.c` untouched, and Solveig has the identical `{ a | b }` and settles it the
identical way. What stands in the way of `|` is **Proto's own block syntax**.

The work was reverted, not kept: it arrived uncommitted in a shared checkout and
what it costs had not been looked at. [ROADMAP.md](ROADMAP.md) is that looking,
and carries the reason not to hurry — 0.13.0 had just settled the repository on
`\` for bitwise or *because* `|` was unavailable, and a spelling should be
changed once. [POSTMORTEM.md](POSTMORTEM.md) 18.

**It also came within half an hour of being swept into a commit of mine.** The
edit landed at 11:59 and my last `git add -A` was 11:30. Two sessions in one
working copy is a hazard that cost nothing today by timing alone.

### The question this project exists to answer, finally written down

[targets.md](targets.md) has said since 0.1.0 that the only thing this project
exists to find out is **whether a grammar declared per module is a good idea**,
and then left it to be answered elsewhere. Four programs had answered parts of
it, each in its own README, each quoting the one before — and *a dialect pays
per line it removes* appeared in four program folders and **nowhere in `docs/`
or the README.**

[does-it-pay.md](does-it-pay.md) is the four weighed together, with the numbers
re-measured rather than carried across. Tabulating them showed something no
single program could have:

| | operators | forms |
| --- | ---: | ---: |
| ember, grammar — about another *language* | **0** | 16, 8 |
| digest, ledger — about a *value domain* | 17, 10 | 3, 6 |

**A domain of steps wants forms. A domain of values wants operators.** Nobody
chose that; four programs arrived at it independently, and `ember` had already
found the reason without knowing it was one — a pattern *reads as a step in a
procedure*.

Re-counting also corrected `digest`'s own README in both directions. It claimed
Solveig writes twenty-three `bitAnd`s by hand and Proto writes none. Solveig's
file has 24 in code, of which **18 are `bitAnd(mask)`**; Proto's has **0 masks
and one** `bitAnd`, a byte extract. **Eighteen hand-written masks became five
declarations** — the finding survives and the figures did not.

### And a fifth program, for the one thing four had not tested

`does-it-pay.md` ended by asking for a domain that was neither arithmetic nor
instructions. [`programs/prose`](../programs/prose) is that: a document
language, with the document itself written in the dialect. It is also the
answerable half of a question asked the wrong way round earlier — *can Proto
take prose?* Not as its body; but a dialect can be shaped so the document **is**
the program.

**It found no third category.** No operators, seven forms — `ember`'s shape
exactly. A document is a domain of steps and the taxonomy absorbed it.

**One prediction was wrong and it was the best finding.** Nesting was predicted
to be the wall. It is not: a form takes a **block**, a block holds statements,
and statements are content forms, so `indent { … }` nests to any depth and
Solveig's braces carry the structure. The real ceiling is a level lower —
**a form can contain content; a form cannot contain half a line.** Emphasis
inside a sentence has nowhere to go, because a paragraph is one string.

**And it split *carrying a rule* in two.** `indent { … }` cannot be unbalanced,
but the dialect borrowed that from Solveig rather than inventing it. `sha2.pro`
invented its own. **Only the invented kind is evidence that a declared grammar
does something a fixed one cannot**, and it is still the single clear instance
in five programs.

It also reversed an answer given the same morning. `lib/arith.pro` has no `<=`,
and the renderer wanted one. Asked at eleven whether arith should be completed,
the answer was no — *no customer at all*, every one of arith's five users
declaring no operator of its own. This is the sixth user and the customer. **One
is still not enough**, which is the rule that kept the bitwise operators out on
the same day; the roadmap records it so the second customer settles it.

### The bar, landed, and a spelling changed twice

The retraction earlier in the day said `|` could be declared and did not do it.
Asked for an example, the honest answer was that the current build refuses one —
so a scratch copy was patched to demonstrate it, and the demonstration made the
case for finishing it properly.

**0.14.0 is the bar, and `\` retired in the same commit.** The rule is the one
`#[k = v]` already had, and the reason the two went together is the whole
argument for waiting a version:

> 0.13.0 had settled the repository on *one spelling per operation*, with `\`
> for a bitwise or **because `|` could not be had**. Landing the bar alone would
> have changed one spelling twice in two versions.

**A spelling should be changed once**, and this one was changed twice — the
second time deliberately, in one commit, with the table ending as C's exactly
and nothing substituted. The two gaps the demonstration had — `@prefix |`
accepted and inert, and a stray bar with the wrong diagnostic — were closed
before it landed rather than after.

The lexer was never touched. `|` is still `PROTO_TOK_BAR` and still not an
operator character, so a tool can tokenise any `.pro` knowing nothing about its
dialect — the property [COMPLETED.md](COMPLETED.md) 12 was written to defend and
does defend correctly, even though the conclusion drawn beside it was wrong.

### A table cell that misled its first reader

The one-spelling table had an em-dash in the logical-xor cell, meaning *there is
not one*. Its first reader read it as a proposed operator and asked whether
logical xor was a minus sign.

**That is the table's fault and not the reader's**, and the answer turned out to
be more interesting than the correction. There is no symbol to have — C has no
`^^`, Java and Python reuse `^`, Pascal uses a keyword — and Solveig's boolean
understands only `not`, `and`, `or`, `ifTrue`, `ifFalse` and `ifElse`. What
there *is* is `!=`: for booleans, xor and not-equals are the same operation,
which is why nobody invents a symbol for it.

So **`lib/clike.pro` has had a logical xor since it declared `!=`**, and nobody
noticed — including me, that afternoon, while replacing that very template with
the direct message. And if it were ever spelled as its own operator it would be
`^^`, for the reason Hans gave when the answer reached him: the single character
is the bitwise one and the doubled one is the logical one, as `&` is to `&&`.
Recorded, and **not declared**, because nothing has wanted one.

### What the tests did today

Nothing, and mostly that was the job. The suite held at 58, 6, 34 and 10 while
the spelling change went through, which is precisely what a spelling change
should do to it — **a control, not a detector**. It ended at 58, 6, 69 and 11:
the segfault added one, and the new spellings thirty-five.

*Corrected on the evening of the same day: this line read `58, 6, 60 and 11`,
which is 135, in an entry that reports the total as 144 six paragraphs later.
Nothing had touched `tests/` since. See the closeout section below.*

### The numbers, written last

**Thirty-two commits, this one included** — a number cannot count itself and
has to be told to, which is why this line has been rewritten as often as it has.
**Five versions, 0.10.0 to 0.14.0. A fifth program. And not one finding from a
test.**

Two misreadings, by a person asking. One dead directive's real argument, by a
person asking what it would mean. One nine-version-old segfault, by declining to
repeat a sentence without checking it. Eight of the nine syntactic differences,
by a person asking whether the first survey had been complete. One
impossibility, by somebody building the thing that could not be built. And one
misleading table, **by its first reader asking what a dash meant.**

Every one by a person or a program, and the tally has two rows it did not have
this morning: *being asked whether a survey had been complete*, at two, and
*somebody building the thing that could not be built*, at one.

**Three documents arrived that had no home before**:
[REFERENCE.md](REFERENCE.md), the page you look a spelling up in;
[does-it-pay.md](does-it-pay.md), the answer to the only question the project
exists to ask; and `programs/prose/README.md`, a document about a document.

Those are the day's real output. The five versions were the easy part — four of
them closed differences nobody knew were there at breakfast, and the fifth
landed a thing three documents had called impossible.

**And the day closed with a sweep**, which found five more stale things: a
version heading four releases behind, a *Known gaps* row for something that
landed in 0.12.0, a folding claim carrying one measurement when there are two,
this page's own count in two other documents, and — while the entry recording
all of that was being written — the postmortem's claim of 109 unit tests when
there are 144.

**None of them was the work. All of them were a document describing yesterday's
version of itself**, which is the failure this journal spent the day committing
and correcting three times. [POSTMORTEM.md](POSTMORTEM.md) 19 collects the nine
instances and says why 13's defence was not enough: it works when a stale claim
is in front of you, and **nobody re-reads a document that is not being read.**
The one that worked was reading everything once at the end, whether or not
anything was suspected, and that is a standing agreement now.

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
