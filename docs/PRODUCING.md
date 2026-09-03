# Writing a producer

*What a program that generates Solveig — source or bytecode — has to get right
beyond the grammar.*

[GRAMMAR.md](GRAMMAR.md) and
[programs/check_syntax/solum.bnf](../programs/check_syntax/solum.bnf) say what
is *syntax*. [BYTECODE.md](BYTECODE.md) says what the instructions are and
[serialize.h](../solum/include/solum/serialize.h) says what a `.sob` holds. This
page is the third thing: the rules `solas` enforces that neither can carry, and
the limits a chunk has.

It exists because somebody outside this repository started emitting `.sob` and
had nowhere to look.
[ROADMAP 6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done)
is the entry.

**Every rule below was triggered before it was written down**, and the message
quoted is the message `solas` gives. That is not a flourish: writing this page
found two defects, one of which was `solas` emitting bytecode its own verifier
refuses.

## What a grammar cannot carry

`solum.bnf` says of itself that **there are no reserved words**, and that is
true — `nil`, `true`, `object` and `self` are ordinary identifiers that happen
to be bound. A front end built from the grammar alone will therefore accept
programs `solas` rejects, and these are they.

### Scope

| what | `solas` says |
| --- | --- |
| `self` outside a block | `'self' is only meaningful inside a block` |
| `self := ...` anywhere | `cannot assign to 'self'` |

`self` is the receiver, held in slot 0 of a frame. At the top level of a script
there is no receiver, and it is never assignable.

### Names in a frame

| what | `solas` says |
| --- | --- |
| a temporary declared twice | `that name is already declared here` |
| a temporary with a parameter's name | `that name is already declared here` |
| a parameter declared twice | `that name is already a parameter here` |

A frame's names are one namespace: parameters and temporaries share it, and
slot 0 is the receiver.

### Inside `@expr`

The infix region is a second grammar, and three rules live in the compiler
rather than in it:

| what | `solas` says |
| --- | --- |
| `@expr( a < b < c )` | `comparisons do not chain; the left of this one is a boolean` |
| `@expr( * a )` | `an operator needs something to its left; inside '@expr(...)' only '-' and '~' may open one` |
| `a + b` outside a region | `this is written as a send here; '@expr(...)' is where the operators are` |

### Directives

| what | `solas` says |
| --- | --- |
| `x := @include "f".` | `a directive must stand alone as a statement` |
| `@nosuch "f".` | `unknown directive` |
| a file that includes itself | `this file includes itself, so the include does nothing` |

## The limits a chunk has

**These are the ones a bytecode producer must respect**, because the format
writes them in a fixed width and the verifier refuses a chunk that overruns.
Each was found by generating programs until `solas` refused.

| | limit | what happens at one more |
| --- | --- | --- |
| slots in one frame — parameters, temporaries and the receiver together | **255** | `too many parameters`, or `too many names declared in one frame` |
| elements in one array literal | **255** | `too many elements in one array literal` |
| pairs in one dictionary literal | **127** | `too many pairs in one dictionary literal` |
| arguments in one send | **255** | `too many arguments` |
| names in one chunk | 65,535 | `too many names in one chunk` |
| constants in one chunk | 65,535 | `too many constants in one chunk` |
| blocks in one chunk | 65,535 | `too many blocks in one chunk` |
| bytes a conditional jumps over | 65,535 | `conditional is too large to jump over` |
| bytes a loop jumps back over | 65,535 | `loop body is too large to jump back over` |
| call frames, at **run** time | 256 | `call depth exceeded` |

**The dictionary limit is 127 and not 254, which the message does not say.**
A literal lowers to `dictionary:of(k, v, k, v, ...)`, so 127 pairs is 254
arguments and the ceiling is the argument list's. An array literal of 255 is
therefore twice the dictionary's, and neither number is arbitrary — they are the
same limit counted differently.

**The frame limit is 255 and not 256**, and it was 256 until 2026-09-01. A
frame's `slot_count` goes out as a `u8`, so 256 slots compiled cleanly and then
failed to serialise: `solas` emitting bytecode its own verifier refuses, and
reporting it as *bytecode is internally inconsistent* rather than *too many
parameters*. Corrected, and it is the sharpest illustration of why 6.42's second
half matters — that one sentence stands for thirty-five distinct faults.

## What the verifier checks

Every `.sob` is verified before anything in it runs, and a chunk that fails is
**reported rather than executed**. That is the safety net a producer is working
against, and it is a good one: a bad jump target or an unbalanced stack arrives
as a message and an exit status, not a crash.

**It says which way**, since 2026-09-01. `bytecode is internally inconsistent`
stood for thirty-two conditions and now carries a sentence apiece:

```text
solvm: cannot load 'x.sob': bytecode is internally inconsistent
       -- a jump lands in the middle of an instruction
```

A single-byte fuzz over one small `.sob` produces twelve distinct diagnoses
where it used to produce one. The ones a generator meets most:

| | |
| --- | --- |
| `a jump lands outside the code` | the offset is past the end |
| `a jump lands in the middle of an instruction` | the offset is not a boundary |
| `an instruction takes more from the stack than is on it` | the depth does not reach |
| `two paths reach one instruction with different stack depths` | a branch whose arms do not balance |
| `a slot index names a slot the frame has not got` | `slot_count` is too small, or the index too large |
| `a method has fewer slots than it has arguments and a receiver` | `slot_count < arity + 1` |
| `a name index names a name the chunk has not got` | a send, global or `SET_SLOT` operand |
| `a constant index names a constant the chunk has not got` | an `OP_CONST` operand |
| `the code does not end in HALT or RETURN` | the dispatch loop would run off the buffer |
| `the line runs do not cover the code exactly` | the debug side tables disagree with the code length |

**Thirteen of these are pinned by tests** — seventeen cases in
[test_serialize.c](../tests/test_serialize.c), each constructing a chunk with
one fault and asserting the sentence rather than the code. So a diagnosis
changing, or two of them merging back into one, fails the build. The ones a
back end writes rather than a corrupted byte produces are grouped together
under *the faults a generator writes*: a jump off the end, a jump into the
middle of an instruction, a block index naming nothing, `OP_BLOCK` naming a
method that is not a block.

There is deliberately **no directory of malformed `.sob` files**. Producing one
means patching bytes of a valid file, since `sol_chunk_save` refuses to write a
chunk that will not verify — and a producer does not need our broken files, it
needs its own diagnosed. What the corpus is for is keeping these sentences
still, and it does that where the chunks can be built directly.

The codes themselves are unchanged — `SOL_SER_MALFORMED` still means what it
meant — so nothing that reads them had to move.
[`sol_chunk_load_why`](../solum/include/solum/serialize.h) is the form that
answers with the sentence, and `sol_chunk_load` is a wrapper passing NULL.

[disasm.sol](../programs/disasm.sol) is still the way to see the chunk itself:
it decodes the format independently of the machine that runs it, and was written
to check one implementation against another.

## The version, and what it promises you

`.sob` opens with `SOLB` and the version as a little-endian `u16`:

```text
53 4f 4c 42   0e 00   01 00   ...
S  O  L  B    14      slot_count
```

**A build reads exactly its own version and refuses every other, in both
directions.** Format 15 will refuse 14 and everything before it; 14 refuses 15.
The check is an equality rather than a floor, so a newer file is as unreadable
as an older one, and the diagnosis is `unsupported bytecode version` with
nothing else examined.

**So the contract is: pin nothing, read the header.** Take `SOL_SOB_VERSION`
from [serialize.h](../solum/include/solum/serialize.h) when you build, rather
than writing `14` into your own source — the number is the only thing that has
to move when the format does, and reading it from the header is what makes a
rebuild sufficient.

There is no compatibility window and none is planned. A version rises when the
format changes at all, every file made before it becomes unreadable, and
everything is recompiled from source. It is a small price here because a `.sob`
is a build artefact rather than a distribution format — nothing ships one — and
it buys a verifier whose guarantees are about a single layout, with no reader
carrying a branch for a shape that no longer exists.

**What that means in practice**: a producer's `.sob` files stop working when
this repository bumps the version, and the fix is always to rebuild rather than
to migrate. [BYTECODE.md](BYTECODE.md) records every version's contents, and the
changelog names the release that moved it.

## Checking yourself against the answers

Everything above says what to *emit*. It says nothing about whether what you
emitted computes the right thing, and the verifier accepting a chunk is not that
claim — it is the claim that the chunk is well formed.

[conformance/](../conformance/README.md) is the other half: a corpus of programs
with their exact output, run by a harness that takes the tools from the
environment.

```sh
./conformance/run.sh                          # against the binaries here
SOL_COMPILE='mycc %s -o %s' ./conformance/run.sh   # against your front end
SOL_RUN='mymachine %s' ./conformance/run.sh        # against your machine
```

**A producer emitting bytecode from another language sets both and translates.**
The corpus cannot be input to you — you do not read `.sol` — so what you use is
the `.out` file beside each case, which is the answer. That is how the
[NBS Minimal BASIC suite](../programs/basic/conformance.sh) is used here too,
and it is why a case is a program and its output rather than a program with
assertions in it.

Two things it deliberately does not check. **No case is a program that must be
refused**, so nothing above this line is scored by it — the limits appear only
at N, never at N+1. And **no case compares the wording of a failure**, since
that is a thing an implementation chooses; where an error's text is compared it
is because the *program* supplied it.

## Two things that are easy to get wrong

**`#[` is one token.** The `[` must follow the `#` immediately, the way a digit
must. A scanner that reads `#` and `[` separately will not produce a dictionary
literal.

**A dictionary key is a `sum`, not an expression.** Otherwise it swallows the
`=` that ends the pair, since `=` lives in `comparison`. Nothing is lost: a
comparison is only legal inside an `@expr` region, and a region is a `primary`.
