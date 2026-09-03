# The conformance suite

*A corpus another implementation can score itself against, without borrowing
anything from this one.*

`tests/` holds this repository's own tests, in C, against its own symbols.
[`programs/expect.sol`](../programs/expect.sol) holds the examples and the
documents against their own comments. Neither is usable by a stranger: the first
needs our headers and the second matches a *subsequence* of our output, which is
right for a document and cannot score an implementation.

This is the third thing. Every case is written in the language, depends on
nothing outside what [REFERENCE.md](../docs/REFERENCE.md) and
[PRODUCING.md](../docs/PRODUCING.md) already say, and states its answer where a
program that has never seen this repository can read it.

## Running it

```sh
./conformance/run.sh                     # every case
./conformance/run.sh accepted/03-blocks  # one directory, or one case
./conformance/run.sh -v                  # name every case, not only the failures
```

`make test` runs it, first, before the C suite — a corpus a second
implementation is invited to score itself against has to be one this
implementation is scored against continuously, or the day a limit moves nobody
finds out. It needs no network and no clone and takes about a second, which is
why it is here rather than beside the [oracles](../programs/oracle.sh).

Two environment variables say what to run, each a template with `%s` where a
path goes:

```sh
SOL_COMPILE='./bin/solas %s -o %s'       # the source, then the object
SOL_RUN='./bin/solvm %s'                 # the object
```

Those defaults name this repository's binaries and are the only mention of them
in this directory. Nothing else here knows what it is scoring.

| you are writing | you set | what a failure means |
| --- | --- | --- |
| a second **front end** — `.sol` to `.sob` | `SOL_COMPILE` | your compiler produced a chunk that computes the wrong thing |
| a second **machine** — `.sob` to behaviour | `SOL_RUN` | your machine ran a correct chunk the wrong way |
| a **producer** from another language | both, and translate | your back end and the answers disagree |

The third row is the one that shaped this tree. A producer emitting bytecode
from a language of its own cannot read a `.sol` file at all, so the corpus
cannot be *input* to it — only the answers can, which it reaches by translating
each case by hand, the way a person uses the
[NBS Minimal BASIC suite](../programs/basic/conformance.sh). That is why a case
is a **program and its exact output** rather than a program with assertions in
it: an assertion is only readable by something that can run the program.

## A case is two files

`name.sol` is the program and `name.out` is its output, compared **byte for
byte** — not as a subsequence, not as a pattern. There is no tolerance and no
escape hatch: a float that prints differently is a conformance failure and
should read as one.

They are two files rather than one because a trailing space and a missing final
newline are both things an implementation gets wrong, and a comment inside the
program cannot carry either unambiguously.

Everything else lives in a header inside the program, so there is no manifest
beside the tree to go stale — the harness enumerates by extension and reads the
case:

```text
; conformance: what this case pins        required, one line
; varies: front | machine | both          required -- who can fail it
; status: 0                               optional; 0 if absent
```

A case with no header is a **failure**, not a skip. A corpus that quietly
declines to run a case is the thing this suite exists to avoid.

`varies` is not read by the harness. It is there so that a second front end can
be scored on the cases a front end can fail, once there is a second one; today
it is a claim about the case that a reader can check.

## What is here

`run.sh` says how many there are; it was 42 when this page was written, and the
number is not repeated anywhere that would have to be kept in step with it.

| | |
| --- | --- |
| `00-lexis` | literals and their tags, statement separation, comments, escapes, `#[` as one token, identifiers |
| `01-values` | value against reference equality, floored division, bits, IEEE floats, printing, strictness, absence |
| `02-sends` | left-to-right chaining, grouping, the `@expr` lowering, name lookup, reflection |
| `03-blocks` | parameters and temporaries, lexical capture, control flow as messages, escaping |
| `04-objects` | slots and delegation, methods, `via`, one hierarchy, `asString` and reflection |
| `05-errors` | what `onError` answers, `raise` and re-raise, `ensure`, `system:exit` |
| `06-limits` | 255 elements, 127 pairs, 255 arguments, 255 slots — each at exactly N — and recursion |
| `07-library` | `split` and `replace`, the format spec, the four iteration messages, slicing, dictionaries, symbols, `sorted` |

Every expected output here was **written from the documentation before it was
run**, which is the only way a corpus like this can find anything: recording
what an implementation prints produces a file that agrees with it by
construction. Two disagreed on the first run and both were the author's
arithmetic rather than the implementation's answer.

## What this suite does not cover

**Refusals.** Every case here is a program that runs. The programs that must be
*rejected* — `self` outside a block, a duplicate temporary, a chained
comparison, a literal one past its limit — are a second corpus, and
[PRODUCING.md](../docs/PRODUCING.md) already tabulates the rules it would be
built from. The limit cases here sit at exactly N for that reason: N+1 belongs
on the other side.

**The wording of a failure.** An error's text is a thing an implementation
chooses, and a suite that demanded ours would be scoring the words. `05-errors`
pins that a failure *arrives*, as an object delegating to `error`, carrying a
message — and compares text only where the text is the **program's own**, as in
`error:raise("bad input on line 3")`.

**Anything an address reaches.** An object without an `asString` shows its
address, so no case prints a bare object.

**Anything unordered.** A dictionary's `keys` come back in no order worth
relying on, and the reference says so, so every case that prints them sorts them
first.

**The three 65,535 limits** — names, constants and blocks in one chunk — because
a case at N would be a file of that many lines. They are in PRODUCING.md's table
and are a generator's business rather than a corpus's.

**The 256-frame ceiling.** How deep a given program can recurse depends on what
each construct costs in frames, which is a fact about an implementation's
accounting rather than about the language. `06-limits/recursion.sol` runs well
inside it deliberately.

**The order arguments are evaluated in.** Nothing in the documentation says, so
there is nothing to score. It is a real question a second implementation will
have to answer, and it wants a sentence in the reference before it wants a case
here.

## It is not a specification

It is a set of answers. Every case it does not contain is unspecified *by it*,
and a gap here is not a licence — [REFERENCE.md](../docs/REFERENCE.md) is what
the language is, and this is a sample of it that can be run.

It promises no more stability than a `.sob` does, which is none:
[the format has no compatibility window](../docs/PRODUCING.md#the-version-and-what-it-promises-you)
and this does not invent one. Cases will be added, corrected, and occasionally
removed when they turn out to have pinned an accident. What will not happen is a
case quietly changing its answer without the change being an entry in
[CHANGELOG.md](../docs/CHANGELOG.md).
