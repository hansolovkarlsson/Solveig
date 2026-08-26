# SolaBasic — a compiled BASIC for SolVM

*The language definition. Written before the compiler, and frozen when it
starts, because there is no standard for this dialect and somebody has to hold
the line that a standard would have held.*

SolaBasic is BASIC in the shape QuickBASIC gave it — labels rather than line
numbers, `SUB` and `FUNCTION`, block `IF` and `SELECT CASE` — compiled to a
`.sob` file and run by `bin/solvm`. It is **not** QBasic and does not try to be.
It is a subset, and this document is the whole of it.

## The name

*Sola* is Norwegian for the sun — the definite form of *sol*, which is how it
comes to stand beside Solveig. In Latin *sōla* is the feminine of *sōlus*, the
same root as the *sōlum* the README takes the whole design principle from.
*Basic* is on the end because the dialect is BASIC, and because it belongs to
this project rather than to Microsoft.

**The obvious name was taken, and taken from close by.** S-BASIC — *Structured
Basic*, Topaz Programming, 1981, distributed with Kaypro's CP/M machines — had
optional line numbers, labels that were not numbers, and a two-pass compiler. It
is CB80's contemporary and competitor, which is to say it sits inside the same
paragraph this language borrows its boundary from. SmallBASIC is in use as well.
So the short name is spoken for twice over, and this is the longer one.

## Why this document exists at all

[basic.sol](../programs/basic.sol) could point at ECMA-55 and let a published
standard decide when it was finished. **SolaBasic has no such standard, and the
reason is worth writing down, because it is not for want of looking.**

There is exactly one standardised structured BASIC: **Full BASIC**, ratified as
ECMA-116 (1986), ANSI X3.113-1987 and ISO/IEC 10279:1991. It has `SUB`,
`FUNCTION`, `SELECT CASE`, `DO...LOOP`, `EXIT`, and structured exception
handling, and ECMA publishes it for nothing exactly as it publishes ECMA-55.
Three things rule it out:

| | |
| --- | --- |
| **Line numbers are still mandatory** | Full BASIC adds structure without removing the line editor it was designed around. It fails the first requirement. |
| **176 keywords, 161 concepts** | plus 38 mathematical and 14 string functions, plus five optional modules, one of them a graphics system. Against Minimal BASIC's twenty statements, that is a different category of job rather than a larger one. |
| **Nobody appears to have built a conforming implementation** | and there is no Full BASIC counterpart to the NBS test programs. A standard nobody met and nobody tests is not an external authority; it is a long document. |

So the choice was a vendor dialect, and the trouble with a vendor dialect is
that the subset boundary is drawn by whoever is writing the compiler, on the day
they are writing it, which is the failure ECMA-55 protected the interpreter
from.

**The line is therefore borrowed rather than invented.** It is CB80's.

## Where the line is drawn

**CB80** — the CBASIC Compiler, Digital Research, 1982 — is the closest thing
this project has to an ancestor. CBASIC compiled to an intermediate `.INT` file
executed by a separate runtime called CRUN, which is this design in 1977. CB80
added alphanumeric labels to it, along with nested `IF`, variable type
declarations, `CALL` with parameters, and multiple-line functions with local
variables.

That list is a boundary drawn by people building a compiled, structured,
label-based BASIC **with no machine underneath it** — no screen, no memory map,
no interrupt table. It is the boundary SolaBasic uses:

> **Everything QBasic has that CB80 also had is language. Everything QBasic adds
> beyond it is either the PC or convenience, and neither is here.**

Where SolaBasic departs from that rule it says so, in
[Where this is not QBasic](#where-this-is-not-qbasic) and
[What is not here](#what-is-not-here).

## Why compile it at all

Because **`GOTO` is not expressible in Solum**.

Solum has no control-flow syntax; a loop is a message send. A transpiler would
have to compile every statement into a block, keep them in an array, and
dispatch on a label variable — a full send per BASIC statement, which is what
[basic.sol](../programs/basic.sol) already pays as a tree-walker. It would be a
slower interpreter wearing a compiler's name.

Emitting bytecode, `GOTO` is `OP_JUMP` and `OP_LOOP`. This is the rare case
where dropping a level buys a construct rather than a constant factor, and it is
the reason this program exists.

**The verifier cooperates.** Its rule is the JVM's — the paths into a point must
agree on stack height ([design.md](design.md), `verify_stack_heights`).
SolaBasic statements compile at depth 0 with a `POP` at each boundary, so every
label is a depth-0 merge point by construction and an arbitrary jump between
statements verifies without any analysis at all.

---

## Program structure

A SolaBasic program is a sequence of lines. A line holds one statement, or
several separated by `:`, or nothing.

**There are no line numbers.** A line may carry a label:

```basic
Again:  PRINT "round and round"
        GOTO Again
```

A label is an identifier followed by `:`, at the start of a line. **A number is
also a label**, and this is CB80's rule taken verbatim: the compiler treats a
label as a string of characters rather than a numeric quantity, so labels need
not be ordered, need not be present, need not be unique in any numeric sense,
and mean nothing except as the target of a jump. `100` and `100.0` are two
different labels. Old listings therefore pass through unaltered, and nothing in
the compiler ever sorts them.

A program is one file. There is no `CHAIN`, no `COMMON`, and no linker.

### Module level and procedure level

Statements outside any `SUB` or `FUNCTION` are **module level** and run in
order, top to bottom, from the first such statement. `SUB` and `FUNCTION`
definitions are not executed where they stand.

`GOTO` may not cross between module level and a procedure, or between two
procedures. Each is a separate chunk and a jump is an offset within one.

---

## Lexical structure

| | |
| --- | --- |
| **Case** | Keywords and identifiers are case-insensitive. `PRINT`, `Print` and `print` are one word; `Total` and `TOTAL` are one variable. |
| **Identifiers** | A letter, then letters, digits and `.`, up to 40 characters, optionally ending in a type suffix. |
| **Comments** | `REM` to end of line, or `'` to end of line. `'` may follow a statement; `REM` may follow one after a `:`. |
| **Continuation** | None. A statement ends at the end of its line. |
| **Whitespace** | Required between a keyword and what follows it. See [Where this is not QBasic](#where-this-is-not-qbasic). |
| **Statement separator** | `:` joins statements on one line. |

### Literals

| | |
| --- | --- |
| Integer | `42`, `-7`, `&HFF` (hex), `&O17` (octal) |
| Double | `3.14`, `1.5E-3`, `2D6` |
| String | `"between double quotes"`. There is no escape; a string may not contain `"`. Use `CHR$(34)`. |

---

## Types

**Three, and no more.**

| Type | Suffix | `AS` name | Backed by |
| --- | --- | --- | --- |
| Integer | `%` | `INTEGER`, `LONG` | SolVM's tagged 64-bit integer |
| Double | `#` | `DOUBLE` | SolVM's `f64` |
| String | `$` | `STRING` | `SolString`, dynamic length |

`LONG` and `&` are accepted as synonyms for `INTEGER`. **`SINGLE` is not in the
language** and `!` is not a suffix — see the divergences.

A name's type is fixed by, in order: its suffix; an `AS` clause on its `DIM`;
the `DEF`*type* range covering its first letter; otherwise **`DOUBLE`**.

```basic
DEFINT A-N
DIM Count AS INTEGER
Total# = 0
Name$ = "Solveig"
```

### Conversion and arithmetic

- `/` always answers a Double, whatever its operands. `\` is integer division
  and `MOD` is integer remainder; both convert their operands to Integer first.
- Assigning a Double to an Integer rounds to nearest, halves away from zero.
- An Integer operation that leaves the 64-bit range is an error, not a
  wraparound. SolVM traps, and SolaBasic reports it as `overflow`.
- `+` on two Strings concatenates. Any other mixing of String and number is a
  compile error — SolaBasic never converts between them silently. `VAL` and
  `STR$` are how you cross.

---

## Declarations and scope

| | |
| --- | --- |
| `DIM name AS type` | declares a scalar |
| `DIM name(bounds) AS type` | declares an array |
| `DIM SHARED ...` | at module level, makes the name visible inside every procedure |
| `CONST name = expression` | a named constant, folded at compile time |
| `SHARED name` | inside a procedure, names a module-level variable to use |
| `STATIC name` | inside a procedure, a local that survives between calls |
| `DEFINT`/`DEFLNG`/`DEFDBL`/`DEFSTR` *letter*`-`*letter* | sets the default type for a range of initial letters |
| `OPTION BASE 0` \| `1` | the default lower bound for arrays. Once, before any `DIM`. |

A variable not declared anywhere springs into being on first use, with the type
its suffix or the `DEF`*type* ranges give it, and the value `0` or `""`.

**A procedure's variables are local to it** unless named by `SHARED`. Module
level and procedure level do not otherwise see each other.

### Arrays

```basic
DIM Grid(1 TO 8, 1 TO 8) AS INTEGER
DIM Names$(100)
```

Bounds are constant expressions. `DIM a(10)` runs from `OPTION BASE` to 10
inclusive. Up to eight dimensions. Arrays are not resizable; there is no
`REDIM`.

---

## Expressions

Highest binding first. Every level is left-associative except `^`, which is
right-associative.

| | |
| --- | --- |
| `^` | exponentiation, always Double |
| `-` | unary minus |
| `*` `/` | multiply, divide |
| `\` | integer division |
| `MOD` | integer remainder |
| `+` `-` | add and subtract; `+` also concatenates Strings |
| `=` `<>` `<` `>` `<=` `>=` | comparison, answering `-1` for true and `0` for false |
| `NOT` | bitwise complement |
| `AND` | bitwise and |
| `OR` `XOR` | bitwise or, exclusive or |

There is no boolean type. A condition is true when it is non-zero, which is why
the comparisons answer `-1`: `NOT (a = b)` then works out.

`EQV` and `IMP` are not here.

---

## Statements

### Assignment

```basic
LET x = 1
x = 1
SWAP a, b
```

`LET` is optional and means nothing.

### Conditionals

```basic
IF x > 0 THEN PRINT "positive"
IF x > 0 THEN PRINT "positive" ELSE PRINT "not"

IF x > 0 THEN
    PRINT "positive"
ELSEIF x = 0 THEN
    PRINT "zero"
ELSE
    PRINT "negative"
END IF
```

```basic
SELECT CASE grade$
    CASE "A", "B"
        PRINT "pass"
    CASE IS >= "C"
        PRINT "marginal"
    CASE ELSE
        PRINT "fail"
END SELECT
```

`CASE` takes a list of values, ranges written `low TO high`, or `IS` followed by
a comparison operator.

### Loops

```basic
FOR i = 1 TO 10 STEP 2
    PRINT i
NEXT i

DO WHILE more
    ...
LOOP

DO
    ...
LOOP UNTIL done

WHILE more
    ...
WEND
```

`NEXT` may name its variable or not, and may close several at once
(`NEXT j, i`). `DO`/`LOOP` takes `WHILE` or `UNTIL` at either end, or neither,
in which case only `EXIT DO` leaves it.

`EXIT FOR` and `EXIT DO` leave the innermost enclosing loop of that kind.

### Jumps

```basic
GOTO Cleanup
```

Within one procedure, or within module level. That is the whole of it: there is
no `GOSUB`, no `ON n GOTO`, and no `RETURN`. See
[What is not here](#what-is-not-here).

### Procedures

```basic
SUB Greet (name$)
    PRINT "Hello, "; name$
END SUB

FUNCTION Area# (r#)
    Area# = 3.14159265358979 * r# ^ 2
END FUNCTION

CALL Greet("world")
Greet "world"
PRINT Area#(2)
```

A `FUNCTION` answers by assigning to its own name. `EXIT SUB` and
`EXIT FUNCTION` leave early.

**Parameters are passed by reference**, as in QBasic: assigning to a parameter
assigns to the caller's variable. Wrapping an argument in parentheses passes it
by value instead — `CALL Greet((name$))` — which is QBasic's own idiom for it.

An array is passed by writing `a()` at the call site and `a()` in the parameter
list. Arrays are always by reference.

`SUB` and `FUNCTION` may recurse, subject to the frame limit — see
[What this costs](#what-this-costs).

`DECLARE` is accepted and ignored. SolaBasic resolves every procedure in a pass
over the whole file before it compiles anything, so nothing needs declaring
ahead of its use.

### Input and output

```basic
PRINT "answer:", x; y
PRINT TAB(20); "indented"
PRINT USING "###.##"; total
INPUT "Name"; name$
LINE INPUT line$
```

`PRINT` separates with `,` to the next 14-column zone and with `;` not at all. A
trailing `;` or `,` suppresses the newline. `TAB(n)` and `SPC(n)` are allowed in
the list.

**A number prints with a leading space when positive** — the place where a minus
sign would go — and a trailing space always. This is QBasic's rule and Minimal
BASIC's before it, and it is why BASIC output looks airy.

`PRINT USING` supports `#`, `.`, `,`, `+`, `-`, `$$`, `**`, `^^^^` for numbers
and `&`, `!`, `\ \` for strings.

### Files

```basic
OPEN "data.txt" FOR INPUT AS #1
DO UNTIL EOF(1)
    LINE INPUT #1, line$
LOOP
CLOSE #1
```

Sequential only: `FOR INPUT`, `FOR OUTPUT`, `FOR APPEND`. `PRINT #`, `INPUT #`,
`LINE INPUT #`, `WRITE #`, `EOF`, `CLOSE`. There is no random access, no
`FIELD`, no `GET`/`PUT`.

### Ending

`END` stops the program. `STOP` does the same and says where.

---

## Built-in functions

**Mathematical.** `ABS` `ATN` `COS` `EXP` `FIX` `INT` `LOG` `RND` `SGN` `SIN`
`SQR` `TAN`, and `RANDOMIZE` as a statement.

**String.** `ASC` `CHR$` `INSTR` `LCASE$` `LEFT$` `LEN` `LTRIM$` `MID$`
`RIGHT$` `RTRIM$` `SPACE$` `STR$` `STRING$` `UCASE$` `VAL`.

`MID$` is a function only. It is not an assignment target.

Twenty-seven in all, against Minimal BASIC's eleven and Full BASIC's fifty-two.

---

## What is not here

### Never — the PC

QBasic's largest surface is not language, it is a machine. None of it is here
and none of it is planned:

`SCREEN`, `PSET`, `LINE`, `CIRCLE`, `PAINT`, `DRAW`, `PALETTE`, `GET`/`PUT` for
graphics, `PLAY`, `SOUND`, `BEEP`, `PEEK`, `POKE`, `DEF SEG`, `VARPTR`,
`CALL ABSOLUTE`, `CALL INTERRUPT`, `INP`, `OUT`, `WAIT`, `SHELL`, `ON KEY`,
`ON TIMER`, `KEY`, `LOCATE`, `COLOR`, `CLS`, `INKEY$`, `CHAIN`, `COMMON`, `RUN`.

### Never — the vestiges

| | why |
| --- | --- |
| `GOSUB` / `RETURN` / `ON n GOSUB` | `SUB` is the mechanism. `RETURN` also needs a computed jump, which SolVM does not have: the return address is dynamic and `OP_JUMP` takes a literal offset, so each `RETURN` would compile to a chain of comparisons over a return-id stack. Cutting it saves that entirely. |
| `ON n GOTO` | the same computed-jump problem, in the form the tree-walker solved with an array. `SELECT CASE` says it. |
| `DATA` / `READ` / `RESTORE` | a listing carrying its own input is a line-numbered idea. Files are here instead. |
| line numbers | labels are here instead, and a leading number is one. |
| `DEF FN` | `FUNCTION` says it. |
| `SINGLE` | see the divergences. |

### Not yet

Named so that adding one is a decision rather than a drift. Each says what would
make it worth doing:

| | when |
| --- | --- |
| `ON ERROR GOTO` / `RESUME` / `ERR` | CB80 had it, so the cut line says it belongs. It waits because Solum already has the unwinding half — `onError` and `ensure` — and the design should be settled against those rather than guessed at. **The first SolaBasic program that needs to survive a bad file.** |
| `TYPE` ... `END TYPE` | records. The first program wanting more than parallel arrays. |
| `REDIM` and dynamic arrays | the first program that cannot size an array at compile time. |
| `OPTION EXPLICIT` | when a misspelled variable has cost somebody an afternoon. |
| `MID$` as a statement | when something needs to patch a string in place and `LEFT$` + `RIGHT$` is the workaround being written twice. |
| Random-access files | the first program with a record format. |

---

## Where this is not QBasic

The list `basic.sol` keeps, for the same reason: a gap written down is a gap,
and a gap discovered is a bug.

**1. There is no `SINGLE`.** QBasic's default numeric type is a 32-bit float
printed to seven significant digits. SolVM has `i64` and `f64` and nothing
between, so emulating it means rounding on every store and would still print
differently. SolaBasic's default numeric type is **`DOUBLE`**, `!` is not a
suffix, and `AS SINGLE` is refused rather than silently widened. **A ported
program will print more digits than it used to.** This is the largest single
divergence and the one most likely to surprise.

**2. `INTEGER` is 64 bits.** QBasic's is 16 and `LONG` is 32, and both overflow
at their boundary. SolaBasic has one integer type, and `LONG` is a synonym for
it. A program relying on `32767 + 1` failing will not fail here — it will be
right, which is worse.

**3. Spaces between tokens are required.** `FORI=1TO10` is not `FOR I = 1 TO 10`.
This is inherited deliberately from
[basic.sol](../programs/basic.sol), which explains at length why: a tokeniser
that ignores spaces cannot work left to right on characters alone, and has to
know where it is in the grammar. It is a different scanner, not a missing
branch. Nobody writes it; it is still a gap.

**4. A string may not contain a double quote.** QBasic has the same restriction,
and `CHR$(34)` is the same answer. Recorded because it looks like an oversight.

**5. Procedures are resolved before compilation.** QBasic requires `DECLARE` for
a procedure used before it is defined, and QB's editor writes them for you.
SolaBasic takes a pass first, so `DECLARE` is accepted and does nothing.

---

## What this costs

**Recursion depth is SolVM's, not BASIC's.** A `SUB` compiles to a Solum block
and a SolaBasic call is a Solum frame, so a SolaBasic program's call depth is
bounded by [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) — about
254 levels. [ideas.md](ideas.md) predicted exactly this when it argued for a
Pascal interpreter: *"a lexically nested language spends frames in proportion to
the interpreted program's call depth, so 3.5 would be met head on rather than
dodged."* SolaBasic meets it head on. A line-numbered BASIC never could, which
is what made `basic.sol` fit.

**By-reference parameters need boxing.** Solum sends values, so a variable
passed by reference to a `SUB` that assigns to it must live in a cell rather
than a slot. Which variables those are is decided statically, in the same pass
that resolves procedures. **This is the most expensive item in the language and
the one most likely to be underestimated.** It is here anyway, because passing
by value instead would leave `SWAP`-shaped programs running and answering
differently — and a wrong answer is the one outcome this project does not
accept.

**A jump reaches 64KB.** Every offset is a `u16`, so no jump can span more than
65,535 bytes of code within one chunk. That is a few thousand statements per
procedure — generous, and a hard wall for one long module-level program.

**Arithmetic stays a message send.** SolVM has no arithmetic instruction; `a + b`
compiles to one `OP_SEND`, not an add. It is *"a much faster interpreter"*
rather than *"compiled"*, and the document should say so before the benchmark
does — but the benchmark has now spoken and it is **45 times** the tree-walker,
not the order of magnitude first written here. The same counting loop, 200,000
iterations of two statements, is 1.54s under
[basic.sol](../programs/basic.sol) and 0.034s compiled, both including VM start.

---

## How done is decided

There is no standard and no conformance suite, so the authority has to be
manufactured. Three mechanisms, in descending order of how much they are worth:

**1. A real QBasic is the oracle.** Every program in the test corpus runs under
QuickBASIC 4.5 in DOSBox and under SolaBasic, and the two outputs are compared.
Where they differ, either SolaBasic is wrong or the difference is one of the
five divergences above — and if it is neither, the divergence list gains an
entry before the build goes green. This is the nearest thing to somebody else's
test, and it is the only mechanism here that can find something nobody thought
of.

**2. A recorded transcript per feature**, compared byte for byte on every build,
in the manner of [programs/basic/](../programs/basic/). Every statement in this
document and every function in it has one, and the check is that the document
and the transcripts cover the same list.

**3. This document is frozen when the compiler starts.** It may still change —
a specification written before an implementation is always partly wrong — but
every change is recorded below, with its date and its reason. **The goal may
move; it may not move silently.** That is the whole of what ECMA-55 gave the
interpreter, and it is the part that can be had without a standard.

### Changes to this document

**2026-08-26 — stage 3 was built first, and the claim it tests holds.**
[programs/sola.sol](../programs/sola.sol) compiles labels and `GOTO` to
`OP_JUMP` and `OP_LOOP`. Before it was written, a chunk was hand-assembled with
a backward jump to an arbitrary earlier offset, a forward jump over dead code,
and a conditional between them: it verified and ran. **Both ways of getting it
wrong were checked too**, because a test that cannot fail proves nothing — a
jump into the middle of an instruction and a jump to a point at a different
stack depth are each refused *at load*, exit 65, as a message rather than a
crash. The depth-0 discipline is load-bearing rather than tidy, and nothing in
the design section above needed changing.

**2026-08-26 — stage 2 needed nothing the back end did not already have.**
`IF`, `SELECT CASE`, `FOR`, `DO`, `WHILE` and `EXIT` are in
[programs/sola.sol](../programs/sola.sol), and the whole of them is one stack of
open blocks over the hole-and-fill the `GOTO` work had already built: a forward
jump emitted before its target exists, patched when the closing line turns up
instead of when a label does. **Nothing was added to the emitter**, which is the
finding — the structured half of the language is the unstructured half with a
stack on top, and doing stage 3 first is what made that visible rather than
lucky.

Two things this settled that the document had left open. **The blocks are a
stack and the statements stay flat**, rather than a parser that builds a tree:
BASIC's blocks are an opening line and a closing line, half the errors worth
reporting are the two not matching, and a stack has the mismatch in its hand
where a tree would refuse to parse and have less to say. And **`EXIT FOR` leaves
the innermost `FOR` rather than the innermost block**, so it searches down that
stack — four lines, against a tree walk.

**Where `FOR` is not exact** is now written down, because it was decided here.
A step written as a literal fixes the loop's direction at compile time, which is
nearly every loop. A step that is an expression does not, so the test becomes
`(limit - counter) * step >= 0` — right for either sign, and forever on a step
of nought, as BASIC is. The one case it gets wrong is a product that underflows
to `-0.0`, which compares as `>= 0` and buys one extra iteration. Unreachable
from a literal step.

**2026-08-26 — the speed estimate was too modest, and is now measured.**
[What this costs](#what-this-costs) said compiling should be worth "roughly an
order of magnitude" over the tree-walker. It is 45 times: the same 200,000-
iteration loop is 1.54s under `basic.sol` and 0.034s compiled. The sentence has
been replaced with the measurement. The claim it qualifies — that this is a much
faster *interpreter* rather than compiled code, because arithmetic is still a
send — is unchanged and still the honest description.

---

## Stages

The language above is the finish line. The order to reach it in:

| | |
| --- | --- |
| **0** | **Done** — [programs/sola.sol](../programs/sola.sol). A `.sob` out of a SolaBasic program, running, with nothing of the compiler present. |
| **1** | **Partly.** Expressions, variables and `PRINT` are here; the three types are not — every number is a Double — and `PRINT`'s rules are stage 6. |
| **2** | **Done.** `IF` in both shapes, `SELECT CASE`, `FOR`/`NEXT`, `DO`/`LOOP`, `WHILE`/`WEND`, `EXIT FOR` and `EXIT DO`, all compiled to jumps. |
| **3** | **Done, and first, as this table said it should be.** `GOTO` and labels, forwards and backwards, to any label in the program. What it found is below. |
| **4** | `SUB`, `FUNCTION`, `CALL`, locals, `SHARED`, `STATIC` — and the boxing analysis. The largest stage by some distance. |
| **5** | Arrays, `DIM`, `OPTION BASE`. |
| **6** | `INPUT`, files, `PRINT USING`. |
| **7** | The QuickBASIC 4.5 comparison harness, and the divergence list settled against it. |

Stage 3 is the one to reach early even though the ordering does not demand it,
because it is the claim the whole design rests on. If arbitrary `GOTO` between
statements does not verify as predicted, that is worth knowing in week one
rather than week six.
