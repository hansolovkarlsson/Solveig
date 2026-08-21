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
7. [Blocks: code as a value](#7-blocks-code-as-a-value) —
   including [`(group)` and `{block}`](#group-and-block)
8. [Control flow is message sending](#8-control-flow-is-message-sending)
9. [Methods](#9-methods)
10. [Objects and prototypes](#10-objects-and-prototypes)
11. [Overriding, and `via`](#11-overriding-and-via)
12. [Arrays](#12-arrays)
13. [Reflection](#13-reflection)
14. [Fetching a method](#14-fetching-a-method)
15. [Getting text out](#15-getting-text-out)
16. [Errors and strictness](#16-errors-and-strictness)
17. [Splitting a program across files](#17-splitting-a-program-across-files)
18. [The program and its process](#18-the-program-and-its-process)
19. [What is left](#19-what-is-left)

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

> **Run:** [examples/binding.sol](../examples/binding.sol)

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

A temporary needs a frame to live in, and every frame has slots for them — the
top level of a script included, so a group may declare one anywhere:

```
#1:add(( | t | t := #5. t )):print.        ; #6
```

The whole script is **one** frame, though, so two groups in a file share a
namespace and cannot both declare `t`. That is the same rule two groups inside
one block already live by: a group borrows the frame it sits in rather than
making one.

```
f := { ( | t | t := #5. t:add(#1) ) }.
f:value:print.                   ; #6
```

> **Run:** [examples/binding.sol](../examples/binding.sol)

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

Three messages take one apart. `split` answers the pieces between occurrences of
a separator, `indexOf` says where something first appears, and `copyFrom` cuts
out a run:

```
"a,b,c":split(",").              ; ["a", "b", "c"]
"hello":indexOf("ll").           ; #3
"hello":copyFrom(#2, #4).        ; "ell"
```

Two things about them are worth knowing before you rely on them. `split` keeps
every piece, so `"a,,b"` gives three and the last piece of a file ending in a
newline is empty — the pieces always go back together into what you started
with. And `indexOf` answers **nil** when there is no match rather than `#0`,
which is the same "nothing" an unset slot answers:

```
"hello":indexOf("z"):isNil:print.          ; true
```

`copyFrom` includes both ends, so `copyFrom(#i, #i)` is `at(#i)`, and an empty
result is written with the end one before the start.

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

**nil is a value like the rest**, and there is exactly one of it. It carries no
type, so there is no `string:nil` or `integer:nil` — a name holds a value and
never a type, and a name bound to nil does not remember what you meant to put
there. Absence is also not emptiness: `""` and `[]` are values that answer their
type's messages, where nil answers `print`, `display`, `asString`, `equals`,
`notEquals` and the reflection messages, and errors at anything else — so a
missing value is reported where it was needed instead of travelling on.

```
"":size:print.                   ; #0
nil:size.                        ; solvm: nil does not understand 'size'
```

Asking whether something is there is `isNil`, and its negative `notNil`. Both are
on every type, which they have to be — the point of asking is that you do not
know what the receiver is, so a message only nil understood could not be sent to
find out:

```
nil:isNil:print.                 ; true
"":isNil:print.                  ; false -- empty is not absent
```

`notNil` earns its place by being the one that gets written, since running out
of input is how a loop finishes:

```
line := system:readLine.
{ line:notNil }:whileTrue({ ... }).
```

> **Run:** [examples/values.sol](../examples/values.sol)
>
> **Read:** [absence.md](absence.md) — nil against empty against unset, where nil
> comes from, and why there is no typed null.

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

### `(group)` and `{block}`

Both are code in brackets, and they are not variations on each other. **A group
runs. A block is a value.**

```
m := { x | x:add(#1) }.
(m:value(#42)):print.            ; #43     -- the group ran, and answered
{ m:value(#42) }:print.          ; <block> -- nothing ran
{ m:value(#42) }:value:print.    ; #43     -- now it did
```

A group evaluates where it is written, exactly once, and answers its last
statement. Sending to it sends to that answer. A block evaluates nowhere until
something sends it `value` — and then perhaps never, or perhaps a thousand
times.

**That difference is what makes control flow possible at all.** `ifTrue` is an
ordinary message, so its argument is evaluated before the send like any other
argument. Hand it a group and the group has already run by the time `ifTrue`
gets to decide anything:

```
false:ifTrue(("the group ran anyway":display. nil)).
false:ifTrue({ "the block did not":display }).
```

```
the group ran anyway
```

Only the first line printed. There is no rule about `ifTrue` here and nothing in
the compiler knows what it means — the block simply has not been run, and
`ifTrue` chose not to run it. Everything the language does with conditions and
loops rests on that one fact.

The other difference is frames. **A block makes a frame; a group borrows the one
it is in.** So a group's temporaries are the enclosing frame's, and two groups
sharing a frame share one namespace:

```
f := { | a |
    a := #1.
    ( a := a:add(#1). a )        ; the same `a`, not a copy
}.
f:value:print.                   ; #2
```

Both hold statements separated by `.`, both answer their last one, and both may
open with `| temporaries |`. Everything else about them is different.

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

`doUntil` is the seventh, and the one you would otherwise have to write out
yourself: it runs the body *before* the test, so it always runs at least once —
which `whileTrue` cannot do without a flag declared outside the loop.

```
lines := #0.
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
lines:print.                     ; #3
```

Written literally, all seven of those compile to **jumps**: no block allocated,
no frame entered. That is an optimisation and nothing more — the messages are still
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

Because `integer` is an object like any other, that example **added a method to
every integer in the program**. Extending a built-in class needs no special
form; it is the same binding. The reference has the two things worth knowing
before you override a message that already exists.

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

> **Run:** [examples/objects.sol](../examples/objects.sol)

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

`do`, `collect`, `select`, `inject`, and `sorted` take blocks:

```
[#1, #2, #3]:collect({ e | e:mul(#2) }):print.        ; [#2, #4, #6]
```

The four iteration messages differ in what they answer. `do` throws the block's
answers away, `collect` and `select` each answer an array, and `inject` folds
the whole array down to one value:

```
[#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) }):print.   ; #10
```

The block is given what has accumulated so far and one element. An empty array
answers the start without ever calling it, so a fold is safe to write without
asking first whether there is anything to fold. And unlike `do`, `inject` is an
expression — a reduction can stand in the middle of one rather than needing an
accumulator declared at the top of a frame.

`join` puts an array of strings together with a separator between them, and is
the inverse of `split`:

```
["ada", "grace"]:join(", "):print.        ; "ada, grace"
"a,,b":split(","):join(","):print.        ; "a,,b"
```

`at(#0)` is out of bounds and therefore caught, which is a small safety win that
falls out of counting from one.

Taking a piece of one comes in two shapes, and they differ on purpose:

```
[#1, #2, #3, #4, #5]:copyFrom(#2, #4):print.     ; [#2, #3, #4]
[#1, #2, #3]:first(#99):print.                   ; [#1, #2, #3]
```

`copyFrom` names **positions** — both ends included, both one-based, exactly as
a string's does — and a position outside the array is an error, like `at`.
`first` and `last` name a **quantity**, and they clamp: asking a three-element
array for its top five is a question it has answered by handing over three, so a
ranked report does not have to check the size first.

> **Run:** [examples/arrays.sol](../examples/arrays.sol)

### Dictionaries

An array finds things by position. A **dictionary** finds them by key, and it is
the other collection:

```
counts := dictionary:new.
"the fox the dog the":split(" "):do({ word |
    counts:atPut(word, counts:at(word, #0):add(#1))
}).
counts:at("the"):print.          ; #3
```

`at(key)` is an error when the key is not there, like an out-of-range index.
`at(key, default)` is the form above, for a lookup that may legitimately miss —
which saves asking `includes` first.

**Keys are values**: numbers, strings, symbols, booleans, nil. Those are compared
by content, so two keys that look alike are one key. An array or an object is
compared by identity, so two that look alike would be two keys — useless in a
table, so they are refused rather than quietly behaving that way.

`do` walks the values with a one-argument block, exactly as an array's does;
`keysAndValuesDo` takes both. `keys` and `values` answer arrays in **no
particular order**, so sort before showing anything.

There is no literal for one. `[...]` builds an array; a dictionary is built by
sending `new` and filling it.

> **Run:** [examples/dictionaries.sol](../examples/dictionaries.sol) and
> [examples/log.sol](../examples/log.sol), which is what a dictionary is for

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

> **Run:** [examples/reflect.sol](../examples/reflect.sol)
>
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

### Catching one

A failure stops the program unless something catches it, and `onError` is how
something catches it:

```
{ nil:frobnicate }:onError({ e | e:message:display }).
        ; nil does not understand 'frobnicate'
```

It answers the receiver's answer when nothing went wrong and the handler's when
something did, so it is an expression — which is usually what you want:

```
text := { system:readFile(path) }:onError({ e | "" }).
```

A program raises one the same way the machine does, with `error:raise("...")`,
and the error a handler is given is an **object** with a `message` — not the
text itself, because these messages get reworded and matching on them should not
become the habit.

**It catches everything**, including a message you misspelled. That is
deliberate and it is the familiar hazard of a bare catch: a handler around too
much hides mistakes. The way out is that passing one on is a single message,
`error:raise(e:message)`, so a handler that only means to deal with some
failures can hand the rest onward.

`system:exit` is not caught — it is a stop, not a failure.

`ensure` is the other half: it runs its cleanup whether the body finished or
not, and then goes on doing whatever the body was going to do.

```
{ working:value }:ensure({ tidyUp:value }).
```

It answers the body's answer, runs the cleanup on the way out of an exit as well
as a failure, and when both the body and the cleanup fail, the body's failure is
the one that carries on.

> **Run:** [examples/strictness.sol](../examples/strictness.sol), which ends by
> failing on purpose so that a real stack has somewhere to be shown, and
> [examples/errors.sol](../examples/errors.sol) for catching and raising.

## 17. Splitting a program across files

Nothing above a few hundred lines wants to live in one file. One line brings
another file in:

```
@include "library.sol".
```

That file is compiled in at that point, as though its text had been written
there. The `@` is what tells you this is not a message: it happens while
compiling, and by the time the program runs there is nothing left of it. Which
is also why it has to stand alone as a statement — there is nowhere inside an
expression for a file to go.

The file is found beside the file including it, not beside wherever you were
standing when you ran the compiler, so a program can be moved as a piece. And a
file is compiled once however many ways you reach it, so two files may each
include what they need without arranging between themselves who includes what.

There is no module system behind this. Globals are one flat namespace and stay
one, so an included file's names are indistinguishable from the including
file's, and two files binding the same name collide exactly as two `:=` in one
file do. What a library can do instead is claim a single global and hang the
rest off it, an object being a namespace already:

```
temperature := object:new.
temperature:cToF := { c | c:mul(1.8):add(32.0) }.
```

[examples/library.sol](../examples/library.sol) and
[examples/include.sol](../examples/include.sol) are the pair, and
[REFERENCE.md](REFERENCE.md#splitting-a-program-across-files) has the rules
exactly.

### The library that ships with it

A name not found beside the file including it is looked for on a **search
path** — `-I` arguments, then `SOLUM_PATH`, then the library that ships beside
the binary. So a program asks for what it wants without saying where that
lives:

```
@include "control.sol".

#3:repeat({ "tick":display }).
#1:toByDo(#10, #3, { n | n:display }).       ; 1 4 7 10
#4:timesCollect({ n | n:mul(n) }):print.     ; [#1, #4, #9, #16]
```

`lib/control.sol` gives you `timesCollect`, and it used to give you four more. **None of it is language.** They are methods bound on `integer`
and `block` by an ordinary Solum file — which is possible at all because control
flow here is message sending, so a loop is something a library can add. That is
why §8 could say the language has no loop syntax and mean it.

`repeat`, `toDo`, `toByDo` and `doUntil` were all in that list once and are all
part of the language now, because measuring said they were worth building in.
`doUntil` is the interesting one — it is the shape `whileTrue` cannot express, the body
running *before* the test so it always runs at least once:

```
lines := #0.
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
```

Written like that it compiles to jumps, which makes it **faster than writing the
loop out by hand**: doing it yourself needs a `done` flag outside the loop, and
that flag costs two sends an iteration the jumps do not need.

Beside-first means a local file of the same name **shadows** the library one,
which is usually what you want. It also means a file that includes a library
file of its own name finds itself, and — a file being compiled once — that
include quietly does nothing.

> **Run:** [examples/loops.sol](../examples/loops.sol)

## 18. The program and its process

Everything so far has been about values. `system` is the one global that is not
a value and not a class: one object, holding what belongs to the program rather
than to anything inside it.

```
system:arguments:size:print.            ; how many arguments it was given
system:clock:isKindOf(float):print.     ; true -- monotonic seconds
system:exit(#0).                        ; stop, and say it went well
```

**`exit` is a message**, so it is neither a keyword nor a statement, and it
unwinds rather than leaving from under the machine: everything already printed
is flushed, and nothing after it runs — including the rest of a loop it was
called inside. A status is `#0` to `#255`, and anything else is an error rather
than a number quietly adjusted to fit, since POSIX would keep only the low eight
bits and `#256` would leave looking like success.

**`arguments` is a slot rather than a method**, because it is data: the same
array of strings every time you ask, and the empty array rather than nil when
there were none, so it can be walked without first asking whether it is there.

**`readLine` answers one line of standard input**, without its terminator, or
nil when there is no more. Nil is the end and `""` is an empty line, so a loop
that reads to the end can be written the obvious way:

```
line := system:readLine.
{ line:notEquals(nil) }:whileTrue({ line:display. line := system:readLine }).
```

**Files are whole files**: `system:readFile(path)` answers one as a string, and
`system:writeFile(path, text)` replaces it. A missing file is an error rather
than nil — the same answer an out-of-range index gets — and
`system:fileExists(path)` is how to ask first. They are on `system` rather than
on the string naming the file, because a string knows nothing about files.

Reading a file needs its path, and `system:filesIn(path)` is how a program finds
one out rather than being told:

```
system:filesIn("examples"):sorted:do({ name |
    system:isDirectory("examples/":concat(name)):ifFalse({ name:display }) }).
```

It answers **names**, directories included, in no order worth relying on — so
join, sort, and use `isDirectory` to tell them apart. `system:appendFile` adds
to a file rather than replacing it, `system:fileSize` measures one without
reading it, and `system:environment(name)` answers a variable or nil.

`system:makeDirectory`, `system:rename` and `system:remove` change what is
there, and cannot be undone. `remove` takes a file or an **empty** directory —
there is no recursive form, deleting a tree not being something to make one
message wide. Every refusal names the reason the system gave.

A `.sol` file can also be run directly: put `#!/usr/bin/env solis` on the first
line, `chmod +x` it, and `./script.sol` works like any other script.

**`clock` is monotonic**, which is why its epoch is unspecified — the only
useful thing to do with two readings is subtract them:

```
start := system:clock.
i := #0. { i:lessThan(#100000) }:whileTrue({ i := i:add(#1) }).
system:clock:sub(start):asString("0.4"):display.     ; 0.0153
```

**`system:time` is a different thing from `system:clock`**, and the difference
is the point. `clock` is a stopwatch: monotonic, unspecified epoch, only
differences meaningful. `time` is a calendar — an instant you can ask the year
of, and show:

```
now := system:time.
now:print.                                   ; 2026-08-21T16:57:41Z
now:year:print.                              ; #2026
now:asString("%Y-%m-%d"):display.            ; 2026-08-21
system:modifiedAt("notes.txt"):asString("%H:%M"):display.
```

A time is a **value**, like a number: two of the same instant are equal, nothing
mutates one, and it can be a dictionary key. Everything is **UTC** — there is no
local time and no zone, a zone being a political fact that changes where an
instant does not. `secondsSince` measures a gap and `plusSeconds` moves along
one, both in floats as `clock` differences are.

A program asking how long something took wants `clock`; one asking when
something happened wants `time`.

`{ ... }:timeToRun` does that without the bookkeeping, answering the seconds the
block took. The thing to know before trusting a number from it is that **the
clock has a floor** — a microsecond here — and most single operations in Solum
are well under it. So a single run measures the floor rather than the block, and
a count is how anything smaller gets measured:

```
{ #1:add(#1) }:timeToRun:print.                  ; 0, or 0.000001 -- the floor

total := { #1:add(#1) }:timeToRun(#200000).      ; the total for all of them
total:div(200000.0):asString(".9"):display.      ; 0.000000088 -- or thereabouts
```

> **Run:** [examples/system.sol](../examples/system.sol),
> [examples/reading.sol](../examples/reading.sol) and
> [examples/files.sol](../examples/files.sol)

## 19. What is left

The language is Turing-complete and does not leak. What remains is in
[ROADMAP.md](ROADMAP.md), and it is no longer about the language: a program can
now be split across files, stop with a status, read its input, read and write
files, take a string apart and put it back together, and time itself. One design
question is still open — whether the class side and the instance side should be
separate objects.

Known restrictions worth carrying with you:

- A capturing block cannot outlive the frame it was written in.
- There is no non-local return; a block answers its last expression.
- Recursion reaches about 62 levels.
- Text is bytes: `size` counts bytes, and `"café":size` is 5.
