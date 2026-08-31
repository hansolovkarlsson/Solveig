# Ember

A small language, compiled to ARM64 assembly by a compiler written in Phoenix.

```
programs/ember/emberc.phx   --phoenix-->  emberc.sol
                            --solas---->  emberc.sob
examples/fizzbuzz.em        --solvm---->  fizzbuzz.s
                            --cc------->  a.out
```

**This is not a Phoenix feature.** It is a program written in Phoenix, and it
exists for the reason [docs/targets.md](../../docs/targets.md) gives:

> A code generator is exactly the kind of program that wants a declared
> notation — instruction patterns, addressing modes, a peephole table. If
> declaring a grammar per module does not help *there*, that is worth knowing
> early, and it is not a thing a small example can tell you.

Six versions of Phoenix were built with four toy examples and no customer.
`lib/text.sol` over in Solveig states the rule this is here to satisfy: **one
customer, satisfied in six lines, is not a reason to grow a surface** — and its
converse, that a surface with no customer at all has never been tested.

## What was predicted before it was written

Recorded here first, in the manner of Solveig's `docs/ideas.md`, so that *it
found nothing* stays an available answer.

| | |
| --- | --- |
| **1. A pattern's words can only be identifiers.** | `mov x0, x1` cannot be a form, because a pattern's literal parts are names and `,` is not one. Predicted to be the first thing that bites, and to be worked around with `mov <d> from <s>` or the call shape. |
| **2. The group parens will grate.** | `while t do (a. b)` — 0.5.0 predicted a pattern language would dissolve this and it did not. Predicted to appear on nearly every loop in the compiler and to be the most-noticed wart. |
| **3. A form cannot be recursive.** | A template may mention only forms declared above it. Predicted not to bite, because notation is not recursive even when the program using it is — but recorded because it is the rule most likely to surprise. |
| **4. The dialect will mostly be `concat`.** | Emitting assembly is building strings. Predicted that the useful forms are the ones that hide string joining, and that this says something about what a dialect is *for*. |
| **5. Solveig will bite before Phoenix does.** | Most likely [3.1](https://hansolovkarlsson.github.io/Solveig/docs/ROADMAP.html) — a block outliving the frame it was written in — if the codegen is built the combinator way. `lib/scan.sol` already hit it and says so. |

Predicted **not** to find: a problem with hygiene, with `@use`, or with the map.
Those have tests and the tests are about the right things.

## What it found

Ember compiles. `examples/fizzbuzz.em` and `examples/primes.em` go all the way
to ARM64 machine code and print the right answers, and `make test` diffs both
against `.expected`. Five programs and two languages to print a prime.

### The predictions

| | |
| --- | --- |
| **1. A pattern's words can only be identifiers** | **Right, within a minute.** `@syntax mov <d> , <s>` is the first thing anybody writing an assembler notation tries. The workaround — `load <d> imm <n>`, `store <s> slot <n>` — reads better than the thing it replaces, which was not expected. **Acted on:** the message used to be *needs `=>`*, pointing at the comma and saying nothing about why; it now names the rule and suggests the call shape. |
| **2. The group parens will grate** | **Right, and in a place not predicted.** They are on every multi-statement branch in the compiler, as expected — but they are also in `asm.phx`, because a *template* is one expression too. `load <d> adr <s>` emits two instructions and needs a group to do it. The wart is not the pattern language's; it is that a template is an expression. |
| **3. A form cannot be recursive** | **Did not bite.** Notation is not recursive even when the program using it is, which is what was predicted and is now checked rather than assumed. |
| **4. The dialect will mostly be `concat`** | **Right, and it sharpened.** Every form in `asm.phx` is one `fill`. The ones that earned their keep hide *the operand order as well as the joining* — `store "x0" slot n` against `emit("    str {}, [x29, #-{}]":fill([r, n:mul(#8)]))`, where the slot arithmetic is the part you would get wrong. |
| **5. Solveig will bite first** | **Wrong.** No 3.1, no block outliving its frame, nothing. A lexer, a recursive-descent parser and a code generator went in without Solveig complaining once, with `lib/scan.sol` doing the cursor work. The things that bit were Phoenix's and the author's. |

### Two things nobody predicted

**A pattern form whose last part is a hole cannot be closed.**

```
@syntax load <d> adr <s> => emit(A):add(emit(B)).
```

The `:add` went *inside* the hole — a hole takes an expression and a postfix
send continues one, so there is no way to write something after the form. That
is right for a form which reads as a statement, and it is invisible until it
bites. It bit on the first run of the first dialect written here.

**Sends bind tighter than operators, and it costs more than it looks.**

```
t:kind == 'op:and({ ... })        ; sends `and` to the symbol 'op
(t:kind == 'op):and({ ... })      ; what was meant
```

Six of these in one file, every one of them found *at run time* — they are type
errors, not syntax errors, so nothing catches them until a symbol is asked to
understand `and`. **This is the standing cost of putting operators on a language
whose core is sends**, it is not a defect in either, and it is the largest
friction this program found. A dialect that wanted to remove it would have to
declare `and` and `or` as operators too, which `lib/arith.phx` does not and
probably should.

### And one design question answered by use

**The call shape and the pattern shape divide by what the form *is*, not by
taste.** `binop(op, d, a, b)` has four operands of one kind with no words to put
between them, and reads as an application. `store <s> slot <n>` reads as a step
in a procedure. Written the other way round, both are worse. 0.5.0 shipped both
shapes without being able to say when each was right; this says.

### What Ember has and has not

Integers, string literals, `let`, `print`, `if`/`else`/`end`, `while`/`do`/`end`,
`+ - * / %`, the six comparisons, and parentheses. No functions, no arrays, no
input. Variables live in stack slots below the frame pointer and the expression
stack is the machine stack.

Ember has `end` on its blocks and Phoenix's own forms do not, which is the
contrast worth keeping: **an expression nests without a terminator, and a
hand-written recursive-descent parser wants one.** Two languages, two answers,
one of them written in the other.
