# SolaBasic — reference manual

*Every statement the compiler accepts, what it does, and where it stops. For
looking things up.*

SolaBasic is BASIC in the shape QuickBASIC gave it — labels rather than line
numbers, `SUB` and `FUNCTION`, block `IF` and `SELECT CASE` — compiled to a
`.sob` file and run by `bin/solvm`. [SOLABASIC.md](SOLABASIC.md) is the language
*definition*: what the dialect is, where its boundary came from, and why. **This
page is what the compiler accepts today**, which is less, and says so in
[What is not here yet](#what-is-not-here-yet).

The compiler is [programs/sola.sol](../programs/sola.sol), and its own header is
the argument for how it works.

## Running one

```sh
./bin/solas programs/sola.sol            # build the compiler, once
./bin/solvm programs/sola.sob prog.bas   # prog.bas -> prog.bas.sob
./bin/solvm prog.bas.sob                 # run it
```

A second argument names the output. With no arguments at all the compiler
compiles a demonstration and tells you how to run it.

```sh
./bin/solvm programs/sola.sob prog.bas out.sob
./bin/solvm --dump out.sob               # the instructions it produced
```

## Contents

- **[A program](#a-program)** — [lines](#lines) · [labels](#labels) · [comments](#comments)
- **[Values](#values)** — [numbers](#numbers) · [strings](#strings)
- **[Variables](#variables)**
- **[Expressions](#expressions)**
- **[Assigning](#assigning)** — `LET`
- **[Printing](#printing)** — `PRINT`
- **[Choosing](#choosing)** — `IF` · `SELECT CASE`
- **[Repeating](#repeating)** — `FOR` · `DO` · `WHILE` · `EXIT`
- **[Jumping](#jumping)** — `GOTO`
- **[Procedures](#procedures)** — `SUB` · `FUNCTION` · `CALL` · `SHARED` · `STATIC` · `DECLARE`
- **[Stopping](#stopping)** — `END`
- **[What is not here yet](#what-is-not-here-yet)**
- **[Where this is not QBasic](#where-this-is-not-qbasic)**
- **[What it says when it refuses](#what-it-says-when-it-refuses)**

---

## A program

### Lines

**One statement to a line.** There is no `:` between statements and no
continuation onto the next line: a statement begins where its line begins and
ends where its line ends.

**Keywords and names are case-insensitive.** `PRINT`, `Print` and `print` are one
word, and `Total` and `TOTAL` are one variable. Text inside a string is left
alone, so `PRINT "Hello"` still has its capital.

Spaces between words are **required**. `FORI=1TO10` is not `FOR I = 1 TO 10`.

### Labels

A label marks a line so a `GOTO` can name it. Either spelling:

```basic
Again:
  PRINT "round and round"
  GOTO Again
```

```basic
100 PRINT "at one hundred"
GOTO 100
```

**A label is a string of characters and not a number.** A number written at the
start of a line is a label, not a line number: labels need not ascend, need not
be present, and nothing sorts them. `100` and `100.0` are two different labels.
This is CB80's rule and it is what lets an old listing through unaltered.

A label may stand on a line of its own, in which case it belongs to the next
statement there is — or to the end of the program, if there is none.

### Comments

```basic
REM this is a comment, and the rest of the line is not read at all
' so is this
PRINT "x"      ' and this
```

`REM` takes the rest of its line as raw text, so it may hold anything — an
apostrophe, an unclosed quote. `'` may follow a statement on the same line.

---

## Values

### Numbers

**Every number is a Double**: a 64-bit binary floating point value. There is one
numeric type and no way to ask for another.

```basic
PRINT 42
PRINT 3.14159
PRINT 1.5E-3
PRINT -7
```

`7 / 2` is `3.5`. Division is never integer division.

### Strings

Between double quotes. **There is no escape**, so a string cannot contain a
double quote.

```basic
PRINT "hello, world"
```

Strings may be compared with the same operators numbers are, which compares
their characters:

```basic
s = "abc"
IF s < "abd" THEN PRINT "less"
```

---

## Variables

A variable springs into being on first use. **Every variable starts at nought**,
so reading one before assigning to it is `0` and not an error.

```basic
PRINT z        ' 0
z = z + 1
PRINT z        ' 1
```

A name is a letter followed by letters and digits. There are no type suffixes:
`A$` is not a name, it is an error.

**At module level every variable is global.** Inside a `SUB` or `FUNCTION` every
variable is local to that call, unless [`SHARED`](#shared) or
[`STATIC`](#static) says otherwise — see [Procedures](#procedures).

---

## Expressions

Highest binding first. Every level is left-associative.

| | |
| --- | --- |
| `-` | negation |
| `*` `/` | multiply, divide |
| `+` `-` | add, subtract |
| `=` `<>` `<` `<=` `>` `>=` | comparison |

Brackets group. `(a + b) * c` is what it looks like.

**A condition is a comparison, or a number.** Where a statement wants a
condition, a comparison answers one directly and any other value is true when it
is not nought — which is BASIC's rule:

```basic
IF count THEN PRINT "there are some"
```

---

## Assigning

```basic
LET x = 1
x = 1
```

`LET` is optional and means nothing.

---

## Printing

```basic
PRINT "answer: "; x
PRINT a, b, c
PRINT
```

Items are separated by `;` or `,`, and **both do the same thing**: the items of
one `PRINT` are joined and shown as one line. `PRINT` with nothing after it
prints an empty line.

> **This is not BASIC's `PRINT` yet.** There are no print zones, no leading space
> in front of a positive number and no trailing space after one, and `,` does not
> move to the next zone. That is stage 6 of
> [SOLABASIC.md](SOLABASIC.md#stages), and it is the thing here most likely to be
> mistaken for a bug.

---

## Choosing

### IF

**Two shapes, and what follows `THEN` decides which.** Nothing after it opens a
block; anything else is the one-line form.

```basic
IF x > 0 THEN PRINT "positive"
IF x > 0 THEN PRINT "positive" ELSE PRINT "not"
```

A bare label after `THEN` or `ELSE` is a `GOTO`:

```basic
IF i > 10 THEN Done
```

The block form runs until `END IF`, with any number of `ELSEIF` arms and at most
one `ELSE`:

```basic
IF n = 1 THEN
  PRINT "one"
ELSEIF n = 2 THEN
  PRINT "two"
ELSE
  PRINT "many"
END IF
```

A one-line `IF` holds **one** statement on each side, and it may not be a
statement that opens a block.

### SELECT CASE

```basic
SELECT CASE n
CASE 1, 2
  PRINT "one or two"
CASE 3 TO 6
  PRINT "somewhere in three to six"
CASE IS >= 10
  PRINT "ten or more"
CASE ELSE
  PRINT "none of those"
END SELECT
```

The subject is evaluated **once**. A `CASE` takes any number of alternatives
separated by commas, and each is one of:

| | |
| --- | --- |
| `value` | equal to it |
| `low TO high` | between them, both ends included |
| `IS <op> value` | any of the six comparisons |

The first `CASE` that matches runs, and nothing after it. `CASE ELSE` must be
last. **Nothing may come between `SELECT CASE` and its first `CASE`.**

---

## Repeating

### FOR

```basic
FOR i = 1 TO 10
  PRINT i
NEXT i

FOR i = 10 TO 1 STEP -1
  PRINT i
NEXT
```

The limit and the step are evaluated **once, when the loop starts**, so a body
that assigns to what they were computed from does not change the number of
times it runs. **The test is before the body**, so a loop whose range is already
empty runs no times.

`NEXT` may name its variable or not. `NEXT j, i` closes two loops, innermost
first:

```basic
FOR a = 1 TO 2
  FOR b = 1 TO 2
    PRINT a; ","; b
NEXT b, a
```

### DO

The condition goes at the top, at the bottom, or nowhere — **not at both ends**.

```basic
DO WHILE more
  ...
LOOP

DO UNTIL done
  ...
LOOP

DO
  ...
LOOP WHILE more

DO
  ...
LOOP UNTIL done

DO
  ...            ' only EXIT DO leaves this one
LOOP
```

A `DO ... LOOP` with the test at the bottom always runs its body at least once.

### WHILE

```basic
WHILE k < 3
  k = k + 1
WEND
```

`WHILE`/`WEND` is `DO WHILE`/`LOOP` under an older spelling. It has no `EXIT`.

### EXIT

`EXIT FOR` and `EXIT DO` leave the innermost enclosing loop **of that kind**, so
one written inside an `IF` inside the loop leaves the loop:

```basic
FOR i = 1 TO 10
  IF i = 3 THEN EXIT FOR
  PRINT i
NEXT i
```

`EXIT SUB` and `EXIT FUNCTION` are in [Procedures](#procedures).

---

## Jumping

```basic
GOTO Cleanup
```

Forwards or backwards, to any label in the same procedure — or anywhere at
module level, if that is where it is written. **A `GOTO` may not cross between
module level and a procedure**, or between two procedures.

It may leave a block from inside one, which is the ordinary way to give up on a
loop early when `EXIT` will not do:

```basic
FOR i = 1 TO 10
  IF i = 3 THEN GOTO Escaped
  PRINT i
NEXT i
Escaped:
```

And a label just before `NEXT` is how BASIC spells what a later language calls
`continue`:

```basic
FOR j = 1 TO 3
  IF j = 2 THEN GOTO Skip
  PRINT j
Skip:
NEXT j
```

A jump to a label that does not exist is refused **before the program runs**.

---

## Procedures

A `SUB` does something; a `FUNCTION` answers something. Both may be written
anywhere at module level, and both may be called from above where they are
written — the whole listing is read before anything is compiled.

### SUB

```basic
SUB Greet (who)
  PRINT "hello, "; who
END SUB

CALL Greet("world")
Greet "world"
```

The two call forms are the same call. Brackets around the parameter list are
optional in the declaration.

### FUNCTION

**A `FUNCTION` answers by assigning to its own name.** Its answer is nought if it
never does.

```basic
FUNCTION Square (x)
  Square = x * x
END FUNCTION

PRINT Square(5)
```

A call in an expression always takes brackets. Recursion works:

```basic
FUNCTION Fact (n)
  IF n <= 1 THEN
    Fact = 1
  ELSE
    Fact = n * Fact(n - 1)
  END IF
END FUNCTION
```

> **Recursion stops at about 254 levels deep** and says `call depth exceeded`
> when it does. A SolaBasic call is a real machine frame, and that is the
> machine's limit — [ROADMAP 3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels).

### Parameters are passed by reference

**Assigning to a parameter assigns to the caller's variable.**

```basic
SUB Double (v)
  v = v * 2
END SUB

a = 21
Double a
PRINT a            ' 42
```

It works through a chain, too: if `A` hands its parameter to `B` and `B` hands
it to `C`, and only `C` assigns to it, all three pass by reference and the write
reaches the original.

**Brackets pass a copy instead**, which is QBasic's own way of spelling by value:

```basic
n = 10
Double (n)
PRINT n            ' 10, unchanged
```

Note the difference between the two call forms here: `CALL Double(n)` passes `n`
itself, because those brackets are the argument list. `Double (n)` passes a copy,
because without `CALL` there is no argument list and the brackets group an
expression.

An argument that is not a plain variable — an expression, a literal — is passed
as a copy whatever the parameter is.

### EXIT SUB and EXIT FUNCTION

Leave at once. A `FUNCTION` answers whatever it has assigned to its name so far.

```basic
SUB Maybe (v)
  IF v < 0 THEN EXIT SUB
  PRINT "positive "; v
END SUB
```

### SHARED

Inside a procedure, names a module-level variable to use instead of a local one.
It is in force for the whole procedure wherever it is written.

```basic
total = 0

SUB AddOn (v)
  SHARED total
  total = total + v
END SUB
```

### STATIC

A local that survives between calls, and starts at nought.

```basic
SUB Counted
  STATIC seen
  seen = seen + 1
  PRINT "call number "; seen
END SUB
```

### DECLARE

Read and dropped. QBasic needs one for a procedure used before it is defined;
this compiler resolves every name in a pass over the whole listing first, so
there is nothing for it to say. Listings that carry them still compile.

---

## Stopping

`END` stops the program. It may appear anywhere, including on a one-line `IF`.

---

## What is not here yet

Named so that reaching for one gets an answer rather than a puzzle. The stage
each belongs to is in [SOLABASIC.md](SOLABASIC.md#stages).

| | |
| --- | --- |
| `INTEGER`, `STRING`, `AS`, `DEFINT`, type suffixes | stage 1 — there is one numeric type and no way to name it |
| `^`, `\`, `MOD`, `AND`, `OR`, `NOT`, `XOR` | stage 1 |
| `+` joining two strings | stage 1 — it is numeric only, and two strings are an error when it runs |
| `&H` and `&O` literals | stage 1 |
| `PRINT`'s zones, `TAB`, `SPC`, `PRINT USING` | stage 6 |
| `DIM`, arrays, `OPTION BASE` | stage 5 |
| `INPUT`, `LINE INPUT`, files | stage 6 |
| `CONST` | stage 5 |
| `ON ERROR`, `TYPE`, `REDIM`, `OPTION EXPLICIT` | listed as *not yet* in the language definition |
| `:` between statements on one line | not written yet |
| the built-in functions — `ABS`, `LEFT$`, `LEN`, `RND` and the rest | stage 1 |

`GOSUB`, `RETURN`, `ON n GOTO`, `DATA`, `READ`, `SINGLE` and the whole of the PC
— `SCREEN`, `PEEK`, `POKE` — are **not coming**. See
[SOLABASIC.md](SOLABASIC.md#what-is-not-here) for why each.

---

## Where this is not QBasic

The full list is in [SOLABASIC.md](SOLABASIC.md#where-this-is-not-qbasic); these
are the ones that bite while typing.

1. **There is no `SINGLE`, and one numeric type.** Everything is a Double, so a
   ported program prints more digits than it used to.
2. **Spaces between words are required.** `FORI=1TO10` is not a `FOR`.
3. **A string may not contain a double quote**, and there is no `CHR$` yet to
   get round it.
4. **`PRINT` does not format like BASIC's**, as above.
5. **`DECLARE` does nothing**, because nothing needs declaring.

---

## What it says when it refuses

Compile-time refusals name the line. The ones worth recognising:

| | |
| --- | --- |
| `there is no label 'X' to jump to` | a `GOTO` naming a label that is nowhere in the same procedure |
| `the label 'X' is used twice` | two lines carry the same label |
| `this FOR is never closed by its NEXT` | reported on the line that **opened** the block, which is the one to go and look at |
| `NEXT closes the DO opened on line 1` | a closing line that closes the wrong thing |
| `NEXT J closes the FOR on 1, which counts I` | `NEXT` naming a variable that is not the loop's |
| `a DO tests at one end or at neither, not at both` | `DO WHILE ... LOOP UNTIL` |
| `EXIT FOR with no FOR loop around it` | `EXIT` looks for its own kind of loop, not the innermost block |
| `nothing may come between SELECT CASE and its first CASE` | there is nowhere for it to run |
| `'FOR' opens a block, and a one-line IF holds one statement` | a block statement after `THEN` on the same line |
| `there is no SUB or FUNCTION called 'X'` | including a misspelling, since a bare name with arguments is a call |
| `S takes 1 argument and was given 2` | checked when it compiles, not when it runs |
| `a procedure cannot be written inside another` | `SUB` inside `SUB` |
| `more than 255 names in one procedure` | the machine's frame is a byte wide |
| `a jump of N bytes: no jump reaches further than 65535` | one procedure holding more code than a jump can cross |

Two things are refused when the **program** runs rather than when it compiles:
`undefined name` for a procedure never bound, and `call depth exceeded` for
recursion past about 254 levels.
