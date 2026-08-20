# Solum — language reference

Solum is the language; **Solas** compiles it, **SolVM** runs the bytecode, and
**Solis** is the REPL. This document describes the language as it is, message by
message, for looking things up.

If you are meeting the language for the first time, read [GUIDE.md](GUIDE.md)
instead — the same ground in an order that builds, with a runnable example behind
each concept. For why the language is this way see [design.md](design.md); for
what is still missing see [ROADMAP.md](ROADMAP.md).

Everything is an object and all work happens by sending messages.

```
a := #45.
a:print.
```

## Contents

- [Running a program](#running-a-program)
- [Splitting a program across files](#splitting-a-program-across-files)
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
./bin/solis                      # a prompt; input may span lines
```

The program is `solvm`; its sources live under `solum/`. The two are the same
word -- `SOLVM` is how *solum* was written before the alphabet split V into two
letters -- so the directory keeps the modern spelling and the program the older
one.

`solas --dump` also prints the disassembly. `solvm --dump` prints it for a
compiled file before running.

A `.sob` file is verified before it runs: every instruction must fit, every
operand must index something that exists, every jump must land on the start of
an instruction inside the chunk, and the last instruction must stop the machine.
A corrupt file is refused rather than executed.

The file also carries a format version, and a build reads only its own: a `.sob`
left over from an earlier one is refused with `unsupported bytecode version`
rather than misread. Recompile the `.sol`.

---

## Splitting a program across files

```
"library.sol":include.
```

compiles that file into this one at that point, as though its text had been
written there. Globals are one flat namespace and stay one: two files binding
the same name collide exactly as two `:=` in one file do, and the later wins.

**It stands alone.** An include is a compile-time directive, not a message. It
is spelled as a send to a string because the language has no directive syntax
and no keyword to spare, and that shape already parses — but the compiler takes
it before any send is emitted. Anywhere other than on its own as a statement,
`"...":include` is a compile error rather than a send that would fail at run
time:

```
[prog.sol:1:7] solas: an include must stand alone as a statement at '"library.sol"'
  x := ("library.sol":include).
        ^^^^^^^^^^^^^
```

The receiver has to be a literal string, because the file is found while
compiling and a name holding one has no value yet. Sent to anything else,
`include` is an ordinary selector that anybody may define.

**The file is found beside the file including it**, not beside the directory you
happened to be standing in, so a program can be moved without its includes
breaking. An absolute path is taken as it stands. Source that is not a file at
all — the prompt, or a string handed to the compiler — has nothing to be
relative to, and the working directory is used.

**A file is compiled once** per compilation, however many ways it is reached,
keyed by where it turns out to be on disk so that two spellings of one file are
one file. C compiles it every time and leaves each file to guard itself, which
needs conditional compilation that Solum has not got; and a second copy could
only rebind names already bound and repeat whatever the file did on the way. So
two files may each include what they need without arranging between themselves
who includes what — and a cycle ends instead of recurring.

**Errors name the file**, and the chain that reached it:

```
[lib/broken.sol:2:6] solas: expected an expression at ':'
  y := :.
       ^
  ... included from lib/middle.sol, line 1
  ... included from prog.sol, line 3
```

Includes may nest 64 deep.

Two things this is not. There is no module system: an included file gets no
namespace of its own. If you want one, bind an object and hang the rest off it,
which claims one global instead of a dozen —
[examples/library.sol](../examples/library.sol) does that. And a `.sob` file is
one chunk with no record of which file a line came from, so a run-time stack
trace gives a line number without saying which file counted it.

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
| `'foo` | symbol | an interned name; no closing quote |

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
will surprise you: `integer`, `float`, `string`, `array`, `symbol`, `block`,
`boolean`, `object`, `nil`, `true`, `false`, `infinity`, `nan`.

The first eight are the class objects; the rest are values.

`self` is not a global; it is recognised by the compiler inside a block.

`include` is not reserved either, but a string literal sent `include` is the
compile-time directive above and never a message.

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
| symbol | `'foo` | an interned name, **immutable** |
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
#45:add(1.5).        ; solvm: 'add' expects integer, got float (no implicit coercion)
"a":concat(#1).      ; solvm: 'concat' expects a string, got integer
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

Declarations may open a block or a method body, and a duplicate name in one
frame is a compile error.

A group may open with them too, but only inside a block or a method, because a
temporary needs a frame to live in and only those have one. The top level of a
script has no frame, and says so:

```
( | t | t := #5. t ):print.
[line 1:3] solas: a temporary needs a frame, so declare it inside a block at '|'
  ( | t | t := #5. t ):print.
    ^
```

Declare it in the enclosing block instead.

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

### Grouping

`( ... )` groups an expression, which is how a chain is redirected:

```
#1:add(#2):mul(#3):print.       ; #9, being (1+2)*3
#1:add((#2:mul(#3))):print.     ; #7, being 1+(2*3)
```

A group may hold several statements separated by `.`. The earlier ones are
discarded and the last is the group's value.

```
( #1. #2 ):print.               ; #2
```

It may also open with `| a, b |`, declaring temporaries of the frame it sits in
-- but only where there is a frame, which means inside a block or a method body.
At the top level of a script it is a compile error; see
[Names and binding](#names-and-binding).

---

## Blocks

`{ ... }` makes a block: code as a value. Writing one runs nothing.

```
b := { #21:add(#21) }.
b:value():print.              ; #42
```

Parameters come before `|`. A leading `|` declares temporaries, and a block may
have both -- the parameters, then a temporaries list of its own:

```
{ k | | t | t := k:add(#1). t }
```

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

### What the compiler does with them

Written literally, `ifTrue`, `ifFalse`, `ifElse`, `whileTrue`, `and`, and `or`
compile to jumps: no block is allocated and no frame is entered. This is an optimisation
only — the meaning is exactly that of the message, and the message is still
there, reachable through `perform` or with a block held in a variable.

It applies when every block involved is written on the spot with no parameters
and no temporaries. For `whileTrue` that includes the receiver, since the
condition is the receiver. Anything else is compiled as an ordinary send, so
these still mean what they say rather than being quietly rewritten:

```
true:ifElse({ a | a }, { #2 }).      ; still an arity error, as a send would be
true:ifElse({ | t | t := #1. t }, { #0 }).   ; t stays in a frame of its own
{ a | a }:whileTrue({ #1 }).         ; the condition is a block like any other
```

A non-boolean receiver reports the same error either way:

```
#45:ifElse({ #1 }, { #2 }).
solvm: integer does not understand 'ifElse'
```

A condition that answers something other than a boolean is `whileTrue`
complaining about the answer, not a receiver failing to understand a message,
and it reads the same either way:

```
{ #1 }:whileTrue({ #2 }).
solvm: whileTrue expects the condition block to answer a boolean, got integer
```

`and` and `or` say the same thing about their block, naming themselves, since
what the block answered is what they answer:

```
true:and({ #5 }).
solvm: 'and' expects the block to answer a boolean, got integer
```

A loop compiles to a jump backwards, which is the only way the machine can run
the same instruction twice. It therefore need not terminate — but neither need
the loop it was compiled from, so nothing is reachable that was not before.

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

### The built-in classes are objects too

`integer`, `array`, `string` and the rest are ordinary objects holding the
messages their *instances* understand. Sending one of those to the class itself
is an error, not a shortcut:

```
[#1, #2]:add(#3).    ; the array grows
array:add(#3).       ; solvm: 'add' expects an array, got object
```

The messages a class answers for itself are the ones that make instances —
`array:of(...)`, `array:new`, `integer:new(...)`, `object:new` — plus reflection,
which reads either side. `respondsTo` agrees with sending, so
`array:respondsTo('add)` is false and `array:respondsTo('of)` is true.

Every built-in class delegates to `object`, so there is one hierarchy and
everything is an object in the type graph as well as in the slogan:

```
#45:isKindOf(object):print.      ; true
"s":isKindOf(object):print.      ; true
integer:parent:equals(object):print.   ; true
object:parent:print.             ; nil  -- the chain ends here
```

Four classes cannot make their instances, because those instances are not
objects, and they say so rather than inheriting a `new` that would answer
something useless:

```
string:new.
solvm: a string is written as a literal, not made with 'new' -- "" is the empty one
```

`symbol`, `block` and `boolean` refuse in the same way, each naming what to
write instead.

Binding a block over one of these replaces the requirement along with the
primitive, so a class can be given messages of its own:

```
array:describe := { "arrays, in a list" }.
array:describe:display.
```

### Adding methods to a built-in class

A built-in class is an object and a slot holding a block is a method, so
extending one needs no new rule — it is the same `:=` used everywhere:

```
integer:double := { self:mul(#2) }.
#21:double:print.                    ; #42
```

Every built-in takes them, arguments and recursion included:

```
integer:between := { lo, hi | self:greaterOrEqual(lo):and({ self:lessOrEqual(hi) }) }.
#5:between(#1, #10):print.           ; true

string:shout   := { self:asUppercase:concat("!") }.   ; "hey":shout   -> "HEY!"
array:second   := { self:at(#2) }.                    ; [#1,#2,#3]:second -> #2
boolean:toggle := { self:not }.                       ; true:toggle  -> false
block:twice    := { self:value. self:value }.
```

The addition is global: every integer gains `double`, because there is one
`integer` and that is where the method now lives. To give a *distinct* type its
own behaviour, build an object that holds a value rather than extending the
class — a value type cannot be subclassed, since an unboxed number's class is
chosen by its type tag and there is nowhere to record a different one.

Two things to know before overriding a message that already exists.

**The primitive is gone.** A slot wins over a primitive of the same name, and
nothing keeps the displaced one. `via` cannot reach it either: a built-in class
has no ancestor holding the version you replaced.

**Do not build the text with `fill` inside an `asString` override.** `fill`
renders each of its values by *sending* `asString`, so it re-enters the override
and recurses until the call-depth cap:

```
integer:asString := { "<{}>":fill([self:abs]) }.
#42:asString.
solvm: call depth exceeded
```

Use `concat` there instead. The recursion is bounded rather than fatal, but it
is an easy loop to write.

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

**Assigning it does not re-parent.** `o:parent := other` binds an ordinary slot
named `parent`, which shadows the message — the delegation link is an internal
pointer rather than a slot, so nothing a program writes can corrupt dispatch.
The assignment succeeds, `o:parent` then answers `other`, and what `o` actually
delegates to is unchanged:

```
a := object:new. a:tag := #1.
b := object:new. b:tag := #2.
kid := a:new.

kid:parent := b.
kid:parent:equals(b):print.      ; true   -- the slot answers
kid:tag:print.                   ; #1     -- but the chain still runs to a
```

This is the ordinary shadowing rule rather than a special case: a slot always
wins over a primitive of the same name, which is what lets an object define its
own `asString`. It is worth knowing because it is the one assignment that looks
like it did something and did not.

There is no way to re-parent at run time. It would need the link to become a
real slot, which is a separate question — see [ROADMAP.md](ROADMAP.md) 2.14.

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

## Reflection

Five messages let a program ask about itself. Names are given as symbols,
because a symbol is what a name is and comparing one is a pointer comparison.

| Message | Answers |
| --- | --- |
| `slots` | an array of symbols naming the receiver's **own** slots |
| `slotAt(name)` | the value in that slot, searching the chain like a send |
| `respondsTo(name)` | whether a send of that name would find anything |
| `isKindOf(class)` | whether the receiver delegates to `class`, at any depth |
| `perform(name, ...)` | the answer to a send whose name is decided at run time |

Continuing the `point` above:

```
point:slots:print.               ; ['x, 'y, 'sum, 'make]
p:isKindOf(point):print.         ; true
p:respondsTo('sum):print.        ; true
p:perform('sum):print.           ; #7
```

`slots` answers own slots in the order they were defined; inherited names are
not yours, and `parent:slots` is how you ask about those. `respondsTo` and
`slotAt` search the whole chain, as a send does.

A value answers for the class it dispatches to, so `#45:isKindOf(integer)` is
true and `#45:respondsTo('add)` is true. `slots` and `slotAt` want an object to
look inside and say so on anything else.

The built-in classes are objects whose slots hold primitives, so
`integer:slots` lists what an integer understands. `slotAt` on one of those is
an error: a primitive is C, and has no value to answer.

### Fetching a method

A slot holding a block **is** a method, so `slotAt` is the only way to get at
one as a value. What comes back is the plain block, and `self` is supplied by a
send rather than carried by the block:

```
m := point:slotAt('sum).
m:value.                 ; solvm: nil does not understand 'x'
p:perform('sum):print.   ; #7 -- the receiver comes from the send
```

`boundTo` chooses one. It answers a **second block** over the same code with
`self` set, which you then call like any other block. The longer explanation,
including what it is for, is in [fetched-methods.md](fetched-methods.md):

```
bound := m:boundTo(p).
bound:value:print.       ; #7
```

Binding and calling stay two things, as `via` keeps them two things. So `value`
means exactly what it always meant -- the arguments are the block's own, and the
receiver is not one of them:

```
n := integer:slotAt('poly):boundTo(#10).
n:value(#3, #7):print.   ; #37
```

The receiver may be any value, since `self` may be. The original block is
untouched: binding answers a new one, and binding that one binds again.

Two things it does **not** do. It does not lift the frame restriction — a block
that reads its home frame is no freer for being bound, so binding chooses a
receiver, not a lifetime. And it does not survive a send: installing a bound
block in a slot still makes an ordinary method, and a send supplies its own
receiver, which is what makes an installed block a method at all.

```
b:show := m:boundTo(a).
b:show.                  ; the send wins -- self is b, not a
```

---

## Message reference

Every built-in message. `print` shows the **literal** form (`#45`, `"a\"b"`);
`display` writes the **text** (`45`, `a"b`); `asString` answers that text as a
string.

Elements inside an array are always shown in literal form, so that a printed
array reads back as one: `["a"]:display` writes `["a"]`, quotes and all, where
`"a":display` writes `a`.

### Every type

`print`, `display`, `asString`, `equals`, `notEquals`, and the reflection
messages `perform`, `respondsTo`, `isKindOf`, `slots`, `slotAt` (see
[Reflection](#reflection)).

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

`<` `>` `^` align left, right, centre. Numbers align right by default and
everything else left. A value wider than the width is never cut.

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

Everything integer has, minus `asFloat`, `asBase`, and the overflow traps, plus:

| Message | Answers |
| --- | --- |
| `new(f)` | the float |
| `floor` `ceiling` `rounded` `truncated` | an **integer**; errors on infinity, not-a-number, or out of range |

There is no `asInteger`: narrowing names its direction so there is no default to
remember. `rounded` is half away from zero. Bases are an integer's business, so
`asBase` is not here.

Dividing by zero answers a float rather than erring: `1:div(0)` is `infinity`,
`-1:div(0)` is `-infinity`, and `0:div(0)` is `nan`, which is IEEE rather than a
choice made here. `nan:equals(nan)` is false for the same reason.

A float is written as the shortest text that reads back as the same value, so
`0.1` prints as `0.1` and not as the seventeen digits it really is. A whole
float prints without a point, which is how the two number types are told apart
on the page: the `#` marks the integer.

```
45:print.            ; 45
#45:print.           ; #45
1:div(3):print.      ; 0.3333333333333333
1e21:print.          ; 1e+21
0.000001:print.      ; 1e-06
```

`infinity` and `nan` are written by name, and both read back — `infinity` and
`nan` are globals, and `asFloat` parses either. `-infinity` has no literal;
`"-infinity":asFloat` gives it.

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
| `asSymbol` | the interned symbol for these characters |
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
| `sorted` | a new array in ascending order |
| `sorted(block)` | a new array ordered by the block |

`collect`, `select`, and `sorted` leave the receiver untouched. `select` and the
comparison block are both strict about answering a boolean.

**Sorting.** With no argument the order comes from *sending* `lessThan`, so a
type that defines one sorts itself:

```
[#3, #1, #2]:sorted:print.                            ; [#1, #2, #3]
["pear", "apple"]:sorted:print.                       ; ["apple", "pear"]
[#1, #3, #2]:sorted({ a, b | b:lessThan(a) }):print.  ; [#3, #2, #1]
```

The comparison answers whether `a` comes strictly before `b`. Mixed types are an
error rather than an arbitrary order, for the same reason arithmetic on them is:
`lessThan` has no coercion to fall back on.

The sort is **stable** -- equal elements keep the order they were in -- which is
what makes sorting twice a way to order by two keys: sort by the minor key
first, then by the major one.

### symbol

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `asString` | the name, as a string |

`'foo` is an interned name: two symbols spelling the same thing are the same
symbol, so `equals` is a pointer comparison. `"foo":asSymbol` finds the existing
one. A symbol never equals a string.

Useful as a tag where a string would be compared character by character:

```
state := 'running.
state:equals('running):ifTrue({ "go":display }).
```

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
| `boundTo(receiver)` | a new block over the same code, with `self` set |
| `whileTrue(body)` | nil, having run `body` while the receiver answers true |

### object

| Message | Answers |
| --- | --- |
| `new` | a fresh object delegating to the receiver |
| `via(ancestor)` | a delegating view: lookup starts there, `self` stays |
| `parent` | the prototype, or nil at the root; read-only — assigning it shadows the message rather than re-parenting |

`slots` and `slotAt` are listed under [Reflection](#reflection); they are on
every type but answer only for objects.

### nil

`print`, `display`, `asString`, `equals`, `notEquals`, and the five reflection
messages every type carries. Nothing else — asking nil for anything more is an
error rather than nil again, so a missing value is reported where it is used
rather than propagating.

`nil` names the value, not a class: there is no global for the class it
dispatches to. `nil:isKindOf(object)` is true, like every other value, but
`nil:slots` says an object is what has slots.

There is one nil and it carries no type, so `string:nil` and `integer:nil` are
not messages anything understands. A name holds a value and never a type, so
what a value is gets asked of the value: `isKindOf(string)` is false for nil and
true for a string. Absence and emptiness are different — `""`, `#0` and `[]` are
values that answer their type's messages, and nil answers almost nothing.

A declared temporary holds nil before it is assigned. A slot that was never
bound is a *miss* rather than a nil, reported like any unknown message, so a
prototype with an optional field binds `nil` as the default. The whole of it,
with the reasoning, is in [absence.md](absence.md).

---

## Errors

**A compile error** names the line and column, then shows the line with the
offending text underlined:

```
[line 2:9] solas: expected '.' between statements at ','
  b := #2 , .
          ^
```

A long line is windowed around the token rather than shown whole. Only the
first error in a statement is reported; the parser then resynchronises at the
next `.` and carries on, so one mistake gives one message.

**A runtime error** stops the program and reports the line of each frame,
innermost first. There is no way to catch one.

```
solvm: integer does not understand 'frobnicate'
  [line 1] in script
```

A running frame knows its line but not its column: the chunk records a line per
byte of bytecode, and a column would be a second table in every `.sob` for a
message only printed when something has already gone wrong.

Errors, rather than silent answers, are the rule: unknown messages, wrong
argument counts, type mismatches, out-of-range indices, integer overflow,
division by zero, undeclared names, and a block outliving its frame.

---

## Limits

| | |
| --- | --- |
| Recursion | about **62 levels** — the frame cap is 64 and a level costs one frame, now that an `ifElse` branch, a `whileTrue` body, and an `and`/`or` block are inlined rather than called |
| Constants, names, blocks per chunk | **65536** — a two-byte index, and both tables intern, so repeats cost nothing |
| Arguments, parameters, array literal elements | 255 — an argument count is one byte |
| Locals per frame | 255 |
| Solis input | no limit — the buffer grows, and reading continues while a bracket or a string is open |
| Strings | bytes, not characters: `size` counts bytes, `at` answers a byte, and `"café":size` is 5 |
| Case | ASCII only, and by explicit range rather than the C locale |
| Strings | no `\0`, no unicode escapes |
| Symbols | read-only: `perform`, `respondsTo`, and `slotAt` take one to *name* something, but nothing takes one to *create* a slot — there is no `slotAtPut` |

Collection is mark-and-sweep and stop-the-world. `SOLUM_GC_STRESS=1` collects on
every allocation, which is how the collector is tested.
