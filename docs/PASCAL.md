# Pascal on SolVM

*ISO 7185 Standard Pascal, compiled to a `.sob` file and run by `bin/solvm`.
Written before the compiler, and this page is the plan and the boundary rather
than the record — [CHANGELOG.md](CHANGELOG.md) says what has landed.*

**This is not a language definition, and that is the whole difference from
[SOLABASIC.md](SOLABASIC.md).** That document exists because there is no
standard for the dialect it describes and somebody had to hold the line. Pascal
has a standard: **ISO 7185:1990**, and Wirth and Jensen's *Pascal User Manual
and Report* before it. So the boundary is not this page's to draw. What this
page is for is the three things a standard cannot say:

1. **How Pascal's types land on SolVM's**, which have almost nothing in common.
2. **Where SolVM forces a divergence**, named one at a time so the list can be
   checked rather than believed.
3. **What is not built yet**, per stage, so that reaching for something gets an
   answer instead of a puzzle.

The compiler is `programs/pascal.sol`. Its grammar is already written and
already checked:
[pascal.bnf](../programs/check_syntax/pascal.bnf) has been run against
[check_syntax](../programs/check_syntax.sol) since before any of this, and both
files it ships with are **accepted by `fpc -Miso`** — which is the first thing
the oracle was asked and the first evidence that grammar is Pascal's rather than
this project's idea of it.

---

## Why compile rather than interpret

[ideas.md](ideas.md#programs-that-would-press-on-something) had this down as an
*interpreter*, and predicted its value would be meeting
[3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) head on: a
tree-walker spends host frames in proportion to the interpreted program's call
depth, so a Pascal recursing forty deep would exhaust the machine.

**Compiling takes that away**, and the entry now says so. A compiled Pascal call
is one `OP_SEND` and one frame, where a tree-walker spends three to six, so
recursion reaches something like 250 levels rather than 40. The prediction was
falsified by a decision rather than by a result, which is still a prediction that
paid: it is the reason the frame cost was looked at before the shape was chosen.

What compiling buys is the same thing it bought
[sola.sol](../programs/sola.sol): the file it writes is run by `solvm` with
nothing of the compiler present. **And `goto` is `OP_JUMP`** — a translator into
Solum *source* could not have one, there being no control-flow syntax in the
language to translate it into.

---

## The mapping

**Pascal is statically typed and SolVM is not, so every Pascal type is a
representation decision.** This is the part a standard has no opinion about and
the part the work actually is.

| Pascal | on SolVM | |
| --- | --- | --- |
| `integer` | an integer | 64-bit and traps on overflow; `maxint` is 2^63−1, which the standard leaves to the implementation |
| `real` | a float | 64-bit binary, the only float SolVM has |
| `char` | a one-character string | `ord`/`chr` are `asByte`/`asCharacter`; bytes, not code points |
| `boolean` | a boolean | `ord(false)` is 0 and `ord(true)` is 1, as the standard says |
| enumerated | an integer | the names resolve while compiling; `ord` is the value itself |
| subrange | its base type | the bounds are the compiler's business, and the checks are code it emits |
| `array` | an array | Pascal indexes from any ordinal; the offset is folded in while compiling, so `a[lo]` costs no more than `a[1]` |
| multi-dimensional | nested arrays | a row is a value, which is what `array [1..8] of vector` already means |
| `record` | an array, with field offsets fixed while compiling | a field is an index and not a name, so it costs an `at`, not a lookup |
| `set` | an array of integers, one bit per member | `set of char` is 256 bits; union, intersection and difference are `bitOr`, `bitAnd`, `bitXor` |
| pointer | a one-element array | `new` makes one, `nil` is `nil`, and see the divergence about `dispose` |
| `text` | a channel holding the whole file | what SolaBasic already does; there is no streaming underneath |
| `file of T` | the same, as an array of values | stage 6 |
| procedure, function | a block | called with `OP_SEND` |
| nested procedure | a block inside a block | `OP_OUTER depth slot` **is** a static link, and this is its first customer |
| `var` parameter | a box, and the variable is the box | sola.sol's answer, and Pascal is the easier case: `var` is *declared*, where QBasic made the compiler infer it |

**Two of those rows are the interesting ones.**

**`var` is easier here than in BASIC.** sola.sol has to work out which parameters
are by reference — a parameter is one when the procedure assigns to it, or hands
it to something that does, and that chains until it settles. Pascal writes `var`
on the parameter. The mechanism is the same box; the analysis is gone.

**Nested procedures may be free.** `OP_OUTER` takes a depth and a slot, which is
a static link by another name, and no compiler here has ever emitted one —
SolaBasic has no nested procedures. If Pascal's uplevel access needs nothing the
machine does not already have, that is the finding, and it is written down here
before it is known.

---

## Divergences

**Each of these is a place a conforming program gets a different answer, and the
oracle is what stops the list being prose.** A program in `programs/pas/oracle/differ/`
exercises each one and must *not* agree with `fpc -Miso`; one that starts
agreeing means the divergence has gone and this list is wrong.

| | |
| --- | --- |
| **`dispose` frees nothing** | SolVM is garbage-collected. `dispose(p)` is accepted and does nothing, and a program that uses a disposed pointer gets the object rather than the standard's *undefined*. It is the safe direction, and it is a difference. |
| **`real` is double** | The standard leaves precision to the implementation; SolVM has one float and it is 64-bit. |
| **`integer` overflow traps** | The standard calls overflow an error, which most compilers do not enforce. This one cannot help enforcing it. |
| **`char` is a byte** | 256 values, and text is bytes throughout the machine ([2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only)). |
| **A file is held, not streamed** | A file open for writing holds what has been written until it is closed. The same as SolaBasic, for the same reason. |
| **Lines end with a line feed** | And a trailing carriage return is taken off when reading. |

---

## What is not coming

| | |
| --- | --- |
| `goto` out of a procedure | The standard allows a jump to a label in an enclosing block. That is a non-local return, which is [3.2](ROADMAP.md#32-no-non-local-return), and the machine has no way to unwind to a named frame. A `goto` within one procedure is ordinary and is here. |
| variant records | The standard's own free union, and the one construct with no honest mapping onto a machine where a value knows what it is. |
| `packed` as a promise | Read and ignored. `packed` asks for a representation SolVM does not let a program choose. |

---

## Stages

**In this order, and the order is the argument.** Each stage ends with programs
in `programs/pas/oracle/agree/` that produce the same bytes under `fpc -Miso`
and under this compiler.

| | |
| --- | --- |
| **1** — **done** | `program`, `var` of the four simple types, assignment, expressions, `write` and `writeln` with field widths, `begin`/`end`, `if`, `while`. Five programs in `agree/` produce the same bytes as `fpc -Miso`. |
| **2** — **done** | `const`, `type`, enumerations, subranges, `case`, `repeat`, `for`, `goto` and labels, and `ord`, `chr`, `succ`, `pred`, `odd`, `abs`, `sqr`. Ten programs in `agree/`. |
| **3** — **done** | `procedure` and `function`, value and `var` parameters, recursion, `forward`. Thirteen programs in `agree/`. |
| **4** | Nested procedures and uplevel access — the `OP_OUTER` prediction, settled either way. |
| **5** | `array`, multi-dimensional, `record`, `with`. |
| **6** | `set`, and the file half: `text`, `read`, `readln`, `write`, `writeln`, `eof`, `eoln`, then `file of T`. |
| **7** | Pointers, `new`, `nil`, and linked structures. |
| **8** | The standard's required procedures and functions in full, and whatever the oracle has been complaining about. |

**Stage 3 landed the same day, and cost the compiler its single pass.** A `var`
parameter is a box and the variable *is* the box, which is `sola.sol`'s answer —
but knowing *which* of the caller's variables need boxing cannot be done in one
pass, because a variable read in one procedure may be handed to a `var`
parameter by another declared after it. So the source is parsed twice: the first
pass fills the set and its output is thrown away.

Two other things moved with it. A program's variables became **globals**, since
a procedure has to see them and a block cannot reach the script's slots without
`OP_OUTER` — which is stage 4's business. And they carry a `pas.` in front, so
that a Pascal program declaring `var system : integer` cannot reach in and
replace the machine's own.

**Stage 2 landed the same day.** A type became an object with two kinds: `run`
is what the machine holds — an integer, a float, a one-character string, a
boolean — and `kind` is what Pascal thinks it is. An enumeration is an integer
at run time and a `Colour` at compile time; a subrange of `char` is a character
at run time and a `1 .. 20` at compile time. Every check is on `kind` and every
instruction is chosen by `run`, and keeping those two words apart is most of
what the stage was.

Three things it added to the divergence list by finding them:

| | |
| --- | --- |
| an unmatched `case` falls through | ISO calls it an error. `fpc` lets it fall through and so does this, so that the two do not disagree by accident. |
| a subrange is not range-checked | `fpc` does not check without `-Cr`, and a checking compiler here would diverge from the oracle on every program that relies on it. Stage 8, with `-Cr` on the other side. |
| an enumeration cannot be written | Which is the standard's rule and not a gap: `write` takes an integer, a real, a char, a boolean or a string, and a `Colour` is none of them however it is held. `ord` does the showing. |

**Stage 1 landed on 2026-08-27**, and three things about it are worth carrying
forward. `mod` is one instruction and `div` is nine, which is the reverse of
SolaBasic: ISO's remainder is floored and the machine's already is, while ISO's
division truncates toward nought and the machine's floors. Pascal's `and` and
`or` are jumps rather than sends, the machine's own taking blocks. And a field
width is a compile-time string, so a `write` needs no runtime formatter and no
prelude — the other thing `sola.sol` needed and this does not.

**Stage 4 goes early on purpose**, the way SolaBasic put `GOTO` in week one: it
is the claim the whole design rests on. If `OP_OUTER` does not give Pascal's
scoping, the shape of everything after it changes, and that is worth finding out
before there is anything to change.

---

## The oracle

`programs/pas/oracle.sh`, on the pattern
[sola/oracle.sh](../programs/sola/oracle.sh) established.

```sh
brew install fpc          # 3.2.2, and -Miso is ISO 7185 mode
./programs/pas/oracle.sh
```

**It is the only check here that can find something nobody thought of.** The
evidence for that is on this repository's own record: SolaBasic took five
defects from comparing against a real QuickBASIC, seven more from writing real
programs in it, and **none at all from twelve transcripts it had recorded of
itself**. A transcript checks what its author thought to check.

Not in `make test`, because this repository has no dependencies beyond a C11
compiler and `make`, and keeps that by **saying what it needs rather than
fetching it**. `make test` holds the compiler to transcripts; the oracle is run
when somebody wants to know.
