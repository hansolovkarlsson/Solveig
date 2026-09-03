# A BASIC interpreter, written in Proto

**Predictions recorded before the program was written.** That is
[conventions.md](../../docs/conventions.md)'s rule, and this file is committed
before a line of `basic.pro` exists so that the ordering is in the history
rather than in a claim.

## Why this one

The sixth program, and the first that is not a pass over its input.

**Every program here so far runs once and stops.** `ember` turns source into
assembly, `grammar` turns text into a tree, `digest` turns bytes into a digest,
`ledger` turns transactions into a report, `prose` turns a document into text.
Each walks its input from one end to the other, and the order it walks in is the
order the input is written in.

An interpreter is not that. It has a **program counter that can go backwards**,
an environment that outlives every statement, and statements that run a number
of times the source does not say. [does-it-pay.md](../../docs/does-it-pay.md)
weighs five programs and closes on what is still unknown; a run-time state
machine is not on that list, because until now nothing here had one.

**And it is the first program with two domains in one file.** does-it-pay's one
general finding is that

> A domain of steps wants forms. A domain of values wants operators.

Five programs arrived at that independently and every one of them is on one side
of it — `ember`, `grammar` and `prose` declare no operators at all, `digest` and
`ledger` declare mostly operators. An interpreter has both at once: the dispatch
over statement kinds is a domain of steps, and BASIC's own values — a number or
a string, with `+` meaning two different things — are a domain of values. **The
rule has never been asked to hold twice inside one dialect.**

**It is also the half of [targets.md](../../docs/targets.md) that was never
written.** That page answered a question about a BASIC *compiler* in 2026-08-31
and answered it in the abstract, because no such program existed. The
interpreter is the cheaper half of the same question and settles the same
confusion with something that runs.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The dispatch cannot be notation, and this is `grammar`'s wall one level over.** | `programs/grammar` found that a template cannot declare a form, so a grammar's rules stop being notation and **become data**. An interpreter's core is *given a statement kind, run the right code*, and the prediction is that it stays a chain of `if kind == 'let then …` exactly as `ember`'s `genStmt` is, with no form removing a line of it. The reason, predicted in advance: **notation is chosen when the program is written and a dispatch is chosen when it runs.** If that is right it is the sharpest statement of the ceiling yet, because it names *why* rather than *where*. |
| **2. The value dialect will be declined, not worked around — and that is new.** | `digest` and `ledger` both declared an operator that was right for the domain and a trap beside it, and both **worked around it with a send and a comment**. BASIC's `+` is add-or-concat, which is exactly an operator's job; the interpreter's own `+` counts a program counter, a token index and an array index. Predicted: the traps outnumber the uses so heavily that `+` is **never declared at all**, and the domain boundary kills the dialect instead of being papered over inside it. **A third instance of a known finding, in a shape neither of the first two had.** |
| **3. So the dialect declares forms and no operators.** | Follows from 2, and puts this program on `ember`'s side of the split. Predicted count: seven or eight forms, no operators — which would make it the fourth of six programs to declare none, against a taxonomy that says a program with a value domain should want them. **The prediction is that the taxonomy is right about the domain and wrong about the program**, because a program can contain a domain without being one. |
| **4. `<=` and `>=` get their second customer, and it is the interpreter rather than BASIC.** | [ROADMAP.md](../../docs/ROADMAP.md) has `lib/arith.pro` missing `<=`, `>=` and `!=` with one customer — `programs/prose`, which writes `while i < doc:size + #1`. Predicted: this program wants them too, in bounds checks and in the `FOR` loop's limit test, and **not** for BASIC's own `<=`, which is a token the lexer reads and has nothing to do with any module's header. Two customers settles a live entry; that the second one wants it for a different reason than expected is the part worth recording. |
| **5. A REPL costs one block, and the reason is BASIC's and not Proto's.** | `system:readLine` and the same parse-one-line path give an interactive mode with no second parser, because a line-numbered BASIC **has no construct that spans lines** — `FOR` and `NEXT` are two statements, not a bracket. Predicted: the file driver and the prompt driver differ by their loop and nothing else, and **this is a property of the interpreted language rather than a thing Proto did**, which is precisely the sort of credit that lands on the wrong layer if nobody writes it down first. |
| **6. Proto helps with less of this than it looks.** | [rules-and-logic.md](../../docs/rules-and-logic.md) says exactly this about a Prolog dialect and it should be said here too. The hard parts of an interpreter are the environment, the return stack and the value model, and **not one of the three is notation.** Predicted: the dialect covers the leaves — reading a token, storing a variable, jumping — and the three hard parts are ordinary Proto with no notation over them, in the proportion `ledger` found, where three of its functions were formatting and none of the three was money. |

## How it is checked

`make test` runs `examples/*.bas` and diffs against `basic.expected`. The
expected output is worked out by hand from the BASIC source and not produced by
this program, which is the discipline `programs/digest` and `programs/ledger`
both use: **a program that verifies itself verifies nothing.**

## What it found

Written after the program, below the predictions rather than in place of them.
