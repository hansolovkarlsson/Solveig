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

## Not defects, recorded so they are not re-found

**Solas is single-pass and has no tree.** `sol_compile(source, chunk)` runs the
parser straight into the emitter. This is why Phoenix owns a tree instead of
borrowing one, and it is the right shape for Solveig — noted so that the next
person to look does not read it as an omission. See the README here, *What
Phoenix is allowed to know about Solveig*.

**`:not` and `:not()` are the same send.** Phoenix emits the first. Confirmed
against the grammar, which makes an argument list optional; recorded because it
looks like a difference and is not.
