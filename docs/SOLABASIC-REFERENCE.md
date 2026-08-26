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
- **[Types](#types)** — [numbers](#numbers) · [strings](#strings) · [what a name's type is](#what-a-names-type-is)
- **[Variables](#variables)**
- **[Expressions](#expressions)**
- **[The supplied functions](#the-supplied-functions)**
- **[Declaring](#declaring)** — `CONST` · `DIM` · `OPTION BASE`
- **[Arrays](#arrays)**
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

## Types

**Three, and no more.**

| Type | Suffix | Backed by |
| --- | --- | --- |
| Integer | `%` or `&` | a 64-bit whole number |
| Double | `#` | 64-bit binary floating point |
| String | `$` | text of any length |

### Numbers

**A literal with no point and no exponent is an Integer**; anything else is a
Double. That one rule is why `7 / 2` and `7 \ 2` differ without anything being
declared.

```basic
PRINT 42          ' an Integer
PRINT 3.14159     ' a Double
PRINT 1.5E-3      ' a Double
PRINT &HFF        ' 255, written in hex
PRINT &O17        ' 15, written in octal
```

Mixing the two in one expression gives a Double. Assigning a Double to an
Integer **rounds** it.

```basic
n% = 3 / 2        ' 2, rounded from 1.5
```

### Strings

Between double quotes. **There is no escape**, so a string cannot contain a
double quote — `CHR$(34)` is how you write one.

```basic
PRINT "hello, world"
PRINT "con" + "cat"
```

`+` joins two strings. Strings compare with the same operators numbers do,
comparing their characters:

```basic
s$ = "abc"
IF s$ < "abd" THEN PRINT "less"
```

**Text and numbers never turn into each other by themselves.** `STR$` and `VAL`
are how you cross.

### What a name's type is

In order:

1. **Its suffix**, if it has one. `A%` and `A$` are two different variables.
2. **A `DEF` statement** covering its first letter.
3. Otherwise **Double**.

```basic
DEFINT I-N        ' every name starting I to N is an Integer
DEFSTR S
DEFDBL A-H, O-Z
```

A `DEF` applies to the whole listing wherever it is written.

---

## Variables

A variable springs into being on first use. **Every variable starts at nought**
— or at the empty string, if it is one — so reading one before assigning to it
is `0` and not an error.

```basic
PRINT z        ' 0
z = z + 1
PRINT z        ' 1
```

A name is a letter followed by letters and digits, optionally ending in a type
suffix. See [what a name's type is](#what-a-names-type-is).

**Names beginning `SOLA` are reserved.** `PRINT`'s rules are themselves written
in SolaBasic and compiled into your program, and those four letters are what
keeps its routines and its line buffer out of your way.

**At module level every variable is global.** Inside a `SUB` or `FUNCTION` every
variable is local to that call, unless [`SHARED`](#shared) or
[`STATIC`](#static) says otherwise — see [Procedures](#procedures).

---

## Expressions

Highest binding first. Every level is left-associative.

Tightest first.

| | |
| --- | --- |
| `^` | raise to a power; always a Double, and **right-associative** |
| `-` | negation |
| `*` `/` | multiply, divide; `/` always answers a Double |
| `\` | integer divide — both sides rounded first, and it cuts **towards nought** |
| `MOD` | remainder, taking the sign of the left-hand side |
| `+` `-` | add, subtract; `+` also joins text |
| `=` `<>` `<` `<=` `>` `>=` | comparison |
| `NOT` | flip every bit |
| `AND` | bit-by-bit and |
| `OR` `XOR` | bit-by-bit or, exclusive or |

`^` binds tighter than negation, so `-2 ^ 2` is `-4` and not `4`.

Brackets group. `(a + b) * c` is what it looks like.

**There is no boolean type.** A comparison answers `-1` when true and `0` when
false, which is why `NOT`, `AND` and `OR` are bit operations and still read
correctly:

```basic
PRINT (1 < 2)                        ' -1
IF a > 0 AND b > 0 THEN PRINT "both"
IF NOT (a = b) THEN PRINT "differ"
```

**A condition is true when it is not nought**, so a plain number works where one
is wanted:

```basic
IF count THEN PRINT "there are some"
```

---

## The supplied functions

Twenty-seven. Each is compiled **where it is called** — there is no library in
the file this writes, so a function is a short run of instructions rather than
something to call.

### Numbers

| | |
| --- | --- |
| `ABS(x)` | size without a sign; an Integer stays an Integer |
| `SGN(x)` | `-1`, `0` or `1` |
| `INT(x)` | the **floor** — `INT(-2.5)` is `-3` |
| `FIX(x)` | cut towards nought — `FIX(-2.5)` is `-2` |
| `SQR(x)` | square root |
| `EXP(x)` `LOG(x)` | e to the x, and the **natural** logarithm |
| `SIN(x)` `COS(x)` `TAN(x)` `ATN(x)` | **radians** |
| `RND` | a Double, at least 0 and always less than 1 |

`RANDOMIZE n` is a statement, and replaces the generator with one seeded to
repeat.

### Text

| | |
| --- | --- |
| `LEN(s$)` | how many characters |
| `LEFT$(s$, n)` `RIGHT$(s$, n)` | the first or last `n`; **clamps** rather than failing |
| `MID$(s$, start)` | from `start` to the end |
| `MID$(s$, start, n)` | `n` characters from `start`; a start past the end is `""` |
| `INSTR(s$, part$)` | where `part$` first is, one-based, or **0** |
| `INSTR(start, s$, part$)` | the same, looking from `start` |
| `UCASE$(s$)` `LCASE$(s$)` | case folded |
| `LTRIM$(s$)` `RTRIM$(s$)` | spaces off the front, or off the back |
| `SPACE$(n)` | `n` spaces |
| `STRING$(n, s$)` | `s$`'s first character, `n` times |
| `ASC(s$)` | the number of the first character |
| `CHR$(n)` | the one-character string that number spells |

### Between the two

| | |
| --- | --- |
| `STR$(x)` | the number as text |
| `VAL(s$)` | the number that text spells — **strictly**; see the divergences |

---

## Declaring

### CONST

A name for a value, worked out **while compiling** and never stored anywhere.

```basic
CONST Size = 10
CONST Pi# = 3.14159265358979
CONST Greeting$ = "hello"
```

A `CONST` may be built from literals and earlier `CONST`s, and must come before
anything that uses it. It is what makes `DIM a(Size)` mean something.

### OPTION BASE

The lowest subscript an array has when its `DIM` gives only an upper bound.
`0` or `1`, **asked once, before the first `DIM`**.

```basic
OPTION BASE 1
```

### DIM

```basic
DIM a(10)                        ' OPTION BASE to 10
DIM Grid(1 TO 8, 1 TO 8)         ' both bounds said
DIM Names$(100)
DIM Counts(20) AS INTEGER
DIM SHARED Totals(12)
DIM Balance AS DOUBLE            ' a plain variable, given a type
```

**Bounds are constant expressions** — literals and `CONST`s — because an array
is made once, at the size the listing wrote. Up to eight dimensions. There is
no `REDIM`, so an array is the size it was given.

`AS INTEGER`, `AS LONG`, `AS DOUBLE` or `AS STRING` says the type outright; a
suffix on the name says the same thing.

**`DIM SHARED` makes an array visible inside every procedure.** A plain `DIM` at
module level does not — a procedure names it with `SHARED a()` or does not see
it, exactly as with a plain variable. A `DIM` written inside a procedure makes a
fresh array on every call.

---

## Arrays

```basic
DIM squares(10)
FOR i = 0 TO 10
  squares(i) = i * i
NEXT i
PRINT squares(7)                 ' 49
```

Subscripts count from `OPTION BASE` unless the `DIM` said otherwise, and both
bounds are included.

**An array is passed to a procedure by writing `a()`**, at the declaration and
at the call. It is passed **by reference** — the procedure works on the caller's
array, not a copy — and unlike a scalar this costs nothing, because an array is
already a reference.

```basic
SUB Sort (v(), count%)
  ...
  v(j%) = v(j% + 1)              ' the caller sees this
END SUB

CALL Sort(n(), 6)
```

An array parameter is **one-dimensional**, and its subscripts start at
`OPTION BASE`.

**A subscript out of range is refused when the program runs.** For an array of
more than one dimension the compiler checks each subscript by name and says
which one — `subscript 2 of G is above 8` — because one out of range would
otherwise land on a *different element* rather than off the end. A
one-dimensional array needs no such check: there is nowhere for a bad subscript
to go except outside the array, and the machine refuses that itself.

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

**A number is a sign character — a minus, or a space where one would go — then
the digits, then a trailing space.** A string gets neither. That is why BASIC
output has its airy look, and why a negative number lines up under a positive
one:

```text
 14
-7
 2.5
 .5
text
```

There is no nought before the point, and a number too large or small for plain
digits is written with a `D` exponent.

**`,` moves to the next print zone; `;` moves nowhere.** A zone is 14 columns:

```basic
PRINT 1, 2, 3        '  1             2             3
PRINT "a"; "b"; "c"  ' abc
```

**A separator at the end of the line holds the line open** for the next `PRINT`
to carry on, and `PRINT` with nothing after it ends the line it is on:

```basic
PRINT "open";
PRINT " continued"   ' open continued
```

A line still open when the program stops is written out before it does.

**`TAB(n)` puts the next thing in column `n`**, counting from one, and starts a
new line if that column has gone by. **`SPC(n)`** is `n` spaces from wherever it
is. Both are only meaningful inside a `PRINT`.

```basic
PRINT TAB(10); "at ten"
PRINT "x"; SPC(5); "y"
```

**The margin is 80.** An item that will not fit goes on the next line.

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
| `PRINT USING` | stage 6 |
| `INPUT`, `LINE INPUT`, files | stage 6 |
| `LBOUND`, `UBOUND` | not written yet — an array's bounds are in the listing that `DIM`med it |
| an array parameter of more than one dimension | not written yet; its strides would have to travel with it |
| `ON ERROR`, `TYPE`, `REDIM`, `OPTION EXPLICIT` | listed as *not yet* in the language definition |
| `:` between statements on one line | not written yet |

`GOSUB`, `RETURN`, `ON n GOTO`, `DATA`, `READ`, `SINGLE` and the whole of the PC
— `SCREEN`, `PEEK`, `POKE` — are **not coming**. See
[SOLABASIC.md](SOLABASIC.md#what-is-not-here) for why each.

---

## Where this is not QBasic

The full list is in [SOLABASIC.md](SOLABASIC.md#where-this-is-not-qbasic); these
are the ones that bite while typing.

1. **There is no `SINGLE`.** QBasic's default numeric type is a 32-bit float;
   here the default is a Double, so a ported program prints more digits than it
   used to. Writing `A!` is refused by name rather than quietly widened.
2. **`INTEGER` is 64 bits**, where QBasic's is 16 and overflows at `32767`. A
   program relying on that failure will not fail here.
3. **Spaces between words are required.** `FORI=1TO10` is not a `FOR`.
4. **A string may not contain a double quote.** `CHR$(34)` is the way round it,
   as it is in QBasic.
5. **A Double prints to the shortest text that reads back as the same number**,
   where QuickBASIC prints sixteen significant digits. Measured against
   QuickBASIC 4.5: `1# / 3#` is `.3333333333333334` there and
   `.3333333333333333` here. They agree whenever the shortest round-trip is
   sixteen digits or fewer and rounds the same way, and part company on a
   seventeenth digit or the last one. Print zones, the margin and the `D`
   exponent all agree exactly.
   `STR$` does not add the leading space that BASIC's does — `PRINT` adds it,
   which is where BASIC puts it too.
6. **`VAL` is strict.** BASIC's reads a number off the front of a string and
   answers `0` for junk; this one wants the whole string to be a number. Reading
   a number out of the front of text wants a scanner, and there is none in the
   file the compiler writes.
7. **`DECLARE` does nothing**, because nothing needs declaring.
8. **An array name means one array in the whole listing.** QBasic lets two
   procedures each `DIM` a `Temp` of their own; here the second one is
   *dimensioned twice*. Bounds are settled while compiling and are looked up by
   name, so the name has to be the whole of the question.

**And two places where SolaBasic follows QBasic against the machine**, which is
worth knowing because the machine's answer is the one you would get by guessing.
`\` cuts towards nought and `MOD` takes the sign of its left-hand side, where
SolVM's own integer divide and remainder are *floored*: `-7 \ 2` is `-3` here
and `-7 MOD 2` is `-1`, as QBasic says and not as the machine would. Both are
**exact for every number an Integer can hold** — there is no large-value corner
where they stop agreeing with QBasic.

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
