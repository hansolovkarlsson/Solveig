# Absence: nil, empty, and unset

*Why there is no `string:nil`, what a name holds before you fill it, and where
nil comes from. Every snippet here has been run; the outputs are what the VM
actually prints.*

For the messages themselves see [REFERENCE.md](REFERENCE.md#nil).

---

## There is one nil, and it has no type

Languages with declared types usually give each type its own emptiness — a
`String` that is `null` is still a `String`. Solum has one nil for everything,
and asking a class for its own is not a thing you can do:

```
> a := string:nil.
solvm: object does not understand 'nil'
> b := integer:nil.
solvm: object does not understand 'nil'
```

The error is exactly right, if a little terse: `string` is an object, `nil` is
not a message it has, and there is nothing further to it than that.

`nil` names **the value**, not a class. Every other built-in type has a class
object bound to a global — `integer`, `float`, `string`, `array`, `symbol`,
`block`, `boolean`, `object` — and nil does not. The class it dispatches to
exists inside the VM, so nil can be sent messages, but nothing names it, so
there is nowhere to send `nil` to in the first place.

## A name has no type either

Even if there were a typed nil, there would be nowhere to put it:

```
mystring := nil.
```

`:=` binds a name to whatever the right-hand side answered. The name does not
remember what you meant it to hold, because it never held a type — only values
have those. `mystring` is not "a string that is currently empty"; it is a name
bound to nil, exactly like a name bound to nil that you meant for an integer.

This is why the type test is on the value rather than the name:

```
"a":isKindOf(string):print.        ; true
mystring:isKindOf(string):print.   ; false
mystring:isKindOf(object):print.   ; true   -- everything is
```

## Absent is not empty

Two different questions, and Solum keeps them apart:

| | |
| --- | --- |
| **absent** — there is no value | `nil` |
| **empty** — there is a value, and it holds nothing | `""`, `#0`, `0.0`, `[]`, `object:new` |

An empty value is a value, and answers everything its type answers:

```
"":size:print.                     ; #0
[]:size:print.                     ; #0
```

Which is what the refusal to make one with `new` is about — the empty string is
not made, it is written:

```
> b := string:new.
solvm: a string is written as a literal, not made with 'new' -- "" is the empty one
```

## nil answers almost nothing, on purpose

`print`, `display`, `asString`, `equals`, `notEquals`, and the five reflection
messages every type carries. That is the whole list.

```
nil:print.                         ; nil
nil:display.                       ; nil
nil:asString:print.                ; "nil"
nil:equals(nil):print.             ; true
nil:respondsTo('print):print.      ; true
```

Anything else is an error where it is asked:

```
> mystring:size.
solvm: nil does not understand 'size'
```

Some languages let nil swallow messages and answer nil again, so a missing value
travels quietly through a program and surfaces somewhere unrelated. Here the
absence is reported at the point that depended on it, which is the same choice
made everywhere else in the language: an out-of-range index is an error rather
than nil, integers and floats never coerce, and a block that answers the wrong
type where a boolean was wanted is told so.

Reflection is the one place nil is turned away by name rather than by not
understanding, since the question only makes sense for objects:

```
> nil:slots.
solvm: 'slots' expects an object, got nil -- only an object has slots of its own
```

## Where nil comes from

It is an ordinary value: you can bind it, put it in an array, and pass it
around.

```
[nil, #1, nil]:print.              ; [nil, #1, nil]
"{}":fill([nil]):display.          ; nil
```

Five places produce one without your writing it:

```
false:ifTrue({ #1 }):print.        ; nil   -- a branch that did not run
{ false }:whileTrue({ #1 }):print. ; nil   -- a loop answers nothing
object:parent:print.               ; nil   -- the chain ends here
{ | t | t }:value:print.           ; nil   -- a temporary before it is assigned
```

The last is the one worth keeping in mind: a declared temporary starts as nil,
so "declare it now, fill it in later" already works and needs no ceremony.

## An unset slot is an error, not nil

A temporary and a slot behave differently, and the difference catches people:

```
> o := object:new.
> o:missing:print.
solvm: object does not understand 'missing'
```

A temporary is a slot in a frame that exists and holds nil. A slot that was
never bound does not exist, so looking it up walks the prototype chain, finds
nothing, and reports the miss — the same as any unknown message, because it *is*
the same thing. There is no separate "field" concept for it to be a nil member
of.

So a prototype with an optional field says so, by binding nil as the default:

```
item := object:new.
item:price := nil.

p := item:new.
p:price:print.                     ; nil
p:price:isNil:print.               ; true
```

That is the same defaulting that any prototype slot does — see
[the tutorial's step 1](TUTORIAL.md#step-1-an-item) — and nil is a perfectly
ordinary thing to default to.

## Asking whether something is there

```
x := nil.
x:isNil:ifElse({ "unset" }, { x }):display.       ; unset

x := "here".
x:isNil:ifElse({ "unset" }, { x }):display.       ; here
```

`isNil` and `notNil` are on **every type**, which they have to be: the point of
asking is that you do not know what the receiver is, so a message only nil
understood could not be sent to find out.

`notNil` is not merely `isNil` with `not` on the end, though it is exactly that
in effect. It is there because the negative is the form that actually gets
written — running out of input is how a loop finishes:

```
line := system:readLine.
{ line:notNil }:whileTrue({ ... }).
```

`x:equals(nil)` says the same thing and did the job before these existed. It
reads as a comparison against a value rather than a question about absence, and
its negative — `x:notEquals(nil)` — is three concepts deep to ask one thing.

Where you want "is it the kind of thing I can use", `isKindOf` asks that
directly, and nil is not a kind of anything but `object`.

**None of these confuse absence with emptiness.** `""`, `#0`, `[]` and `false`
are all values, and every one of them answers `notNil`:

```
"":isNil:print.       ; false
#0:isNil:print.       ; false
[]:isNil:print.       ; false
false:isNil:print.    ; false
```

## Why there is no typed null

It would need somewhere to live. Nothing in the language carries a type but a
value itself, so `string:nil` would have to answer a value that *claims* to be a
string and answers no string message — a thing that passes `isKindOf(string)`
and fails `size`. That is precisely the quiet mistake the language refuses
everywhere else.

And it would buy nothing. Without a checker reading the program before it runs,
a typed null is caught in the same place an untyped one is: at the send that
needed a real value. Solum has no such checker and no declarations for one to
read, so the only difference would be a second spelling of nil per type, and
eight ways to say the same thing.

The version that would be worth something is a static one — a type that a
compiler knows is "string or nothing" and will not let you use until you have
checked. That is a type system, not a value, and it is not on the roadmap.

---

## Nor a `string:new` that means "a string, not filled in yet"

The same wish arrives in better clothes. `string:nil` reads as a null; but

```
a := string:new.
```

reads as a **declaration** — *`a` is a string variable, and it has no value
yet* — which is a genuinely nicer thing to want than a typed null, and closer to
how most languages let you open a variable. `array:new` already answers `[]`,
so the shape is right there waiting to be generalised.

It should not be, and the reasons are worth separating from the ones above.

### The language already has that declaration

Inside a block, `| a |` **is** the declaration, and an unassigned temporary holds
nil:

```
{ | a |
    a:print.                     ; nil
    a:isNil:print.               ; true
}:value.
```

At the top level, where there are no temporaries, `a := nil.` says the same
thing. Both mean exactly *declared, no value yet*, and both leave the question
askable.

### `string:new` would claim a constraint that does not exist

A name holds a value and never a type — the whole of [A name has no type
either](#a-name-has-no-type-either). So nothing follows from having written
`string:new`:

```
b := "".
b := #5.
b := [].                         ; all fine; nothing objects
```

A reader arriving from a language with declarations sees `a := string:new` and
reasonably concludes that `a` is now a string variable. It is not, and nothing
will ever tell them otherwise. A construct that looks like ordinary syntax and
obeys different rules teaches the wrong model — the same objection that sank the
[trailing-block shorthand](ideas.md), and it lands harder here, because that one
would at least still have been a message.

### And it would trade "not filled in" for "filled in with nothing"

This is the cost that bites a running program. `nil` means absent; `""` is a
value that happens to have no characters, and [Absent is not
empty](#absent-is-not-empty) is the distinction the rest of this document is
about. Start a name at `""` and the question stops being answerable:

```
a := nil.                        ; a:isNil is true  -- nobody has filled it in
a := "".                         ; a:isNil is false -- somebody filled it in
```

For a string that is mildly annoying. When the empty string is also a real
answer — `system:readFile` on an empty file, a `split` piece between two
separators — it is the bug you cannot find, because "nobody set this" and
"this is genuinely empty" have become the same value.

### Where `""` is right, and why `array:new` is not the precedent

`""` is the correct thing to write when you mean **an initial value** rather
than a declaration:

```
joined := "".
["a", "b", "c"]:do({ piece | joined := joined:concat(piece) }).
joined:display.                  ; abc
```

There you really do want the empty string to start from, and `string:new` would
read *worse*, because it would suggest a declaration where an accumulator was
meant.

`array:new` is not the counter-example it looks like. It does not answer "the
empty array" the way `""` is the empty string — it answers **a fresh array**:

```
array:new:equals(array:new):print.   ; false -- two arrays
"":equals(""):print.                 ; true  -- one value
```

An array is mutable, so `new` hands you a distinct thing to fill, and two calls
give two of them. A string is a value, so `string:new` would answer the same
`""` every time: a literal spelled longer, not a construction. That difference —
whether there is anything to construct — is also why `symbol`, `block` and
`boolean` [refuse `new`](class-and-instance.md#why-none-of-the-four-wants-a-real-one),
and two of those three have no empty value to answer with at all.
