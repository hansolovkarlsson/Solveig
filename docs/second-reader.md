# The second reader

*[does-it-pay.md](does-it-pay.md) weighs six programs and ends on the one thing
none of them tested. This is the design for testing it, and the predictions,
recorded before it is run.*

> What no program has yet tried is a dialect used by **somebody who did not
> write it** — every dialect here was written by the author of the file that
> uses it, an hour before, and a notation's real cost is paid by the second
> reader.

**It needs nothing added to Proto**, which is why it is next. Six programs have
made every other open question smaller and left this one exactly where it
started.

**And it stopped being hypothetical on 2026-09-03**, when Solveig's README began
linking this repository. The second reader is about to exist whether or not
there is a measurement of what they pay.

## The design

| | |
| --- | --- |
| **The dialect** | `lib/clike.pro`. It is shipped, standalone, documented in [REFERENCE.md](REFERENCE.md), and the only one written for readers rather than for one program — `interp.pro` and `sha2.pro` name their program's globals and are explicitly not reusable. |
| **The reader** | Somebody who did not write it and has not read this repository. The available proxy is a session with no context, given the published surface and nothing else. **A proxy is not a person**; what that costs is under *How it is checked*. |
| **What they get** | Everything published: `README.md`, `REFERENCE.md`, `lib/clike.pro` and `examples/clike.pro`. **Nothing is withheld**, because a stranger arriving from Solveig's front page gets all of it, and testing a smaller surface would test a strawman. |
| **The task** | Print every pair `(a, b)` with `1 ≤ a < b ≤ 6` whose product is even, then how many there were. A nested loop, `%`, `&&`, a comparison, a counter and two kinds of printing — and **nothing in `examples/clike.pro` to copy**, which has no nested loop and no counter. |
| **What is recorded** | Every attempt, in order; every diagnostic; every time a document is opened and which one; and for each failure, whether the message alone was enough to fix it. |

## What is predicted before it is run

| | |
| --- | --- |
| **1. The example is load-bearing, and the operator table is not enough on its own.** | `REFERENCE.md`'s clike entry is two tables of operators and forms. It does not mention `#` on an integer, `.` where C writes `;`, or how to print — and none of the three is a thing a *dialect* has, so no operator table could carry them. Predicted: `examples/clike.pro` is opened in the first minute and consulted more often than either table, **and the finding is a cost `does-it-pay.md` has never counted** — a dialect does not document itself, and every dialect here was written by somebody who needed no example. |
| **2. Every expensive mistake is at the dialect/substrate boundary, and none is in the notation.** | The operators and forms *are* C's: `=`, `&&`, `%`, `while`, `if`/`else`. Predicted to cost nothing at all. The three predicted failures are `1` for `#1`, `;` for `.`, and not knowing how to print — **Solveig's lexer and Solveig's library, neither of them anything `lib/clike.pro` could have said.** If that holds, *a dialect ends at its domain* has a second face: it also ends at its **substrate**, and the reader meets that edge before they meet the domain's. |
| **3. Only one of the three survives compilation, and it is the bare integer.** | `;` and a missing `print` are syntax and message errors with a line and a caret. A bare `1` **is a valid float in Solveig** — checked: `(1):class` answers *float does not understand 'class'* — so `a = 1` compiles, runs, and gives a float where an integer was meant, and `%` on it answers something plausible. Predicted: the only mistake that reaches a wrong answer instead of an error, and **the first entry in `does-it-pay.md`'s silence table contributed by a reader rather than an author.** |
| **4. The `else if` chain is hit, and the diagnostic is now the thing on trial.** | Checking this rather than asserting it found [POSTMORTEM.md](POSTMORTEM.md) 22: the error pointed into `lib/clike.pro`'s template and named the reader's own file nowhere but the summary line. **Fixed in 0.15.0 before this is run**, deliberately — measuring in front of it would have scored the defect and not the notation. So the message now names the reader's line and underlines the whole nested `if`, and the prediction is what it should have been: **the position is right and the message still does not say what to do.** It names the hole's kind, not the nested-brace workaround, and predicted: the reader finds that in `examples/clike.pro`'s comment rather than in the error. If so, **a diagnostic that points correctly and prescribes nothing is the next thing to fix**, and this is the first evidence for it from somebody who could not already know the answer. |
| **5. `for` and `i++` cost nothing, and that is a result rather than a shrug.** | Neither exists; both are named in [ROADMAP.md](ROADMAP.md) as things C has that Proto cannot. Predicted: noticed within seconds, substituted without complaint, and **not recorded as friction by the reader at all** — because an absent thing announces itself at the first attempt. Set against 3, that is the shape of every finding in `does-it-pay.md`'s cost table: **absence is cheap and silence is expensive.** |
| **6. This measures one half of the cost and will be quoted as both.** | *A notation's real cost is paid by the second reader* has two halves — **learning it once**, and **reading somebody else's code in it a year later.** This design measures the first and cannot touch the second, there being no year-old Proto and no second author. Predicted: the result gets cited as though it settled the sentence. Written down now so that it settles the half it settles. |

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

**And the task is checked against a hand-computed answer**, as the six programs
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
| **1. The example is load-bearing** | **Right, and by more than predicted.** `examples/clike.pro` and `lib/clike.pro` were opened first, together, before anything else was read — and never opened again. `README.md` was **never read in full**; it was grepped, twice, after the fact. The syntax came entirely from the example plus one table. |
| **2. Every expensive mistake is at the dialect/substrate boundary** | **Right, and it is the finding.** In the reader's own words: *all of my friction was on the other side of the compiler.* The notation cost **nothing** — `=`, `%`, `&&`, `while`, nested `if`, the precedence rungs, all correct first time and none of them remarked on. |
| **3. The bare integer is the only mistake that survives compilation** | **Wrong about the instance, right about the class.** No bare integer was ever written: `#` came out of the example inside the first minute and never came up again. **The prediction described a reader who skips the example, and an example was provided.** But a silent failure did happen, by another route — see *print is a repr* below — so the silence class got its reader-contributed entry, from a mechanism nobody had named. |
| **4. The `else if` chain** | **Not tested, and that is a fault in the design rather than a result.** The task wanted a nested loop and needed no branching cascade, so the chain was never written. The one prediction aimed at a known rough edge got no evidence, and a second run would have to ask for the shape that produces it. |
| **5. `for` and `i++` cost nothing** | **Right, and understated.** `while` and `b = b + #1` were written without comment. Neither absence appears **anywhere in the reader's log** — not as friction, not as a workaround, not as a remark. Absence is not merely cheap; it was invisible. |
| **6. This measures one half of the cost** | **Stands, and is now load-bearing.** One reader, one task, one hour. It says what learning the notation costs and nothing about reading somebody else's code in it. |

### A stranger declared an operator in their first program

Nobody predicted this and it is the strongest single result. Needing to join
strings, the reader wrote:

```
@use "lib/clike.pro".
@infix ++ 55 concat.
```

— an unprompted new operator, at a precedence chosen to sit under `+` at 60,
mixed into a module that also `@use`s a dialect. **The one thing this project
claims is that a programmer can declare notation, and the first stranger to
touch it did so in their first program, unasked, and got it right.**

### `print` is a repr, and the example teaches it wrongly

The one thing the reader expected and got wrong:

```
"big":print.        ; "big"   -- with the quotes
"big":display.      ; big
```

`examples/clike.pro` sends `:print` to a string **seven times** and shows the
output of none of them. Its only two output comments — `; #40` and `; #3` — are
on **integer** prints, where `print` and `display` are indistinguishable.

> **The example demonstrates the message exactly where its trap is invisible.**

That is a defect in a shipped example, it is what cost this reader their second
cycle, and it is fixed alongside this entry: the string prints now carry their
real output.

### The published surface documents a dialect and not its substrate

The largest finding, and the one with an action attached. Counting mentions
across everything a stranger is given:

| | README | REFERENCE | clike.pro | example |
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

> **The documents describe, exhaustively, how Proto turns operators into sends —
> and never say what sends exist.**

That is prediction 2 confirmed and then sharpened past where it was aimed. The
boundary is not merely where the *mistakes* are; it is where the *documentation
stops*, and a reader reaches it in their first statement, because a program that
computes anything must eventually print it.

**The fix is one line and it is made**: [REFERENCE.md](REFERENCE.md) now sends
the reader to Solveig's own reference for the message set, which is the half
this repository has no business restating and had never named.

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
| **9. And it still will not say what to do.** | This is the real prediction 4, restated where it can be tested. The message names the *hole's kind* — `'if' wants a block here, and this is a send` — which is true, unhelpful, and says nothing about nested braces. Predicted: the reader does **not** get from the message to the fix, and finds it in `examples/clike.pro`'s comment instead. **If so, a diagnostic that points correctly and prescribes nothing is the next thing to fix**, and this is the evidence for it. |
| **10. Two readers hit the same wall means it is the wall.** | Run 1 never reached the chain. If this reader is stopped by it, then the *only* construct in `lib/clike.pro` that costs a stranger anything is the one the ROADMAP already knows about — a hole's kind being one choice with no alternation, entered as *worked around, one customer*. Predicted: it gets its second customer, and the first from somebody who did not write the dialect. |
| **11. The substrate friction is mostly gone.** | Run 1 guessed `concat` and `asString` from zero documentation and found `display` by six probes. Solveig's reference lists all three. Predicted: **zero probes**, and the one-line fix in `REFERENCE.md` is worth more than the run that found it. If friction remains, it is that a reader must be *told* the pointer exists rather than tripping over it, which a link in a table does not guarantee. |

### What the second run found

Run on 2026-09-03 against 0.15.0, predictions committed first in `08a0149`.
Program and output re-run and diffed against a hand-computed oracle here.

**Correct on the first compile-and-run, again. No diagnostic was emitted at any
stage.** Two readers, two tasks, two first-attempt successes.

| | |
| --- | --- |
| **7. The chain is written the C way, first** | **Wrong, and it is the finding.** The reader wrote `else { if (…) { … } else { … } }` **on the first attempt** and never tried `else if`. Their reason, unprompted: *I would have tried `else if (n < #9) {` first if the dialect file had not spent a paragraph on it.* |
| **8. The diagnostic names their line** | **Check passes** — verified here rather than through the reader, who never saw it. `chain2.pro:5:6`, underlining the whole `else if`. 22's fix holds for this shape. |
| **9. And it still will not say what to do** | **Not tested, for the second time — and now for a much better reason.** Run 1 missed it because the task did not need a cascade. Run 2 missed it because **the documentation prevented the failure from happening.** The message's unhelpfulness is real and remains unmeasured, and two runs now say the same thing about why: nobody reaches it. |
| **10. Two readers hit the same wall means it is the wall** | **Wrong premise.** Neither reader hit it. One never met it; one was warned before they could. |
| **11. The substrate friction is mostly gone** | **Right, and it is the cleanest measurement of the day.** **Zero** probes against `does not understand`, where run 1 made six. The reader named `REFERENCE.md`'s *What is not here: the messages* as *the decisive signpost*, and went straight to Solveig's reference for `fill` and `display` instead of guessing. |

### A rough edge documented at its declaration costs a reader nothing

`lib/clike.pro` spends eleven lines, at the `else` form's own declaration, on
why a chain cannot be a chain — the `{ { … } }` that silently answers instead of
running, the `#54` where `#40` was right, and the spelling of the fix. The
example repeats it in two lines.

**A stranger read that and paid nothing.** No attempt, no diagnostic, no cycle.

> **A limitation explained where it is declared is not a limitation a reader
> pays for. It is a limitation its author paid for once.**

That is evidence about [ROADMAP.md](ROADMAP.md)'s alternation entry, which has
sat as *wanted by `lib/clike.pro`, worked around, one customer*. **Two strangers
have now been put in front of the workaround and neither noticed it was one.**
It is the fourth roadmap item this project has had answered by a customer
declining to need it, and the first answered by a customer being **told** in
advance.

### Both of the morning's one-line fixes were measured by the afternoon

Run 1 found two things and each got one line. Run 2 is the control:

| the fix | run 1 | run 2 |
| --- | --- | --- |
| `REFERENCE.md` names the message set as Solveig's and links it | 6 probes against `does not understand`, `concat` and `asString` guessed from nothing | **0 probes**, cited as *the decisive signpost* |
| `examples/clike.pro` shows what `:print` really prints | cost a cycle; the example taught it wrongly | caught it — *the one that would have bitten me* |

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
found* is where that is recorded.** [POSTMORTEM.md](POSTMORTEM.md) 25.

## The third run, and the thing it is aimed at

**Predictions recorded before it, as both earlier runs' were.** Committed here
before the reader is given anything.

**0.16.0 shipped on an argument and no measurement, and this is the
measurement.** The hole-kind diagnostic now carries `wrap it in braces -- '{'
before this and '}' after it`. Prediction 9 — *the message names the hole's kind
and says nothing about what to do* — is **untested twice**: run 1's task needed
no cascade, and run 2's reader was warned off by `lib/clike.pro`'s eleven lines
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

`lib/clike.pro` declares `if <c> <t: block>` and `while <c> <b: block>`, so a
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
| **14. And this time it says what to do, and that is enough.** | The real prediction 9, restated where it can finally be tested. 0.16.0 put `wrap it in braces` under the error. Predicted: the reader goes **from the message to the fix without opening a document**, and their log shows it. If they open `lib/clike.pro` or the example instead, the prescription did not carry and 0.16.0's argument is weaker than it reads. |
| **15. The design note does not prevent what the essay prevented.** | Predicted: the `if`/`while` note is not recalled, not cited, and does not stop the failure — **a limitation mentioned is not a limitation explained**, and only the second kind buys anything. That is the sentence run 2 earned, given its boundary. |
| **16. The example is the real competition, and it argues for braces.** | Every body in `examples/clike.pro` is braced, and both readers so far took their syntax from that example over any table. Predicted: **if 12 is wrong, this is why** — and that is a result about examples rather than about the diagnostic. Written down now so it cannot be a retrofit. |
| **17. The substrate still costs nothing.** | Run 2 made **zero** `does not understand` probes against run 1's six, after `REFERENCE.md` gained one sentence. Predicted: zero again — which would be that one sentence holding across two readers and two unrelated tasks. |

**The answer is worked out by hand, as the other two were.** Divisible by 3:
3, 6, 9, 12, 15. Divisible by 5: 5, 10, 15. In order of `n`, with 15 twice:
**3, 5, 6, 9, 10, 12, 15, 15** — eight lines.
