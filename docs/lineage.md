# Lineage — what Solveig is like, and what it is not

*For anyone arriving with another language in their hands. What Solveig borrowed,
from whom, and where it leaves the family. If you want to learn the language
rather than place it, start with the [tutorial](TUTORIAL.md) instead.*

[design.md](design.md#object-model) sums it up in three words —

> **Smalltalk lineage, prototype flavour**

— and that is accurate enough to be worth unpacking rather than replacing.

## The two ancestors

**Smalltalk** gave it the central idea and most of the vocabulary. Everything is
an object. **Control flow is message sending**: `ifTrue`, `ifElse`, `whileTrue`
and `and`/`or` are ordinary messages that take blocks, exactly as Smalltalk's
`ifTrue:` and `whileTrue:` are — which is why
[lib/control.sol](../lib/control.sol) could add loops to the language without
touching the compiler. Indices are one-based for Smalltalk's reasons. Method
names read the same way: `asUppercase`, `lessOrEqual`, `copyFrom`. Temporaries
are declared between bars.

**Self** gave it the object model. Slots hold state and behaviour with no
distinction between them; a class is not a separate kind of thing; `object:new`
answers something that *delegates* to the receiver rather than copying it. An
object is a bag of named slots plus a parent pointer, and that is the whole
model — see [one-hierarchy.md](one-hierarchy.md) and
[class-and-instance.md](class-and-instance.md).

So: structurally it is nearer Self, and it sounds like Smalltalk.

## The closest living relative

**[Io](https://iolanguage.org/)**, which this project arrived at independently
and which is worth knowing about if you do not. Same design point almost
exactly: prototype-based, everything is a message send, delegation through a
parent, blocks as values, a small C virtual machine, a deliberately tiny
surface. Where Solveig writes `point:x`, Io writes `point x`.

If you have written Io, you will find Solveig immediately familiar and slightly
more restrictive.

## The closest in size and shape — to the machine

**Lua** — not in semantics but in engineering ambition. A small C VM, bytecode,
a mark-sweep collector, one obvious collection type, and a serious intent to be
[embedded](embedding.md) in a larger program. Lua's object story is metatables
rather than prototypes and its syntax is Pascal-flavoured, **so the resemblance
is to Solum and not to Solveig** — to the machine underneath rather than to the
language above it. That sentence used to have to be said the long way round;
naming the two layers separately is what made it a short one.

## Syntax, borrowed piece by piece

| | Solveig | nearest relative |
| --- | --- | --- |
| send a message | `x:print` | Io's `x print`, Smalltalk's `x print` |
| bind a name | `a := #45` | Smalltalk, Pascal, Go |
| end a statement | `.` | Smalltalk (as a separator), Prolog (as a terminator) |
| a block | `{ x \| x:add(#1) }` | **Ruby**'s `{ \|x\| ... }` very nearly; Smalltalk's `[ :x \| ... ]` |
| block temporaries | `{ \| t \| ... }` | Smalltalk's `\| a b c \|` |
| a symbol | `'foo` | Lisp's quote; Ruby's `:foo` |
| an array | `[#1, #2]` | everyone |
| a comment | `; to end of line` | Lisp, assembly |
| a directive | `@include "lib.sol".` | the C preprocessor, deliberately |
| an integer | **`#45`** | — |
| a float | **`45`** | — |

The last two rows are Solveig's own. Nearly every language makes the integer the
unmarked case; this one reverses it, on the grounds that a tagged integer is
worth the mark where a value's type is never inferred. `#` is Smalltalk's
literal marker, repurposed.

There are **no keyword messages**: `copyFrom(#2, #4)`, not `copyFrom:to:`. So
the surface is a Smalltalk dialect wearing C-family punctuation.

## If you already know…

**Smalltalk.** Nearly everything transfers. What is missing: `^`, cascades,
keyword syntax, metaclasses, and a class/instance split — a class here is an
object like any other, and the line between the two sides is drawn by the
receiver each slot requires rather than by splitting the objects
([2.5](COMPLETED.md#25-class-side-versus-instance-side--closed)). There is no
image and no live environment: you edit files and run a compiler.

**Self or Io.** The object model is yours. The surprise is that blocks are
restricted — see below — and that reflection can read but never write.

**Ruby.** Blocks look almost identical and behave similarly in the common case,
because Ruby blocks are usually downward-only in practice and Solveig's must be.
`:` where you expect `.`, `:=` where you expect `=`, and no `end`.

**JavaScript.** You have prototypes already, so delegation will read naturally.
The differences that will bite: there is **no implicit conversion anywhere**, so
`#1:add(1.0)` is an error rather than a number, and `#1:lessThan(1.0)` is an
error rather than an answer. `equals` is the exception and answers `false`,
because "are these the same value" is a question worth answering across types
where "which is larger" is not. And `nil` is one thing rather than two —
[absence.md](absence.md) is the page on that.

**C.** **Solum** will be legible — the VM, the bytecode, the
[embedding interface](embedding.md) and the
[extension interface](extensions.md) are all C and read as C. **Solveig** will
not feel like C at all: no statements that are not expressions, no control-flow
keywords, and no types written down. The two names are the two halves, and this
is the paragraph where the difference is easiest to feel.

## Where it leaves the family

These are the departures a Smalltalker notices first, and each is deliberate and
documented where a program would meet it.

- **A block that reads its enclosing frame cannot outlive it**
  ([3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame)). Smalltalk,
  Self and Io all have full closures. Solveig's are downward-only, and calling one
  after its frame returned is reported rather than reading somebody else's
  slots. This is the biggest single difference from the family.
- **No non-local return** — no `^`
  ([3.2](ROADMAP.md#32-no-non-local-return)). A block answers its last
  expression.
- **No metaclasses.** [class-and-instance.md](class-and-instance.md) argues that
  they answer a question this language does not ask.
- **Reflection reads and never writes.** `slots`, `slotAt`, `respondsTo` and
  `perform` are all there; there is no `slotAtPut`, no way to remove a slot, and
  no re-parenting.
- **An override names what it overrides**: `self:via(ancestor)` rather than
  `super`, so no frame has to record where a method was found.
- **Strings are bytes**
  ([2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only)) — the Lua
  position rather than the Smalltalk one. `"café":size` is 5.
- **Recursion reaches about 254 levels**
  ([3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels)), and running
  out is catchable like any other failure.

## What the relatives have that this does not

Placing the language invited the next question, and
[ideas.md](ideas.md) now carries the survey: what Smalltalk, Self, Io, Lua and
Ruby have that Solveig might want, each with a verdict.

The short version. **Deferred with a trigger**: an early exit from a loop,
intercepting a message that was not understood, a set type, and mathematics with
a source of randomness. **Turned down, each for a stated reason**: tail calls,
coroutines, multiple return values, resuming from an error, and more than one
parent.

Only one of them produced a roadmap entry, and it came from this repository's
own programs rather than from the other languages —
[3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing), because
loops here keep carrying a boolean whose only job is to stop them, in file after
file and mostly without comment.

## What is genuinely its own

Two things, as far as anyone here can tell.

**The literal convention** — `#45` for an integer and `45` for a float — which
follows from refusing every implicit numeric conversion. If the two never mix
silently, the one you meant is worth marking.

**The combination.** A Smalltalk-family object model with Self's prototypes, a
Lua-sized implementation, and no live environment is an uncommon place to stand.
Scripting languages usually go class-based or hash-of-functions, and the ones
that choose prototypes usually end up at JavaScript's shape rather than Self's.

---

*A caveat this page owes the reader.* Everything above about **Solveig** is
checked — the syntax against the [reference](REFERENCE.md), the restrictions
against the [roadmap](ROADMAP.md), and the strictness by running it, which
corrected one claim: `equals` across types answers `false` where `lessThan`
refuses. Everything about the **other** languages is recollection. The
comparisons to Io and Self especially would be better for a reading by somebody
who has used them.
