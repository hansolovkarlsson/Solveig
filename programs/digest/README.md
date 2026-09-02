# SHA-256, written in Proto

The digest of the FIPS 180-4 vectors, and of any file named on the command
line, computed by sixty-four rounds of shifts, rotations, exclusive-ors and
additions.

**Not a Proto feature.** A third program, written for the reason the first two
were — and this one has a customer that named itself.

## Why this one

`programs/ember` pressed on notation for something flat, `programs/grammar` on
notation for something recursive. Both leaned on `@syntax` patterns. **The
operator half of Proto has never had a customer**: `lib/arith.pro` declares
operators for arithmetic that Solveig can already write as sends, and
`examples/utf8.pro` is twenty lines.

Solveig's own `programs/sha256sum` wrote the gap down, in its own findings:

> **`@expr` has no bit operators**, so the one file here that is nothing but
> shifts, xors and masks is the one file that cannot use the notation at all —
> `&` and `|` are already the short-circuiting logical pair. One program is one
> program, and it is written down because a notation introduced for "a formula
> you are transcribing" met a formula it could not transcribe.

Proto's ROADMAP has claimed the answer to that in the abstract since 0.1.0 —
*Solveig's fixed infix region is the special case of what `@infix`
generalises* — with nothing to point at. This is the same algorithm on the same
substrate, one file with a fixed infix region and one that declares its own.

It also lands on a second thing Solveig measured and Proto has not:

> **A fifth of the program was a method call.** `rotr` written the obvious way —
> a method on the hash object — costs 0.73 MB/s; written out in the sixty-four
> rounds, 0.90; written out in the message schedule too, 1.06.

A Proto template is expanded, not called. So the readable spelling and the
fast spelling should be the same text here, which is a claim about run time that
no program has tested and no unit test can.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The formulas will transcribe.** | `Ch(x,y,z) = (x & y) ^ (~x & z)` should be that, in a file that declared `&`, `^` and `~` in its header. Predicted right, predicted the least interesting thing here, and predicted to be the whole of what `@expr` could not do. |
| **2. The dialect will carry a rule, not a spelling.** | Solveig's version needs **twenty-three `bitAnd`s written by hand**, because integers are 64-bit and trap rather than wrapping. Predicted: `+` is declared as *wrapping* addition and every one of them disappears into the operator — and the finding is that **a dialect can enforce a correctness discipline**, which is new in kind. Ember's and grammar's dialects only ever saved typing. |
| **3. A template that names a hole twice will evaluate it twice.** | `rotr` is `(x >> n) \| (x << (32-n))` and `left` appears on both sides of the bar. Proto has hygiene but no way to say *bind this once*. Predicted to bite, predicted to have no clean fix today, and predicted to be the sharpest finding **against** Proto. Mitigation predicted: rotations apply to plain variables, so the duplication re-reads rather than re-computes. |
| **4. Nothing folds the constants a template introduces.** | `x >>> #2` expands with `#32:sub(#2)` inside it, and that subtraction is a send at run time, once per rotation, ten times a round. Predicted: real, measurable, and correctly Proto's problem rather than Solveig's — an expander that does not evaluate is the whole reason `.pro` files can be read without running them. |
| **5. Notation pays like ember's, not like grammar's.** | Grammar's rule was that **a dialect pays per line it removes**, so a flat repetitive domain earns more than a small structured one. Sixty-four rounds of arithmetic is as flat as an assembler. Predicted: the biggest payoff of the three programs, per line. |

Predicted **not** to find: anything wrong with hygiene, `@use`, or the map —
three programs and no complaint from any of them. And `||`, one commit old, is
predicted to be irrelevant here: this file wants `^` and `&`, and its `\/` is
bitwise, which is the spelling that did not change.

## What it found

The three FIPS 180-4 vectors and five block-boundary cases, all eight agreeing
with `shasum -a 256` before anything here was committed, and the file mode
byte-identical to it including the two-space separator. `make test` runs them.

### The predictions

| | |
| --- | --- |
| **1. The formulas transcribe** | **Right, and as dull as predicted.** `t2 := (va >>> #2 ^ va >>> #13 ^ va >>> #22) + (va & vb ^ va & vc ^ vb & vc).` is Σ0(a) + Maj(a,b,c), in the precedences C uses, in a file whose header said so in nine lines. This is the whole of what `@expr` could not do, and it took nine lines to do. |
| **2. The dialect carries a rule** | **Right, and it is the finding of the program.** Solveig's version writes twenty-three `bitAnd`s by hand; this one writes **none**, because `+` *is* addition modulo 2³². A dialect here is not shorter code, it is code that cannot express the mistake. |
| **3. A template naming a hole twice evaluates it twice** | **Right, and it cost less than predicted.** `>>>` expands `left` four times, so `w:at(i - #1) >>> #17` fetches from the array four times. The mitigation predicted held — rotations apply to variables, so it is a re-read — but only because it was known while writing. Nothing in the language says so. |
| **4. Nothing folds a template's constants** | **Right, and it is measurable.** `x >>> #17` expands with `#32:sub(#17)` inside it, evaluated per rotation, 36,864 times in a 4 KB hash. Measured in isolation: **73,728 instructions, exactly 2.00 per rotation.** |
| **5. A template costs nothing at run time** | **Wrong as stated, and 4 is why.** It costs *less*, not nothing. |

### 4 and 5 are the same finding, and the numbers meet

A 4096-byte input, hashed once, with the exact instruction count found by
binary search on `--steps` — the method Solveig's own program used:

| | instructions |
| --- | ---: |
| `>>>` as an expanded template | **1,362,533** |
| `>>>` as a method on `integer` | **1,437,417** |
| what the template saved | 74,884 — **2.03 per rotation** |
| what the unfolded `#32:sub(#17)` cost | 73,728 — **2.00 per rotation** |

**The template gives back 98% of what it saves.** Proto avoids the frame and
the return that Solveig measured at a fifth of that program, and then spends it
recomputing a constant subtraction 36,864 times. The net is 1,156 instructions
in 1.36 million — 0.08%, which is nothing.

So the claim *a form is a method that costs nothing at run time* is **not true
today**, and the gap is one specific missing thing rather than a wrong idea. A
folding expander would take this program to about 1,288,805 instructions, a 5.4%
win, and would make the claim true.

**And it is not obviously safe**, which is why this is a finding and not a patch.
Folding `#32:sub(#17)` to `#15` means evaluating a send at expand time, and
`integer:sub` is a slot a Solveig program may assign. An expander that folds is
an expander that has decided some sends are safe to run — which is a smaller
version of the question [rules-and-logic.md](../../docs/rules-and-logic.md) asks
about guards, and it deserves the same treatment rather than a quick answer.

### What nobody predicted

**A wrong precedence is silent, and the operator half has its own version of
*choosing the shape wrongly*.** This file's first draft declared `*` and `%` at
60, the same rung as `+`, so `at + i * #4` parsed as `(at + i) * #4`. It
compiled without a word and ran, and what stopped it was an array index out of
bounds four calls deep in generated code. `lib/arith.pro` puts `*` at 70 for
this reason and this file did not copy it.

**A dialect ends at its domain, and there is no way to say where that is.**
`+` masking to 32 bits is right for every line of SHA-256 and wrong for a loop
counter. `while shift >= #0 do (... shift := shift:sub(#8))` is written with a
send precisely because `shift - #8` at zero would be `#4294967288` and the loop
would never end. The dialect is correct for the algorithm and a trap for the
scaffolding around it, and the file has to switch notations halfway down a
function with only a comment to say why.

**The collision rules got their first real customer, and the answer was not to
compose.** `@use "sha2.pro"` beside `lib/control.pro` collides on `+`, `-`, `~`
and `\/`, because control.pro uses arith.pro. Proto reports all four, names
both declarations and the whole `@use` chain, and says *this one wins, and
nothing else will say so* — which is exactly right and still leaves a program
that hashes wrongly if the header is in the other order. `sha2.pro` is standalone
for that reason, which is `lib/clike.pro`'s reason with correctness behind it
rather than taste.

**A dialect file must not declare `@language`.** Putting one in `sha2.pro` gives
*this module has already declared its language*, pointing at the used file. The
diagnostic is right and says nothing about the rule it is enforcing, which is
that a `@use`d file is read into the header of the module using it. It was the
first thing this program got wrong.

*Overtaken in 0.10.0: `@language` was removed, so this particular diagnostic is
gone. The rule it was enforcing sideways is unchanged and is now stated where it
belongs, in the README under* A dialect is a file.

### What did not come up

Hygiene, `@use` resolution, and the map: nothing, from a fourth program. The
`||` of one commit earlier was predicted irrelevant here and was — this file's
`\/` is the bitwise one, which is the spelling that did not change.

