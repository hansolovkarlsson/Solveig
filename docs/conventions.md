# How this project is worked on

*The standing agreements and the method, written down so that neither depends on
anybody remembering them.*

[journal.md](journal.md) is what happened; this is how.

---

## Standing agreements

**`scratch/` is not the repository's.** A `scratch/` directory holds Hans's own
comments, thoughts and experiments. It is not read, scanned, summarised or
committed, and it is in `.gitignore` so that it cannot be. If something in there
seems relevant, ask rather than read.

**What Proto finds in Solveig goes in [solveig-notes.md](solveig-notes.md).**
Bugs, missing functionality and surprises are written up clearly enough to be
lifted straight into Solveig as task items: what happens, a minimal repro,
expected against observed, the cause **if confirmed**, a suggested fix, and why
it matters here. Things that *look* like defects and are not go in too, so they
are not re-found. Nothing goes in unverified — reproduce it, and do not assert a
mechanism you have not checked.

**Solveig's README links Proto, since 2026-09-03.** The hold was set on
2026-08-31, when Proto was a front end with no expander and pointing Solveig's
front page at it would have advertised something that had not yet done the thing
it claimed. The expander landed the same day, which met the condition and turned
it into a decision rather than a hold — Hans's, and taken on 2026-09-03, six
programs in.

**Where it went says something worth keeping.** Not in the table of
`solveig-gtk` and `solveig-sdl`, which are outside that repository so *no
dependencies beyond a C11 compiler and `make`* stays true. **Proto is outside so
that it cannot reach in**, which is a different reason and the one this project
exists on, so it is a paragraph of its own below them.

**The name Phoenix belongs to a different project and is not this one's to
reuse.** This project was called Phoenix until 2026-09-01. The name was already
reserved, three days earlier, in Solveig's `docs/ideas.md` — *a second language
whose output Solum uses*, closing with *the name, should it happen, is Phoenix*
— for a language that publishes a **library** Solum consumes, where Proto emits
a program's source. Two consequences, and the second is the one that costs
something if forgotten: any surviving `phx`, `Phx`, `PHX_` or `phoenix` in this
tree is a defect rather than a distinction, and **the Phoenix entry in Solveig's
`ideas.md` is that project's reservation and is not to be rewritten** — a
search-and-replace across both repositories would have taken it.

## The method

**A surface does not grow without a customer.** `lib/text.sol` states it over in
Solveig — *one customer, satisfied in six lines, is not a reason to grow a
surface* — and its converse is the trap this project fell into for six versions:
a surface with no customer at all has never been tested. Optional and repeated
parts have now been declined **three times by three programs**, which is worth
more than any argument either way — and the third declined them from the far
side, `programs/basic` finding that BASIC's `PRINT a, b, c` and its optional
`STEP` are repetition and an optional part in the *interpreted* language, where
no Proto feature reaches.

**Predictions are recorded before a program is written**, in the manner of
Solveig's `ideas.md`, so that *it found nothing* stays an available answer. All
six programs in `programs/` have a table of them and a *What it found* section
written afterwards. Predictions that were wrong stay in, marked wrong:
`programs/ember` predicted Solveig would bite first and it did not, and
`programs/digest` predicted a template costs nothing at run time and it does not.

**A claim about cost is measured, not argued.** `programs/digest` was going to
say that a form is a method that costs nothing, because a template expands
rather than calls. It is not true — the template saves 2.03 instructions per use
and spends 2.00 on a constant nothing folds — and no amount of reasoning about
expansion would have produced that number. The method is a binary search on
`solvm --steps=N`: the smallest N that lets a run finish is the run's exact
instruction count. It is exact, it costs one run per bit, and it turned a
roadmap claim into a roadmap entry with a figure attached.

**A finding is retracted in place, not edited away.** `POSTMORTEM.md` entry 11
exists because entries 7 and 9 were written down somewhere somebody could go
back and disagree with them. A README that quietly stops claiming something
teaches nothing.

**Every text replacement asserts its match.** A replacement that matches nothing
is not an error; it is a no-op that reports success, and three of them left the
roadmap four versions stale while commit messages said otherwise. Three of the
recorded defects are this one mistake.

**Read Solveig's own documents before designing anything that overlaps.** The
collision rule, the binding rules that made 0.3.0 one pass instead of a
resolver, the block-escape limit that shaped `programs/grammar`, and the
embedding surface that would host a guard — all four were already written down,
and reading them was consistently the cheapest hour available.

**A commit message carries the argument**, not the diff. What was decided, what
was rejected, and what it cost. The diff is in the diff.

**Output is checked by hand, not trusted for having run.** `examples/clike`
printed `#54` where `#40` was right, compiled clean and failed nothing.

**Everything is read once at the end of a day, whether or not anything is
suspected.** [POSTMORTEM.md](POSTMORTEM.md) 13 said a claim about another
document is re-derived when it is read; 19 is eight instances in one day of why
that is not enough — **nobody re-reads a document that is not being read.** A
README's version heading is not consulted when adding a version, and a *Known
gaps* table is not consulted when closing a gap. A sweep at the end found four
of the eight in ten minutes, two of them in files nobody would have opened for
months. A defence that depends on suspicion is not a defence.

**And the sweep greps for the claim, not for the documents.**
[POSTMORTEM.md](POSTMORTEM.md) 20 is the next session's closeout correcting
fifteen claims, six of which 19's sweep had already had its chance at — one the
*same sentence* it corrected in two files and missed in a third, and two in this
file. Reading everything once does not catch that: `targets.md` **was** read,
for what it says about targets, which is what it is for. A claim repeated in
three documents is one claim — `grep -rn "five programs"` returns all three at
once, and opening the two you remember returns two.

**This file is not exempt and was the worst offender**, which is the part to
keep: a document stating a rule is the least likely of all to be opened while
the rule is being applied.

**The sweep runs on a day with no work in it too.** On 2026-09-03 the answer to
*close out the day* was *there is nothing to close out* — the previous day had
been closed and pushed and nothing had moved since. Run anyway, the sweep found
three, one of them a sentence that had been false since the commit that wrote
it. **A sweep audits the documents, not the day**, so an empty day is not a
reason to skip one. [POSTMORTEM.md](POSTMORTEM.md) 21.

**And a record of a defect is written in the past tense.** *The entry below
reports X* is false as soon as X is fixed, and the fix is usually in the same
commit, because describing a defect and correcting it are one piece of work.
*The entry below read X* survives it. Three of 21's instances are this, one of
them inside 20's own write-up.

**Two sessions do not share a working copy.** On 2026-09-02 a second session
made a branch and left uncommitted changes to `proto/src/reader.c` in this
checkout while this one was committing every few minutes with `git add -A`. The
edit landed at 11:59 and the last such commit was 11:30; nothing was swept in,
by half an hour and no more. A second checkout is one command and makes it
structural rather than lucky:

```sh
git worktree add ../Proto-<name> -b <name>
```

**`make sanitize` before a release, and after anything that touches the dialect
tables.** The suite cannot find a use of freed memory on its own: whether a
stale pointer is a crash is the allocator's decision, so a check can hold the
exact shape of the bug and pass. [POSTMORTEM.md](POSTMORTEM.md) 15 was latent
from 0.1.0 to 0.10.0 with the invocation that catches it sitting documented and
unused in the Makefile the whole time. **A tool nobody runs is not a tool**,
which is why it is a target now and this is a standing agreement rather than a
good intention.

## What the build guarantees

`make` needs a C11 compiler and nothing else — no Solveig header, archive or
symbol. `make test` needs Solveig, because it runs every example and all six
programs all the way through `solas` and `solvm`, `programs/ember` all the way to
a linked binary diffed against expected output, and `programs/digest` against
digests that an independent oracle produced first.

**A front end that emits text can be wrong in a way no unit test sees** —
Solveig-looking source that Solveig rejects, or accepts and reads differently —
and the only witness to that is the real compiler.
