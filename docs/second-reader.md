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

Written after.
