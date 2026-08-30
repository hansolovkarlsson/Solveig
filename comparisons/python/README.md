# Solveig against CPython

Nine matched programs, and the four probes that explained the results.
[docs/performance.md](../../docs/performance.md) is the account of what they
found; this page is what each program is and how to run them.

## Running them

```sh
comparisons/python/run.sh                 # all nine
comparisons/python/run.sh loop float      # only these
RUNS=31 comparisons/python/run.sh         # more rounds per pair
SOLVM=/path/to/solvm comparisons/python/run.sh
```

**Build the machine you meant to measure first.** `make` produces a `-g` build
with no optimiser, which is 1.9× to 4.1× slower than the same source at `-O2`
and loses every one of these nine. The published figures are `-O2`:

```sh
make CFLAGS="-std=c11 -Wall -Wextra -Wpedantic -O2"
```

The runner compiles each `.sol`, checks that the two halves of the pair print
the same answer, and only then hands them to
[bench.sol](../../programs/bench.sol), which interleaves the two commands, flips
a coin for which goes first each round, and reports a bootstrap interval on the
ratio. It measures with whichever `solvm` is in `bin/` rather than with the one
under test, so the subject is not also the instrument.

## The nine

Each is sized to take about a second, so that startup — 3 ms against 21 ms — is
a small enough part of the total to be subtracted honestly rather than to
dominate.

| | What it exercises |
| --- | --- |
| `loop` | sum 1 to 10,000,000 in a while loop — integer arithmetic and loop overhead |
| `fib` | `fib(34)` by recursive message send — 18M calls, dispatch and frame cost |
| `array` | grow a 5,000,000-element array, then fold it — allocation and growth |
| `dict` | 1,500,000 string-keyed inserts, then as many lookups |
| `strlib` | join 2,000,000 strings and split them back — work that lives in the primitives |
| `strloop` | scan 9,043,899 characters one `at` at a time — work that stays in the language |
| `float` | 8,000,000 × square root, divide, add |
| `object` | make 4,000,000 objects, fill two slots, send one message — allocation and GC |
| `higher` | `collect`, `select`, `inject` over 4,000,000 — a block called per element |
| `hello` | not in the suite; run by hand to measure startup |

## The probes

Not benchmarks. Each is a pair of programs differing in **one** thing, written
because a profile raised a question that a ratio could not answer.

| | The question, and the answer |
| --- | --- |
| `loop-local.sol` | `loop` with its counter as a block temporary instead of a global. **1.255× faster** — which is what a global variable costs when reading one is a hash lookup. It is why chunks remember where a global lives ([4.5](../../docs/COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)). |
| `probe-noat.sol` | `strloop` with the `s:at(i)` taken out, so the loop alone can be timed. Separated the cost of reading a character from the cost of looping over one ([4.4](../../docs/COMPLETED.md#44-a-one-byte-string-is-allocated-per-character-read--done)). |
| `depth1.sol` / `depth5.sol` | The same recursion with the method in the receiver's own first slot, and five objects up a chain with four slots to skip at each. **18% apart**, which is how the [inline cache](../../docs/ideas.md#an-inline-cache-at-the-send-site) was shown to be worth a tenth of what had been claimed for it. |

Run one against another the way the results were got:

```sh
./bin/solas comparisons/python/probes/depth1.sol
./bin/solas comparisons/python/probes/depth5.sol
./bin/solvm programs/bench.sob 15 \
    ./bin/solvm comparisons/python/probes/depth1.sob -- \
    ./bin/solvm comparisons/python/probes/depth5.sob
```

## What is being compared

CPython 3.14.7, from Homebrew, no JIT, GIL enabled — a standard build, not a
handicapped one. It is one of the faster CPython releases: an adaptive
specialising interpreter, computed-goto dispatch, and inlined Python-to-Python
calls.

The pairs are written to be idiomatic in each language rather than identical in
shape — `while` loops in both, but `list.append` against `array:add` and
`map`/`filter`/`reduce` against `collect`/`select`/`inject`. A transliteration
would measure how awkwardly one language can imitate the other.

**And they are not doing quite the same work**, which
[docs/performance.md](../../docs/performance.md) says at greater length: a
Solveig integer is sixty-four bits and traps on overflow where Python's is
arbitrary precision, and Solveig strings are bytes where Python's are Unicode.
Some of the arithmetic win is that difference rather than better arithmetic.
