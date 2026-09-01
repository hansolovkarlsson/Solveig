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

**The hardest version of that is the one that misleads *usefully*.** On
2026-09-01 a throwaway link checker reported one dead anchor in `CHANGELOG.md`.
Chasing it found two real faults in that file — a paragraph wrapped so that ```
began a line, and an inline code span wrapped so that `<if-statement>` began
one — which between them had left 64 of that page's 327 headings on the
published site for ten days. Then the reported anchor turned out to be an
artefact of the throwaway's own fence rule: under the rule the renderer keeps,
that link was fine, and the checker that shipped reports nothing on a tree with
both faults still in it.

A wrong check produced a wrong finding, and chasing the wrong finding found two
right ones. That is luck, and the write-up has to say so — the temptation is to
report the check as having worked, because something real came out of the run.
**Ask what the check would have said if the faults were the only thing wrong**,
and put the answer in the entry. Here it was *nothing*, which is how the
artefact was found at all.

## And a comparison whose two sides did not run alike is not one either

The other half of the rule above, and it cost an afternoon on 2026-09-01. A
throwaway measured `/usr/bin/tail -f` and `-F` through a rotation, in one
script, one after the other, and reported that both follow the name. That went
into a roadmap entry in bold, including *the man page is wrong about its own
flag*.

It is not. `-f` follows the descriptor, and `lsof` on the running process shows
it holding the renamed file open. **The measurement reproduced four times, at
two timings**, which is exactly what made it convincing; reducing the script to
one flag made the wrong answer disappear.

What caught it was [follow.sh](../programs/tail/follow.sh) — a harness that runs
the two sides under **one** set of conditions — on the first run after a
scenario for this went in. The rule had been applied to every check here and not
to the throwaway that measured the oracle those checks compare against.

**So a throwaway that measures something the documents will state is not a
throwaway.** It is a check, and it owes the same discipline: one harness, both
sides, and direct evidence when a run disagrees with a published description.
Distrusting the run rather than the page was the right instinct and was applied
in the wrong direction — the run was re-run, agreed with itself, and was
believed. Re-running a wrong experiment is not evidence.

## Check against what ships, not against the working tree

On 2026-08-29 a throwaway reported sixteen `.sob` files in the tree differing
from a fresh compile, and one of them shipping without an `exports` boundary its
source demands. Written up as a defect. It was not one: `*.sob` is ignored,
`make install` copies `lib/*.sol`, and nothing in `lib/` is tracked or built.
They were hand-compiled leftovers.

`git ls-files` takes four seconds, and it was skipped precisely because the
finding looked interesting. **Presenting a non-defect as a defect costs more than
saying nothing.**

## Hold it against something somebody else wrote

**The strongest check available is an implementation whose author had no idea
what this language can do.** Every other check here is a transcript recorded by
the person who wrote the code, and can only catch what that person thought to
check.

It cost ninety seconds to prove on 2026-08-31. `programs/sed.sol` was held
against `/usr/bin/sed` and the first run reported a defect in `lib/pattern.sol`
that had been shipping for days: an empty match at the position where the
previous match ended was being counted as a match, so `s/o*/-/g` over `aoc`
answered `-a--c-` where every sed answers `-a-c-`. `edit.sol`'s `:s` had had it
for as long as it existed.

**The part that transfers is why nothing had caught it.** The library's header
explains the neighbouring rule at length and demonstrates it with `s/x*/-/g` over
`abc` — and *that example is the one case that cannot show the difference*, since
the star never matches a character there, so no match has an end for a later
empty one to land on. **The documentation was careful, correct, and blind by
construction.** An example written by the author of the code shows the rule the
author was thinking about; only a stranger's program picks a case they were not.

**It is not a text-tool trick and does not run out.** `sha256sum` has published
vectors, `diff` has `diff`, a matrix multiply has numpy, a Prolog has swipl. What
the frontier loses is exactly the oracle, which is the argument for spending the
cheap ones early — [ideas.md](ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31)
surveys them.

**And better than an implementation is a number somebody printed.** The
sentence above was written on 2026-08-31 and tested the same day.
`programs/sha256sum.sol` is held against `/sbin/sha256sum` *and* against the
digests in FIPS 180-4, and the second is the stronger of the two for a reason
the first cannot fix: **an oracle can be wrong in the same direction as anything
derived from it.** Two implementations of a hash that share an ancestor share
its mistakes; a number printed in a standard before this language existed cannot
have been influenced by anything here. `programs/sha256sum/vectors.sh` is the
**second** check here that does not depend on another implementation being
right, and where such a thing is available it should be the first one written.

**The first was the [NBS Minimal BASIC Test Programs](../programs/basic/conformance.sh)**,
208 programs written at the National Bureau of Standards in 1980 against ANSI
X3.60-1978, which found seven defects in `basic.sol` that eighty-three claims
written by its author had not. That is the same idea and it was here first; what
`vectors.sh` adds is that a digest is a string, so the comparison is
**mechanical**, where the NBS suite prints what a correct result looks like for
a person to read and cannot be scored by a machine. A standard that prints
*answers* is worth more than one that prints *descriptions*, and it is worth
knowing which kind a direction offers before betting a check on it.

**It also decides what the oracle is *for*.** Held against the vectors, the
algorithm is either right or wrong. What the oracle then checks is the
plumbing — a NUL lost, a high byte sign-extended, a chunk boundary landing
inside a block, a warning that says "1 line is" where the other says "2 lines
are" — and those are the failures a standard says nothing about. Two checks
that fail for different reasons are worth more than two that fail for the same
one.

**Two corpora, and the second is the point.** `agree/` must match byte for byte.
`differ/` must **not**, and each case says at the top what each side does and why
this one is allowed to be different — so the list of divergences stops being
prose and becomes something that fails. A case in `differ/` that starts agreeing
is news too.

**Run every case both ways in.** A named file and a pipe are different code paths
here, and a program that answered two ways about the same bytes would be wrong
where a single-route check cannot look. Where the two genuinely cannot agree, the
case declares it *and bounds it*: `pipediffers:` means the pipe's answer must be
the file's plus exactly one newline, which would fail if the difference grew.

`programs/oracle.sh <name>` is the harness; it was written for sed and
generalised by its second caller rather than copied.

## An author-written corpus tests what its author thought of

**The oracle is the only check here that can find what nobody thought to look
for** — and the corpus it runs is written by the same person who wrote the
program, so it inherits their blind spots exactly.

`programs/sed/agree/` holds sixty cases and **not one of them used `\(`**. So
`sed.sol` read a group as a literal parenthesis for the life of the file, and on
a valid script came out *inverted* — substituting the line that contained the
text `(ab)c` and leaving the line that contained `abc` alone, with no error and
exit 0. Its own header had said such a script "will be refused rather than
misread". Nothing had run it.

That is not an argument against the corpus, which has earned its place several
times over. It is the reason the corpus is not the last word:

- **Write cases for what the program says it will not do**, not only for what it
  does. A refusal is a behaviour and belongs in `differ/` with its reason. The
  two that were missing are there now.
- **A claim in a header is a case waiting to be written.** Every *this is
  refused*, *this is not supported*, *this would be wrong* in a program's
  comments names an input nobody has tried.
- **Where a standard exists, it is a second author.** `sha256sum` is held to FIPS
  180-4 and `basic` to the NBS suite for exactly this reason — the NBS programs
  found seven defects that eighty-three author-written claims had missed, and
  the ratio here was two in sixty.

## A program that does not stop can still be checked — give it a deadline

**`tail -f` was nearly left out on the grounds that an oracle cannot check a
program that never finishes.** That was true and was not a reason. Start both,
feed the input on a schedule, stop them, compare what each managed to write:
fifteen lines of shell, in `programs/tail/follow.sh`.

It earned itself on its fourth scenario, finding that BSD `tail` puts a blank
line before the **first** heading when following and not when it is not — which
nothing but a check running the real thing would have found.

**The general form**: when a check looks impossible, ask whether it is the
*shape* of the check that is wrong rather than the thing being unchecked. A
deadline, a scripted key sequence ([edit.sol](../programs/edit.sol)'s 181
sessions), a pseudo-terminal — each turned something interactive or unbounded
into something with an answer.

## A sentence that was true when written is not checked by anything

**Four instances in one day, 2026-08-31, and the shape is worth more than any of
them.** Each was a statement that was true when it was written, stayed
technically true, and became misleading because the world moved underneath it.

- **`pattern.sol`'s worked example** could not show the defect it stood next to,
  and only a case its author would not have picked did.
- **[3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done)'s trigger**
  said *nothing here has a file that does not fit*. That was a fact about this
  repository's inputs rather than about the world: a sparse file is 3 GB and 8 KB
  of disk, and making one took four seconds. The entry had stood for weeks.
- **Four count markers sat on statements about past releases** in `README.md` and
  `index.md`, so a moving message count would have quietly rewritten what 0.38.0
  answered. [releasing.md](releasing.md) states that exact rule — a marked number
  is a *live* number — and it had been written for the release page and never
  applied to the README. It went unnoticed for four releases because the number
  happened not to move.
- **[ROADMAP.md](ROADMAP.md)'s own summary** said *nothing is on it* while an
  entry was being added to it.

**The habit that catches them is not a tool.** It is going to check a sentence
before repeating it, and preferring the check that could *fail*: making the file,
running the case, moving the number. The 2026-08-30 postmortem said the same
thing about five documented claims of which four were wrong, and this is the
second day running.

## An enumeration that looks complete is not a proof

**Three cases, all correct, reads exactly like all the cases**, and the second
is a far stronger claim than the first. Nothing in the sentence marks where its
edges are, so a reader — including the person who wrote it — cannot tell a
survey from an argument.

On 2026-08-31 `tail.sol` and `sha256sum.sol` both told a person at a prompt from
a pipe with `keyWaiting(0.0)`, and the reasoning was written down in three
places and called **exact rather than approximate**: an idle terminal answers
false, a pipe with data answers true, a pipe at its end answers true. Each of
those is true.

**A pipe has four states.** The fourth is open, empty and not yet finished, and
it answers false — exactly as the idle terminal does, because *is there a byte
right now* is equally false of both. So `{ sleep 1; echo hi; } | prog` took the
terminal branch, and both programs threw away the input of any pipeline slow to
produce its first byte. For as long as either had existed.

**Nothing here was going to catch it.** A pipeline typed at a prompt or written
into a corpus has its first byte ready before the program starts, so the missing
case does not occur anywhere it would be looked for. It needs a slow writer,
which is not a thing anybody constructs by accident.

**The check is not more care with the prose.** It is to go and ask what states
the thing has *from its own side* — a pipe, not the list of pipes somebody
thought of — and count them. Where that is not possible, say *these are the
cases I found* rather than *these are the cases*, so the sentence carries its
own uncertainty.

### Replacing something that works is how you find out what it was doing

The remedy that actually fired here is worth naming separately, because it is
cheap and nobody plans it.

The `keyWaiting` paragraph had been read many times and never audited — there
was no reason to audit it, since the program worked. The audit happened only
because [6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done)
built a message answering the same question, and the two answers had to be
compared. **The comparison is what asked, for the first time, what the old
spelling had actually been answering.**

So a replacement that is *only* about spelling is still worth doing, and the
argument for it is not tidiness: an old expression nobody has a reason to doubt
is exactly an expression nobody checks.

## An analogy to a measured case carries the mechanism, not the rate

**A prediction on 2026-08-31 was right about an absence and wrong about its
price**, and the way it went wrong is the useful part.

`tail -f` needs to wait. The prediction was that `shell:run("sleep 1")` would do
it and *the finding would be the cost* — reasoning from
[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done),
where the terminal's size was reachable through `stty` at 7 ms an ask and the
price was what made it an entry.

A fork of `/bin/sleep` measured **2.23 ms**, which at a one-second poll is
**0.22%**. Perfectly livable. **`stty` was a fork per keystroke and this is a fork
per second**, and the entry reasoned from one to the other because both are *a
fork where a syscall would do* — without noticing they differ by four orders of
magnitude in how often they happen.

**A cost is a property of an operation and a rate**, and the prediction carried
only the first half. When an entry argues by analogy to a measured case, the
thing to check is whether the *rate* carried over, not whether the mechanism did.

`system:sleep` was built anyway, on a weaker and truer argument: waiting is one
call to the kernel and a program should not start a process to do it. **Being
right for the reason expected would have been worth less than finding out the
reason was wrong**, and the entry keeps both halves.

## A scoping can be wrong about the order, not only the answer

[Scope before building](#scope-before-building-and-the-decision-is-separate) says
a scoping may end in *no*. On 2026-08-31 one ended in *not yet, and not in that
order*.

`tail` was scoped to be written first, on the whole-file read, so that it could
ask for a ranged one — because a program asks and a page does not, which is the
rule. **The evidence had already arrived without it**: `fileSize` answered and
`readFile` refused on a file made in four seconds.

What was wrong is sharper than being unnecessary. **A `tail` on the whole-file
read cannot call the thing it is meant to be asking about**, so it would have
re-proved a measured wall and said nothing about the shape of the fix. The
program meant to inform the design was the one program guaranteed not to.

**The question splits**: *whether* is often settled by a measurement, and *what
shape* wants a caller — and a caller has to come after the call exists. When the
evidence is already in hand, build the thing and write the program against it,
which is the throwaway rule with the order put right. Both recommendations are
kept in the entry rather than the first being overwritten, which is what that
page does with predictions.

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
