# What Phoenix has found in Solveig

A running log, kept here rather than raised there, so that each entry is written
where it was found and can be taken into Solveig's own numbering when somebody
decides it is worth taking.

**This is what a second customer is for.** solveig-sdl's README says the same
thing about `sol_symbol_intern` — reachable and not promised, promised now
because a second binding wanted it. Phoenix is a customer of a different part:
not the extension ABI but the compiler and the machine as *programs*, driven
from a command line by something that generated their input.

Entries are open unless marked otherwise. Nothing here is a blocker.

---

## 1. Program output and a runtime error come out in the wrong order

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

**Why it matters here.** `make test` in Phoenix runs every example through
`solvm` and captures both streams. A failing example's last output is the first
thing you want and the last thing shown, and the misordering reads as *the print
never happened* rather than as a buffering artefact.

---

## 2. A generated file cannot say where it came from

**Kind:** missing capability. Not urgent; the difference between a manual step
and none.

**What happens.** Both tools report positions in the file they were handed, and
there is no way to tell either one that the file is generated.

```
[syn.sol:2:1] solas: expected '.' between statements at 'y'
solvm: integer does not understand 'notAMessage'
  [rt.sol:3] in script
```

Phoenix compiles `vectors.phx` to `vectors.sol` and writes `vectors.sol.map`
beside it, so the information exists — but it exists on Phoenix's side, and
`solas`, `solvm` and `solid` all name the generated file. Everybody who is not
Phoenix has to look the position up by hand.

**What would close it**, roughly in order of how little it asks of Solveig:

| | |
| --- | --- |
| `solas --source-name=<path>` | The path recorded in the chunk, rather than the one on the command line. One flag, one field. Fixes the *file*, not the *line*. |
| A `#line`-style directive in source | `@line 25 "vectors.phx".` setting what the next statement records. Fixes both, costs a directive and a lexer case. Every generated-source language ends up with one. |
| The chunk carrying a map | Right, and much larger, and not worth it before something asks. |

**Why it matters here.** It is the one thing that would make Phoenix's map
consumed rather than merely written. Phoenix is deliberately built so that
`solas` needs nothing from it, so this is a request rather than a dependency —
and the first option alone would already turn *a line in a file you did not
write* into *a line in a file you did not write, from one you did*.

**Note.** `[rt.sol:3]` at run time means the path and line are already in the
`.sob` and already reported. The mechanism is there; what is missing is a way to
set what goes into it.

---

## 3. The machine counts instructions and will not say how many

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

**Why it matters here.** `programs/digest` in this repository exists partly to
measure what a Phoenix template costs against a Solveig method, and the answer —
2.03 instructions per rotation against 2.00 — is a difference of 5% found by
running two programs 56 times. Two runs would have done. The number is the whole
point of that program, and it is the one thing the machine will not hand over.

**Not a blocker, and not urgent.** The binary search is in a nine-line shell
script in this repository's history and can be lifted by anybody who wants it.

---

## A prediction about Solveig that was wrong

`programs/ember` is a lexer, a recursive-descent parser and an ARM64 code
generator, written in Phoenix and run on SolVM. Its README predicted that
**Solveig would bite before Phoenix did** -- most likely
[3.1](https://hansolovkarlsson.github.io/Solveig/docs/ROADMAP.html), a block
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
parser straight into the emitter. This is why Phoenix owns a tree instead of
borrowing one, and it is the right shape for Solveig — noted so that the next
person to look does not read it as an omission. See the README here, *What
Phoenix is allowed to know about Solveig*.

**Integer arithmetic traps rather than wrapping, and that is right.** It is what
made `programs/digest` interesting rather than what made it hard: SHA-256 is
defined on mod-2^32 arithmetic, Solveig's own `programs/sha256sum` pays for the
difference in twenty-three hand-written `bitAnd`s, and Phoenix's version pays for
it once in a header. A language that wrapped silently would have been the
convenient choice and the wrong one. Recorded so that *a hash program wanted
wrapping* is not read as a request for it.

**`shiftLeft` refusing to lose the number never fired.** The largest shift in a
32-bit rotation moves a value under 2^32 left by thirty places, which is
2^62-ish and fits. Solveig's own program says the same about
[3.12](https://hansolovkarlsson.github.io/Solveig/docs/ROADMAP.html); a second
program of the same shape confirms it rather than finding an edge.

**`display` and `print` both end the line.** There is no *write this and stay on
the line* among them — `system:write` is that, and the REFERENCE says so. A line
with two things on it is built and then written once, which is what
`programs/digest` does. Recorded because reaching for `display` twice and
getting two lines looks like a bug for about a minute.

**`:not` and `:not()` are the same send.** Phoenix emits the first. Confirmed
against the grammar, which makes an argument list optional; recorded because it
looks like a difference and is not.
