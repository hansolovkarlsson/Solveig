# Solum — language reference

Solum is the language; **Solas** compiles it, **SolVM** runs the bytecode, and
**Solis** is the REPL. This document describes the language as it is. For why it
is that way see [design.md](design.md); for what is still missing see
[ROADMAP.md](ROADMAP.md).

Everything is an object and all work happens by sending messages.

```
a := #45.
a:print.
```

## Contents

- [Running a program](#running-a-program)
- [Lexical structure](#lexical-structure)
- [Values](#values)
- [Names and binding](#names-and-binding)
- [Messages](#messages)
- [Blocks](#blocks)
- [Control flow](#control-flow)
- [Objects](#objects)
- [Message reference](#message-reference)
- [Errors](#errors)
- [Limits](#limits)

---

## Running a program

```sh
./bin/solas program.sol          # compiles to program.sob
./bin/solvm program.sob          # runs it
./bin/solis                      # a prompt, one line at a time
```

The program is `solvm`; its sources live under `solum/`. The two are the same
word -- `SOLVM` is how *solum* was written before the alphabet split V into two
letters -- so the directory keeps the modern spelling and the program the older
one.

`solas --dump` also prints the disassembly. `solvm --dump` prints it for a
compiled file before running.

A `.sob` file is verified before it runs: every instruction must fit, every
operand must index something that exists, and the last instruction must stop the
machine. A corrupt file is refused rather than executed.

---

## Lexical structure

### Comments

`;` begins a comment, which runs to the end of the line.

```
a := #45.        ; this is a comment
```

### Statements

`.` separates statements. It is required between two and optional after the
last, in a script and inside a group or block alike.

```
a := #1. b := #2      ; the last needs no '.'
```

A line beginning with `:` continues the expression above it, so

```
total := #10
:add(#5).
```

is one statement, not two.

### Literals

| Form | Type | Notes |
| --- | --- | --- |
| `#45`, `#-45` | integer | `#` is a type tag, not a marker |
| `45`, `45.5` | float | a bare number is a float |
| `1e3`, `1.5e-3`, `1E+3` | float | exponent optional, sign optional |
| `"hello"` | string | see escapes below |
| `[#1, #2]` | array | sugar for `array:of(#1, #2)` |
| `{ #1 }` | block | code as a value |
| `'foo` | symbol | **scans, but has no runtime type yet** |

`#` marks an integer and its absence marks a float, so `#45` and `45` are
different values of different types. There is no exponent on an integer, `#`
meaning exact.

A `.` only continues a number when a digit follows it, so `45.` is the float
`45` followed by a statement separator.

### String escapes

`\"`, `\\`, `\n`, `\t`, `\r`. Any other escape is an error rather than a literal
backslash. There is no `\0`.

```
"she said \"hi\"".
"one\ntwo".
```

A literal newline inside the quotes also works.

### Identifiers

`[A-Za-z_][A-Za-z0-9_]*`. Message selectors are identifiers, which is why `=`
cannot be one: `a:=(b)` would otherwise be both an assignment and a send.

### Reserved names

None are keywords, but these are bound as globals at startup and shadowing them
will surprise you: `integer`, `float`, `string`, `array`, `object`, `nil`,
`true`, `false`, `infinity`, `nan`.

`self` is not a global; it is recognised by the compiler inside a block.

---

## Values

| Type | Literal | Semantics |
| --- | --- | --- |
| nil | `nil` | the absent value |
| boolean | `true`, `false` | |
| integer | `#45` | signed 64-bit, **immutable** |
| float | `45.5` | IEEE-754 binary64, **immutable** |
| string | `"hi"` | **immutable** |
| array | `[#1]` | growable, **mutable** |
| block | `{ #1 }` | code as a value |
| object | `object:new` | slots plus a prototype, **mutable** |

**Values and references divide on mutability.** Numbers and strings are
immutable, so they are values: two are equal when they say the same thing, and
sharing is always safe. Arrays, blocks, and objects are references: two are equal
only when they are the same one, and `a := b` makes two names for one thing.

```
a := "hi". b := "hi". a:equals(b):print.      ; true  -- same characters
a := [#1]. b := [#1]. a:equals(b):print.      ; false -- two arrays
```

### Strictness

Types never coerce. An integer does not combine with a float, and a string does
not join to a number.

```
#45:add(1.5).        ; error: 'add' expects integer, got float
"a":concat(#1).      ; error: 'concat' expects a string, got integer
#45:asFloat:add(1.5) ; the conversion is written out
```

Integer arithmetic traps rather than wrapping: overflow, division by zero, and
`INT64_MIN div #-1` are all errors. Floats follow IEEE, so they overflow to
`infinity` and divide by zero to it, infinity being a representable float where
there is no such integer.

---

## Names and binding

`:=` binds a name to an evaluated value. It means the same thing everywhere.

```
a := #45.                            ; a global
integer:double := { self:mul(#2) }.  ; a slot on a class
p:x := #3.                           ; a slot on an object
```

Only **parameters** and names declared with `| ... |` are locals. Everything else
is a global, read or written.

```
counter := #0.
integer:bump := {
    counter := counter:add(#1).      ; updates the global
    counter
}.

integer:quadruple := { | d |         ; a temporary of this frame
    d := self:double.
    d:double
}.
```

Only the top level of a script may **create** a global. An undeclared name
assigned inside a block must already exist, so a typo is reported rather than
quietly becoming a variable that looks local.

Declarations may open any group or block body, and a duplicate name in one frame
is a compile error.

---

## Messages

`:` is the send operator. Parentheses group a message's arguments.

```
receiver:selector.
receiver:selector(a).
receiver:selector(a, b).
```

Sends chain left to right:

```
#2:add(#3):mul(#4):print.     ; #20, being (2+3)*4
```

There are no operators and no precedence to remember; `a:add(b:mul(c))` is
written out.

A bare identifier resolves to a local, then to an enclosing frame's local, then
to a global. It is a lookup, not a send.

---

## Blocks

`{ ... }` makes a block: code as a value. Writing one runs nothing.

```
b := { #21:add(#21) }.
b:value():print.              ; #42
```

Parameters come before `|`; a leading `|` declares temporaries instead.

```
add := { a, b | a:add(b) }.
add:value(#3, #4):print.      ; #7

{ | t | t := #5. t:add(#1) }:value():print.   ; #6
```

A block's body may hold several statements separated by `.`; the last is its
value.

### Capture

A block reads the frame it was written in, lexically, however many blocks deep.

```
integer:sumTo := { | total, i |
    total := #0.
    i := #1.
    { i:greaterThan(self):not }:whileTrue({
        total := total:add(i).
        i := i:add(#1)
    }).
    total
}.
```

`self` is the receiver the block was written under, captured when the block is
created — so a block inside a method still answers the right object.

A block that reads or writes its enclosing frame cannot outlive it. Calling one
after that frame has returned is reported, not left to read whatever now sits
there. A block that touches nothing outside itself may escape freely.

---

## Control flow

There is no control-flow syntax. `ifTrue`, `ifElse`, and `whileTrue` are ordinary
messages that take unevaluated blocks, so a user can add control structures the
same way.

```
#5:lessThan(#10):ifTrue({ "small":display }).
#5:lessThan(#10):ifElse({ "small" }, { "large" }):display.

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

`and` and `or` take a block for the same reason — so the answer can be settled
without running it.

```
x:greaterThan(#0):and({ x:lessThan(#10) }).
```

`whileTrue` and `and`/`or` are strict about the block answering a boolean.

Recursion works, and with conditionals it terminates:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul(self:sub(#1):factorial) })
}.
```

---

## Objects

There is no separate notion of a class. `object:new` answers a fresh object
delegating to the receiver; whether something is a class or an instance is how
you use it.

```
point := object:new.
point:x := #0.                       ; a default every instance sees
point:y := #0.
point:sum := { self:x:add(self:y) }. ; a method: a slot holding a block

point:make := { a, b | | p |
    p := self:new.                   ; self, so it survives inheritance
    p:x := a.
    p:y := b.
    p
}.

p := point:make(#3, #4).
p:sum:print.                         ; #7
```

- A slot holding a **block** is a method; sending its name runs it with the
  receiver as `self`. A slot holding anything else answers that value.
- Assigning on an instance always makes the **instance's own** slot, so it
  shadows the prototype rather than writing through.
- Delegation chains, and the nearest slot wins.

### Calling what you override

`self:via(ancestor)` begins the lookup at the ancestor but keeps the receiver, so
`self` inside the ancestor's method is still the instance.

```
animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro:display.            ; I am rex!
```

The ancestor is named rather than inferred, so a method extends the object it was
written against however deep the receiver is.

`parent` reads the delegation link and is read-only.

### Showing an object

Define `asString` and it serves `print`, `display`, `fill`, and an enclosing
array alike.

```
point:asString := { "point({}, {})":fill([self:x, self:y]) }.
p:print.                      ; point(3, 4)
[p]:print.                    ; [point(3, 4)]
```

Without one, an object shows its address.

---

## Message reference

Every built-in message. `print` shows the **literal** form (`#45`, `"a\"b"`);
`display` writes the **text** (`45`, `a"b`); `asString` answers that text as a
string.

### Every type

`print`, `display`, `asString`, `equals`, `notEquals`.

`asString` takes an optional format spec:

```
[align] [','] ['0'] [width] ['.' decimals]

45.8:asString("6.2")         ; " 45.80"
45.8:asString("08.2")        ; "00045.80"
#1234567:asString(",")       ; "1,234,567"
1234.5:asString(",10.2")     ; "  1,234.50"
#45:asString("<6")           ; "45    "
"ab":asString(">6")          ; "    ab"
```

`<` `>` `^` align left, right, centre. Numbers align right by default and text
left. A value wider than the width is never cut.

`,` groups whole-number digits in threes, and only those -- a sign, a fraction,
and an exponent pass through. Decimals and grouping belong to numbers; asking a
string, a boolean, or an array for either is an error.

Zero fill must align right and goes after any sign, so `#-45:asString("06")` is
`-00045`. It cannot be combined with `,`. The flags have one order, so there is
one way to write a given spec.

With no argument it answers the plain text, which is what `display`, `fill`, and
array rendering ask for.

`equals` compares characters for strings and identity for arrays, blocks, and
objects.

### integer

| Message | Answers |
| --- | --- |
| `new(#n)` | the integer — the long form of a literal |
| `add(n)` `sub(n)` `mul(n)` | an integer; traps on overflow |
| `div(n)` `mod(n)` | **floored**; traps on zero and on `INT64_MIN div #-1` |
| `negated` `abs` | an integer; traps on the most negative |
| `lessThan(n)` `greaterThan(n)` | a boolean |
| `lessOrEqual(n)` `greaterOrEqual(n)` | a boolean |
| `asFloat` | a float; loses precision above 2^53 |
| `asString` | the digits, without the `#` |
| `asBase(#n)` | the digits in base `n`, 2 to 36, as a string |

`#-7:div(#2)` is `#-4` and `#-7:mod(#2)` is `#1`: division floors, so the
remainder takes the divisor's sign and stays in `[0, n)` for positive `n`.

### float

Everything integer has, minus `asFloat` and the overflow traps, plus:

| Message | Answers |
| --- | --- |
| `new(f)` | the float |
| `floor` `ceiling` `rounded` `truncated` | an **integer**; errors on infinity, not-a-number, or out of range |

There is no `asInteger`: narrowing names its direction so there is no default to
remember. `rounded` is half away from zero.

Dividing by zero answers `infinity` rather than erring.

### string

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `at(#i)` | a one-character string; **one-based** |
| `concat(s)` | a new string; strict about its argument |
| `fill([...])` | a new string with the blanks filled; see below |
| `lessThan(s)` `greaterThan(s)` | a boolean, comparing characters |
| `lessOrEqual(s)` `greaterOrEqual(s)` | a boolean |
| `asInteger` `asFloat` | strict: the whole string must be a number |
| `asInteger(#n)` | reads base `n`, 2 to 36; the digits alone, no `0x` |
| `asUppercase` `asLowercase` | a new string; ASCII letters only |
| `asString` | itself |
| `asString(spec)` | padded text; see the spec below |

`fill` puts the array's values into the `{}` blanks, rendering each by sending
it `asString`. `{{`
writes a literal brace; `}` is never special. Placeholders and values must match
exactly — too few and too many are both errors.

```
"you have {} apples":fill([#3]):display.    ; you have 3 apples
```

Parsing is strict at both ends: `" 45"` and `"45 "` are errors, not `45`.

Bases go through `asBase` and `asInteger(#n)` rather than a letter in the format
spec, so one message covers every base from 2 to 36 and nothing in the spec
starts looking like a conversion character. Digits above nine are lowercase, and
padding comes from the spec by chaining:

```
#255:asBase(#16)                    ; "ff"
#255:asBase(#16):asString("08")     ; "000000ff"
"ff":asInteger(#16)                 ; #255
```

### array

| Message | Answers |
| --- | --- |
| `new` | an empty array |
| `of(...)` | an array of the arguments — what `[...]` compiles to |
| `size` | an integer |
| `at(#i)` | the element; **one-based**, out of range is an error |
| `at_put(#i, v)` | the value stored |
| `add(v)` | **the array**, so it chains |
| `do(block)` | the array, having run the block per element |
| `collect(block)` | a new array of the block's answers |
| `select(block)` | a new array of the elements the block accepted |

`collect` and `select` leave the receiver untouched. `select` is strict about the
block answering a boolean.

### boolean

| Message | Answers |
| --- | --- |
| `not` | a boolean |
| `and(block)` `or(block)` | short-circuit; the block runs only if needed |
| `ifTrue(block)` `ifFalse(block)` | the block's answer, or nil |
| `ifElse(t, f)` | the chosen block's answer |

### block

| Message | Answers |
| --- | --- |
| `value(...)` | the block's answer; the count must match its parameters |
| `whileTrue(body)` | nil, having run `body` while the receiver answers true |

### object

| Message | Answers |
| --- | --- |
| `new` | a fresh object delegating to the receiver |
| `via(ancestor)` | a delegating view: lookup starts there, `self` stays |
| `parent` | the prototype, or nil at the root; read-only |

### nil

`print`, `display`, `asString`, `equals`, `notEquals`. Nothing else — asking nil
for anything more is an error rather than nil again.

---

## Errors

An error stops the running program and reports the line, innermost frame first.
There is no way to catch one.

```
solum: integer does not understand 'frobnicate'
  [line 1] in script
```

Errors, rather than silent answers, are the rule: unknown messages, wrong
argument counts, type mismatches, out-of-range indices, integer overflow,
division by zero, undeclared names, and a block outliving its frame.

---

## Limits

| | |
| --- | --- |
| Recursion | about **30 levels** — the frame cap is 64 and each level costs two, one for the method and one for the `ifElse` branch |
| Constants, names per chunk | 255 |
| Arguments, parameters, array literal elements | 255 |
| Locals per frame | 255 |
| Solis input line | 1024 bytes, silently truncated beyond |
| Strings | bytes, not characters: `size` counts bytes, `at` answers a byte, and `"café":size` is 5 |
| Case | ASCII only, and by explicit range rather than the C locale |
| Strings | no `\0`, no unicode escapes |
| Symbols | `'foo` scans but has no runtime type |

Collection is mark-and-sweep and stop-the-world. `SOLUM_GC_STRESS=1` collects on
every allocation, which is how the collector is tested.
