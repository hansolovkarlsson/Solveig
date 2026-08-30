# Comparisons

Solveig measured against other implementations, with the programs that did the
measuring.

Everything else in this repository compares Solveig with an earlier Solveig,
which says whether a change helped and nothing at all about where the whole
thing stands. That was true for thirty-eight releases. The first comparison
outside found three defects in a week, none of which anything measured from the
inside had noticed — so these live in the tree rather than in a scratch
directory, and the numbers quoted in [docs/performance.md](../docs/performance.md)
can be re-run by whoever doubts them.

| | |
| --- | --- |
| [python](python/) | CPython 3.14 — nine matched programs, and four probes that isolate a cost |

## What a comparison directory holds

- **Matched pairs.** `name.sol` and `name.py` doing the same work and printing
  the same answer. The runner checks that they agree *before* it times them,
  because a benchmark whose two halves compute different things measures
  nothing.
- **`run.sh`**, which compiles, checks the answers, and hands each pair to
  [bench.sol](../programs/bench.sol) — the interleaved, coin-flipped,
  bootstrap-interval measurement this repository already uses for everything
  else.
- **`probes/`**, the programs that isolate one cost by removing it. These are
  not benchmarks and are not a suite; each exists because a profile raised a
  question and a pair of programs answered it.
- **A README** saying what each program is for and what it found.

## Adding another

A new directory beside `python/`, the same shape. Two things are worth keeping
whatever the target language is:

**The answers must be checked before the times are.** It is the cheapest
possible guard against measuring two different programs, and it has already
caught rewrites that changed a result while staying plausible.

**Say what is unfair.** Every comparison here is between languages that made
different promises — Solveig's integers are sixty-four bits and trap where
Python's are arbitrary precision, and that difference *is* some of the win on
the arithmetic benchmarks. A comparison that does not name what it is quietly
taking credit for is an advertisement.

`make test` compiles everything here and runs none of it. Each program is sized
to take about a second on purpose, so running the set belongs to somebody who
meant to rather than to the suite.
