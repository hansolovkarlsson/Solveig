# What Parasol found in Solveig

*A running log while Parasol was a repository of its own, kept there rather
than raised here, so that each entry was written where it was found and could
be taken into Solveig's numbering when somebody decided it was worth taking.
Since 2026-09-15 it is a page of Solveig's documents and the log is closed:
the four findings still open became [3.28 to 3.31](ROADMAP.md#3-known-limitations)
on the roadmap, each pointing back here for the account, and a finding after
this date is Solveig's own and goes to the roadmap directly. They were 3.23
to 3.26 for a day, until the count was found to have reused a number; the
roadmap says so.*

**This is what a second customer is for.** solveig-sdl's README says the same
thing about `sol_symbol_intern` — reachable and not promised, promised now
because a second binding wanted it. Parasol is a customer of a different part:
not the extension ABI but the compiler and the machine as *programs*, driven
from a command line by something that generated their input.

Entries 1 to 4 are open, and numbered on the roadmap; 5 is an inventory and
was never a request. Nothing here is a blocker.

---

## 1. Program output and a runtime error come out in the wrong order

*Roadmap 3.28.*

**Kind:** defect, small, one line.

**What happens.** A program that prints and then fails shows its error *before*
its output, whenever standard output is not a terminal.

```sh
$ printf 'x := #1.\nx:print.\nx:notAMessage.\n' > rt.sol
$ solas rt.sol -o rt.sob
$ solvm rt.sob 2>&1 | cat
solvm: integer does not understand 'notAMessage'
  [rt.sol:3] in script
#1
```

`x:print` runs on line 2 and the failure is on line 3, so `#1` should come
first — and it does, interactively:

```sh
$ script -q /dev/null solvm rt.sob
#1
solvm: integer does not understand 'notAMessage'
  [rt.sol:3] in script
```

**Cause.** Standard output is block-buffered when it is not a terminal and
standard error is not buffered at all, so the error overtakes everything the
program printed and has not flushed. Interactively stdout is line-buffered and
the ordering happens to be right, which is why this is invisible until something
captures both.

**Suggested fix.** `fflush(stdout)` before a runtime error is written to stderr.
Probably also before the machine stops for `--steps` or `--memory`, which fail
the same way.

**Why it matters here.** `make test` in Parasol runs every example through
`solvm` and captures both streams. A failing example's last output is the first
thing you want and the last thing shown, and the misordering reads as *the print
never happened* rather than as a buffering artefact.

---

## 2. A generated file cannot say where it came from

*Roadmap 3.29.*

**Kind:** missing capability. Not urgent; the difference between a manual step
and none.

**What happens.** Both tools report positions in the file they were handed, and
there is no way to tell either one that the file is generated.

```text
[syn.sol:2:1] solas: expected '.' between statements at 'y'
solvm: integer does not understand 'notAMessage'
  [rt.sol:3] in script
```

Parasol compiles `vectors.psol` to `vectors.sol` and writes `vectors.sol.map`
beside it, so the information exists — but it exists on Parasol's side, and
`solas`, `solvm` and `solid` all name the generated file. Everybody who is not
Parasol has to look the position up by hand.

**What would close it**, roughly in order of how little it asks of Solveig:

| | |
| --- | --- |
| `solas --source-name=<path>` | The path recorded in the chunk, rather than the one on the command line. One flag, one field. Fixes the *file*, not the *line*. |
| A `#line`-style directive in source | `@line 25 "vectors.psol".` setting what the next statement records. Fixes both, costs a directive and a lexer case. Every generated-source language ends up with one. |
| The chunk carrying a map | Right, and much larger, and not worth it before something asks. |

**Why it matters here.** It is the one thing that would make Parasol's map
consumed rather than merely written. Parasol is deliberately built so that
`solas` needs nothing from it, so this is a request rather than a dependency —
and the first option alone would already turn *a line in a file you did not
write* into *a line in a file you did not write, from one you did*.

**Note.** `[rt.sol:3]` at run time means the path and line are already in the
`.sob` and already reported. The mechanism is there; what is missing is a way to
set what goes into it.

---

## 3. The machine counts instructions and will not say how many

*Roadmap 3.30.*

**Kind:** missing capability. Small, and the workaround works — it just costs
one run per bit.

**What happens.** `--steps=N` stops a program after N instructions, so the
machine is counting. Nothing reports the count. A program that finishes says
nothing and exits 0; one that is stopped says *the step limit of 100 was
reached* and exits 124, naming the limit rather than the position.

```sh
$ solvm --steps=100 m.sob
solvm: stopped: the step limit of 100 was reached
  [m.sol:2] in block
$ solvm --steps=200000 m.sob        # finishes, says nothing
$ echo $?
0
```

**The workaround, which Solveig's own documents describe.**
`programs.md` measures `sha256sum` this way: *the smallest N that lets a run
finish is that run's exact count, and a binary search finds it.* It is exact and
it is correct. It is also **28 runs of the program** to learn one number the
machine had after the first one, and each run is a full execution — measuring a
one-second program costs half a minute.

**Suggested fix**, smallest first:

| | |
| --- | --- |
| `--steps` with no `=N` | Run to completion and write the count to stderr. One flag spelling, one `fprintf`, no new machinery. |
| A count in the `--steps=N` stop message | *stopped at instruction N of a limit of N* is the same number this already knows. Helps a stopped run, not a finished one. |
| `system:steps` | The count from inside the program. Larger, and it changes what a program can observe about itself, which is a decision rather than a flag. |

**Why it matters here.** `programs/digest` exists partly to
measure what a Parasol template costs against a Solveig method, and the answer —
2.03 instructions per rotation against 2.00 — is a difference of 5% found by
running two programs 56 times. Two runs would have done. The number is the whole
point of that program, and it is the one thing the machine will not hand over.

**Not a blocker, and not urgent.** The binary search is in a nine-line shell
script in Parasol's history and can be lifted by anybody who wants it.

---

## 4. A run-time trace carries a line and no column

*Roadmap 3.31.*

**Kind:** missing functionality, small; matters more to a generated file than
to a written one.

**What happens.** A compile error is reported with a column,
`[prog.sol:1:7] solas: ...`, and a run-time frame is not:

```text
solvm: integer does not understand 'asStrin'
  [bignum.sol:27] in block
  [calc.sol:16] in block
  [calc.sol:17] in script
```

**Why it matters here.** Parasol's map is exact to the column, and a generated
line is often a span: a `while` body or an `if` arm is emitted on one line, so
`bignum.sol:27` is `bignum.psol` lines 54 to 57 and the map cannot narrow it
without a column to look up. Sixteen of that library's 103 generated lines are
spans. A four-line answer is a recovery; the exact one is what the map was
built to give.

**Expected.** `[bignum.sol:27:10] in block`, the column of the send that
failed, which the compiler had when it emitted the instruction. **Observed.**
The line alone.

**Suggested fix.** Carry the column in the line table beside the line, and
print it in the frame. The other half is Parasol's, keeping a source line break
inside an expanded hole, and is on its roadmap under *Rough edges*; either
alone would do, and this one helps every generated file, not only Parasol's.

**Not a blocker.** Found on 2026-09-13 by `programs/bignum`, which put a
deliberate error in a copy of its library to test the map across two modules.

## 5. What a large-number library wants, and what Python's `math` has that Solveig does not

**Kind:** an inventory, not a request. Written because Hans asked, with
`programs/bignum`, whether a maths extension in the shape of `extensions/net`
is wanted, and whether Python's `math` module is the measure of *advanced
maths*.

**A bignum is a library.** `programs/bignum/bignum.sol` is 126 lines of
generated Solveig, correct against `bc`, and nothing in it needed a capability
the machine lacks. What it wanted and could not have is a product wider than
64 bits, and no scripting language's integers offer that either: CPython keeps
30-bit digits in C for the same reason this keeps nine decimal ones. The trap
on overflow is what fixed the base, and it fixed it correctly. The case for a
C extension is speed alone: `1000!` takes 40 ms at `-O2` against 0.24 ms for
CPython's `int`, 170×, and no program has waited for it. If one does, the
shape is `net`'s, a global holding primitives, and the measurement comes
first.

**Python's `math` is a different question**, being float mathematics rather
than large integers, and most of it sorts by 3.14's own argument: a function a
program cannot write correctly for itself is a primitive, and one it can is
`lib/math.sol`. Against Solveig's `float` today, which has `floor`, `ceiling`,
`rounded`, `truncated`, `sqrt`, `pow`, `exp`, `log`, the six trigonometric
messages, `float:pi` and `float:atan2`:

| would be primitives, being C-library calls a program cannot reproduce | `log2`, `log10`, `log1p`, `expm1`, `exp2`, `cbrt`, `hypot`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, `atanh`, `erf`, `erfc`, `gamma`, `lgamma`, `frexp`, `ldexp`, `nextafter`, `ulp` |
| would be `lib/math.sol`, being arithmetic a program can write | `degrees`, `radians`, `fabs`, `copysign`, `fmod`, `remainder`, `modf`, `isclose`, `dist`, `fsum`, `prod`, `sumprod`, and on integers `gcd`, `lcm`, `isqrt`, `factorial`, `comb`, `perm` |
| constants | `e` and `tau` beside `float:pi`; `inf` and `nan` are already `infinity` and `nan` |

`fsum` is the one in the second row that is not obvious: a correctly rounded
sum is Shewchuk's algorithm, which can be written in Solveig and is not short.
Nothing in either row was wanted by any of the seven programs here, which is
the standing rule's answer for now: a surface does not grow without a
customer, and the customer names the row.

## A prediction about Solveig that was wrong

`programs/ember` is a lexer, a recursive-descent parser and an ARM64 code
generator, written in Parasol and run on SolVM. Its README predicted that
**Solveig would bite before Parasol did** -- most likely
[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame), a block
outliving the frame it was written in, since `lib/scan.sol` had already hit it
and said so.

**It did not.** Recursive blocks held in globals and called from inside other
blocks, an AST of `object:new` with slots assigned after the fact, arrays of
arrays, `system:arguments`, `system:readFile`, and `fill` doing every line of
the assembler -- none of it complained. `lib/scan.sol` did the cursor work and
`lib/text.sol` was included and, as it turned out, not needed.

Recorded because a prediction that was written down and then failed is worth
more than one that was never made, and because it is a data point for 3.1: a
program of this shape does not reach it.

## Not defects, recorded so they are not re-found

**Solas is single-pass and has no tree.** `sol_compile(source, chunk)` runs the
parser straight into the emitter. This is why Parasol owns a tree instead of
borrowing one, and it is the right shape for Solveig — noted so that the next
person to look does not read it as an omission. See [PARASOL.md](PARASOL.md),
*What Parasol is allowed to know about Solveig*.

**Integer arithmetic traps rather than wrapping, and that is right.** It is what
made `programs/digest` interesting rather than what made it hard: SHA-256 is
defined on mod-2^32 arithmetic, Solveig's own `programs/sha256sum` pays for the
difference in twenty-three hand-written `bitAnd`s, and Parasol's version pays for
it once in a header. A language that wrapped silently would have been the
convenient choice and the wrong one. Recorded so that *a hash program wanted
wrapping* is not read as a request for it.

**`shiftLeft` refusing to lose the number never fired.** The largest shift in a
32-bit rotation moves a value under 2^32 left by thirty places, which is
2^62-ish and fits. Solveig's own program says the same about
[3.12](ROADMAP.md#312-no-shift-can-produce-a-negative-integer); a second
program of the same shape confirms it rather than finding an edge.

**`display` and `print` both end the line.** There is no *write this and stay on
the line* among them — `system:write` is that, and [REFERENCE.md](REFERENCE.md) says so. A line
with two things on it is built and then written once, which is what
`programs/digest` does. Recorded because reaching for `display` twice and
getting two lines looks like a bug for about a minute.

**`:not` and `:not()` are the same send.** Parasol emits the first. Confirmed
against the grammar, which makes an argument list optional; recorded because it
looks like a difference and is not.
