# How work is decided and checked here

*The practices this project actually runs on, which until now lived in nobody's
document. [ROADMAP.md](ROADMAP.md) says what is outstanding, [ideas.md](ideas.md)
says what was considered and refused, [releasing.md](releasing.md) says how a
release is cut. This says how any of those get decided, and how a claim gets to
be believed.*

Every rule below was learnt by getting something wrong, and each one names the
occasion. That is the only reason to trust them.

---

## A program asks, not a document

**Nothing is built until something asks for it, and the asking is done by a
program rather than by a page.** [ideas.md](ideas.md) records each deferred idea
with a **named trigger**, and there are two dozen of them; the trigger is what
fires the work.

The rule earns its keep in both directions.

**It fired for `startsWith` and `endsWith`** on 2026-08-30. They had been
deferred the day before with one customer. A count then found three programs,
nine call sites, and *two independent implementations of `endsWith`* — one of
which carried a comment recording a defect the absence had already caused. Two
copies of one function is the same trigger `string:replace` was built on.

**And it did not fire for `dictionary:of`**, built the same day because a
dictionary literal would compile to it and because it was asked for. Every
`dictionary:new` in the tree is an accumulator or a table of blocks, so nothing
called it but its own demonstration. The entry says so rather than dressing it
up, because a page that only records the times the rule was obeyed is not
evidence of anything.

**Why it holds:** the one time the method was ignored, the page arguing for
extensions kept getting longer instead of being tested. When it was finally
acted on, an afternoon falsified two of its claims.

## The throwaway comes before the design

**Build the smallest thing that settles the question, and let it correct the
design.** Fifty lines, thrown away afterwards.

The extensions entry closed by advising exactly this and was then proved right
by its own advice. The GTK canvas found that a `cairo_t` cannot be published to
a program because it dangles the moment a draw callback returns — a design
question no amount of reading would have raised, and one that decided the
interface.

## Scope before building, and the decision is separate

**A language change is written into [ideas.md](ideas.md) first, with the
analysis, a recommendation, and the calls only the author can make.** Then it
stops. Building is a separate instruction.

`@expr` was scoped on paper on 2026-08-28 and implemented the next day with
almost nothing left to decide. The dictionary literal went the same way on
2026-08-30 — and the scoping is what found that half the proposal was
unnecessary, which no implementation would have discovered because that half
would simply have been built.

**Scoping is also allowed to end in no.** Named arguments were recommended in
the morning and refused in the afternoon, once the options array turned out to
catch every mistake it stood accused of passing.

## Check the thing, not a picture of it

**A graphics program's output is a picture, so the check has to be the picture.**
On 2026-08-30 an SDL example drew bands of noise past three checks that had all
passed: the arithmetic rendered as ASCII, the program run and timed, and the
colours recorded as they were handed to `sdl:fill`. **All three tested the inputs
to the drawing calls and the defect was on the other side of them.** Look at it —
`screencapture`, or have the program write a PPM.

**It is not only about pixels.** The 0.40.0 release page rendered as a narrow
ragged column because release notes are rendered with hard line breaks and every
document here is wrapped at 79 columns. The markdown was correct; every check on
it passed and every check was honest. There was nothing to find by reading,
because nothing that was read was wrong.

## A check that cannot fail is decoration

Two of these in one day, both the same shape, and the shape is worth more than
the instances: **a comparison whose two sides came from the same source is not a
comparison.**

The editor's screen transcript was compared against a recording made at a path
that no longer existed, so the comparison ran one binary twice. `html.sol` before
and after a change was compared by recompiling a probe — except `@include`
resolves while compiling, so the probe's `.sob` had the old library baked into it
and the same bytecode ran twice.

The question that catches both: **what would have to be broken for this to
fail?** If the answer is nothing, the check is decoration.

**And its mirror**, from the same day: a test that fails for the *wrong* reason
misleads exactly as far as one that cannot fail. Three findings against the
0.40.0 release page were artefacts of the checks rather than faults in the page,
and reporting any of them would have been worse than not checking.

## Check against what ships, not against the working tree

On 2026-08-29 a throwaway reported sixteen `.sob` files in the tree differing
from a fresh compile, and one of them shipping without an `exports` boundary its
source demands. Written up as a defect. It was not one: `*.sob` is ignored,
`make install` copies `lib/*.sol`, and nothing in `lib/` is tracked or built.
They were hand-compiled leftovers.

`git ls-files` takes four seconds, and it was skipped precisely because the
finding looked interesting. **Presenting a non-defect as a defect costs more than
saying nothing.**

## How a feature ships

One unit, in this order:

1. **Implementation, then tests** — `tests/test_<feature>.c`, including a
   GC-stress case if it allocates.
2. **Prove a new GC root is load-bearing by removing it** and showing what
   breaks, then restore. **This can end in deletion.** `dictionary:of`'s root was
   removed on 2026-08-30 and 200 dictionaries plus a 120-pair one ran clean under
   `SOLUM_GC_STRESS`, because `sol_dict_put` grows with `calloc` and cannot
   collect — which `object.c` already said, beside the code doing it. A guard
   against a hazard that is not there is worse than no guard: it tells the next
   reader the hazard exists. Keep the root only when removing it breaks
   something, and leave a comment saying why there is none. A front-end-only
   change owes no GC proof; say so.
3. **The documentation tail** — `docs/REFERENCE.md`, `docs/CHEATSHEET.md`,
   `docs/GRAMMAR.md` *and* `programs/check_syntax/solum.bnf` if the grammar
   moved, an example, and `docs/ROADMAP.md` if an entry closed.
4. **Re-sync the marked counts.** Adding a claim to a document moves the totals
   the checker recounts.
5. **Then journal and changelog**, as their own commit, and **the changelog hash
   as a third** — an entry names the commit it landed in, which cannot be known
   until that commit exists.

## The checker checks what it can run

[expect.sol](../programs/expect.sol) executes the claims in the documentation —
over a thousand of them — and that is why the numbers in these pages can be
trusted. **It only checks claims it can execute.**

*Nothing is slower* is a claim. It is not one the checker can see, and it was
wrong by three orders of magnitude for a day. On 2026-08-30 five sentences
standing in the documentation were tested and four were wrong, and not one was
found by a program failing. They were found by going to check a sentence before
repeating it.

**The habit that catches them is not a tool.** It is refusing to write *because
X* until X has been run once.

## And a program that measures a class cannot load a library that extends it

Found on 2026-08-30 when `expect.sol` began reporting the wrong number of
messages an integer answers. It includes `text.sol` now, and `text.sol` puts two
methods on `integer`. The count is read before the includes for that reason.

Four of the nine libraries add methods to built-in classes and five do not, so
the hazard is real and invisible until it fires.
