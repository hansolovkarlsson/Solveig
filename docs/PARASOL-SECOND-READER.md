# The second reader

*[does-it-pay.md](PARASOL-DOES-IT-PAY.md) weighs seven programs and ends on the one thing
none of them tested. This is the design for testing it and the predictions,
recorded before each run and scored after — **four runs now**, oldest first,
with wrong predictions left in and marked wrong.*

> What no program has yet tried is a dialect used by **somebody who did not
> write it** — every dialect here was written by the author of the file that
> uses it, an hour before, and a notation's real cost is paid by the second
> reader.

**It needs nothing added to Parasol**, which is why it is next. Six programs have
made every other open question smaller and left this one exactly where it
started.

**And it stopped being hypothetical on 2026-09-03**, when Solveig's README began
linking Parasol, then a repository of its own. The second reader is about to exist whether or not
there is a measurement of what they pay.

## The design

| | |
| --- | --- |
| **The dialect** | `lib/clike.psol`. It is shipped, standalone, documented in [REFERENCE.md](PARASOL-REFERENCE.md), and the only one written for readers rather than for one program — `interp.psol` and `sha2.psol` name their program's globals and are explicitly not reusable. |
| **The reader** | Somebody who did not write it and has not read Parasol's pages. The available proxy is a session with no context, given the published surface and nothing else. **A proxy is not a person**; what that costs is under *How it is checked*. |
| **What they get** | Everything published: `README.md`, `REFERENCE.md`, `lib/clike.psol` and `examples/clike.psol`. **Nothing is withheld**, because a stranger arriving from Solveig's front page gets all of it, and testing a smaller surface would test a strawman. |
| **The task** | Print every pair `(a, b)` with `1 ≤ a < b ≤ 6` whose product is even, then how many there were. A nested loop, `%`, `&&`, a comparison, a counter and two kinds of printing — and **nothing in `examples/clike.psol` to copy**, which has no nested loop and no counter. |
| **What is recorded** | Every attempt, in order; every diagnostic; every time a document is opened and which one; and for each failure, whether the message alone was enough to fix it. |

## What is predicted before it is run

| | |
| --- | --- |
| **1. The example is load-bearing, and the operator table is not enough on its own.** | `REFERENCE.md`'s clike entry is two tables of operators and forms. It does not mention `#` on an integer, `.` where C writes `;`, or how to print — and none of the three is a thing a *dialect* has, so no operator table could carry them. Predicted: `examples/clike.psol` is opened in the first minute and consulted more often than either table, **and the finding is a cost `does-it-pay.md` has never counted** — a dialect does not document itself, and every dialect here was written by somebody who needed no example. |
| **2. Every expensive mistake is at the dialect/substrate boundary, and none is in the notation.** | The operators and forms *are* C's: `=`, `&&`, `%`, `while`, `if`/`else`. Predicted to cost nothing at all. The three predicted failures are `1` for `#1`, `;` for `.`, and not knowing how to print — **Solveig's lexer and Solveig's library, neither of them anything `lib/clike.psol` could have said.** If that holds, *a dialect ends at its domain* has a second face: it also ends at its **substrate**, and the reader meets that edge before they meet the domain's. |
| **3. Only one of the three survives compilation, and it is the bare integer.** | `;` and a missing `print` are syntax and message errors with a line and a caret. A bare `1` **is a valid float in Solveig** — checked: `(1):class` answers *float does not understand 'class'* — so `a = 1` compiles, runs, and gives a float where an integer was meant, and `%` on it answers something plausible. Predicted: the only mistake that reaches a wrong answer instead of an error, and **the first entry in `does-it-pay.md`'s silence table contributed by a reader rather than an author.** |
| **4. The `else if` chain is hit, and the diagnostic is now the thing on trial.** | Checking this rather than asserting it found [POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 22: the error pointed into `lib/clike.psol`'s template and named the reader's own file nowhere but the summary line. **Fixed in 0.15.0 before this is run**, deliberately — measuring in front of it would have scored the defect and not the notation. So the message now names the reader's line and underlines the whole nested `if`, and the prediction is what it should have been: **the position is right and the message still does not say what to do.** It names the hole's kind, not the nested-brace workaround, and predicted: the reader finds that in `examples/clike.psol`'s comment rather than in the error. If so, **a diagnostic that points correctly and prescribes nothing is the next thing to fix**, and this is the first evidence for it from somebody who could not already know the answer. |
| **5. `for` and `i++` cost nothing, and that is a result rather than a shrug.** | Neither exists; both are named in [ROADMAP.md](../parasol/docs/ROADMAP.md) as things C has that Parasol cannot. Predicted: noticed within seconds, substituted without complaint, and **not recorded as friction by the reader at all** — because an absent thing announces itself at the first attempt. Set against 3, that is the shape of every finding in `does-it-pay.md`'s cost table: **absence is cheap and silence is expensive.** |
| **6. This measures one half of the cost and will be quoted as both.** | *A notation's real cost is paid by the second reader* has two halves — **learning it once**, and **reading somebody else's code in it a year later.** This design measures the first and cannot touch the second, there being no year-old Parasol and no second author. Predicted: the result gets cited as though it settled the sentence. Written down now so that it settles the half it settles. |

## How it is checked

**The proxy is not a person, and the difference has a direction.** A session with
no repository context has still read C and Smalltalk, and may produce `:print`
from habit rather than from a document. That makes the dialect look **better
documented than it is**, so the bias runs one way and can be corrected for: a
use of anything not in the published surface is recorded as an **assist** and
not as a success, and the transcript has to show which document produced it or
it does not count.

**Attempts are counted, not judged.** The measure is how many compile-run cycles
reach a correct answer, and which document was open at each. A reader who gets
it right first time and a reader who takes six are both results; **only the
second produces a list of what a dialect cannot say about itself**, which is
what this is for.

**And the task is checked against a hand-computed answer**, as the seven programs
are: the pairs with `1 ≤ a < b ≤ 6` and an even product are (1,2) (1,4) (1,6)
(2,3) (2,4) (2,5) (2,6) (3,4) (3,6) (4,5) (4,6) (5,6) — **twelve**, of the
fifteen pairs.

## What it found

Run on 2026-09-03, against 0.15.0, with the predictions above committed in
`3777a9a` first. The reader got the four published files in a directory of their
own and the three toolchain commands, and was told not to look at the
repository. The program it produced, its output and the twelve pairs were
re-run and checked here rather than taken from its report.

**It got correct output on the first compile-and-run.** One cycle against the
task; a second that changed formatting and nothing else.

### The predictions

| | |
| --- | --- |
| **1. The example is load-bearing** | **Right, and by more than predicted.** `examples/clike.psol` and `lib/clike.psol` were opened first, together, before anything else was read — and never opened again. `README.md` was **never read in full**; it was grepped, twice, after the fact. The syntax came entirely from the example plus one table. |
| **2. Every expensive mistake is at the dialect/substrate boundary** | **Right, and it is the finding.** In the reader's own words: *all of my friction was on the other side of the compiler.* The notation cost **nothing** — `=`, `%`, `&&`, `while`, nested `if`, the precedence rungs, all correct first time and none of them remarked on. |
| **3. The bare integer is the only mistake that survives compilation** | **Wrong about the instance, right about the class.** No bare integer was ever written: `#` came out of the example inside the first minute and never came up again. **The prediction described a reader who skips the example, and an example was provided.** But a silent failure did happen, by another route — see *print is a repr* below — so the silence class got its reader-contributed entry, from a mechanism nobody had named. |
| **4. The `else if` chain** | **Not tested, and that is a fault in the design rather than a result.** The task wanted a nested loop and needed no branching cascade, so the chain was never written. The one prediction aimed at a known rough edge got no evidence, and a second run would have to ask for the shape that produces it. |
| **5. `for` and `i++` cost nothing** | **Right, and understated.** `while` and `b = b + #1` were written without comment. Neither absence appears **anywhere in the reader's log** — not as friction, not as a workaround, not as a remark. Absence is not merely cheap; it was invisible. |
| **6. This measures one half of the cost** | **Stands, and is now load-bearing.** One reader, one task, one hour. It says what learning the notation costs and nothing about reading somebody else's code in it. |

### A stranger declared an operator in their first program

Nobody predicted this and it is the strongest single result. Needing to join
strings, the reader wrote:

```text
@use "lib/clike.psol".
@infix ++ 55 concat.
```

— an unprompted new operator, at a precedence chosen to sit under `+` at 60,
mixed into a module that also `@use`s a dialect. **The one thing this project
claims is that a programmer can declare notation, and the first stranger to
touch it did so in their first program, unasked, and got it right.**

### `print` is a repr, and the example teaches it wrongly

The one thing the reader expected and got wrong:

```parasol
"big":print.        ; "big"   -- with the quotes
"big":display.      ; big
```

`examples/clike.psol` sends `:print` to a string **seven times** and shows the
output of none of them. Its only two output comments — `; #40` and `; #3` — are
on **integer** prints, where `print` and `display` are indistinguishable.

> **The example demonstrates the message exactly where its trap is invisible.**

That is a defect in a shipped example, it is what cost this reader their second
cycle, and it is fixed alongside this entry: the string prints now carry their
real output.

### The published surface documents a dialect and not its substrate

The largest finding, and the one with an action attached. Counting mentions
across everything a stranger is given:

| | README | REFERENCE | clike.psol | example |
| --- | ---: | ---: | ---: | ---: |
| `asString` | **0** | **0** | 0 | 0 |
| `display` | 1 | **0** | 0 | 0 |
| `concat` | 1 | **0** | 0 | 0 |

`concat`'s single appearance is **filler inside an example of a duplicate-operator
warning**, not documentation that a string understands it.

So the reader guessed `concat` and `asString` with nothing to check them
against, and found `display` by running six one-line probes —
`show`, `write`, `printNl`, `put`, `emit` — each answering `string does not
understand '…'`, **a message that says the name is wrong and cannot say what is
right, with nothing in the sandbox to look it up in.**

> **The documents describe, exhaustively, how Parasol turns operators into sends —
> and never say what sends exist.**

That is prediction 2 confirmed and then sharpened past where it was aimed. The
boundary is not merely where the *mistakes* are; it is where the *documentation
stops*, and a reader reaches it in their first statement, because a program that
computes anything must eventually print it.

**The fix is one line and it is made**: [REFERENCE.md](PARASOL-REFERENCE.md) now sends
the reader to Solveig's own reference for the message set, which is the half
Parasol's pages have no business restating and had never named.

## The second run, and what changed about it

**Predictions recorded before it, as the first run's were.** Committed here
before the reader was given anything.

Run 1 left two things undone. Its fourth prediction was **never tested** — the
task wanted a nested loop and needed no branching cascade, so the `else if`
chain was never written — and its one real finding, that the published surface
documents a dialect and not its substrate, produced a **one-line fix** that
nothing has measured.

**So the second run varies two things and holds the rest.**

| | |
| --- | --- |
| **The task** | Classify `n` from 1 to 12 into three ranges and print one line each. Three mutually exclusive cases is a cascade, and a cascade in C is `else if`. **Nothing else about the task is interesting**, which is deliberate: run 1 established that the notation costs nothing, so this one is aimed at the single construct that has a known rough edge. |
| **The surface** | Now includes **Solveig's own reference**, because `REFERENCE.md` names it since run 1 and a real reader follows the pointer. Run 1's biggest cost was that the message set was documented nowhere in reach. **This measures whether naming it was enough.** |

Everything else is held: same dialect, same example, same isolation, same
instruction to keep an untidied log.

| | |
| --- | --- |
| **7. The chain is written the C way, first, without hesitation.** | `if (a) { … } else if (b) { … } else { … }` is not a thing a C programmer decides to write; it is the shape the problem arrives in. Predicted: it is attempt one, and it is refused. |
| **8. The diagnostic names their line, and that is a check rather than a prediction.** | 0.15.0 fixed the position four hours before this was written, so the error will point at the reader's `else if` and underline it. **Recorded as a check**: if it does not, 22's fix is wrong and the run has found that instead. |
| **9. And it still will not say what to do.** | This is the real prediction 4, restated where it can be tested. The message names the *hole's kind* — `'if' wants a block here, and this is a send` — which is true, unhelpful, and says nothing about nested braces. Predicted: the reader does **not** get from the message to the fix, and finds it in `examples/clike.psol`'s comment instead. **If so, a diagnostic that points correctly and prescribes nothing is the next thing to fix**, and this is the evidence for it. |
| **10. Two readers hit the same wall means it is the wall.** | Run 1 never reached the chain. If this reader is stopped by it, then the *only* construct in `lib/clike.psol` that costs a stranger anything is the one the ROADMAP already knows about — a hole's kind being one choice with no alternation, entered as *worked around, one customer*. Predicted: it gets its second customer, and the first from somebody who did not write the dialect. |
| **11. The substrate friction is mostly gone.** | Run 1 guessed `concat` and `asString` from zero documentation and found `display` by six probes. Solveig's reference lists all three. Predicted: **zero probes**, and the one-line fix in `REFERENCE.md` is worth more than the run that found it. If friction remains, it is that a reader must be *told* the pointer exists rather than tripping over it, which a link in a table does not guarantee. |

### What the second run found

Run on 2026-09-03 against 0.15.0, predictions committed first in `08a0149`.
Program and output re-run and diffed against a hand-computed oracle here.

**Correct on the first compile-and-run, again. No diagnostic was emitted at any
stage.** Two readers, two tasks, two first-attempt successes.

| | |
| --- | --- |
| **7. The chain is written the C way, first** | **Wrong, and it is the finding.** The reader wrote `else { if (…) { … } else { … } }` **on the first attempt** and never tried `else if`. Their reason, unprompted: *I would have tried `else if (n < #9) {` first if the dialect file had not spent a paragraph on it.* |
| **8. The diagnostic names their line** | **Check passes** — verified here rather than through the reader, who never saw it. `chain2.psol:5:6`, underlining the whole `else if`. 22's fix holds for this shape. |
| **9. And it still will not say what to do** | **Not tested, for the second time — and now for a much better reason.** Run 1 missed it because the task did not need a cascade. Run 2 missed it because **the documentation prevented the failure from happening.** The message's unhelpfulness is real and remains unmeasured, and two runs now say the same thing about why: nobody reaches it. |
| **10. Two readers hit the same wall means it is the wall** | **Wrong premise.** Neither reader hit it. One never met it; one was warned before they could. |
| **11. The substrate friction is mostly gone** | **Right, and it is the cleanest measurement of the day.** **Zero** probes against `does not understand`, where run 1 made six. The reader named `REFERENCE.md`'s *What is not here: the messages* as *the decisive signpost*, and went straight to Solveig's reference for `fill` and `display` instead of guessing. |

### A rough edge documented at its declaration costs a reader nothing

`lib/clike.psol` spends eleven lines, at the `else` form's own declaration, on
why a chain cannot be a chain — the `{ { … } }` that silently answers instead of
running, the `#54` where `#40` was right, and the spelling of the fix. The
example repeats it in two lines.

**A stranger read that and paid nothing.** No attempt, no diagnostic, no cycle.

> **A limitation explained where it is declared is not a limitation a reader
> pays for. It is a limitation its author paid for once.**

That is evidence about [ROADMAP.md](../parasol/docs/ROADMAP.md)'s alternation entry, which has
sat as *wanted by `lib/clike.psol`, worked around, one customer*. **Two strangers
have now been put in front of the workaround and neither noticed it was one.**
It is the fourth roadmap item this project has had answered by a customer
declining to need it, and the first answered by a customer being **told** in
advance.

### Both of the morning's one-line fixes were measured by the afternoon

Run 1 found two things and each got one line. Run 2 is the control:

| the fix | run 1 | run 2 |
| --- | --- | --- |
| `REFERENCE.md` names the message set as Solveig's and links it | 6 probes against `does not understand`, `concat` and `asString` guessed from nothing | **0 probes**, cited as *the decisive signpost* |
| `examples/clike.psol` shows what `:print` really prints | cost a cycle; the example taught it wrongly | caught it — *the one that would have bitten me* |

**Neither fix was to the compiler and neither was longer than a sentence.**

### Neither reader opened the README

Run 1 grepped it, twice, after the fact. Run 2 **never opened it at all** and
said so unprompted: *worth knowing if you were expecting the front page to be
load-bearing.*

Two for two, and prediction 1 has the shape of it right but the wrong three
documents: the entry point is **the dialect file, the example, and the
reference.** The README is where somebody decides whether to try the language,
not where they learn it — which is a reasonable thing for a front page to be,
and is not what it currently reads as.

### What the proxy cost, measured as the design said it would

*How it is checked* said a use not traceable to a document counts as an
**assist**, the bias running one way. It ran that way:

| | |
| --- | --- |
| `concat`, `asString` | **assists.** Guessed with zero documentation, correct first time, and traceable to Smalltalk habit rather than to anything read. |
| `display` | **not an assist.** Six failed probes and a guess. |

**So the documentation gap is worse than the run makes it look.** A reader
without Smalltalk in their background does not guess `asString`; they get
`integer does not understand 'toString'` and have nowhere to go. The proxy
flattered the surface exactly as predicted, and correcting for it is what turns
the third finding above from an inconvenience into the thing to fix first.

**And that last clause was still standing here on 2026-09-04, sixty lines below
the run that settled it.** *The thing to fix first* was written about run 1 and
is true of run 1; run 2 measured the one-line fix at **zero probes** and named
it *the decisive signpost*. The sentence carries no date and sits last in the
file, so a reader who reaches the end reaches an open recommendation that was
closed two sections earlier — and one did, on 2026-09-04, and reported the gap
as outstanding.

**It is corrected here rather than rewritten**, because the paragraph above is
what run 1 cost and that is worth keeping. What it needed was the tense it now
has: **it was the thing to fix first, it was fixed, and *What the second run
found* is where that is recorded.** [POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 25.

## The third run, and the thing it is aimed at

**Predictions recorded before it, as both earlier runs' were.** Committed here
before the reader is given anything.

**0.16.0 shipped on an argument and no measurement, and this is the
measurement.** The hole-kind diagnostic now carries `wrap it in braces -- '{'
before this and '}' after it`. Prediction 9 — *the message names the hole's kind
and says nothing about what to do* — is **untested twice**: run 1's task needed
no cascade, and run 2's reader was warned off by `lib/clike.psol`'s eleven lines
before they could reach it. Two runs agree on why, and it is the same reason:
**nobody reaches it.**

### Reaching it without rigging it

The tempting design is to hand the reader a dialect with the warning paragraph
removed. **That would be measuring a file written for the measurement**, and the
run would prove only that an undocumented limitation costs something, which
nobody doubts.

So the dialect is held exactly as it ships and the *route* changes. `else if` is
not the only way into a block hole — the ordinary one is a **single-statement
body with no braces**, which is what a C programmer writes without thinking:

```c
if (n % 3 == 0) printf("%d\n", n);
```

`lib/clike.psol` declares `if <c> <t: block>` and `while <c> <b: block>`, so a
bare send in that position fails the same way `else if` does. **And what those
two declarations say about it is different in kind from what `else` says:**

| | |
| --- | --- |
| the `else` form | **Eleven lines, at the declaration.** Names the silent `{ { … } }` failure, shows the `#54` where `#40` was right, spells the fix. Stopped run 2 before it started. |
| the `if` and `while` forms | **One design note**, saying the body *is* a `block` — as the reason two holes may sit adjacent with no word between them. It never says a braceless body fails, and never spells a fix. |

**So run 3 tests the middle case: a limitation *mentioned* at its declaration
but not *explained*.** Runs 1 and 2 measured the two ends — undocumented, which
cost run 1 six probes, and explained, which cost run 2 nothing.

### What varies, and what is held

| | |
| --- | --- |
| **The task** | Print each `n` from 1 to 15 that is divisible by 3, and each divisible by 5 — a number divisible by both is printed twice. **Two single-statement conditionals inside a loop**, which is the commonest brace-omission site in C. Nothing else about it is interesting, deliberately. |
| **Everything else** | Held. Same dialect, unmodified. Same four published files plus Solveig's reference. Same isolation, same instruction to keep an untidied log, same no-context proxy. |

### What is predicted before it is run

| | |
| --- | --- |
| **12. The braces come off at least once.** | Two one-statement conditionals in a loop is where a C programmer stops typing braces. Predicted: attempt one omits them on at least one, and is refused. |
| **13. A hole-kind diagnostic is emitted, for the first time in three runs.** | Runs 1 and 2 produced **no diagnostic at any stage**, between them. Predicted: this run produces one, and it is the first any reader of this language has seen. |
| **14. And this time it says what to do, and that is enough.** | The real prediction 9, restated where it can finally be tested. 0.16.0 put `wrap it in braces` under the error. Predicted: the reader goes **from the message to the fix without opening a document**, and their log shows it. If they open `lib/clike.psol` or the example instead, the prescription did not carry and 0.16.0's argument is weaker than it reads. |
| **15. The design note does not prevent what the essay prevented.** | Predicted: the `if`/`while` note is not recalled, not cited, and does not stop the failure — **a limitation mentioned is not a limitation explained**, and only the second kind buys anything. That is the sentence run 2 earned, given its boundary. |
| **16. The example is the real competition, and it argues for braces.** | Every body in `examples/clike.psol` is braced, and both readers so far took their syntax from that example over any table. Predicted: **if 12 is wrong, this is why** — and that is a result about examples rather than about the diagnostic. Written down now so it cannot be a retrofit. |
| **17. The substrate still costs nothing.** | Run 2 made **zero** `does not understand` probes against run 1's six, after `REFERENCE.md` gained one sentence. Predicted: zero again — which would be that one sentence holding across two readers and two unrelated tasks. |

**The answer is worked out by hand, as the other two were.** Divisible by 3:
3, 6, 9, 12, 15. Divisible by 5: 5, 10, 15. In order of `n`, with 15 twice:
**3, 5, 6, 9, 10, 12, 15, 15** — eight lines.

### What the third run found

Run on 2026-09-04 against 0.17.0, predictions committed first in `8c823df`.
The program and its output were re-run and diffed against the hand-computed
oracle here; it matches, byte for byte.

**Correct on the first compile-and-run, for the third time in three runs. And
no diagnostic was emitted, for the third time in three runs.**

| | |
| --- | --- |
| **12. The braces come off at least once** | **Wrong.** Braces on both conditionals, first attempt, never questioned. |
| **13. A hole-kind diagnostic is emitted** | **Wrong.** Zero, again. **Three readers, three tasks, and not one has seen a Parasol error message of any kind.** |
| **14. And this time it says what to do** | **Untested for the third time, and for a third distinct reason.** Run 1: the task had no cascade. Run 2: the dialect's eleven lines prevented it. Run 3: the example's braces prevented it. |
| **15. The design note does not prevent what the essay prevented** | **Untested.** Nothing reached the failure, so the note was never on trial. The middle case remains unmeasured. |
| **16. The example is the real competition** | **Right, and it is the finding.** *"`example.psol` was the single most useful document"*, supplying *"nearly 100% of what I needed"*, and the program was written *"by direct analogy"* with it. The prediction that cost something to write is the one that paid. |
| **17. The substrate still costs nothing** | **Right.** Zero `does not understand` probes, and the reader went to Solveig's reference by targeted `grep` rather than by guessing. Two runs now. |

### The README was read, and the section written for it worked

**Neither of the first two readers opened the front page.** This one opened it
**first**, met *Not here.* in its first two words, was sent to `clike.psol` and
`example.psol`, and — in their own words — *stopped reading README past that
point and did not go back to it later.*

That is the twenty-five lines added on 2026-09-04, doing exactly the job they
were added for, measured the same day. **It is the first evidence that any part
of `README.md` has ever been load-bearing for a reader.** The correct behaviour
for a front page is to be read once, briefly, and left.

### And the rule from run 2 does not hold as it was written

**The `print`-is-a-repr trap fired again — on a reader who had read the warning
about it.** `examples/clike.psol` has carried that warning since run 1, at the
line it is about. Run 2 caught the trap before it fired and called it *the one
that would have bitten me*. Run 3 read the same comment, quoted it back
accurately, wrote `:print` anyway, got `#3` where `3` was wanted, and said:

> the warning didn't fully land until I saw the actual output.

**Run 2 earned this sentence, and it is now in four documents:**

> A limitation explained where it is declared is not a limitation a reader pays
> for. It is one its author paid for once.

**It was generalised from one instance and the next instance contradicts it.**
`else if` and `print` are both limitations explained at their declarations, and
only one of them was prevented. What separates them is not how well either is
explained — the `print` comment is three lines and names the exact symptom:

| | |
| --- | --- |
| **`else if`** | A **refusal**. The reader must decide to type something, and the warning arrives before the decision. Reading it removes the option. |
| **`print`** | A **silence**. The wrong choice compiles, runs, and produces plausible output. The warning describes an outcome the reader cannot recognise until they have one to compare against — and by then they have already paid the cycle. |

> **A warning prevents a failure you would have chosen. It does not prevent one
> you would have walked into believing you had succeeded.**

Which is [does-it-pay.md](PARASOL-DOES-IT-PAY.md)'s own silence category arriving from
the documentation side: **the things that cost a reader are the silent ones,
and explaining a silence at its declaration does not make it loud.** That is
the narrowing, and it took a third reader because the second one produced a
sentence good enough to stop looking. [POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 26.

### What it cost, and the assist accounting

**No assists this run**, where run 1 had two. Everything the reader used —
the loop shape, `%`, the comparisons, `:display` — traces to `example.psol`,
`clike.psol` or Solveig's reference. The proxy's C and Smalltalk habits had
nothing to supply, because the example already supplied it.

**One cycle spent, and it was spent on the silence.** The reader resolved
`print` against `display` by grepping Solveig's reference, finding it
*ambiguous — no example shows `#N:display` with its output* — and then **writing
a five-line test program instead of reading further.** A three-command toolchain
with clean exits makes an experiment cheaper than a document, which is a point
in the toolchain's favour and a mark against the reference.

### The thing three runs now agree on and nobody designed for

**No reader has ever seen a diagnostic.** Three tasks, one of them built
specifically to force an error, and the compiler has never spoken to any of
them. Every hour spent on diagnostics — POSTMORTEM 22's caret, 0.16.0's
prescription, the map that is *tested harder than anything else here* — remains
**entirely unmeasured by the only population it exists for.**

That is not an argument that the work was wrong. It is an argument that the
justification for it is still the author's reasoning and not a reader's
experience, and after three runs that should be said plainly rather than
waited out.

**A fourth run then said it again**, and retired the question rather than asking
it a fifth time — *What the fourth run found*, below. This paragraph is run 3's
and its count is run 3's; [POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 25 is why it says so
rather than leaving a reader to reach the end and carry away *three*.

### What the third reader actually wrote

Kept here because the findings above cite it and nothing else in this
repository holds it — a reader run leaves its artifacts in a scratch directory
that does not survive the session, and a claim about a program nobody can read
again is a claim on trust.

```parasol
@use "clike.psol".

n = #1.
while (n <= #15) {
    if (n % #3 == #0) { n:display }.
    if (n % #5 == #0) { n:display }.
    n = n + #1
}.
```

Output, verified against the hand-computed oracle: `3 5 6 9 10 12 15 15`.

## The fourth run, and the customer the first three did not test

**Predictions recorded before it, as all three earlier runs' were.**

Three runs have now failed to reach a diagnostic, each for a different reason,
and the honest reading is that **an ordinary user of a well-documented dialect
does not meet one**. The obvious way to force it is to hand a reader
`lib/clike.psol` with its eleven lines removed. **That is refused**, for the
reason run 3 refused it: it would measure a file written for the measurement.

**So the reader's role changes instead.** 0.16.0's own justification names a
customer that runs 1 to 3 did not contain:

> `lib/clike.psol`'s author paid it, and every future dialect with a `block` hole
> has an author who has not.

Every reader so far has *used* a dialect somebody else wrote. **None has written
one.** And nothing in the published surface models it: `examples/forms.psol`
declares four forms and types **no hole at all**, so a reader authoring a form
with a `block` hole has no example to copy — which is the condition the first
three runs never had.

### What varies, and what is held

| | |
| --- | --- |
| **The reader's role** | **Author, not user.** They declare a form of their own and then call it. This is the second of 0.16.0's two customers and the first time either run has been aimed at it. |
| **The task** | Declare a `banner` form that rules a line, runs a body, and rules another line; use it three times — **once around a single statement**, which is where braces get dropped in every language that allows it. |
| **The surface** | **Everything published**, and a superset of what runs 1 to 3 got: `README.md`, `REFERENCE.md`, all of `lib/`, all five examples, and Solveig's reference. Nothing is withheld and nothing is edited. |

**This varies two things at once**, so it is **not comparable to runs 1 to 3 on
the reader axis** and is not offered as a fourth point on that line. It measures
a different customer.

### The two outcomes, checked before the run rather than reasoned about

| the author writes | what the toolchain does |
| --- | --- |
| `@syntax banner <b: block>` then `banner "hi":display.` | **The diagnostic**, at the use, with 0.16.0's `wrap it in braces` under it. Refused before anything runs. |
| `@syntax banner <b>` then `banner "hi":display.` | **Compiles clean.** Prints `-----`, prints `hi`, then dies: `string does not understand 'value'` — naming a line in the **generated `.sol`**, which the author never wrote. |

**The second is the failure this project was built to prevent**, and 0.6.0's
hole kinds are what stand in front of it. No reader has met it either.

### What is predicted before it is run

| | |
| --- | --- |
| **18. The hole is typed `block`.** | `REFERENCE.md` documents the five kinds, and both shipped dialects show `<b: block>` at a declaration. Against it: untyped is the default, shorter, and `examples/forms.psol` — the only example of *declaring* forms — types nothing. **This is the prediction the run turns on**, and it is close to even. |
| **19. The single-statement use loses its braces.** | `banner "hello":display.` is what a person types when the body is one thing. The other two uses are multi-statement and will be braced. |
| **20. A diagnostic is emitted — the first in four runs.** | Conditional on 18 and 19 both holding. |
| **21. And the prescription is enough on its own.** | The real prediction 9, still untested at the fourth attempt. Predicted: the author goes from `wrap it in braces` to the fix **without opening a document**, and the log shows it. This is the measurement 0.16.0 shipped without. |
| **22. If 18 goes the other way, the finding is worse and better.** | An untyped hole gives a run-time error in a generated file, after partial output, naming a line the author never wrote. **That is the characteristic failure of a declared grammar**, the one `README.md` says the map and the diagnostics exist to stand in front of, and no reader has ever met it. Predicted: if it happens, it costs more cycles than any single thing in runs 1 to 3. |
| **23. A fourth failure to reach it settles a different question.** | If braces go on everywhere again, then **four tasks, two of them built to force an error, have produced none** — and the conclusion is about the diagnostic's reachability rather than about its wording. Predicted as the outcome that ends this line of experiment rather than extending it. |

**The oracle**, worked out by hand. The task asks for three uses: a single
statement printing `hello`, two statements printing `one` and `two`, and a
computation printing the sum of 1 to 4. Each banner rules five dashes either
side, so that is **3 + 4 + 3 = ten lines**:

```text
-----      -----      -----
hello      one        10
-----      two        -----
           -----
```

**Whether the last body prints `10` or `#10` is the reader's choice** between
`display` and `print`, and both are correct — run 3 established that this is a
real fork and not a mistake, so the oracle does not fix it.

### What the fourth run found

Run on 2026-09-04 against 0.17.0, predictions committed first in `9f2c22d`.
The final program was re-run here and diffed against the ten-line oracle; it
matches.

**Two attempts. And for the fourth time in four runs, Parasol emitted nothing.**

| | |
| --- | --- |
| **18. The hole is typed `block`** | **Right.** `@syntax banner <b: block>`, and the author says where it came from: *I copied the shape from `lib/control.psol`'s `repeat <n> times <b: block>`* — the only precedent in the surface for a form whose whole argument is a body. |
| **19. The single-statement use loses its braces** | **Wrong.** `banner { "hello":display }.` — braced, first attempt. Same cause as run 3, one level up: `examples/dialect.psol` shows `repeat #3 times { "tick":display }`, a **one-statement body wearing braces**, and that is the model that got copied. |
| **20. A diagnostic is emitted** | **Wrong.** `parasol` exited 0 with no output. **Four runs, four tasks, two of them built to force an error, and no reader has yet seen a Parasol diagnostic of any kind.** |
| **21. The prescription is enough** | **Untested, fourth time.** |
| **22. If untyped, a runtime error in generated source** | **Not applicable by its own terms** — 18 held, so the untyped path was never taken. **But the failure it describes happened anyway, by a route nobody predicted.** See below. The class was predicted and the mechanism was wrong. |
| **23. A fourth failure settles reachability** | **Right, and it is the conclusion.** |

### The characteristic failure finally happened, and not through a hole kind

Attempt 1 assigned `total` and `i` inside a `banner` body without declaring
them. **`parasol` exited 0. `solas` exited 0.** Then:

```text
solvm: undefined name 'total' -- declare it with '| total |' or assign it at the top level
  [banner.sol:8] in block
  [banner.sol:11] in script
-----
hello
-----
-----
one
two
-----
-----
```

**An error naming a file the author never wrote, after seven lines of correct
output.** That is the failure [README.md](PARASOL.md) names as the one that
kills syntax-extension systems — *somebody writes one thing, is shown an error
about another, and cannot get from the second back to the first* — and it is the
first time any reader has met it. Four runs in, it arrived from the substrate
rather than from anything Parasol declares.

**The map that recovers it was never written.** Reproduced here: the map's line
for generated `8:5` is source `10:5`, which is `total := #0.` in the reader's
own file. The machinery works, exactly as designed, and it was switched off —
the map is opt-in behind `--map`.

> **The one failure this project built two mechanisms against reached a reader
> with one of them turned off, and the reader got out on the strength of the
> substrate's error text instead.**

**They self-diagnosed from the message alone** — their words, case (a): *the
error message alone told me exactly what to do*, `declare it with '| total |'`.
They read Solveig's binding rules afterwards only to confirm why, having
*already typed the edit*. **Solveig's diagnostic did the job Parasol's has never
been given a chance to do.**

### The confound, stated rather than buried

**The reader was given a command line that omits `--map`. `README.md`'s own
quickstart includes it.** That difference is the experimenter's and not the
reader's, so this run establishes one thing and not the other:

| | |
| --- | --- |
| **Established** | Without a map, a runtime error names generated source and there is nothing to get back with. With one, the recovery is exact. |
| **Not established** | Whether a reader left to themselves would omit `--map`. They were told to. |

**So the rough edge is not settled by this run**, and the argument it makes is
still worth something: the run shows what the *minimal* invocation costs, and
*the default should probably change* is a claim about exactly that invocation.
[POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 27 is the method failure, which is mine.

**And even with the map, recovery is manual.** `solvm` knows nothing about
`.sol.map`; a person reads it. The map makes getting back *possible*, not
automatic.

### What four runs now say about the diagnostics

**No reader has seen one.** Not the caret POSTMORTEM 22 fixed, not 0.16.0's
prescription, not a hole-kind failure of any sort. Four tasks, and the two
designed specifically to produce one produced none — the first stopped by a
dialect's essay, the second by an example's braces.

> **Every reader has been served by three things, and Parasol's diagnostics are
> not among them: the example, the dialect file, and Solveig's runtime errors.**

That is not an argument that the diagnostics are wrong. It is an argument that
**four runs is enough to stop expecting a reader to find out**, and that the
next thing aimed at them should be aimed somewhere a reader actually looks.
Prediction 21 is retired unmeasured rather than asked a fifth time.

### One thing the design got right, unprompted

The author expected to need two declarations for the one-statement and
multi-statement cases, *the way `control.psol` needs two for `if` and `if/else`*,
and did not: one `<b: block>` hole takes `{ a }` and `{ a. b }` identically.
**A hole that asks for a block does not care how much is in it**, which nobody
had written down because nobody had doubted it.

### What the fourth reader actually wrote

Attempt 2, the working one. Attempt 1 is identical but for the third body's
`{`, which carried no `| total, i |` and produced the run-time failure above.

```text
; banner.psol -- a module declaring its own `banner` notation: a ruled line
; above and below whatever it wraps.

@use "../parasol-lang/lib/control.psol".

@syntax banner <b: block> => ("-----":display. b:value. "-----":display).

banner { "hello":display }.

banner { "one":display. "two":display }.

banner { | total, i |
    total := #0.
    i := #1.
    while i <= #4 do (total := total + i. i := i + #1).
    total:print
}.
```

Output: the ten lines of the oracle, with `#10` for the total — the reader
chose `:print` over `:display` knowing what it would render, which run 3
established is a real fork rather than a mistake.
