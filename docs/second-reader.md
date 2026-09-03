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
