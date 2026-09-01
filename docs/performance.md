# Speed, and what measuring it found

Solveig had never been compared with another implementation. Every number in
this repository was Solveig against an earlier Solveig, which tells you whether
a change helped and nothing at all about where the whole thing stands.

So it was measured against CPython 3.14: nine matched programs, each pair
verified to print the same answer before either was timed, run interleaved
through [bench.sol](../programs/bench.sol).

**It started level and ended ahead** — geometric mean 1.09, then 0.885 — and the
distance between those two numbers is the interesting part. Nothing was
rewritten and no algorithm changed. The comparison found three defects, and
**every one of them had been invisible from the inside**.

---

## The numbers

| Benchmark | What it does | Solveig | CPython | Ratio |
| --- | --- | ---: | ---: | ---: |
| float | 8,000,000 × square root, divide, add | 674 ms | 1412 ms | **0.48** |
| loop | sum 1 to 10,000,000 in a while loop | 453 ms | 844 ms | **0.55** |
| array | grow a 5,000,000-element array, then fold it | 347 ms | 634 ms | **0.56** |
| higher | `collect`, `select`, `inject` over 4,000,000 | 431 ms | 665 ms | **0.67** |
| object | 4,000,000 objects made, filled, messaged | 859 ms | 955 ms | **0.92** |
| strloop | scan 9,043,899 characters one `at` at a time | 632 ms | 643 ms | 1.01 |
| dict | 1,500,000 string-keyed inserts, then lookups | 1015 ms | 874 ms | 1.19 |
| strlib | join 2,000,000 strings, split them back | 533 ms | 359 ms | 1.57 |
| fib | `fib(34)` by recursive message send — 18M calls | 1038 ms | 549 ms | 1.96 |

Medians, with each runtime's own startup subtracted so the figures are the work
and not the launch. **Geometric mean 0.885**, ahead on five of the nine. The
character scan is the one genuine dead heat: measured end to end Solveig wins
it, and once its startup advantage is removed the two are within one percent.

| | Solveig | CPython |
| --- | ---: | ---: |
| Startup, hello world | 2.95 ms | 21.43 ms |
| Compiling source | 1.09M lines/s | 268k lines/s |

Apple M2 Pro, macOS 25.6.0. `solvm` 0.38.0 built `-O2`; CPython 3.14.7 from
Homebrew, no JIT, GIL enabled.

**Where it wins, it wins on representation.** A Solveig integer is sixty-four
bits in a register; a CPython integer is a heap object with a reference count,
allocated and freed on every arithmetic operation. Summing to ten million costs
Solveig an `add` instruction and costs CPython ten million allocations. Add
[conditionals and loops that compile to jumps](COMPLETED.md#41-conditionals-and-loops-are-real-calls--done)
and that is the whole of the first four rows.

**Where it loses, it mostly loses on tuning.** `str.split` and CPython's compact
dict have had years of SIMD scanning, key-sharing layouts and probe-sequence
work poured into them. Solveig's are correct, clear implementations of the same
operations. There is nothing structurally wrong to fix, which is a different and
much less interesting kind of gap — and it confirms from the outside what
[the editor's substitute pass](programs.md#edit--a-file-on-the-screen) found
from the inside: **a library's speed lives at the boundary with the
primitives.** That boundary is in the same place in both languages.

---

## What the comparison found

Three fixes. Each was measured before it was believed, and none of them is an
interesting idea.

**A heap object per character.** `string:at` answers a one-character string,
there being no character type, and it ended in a fresh allocation every time —
while `"o"` in the loop's condition is a literal, and the machine built a
literal fresh on every evaluation. A scan comparing each character against a
constant was making *two* strings a pass. The machine keeps one string per byte
value now, filled on first use, and the scan went from 2.13× CPython's time to
level. Interning every literal had been an open item for a month, held up
because it wants a weak table so long literals can still die; there are 256 byte
values and never more, so a table that size can be strong. **The bounded case
did not need the unbounded mechanism.**
[4.4](COMPLETED.md#44-a-one-byte-string-is-allocated-per-character-read--done).

**A hash lookup per variable.** This one the benchmarks had been hiding. In the
integer loop's profile, name lookup was 218 samples against the dispatch loop's
304 — far too much for a program that sends `add` and `inc` and nothing else.
The reason is that its counter is a *global*, because the loop is written at a
script's top level, so every read hashed the root object and every write hashed
it again. The same loop with the counter as a block temporary is **1.255×**
faster. That is not a benchmark to correct for: it is every top-level script and
every line typed at the prompt.

**A function in the wrong file.** The per-send receiver check asks three
predictable questions, and it lived in `object.c` while its only caller lived in
`vm.c` — so every send in every program paid a call across a translation unit
for three branches. Profiling [basic.sol](../programs/basic.sol) interpreting
39,000 BASIC statements put it at 12.6% of the run, against the name lookup's
13%. It had never been suspected of anything.
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)
carries the last two.

---

## What was refused

Two things were built and rejected on the measurements, which is worth more
here than the two that landed.

**An inline cache at the send site**, proposed confidently as closing most of
the recursion gap. Profiling says the proto-chain walk is 9.7% of that
benchmark. Two programs differing only in how far the method sits from the
receiver — its own first slot, against five objects up with four slots to skip
at each — are 18% apart, so the entire walk in a deliberately deep case is about
a sixth, and `fib` is not that case.
[Deferred, with the profile](ideas.md#an-inline-cache-at-the-send-site).

**Computed-goto dispatch**, the textbook optimisation for a bytecode
interpreter, which the roadmap had put at 10–20% on the strength of the
folklore. Built: it is **1% to 13% slower** than the `switch`, on all nine
benchmarks and on the real program. The disassembly says why — twenty-one
hand-written dispatch sites were tail-merged by the compiler back into a single
indirect branch, which is the shape a `switch` already compiles to, leaving 528
bytes of extra code around it for nothing.
[Refused, with the disassembly](ideas.md#computed-goto-dispatch--measured-and-refused).

**And two changes that each did no harm alone made deep recursion 8.5% slower
together**, on a program that uses neither. Nothing had been added to its path:
it was instruction cache, a bigger switch body and the hot cases falling
differently across it. Moving the slow paths out of the loop fixed the
regression and improved everything else at the same time. **A dispatch loop is a
cache-resident thing, and code that runs once per site does not belong in it.**

---

## The build flag is worth more than any of this

Everything above is an `-O2` build. The default `CFLAGS` in the Makefile is
`-std=c11 -Wall -Wextra -Wpedantic -g` — no optimiser at all — and that is what
`make` puts in `bin/`.

**The shipped debug build is 1.9× to 4.1× slower than the same source at
`-O2`,** and against CPython it loses every one of the nine.

Nothing is wrong with a debug default: `-g` with no optimiser is the right thing
to be developing against, and the sanitizers have
[a variable of their own](../Makefile). But the binaries in `bin/` are not the
ones these numbers describe, and **a timing quoted without its build is a timing
that means nothing.**

```sh
make CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -O2"
```

One further gain is measured and not taken: `-flto` is 5% to 29% faster across
the suite with no source change, and it drops the exported `sol_*` surface from
147 symbols to zero, which silently breaks every loadable
[extension](extensions.md). The test suite catches it. Keeping both means naming
those symbols deliberately, and that is
[the one candidate on the ideas page still unbuilt](ideas.md#where-the-interpreters-time-actually-goes--two-built-two-left).

---

## What one instruction costs, which nothing above says

Everything above is a **ratio** — against CPython, or against an earlier
Solveig. That is what the comparison was for, and it leaves one question
unanswered: what does the machine cost in absolute terms?

**4.4 nanoseconds per bytecode instruction, or 227 million a second.**

`programs/sha256sum.sol` is where that came from, on 2026-08-31. It is the first
program here with no I/O in its inner loop — sixty-four rounds of shifts, masks
and additions per sixty-four bytes and nothing else — so its running time is the
dispatch loop and nothing is hiding in a syscall or a `split`.

The instruction count is **measured rather than counted**, using a flag that was
not put there for this. `solvm --steps=N` stops a program after N instructions
and exits 124, so the smallest N that lets a run finish is that run's exact
count, and a binary search finds it:

| bytes hashed | instructions | blocks | per block |
| ---: | ---: | ---: | ---: |
| 0 | 14,671 | 1 | |
| 64 | 28,049 | 2 | 13,378 |
| 640 | 147,767 | 11 | 13,302 |
| 6,400 | 1,344,947 | 101 | 13,302 |

13,302 instructions per 64-byte block — flat from ten blocks to a hundred, which
is what says the figure is the loop and not the setup — and **207.8 instructions
per byte of message**. A megabyte takes 0.96 s at `-O2` on the M2 Pro, which is
the 227M a second above.

It is one program and one kind of work: integer arithmetic on block locals, no
allocation in the loop, no globals, no string building. A program that allocates
or sends into a deep proto chain will do worse per instruction, and the `fib`
row above is what that looks like. **It is a floor rather than an average**, and
this project had no such number before.

| | on a megabyte |
| --- | ---: |
| `/sbin/sha256sum` | 1667 MB/s — C, and the M2's SHA instructions |
| `shasum -a 256` | 317 MB/s — Perl, calling a C library |
| `sha256sum.sol`, `-O2` | 1.04 MB/s |
| `sha256sum.sol`, the `-g` build | 0.22 MB/s |

The Perl row is the one worth reading twice: an interpreter, 305 times faster,
because it is not interpreting the hash. **And the build flag costs 4.8x here**
against the 1.9x to 4.1x the nine benchmarks show, which is the largest gap
measured for it — a program that is nothing but arithmetic inside the dispatch
loop is the shape it matters most to.

---

## What is not fair here, said plainly

- **Integers are not the same thing.** A Solveig integer is sixty-four bits and
  traps on overflow; a Python integer is arbitrary precision. The `loop` and
  `array` rows partly measure that, and CPython is paying for a capability
  Solveig does not offer. A benchmark whose sums exceeded 2⁶³ would not run here
  at all.
- **Strings are not the same thing either.** Solveig strings are bytes; Python
  strings are Unicode with three internal widths. CPython's own single-byte
  string cache is the thing Solveig now has too, so on that row the two are
  finally doing the same work.
- **These are microbenchmarks.** Nine loops on one machine. They say what these
  nine loops cost. The one real program measured here gained 6.5% from changes
  that gave the synthetic loops up to 28%, which is the usual relationship and
  worth remembering when reading the table.
- **One machine.** Ratios on another architecture could differ, and nothing here
  was run anywhere else — which matters more than usual, given that one of the
  findings was an instruction-cache effect.
- **No warm-up, deliberately.** Both runtimes were launched fresh per run,
  because that is how both are actually used. Startup was then subtracted so it
  did not count twice.

---

## How it was measured, and how to re-run it

The programs are in [comparisons/python/](../comparisons/python/) — nine matched
pairs and the four probes — with a runner:

```sh
make CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -O2"   # the build being measured
comparisons/python/run.sh
```

`make test` compiles them and runs none of them: each is sized to take about a
second, so the nine belong to somebody who meant to run them rather than to a
suite that takes eight seconds. Compiling them is enough to catch the rot that
happens to code nothing builds.

The measuring is done by [bench.sol](../programs/bench.sol), which is what it was
written for. It
interleaves the two commands and flips a coin for which goes first each round,
so a machine drifting over a minute cannot be mistaken for a difference, and it
reports a bootstrap interval on the ratio rather than a test that assumes a
normal distribution. Given the same command twice it answers `1.001` and says
the runs cannot tell them apart — the check it has to pass before any other
answer it gives is worth reading.

```sh
./bin/solvm programs/bench.sob 21 ./solvm loop.sob -- python3 loop.py
```

```text
A:  ./solvm loop.sob                B:  python3 loop.py
  runs     21                        runs     21
  min       563.090 ms               min       784.914 ms
  median    572.593 ms               median    811.216 ms
  mean      595.385 ms  +/- 63.185   mean      816.629 ms  +/- 24.707

A / B    0.706 times, 95% interval 0.698 to 0.717
         A is faster
```

Every pair of programs prints the same answer, checked before anything was timed
and again after every change to the machine. **A benchmark whose two halves
compute different things measures nothing.**

The profiles are `sample` against a running process. The one that mattered was
of a real program rather than a loop written to be timed — which is how the
receiver check was found, having been invisible in every synthetic benchmark.

---

## The part worth keeping

Four things looked worth doing to the dispatch loop. **The two that paid were a
missing `inline` and a table lookup; the two that did not were the ones with
reputations.** Both of those were refused on measurements taken after building
them, not before.

That is the argument for measuring against something outside. A project measured
only against itself gets steadily better at the things it already thought were
important. It took another implementation to point at a one-byte string
allocated nine million times, and at a variable read that had been a hash lookup
since the beginning.
