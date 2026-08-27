# SolaBasic cheatsheet

*Every statement and every supplied function on one page, for when you know what
you want and not what it is called.
[SOLABASIC-REFERENCE.md](SOLABASIC-REFERENCE.md) is the full account of each of
these; [SOLABASIC.md](SOLABASIC.md) is the language definition and says where the
boundary came from. This is the index to your own memory.*

---

## Syntax, all of it

```basic
' a comment, to the end of the line
REM so is this, and it may hold anything -- an apostrophe, an unclosed quote

Again:                        ' a label. A number at the start of a line is one too
  total = total + 1
  IF total < 3 THEN GOTO Again

a = 1 : PRINT a : PRINT "two"      ' ':' joins statements; a line ends where it ends
LET a = 1                          ' LET is optional and means nothing
```

**Keywords and names are case-insensitive** — `PRINT`, `Print` and `print` are
one word. **Spaces between words are required**: `FORI=1TO10` is not a `FOR`.
There is no line continuation.

| Written | Is |
| --- | --- |
| `42` | an **Integer** — no point and no exponent |
| `3.14` `1.5E-3` | a **Double** — anything else |
| `&HFF` `&O17` | `255` and `15`, in hexadecimal and octal |
| `"text"` | a String. **No escape**, so `CHR$(34)` is how you write a `"` |
| `A%` `A&` | an Integer, 64-bit |
| `A#` | a Double |
| `A$` | a String |
| `DEFINT I-N` | the default type for names starting `I` to `N` |
| a name with no suffix and no `DEF` | a **Double** |

`DEFINT`, `DEFLNG`, `DEFDBL` and `DEFSTR`, one per type, each taking letters or
ranges separated by commas, anywhere in the listing.

## Ten rules that bite

| | |
| --- | --- |
| **Three types and no `SINGLE`** | QBasic's default is a 32-bit float; here it is a Double, so a ported program prints more digits. `A!` is refused by name. |
| **`INTEGER` is 64 bits** | QBasic's is 16 and overflows at `32767`. A program relying on that failure will not fail here. |
| **`/` always answers a Double** | `7 / 2` is `3.5`. `7 \ 2` is `3`, and `\` cuts **towards nought**. |
| **`MOD` takes the sign of its left side** | `-7 MOD 2` is `-1`, as QBasic says and not as the machine would. |
| **There is no boolean** | True is `-1` and false is `0`, which is why `NOT`, `AND` and `OR` are bit operations and still read correctly. |
| **A condition is true when it is not nought** | `IF count THEN ...` works. |
| **Assigning a Double to an Integer rounds** | `n% = 3 / 2` is `2`. |
| **Parameters pass by reference** | Assigning to one assigns to the caller's variable. **Brackets pass a copy**: `Double (n)`. |
| **An array name means one array in the whole listing** | Bounds are settled while compiling and looked up by name, so two procedures cannot each `DIM` a `Temp`. |
| **Names beginning `SOLA` are reserved** | `PRINT`'s own rules are written in SolaBasic and compiled into your program. |

**Every variable starts at nought**, or at `""`, so reading one before assigning
is `0` and not an error. **`VAL` is strict** — the whole string must be a number.

## Expressions, tightest first

| | |
| --- | --- |
| `^` | raise to a power; always a Double, and **right-associative** |
| `-` | negation — so `-2 ^ 2` is `-4` |
| `*` `/` | multiply, divide |
| `\` | integer divide, both sides rounded first |
| `MOD` | remainder |
| `+` `-` | add, subtract; `+` also joins text |
| `=` `<>` `<` `<=` `>` `>=` | comparison, on numbers or on text |
| `NOT` | flip every bit |
| `AND` | bit-by-bit and |
| `OR` `XOR` | bit-by-bit or, exclusive or |

Every level is left-associative but `^`. Brackets group.

## Choosing

```basic
IF x > 0 THEN PRINT "positive" ELSE PRINT "not"
IF i > 10 THEN Done              ' a bare label after THEN or ELSE is a GOTO

IF n = 1 THEN                    ' nothing after THEN opens a block
  PRINT "one"
ELSEIF n = 2 THEN
  PRINT "two"
ELSE
  PRINT "many"
END IF

SELECT CASE n
CASE 1, 2
  PRINT "one or two"
CASE 3 TO 6
  PRINT "three to six"
CASE IS >= 10
  PRINT "ten or more"
CASE ELSE
  PRINT "none of those"
END SELECT
```

The `SELECT CASE` subject is evaluated once, the first matching `CASE` runs, and
**nothing may come between `SELECT CASE` and its first `CASE`**.

## Repeating

```basic
FOR i = 1 TO 10 : PRINT i : NEXT i
FOR i = 10 TO 1 STEP -1 : PRINT i : NEXT
FOR a = 1 TO 2 : FOR b = 1 TO 2 : PRINT a; b : NEXT b, a   ' innermost first

DO WHILE more   : ... : LOOP
DO UNTIL done   : ... : LOOP
DO : ... : LOOP WHILE more
DO : ... : LOOP UNTIL done
DO : ... : LOOP                  ' only EXIT DO leaves this one

WHILE k < 3 : k = k + 1 : WEND   ' an older spelling of DO WHILE, with no EXIT
```

The limit and the step are worked out **once, when the loop starts**. The test
is before the body, except in the two `LOOP WHILE`/`LOOP UNTIL` shapes. A `DO`
tests at one end or at neither, **never at both**.

| | |
| --- | --- |
| `EXIT FOR` `EXIT DO` | leave the innermost enclosing loop **of that kind** |
| `EXIT SUB` `EXIT FUNCTION` | leave the procedure |
| `GOTO label` | any label in the same procedure; **may not cross into one** |
| `END` | stop the program, from anywhere |

## Declaring

```basic
CONST Size = 10                  ' worked out while compiling, stored nowhere
OPTION BASE 1                    ' asked once, before the first DIM

DIM a(10)                        ' OPTION BASE to 10
DIM Grid(1 TO 8, 1 TO 8)         ' both bounds said; up to eight dimensions
DIM Counts(20) AS INTEGER        ' AS INTEGER, LONG, DOUBLE or STRING -- or a suffix
DIM SHARED Totals(12)            ' visible inside every procedure
DIM Balance AS DOUBLE            ' a plain variable, given a type
```

Bounds are **constant expressions**, because an array is made once at the size
the listing wrote. There is no `REDIM`. `DECLARE` is accepted and does nothing.

## Procedures

```basic
SUB Greet (who$)
  PRINT "hello, "; who$
END SUB

FUNCTION Square (x)
  Square = x * x                 ' a FUNCTION answers by assigning to its own name
END FUNCTION

CALL Greet("world")
Greet "world"                    ' the same call
PRINT Square(5)                  ' in an expression, always with brackets
```

Both may be written anywhere at module level and called from above where they
are written. A `FUNCTION` that never assigns to its name answers nought.
Recursion works, and **stops at about 254 levels** with `call depth exceeded`.

| inside a procedure | |
| --- | --- |
| every variable | local to that call |
| `SHARED a, b()` | name module-level variables to see instead |
| `STATIC n` | keep its value between calls |

## Printing

```basic
PRINT "answer: "; x              ' ';' moves nowhere
PRINT a, b, c                    ' ',' moves to the next zone -- 14 columns
PRINT                            ' end the line
PRINT "open";                    ' a separator at the end holds the line open
PRINT TAB(10); "at ten"          ' column 10, counting from one
PRINT "x"; SPC(5); "y"           ' five spaces from wherever it is
```

**A number is written as a sign character — a minus, or a space where one would
go — then the digits, then a trailing space.** A string gets neither. There is
no nought before the point, and the margin is 80.

```basic
PRINT USING "###.##"; 3.14159#
PRINT USING "value: ### units"; 9
PRINT USING "###"; 1; 2; 3       ' the format starts again per item
```

| in a number field | | | in a text field | |
| --- | --- | --- | --- | --- |
| `#` | a digit position | | `!` | the first character |
| `.` | where the point goes | | `\   \` | as many as the backslashes and the gap |
| `,` | thousands separators | | `&` | the whole string |
| `+` | leading, always show the sign | | | |
| `-` | trailing minus for a negative | | | |
| `**` | two more positions, asterisk padding | | | |
| `$$` | two more, one a floating `$` | | | |
| `^^^^` | exponential, then `D±dd` | | | |

`_` makes the next character literal. **A number too wide for its field is
written in full behind a `%`** rather than cut.

## Reading

```basic
INPUT n                          ' shows "? "
INPUT "NAME"; n$                 ' shows "NAME? "  -- ';' adds the question mark
INPUT "NAME", n$                 ' shows "NAME"    -- ',' does not
INPUT "TWO"; a, b                ' one line, split on the comma
LINE INPUT s$                    ' the line whole
```

## Files

Sequential only. Channels `1` to `15`, and the `#` is not part of the number.

```basic
OPEN "data.txt" FOR OUTPUT AS #1
PRINT #1, "a line"
WRITE #1, "Hans", 42
CLOSE #1

OPEN "data.txt" FOR INPUT AS #1
DO UNTIL EOF(1)
  LINE INPUT #1, row$
  PRINT row$
LOOP
CLOSE #1
```

| | |
| --- | --- |
| `OPEN p FOR INPUT`/`OUTPUT`/`APPEND AS #n` | read; write, replacing; write, onto the end |
| `CLOSE #n[, #n]...` | those; **`CLOSE` alone closes them all** |
| `PRINT #n, ...` | as `PRINT`, zones and all. `PRINT #n, USING f; ...` too |
| `WRITE #n, ...` | commas between, quotes round the text — the form `INPUT #` reads back |
| `INPUT #n, v[, v]...` | one line, split on commas, quotes taken off |
| `LINE INPUT #n, v$` | the line whole |
| `EOF(n)` | true once there is no more to read |

**Lines are ended with a line feed**, where QBasic writes a carriage return and
a line feed; a trailing carriage return is taken off when reading, so a file
written by either can be read here.

## The supplied functions

Twenty-seven, each compiled **where it is called** — there is no library in the
file the compiler writes.

| numbers | | | text | |
| --- | --- | --- | --- | --- |
| `ABS(x)` | size without a sign | | `LEN(s$)` | how many characters |
| `SGN(x)` | `-1`, `0` or `1` | | `LEFT$(s$, n)` `RIGHT$(s$, n)` | the first or last `n`; **clamps** |
| `INT(x)` | the **floor** | | `MID$(s$, start[, n])` | from `start`, all or `n` |
| `FIX(x)` | cut towards nought | | `INSTR([start, ]s$, part$)` | where it is, one-based, or **0** |
| `SQR(x)` | square root | | `UCASE$(s$)` `LCASE$(s$)` | case folded |
| `EXP(x)` `LOG(x)` | e to the x; **natural** log | | `LTRIM$(s$)` `RTRIM$(s$)` | spaces off the front, or the back |
| `SIN` `COS` `TAN` `ATN` | **radians** | | `SPACE$(n)` | `n` spaces |
| `RND` | a Double, `0` to under `1` | | `STRING$(n, s$)` | `s$`'s first character, `n` times |
| `RANDOMIZE n` | *a statement* — reseed | | `ASC(s$)` `CHR$(n)` | character to number, and back |

| between the two | |
| --- | --- |
| `STR$(x)` | the number as text — **without** the leading space `PRINT` adds |
| `VAL(s$)` | the number that text spells, **strictly**: the whole string or nothing |

## What is not here

| | |
| --- | --- |
| not written yet | random-access files — `GET`, `PUT`, `FIELD`, `LOF`, `SEEK`; `LBOUND`, `UBOUND` |
| not yet, by the definition | `ON ERROR`, `TYPE`, `REDIM`, `OPTION EXPLICIT` |
| **not coming** | `GOSUB`, `RETURN`, `ON n GOTO`, `DATA`, `READ`, `SINGLE`, and the whole of the PC — `SCREEN`, `PEEK`, `POKE` |

## Running it

```sh
./bin/solas programs/sola.sol            # build the compiler, once
./bin/solvm programs/sola.sob prog.bas   # prog.bas -> prog.bas.sob
./bin/solvm prog.bas.sob                 # run it

./bin/solvm programs/sola.sob prog.bas out.sob    # name the output
./bin/solvm --dump out.sob                        # the instructions it produced
./bin/solvm programs/sola.sob                     # a demonstration, and how to run it
```

---

*Where this is not QBasic, and what the compiler says when it refuses, are both
in [SOLABASIC-REFERENCE.md](SOLABASIC-REFERENCE.md). The compiler is
[programs/sola.sol](../programs/sola.sol) and its header is the argument for how
it works.*
