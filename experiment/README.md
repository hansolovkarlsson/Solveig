# Solum, compiled by Solum

*A finished experiment, parked. It asked whether the compiler could be written
in the language it compiles, and the answer is yes — including the part where it
compiles its own source and the result compiles its own source to the same
bytes.*

**Nothing here is on the search path, and nothing here is in `make test`.** That
is deliberate and is the reason it lives in this directory rather than in
`lib/` and `programs/`. Keeping a second compiler in step with `solas` is a tax
on every change to the real one, and the proof does not need repeating to stay
true — it was true on the day it was made, and the account below says exactly
what was true.

**So expect this to fall behind the language.** If `solas` grows a construct,
these will not know about it, and the first sign will be a file here failing to
compile. That is the trade being made on purpose, not a defect to report.

## What it is

| | |
| --- | --- |
| [lexer.sol](lexer.sol) | Solum's tokens, scanned by Solum — all nineteen kinds |
| [parser.sol](parser.sol) | the grammar: statements, sends, blocks, groups, `@include`, every literal |
| [compiler.sol](compiler.sol) | a tree in, a chunk out, including the control flow `solas` compiles to jumps |
| [compile.sol](compile.sol) | the command line on top of the three above and `sob.sol` |
| [emit.sol](emit.sol) | the first stage: a `.sob` written byte by byte with no compiler at all |

**The fourth piece went back to the library.** `sob.sol` — writing the `.sob`
file, floats taken apart by hand — is [lib/sob.sol](../lib/sob.sol) again,
because the reason the rest of this is parked does not apply to it. The tax is
that a second compiler has to be taught every construct the first one learns;
that falls on `lexer.sol`, `parser.sol` and `compiler.sol`, which track the
**language**. `sob.sol` tracks the **file format**, which changes on a version
bump and not on a new construct. The two files here still find it, on the search
path, without saying where it lives.

## What it proved, on 2026-08-23

**All 47 `.sol` files in the repository compiled to bytes identical to what
`solas` produces from the same source.** Not "runs the same" — the same file.
That is the bar the whole exercise was built on, because it forces agreement on
everything a compiler is otherwise free to decide: the order names are interned
in, which constants are shared, where a line's run of instructions ends, which
line a byte belongs to.

**And the fixpoint.** `solas` compiled `compile.sol` to a first generation; that
generation compiled its own source to a second, byte-identical to the first; the
second compiled its own source to a third, identical again; and the second still
agreed with `solas` on every other file.

## Running the proof again

`prove.sh` does both halves and says so. It needs a built `bin/` and takes about
a minute:

```sh
./experiment/prove.sh
```

It is a script rather than a test because it is a thing to run when somebody
wants to know, not on every build.

## What it found, which was the point

The exercise was run under one rule: **add nothing to the language to make it
easier.** A language that compiles itself with help added for the purpose proves
something smaller. What it wanted, it had to already have — and what it could
not have became an entry the ordinary way.

- **Writing binary works.** Every byte value including NUL survives
  `asCharacter`, `join` and `writeFile`. This was the one thing that could have
  ended the project on day one.
- **Writing an i64 is easier than reading one**, which is not the direction
  anybody would guess: `shiftRight` is arithmetic, so masking after it lands on
  the right byte for negatives as readily as positives, where reconstruction by
  shifting *left* overflows.
- **A float has to be taken apart by hand**, because nothing reinterprets a
  float's bits as an integer. `sob:f64` is `readFloat` in
  [disasm.sol](../programs/disasm.sol) inverted, and was checked against the C
  library at twelve values including `-0.0`, `DBL_MAX` and infinity, bit for bit.
- **The frame limit was the wall**, and it was the last thing standing between
  the compiler and its own source. Four files failed on `call depth exceeded`
  rather than on any construct. That is
  [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels), and
  moving the cap from 64 frames to 256 — which cost 4% more memory, once the
  stack stopped being sized from the frame count — is what finished the job.
- **A scanner needed no help.** `lexer.sol` is 297 lines against
  `solas/src/lexer.c`'s 265, and 169 of those are code. The question that
  started this was whether Solum needed a pattern class or a built-in tokenizer
  first. It did not.

## If it is ever brought back

The gap between this and `solas` is not the compiler, it is the front door.
The compiler is correct on every input this repository has; the diagnostics are
a prototype — an error is *raised*, so you get a VM stack trace through the
parser's own internals rather than `solas`'s underlined source line, and it
stops at the first mistake instead of synchronising and finding the rest. That
is where the work would start.

The full account, with what each stage found and cost, is in
[ideas.md](../docs/ideas.md#solas-written-in-solum--self-hosting).
