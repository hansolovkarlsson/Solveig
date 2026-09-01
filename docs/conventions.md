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

**What Phoenix finds in Solveig goes in [solveig-notes.md](solveig-notes.md).**
Bugs, missing functionality and surprises are written up clearly enough to be
lifted straight into Solveig as task items: what happens, a minimal repro,
expected against observed, the cause **if confirmed**, a suggested fix, and why
it matters here. Things that *look* like defects and are not go in too, so they
are not re-found. Nothing goes in unverified — reproduce it, and do not assert a
mechanism you have not checked.

**Solveig's README does not link Phoenix yet.** Decided on 2026-08-31, when
Phoenix was a front end with no expander and pointing Solveig's front page at it
would have advertised something that had not yet done the thing it claimed. The
expander landed the same day, so the condition is met and the link is now a
decision rather than a hold — Hans's, not one to make unasked.

## The method

**A surface does not grow without a customer.** `lib/text.sol` states it over in
Solveig — *one customer, satisfied in six lines, is not a reason to grow a
surface* — and its converse is the trap this project fell into for six versions:
a surface with no customer at all has never been tested. Optional and repeated
parts have now been declined twice by two programs, which is worth more than any
argument either way.

**Predictions are recorded before a program is written**, in the manner of
Solveig's `ideas.md`, so that *it found nothing* stays an available answer. All
three programs in `programs/` have a table of them and a *What it found* section
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
roadmap four versions stale while commit messages said otherwise. Three of
twelve recorded defects are this one mistake.

**Read Solveig's own documents before designing anything that overlaps.** The
collision rule, the binding rules that made 0.3.0 one pass instead of a
resolver, the block-escape limit that shaped `programs/grammar`, and the
embedding surface that would host a guard — all four were already written down,
and reading them was consistently the cheapest hour available.

**A commit message carries the argument**, not the diff. What was decided, what
was rejected, and what it cost. The diff is in the diff.

**Output is checked by hand, not trusted for having run.** `examples/clike`
printed `#54` where `#40` was right, compiled clean and failed nothing.

## What the build guarantees

`make` needs a C11 compiler and nothing else — no Solveig header, archive or
symbol. `make test` needs Solveig, because it runs every example and all three
programs all the way through `solas` and `solvm`, `programs/ember` all the way to
a linked binary diffed against expected output, and `programs/digest` against
digests that an independent oracle produced first.

**A front end that emits text can be wrong in a way no unit test sees** —
Solveig-looking source that Solveig rejects, or accepts and reads differently —
and the only witness to that is the real compiler.
