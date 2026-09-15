# Changelog

Notable changes to Parasol, newest first.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md); the case for each
piece of work as it was argued *before* the work is in
[COMPLETED.md](COMPLETED.md); what a day actually consisted of is in
[journal.md](journal.md).

---

### `parasol --sob` — `HASH`, 2026-09-14

**No version.** `--sob` writes the `.sol` as before and then runs `solas` on
it, the one beside the `parasol` binary or else the one on PATH, with `-o`,
every `-I` and `--dump` handed through and `--expr` never. One command from
`.psol` to `.sob`. With it, `-o` names the `.sob` and the `.sol` goes beside
it, the map beside the `.sol`; a Parasol error is 65 and writes nothing, and
after the `.sol` is written the status is `solas`'s own, 127 when none could
be run. `--dump` without `--sob` is a usage error.

**It runs `solas` rather than linking it**, and that is the whole of the
decision: linking `libsol.a` was forty lines and would have made the
Makefile's first sentence false. [COMPLETED.md](COMPLETED.md) 19 has the two
side by side; the Makefile's rules still do the two steps themselves.
`tests/test_sob.c` is the first test here that runs the binary, 27 checks,
the load-bearing one being that the driver's `.sob` is byte for byte
`solas`'s. The version stays `0.17.0` on purpose: the roadmap says the next
release is what decides one version or two, and this is not that release.
The same conversation put *a member of the toolkit* on the roadmap, Hans's
direction for where `parasol/` goes next, held apart from this so that
neither waits on the other.

### Proto is Parasol — `ebdc8bc`, 2026-09-14

**No version, and nothing in the language changed.** The compiler, the
library, the headers, the directory and the source extension are spelled
differently and do the same things in the same order: the suite reports the
same checks over the same examples and programs it reported the day before,
and Solveig's suite, which runs this one after its own, is green with the
same 1067 claims. The diff is 2496 lines out and 2496 back in.

**The reason was that Hans was not sold on the name**, and on inspection it
had two collisions and an ambiguity. `.proto` and `protoc` are Protocol
Buffers; `.pro` is qmake's project file and Prolog's source; and in a
prototype-based language *Proto* points at the object model rather than at
the notation layer. The names put and not taken are in
[COMPLETED.md](COMPLETED.md) 18. *Parasol* is plain English, has `sol` in its
tail the way Solas and Solis have it in their head, and `para-` is *beside*:
parallel, paragraph, and above all *paraphrase*, which is what this compiler's
output is, the `.psol` said again in Solveig's own words.

The scheme the code already had is kept, and only respelled, for the second
time:

| | |
| --- | --- |
| `ProtoToken` | `ParasolToken` |
| `proto_lex_init` | `parasol_lex_init` |
| `PROTO_TOK_BAR` | `PARASOL_TOK_BAR` |
| `proto/proto/include/proto/` | `parasol/parasol/include/parasol/` |
| `bin/proto`, `libproto.a` | `bin/parasol`, `libparasol.a` |
| `PROTO_PATH`, `PROTO_SOLVEIG_MINIMUM` | `PARASOL_PATH`, `PARASOL_SOLVEIG_MINIMUM` |
| `.pro` | `.psol` |
| `# proto source map 1` | `# parasol source map 1` |
| `what-is-proto.md` | `what-is-parasol.md` |

**The extension is `.psol`**, five characters, which is the one place the
respelling was not arithmetic. The 2026-09-01 entry recorded as luck that
`.phx` and `.pro` were the same length, so `default_output_path` came through
untouched; the luck ran out, and its `length - 4` is `length - 5`. `.psol`
reads as *para-sol* at a glance and collides with nothing.

**What was respelled in the records, and what was not.** Every mention of the
project by name, in this directory and in Solveig's, is *Parasol* now, as
every *Phoenix* became *Proto* on 2026-09-01. The exception is the record of
that first rename: its changelog entry, COMPLETED 13, POSTMORTEM 14 and the
journal's 2026-09-01 morning keep *Proto* and `.pro`, because they say what
was chosen then and a respelling would have made them say something false,
that `.psol` is four characters, for one. The archived repository keeps its
name, `hansolovkarlsson/Proto`, as the Phoenix one kept its. The editor's
language id and every TextMate scope moved with the name, and the `.sol.map`
header line did too, so a map written by `proto` is not read by `parasol`;
nothing shipped reads maps but this tree.

**Checked against the day before, as last time**: the suite here, Solveig's,
and `editors/vscode/test.py` over all 24 `.psol` files, 202 `.sol` files and
81 completion and dialect cases, all green before the records were written.

**What it cost**, the same thing as last time and three times over. Three
headers, `common.h`, `lex.h` and `reader.h`, are dense enough in the prefix
that respelling dropped them under git's rename threshold, so they record as
a delete and a create where the other files record as renames;
`git log --follow --find-renames=30%` still walks them back.

### The compiler is built beside Solveig's four — `f4dd0d3`, 2026-09-13

**`make` writes `../bin/parasol`, not `bin/parasol`.** `BIN` defaults to
`$(SOLVEIG)/bin`, so one directory holds the whole toolkit and one `PATH`
entry reaches all five. `clean` removes the one file this Makefile puts
there and never the directory, since the four beside it are not Parasol's to
take; that rule was the whole risk of the move, and `make clean && make &&
make test` from either directory is the check. The boundary is where it was:
this Makefile reaches Solveig only through `bin/`, reading four binaries and
now writing one. A standalone `make` inside `parasol/` still works, `..` being
Solveig's root.

### `programs/bignum` — 2026-09-13

**The seventh program, and the first in two modules.** Arbitrary-precision
natural numbers: a library, `bignum.psol`, written in a five-line limb dialect,
and a driver, `calc.psol`, written in `lib/control.psol` and reaching the
library's generated source with `@include`. Add, subtract, multiply, divide by
a small integer, compare, raise to a power; every line the driver prints was
printed by `bc` first. `3ba0380` is the predictions and the answers,
`39f902e` the program and the Makefile, which orders two Parasol modules for the
first time.

**It was written to find where a dialect ends, and found that this one does
not end anywhere.** No operator in either header is a template. One
`@infix + 60 add.` adds two limbs in the library and two bignums in the
driver, because `add` is a message and the receiver decides. The roadmap's
entry with no proposal has one now, and it is a rule rather than a feature:
a dialect traps its scaffolding exactly when its domain's values are the
substrate's own, since a template on the spelling is then the only place the
rule can go. `digest` and `ledger` were bitten for that reason; this was not.

**Folding's third customer declined**, as predicted: no send in the generated
code has two literal operands. **The map holds across modules**: a misspelled
message in the library reported `bignum.sol:27` over `calc.sol:16`, one frame
per generated file, and each file's map took its line back. What the exercise
found instead is that a generated line is a span, a `while` body being emitted
on one line while a run-time trace has a line and no column; a new row under
*Rough edges*, checked the day it was found, and `solveig-notes.md` 4.

**And a number for a question from outside.** `1000!` in 40 ms at `-O2`, 170×
CPython's `int`, at 44 instructions per limb product with the one-based index
arithmetic costing as much as the array access. The prediction said two orders
of magnitude and was wrong. A large-number library is a library; the ratio is
what a C extension would buy, and nothing has waited for it. Records in
`a57982c`.

### Into Solveig's tree as `parasol/` — 2026-09-12

**No version.** The repository became a subtree of
[Solveig](https://github.com/hansolovkarlsson/Solveig) at `parasol/`, history and
all; the commit is in that repository's log. `SOLVEIG` defaults to `..`; `make
check` no longer tests a minimum version, since the parent is the version by
construction, and `PARASOL_SOLVEIG_MINIMUM` stays as the record of the language
level. The parent's `make` and `make test` build and test this directory. The
boundary is unchanged: no Solveig header, archive or symbol, only `../bin/`.
The reasons, on both sides, are in [journal.md](journal.md); the 0.1.0 decision
this reverses is there too.

### Closing out 2026-09-12: the front page's count of its readers

**No version, no code, and not committed by the closeout itself.**

**`README.md`'s *Where to start* said two readers, and that neither opened the
page.** The third reader opened it first, met *Not here* and stopped, which the
2026-09-04 sweep recorded everywhere the count was spelled *two strangers* and
nowhere it was spelled *Two readers*. The sentence now names the first two, the
third with the date, and no total. POSTMORTEM 28.

**Nothing else moved.** An audit of 2026-09-04's twelve commits, eight days on,
found the day's work in the records, every open item recorded, and the code
diff clean. The suite is unchanged at **63, 6, 69 and 13**, 151, green before
the writing and after it, and `make sanitize` is clean.

### The fourth reader, and the failure this project is built against — 2026-09-04

**No version; nothing in the compiler changed.** Predictions 18 to 23 committed
first in `9f2c22d`. Three runs had failed to reach a diagnostic, so this one
changed the reader's **role** rather than stripping a dialect's warning: an
author declaring a form of their own, which is 0.16.0's second stated customer
and the one no run had contained.

**They typed `<b: block>`** — prediction 18, right, copied from
`lib/control.psol`'s `repeat`. **And braced every use anyway** — 19 and 20 wrong,
the model being `examples/dialect.psol`'s `repeat #3 times { "tick":display }`, a
one-statement body wearing braces.

**Four runs, four tasks, two built to force an error, and no reader has seen a
Parasol diagnostic of any kind.** Prediction 21 — *does the prescription carry a
reader to the fix* — is retired unmeasured rather than asked a fifth time.

**What did happen is the failure `README.md` names as the one that kills
syntax-extension systems.** `parasol` exited 0, `solas` exited 0, and `solvm`
reported `undefined name 'total'` at **`banner.sol:8`** — a line in the
generated file, after seven lines of correct output. **No map had been written**,
the map being opt-in behind `--map`. With one the recovery is exact: generated
`8:5` is source `10:5`, the line they wrote.

**The reader got out on Solveig's error text alone**, in their words *the error
message alone told me exactly what to do*. The substrate's diagnostic did the
job Parasol's has never been given a chance to do.

**And the experiment was part of the problem.** POSTMORTEM 27: the prompt handed
the reader a three-command toolchain that omits `--map`, where `README.md`'s own
quickstart includes it. **The cost of the minimal invocation is measured; a
reader's likelihood of choosing it is not.** `README.md`'s *the default should
probably change* stays exactly as unsettled as it was, and the next run uses the
published invocation.

[ROADMAP.md](ROADMAP.md)'s rough-edges list has now had **two of its rows
checked and both mattered** — the `@use` path (POSTMORTEM 24) and this.

### The third reader, and a rule that did not survive them — 2026-09-04

**No version; nothing in the compiler changed.** Predictions 12 to 17 committed
first in `8c823df`, aimed at measuring 0.16.0's prescriptive diagnostic. **The
run failed at that and found something else**, which is what the predictions
were written down to make visible.

**Correct on the first compile-and-run, and no diagnostic emitted — for the
third time in three runs.** The reader braced both conditionals without
hesitating. Predictions 12 and 13 are wrong, 14 and 15 are untested for the
third time, and the reason is now different every time: run 1's task had no
cascade, run 2's dialect explained the limitation, run 3's example showed braces
on every body.

**No reader has ever seen a Parasol error message.** Three tasks, one built
specifically to force one. Every hour spent on diagnostics is still justified by
the author's reasoning and not by a reader's experience.

**The README's new section was read and worked.** Neither earlier reader opened
the front page; this one opened it **first**, met *Not here.*, went where it
pointed and — their words — *stopped reading README past that point.* Written
yesterday, measured today, and the first evidence that any of that page has been
load-bearing for anybody.

**And run 2's headline rule does not hold as it was written.** POSTMORTEM 26.
The `print`-is-a-repr trap is explained at the line it is about; the third
reader read that comment, quoted it back, wrote `:print` anyway and paid the
cycle:

> **A warning prevents a failure you would have chosen. It does not prevent one
> you would have walked into believing you had succeeded.**

*A limitation explained where it is declared is not a limitation a reader pays
for* was generalised from **one reader and one limitation** into four documents
the same evening — in a repository whose loudest standing rule is that **one
customer is not enough**. That bar is applied to features and was not applied to
a conclusion. Narrowed where it is stated live, and kept, because it is true of
the refusal it was measured on.

**Four stale counts and one false claim**, found by grepping for the claim:
`does-it-pay.md` said *the only two strangers to use this language did not read*
the README, which today's run contradicts. `REFERENCE.md`, `targets.md` and
`README.md` said *two strangers* and now say three.

### Closing out 2026-09-04 — a document that outlived its own correction

**No version, no code, and not committed by the closeout itself.**

**One defect, and the closeout found it.** [second-reader.md](second-reader.md)
ends on *the thing to fix first*, about the substrate documentation gap. That
was true of run 1. Run 2 measured the one-line fix at **zero** probes sixty
lines above it, and the closing sentence carries no date and no tense. **A
session read the file cold this morning and reported the gap as outstanding.**
Corrected in place, with run 1's paragraph kept — POSTMORTEM 25.

**It is 19, 20 and 21's failure from a new direction.** Those are a claim about
*another* document going stale. This is a claim about **the same document**,
overtaken by a section appended below it — and three sweeps yesterday missed it
because a sweep checks a document against something else, and this one is only
wrong against a later paragraph of itself.

**[ROADMAP.md](ROADMAP.md) gained two things it did not have.** The alternation
entry now records that 0.17.0's prescription puts the workaround at the failure,
so *once per dialect* becomes once. And the rough-edges list carries a warning
that **its filed severities are guesses**: the fifth row on that list, checked
today, was a compiler defect filed as cosmetic.

The suite is unchanged at **63, 6, 69 and 13** — 151, green before the writing
and after it.

### A file is not its path — 0.17.0, 2026-09-04

**`@use` decided whether it had already read a file by comparing path strings**,
and `x.psol` beside `./x.psol` is one file spelled two ways. Both rules built on
that comparison failed, in opposite directions.

**A diamond spelled two ways warned that a file collided with itself:**

```
d/./base.psol:1:8: warning: operator '+' was already declared by d/base.psol
d/base.psol:1:1: note: declared here
```

Correct code, a false warning, and it names one path as the offender and the
same file's other spelling as where it was declared. **The output was right**
— identical declarations, being the same line of the same file — so what it
cost was confidence in the collision warnings, which is the 0.4.0 feature the
composition story rests on.

**And a cycle spelled two ways was not reported as a cycle.** Every hop appended
another `./`, so no path repeated, the cycle check never fired, and what
stopped it was the 64-deep recursion limit — the wrong diagnostic under
sixty-four lines of `././././` trail. **The limit is what stood between this and
a hang**, and holding exactly as designed is also why the defect stayed quiet: a
guard that turns an infinite loop into a bad error message makes a bug
survivable and therefore invisible.

**A `ParasolSource` now carries `identity` beside `path`** — `realpath`, falling
back to a copy when there is nothing on disk to resolve, which is how a source
built in memory keeps working. **Display is unchanged and deliberately so**: the
cycle error still names `./././a.psol`, because that is what the file says and
where somebody can look. Only the two comparisons moved.

**Found by checking a rough edge instead of accepting how it was filed.**
`README.md` carried it as cosmetic, and named `realpath` as the fix four days
ago. The sentence was right and the severity was wrong — it described what a
diagnostic *shows* and never asked what else compared those strings.
POSTMORTEM 24.

**And `parasol_source_read` now has one exit.** The `fopen` failure had its own
copy of the cleanup and did not gain the new field when the struct did — a leak
written and found in the same hour, which is the argument for the single exit
rather than for remembering.

**Negative control**, `make clean` between the builds: both new checks fail
against the unfixed compiler — the diamond on its warning count, the cycle on
saying *nested more than 64 deep* where it should say *is a cycle*. Clean under
`make sanitize`.

The suite is **63, 6, 69 and 13** — 151.

### A block hole says how to become one — 0.16.0, 2026-09-04

**The diagnostic prescribes where a fix exists.** A hole-kind failure said what
it wanted and stopped:

```
error: 'if' wants a block here, and this is a send
note: 'e' is declared to want a block
```

It now says what to do, between those two lines rather than after them:

```
note: wrap it in braces -- '{' before this and '}' after it
```

**Only for `block`, and the restraint is the design.** Braces make a block out
of anything, so the advice works every time. Nothing makes a `place` out of
`#1` or a `name` out of `r:x`, and a note that prescribed there would be advice
that fails — which is how a reader learns to stop reading the notes. A check
holds that half: `expect_rejected_without` asserts the `place` failure does not
mention braces.

**Placed before the declaration note, not after**, so the fix sits next to the
problem — and `diag.c` then drops the repeated caret, which it only does for a
note about the span the line above just underlined. Three carets became one.

**Both second-reader runs named this and neither reached it.** Run 1's task had
no cascade; run 2's reader was warned off by the eleven lines `lib/clike.psol`
spends at its own `else` declaration. **So this is done on the argument and not
on a measurement**, and the argument is the generalisation of what those runs
found: a limitation explained at its declaration costs a reader nothing, and a
dialect's author pays that once per dialect. The compiler can pay it once for
all of them.

**The advice was run, not assumed.** `else { if (…) { … } else { … } }` compiled
and gave `low`, `mid` and `high` for `n` of 1, 5 and 10 — checked against the
`{ { … } }` trap the dialect warns about, which would have been silent.

**Negative control**, with `make clean` between the builds: the new `block`
check fails against the unfixed compiler. The `place` check passes against both
and is a guard rather than a control, which is what it is for.

The suite is **63, 6, 69 and 11** — 149, the two new checks being the whole of
the change.

### The README says where to start, and it is not the README — 2026-09-04

**No version, no code.** Two strangers used this language on 2026-09-03 and
**neither opened the front page** — one grepped it after the fact, one never
opened it at all and volunteered that it was not load-bearing. Both wrote a
correct program on the first compile-and-run regardless, out of the dialect
file, the example and `REFERENCE.md`. That was recorded in
[second-reader.md](second-reader.md) and [does-it-pay.md](does-it-pay.md) as a
finding, and [journal.md](journal.md) noted it was not on the roadmap and
probably should be. It is fixed instead.

**A *Where to start* section, twenty-five lines in**, naming those three files
and then Solveig's reference for the library — the half this repository
documents nowhere and does not intend to. It says *not here* in its first two
words, because a signpost that will not admit what it is is the thing that was
already wrong.

> **A front page is where somebody decides whether to try a language. It is not
> where they learn it.**

**Which is not an apology for the page.** Six programs' worth of argument is
what a front page is for, and it stays exactly as long as it was. What it did
not do was hand a reader the three files, and the two readers who needed it had
to find them without it.

### Closing out 2026-09-03, third time — the numbers went stale twice

**No version, no code.** The day was closed at midday saying *one commit, this
one, and no version*, corrected at teatime to *six commits and 0.15.0*, and is
nine now. **The numbers section of one journal entry has been wrong twice in one
day**, four hours after [conventions.md](conventions.md) gained *write the
narrative to last and the numbers to be replaced.* The agreement was vindicated
faster than anything else written here, and the entry carries both earlier
readings rather than either being replaced.

**Four claims corrected, three of them one claim.** `README.md`, `REFERENCE.md`
and `targets.md` all described `does-it-pay.md` as *what six programs say*; it
is six programs **and two strangers** since this afternoon. One `grep` returned
all three — the agreement earned on 2026-09-02, now the thing that finds most of
them.

**No defect was found this afternoon**, which is worth recording because every
other half-day this week found one. Two readers, four compile-and-run cycles
between them, nothing broken.

### The second reader, run again to force the chain — 2026-09-03

**No version.** Run 1's fourth prediction was never tested, the task having
needed no cascade, so a second run was designed around one: three mutually
exclusive ranges, which in C is `else if`. Predictions 7 to 11 committed first
in `08a0149`.

**The reader never wrote the chain.** Nested braces first attempt, correct
output first compile-and-run, **no diagnostic emitted at any stage**, and the
reason volunteered: *I would have tried `else if` first if the dialect file had
not spent a paragraph on it.* `lib/clike.psol` spends eleven lines on it at the
`else` form's own declaration.

> **A limitation explained where it is declared is not a limitation a reader
> pays for. It is one its author paid for once.**

**Which answers the alternation entry** — the fourth on [ROADMAP.md](ROADMAP.md)
settled by a customer declining to need it, and the first by one being *told* in
advance. Two strangers put in front of the workaround; neither noticed it was
one.

**And it was an unplanned control on the morning's two fixes, both of which
held**: six `does not understand` probes became **zero**, the reader citing
`REFERENCE.md`'s new *What is not here: the messages* as *the decisive
signpost*; and the `print`-is-a-repr trap that cost run 1 a cycle was caught
before it fired. **Neither fix touched the compiler and neither was longer than
a sentence.**

**Prediction 9 is untested twice over, for two different reasons** — no cascade
in run 1, and documentation in run 2 — which is itself the answer to whether the
message needs fixing: nobody reaches it.

**Neither reader opened the README.** One grepped it after the fact; one never
opened it and volunteered that the front page was not load-bearing. The entry
point in practice is the dialect file, the example and the reference.

### Closing out 2026-09-03 — a day that was closed at midday and did not stop

**No version.** The day was closed out at midday, and the entry said *one commit,
this one, and no version.* It ended with six and 0.15.0. `journal.md` carries the
correction **in place**, with the midday reading shown rather than replaced.

**Two stale claims, both today's own.** The journal's midday numbers, and
`POSTMORTEM.md`'s *144 unit tests* against 147 — the suite having gained the
three checks that hold 22. Found by grepping for the claim, which is the
agreement earned two nights ago and is now the thing that finds most of them.

**And one agreement added**: a closeout is written where it can be corrected,
because a day is not over when one runs, and the part that goes stale is always
the section of countable things. **Write the narrative to last and the numbers to
be replaced.**

**Five findings on a day that opened with nothing to do** — three stale claims
from a sweep on an empty day, a misdirected diagnostic from checking a
prediction, and a negative control from not believing it. **Not one from a
test**, for the third day running.

### The second reader, measured — 2026-09-03

**No version; nothing in the compiler changed.** The question
[does-it-pay.md](does-it-pay.md) has ended on since it was written — a dialect
used by somebody who did not write it — was measured, against six predictions
committed first in `3777a9a`.

**The notation cost nothing.** A reader given only `README.md`, `REFERENCE.md`,
`lib/clike.psol` and `examples/clike.psol`, in a directory of their own, wrote a
correct program on the **first compile-and-run**, never opening the README in
full. **And declared an operator of their own in that first program** —
`@infix ++ 55 concat.` — unprompted, at a sensible precedence, mixed with a
`@use`. The claim this project exists to test, taken up correctly by the first
stranger to touch it.

**Every cost was on the other side of the compiler**, and neither finding is
about notation:

- **A dialect is documented and its substrate is not.** `asString` appears
  nowhere in the published surface; `display` and `concat` once each, one of
  those as filler inside a warning example. `display` was found by six probes
  against `string does not understand '…'`, which names a wrong message and
  cannot name a right one. **REFERENCE.md now says the message set is Solveig's
  reference and points at it** — one line, and it had never been said.
- **`print` is a repr and the example taught it wrongly.** `examples/clike.psol`
  sends `:print` to a string seven times and shows the output of none; its only
  two output comments are on integer prints, **where `print` and `display` are
  indistinguishable**. Fixed: the string prints carry their real output, and one
  is `:display` so the file shows the contrast.

> **A declared grammar's cost to its author is the dialect. Its cost to a reader
> is the substrate.** Six programs measured the first and could not have found
> the second, because an author already knows what sends exist.

**Two predictions were not right.** The bare-integer silence never happened —
`#` came out of the example in the first minute, so the prediction described a
reader who skips an example that was provided — and the `else if` chain was
never written, the task not needing one, which is a fault in the design rather
than a result.

**And the proxy flattered the surface**, as the design said in advance it would:
`concat` and `asString` were guessed from zero documentation, which a reader
without Smalltalk behind them does not do. Recorded as assists, which makes the
documentation finding **worse** than the run makes it look.

### A caret in the right file — 0.15.0, 2026-09-03

**A hole-kind error whose argument is itself a form use reported the position of
the template it expanded into**, not the position the programmer wrote. Against
`lib/clike.psol`, the C chain everybody writes:

```
/…/lib/clike.psol:72:43: error: 'if' wants a block here, and this is a send
 72 | @syntax if <c> <t: block>            => c:ifTrue(t).
parasol: chain.psol -- 1 error
```

No expansion trail, and `chain.psol` named only in the summary count. **There was
no line in the reader's own file to go to** — the one failure `README.md`'s
first commit names as what a per-module grammar characteristically does, and
what the map and the diagnostics exist to stand in front of.

It now says:

```
chain.psol:4:32: error: 'if' wants a block here, and this is a send
  4 | if (x > #9) { "a":print } else if (x > #1) { "b":print }.
    |                                ^^^^^^^^^^^^^^^^^^^^^^^
```

**The check did not change and should not have.** A hole is still tested against
what its argument *became* — `if (b) { … }` in an `else` genuinely is a send by
then, and refusing it is right. `expand_node` now keeps each argument's extent
before the loop that replaces it, and `check_arguments` reports that. **Only the
position moved.**

**Why nine versions missed it.** Every hole-kind failure in the tests and
examples has a plain node in the hole, and a plain node is not replaced. **A
form in a hole is the case a dialect's users hit and its author does not**: the
author knows the chain wants braces and never writes the version that does not.
The check that was already there — *a form as an argument is checked as what it
becomes* — could not have caught it either, because asserting that something is
rejected says nothing about where the caret went.

**Three checks hold it now**, and the shape of the three is the point: the
severe case where the template *builds* the node, the mild one where a
substituted argument keeps its own span and only the column is wrong, and the
plain case that was always right and is what a fix could break. 58 checks became
61. [POSTMORTEM.md](POSTMORTEM.md) 22.

**Found by checking a prediction instead of asserting it**, while writing
[second-reader.md](second-reader.md) — whose fourth prediction was going to be
*the diagnostic will not name the fix* and had to be rewritten twice: once when
checking found it did not name the **file**, and again once that was fixed. The
measurement is deliberately not run in front of the defect it would have scored.

**And the control that verified the tests passed when it should not have.**
[POSTMORTEM.md](POSTMORTEM.md) 23: `git stash` restores a file with its original
timestamp, `make` rebuilt nothing, and the new checks ran against the fixed
compiler while appearing to run against the unfixed one. `make clean` between
the two builds is a standing agreement now.

### A sweep on an empty day — 2026-09-03

**No version, no code, and no work to report** — which is the entry.

The previous day was closed and pushed; nothing had moved. Asked to close out
2026-09-03, the answer given was that there was nothing to close out. Run
anyway, the sweep found **three** claims wrong, and
[POSTMORTEM.md](POSTMORTEM.md) 21 is why they are a different failure from 19's
and 20's:

**They went stale because somebody looked.** 20's write-up said *the entry below
reports the suite as 58, 6, 60 and 11* and the same commit changed that entry to
69. Two more sat in the `programs/prose` entry above — *`lib/arith.psol` has no
`<=`* and *one is still not enough* — both overtaken by `programs/basic` the
same evening.

> **Write what a document *read*, not what it *reports*.** A record of a defect
> is history the moment the defect is fixed, and past tense survives the fix.

And: **a sweep audits the documents, not the day.** An empty day is not a reason
to skip one. Both are standing agreements in
[conventions.md](conventions.md) now.

### Closing out, again — 2026-09-02

**No version, and nothing in the compiler changed.** The day had already been
closed out in `c61680a`; this reopened it for a sixth program and closed it
again.

**Fifteen claims corrected, and six of them were stale before last night's
sweep ran.** [POSTMORTEM.md](POSTMORTEM.md) 20 has them: `targets.md` carrying
the same sentence 19 fixed in two other files, the journal reporting the suite
as 135 six paragraphs above reporting it as 144, `conventions.md` saying "three
programs" twice against six, `does-it-pay.md` headed *What the four declared*
over five rows, and `REFERENCE.md` describing `lib/clike.psol`'s comparisons as
templates when they have been plain messages since 0.6.0 — **wrong for eight
versions.** The other nine went stale during the day's own work and were caught
the same day.

**19's defence was better than 13's and still not enough.** *Read everything
once at the end* works when the claim is somewhere you would open. `targets.md`
was read; it was read for what it says about targets.

> **A claim that appears in three documents is one claim, and it is found by
> grepping for the claim, not by opening the documents.**

That is [conventions.md](conventions.md)'s standing agreement now, beside the
sweep it sharpens — and it was added to the file that was two of the six, which
is the part worth remembering.

### Six comparisons in `lib/arith.psol` — 2026-09-02

**No version; a shipped dialect gained three declarations.** `!=`, `<=` and
`>=`, as `notEquals`, `lessOrEqual` and `greaterOrEqual` — plain messages
Solveig has always had, so three lines and no templates.

**The entry the standing rule was written down against, and it closed by being
applied rather than bent.** *A surface does not grow without a customer* kept
these out from the first commit. `programs/prose` became the first customer and
wrote `while i < doc:size + #1` around the gap; `programs/basic` became the
second, wanting `<=` and `>=` five times and `!=` four.

**Two customers for `<=` and one each for the other two**, so strictly the bar
was met for one of three. The family went in whole, and the reason is the
finding: **an arith with `<=` and no `>=` is a worse trap than an arith with
neither**, the missing one being missing for no reason a reader can see.

> **A customer count is per surface, and a comparison set is one surface.**

Nothing had had to decide that before, and it is what
[COMPLETED.md](COMPLETED.md)'s *Settled by a customer* table now records as the
first entry a customer settled **for** rather than against.

**Both customers were rewritten the same day**, which is the check that they
were real: `note.psol` reads `while i <= doc:size`, and `basic.psol`'s `FOR` limit
test, `pc <= program:size` and four `notEquals` sends are operators now.
`lib/clike.psol` is untouched — it has had the same six since 0.6.0, is
standalone, and declares no `@use`, so nothing collided.

### `programs/basic` — 2026-09-02

**The sixth program, and the first that is not a pass over its input.** A BASIC
interpreter — line numbers, `LET`, `PRINT`, `INPUT`, `IF`/`THEN`, `GOTO`,
`GOSUB`/`RETURN`, `FOR`/`NEXT` — with a program counter that can go backwards,
an environment outliving every statement, and a prompt when given no file. It
is the half of [targets.md](targets.md) that page never had a program for: it
answered a question about a BASIC *compiler* in the abstract on 2026-08-31.

**It stated the ceiling in one sentence where there had been two.**
`programs/grammar` found that a rule cannot be a form, so a grammar's rules
become data, and that was read as a limit on **recursion**. It is not. An
interpreter meets the same wall twice with no recursion in sight — a form per
statement kind, and an operator for BASIC's `+` — and both for one reason:

> **Notation is fixed when a file is read. An interpreter's every decision is
> made after that.**

**Which dissolves the two-domain question rather than answering it.** BASIC has
a real domain of values, `+` meaning add-or-concat, and it never reaches the
header: the interpreter writes `binop:value(op, a, b)` with `op` a *string from
the input*, and two `+` survive in 251 lines, both `pc + #1`. **A program can
contain a domain without being one**, so *steps want forms, values want
operators* is a taxonomy of domains a dialect can see.

**15 forms, 0 operators, 93 uses**, which makes it the fourth of six programs
declaring none — and the prediction had said seven or eight forms, wrong by
half.

**Two things nobody had tested.** A form's word and a message selector do not
collide: `@syntax step` sits beside six sends of `s:step` and both are right,
because a selector is never in primary position. And this is the first program
that **needed hygiene** — `take`'s template temporary `t` against `parseAtom`'s
local `t`, renamed in the generated source, unnoticed until the findings were
written.

**`<=` and `>=` got their second customer here**, in the interpreter's own
bounds tests and never in BASIC's comparisons, which are a token its lexer reads
at run time. That closed a roadmap entry the same day — see below.

### Closing out — 2026-09-02

**No version, and nothing in the compiler changed.** A last read of every
document, which is what the day earned.

**Nine stale claims, in one day of five versions.**
[POSTMORTEM.md](POSTMORTEM.md) 19 lists them: three in the journal's own
opening, three in the README — a version heading four releases behind, a *Known
gaps* row for something that landed in 0.12.0, and a folding claim carrying one
measurement when `ledger` had produced a second that argues against it — two
naming `does-it-pay.md` as covering four programs when it covers five, and one
in the postmortem's own tally. The ninth was found while writing the entry about
the other eight: **109 unit tests, against 144.**

**13 had already named the class and prescribed a defence** — *a claim about the
state of another document is re-derived when it is read.* Nine instances in a
day is the evidence that it is not enough, and the reason is one sentence:
**nobody re-reads a document that is not being read.** A README's version
heading is not consulted when adding a version.

**What worked was reading everything once at the end**, whether or not anything
was suspected, and it is a standing agreement in
[conventions.md](conventions.md) now, beside a second one the day earned:
**two sessions do not share a working copy.** A second session left uncommitted
changes to `reader.c` in this checkout at 11:59 while this one was committing
with `git add -A` every few minutes; the last such commit was 11:30, so nothing
was swept in by half an hour and no more. `git worktree add` is one command.

### A declared `|`, and `\` retired — 0.14.0, 2026-09-02

**A lone `|` may be declared.** Nine versions of documents said it could not, a
retraction two commits ago said they were wrong, and this is the thing itself.

```
@infix | 40 bitOr.

a | b              is  a:bitOr(b)
{ a | b }          is  a parameter and a body, in every module
{ (a) | b }        is  the escape, one bracket down
```

**`|` never joins the operator characters and the lexer is untouched.** A bar is
a token of its own; `@infix | …` asks the *parser* to look one up. A block
settles its parameters and its temporaries with a bounded lookahead that
consults no dialect, so the collision is one production wide and everything else
is free. **A tool can still tokenise any `.psol` knowing nothing about its
dialect** — the property [COMPLETED.md](COMPLETED.md) 12 was written to defend,
and defends correctly.

The second place a context outranks a declaration, and the first — `#[k = v]` in
0.12.0 — is the same shape with the same escape.

**Two things the demonstration had wrong, fixed before landing.**

| | |
| --- | --- |
| `@prefix \|` | was accepted and inert; **refused** now. A block's temporaries open with a bar, so a prefix one would have nothing to tell them apart — and a declaration accepted and doing nothing is what `@language` was deleted for in 0.10.0. |
| a stray `\|` | said *expected '.' after this statement*; says **'\|' has no meaning in this module** now, with the note every other undeclared operator gets. |

**And `\` is retired**, which is why this waited a version rather than landing
the morning it was demonstrated. 0.13.0 had just settled the repository on *one
spelling per operation* with `\` for a bitwise or **because `|` could not be
had**. Landing the bar without redoing that would have changed one spelling
twice in two versions, so the two went in together:

| | logical | bitwise |
| --- | --- | --- |
| and | `&&` | `&` |
| or | `\|\|` | `\|` |
| not | `!` | `~` |
| xor | **none** — and `!=` is xor for booleans | `^` |

**C's table exactly, with nothing substituted.** Nine lines of code across
`examples/utf8.psol`, `programs/digest/sha2.psol` and
`programs/digest/sha256.psol`, converted on the code portion of each line only
and every one printed and read — which is what
[POSTMORTEM.md](POSTMORTEM.md) 6 is for. `digest` still agrees with
`shasum -a 256`.

`\` is free and unused. `\|=` stays undeclarable, nothing being able to run
together with a bar; that is the price of not touching the lexer and it is the
right price. Nine checks in `tests/test_reader.c`, holding both halves of the
rule and both refusals. [COMPLETED.md](COMPLETED.md) 16.

### `programs/prose` — 2026-09-02

**The fifth program, and the one [does-it-pay.md](does-it-pay.md) asked for.**
A document language, with the document itself written in the dialect and
rendered to text — the first program here whose dialect writes the **data**
rather than the processing.

**26 lines of document, 36 lines of renderer.** The dialect reaches 26 of 64
lines and none of the rest. Even in the most content-heavy program that could be
written, the code is larger than the content.

**It found no third category.** It was picked as a domain that was neither
arithmetic nor instructions, to see whether *steps want forms, values want
operators* had a case outside it. `prose.psol` declares **no operators and seven
forms** — `ember`'s and `grammar`'s shape exactly. A document is a domain of
steps.

**It moved the ceiling down a level, and one prediction was wrong.** Nesting
was predicted to be the wall, on `grammar`'s finding that a rule cannot be a
form. It is not: a form takes a **block**, a block holds statements, and
statements are content forms, so `indent { … }` nests to any depth and
Solveig's braces carry the structure. `grammar`'s wall was narrower than
*nesting* — a template cannot **declare** a form, and a grammar's rules are
definitions. What a form still cannot do is contain part of a line:

> **A form can contain content. A form cannot contain half a line.**

Which is the answer to *could Parasol do a markup language*: the block structure
yes, the inline structure no, and not by any arrangement of words and holes.

**And it split "carrying a rule" in two.** `indent { … }` cannot be left
unbalanced — but the dialect did not invent that rule, it borrowed one Solveig
already enforces. `sha2.psol` invented its own; nothing in Solveig makes `+` mask
to 2³². **Only the invented kind is evidence that a declared grammar does
something a fixed one cannot**, and it is still the one clear instance in the
programs written so far — five when this was written, six since.

**Unpredicted, and it reverses an answer given the same morning.**
`lib/arith.psol` had no `<=`, and the renderer wanted one — it was written
`while i < doc:size + #1` instead. Asked hours earlier whether arith should be
completed, the answer was no, on the evidence that `<=`, `>=` and `!=` had *no
customer at all*. This was the customer. One was not enough, and
[ROADMAP.md](ROADMAP.md) recorded it so the second would settle it.

**The second arrived the same evening** — `programs/basic` — and the family
went in. See *Six comparisons in `lib/arith.psol`* above; the renderer reads
`while i <= doc:size` now.

### `|` can be declared after all — a retraction — 2026-09-02

**No version, and nothing in the compiler changed.** Three documents said
something that is not true, and now say what is.

`README.md`, `parasol/src/lex.c` and [COMPLETED.md](COMPLETED.md) 12 all held, in
nearly the same words, that a dialect cannot declare `|` because `{ a | b }`
would then have two readings. Entry 12 put it as *"naming the ambiguity does not
decide it"*. **A rule decides it**, and Parasol had the mechanism: a block reads
its parameters and temporaries first, so `{ a | b }` is a parameter and a body
*by rule*, a declared `|` is an operator everywhere a block is not reading a bar
of its own, and `{ (a) | b }` escapes — which is `#[(b = c) = d]` in a different
bracket, landed in 0.12.0 **four hours earlier**.

**Two questions had been run together and given one answer.** *May `|` join the
operator characters?* — no, and that stands: characters in that set run
together, so a `|` there would make `|=` a spelling and `{ a | b }` a guess.
*May `|` be declared?* — a different question, since a bar is a token of its own
and a parser may look one up without it entering the set at all.

**Demonstrated rather than argued**, by a second session: two hunks in
`reader.c`, no change to the lexer, the suite green and every block form intact.
Reverted rather than kept — it arrived uncommitted in a shared checkout, and
what it costs had not been looked at. [ROADMAP.md](ROADMAP.md) is that looking,
including the reason not to hurry: 0.13.0 has just settled the repository on one
spelling per operation with `\` for bitwise or *because* `|` was unavailable,
and **a spelling should be changed once.**

**And the cause was misattributed in both directions.** The entry blamed the
ambiguity and stopped; the session that built it reported removing *Solveig's*
constraint and had removed nothing of Solveig's — Solveig has the identical
`{ a | b }` and settles it the identical way. What stands in the way of `|` is
**Parasol's own block syntax**. [POSTMORTEM.md](POSTMORTEM.md) 18.

### Seven templates that Solveig already had messages for — 2026-09-02

**No version, and nothing in the compiler changed.** Two dialect files were
writing out sends that Solveig provides directly.

| was | is |
| --- | --- |
| `@infix != … => left:equals(right):not.` | `notEquals` |
| `@infix <= … => left:greaterThan(right):not.` | `lessOrEqual` |
| `@infix >= … => left:lessThan(right):not.` | `greaterOrEqual` |
| `@prefix ! => operand:not.` | `not` |

Six in `lib/clike.psol` and `programs/digest/sha2.psol`, plus the prefix, which
`lib/arith.psol` had been spelling as a plain message all along.

**Asked as a question about whether `lib/arith.psol` should be completed**, and
the answer to that was no — see below — but the neighbourhood turned this up.

**It reads better and costs less.** The generated Solveig says what it means:

```
n:equals(#9):not                ->  n:notEquals(#9)
(shift:lessThan(#0)):not        ->  shift:greaterOrEqual(#0)
{ (i:greaterThan(s:size)):not } ->  { i:lessOrEqual(s:size) }
```

`programs/digest` runs **272,398 instructions against 273,318** — 920 fewer,
0.34%, two of the four sites being loop conditions. Small, and it is the
readability that earns it: a template was standing in for a message, which is
the one thing `lib/clike.psol`'s own header says templates are not for.

**Checked for a correctness difference and there is none.** `<=` as
`not (a > b)` and `a:lessOrEqual(b)` could disagree on a partial order, so NaN
was the case to try: Solveig answers `true` to both. This is a simplification
rather than a fix.

**What is left in `lib/clike.psol` is three templates, and each is one a message
cannot be**: `=`, because assignment is not a send, and `&&` and `||`, because
their right side has to arrive in a block or it is evaluated whether or not it
is wanted.

**And the question that prompted it: no, `lib/arith.psol` should not be
completed.** Bitwise has one usable customer, not two — `examples/utf8.psol`
could share a file, and `programs/digest/sha2.psol` could not, its `<<` being
masked and the file standalone because it redefines `+`. The two also chose
different rungs for `&` (60 against 50) and `>>` (80 against 55), each against
its own neighbours, which is the per-module argument showing up as evidence.
`<=`, `>=` and `!=` have **no** customer: the two files declaring them are both
standalone, and every one of arith's five users declares no operator of its own.
*One customer, satisfied in three lines, is not a reason to grow a surface* —
and completeness is the wrong test for a dialect, which is a notation rather
than an API.

### `%1011`, and the first spelling that cost a dialect something — 0.13.0, 2026-09-02

**Binary integers**, the last of the nine differences
[POSTMORTEM.md](POSTMORTEM.md) 16 found that could be closed at all.

```
%1011           is #11
$FF08           is #65288
#-45            is #-45
```

**Solveig can give the whole `%` to the literal because it has no `%`
operator.** Its `product` is `unary { ( "*" | "/" ) unary }` and nothing else,
so `%2` there is simply an error. Parasol made `%` an operator character in
0.1.0, so the two have to share, and the split is **immediately followed by a
binary digit**:

| | |
| --- | --- |
| `%1011` | a number |
| `a % #2`, `a %#2`, `a % 2`, `a %2` | the operator, unchanged |
| `a %1`, `a %10` | **the number now**, and a loud error where it stands |
| `a +%1011` | the run `+%` is one operator; only a leading `%` starts a literal |

**No declaration is consulted**, so a tool can still tokenise any `.psol` knowing
nothing about its dialect. That is the line that matters and it has not moved.

**What it cost, which is worth naming as a shape.** `||` in 0.9.0 grew the fixed
vocabulary and took only `{ || … }` out of the *core*, and
[COMPLETED.md](COMPLETED.md) 12 held that up as the form any future request
should take. This is the second instance and the first with a different bill:
**growing the fixed vocabulary took something from what a dialect may declare.**
A module declaring `%` can no longer write `a %1` without a space. Nothing here
does — `%` as mod is written `n % #2`, because mod wants an integer and a bare
digit is a float — and it fails loudly rather than quietly. Small, and the next
one might not be.

Six checks in `tests/test_reader.c`, one of which is the cost written down as a
rejection so that it is a decision rather than a surprise.

**Two differences left, and neither is an oversight**: `@expr` is refused, and
`-3` cannot be had while `-` is declarable.

### `#[a = b]`, and the first rule where a context outranks a declaration — 0.12.0, 2026-09-02

**Dictionary literals**, which is the eighth of the nine differences
[POSTMORTEM.md](POSTMORTEM.md) 16 found and the one that had been mis-sorted as
free.

```
#[#1 = "one", #2 = "two"]
```

**The lexer was never the obstacle.** Solveig writes `pair = sum "=" expression`
and settles what `=` means in a key by *level* — a key parses below where `=`
lives, so it cannot swallow one. Parasol has no fixed levels to parse below: a
dialect may declare `=` at any precedence, and `lib/clike.psol` puts it at 10 for
assignment.

**So the rule is that a top-level `=` inside `#[…]` is the separator, whatever
the header said.** That is the first place in this language where a context
outranks a declaration, which is why it took a decision rather than a lexer
case. What keeps it a rule rather than `=` being taken away is that it stops at
the first bracket:

```
@infix = 10 => left := right.
#[k = #1]              is a pair, not an assignment

@infix = 40 equals.
#[(b = c) = d]         is  #[(b:equals(c)) = d]
```

It is a *parser* rule and not a lexer one, so nothing about reading a `.psol`
without running it has changed: `#[` is one token, taken where `#` is already
consumed, and `# [` is still the error it looks like.

**Emitted as Solveig writes it.** Parasol turns every operator into a send, so a
key always reaches `solas` as a send chain or a literal — well inside the `sum`
its grammar asks for.

Nine checks in `tests/test_reader.c`, including the two halves of the rule and
the three ways to get it wrong: no `=`, a trailing comma, and a space between
`#` and `[`. Solveig refuses the trailing comma too, which is why Parasol does.

**Three differences left, and one of them is the only decision:** `%1011`.
`@expr` is refused on purpose, and `-3` cannot be had while `-` is declarable.

### Four of Solveig's spellings, and one Parasol had too many — 0.11.0, 2026-09-02

**Five of the nine differences [POSTMORTEM.md](POSTMORTEM.md) 16 found, now
closed.**

| | |
| --- | --- |
| `#-45` | The sign belongs to the number, which is Solveig's rule. Safe here for a reason a signed *float* is not: nothing but an integer can begin with `#`, so `-` has no second reading to be confused with. |
| `$FF08` | Hexadecimal. `$` was not an operator character or anything else. |
| `1e10`, `2.5E-3` | Float exponents, taken only when the digits are there — `2 e` is still two tokens, and `45.` is still a float and a separator. |
| `"\q"` | **Narrowed.** Solveig has five escapes; Parasol took any character after a backslash. |

**An integer now travels as written.** It used to be stored without its `#` and
have one put back on the way out, which cannot survive `$FF08` or `#-45` — and
normalising `$428a2f98` to `#1116352408` would throw away the base the formula
was transcribed in, which is the only reason to write hexadecimal at all.

**The escape one is the defect rather than the gap.** Every other difference was
Parasol refusing something Solveig takes, which is a smaller language and an
honest error. That one went the other way: `x := "a\qb".` compiled here and
produced a `.sol` that `solas` refused, with the error landing on generated
code. **Parasol emitting invalid Solveig** is the single failure the map and the
run-every-example discipline exist to prevent, and neither caught it, because no
example has a bad escape. [POSTMORTEM.md](POSTMORTEM.md) 17.

**Four differences are left, and one of them was mis-sorted when the nine were
first written up.** `#[a = b]` was called free on the strength of the lexer. The
lexer was never the obstacle: Solveig writes `pair = sum "=" expression` and
resolves it by precedence *level*, which Parasol cannot copy because a dialect may
declare `=` anywhere — `lib/clike.psol` puts it at 10. It needs a rule saying a
context shadows a declaration, which nothing here has ever allowed, so it is a
decision and joins `%1011` on [ROADMAP.md](ROADMAP.md). `@expr` stays refused,
and `-3` stays impossible while `-` is declarable.

Eleven checks in `tests/test_reader.c` hold the new spellings, including the two
that must *not* change: a name after a number, and `45.` as a float and then a
separator.

### `programs/ledger` — 2026-09-02

**The fourth program, and the first that is a value type** — a statement in
fixed-point decimal, checked against figures produced independently in exact
decimal arithmetic. Written to answer two roadmap entries, and it answers both
against the grain.

**The domain-boundary entry has its second instance, so it is a pattern.**
`digest` declares `+` as addition modulo 2³² and is trapped on its loop
counters; `ledger` declares `/` as rounding to the nearest hundredth and is
trapped taking `-1225` apart into `-12.25`, which wants floored division. Both
write those lines as sends with a comment. Two narrowings came with it: **which
operator turns traitor is not predictable from outside the domain** — this
program predicted `*` and was bitten by `/` — and the boundary is not only at
the domain's edge, since `ratio interest to subtotal` answers `0.07` where the
exact value is `0.074995…`. A ledger has amounts wanting two places and rates
wanting five, and a dialect has one scale.

**The folding entry has its second customer, and the customer argues the other
way.**

| | instructions |
| --- | ---: |
| as written | 4,258 |
| every constant folded by hand | 4,250 |
| saved | 8 — **0.19%**, against digest's 5.4% |

A dialect's constants cost per *use*, and this dialect's uses are outside the
loop: `*` and `percent` are written once and stay written once whether the
ledger has five transactions or five thousand. The case for folding rests on the
claim rather than on the number.

**And it found that Parasol has one of Solveig's three integer literals.** `#-5`,
`$FF08` and `%1011` are all integers in Solveig; only the last form of the first
is one here. A ledger is the first program with an ordinary negative value.
[POSTMORTEM.md](POSTMORTEM.md) 16, and [ROADMAP.md](ROADMAP.md) for the third of
it that is a decision: `%` is an operator character, so `a %1011` would have
two readings.

Two smaller things: **one spelling may be both infix and prefix** — `@infix - 60
sub.` beside `@prefix - negated.`, so `#10 - -#5` is `#10:sub(#5:negated)` —
which nothing here had done. And **hygiene has now gone unmentioned by four
programs in a row**, which is the only evidence the 0.2.0 argument for shipping
it early could ever have.

### `make sanitize` — 2026-09-02

**A tool nobody runs is not a tool.** `SANITIZE=` has been in the Makefile since
the first commit, with the invocation written in a comment beside it, and
nothing had ever been run under it — which is how
[POSTMORTEM.md](POSTMORTEM.md) 15 stayed latent from 0.1.0 to 0.10.0.

```sh
make sanitize      # clean, then the whole suite under address + undefined
```

It cleans first, because the sanitizers have to be in every object and the tree
caches objects. It leaves an instrumented `bin/parasol` behind and says so;
`make clean` restores a normal build.

**Checked by reintroducing the defect.** With `parasol_dialect_add_infix` put back
the way it was before `f8b219a`, `make sanitize` exits 2 and names it —
*heap-use-after-free, reader.c:316 in directive\_operator* — and is clean with
the fix in. That is the one class of defect this suite structurally cannot catch
on its own: whether a read of freed memory is a crash is the allocator's
decision, so `tests/test_use.c` can hold the exact shape of the bug and pass.

[conventions.md](conventions.md) now carries it as a standing agreement rather
than a good intention: **before a release, and after anything that touches the
dialect tables.**

### One spelling per operation — 2026-09-02

**Nothing in the compiler changed**, and no version with it. This is the shipped
dialects agreeing with each other.

`\/` had been doing two jobs: logical *or* in `lib/arith.psol` at precedence 25,
and bitwise *or* in `examples/utf8.psol` at 50 and `programs/digest/sha2.psol` at
40. `~` had been doing two as well — logical *not* in arith, bitwise *not* in
sha2, which is C's meaning. A reader had to know which file they were in before
they could read a line.

| | logical | bitwise |
| --- | --- | --- |
| and | `&&` | `&` |
| or | `\|\|` | `\` |
| not | `!` | `~` |
| xor | — | `^` |

**C's table, with one substitution: `\` where C writes `|`.** That is the one
character a dialect can never have, `|` being what separates a block's
parameters from its body — so the single irregularity left is forced by the
design rather than chosen, and points at the constraint instead of hiding it.
`\` was already an operator character; it needed nothing added.

**The language is untouched.** `/\` and `\/` lex and declare exactly as before,
and a module that prefers them may still say so. What changed is this
repository's usage. `lib/arith.psol` and `lib/clike.psol` now spell the logical
operators identically, so clike's stated reason for standing alone is restated
around what actually still distinguishes it: `=` for assignment, `!=`/`<=`/`>=`,
and control flow with C's parentheses and braces.

**Checked rather than assumed:** every generated `.sol` in the tree is
byte-identical across the change — the messages are the same, only the source
spelling moved — and the suite reports the same 58, 6, 34 and 11 checks. A
side effect worth naming: `programs/digest/sha2.psol` beside `lib/control.psol`
now collides on seven operators rather than nine, `~` and `\/` having stopped
overlapping. Counting them is what turned up
[POSTMORTEM.md](POSTMORTEM.md) 15.

### A use-after-free composing two dialects — 2026-09-02

**`parasol` segfaulted on `@use "sha2.psol"` beside `lib/control.psol`** — two real
dialects in this repository, composed the way the collision rules exist to
allow. Latent since 0.1.0.

`parasol_dialect_add_infix` answers the entry a redeclaration displaced, so the
reader can say *previously declared here*. It looked that entry up **before**
growing the array, and `realloc` may move the block — so the caller read
`clash->spelling` out of freed memory. `add_prefix` and `add_macro` had it too;
`add_template` did not, answering no pointer. The lookup now happens after the
growth: realloc changes where the entries are, never what they say.

**It needed a collision, a growth, and a relocating realloc in the same call**,
which is why nine versions and three programs missed it — all three compose
dialects that agree. `tests/test_use.c` gains the shape, and is honest that it
guards only under `make test SANITIZE="-fsanitize=address"`: whether a stale
pointer lands on freed memory is the allocator's business, and in that process it
does not. **The suite is now clean under `-fsanitize=address,undefined`**, an
invocation the Makefile has documented since 0.1.0 and which nothing had been run
under. [POSTMORTEM.md](POSTMORTEM.md) 15.

### `@language`, removed — 0.10.0, 2026-09-02

**The only directive that did nothing, gone.** It parsed, recorded a name in
`ParasolDialect`, and nothing ever read it back. It was optional, ignored and
written by every `.psol` in the tree, which is a ritual rather than a feature.

**It was removed rather than made to act on something.** The roadmap had wanted
it to select a reader or an emitter for nine versions, and neither exists to be
selected. The near-miss option was to make it *assert* — one reader, one
emitter, any other name an error — and that was rejected because it prices the
change without asking whether the directive is right:

> `@language solveig.` at the top of `examples/forms.psol` says the body below is
> Solveig. That file declares `+`, `<`, `>`, `unless`, `while` and `swap`. Its
> body is not Solveig and Solveig cannot read it.

The reading under which the line was true — *the substrate is Solveig* — is the
same for every `.psol` and is already carried by the extension. The thing that
could differ between two files is the output, and the word for that is
`@target`, which is what gets added if a second emitter is ever built.
COMPLETED.md 14 carries the whole argument; [targets.md](targets.md) is amended
where it used to argue the other way.

| | |
| --- | --- |
| the header now takes | `@use`, `@infix`, `@infixr`, `@prefix`, `@syntax` |
| an old file gets | `'@language' is not a directive Parasol knows`, and a note naming the five |
| `ParasolDialect` loses | `name` and `declared_at` |

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

**No version.** SHA-256, and the third program written in Parasol. It agrees
with `shasum -a 256` on the three FIPS 180-4 vectors and five block-boundary
cases, all eight checked against an independent oracle before the expected file
was written, and its file mode is byte-identical to the system tool.

**The first customer for the operator half.** `ember` and `grammar` both leaned
on `@syntax` patterns; this is nothing but shifts, rotations, exclusive-ors and
masked additions. It was chosen because Solveig's own `programs/sha256sum` wrote
the gap down — *`@expr` has no bit operators, so the one file here that is
nothing but shifts, xors and masks is the one file that cannot use the notation
at all* — and Parasol has claimed the answer to that in the abstract since
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
  not to compose: `sha2.psol` beside `lib/control.psol` collides on four operators
  and the losing order hashes wrongly.

### `||`, in the fixed lexer — 0.9.0, 2026-08-31

**`|` is still the block's own and always will be; `||` is two bars and not a
bar.** The lexer takes it before the bar and hands it to every dialect, so
`lib/clike.psol` now spells C's *or* the way C spells it and the paragraph
apologising for `\/` is gone from that file.

The proposal this answers was a `@token` directive letting a file bind a
spelling to a named token. Refused: it does not decide the ambiguity that
actually blocks `|`, and a declarable token stream would make every downstream
tool implement the directive before it could lex at all. The vocabulary grew
instead of becoming declarable, which is the same answer *a dialect that changes
the lexer* has always had in [ROADMAP.md](ROADMAP.md).

`\/` keeps its job: single `|` is still unavailable, so a bitwise *or* is still
spelled that way, as `examples/utf8.psol` does. `lib/arith.psol` keeps `/\` and
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
such behaviour. Five forms in `programs/grammar/peg.psol` and one in
`programs/ember/asm.psol` moved to the call shape; the parentheses that existed
only to work around it are gone from both grammars.

The rule — *a pattern for something that reads as a step, a call for something
that reads as an application* — moved from a program's README into
[GRAMMAR.md](GRAMMAR.md), where somebody choosing a shape would look. The real
finding is that **choosing wrongly is silent**: both readings are legal, so
nothing at the declaration can warn.

### `programs/grammar` — `ec302d8`, 2026-08-31

A grammar toolkit, and the second program written in Parasol. `examples/calc`
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

`lib/clike.psol` and `examples/clike.psol` land with it.

### A diagnostic for a pattern that read no parts — `f489359`, 2026-08-31

`@syntax vec { <x> }` got *needs `=>`* rather than the message about patterns,
because the better message only fired once a part had been read.

### `/\` and `\/`, and the fix for what that broke — `31d0ffc`, `f0af7c0`, 2026-08-31

A spelling change in `lib/arith.psol`. The first commit replaced `&&` in
`emberc.psol` with a blind global substitution and caught a shell command inside
a comment; the second fixed that and four documents that still spelled the new
operator the old way.

### 0.7.0 — an operator that stands for a template — `23f0cbe`, 2026-08-31

`@infix /\ 30 => left:and({ right }).` The only way to declare an operator whose
right-hand side must not always be evaluated — Solveig's `and` takes a block, and
an operator naming a *message* hands over an argument already evaluated.

**The two extension points did not compose and this is the seam.** `programs/ember`
is what found it.

### `programs/ember` — `e3f1288`, 2026-08-31

The first program written in Parasol. A small language compiled to ARM64
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

`@use "arith.psol".` **The collision rule, which everything was queuing behind**,
and the answer was Solveig's: the later wins and the compiler says so. A span
carries its file, which is the refactor the rest needed.

### 0.3.0 — the other half of hygiene — `8101c11`, 2026-08-31

A template's *free* references are protected: the caller's local is renamed
throughout its own frame. One pass rather than a resolver, because only
parameters and `| … |` temporaries are locals in Solveig.

### `docs/solveig-notes.md` — `ef43f60`, 2026-08-31

A running log of what Parasol finds in Solveig. Two entries at the time; a third
added later recording a prediction about Solveig that was wrong.

### 0.2.0 — forms, hygiene and expansion trails — `2af48cf`, 2026-08-31

`@syntax unless(test, body) => … .` Hygiene in the same commit rather than after
it. Expansion terminates without a counter, because a template may mention only
the forms declared above it.

### `docs/targets.md` — `55dbd72`, 2026-08-31

What Parasol targets, and what a program written in Parasol targets — two
unrelated questions, and only the first is a Parasol question.

### 0.1.0 — the first commit — `5d332a2`, 2026-08-31

A tree of Parasol's own, spans on every node, the map, a grammar declared per
module, and a build that takes nothing from Solveig.
