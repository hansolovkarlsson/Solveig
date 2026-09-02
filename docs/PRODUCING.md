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
[ROADMAP 6.42](ROADMAP.md#642-a-second-producer-of-sob-has-no-contract-to-build-against)
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

It is also, today, a **single sentence for thirty-five conditions** —
`bytecode is internally inconsistent` — covering a jump past the end of the
code, a stack height that does not balance, `slot_count < arity + 1`, a name or
constant index out of range, a line run overrunning the code, and a chunk not
ending in `HALT` or `RETURN`. Splitting that is the open half of
[6.42](ROADMAP.md#642-a-second-producer-of-sob-has-no-contract-to-build-against).

Until it is split, [disasm.sol](../programs/disasm.sol) is the way to find out
which one it was: it decodes the format independently of the machine that runs
it, and it was written to check one implementation against another.

## Two things that are easy to get wrong

**`#[` is one token.** The `[` must follow the `#` immediately, the way a digit
must. A scanner that reads `#` and `[` separately will not produce a dictionary
literal.

**A dictionary key is a `sum`, not an expression.** Otherwise it swallows the
`=` that ends the pair, since `=` lives in `comparison`. Nothing is lost: a
comparison is only legal inside an `@expr` region, and a region is a `primary`.
