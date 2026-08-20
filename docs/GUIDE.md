# A tour of Solum

*Every concept in the language, in an order that builds. Each section explains
one idea, shows it working, and points at a runnable example that goes deeper.*

This is the learning path. [REFERENCE.md](REFERENCE.md) is the lookup document —
every message, every rule, no narrative. [design.md](design.md) is how it works
inside and why it was built that way.

**Every snippet here has been run.** The outputs shown are what the VM actually
prints.

```sh
./bin/solas program.sol          # compiles to program.sob
./bin/solvm program.sob          # runs it
./bin/solis                      # a prompt; input may span lines
```

## Contents

1. [Everything is an object](#1-everything-is-an-object)
2. [Names and binding](#2-names-and-binding)
3. [Statements, groups, and temporaries](#3-statements-groups-and-temporaries)
4. [Numbers](#4-numbers)
5. [Text: strings and symbols](#5-text-strings-and-symbols)
6. [Values and references](#6-values-and-references)
7. [Blocks: code as a value](#7-blocks-code-as-a-value)
8. [Control flow is message sending](#8-control-flow-is-message-sending)
9. [Methods](#9-methods)
10. [Objects and prototypes](#10-objects-and-prototypes)
11. [Overriding, and `via`](#11-overriding-and-via)
12. [Arrays](#12-arrays)
13. [Reflection](#13-reflection)
14. [Fetching a method](#14-fetching-a-method)
15. [Getting text out](#15-getting-text-out)
16. [Errors and strictness](#16-errors-and-strictness)
17. [What is left](#17-what-is-left)

---

## 1. Everything is an object

There is one thing that happens in Solum: you send a message to an object. `:`
is the send operator, and `.` ends the statement.

```
#45:print.
```

Not "call a function on a value" — send a message to an object and it answers.
Numbers are objects, classes are objects, blocks are objects. Sends chain left
to right, each one answering the receiver of the next:

```
#10:add(#5):mul(#2):print.       ; #30
```

There is no operator syntax, so `add` and `mul` are ordinary messages with
ordinary names. That is not a stylistic choice you can look past — it is why the
language needs no precedence rules, and why the sections below can keep adding
things without adding syntax.

> **Run:** [examples/hello.sol](../examples/hello.sol)

## 2. Names and binding

`:=` binds a name. One operator, everywhere:

```
greeting := "hi".                ; a global
integer:double := { self:mul(#2) }.   ; a slot on the integer class
```

Those are the same operation. The right-hand side is evaluated, then bound —
and because it is evaluated, a method can be *computed* rather than written out:

```
maker := { { self:mul(#3) } }.
integer:triple := maker:value.
#7:triple:print.                 ; #21
```

That falls out of `:=` meaning one thing. Nothing special was added to allow it.

## 3. Statements, groups, and temporaries

`.` **separates** statements rather than terminating them: required between two,
optional after the last.

```
a := #1
b := #2.
[line 2:1] solas: expected '.' between statements at 'b'
  b := #2.
  ^
```

An error names the line, the column, and points at the offending text.

A line beginning with `:` continues the expression above it, so this is
genuinely one statement and nothing is missing:

```
total := #10
:add(#5).
total:print.                     ; #15
```

Parentheses group an expression, and the group answers its last statement:

```
(#1:add(#2)):mul(#10):print.     ; #30
```

A group or block may open with a **temporary declaration** between pipes. These
are local names, and they belong to the frame the declaration sits in:

```
avg := { | total |
    total := #0.
    [#1, #2, #3]:do({ e | total := total:add(e) }).
    total:div(#3)
}.
avg:value:print.                 ; #2
```

Because a temporary needs a frame to live in, and the top level of a script has
none, declaring one there is refused rather than quietly writing over the
expression stack:

```
#1:add(( | t | t := #5. t )):print.
[line 1:10] solas: a temporary needs a frame, so declare it inside a block at '|'
  #1:add(( | t | t := #5. t )):print.
           ^
```

Inside a block there *is* a frame, so the same shape is fine:

```
f := { ( | t | t := #5. t:add(#1) ) }.
f:value:print.                   ; #6
```

## 4. Numbers

There are two numeric types and **the literal says which**. `#` is a type tag:
`#45` is an integer, a bare `45` is a float.

```
#45:print.                       ; #45
45:print.                        ; 45
```

They never mix on their own. There is no implicit coercion anywhere in the
language, so widening is something you write:

```
#2:add(1.5).
solvm: 'add' expects integer, got float (no implicit coercion)

#7:asFloat:div(#2:asFloat):print.        ; 3.5
```

Integer arithmetic **traps rather than wrapping** — overflow is an error, not a
surprising negative number. Division answers an integer and floors, so the two
differ only on negatives:

```
#7:div(#2):print.                ; #3
#-7:div(#2):print.               ; #-4
#-7:mod(#2):print.               ; #1
```

Floor is chosen for what it does to `mod`: a floored remainder always lands in
`[0, n)` for positive `n`, which is what indexing and cyclic arithmetic want.
Division by zero splits along a line the language already had — integers trap,
having no infinity; floats answer one.

Narrowing names its own direction, because most floats have no integer
counterpart and there is no default worth remembering:

```
2.7:floor:print.                 ; #2
2.7:ceiling:print.               ; #3
2.7:rounded:print.               ; #3
2.7:truncated:print.             ; #2
```

> **Run:** [examples/numbers.sol](../examples/numbers.sol)

## 5. Text: strings and symbols

A string is immutable. Nothing changes one in place, so `concat` answers a new
one:

```
s := "hello".
s:concat(" there"):print.        ; "hello there"
s:print.                         ; "hello"
```

Indices are one-based, `at` answers a one-character string (there is no
character type), and `concat` is strict — joining a string to a number is an
error, not a conversion.

A **symbol** is an interned name, written `'foo`. Two symbols spelling the same
thing are the *same* symbol, so comparing them is comparing addresses rather than
walking characters — which is the whole reason to have them apart from strings:

```
state := 'running.
state:equals('running):print.    ; true
"running":asSymbol:equals(state):print.   ; true
state:asString:print.            ; "running"
state:equals("running"):print.   ; false   -- a symbol is never a string
```

Names are compared far more often than they are read, which is what symbols are
for: reflection takes them, and `perform` and `slotAt` name things with them.

> **Run:** [examples/strings.sol](../examples/strings.sol),
> [examples/symbols.sol](../examples/symbols.sol)

## 6. Values and references

This is the split everything else rests on, and it turns on one question: **can
this thing change?**

**Values** — numbers, strings, symbols, booleans, nil — are immutable. Two of
them are equal when they *say* the same thing:

```
"hello":equals("hel":concat("lo")):print.     ; true
```

**References** — objects, arrays, blocks — can change. Two of them are equal only
when they are *the same one*, and `zs := xs` makes two names for one thing:

```
xs := [#1, #2].
ys := [#1, #2].
xs:equals(ys):print.             ; false   -- same contents, two arrays

zs := xs.
zs:add(#3).
xs:print.                        ; [#1, #2, #3]
```

The split is not arbitrary. **Mutability is what makes identity matter**: if a
thing can change under you, you need to know whether what you are holding is what
changed. If it cannot change, that question has no consequences, so equality can
be about contents instead. It is also what lets numbers ride unboxed — a number
never needs a place on the heap for someone else to point at.

> **Run:** [examples/values.sol](../examples/values.sol)

## 7. Blocks: code as a value

Braces make a block. Writing one runs nothing:

```
b := { #21:add(#21) }.
b:value:print.                   ; #42
```

Parameters come before `|`:

```
add := { a, b | a:add(b) }.
add:value(#3, #4):print.         ; #7
```

A block captures the frame it was written in, lexically, so it still means the
right thing wherever it ends up being run. One restriction is worth knowing
early: a block that *reads its home frame* is tied to that frame, and calling it
after the frame has returned is reported rather than silently reading someone
else's slots. Non-capturing blocks escape freely.

> **Run:** [examples/blocks.sol](../examples/blocks.sol)

## 8. Control flow is message sending

There is no control-flow syntax in the language. None. `ifTrue`, `ifElse`, and
`whileTrue` are ordinary messages that take unevaluated blocks:

```
#5:lessThan(#10):ifElse({ "small" }, { "large" }):display.    ; small

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
i:print.                         ; #5
```

`and` and `or` take a block for the same reason — so the answer can be settled
without running it:

```
x:greaterThan(#0):and({ x:lessThan(#10) }).
```

Booleans are the only thing these accept. There is no truthiness, so a number is
simply an object that does not understand the message:

```
#1:ifTrue({ #2 }).
solvm: integer does not understand 'ifTrue'
```

This is enough to be Turing-complete, and it means you can add control structures
of your own the same way — nothing in the compiler is privileged.

Written literally, all six of those compile to **jumps**: no block allocated, no
frame entered. That is an optimisation and nothing more — the messages are still
there, still reachable through `perform` or with a block held in a variable, and
the compiler falls back to a real send whenever inlining would change what the
program means.

> **Run:** [examples/blocks.sol](../examples/blocks.sol)

## 9. Methods

A method is a **block bound to a slot**, using the same `:=` as everything else:

```
integer:double := { self:mul(#2) }.
#21:double:print.                ; #42
```

A slot holding a block is a method; a slot holding anything else is data,
evaluated once when bound. `self` is the receiver, and it comes from the send
rather than being stored in the block — which is the fact section 14 turns on.

> **Run:** [examples/methods.sol](../examples/methods.sol)

## 10. Objects and prototypes

There is no separate notion of a class. An object is a bag of slots plus a
prototype it delegates to, and `new` answers a fresh object delegating to the
receiver:

```
point := object:new.
point:x := #0.                          ; a default every instance sees
point:sum := { self:x:add(self:y) }.    ; a method
```

Whether a given object is a class or an instance is **how you use it, not what it
is**. Lookup walks the delegation chain and the nearest slot wins, so overriding
works at any depth. Assigning on an instance always makes the instance's own
slot, shadowing the prototype rather than writing through to it — so one instance
cannot change all of them.

> **Run:** [examples/objects.sol](../examples/objects.sol)

## 11. Overriding, and `via`

An override reaches the version it overrides through `self:via(ancestor)`, which
begins the lookup at the ancestor but keeps `self` as the receiver:

```
animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro:display.               ; I am rex!
```

The ancestor is **named rather than inferred**. A `super` keyword would have to
resolve against the object where the running method was *defined*, which is
bookkeeping no frame carries; naming it needs none of that, keeps working however
deep the receiver turns out to be, and cannot accidentally find the method again
and recurse.

`parent` reads the delegation link, read-only:

```
rex:parent:equals(dog):print.    ; true
```

Read-only means what it says, and it has one sharp edge: `o:parent := other`
**succeeds and does not re-parent.** It binds an ordinary slot that shadows the
message, because the delegation link is an internal pointer rather than a slot —
so nothing a program writes can corrupt dispatch. `o:parent` will answer `other`
afterwards while `o` still delegates where it always did.

## 12. Arrays

Arrays hold values and grow. Indices are **one-based** — an index is an ordinal,
not an offset into anything, and there is no pointer arithmetic here for it to be
a displacement from:

```
a := array:of(#10, #20, #30).
a:at(#1):print.                  ; #10

b := array:new.
b:add(#1):add(#2):add(#3).       ; add answers the array, so it chains
```

`[#1, #2, #3]` is sugar for `array:of(#1, #2, #3)` — literally, not merely
equivalently: the two forms produce byte-identical bytecode.

`do`, `collect`, `select`, and `sorted` take blocks:

```
[#1, #2, #3]:collect({ e | e:mul(#2) }):print.        ; [#2, #4, #6]
```

`at(#0)` is out of bounds and therefore caught, which is a small safety win that
falls out of counting from one.

> **Run:** [examples/arrays.sol](../examples/arrays.sol)

## 13. Reflection

Five messages, on every type: `slots`, `slotAt`, `respondsTo`, `isKindOf`, and
`perform`. Names are given as symbols, which is what symbols were wanted for:

```
point:slots:print.               ; ['x, 'y, 'show]
p:respondsTo('show):print.       ; true
p:perform('show):display.        ; (3, 4)
```

Because the built-in classes are just objects whose slots hold primitives,
`integer:slots` lists what an integer understands. Reflection **reads only** —
there is no `slotAtPut`, and the assignment syntax is what writes.

> **Run:** [examples/reflect.sol](../examples/reflect.sol)

## 14. Fetching a method

A method is a block in a slot, so `slotAt` is the only way to hold one as a
value. What comes back is the plain block — and `self` comes from a send rather
than being carried by the block, so a fetched method has no receiver:

```
m := counter:slotAt('bump).
m:value.
solvm: nil does not understand 'n'
```

`boundTo` gives it one, answering a second block over the same code with `self`
set:

```
m:boundTo(a):value:print.        ; #11
m:boundTo(b):value:print.        ; #101
```

Binding and calling stay two things, as `via` keeps them two things — so `value`
means what it always meant and the receiver is never one of the arguments.

> **Read:** [fetched-methods.md](fetched-methods.md) — the long version, including
> what this is actually good for and the two things it deliberately does not do.

## 15. Getting text out

Three messages that look similar and are not:

```
#45:print.                       ; #45     the LITERAL form -- reads back
#45:display.                     ; 45      the TEXT
#45:asString:print.              ; "45"    that text, as a string
```

`asString` takes an optional format spec — `[align] [','] ['0'] [width] ['.'
decimals]`:

```
45.8:asString("6.2"):display.    ;  45.80
#1234567:asString(","):display.  ; 1,234,567
"ab":asString(">6"):print.       ; "    ab"
```

Deliberately smaller than printf: **no conversion letter**, because the receiver
knows its own type and nothing could contradict it.

`fill` fills a template, rendering each value by *sending* it `asString`, so a
type that defines its own is honoured:

```
"you have {} apples and {} pears":fill([#3, #4]):display.
```

And an object is rendered by asking it — define `asString` and `print`,
`display`, `fill`, and array rendering all show it that way, one definition
serving four.

> **Run:** [examples/format.sol](../examples/format.sol)

## 16. Errors and strictness

The language would rather refuse than guess. Integers and floats never coerce,
overflow traps, `concat` will not join a string to a number, an out-of-range
index is an error rather than nil, and a block that answers the wrong type where
a boolean was wanted is told so.

An error reports a message and a stack, innermost first:

```
solvm: integer does not understand 'frobnicate'
  [line 1] in block
  [line 2] in block
  [line 3] in script
```

Assignment inside a block will not quietly create a global, so a typo cannot
bring a new name into being where it would look like a local:

```
solvm: undefined name 'undeclared' -- declare it with '| undeclared |' or assign it at the top level
```

## 17. What is left

The language is Turing-complete and does not leak. What remains is in
[ROADMAP.md](ROADMAP.md), and it is short: stack heights in the verifier, a REPL
that buffers until brackets balance, source positions finer than a line, and one
open design question — whether the class side and the instance side should be
separate objects.

Known restrictions worth carrying with you:

- A capturing block cannot outlive the frame it was written in.
- There is no non-local return; a block answers its last expression.
- Recursion reaches about 62 levels.
- Text is bytes: `size` counts bytes, and `"café":size` is 5.
