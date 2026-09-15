# Postmortem

Every defect this project has found in itself, what caused it, and — the part
worth the paper — **what found it**. The tally at the end is the only real
argument for how the work is done.

[journal.md](journal.md) is the narrative; [CHANGELOG.md](CHANGELOG.md) is what
shipped. This is the failures.

## Scope

Thirty-three, from eight days, in five cohorts that failed for five different
reasons:

- **In the compiler** — nine, five of which were latent from 0.1.0 and 0.2.0,
  and one in a test rather than the compiler, which left a directory behind
  on every run for ten days.
- **In the method** — three: a negative control that passed because `make` had
  rebuilt nothing, a reader experiment whose own prompt changed the surface
  it was measuring, and a scoping that assumed the make on the machine.
- **In the documents**, twelve: three an edit that reported success and changed
  nothing, two where no edit was attempted at all, one where a sweep looked in
  the files it remembered instead of for the claim, one where the fix falsified
  the sentence describing it, one where a file's closing sentence outlived the
  section that settled it, one where a sweep corrected a count in three
  files and missed the fourth, which spelled it with a different noun, one
  where a respelling reached the record of the respelling before it, one
  where the same respelling missed a line in the other project's front page,
  and one where a move broke forty-four links in pages no check reads.
- **In the programs** — four, found by the first real use of a thing.
- **In the reasoning** — five, where something true was written down as
  something else and had to be retracted.

---

## In the compiler

### 1. `instantiate` did not carry the `form` index

**What.** 0.5.0 gave a macro use an index saying which declaration it matched,
because a word may name more than one form. `instantiate` builds template nodes
by hand and did not copy the new field, so a form used *inside another form's
template* lost it and expansion reported `internal: 'unless' was read as a form
and is not one`.

**Cause.** Two constructors for one node kind. `parasol_node_copy` was updated;
`instantiate` was not, and nothing makes them agree.

**Found by** the 0.2.0 test *a form using a form*, on the first run after the
change. The only defect here found by a test written earlier for another
purpose.

### 2. `synchronize` could spin forever — latent since 0.1.0

**What.** After an error the statement loop calls `synchronize`, which halts *at*
a closing bracket without consuming it. That is right when something above is
waiting for it and wrong at the top level, where nothing is: the `)` left over
by any error inside an argument list was read, failed, synchronised to, and read
again. `f(#1 % #2)` with `%` undeclared was enough.

**Cause.** A recovery routine written for one caller and used by two. The
property wanted belongs to the loop — *a pass that reports an error must consume
something* — and was expressed as a rule about brackets.

**Found by a test that was itself wrong.** A new 0.6.0 test omitted the `@infix`
its body needed, took the undeclared-operator path, and hung `make test`. A
correct test would not have found it.

### 3. The pattern diagnostic did not fire when no part was read

**What.** 0.7.0 added *a pattern is made of names and \<holes\>* for
`@syntax mov <d> , <s>`. It only fired once at least one part had been read, so
`@syntax vec { <x> }` still got *needs `=>`*, pointing at the brace and saying
nothing.

**Cause.** The condition tested `parts != NULL` — a proxy for *was this a
pattern* — rather than whether the call shape had been taken.

**Found by** a question about which punctuation a dialect can claim, which meant
running the case rather than reasoning about it.

### 15. A use-after-free in the operator table — latent since 0.1.0

**What.** `parasol` segfaulted on `@use "sha2.psol"` beside `lib/control.psol` — two
real dialects in this repository, composed the way the collision rules exist to
allow.

**Cause.** `parasol_dialect_add_infix` answers the entry a redeclaration displaced,
so the reader can say *previously declared here*. It looked that entry up
**before** growing the array:

```c
const ParasolInfix *existing = parasol_dialect_infix(dialect, spelling, length);
if (count == capacity) { ... dialect->infix = parasol_realloc(...); }   /* moves */
return existing;                                                      /* dangles */
```

The caller then reads `clash->spelling` and `clash->declared_at` out of freed
memory. `parasol_dialect_add_prefix` and `parasol_dialect_add_macro` had it too;
`parasol_dialect_add_template` did not, answering no pointer. The fix is to look up
after the growth — realloc changes where the entries are, never what they say.

**Why it hid for nine versions.** It needs a collision *and* a growth in the same
call *and* a realloc that relocates rather than extends. Every example and
program in the tree composes dialects that agree, and the suite's own fixtures
are small enough that the block grows in place. `programs/digest` was the first
thing here with a dialect that redefines `+`, and its README says composing it is
a collision — but says so having reasoned about it rather than run it.

**What it says about the tests.** The regression check added with the fix
reproduces the shape and **passes without the fix in a plain build**, because
whether the stale pointer lands on freed memory is the allocator's business. It
fails, deterministically, under
`make test SANITIZE="-fsanitize=address"` — an invocation the Makefile has
documented since 0.1.0 and which nothing had been run under. A test that cannot
fail is not a test; this one needed the tool the project already had.

**Found by** checking a claim in `programs/digest/README.md` before repeating it
in another document. The claim was that composing those two dialects collides on
four operators. It collides on nine, and the compiler crashed while saying so.

### 16. Nine of Solveig's syntactic forms are not Parasol's — latent since 0.1.0

**What.** `#-1225` is an error in Parasol and a valid integer in Solveig. So is
much else. Asked whether the survey behind that had been partial, it had:
comparing every form in Solveig's grammar against Parasol, one file each, gives
**nine divergences out of eighteen**.

| form | Solveig | Parasol | |
| --- | --- | --- | --- |
| `#-45` | yes | **0.11.0** | was missing, nothing objected |
| `$FF08` | yes | **0.11.0** | was missing, nothing objected |
| `1e10`, `2.5E-3` | yes | **0.11.0** | float exponents; was missing, nothing objected |
| `"\q"` | refused | **0.11.0** | Parasol was the permissive one — see 17 |
| `#[a = b]` | yes | **0.12.0** | dictionary; not free after all — it needed a rule about `=`, not a lexer case |
| `%1011` | yes | **0.13.0** | `%` is an operator character here and is not one in Solveig; the two now share it, split on whether a binary digit follows |
| `( \| t \| … )` | yes | no | temporaries in a group; already a rough edge, now confirmed by running it |
| `@expr(…)` `@expr{…}` | yes | no | refused on purpose; see ROADMAP.md |
| `-3` | a literal | needs `@prefix -` | **cannot be had** while `-` is declarable |

**Why it is a defect and not a list of missing features.**
[GRAMMAR.md](../../docs/PARASOL-GRAMMAR.md) says everything but `operator` is Solveig's own
spelling, *so that a file can be read by somebody who knows Solveig without a
second set of habits*. [README.md](../README.md) goes further in its first
section: a module may *declare no operators at all and read exactly as Solveig
does today*. **That is false in eight ways**, and a person who knows Solveig
meets the first of them at `#-5`.

**And the claim cannot be made true as written.** Solveig's scanner is
region-sensitive: *a leading `-` belongs to the number outside a `@expr` region,
and inside one it is always the operator.* Parasol has no regions and cannot have
that rule — and it could not simply take `-3` as a literal either, because a
dialect declaring `@infix - 60 sub.` would then read `a -3` as two terms rather
than a subtraction.

**So this is the extensible-operator line again, from a direction nothing had
come from.** Not a dialect wanting to change the lexer — *Solveig's own number
syntax being something Parasol cannot copy while its operators stay declarable*.
Four of the nine are free, one conflicts, two are already-recorded decisions,
and two are consequences of a choice this project made in 0.1.0 and never wrote
down.

**Why nothing found it for ten versions.** No program here had an ordinary
negative value — a hash has none, an assembler none, a parser none, and the five
examples none — and nobody had run the comparison. `programs/ledger` is a
ledger, and the second line of its data is a refund.

**And it had already cost something, unnoticed.** `programs/digest` writes the
SHA-256 round constants as `#1116352408, #1899447441, …`. FIPS 180-4 prints them
as `428a2f98, 71374491, …`, and `$428a2f98` is what Solveig would have taken.
Sixty-four constants converted by hand, in the program whose first prediction
was *the formulas will transcribe* — and they did. **The constants did not,
and the cost never reached that program's findings**, because converting them
felt like the work rather than like a workaround.

**Five closed in 0.11.0**, and the integer literal now travels as written so a
base survives rather than being normalised — `$FF08` does not come back as
`#65288`, which is the whole point of writing it in hexadecimal.

**The whole survey, sorted by kind and with what each decision conceded, is
[COMPLETED.md](COMPLETED.md) 15.** What follows is only the part that belongs in
a postmortem.

**One of them was mis-sorted here**, and the correction is the part worth
keeping. `#[a = b]` was called free on the strength of the lexer, and the lexer
was never the obstacle: Solveig writes `pair = sum "=" expression` and settles
the ambiguity by precedence *level*, which Parasol cannot copy because a dialect
may declare `=` anywhere and `lib/clike.psol` declares it at 10. It needed a rule
saying a context shadows a declaration — the first in this language — which
landed in 0.12.0 rather than being waved through as a lexer case.

**Two are left, and neither is an oversight**: `@expr` is refused, and `-3`
cannot be had.

**Found by** two things, and the second is the one worth keeping. `#-1225` was
found by writing the fourth program, at the second line of its data. **The other
eight were found by being asked whether the first survey had been complete** —
it had not, and nothing but the question would have said so.

### 17. Parasol emits Solveig that Solveig rejects — latent since 0.1.0

**What.** `x := "a\qb".` compiles without complaint and produces a `.sol` that
`solas` refuses:

```
[q.sol:3:6] solas: unknown escape in a string; \" \\ \n \t \r are the escapes
```

Solveig's escapes are five and its grammar says so; Parasol's lexer takes `\` as
escaping whatever follows.

**Why it matters more than the other eight.** Every other divergence is Parasol
refusing something Solveig accepts, which is a smaller language and an honest
error message. This one is the other way: **Parasol accepting something Solveig
does not, and emitting it.** [README.md](../README.md) says the examples are
compiled *and run* precisely because *a front end that emits text can be wrong
in a way no unit test sees — Solveig-looking source that Solveig rejects*. This
is that, and the discipline did not catch it because no example contains a bad
escape.

**Cause.** A lexer written to be permissive where the specification is a closed
set of five.

**Found by** the same comparison as 16, which is the only place a divergence in
this direction could have shown up: it is invisible from inside Parasol, and
invisible from inside Solveig.

**Fixed in 0.11.0.** The lexer checks the five and reports anything else where
it stands, so the error lands on the `.psol` rather than on generated code.

---

### 22. A hole-kind error on a nested form named the dialect and not the file — 2026-09-03

**What.** `lib/clike.psol`'s `else` hole is typed `block`, so a C-style chain is
refused, which is intended and documented. What it says is not:

```
$ parasol chain.psol
/…/lib/clike.psol:72:43: error: 'if' wants a block here, and this is a send
 72 | @syntax if <c> <t: block>            => c:ifTrue(t).
    |                                           ^^^^^^
/…/lib/clike.psol:90:1: note: 'e' is declared to want a block
parasol: chain.psol -- 1 error
```

The error points into a **template the programmer did not write**, the note
points at another one, no expansion trail is printed, and `chain.psol` appears
only in the summary count. **There is no line in their own file to go to.**

**This is the exact failure the project says it is built against.** `README.md`,
first commit:

> A language whose syntax is declared per module has one characteristic way of
> failing: somebody writes one thing, is shown an error about another, and
> cannot get from the second back to the first.

**Cause, read in the source and not inferred.** `check_arguments` in
`parasol/src/expand.c` reports `parasol_node_extent(argument)`. When the argument is
an ordinary node that is right — `if (x > #9) x.` names `chain.psol:4:13` and
puts the caret under the `x`, which was checked. When the argument is **itself a
use of a form**, expansion has already replaced it, and the node's extent is the
span of the template it came from. `note_trail(expander, use)` is called but
prints nothing, because the trail belongs to the *inner* expansion and the node
being reported is the *outer* use.

**Why nine versions missed it.** Every hole-kind failure in the repository's
tests and examples has a plain node in the hole. **A form in a hole is the case
a dialect's own users hit and its author does not**, because the author knows
the chain wants braces and never writes the version that does not.

**Found by** checking a prediction rather than asserting it, while designing
[second-reader.md](second-reader.md) — whose fourth prediction was going to be
*the diagnostic will not name the fix* and had to become something else. It is
the third defect in four days found by that habit, after the escape-set
divergence and the 0.1.0 segfault.

**Fixed in 0.15.0.** `expand_node` keeps each argument's extent *before* the
loop that replaces it, and `check_arguments` reports that. The check still runs
against what the argument **became** — `if (b) { … }` in an `else` genuinely is
a send by then, and the refusal is correct — so only the position moved.

**Three checks in `tests/test_expand.c` hold it**, and the shape of the three is
the point: the severe case, where the template *builds* the offending node; the
mild one, where a substituted argument keeps its own span but the caret lands on
the wrong part of it; and the plain case, which was always right and is what a
fix could break. **The check that was already there could not have caught any of
them** — `a form as an argument is checked as what it becomes` asserts that
something is rejected, and rejection says nothing about where the caret went.

### 23. A negative control passed because `make` did not rebuild — 2026-09-03

**What.** With 22's fix written and its tests passing, the tests were run against
the *unfixed* compiler to check they could fail — the discipline
`tests/test_expand.c` states in its own opening comment, that a check must fail
if the thing it tests is removed. The sequence was `git stash push`, `make`, run.

**It reported `60 checks, 0 failed`**, and the conclusion drawn, in writing, was
that the new checks did not catch the bug. That conclusion was wrong. `make`
had rebuilt nothing: `git stash` restores a file with its **original
timestamp**, which is older than the object built from it, so the dependency
rules had nothing to do and the binary under test was still the fixed one.

**Cause.** A negative control compares two builds and `make` decides whether a
build happened by comparing times. Any operation that moves a source file
*backwards* in time — `stash`, `checkout`, `show >`, restoring from a copy —
defeats it silently, and the failure mode is the worst available: **the control
passes.**

**What it nearly cost.** A test committed as verified, having never run against
the defect it was written for. Rerun with `make clean` between the two builds,
the same checks failed at once and named the exact wrong positions — `<test>:1:26`
inside a declaration for the severe shape, `<test>:3:12` for the mild one.

**And it improved the test.** The first attempt used a form whose template is a
bare hole, so the substituted argument kept its own span and only the *column*
was wrong. Watching it fail showed that was the mild shape and not the reported
one, and a third check was added for a template that **builds** the node, which
is the case that names another file entirely.

**Found by** not believing a control that agreed with the code under test.

### 24. A file was its path, so one file could be two — 2026-09-04

**What.** `@use` decided whether it had already read a file by comparing path
strings. `x.psol` and `./x.psol` resolve to one file and are two strings, so both
rules built on that comparison failed, in opposite directions:

**A diamond spelled two ways collided with itself.** Two dialects using a third,
one arm writing `base.psol` and the other `./base.psol`, read it twice:

```
d/./base.psol:1:8: warning: operator '+' was already declared by d/base.psol
                  -- this one wins, and nothing else will say so
d/base.psol:1:1: note: declared here
```

Correct code, a spurious warning, and the warning names one path as the offender
and **the same file's other spelling** as where it was first declared. The
output was right — the declarations are identical, being the same line of the
same file — so this only ever cost a reader their confidence in the collision
warnings, which are the 0.4.0 feature the whole composition story rests on.

**And a cycle spelled two ways was not a cycle.** `a.psol` using `./b.psol` using
`./a.psol` never matched the cycle check, and every hop appended another `./`, so
no path ever repeated. What stopped it was the recursion limit:

```
.../cyc/./././…/a.psol:1:1: error: @use is nested more than 64 deep
  ... used from .../cyc/././././…/b.psol, line 1        (× 64)
```

The right diagnostic exists and did not fire; the reader gets the wrong one,
under sixty-four lines of `./././` trail.

**Cause.** One string answering two questions. `source->path` is what a
diagnostic must show — `examples/../lib/control.psol` is where somebody can
actually look — and it was also being asked *which file is this*, which is a
different question with a different answer. `parasol_unit_loaded`'s own comment
said "already read under this **exact path**" and the word `exact` was doing the
work of a caveat nobody had priced.

**Fixed in 0.17.0.** A `ParasolSource` carries `identity` beside `path`:
`realpath`, falling back to a copy of the path when there is nothing on disk to
resolve. Display is unchanged — the cycle error still names `./././a.psol`,
because that is what the file says. Both comparisons moved to `identity`.

**What the limit was doing.** It is the reason this is a wrong diagnostic and
not a hang, and it held exactly as designed. It is also why the defect could sit
here unnoticed: **a guard that turns an infinite loop into a bad error message
makes the bug survivable and therefore quiet.**

**Found by** checking a rough edge instead of accepting how it was filed.
`README.md`'s known-gaps table carried this as cosmetic — *`examples/../lib/control.psol`
is what a diagnostic shows, and two spellings of one file are two files* — and
already named `realpath` as the fix. **The sentence was right and the severity
was wrong**: the entry described the display and never asked what *else*
compared those strings. Nothing else on that list has been checked that way.

### 30. A test that cleaned up from a list, seven files behind what it wrote — 2026-09-14

**What.** `test_use` writes its fixture files into a `mkdtemp` directory and
removes them at the end from a hand-kept list of names, then `rmdir`s the
directory. The cases that came in with 0.17.0 on 2026-09-04, a file being its
identity and not its path, added seven files after the list was written and
the list was not, so `rmdir` failed quietly, every run for ten days left a
`parasol-test-*` directory behind, and there were fifty-five of them in
`/tmp` when this was found.

**Cause.** The list is the same thing as every other hand-kept list this
project has recorded against itself, a copy of a fact that lives somewhere
else, and it went stale the way they all do. The failure was invisible
because `rmdir` was not checked and a leftover directory fails nothing.

**Fix.** The test reads its directory and removes what is there
(`a9f299c`). A test that wants to know what it wrote asks the filesystem.

**Found by** listing `/tmp` after running the moved test, to confirm the
move had not broken the cleanup. It had not; the cleanup had been broken
since before the move, and nothing but a look at the directory could have
said so.

### 32. The build the scoping assumed was not the build on the machine — 2026-09-14

**What.** Step 2's scoping said a `$(BUILD)/parasol/%.o` rule would win over
the generic `$(BUILD)/%.o` because GNU make prefers the shortest stem. The
first build under the merged Makefile compiled a Parasol source with
Solveig's include path: macOS ships GNU make 3.81, which takes the first
matching pattern rule in file order, and the shortest-stem rule is 3.82's.

**What it cost.** One failed build, read and understood in a minute, and the
Parasol section sits above the generic rule with a comment saying why. Had
the rule been placed the other way round and the build *succeeded*, which on
a 4.x make it would have, the boundary the section exists to keep would have
been open on every macOS checkout and closed on every Linux one, and nothing
in the suite would have said so until `nm` did.

**Cause.** A claim about the tool from memory of its manual rather than from
the tool: `make --version` was never run.

> A scoping that names how a tool behaves has checked the tool on the
> machine, or it says which version it read about.

**Found by** the build failing on the first try. The reverse case, the build
succeeding for the wrong reason, is what the `nm -g` check in `test` is for,
and it was written the same hour.

---

## In the documents

### 4. Three roadmap edits that did nothing

**What.** Between 0.2.0 and 0.5.0, three replacements in `ROADMAP.md` matched
nothing. The file went on calling the expander *next* for four versions after it
shipped, and went on asking the collision question two versions after 0.4.0
answered it. Commit messages said otherwise.

**Cause.** The original was written with em dashes and the replacement with two
hyphens. **A replacement that matches nothing is not an error; it is a no-op
that reports success.** Once the first had failed, every later one was matching
against text that had never existed.

**Found by** the user asking *what's next?*, which meant reading the file rather
than remembering it.

### 5. A `.gitignore` edit that did nothing

**What.** The entry for `programs/ember`'s generated `.s` and `.out` never
landed, so both were staged with the commit.

**Cause.** The same class as 4 — anchored on Solveig's `.gitignore` wording
rather than Parasol's.

**Found by** reading `git status --short` before committing.

### 6. A blind global replace mangled a comment

**What.** Renaming `&&` to `/\` in `emberc.psol` was done with an unanchored
substitution and caught a shell command inside a header comment:
`> fizzbuzz.s && cc fizzbuzz.s` became `/\ cc`. The comment is how somebody runs
the thing by hand.

**Cause.** A rename applied to a file rather than to a language.

**Found by** grepping for the old spelling after the commit had already gone out.

### 13. A number that was true when it was written — 2026-09-01

**What.** `ROADMAP.md` said `@language` had been inert *eight versions in*. The
changelog had nine, 0.1.0 through 0.9.0. The sentence was written at 0.8.0, and
0.9.0 landed beside it without disturbing it.

**Cause.** A new class in this cohort, and the reason the cohort is now four.
Defects 4, 5 and 6 are edits that ran and did the wrong thing. **Here no edit
was attempted at all** — the number was a fact about a second document, correct
on the day it was written, with nothing in either file to notice when the other
one moved. `edcf4a0` the day before was the same shape, a heading left over a
body that had been rewritten under it, and it was fixed without being recorded
here.

**Found by** counting the versions in `CHANGELOG.md` while writing a changelog
entry — that is, by having to state a number that the roadmap had already
stated, and comparing them.

**What is real.** A cross-document fact has no owner. `9` lives in
`common.h`, the version list lives in `CHANGELOG.md`, and the sentence that
counts them lives in `ROADMAP.md`; nothing links the three, so the count is
correct only until the next release. The cheap defence is the one that caught
it: any claim about *the state of another document* is re-derived when it is
read, not trusted.

### 19. Nine of 13 in one day, and a defence that was not enough — 2026-09-02

**What.** Entry 13 above names the class and prescribes a defence: *any claim
about the state of another document is re-derived when it is read.* On a day of
five versions, nine instances landed anyway — the last of them found while
writing this entry.

| | |
| --- | --- |
| `journal.md` | "five commits, one version" — corrected to nineteen, then to neither |
| `journal.md` | the sentence *this opening carries only what stopped changing*, written to fix the above, and wrong about the version range in the same paragraph |
| `README.md` | `## What 0.10.0 is not`, four releases behind |
| `README.md` | *Known gaps* listing dictionary literals, which landed in 0.12.0 |
| `README.md` | the folding claim carrying one measurement when `ledger` had produced a second that argues against it |
| `README.md`, `REFERENCE.md` | `does-it-pay.md` described as *what four programs say* when it covers five |
| `POSTMORTEM.md` | this file's own tally: "the four programs written in the language", when there are five |
| `programs/digest/README.md` | "twenty-three `bitAnd`s" and "none", against 18 masks and one byte extract when counted |
| this file | "109 unit tests", against 144 — found while writing this entry, which is the ninth |

**Cause.** 13's defence works at *read* time, and **nobody re-reads a document
that is not being read.** Every one of these sat in a file nobody had reason to
open: the README's version heading is not consulted when adding a version, and
the *Known gaps* table is not consulted when closing a gap. The defence covers
the case where a stale claim is in front of you and not the case where it is
somewhere else, which is every case that matters.

**And it is worse than a static fact going stale**, which is 13's shape. Two of
these were **wrong when written**: the journal's second correction was wrong in
the sentence claiming to fix the first, and `digest`'s counts were wrong in both
directions on the day they were counted. A defence at read time cannot catch a
number that was never right.

**What worked.** Reading everything once at the end, whether or not anything was
suspected. That found four of the eight in about ten minutes, including two
nobody would have opened for months. It is now
[conventions.md](conventions.md)'s standing agreement, because a defence that
depends on suspicion is not a defence — and the ninth instance above was found
by the sweep finding a stale number in the paragraph describing the sweep.

**Found by** closing out the day, which is the only reason any of it was looked
at.

### 20. The sweep that found 19 was itself incomplete — 2026-09-02

**What.** 19 landed the standing agreement that everything is read once at the
end of a day. The next session's closeout, the same day, corrected **fifteen**
claims. They divide, and the division is the finding.

**Six were stale before 19's sweep ran, and it missed all six.**

| | |
| --- | --- |
| `targets.md` | *does-it-pay.md is what four programs have said* — the **same sentence** 19 corrected in `README.md` and `REFERENCE.md`, in a third file it did not open |
| `journal.md` | the suite "ended at 58, 6, 60 and 11", which is 135, six paragraphs above the same entry reporting 144. Nothing had touched `tests/`; the figure was 69 and had been all day |
| `conventions.md` | "all **three** programs in `programs/`", against six |
| `conventions.md` | "all **three** programs" again, in *What the build guarantees* |
| `does-it-pay.md` | the heading **What the four declared**, over a table of five rows |
| `REFERENCE.md` | `lib/clike.psol`'s `!=`, `<=`, `>=` as *templates over the three above* — plain messages since 0.6.0, **wrong for eight versions** |

**Nine more went stale during this session's own work** — a sixth program, and
three operators added to `lib/arith.psol` — and were caught the same day:
`REFERENCE.md`'s `does-it-pay.md` cell (corrected *four*→*five* the night
before, stale again at *six*), four counts inside `does-it-pay.md` itself,
*optional and repeated parts declined twice* in `conventions.md`, `COMPLETED.md`
twice and `ROADMAP.md` once, and `REFERENCE.md`'s sentence naming clike's
comparison set as what still differs from arith.

**Cause.** A sweep is only as good as its query, and 19's **searched the files
it remembered rather than the claim.** Three files said *does-it-pay.md covers N
programs*; it opened two. Nothing about reading everything catches that, because
`targets.md` **was** read — it was read for what it says about targets, which is
what it is for.

> **A claim that appears in three documents is one claim, and it is found by
> grepping for the claim, not by opening the documents.**

**Three of the six were in `conventions.md` and `does-it-pay.md`** — the file
that holds the sweep agreement, and the file that holds the project's own
answer. A document stating a rule is the least likely of all to be opened while
the rule is being applied.

**And one was wrong when written, again.** 19 recorded that two of its nine were
wrong on the day they were counted, and then carried a number that was wrong on
the day it was counted — in the paragraph about the tests, in the entry about
numbers being wrong. The suite prints its four figures on every run. The line
was typed rather than read off one.

**The clike row is the different one.** Not a count going stale but a
**description of a mechanism that changed underneath it**: clike moved from
templates to plain messages in 0.6.0 and the table describing it did not. It
survived every sweep because nothing about it looks like a number, and it was
found only because that table was being edited for another reason.

**What worked.** Grepping for the claim. One search for *five programs* returned
every instance at once, including three in `does-it-pay.md`; one for *declined
twice* returned four files. It is [conventions.md](conventions.md)'s standing
agreement now, beside the sweep it sharpens.

**Found by** the next session's closeout, one sweep after the sweep that missed
them.

### 21. Correcting a claim falsified the sentence describing it — 2026-09-03

**What.** 20's own write-up said, of the journal entry below it:

> The entry below **reports** the suite as "58, 6, 60 and 11", which is 135 …

and the same commit changed that entry to read 69. **The description was false
the moment it was committed**, and by the edit it was describing.

Two more of the same shape were in the `programs/prose` CHANGELOG entry, which
still read *`lib/arith.psol` has no `<=`* and *one is still not enough* — both
overtaken by `programs/basic` the same evening, in a commit that never opened
that entry.

**Cause, and it is not 19's or 20's.** Both of those are about a claim going
stale while nobody looks. This one is the opposite: **the claim went stale
because somebody did look, and fixed the thing it described.** A sentence
written in the present tense about another document's *current* state has a
lifetime of one edit, and the edit that ends it is usually in the same commit —
because describing a defect and fixing it are the same piece of work.

> **Write what a document *read*, not what it *reports*.** A record of a defect
> is history the moment the defect is fixed, and past tense survives the fix.

`journal.md`'s line now reads *the entry below **read**…*, and says the
correction stands in place. The two CHANGELOG claims moved to past tense with a
pointer to the entry that closed them.

**And the ritual is not about the day's work.** This closeout ran on a day with
no commits in it — the previous day had already been closed and pushed — and
found three defects anyway. **A sweep audits the documents, not the day**, which
is an argument for running it even when there is nothing to write up, and the
reason [conventions.md](conventions.md) now says so.

**Found by** a closeout run on an empty day, after being told there was nothing
to close out.

### 25. A document's last sentence outlived the section that settled it — 2026-09-04

**What.** [second-reader.md](second-reader.md) ends on *correcting for it is
what turns the third finding above from an inconvenience into the thing to fix
first* — the substrate documentation gap, written about run 1 and true of it.
Run 2 measured the one-line fix at **zero probes** and recorded the reader
calling `REFERENCE.md`'s new section *the decisive signpost*. That is sixty
lines above the closing sentence, which carries no date and no tense marking it
as run 1's.

**What it cost.** On 2026-09-04 a session read the file to answer *what is
outstanding*, reached the end, and reported the substrate gap as the next thing
to do. It was wrong, and the document is why: the last words in a file are what
a reader carries away, and these described a state two sections had already
changed.

**Cause.** The same one as 19, 20 and 21, arriving from a new direction. Those
are a claim about *another* document going stale. This is a claim about **the
same document**, overtaken by a section appended below it — the file grew a
second run and the closing paragraph was not re-read against it.

> 21 said *write what a document read, not what it reports*. The other half is
> the one this cost: **a recommendation is a claim about the present, so it
> needs the tense that says when it was made.**

**Fixed** in place, with the run-1 paragraph kept — it is what run 1 cost and is
worth keeping — and the clause given the tense it needed.

**Found by** a reader acting on the document and being contradicted by the rest
of it. Not by a sweep: three closeouts on 2026-09-03 grepped `docs/` for stale
claims and none of them read this file's last paragraph against its own middle.
**A sweep looks for a claim it can check against something else; this one is
only wrong against a later section of itself.**

### 28. A count with two nouns, and a sweep that knew one of them, 2026-09-12

**What.** `README.md`'s *Where to start* opened: *Two readers who had never seen
this language were put in front of it, and neither opened this page.* Written at
10:42 on 2026-09-04 in `6bd7ef4`, after runs 1 and 2, and true of them. At 11:33,
`dceee92` recorded run 3: that reader opened the page **first**, met *Not here*,
and stopped, which [second-reader.md](second-reader.md) calls the first evidence
that any part of the README has been load-bearing. The same commit swept the
tree for the stale count, found *two strangers* in `does-it-pay.md`,
`REFERENCE.md`, `targets.md` and the README's own table of documents at line
721, and corrected all four; `d01ad10` moved them to *four* at 11:55. Line 37
said *Two readers* and was reached by neither sweep, nor by `62b8e06`'s five
overtaken claims at 12:01.

**What it cost.** Nothing recorded. Run 4 was handed `README.md` after the
sentence had gone stale, and `second-reader.md` does not say whether that reader
opened it. What it stood to cost was the next reader being told, by the page
they were reading, that nobody reads it, on the strength of a count the same
file's foot had already moved past twice.

**Cause.** 13's class, not 25's: a count that is a fact about another document,
with nothing in the sentence to notice when the other document moved. 25's
sentence disagreed only with itself; this one disagreed with `second-reader.md`
and with line 721 of its own file. What is new is that the defence 20 wrote
into [conventions.md](conventions.md), *grep for the claim and not for the
documents*, was applied that day and did not reach: the claim was spelled
*two strangers* in four places and *Two readers* in one, and a grep for the
phrase found the phrase.

> A count is a claim about a thing, not about a phrase. The sweep that corrects
> one spelling of it has not corrected the count until it has looked for the
> thing counted, under every noun the documents use for it.

**Fixed** in place on 2026-09-12: the first two readers as they were, the third
dated, and no total, since a total is the count that went stale and
`second-reader.md` declines to put run 4 on the reader axis at all.

**Found by** an audit eight days later, reading the sentence against
`second-reader.md`'s run count while checking that the section's three file
references resolved. That is 13's defence, a claim about another document
re-derived when read, working for the reason 19 says it usually does not: the
sentence was being read for something else.

**This entry's first draft placed the corrected count six lines below the
sentence**, in the table under *Where to start*, having read a diff hunk's
header as that table. The hunk was at line 721, some seven hundred lines away,
and the draft's cause, adjacency, was built on the misreading. A review before
the commit found it and the entry was rewritten. It is noted here because a
fact about a diff stated from a glance at the diff is the class this cohort
collects, one level up.

### 29. A respelling that reached the record of the previous respelling, 2026-09-14

**What.** The rename from Proto to Parasol was four substitution rules run
over every tracked text file under the directory, with two protections: a
line naming *Phoenix* kept its *Proto*, and `.proto` kept its `t`, that
being Protocol Buffers. The record of the first rename, on 2026-09-01, is
mostly lines that do not say *Phoenix*. So `COMPLETED.md` 13 came out saying
that **`Pro`/`pro_`/`PRO_`, files `.psol`** *keeps the three-letter
abbreviation `phx_` had*, and the changelog's *Phoenix is Proto* entry that
**the extension is four characters either way, so the suffix arithmetic in
`default_output_path` is untouched**, on the same afternoon the arithmetic
was changed because `.psol` is five.

**What it cost.** Nothing shipped. Four passages, in the changelog, COMPLETED
13, POSTMORTEM 14 and the journal's 2026-09-01 morning, were put back from
`HEAD` before the commit, and [conventions.md](conventions.md) now says they
keep the old name on purpose.

**Cause.** A rename rule is a rule about the present tense. A record of a
choice is in the past tense and quotes the thing chosen, and the protection
written for it, *a line that says Phoenix*, was a proxy for *a line about the
first rename* that held for the sentences with the old-old name in them and
for none of the others. The precedent was no help: on 2026-09-01 there was no
earlier rename to protect, so the respelling could be whole and the entry
could say so as a virtue.

> A record that quotes a name keeps the name it quoted. A respelling that
> cannot tell a mention from a use has to be read where the records are,
> not grepped.

**Found by** reading the residue. The rules left a short list of lines that
still said *Proto*, all of them protected on purpose, and reading the
protected lines in their paragraphs showed the unprotected sentences beside
them saying things that were no longer true. The grep found what it was
asked for; the paragraph around it is what found this.

### 31. The rename missed a line in the other project's front page — 2026-09-14

**What.** Solveig's `README.md`, in the paragraph on why Parasol is inside
the tree, kept a pipeline line reading `proto vectors.psol -o vectors.sol`
through the rename that made `.psol` the extension: the extension was
respelled on the line and the command was not. Beside it, *six programs are
written in it* with six named, on the day a seventh had existed for a day.

**Cause.** The rename's rules were run over the files under `parasol/`; the
one paragraph about Parasol in Solveig's own front page was outside the
directory and was edited by hand for the extension only. [29](#29-a-respelling-that-reached-the-record-of-the-previous-respelling-2026-09-14)
is the same day's other rename defect, the rules reaching too far; this is
the hand not reaching far enough.

**Fix.** `parasol`, and seven programs (`b4b4ba0`).

**Found by** reading the paragraph in order to add a sentence to it. The
document checker runs the fenced blocks in `README.md`, but this one is a
`sh` fence, which is the escape for a transcript, so `proto` was never run.

### 33. A move broke forty-four links in pages nothing reads — 2026-09-14

**What.** Step 4 moved the seven programs from `parasol/programs/` to
`programs/`. Each program's README reached Parasol's documents as
`../../docs/`, which from the new place is Solveig's `docs/`; four of the
targets, `ROADMAP.md` and `GRAMMAR.md` twice each, resolved there to the
wrong document, and the rest to nothing. Parasol's own `REFERENCE.md` and
front page reached the examples and programs at their old places. Forty-four
links, and the suite green throughout.

**Cause.** `programs/expect.sol` checks every link in `docs/`, `README.md`,
`index.md` and the `.sol` files, path by path, and reports the number; the
seven READMEs and everything under `parasol/docs/` are outside that set, so
a move that would have turned the suite red anywhere else turned nothing.
The plan for step 4 had listed what enumerates the moved files and had not
asked what does *not*.

**Fix.** Repointed (`6cae6a0`). The lasting fix is step 5's first sub-step:
the checker reads every `README.md` under `programs/`, and Parasol's pages
move to where it already reads.

**Found by** resolving every link in Parasol's pages by hand with a shell
loop, while scoping step 5 and counting what the move of the documents
would break. The count was for the future; it found the present.

---

## In the programs

### 7. `skip <cls: literal>` was typed from the author's examples

**What.** `programs/grammar`'s toolkit typed five holes `literal` because every
use imagined was a literal. The first real grammar wrote `skip blank`, naming a
string it had bound, and was refused by its own toolkit.

**Cause.** A kind is a promise extracted from the *caller*. Typing it from the
uses you have imagined makes a dialect narrower than the thing it is for.

**Found by** the first grammar written with it, four minutes after it existed.

### 8. `peekAt(#2)` was off by one

**What.** `programs/ember`'s lexer produced `<` and `=` as two tokens instead of
`<=`.

**Cause.** `scan:peekAt(#0)` is `peek`, and the code assumed one-based.

**Found by** printing the token stream and reading it, before the parser existed.

### 9. Six precedence bugs in one file

**What.** `t:kind == 'op:and({ … })` sends `and` to the *symbol*, because sends
bind tighter than operators. Six of them in `emberc.psol`.

**Cause.** The standing cost of putting operators on a language whose core is
sends. Nobody's defect.

**Found by** running it — every one of them at run time, because they are type
errors and not syntax errors. **This is the finding that became 0.7.0**: the
right answer was to declare `and` and `or` as operators, which needed operator
templates, which did not exist.

---

## In the reasoning

### 10. The `else` branch that silently did nothing

**What.** `lib/clike.psol` first declared `if <c> <t: block> else <e>` untyped so
that `else if (…)` would chain, with the template wrapping: `c:ifElse(t, { e })`.
When the branch is *already* a block that gives `{ { … } }`, and the outer block
answers the inner one rather than running it. The else branch did nothing.
`examples/clike` printed `#54` where `#40` was right. It compiled, it ran, and
nothing failed.

**Cause.** A template cannot branch on what its hole turned out to be, and a
hole's kind is one choice with no alternation — no way to say *a block, or
another use of me*. Wanting both, the first draft took neither.

**Found by** working the arithmetic out by hand rather than trusting that a
program which ran had run correctly.

### 11. A finding published twice that was not a finding

**What.** `programs/ember` reported that a form's trailing hole swallows a
postfix send; `programs/grammar` reported that it swallows an infix operator.
Both were written up as limitations of Parasol, with a sketch of a fix, in two
READMEs and two commit messages.

**Neither was a limitation.** A call ends at its closing parenthesis, so
anything after it applies to what it answered. `emit`, `at`, `eat`, `skip`,
`take` and `apply` are applications and belonged in the call shape.

**Cause.** `programs/ember`'s own README states the rule — *a pattern for
something that reads as a step, a call for something that reads as an
application*. `programs/grammar` was written afterwards, by the author of that
sentence, and got it wrong in five forms. **The rule was in a program's note and
not in `GRAMMAR.md`**, where somebody choosing a shape would look.

**Found by** re-checking a claim before recommending a feature built on it.

**What is real**, and is now the entry: choosing the shape wrongly is *silent*.
Both readings are legal, so nothing at the declaration can warn.

### 12. A precedence declared on the wrong rung

**What.** `programs/digest/sha2.psol` declared `*` and `%` at 60, the rung `+` is
on. `at + i * #4` therefore parsed as `(at + i) * #4`, and the message schedule
read the wrong bytes of every block.

**It compiled, and it ran.** What stopped it was `index #65 is out of bounds for
an array of size 64`, four calls deep in generated Solveig, pointing at a line
of `.sol` that no one wrote.

**Cause.** A module declares its own ladder, so there is no ladder to be wrong
against — `@infix * 60` is as legal as `@infix * 70` and means something
different. `lib/arith.psol` puts `*` at 70 and this file did not copy it, being
standalone on purpose.

**Found by** running it. No test could have: the file is its own authority on
what its operators bind like.

**What is real**, and it is 11's shape one level over: choosing a *precedence*
wrongly is as silent as choosing a *form's shape* wrongly, and for the same
reason — both readings are legal, so nothing at the declaration can warn. The
difference is that a wrong shape usually fails at the use, and a wrong
precedence computes a different number and keeps going.

### 14. A name doing two jobs, read as doing one — 2026-09-01

**What.** Told the project was renamed Phoenix -> Proto to mark a prototype
restart, the first pass renamed the repository and left the language alone:
`phx_`, `Phx`, `PHX_` and `.phx` were held back on the reasoning that *Proto*
described the project and *Phoenix* was still the name of the thing being built.
That distinction was written down as a standing note. It survived about an hour,
until Hans said the language was Proto too.

**Cause.** "Phoenix" named two things — a repository and a language — and the
instruction was about one of them without saying which. Renaming a repository
and renaming a language are both ordinary readings of *rename the project*. The
error was not picking the wrong one; it was **recording the pick as settled** in
a durable note instead of asking a question that would have cost one line.

**Found by** Hans stating the intent plainly in the next message.

**What is real**, and it is why this is written down when it cost nothing: an
inference and a fact are indistinguishable once they are in the same document.
The note read like something Hans had said. Defect 11 is the same failure with
the roles swapped — there, a claim was published where somebody could go back
and disagree with it, and that is what saved it. **An inference is recorded with
the question it answered, or it is asked instead.**

### 18. An impossibility asserted in three places that was not one — 2026-09-02

**What.** `README.md`, `parasol/src/lex.c` and [COMPLETED.md](COMPLETED.md) 12 all
said, in nearly the same words, that a dialect cannot declare `|` because
`{ a | b }` would then have two readings. Entry 12 put it as *"naming the
ambiguity does not decide it"*. It can be declared. A second session built it —
two hunks in `reader.c`, **no change to the lexer** — and the whole suite passed
with every block form intact.

**Cause.** Two questions run together and one answer given to both. *May `|`
join the operator characters?* is about the character set, and the answer is no
and always was: characters in that set run together, so a `|` there would make
`|=` a spelling and `{ a | b }` a guess. *May `|` be declared?* is a different
question — a bar is a token of its own, and a parser may look one up without it
entering the set at all. Answering the first was taken to have answered the
second, in three files, for nine versions.

**And the ambiguity really does have a resolution**, which is the part that
should have been visible: `{ a | b }` is a parameter and a body **by rule**, and
a bar is an operator everywhere a block is not reading one of its own, escaped a
bracket down as `{ (a) | b }`. **Parasol adopted exactly that shape of rule for
`#[k = v]` in 0.12.0, four hours before this was disproved** — a context
outranking a declaration in one narrow place. The mechanism was in the language
and in that morning's commit message, and the argument against `|` was not
re-read in the light of it.

**The cause was also misattributed in the other direction**, and that belongs
beside it: the session that built it reported having removed *Solveig's*
constraint. It removed nothing of Solveig's. `lex.c` was untouched, `|` is still
`PARASOL_TOK_BAR`, and Solveig has the identical `{ a | b }` and settles it the
identical way. **What stands in the way of `|` is Parasol's own block syntax**,
and neither reading of the problem had said so.

**Found by** somebody building the thing that could not be built. Entry 11's
lesson, second instance and better: a claim was written down in three places
where somebody could go back and disagree with it, and somebody did.

### 26. A rule generalised from one reader, against this project's own bar — 2026-09-04

**What.** Run 2 of the second-reader experiment produced a sentence, and it was
promoted to a headline rule in four documents the same evening —
[ROADMAP.md](ROADMAP.md), [does-it-pay.md](does-it-pay.md),
[CHANGELOG.md](CHANGELOG.md) and [second-reader.md](second-reader.md):

> A limitation explained where it is declared is not a limitation a reader pays
> for. It is one its author paid for once.

**Run 3 contradicted it.** The `print`-is-a-repr trap is explained at the line
it is about, in `examples/clike.psol`, and has been since run 1. The third reader
**read that comment, quoted it back accurately, wrote `:print` anyway**, and got
`#3` where `3` was wanted. Their words: *the warning didn't fully land until I
saw the actual output.*

**Cause.** One instance, one limitation, one reader — generalised into a rule
about limitations in general. The instance it came from is a **refusal**: a
reader must choose to type `else if`, and a warning read beforehand removes the
option. The instance that broke it is a **silence**: `:print` compiles, runs and
produces plausible output, so the warning describes something the reader cannot
recognise until they have already paid for it.

> **A warning prevents a failure you would have chosen. It does not prevent one
> you would have walked into believing you had succeeded.**

**The bar this cleared and should not have.** `conventions.md` states *a surface
does not grow without a customer*, and ROADMAP's own `<=` entry spells out that
**one customer is not enough** — the rule this repository applies hardest, to
features. It was not applied to a *conclusion*. A sentence that reads well is
exactly the kind of thing that gets promoted on one instance, and it went
straight into the page that argues the project pays for itself.

**Fixed** by narrowing it where it is stated rather than deleting it: it holds
for a refusal, and `does-it-pay.md`'s silence category is where the exception
was already documented under another name.

**Found by** the third reader run, which was designed to measure something else
entirely — 0.16.0's prescriptive diagnostic, which a fourth run then also failed
to reach, and which is unmeasured for good now rather than pending.
**Every prediction aimed at the diagnostic was wrong or untested, and the
finding came from the one prediction written down as a hedge**: *if the reader
brackets everything anyway it will be because the example braces every body, and
that is a result about examples rather than about the diagnostic.*

### 27. The experiment's own instructions were part of the surface it measured — 2026-09-04

**What.** Reader runs 3 and 4 were handed a three-command toolchain in the
prompt:

```
parasol FILE.psol -o FILE.sol
solas FILE.sol -o FILE.sob
solvm FILE.sob
```

**`README.md`'s own quickstart passes `--map`, and that one does not.** Run 4's
reader hit a runtime error naming a line in the *generated* `.sol`, had no map
to get back with, and the write-up was one edit away from reading that as a
reader's choice. It was not. **They were told to invoke it that way.**

**Cause.** The design fixes what the reader is *given* — every document, the
dialect, the example, all of it held constant and varied deliberately — and
treats the invocation as plumbing. It is not plumbing. `--map` is the switch on
one of the two mechanisms this project names as standing between a reader and
the failure that kills syntax-extension systems, and the experiment turned it
off in the prompt without noticing it had made a choice.

> **What the experimenter hands over is part of the surface under test.** A
> published quickstart and a prompt's convenience commands are two different
> surfaces, and only one of them is the thing being measured.

**What it did and did not cost.** The finding survives: without a map, a runtime
error names generated source and there is nothing to get back with, and the map
recovers it exactly when present. What does **not** survive is any claim about
whether a reader would omit `--map` on their own, and `README.md`'s *the default
should probably change* is left exactly as unsettled as it was.

**Found by** checking the prompt against the README while writing up a finding
that depended on the difference. The run's own result made the instructions
worth reading, which is the only reason they were.

**Not fixed by editing the past runs.** Runs 3 and 4 stand as they were
conducted, with this recorded against them; a fifth would use the published
invocation. That is the same rule as any retracted finding here — it is
corrected where it stands rather than made never to have happened.

---

## The tally

| What found it | |
| --- | --- |
| A test written earlier, for something else | **1** |
| Looking at the directory a test had just cleaned up | **1** |
| The build failing on the first try | **1** |
| Reading a paragraph in order to add to it | **1** |
| Resolving every link by hand while counting what a move would break | **1** |
| A test that was itself wrong | **1** |
| Writing a real program in the language | **5** |
| Checking output by hand rather than trusting a clean run | **2** |
| Reading a document because somebody asked a question about it | **2** |
| Re-checking a claim before acting on it | **1** |
| `git status` before a commit | **1** |
| Having to restate a number another document already stated | **1** |
| The user saying plainly what had been inferred | **1** |
| Checking a document's claim before repeating it elsewhere | **1** |
| Being asked whether a survey had been complete | **2** |
| Somebody building the thing that could not be built | **1** |
| Reading everything once at the end of a day | **1** |
| Grepping for a claim rather than opening the documents | **1** |
| A closeout run on a day with no work in it | **1** |
| Checking a prediction instead of asserting it | **1** |
| Not believing a control that agreed with the code | **1** |
| Checking a rough edge instead of accepting how it was filed | **1** |
| Reading a document to act on it, and being contradicted by the rest of it | **1** |
| A reader run aimed at something else | **1** |
| Checking the experiment's instructions against the published ones | **1** |
| Re-deriving a claim about another document while reading for something else | **1** |
| Reading the lines a sweep protected, in their paragraphs | **1** |

**Two of thirty-three were found by tests**, and one of those two was a broken
test; a third was found by a build failing, which is the nearest thing. Five
came from writing programs in the language (four of the six programs found
one, and the sixth found none) and eight more came from reading something
rather than running it. The rows sum to one more than the entries, because
16 was found by two things and sits in two of them.

**The four from the evening of 2026-09-14 were all found beside the work
and none by the suite**, which was green through every one of them. Two are
the same lesson as 4, 5 and 20: a check that reads a fixed set of files is
blind to a file outside the set, whether the set is a cleanup list in a test
or the document checker's list of pages, and a move is what puts a file
outside the set. 33 is the reason step 5 of the roadmap's plan begins with
the checker rather than with a document.

The unit tests are worth having — 151 of them, and they caught 1 immediately —
but they check what was thought of. **What found the rest was a customer, or a
second look.** That is the argument for `programs/`, for recording predictions
before writing a program, and for the rule that a finding gets retracted in
place rather than edited away: 11 exists because 7 and 9 were written down where
somebody could go back and disagree with them.

**The two from 2026-09-01 were both found by a person rather than by a check**,
which is the first time that is true of a pair, and the day did not produce a
line of compiler code. Neither is a defect in Parasol. Both are defects in how a
claim gets recorded: one document asserting a fact about another, and an
inference written down in the voice of an instruction.

**15 is the one the tally argues with.** It is a real defect in the compiler,
latent since 0.1.0, and no amount of writing programs found it — all three
compose dialects that agree. What found it was checking whether a sentence in a
README was true. And what would have found it years earlier was running the
suite under the sanitizer the Makefile has documented from the first commit and
which nothing had ever been run under. *The tool was already there* is a worse
finding than a missing test, and it is the one to keep.
