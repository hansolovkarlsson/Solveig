# The class side and the instance side

*What roadmap 2.5 was about, why it was only a problem for the built-in classes,
why the answer was not metaclasses, and what the class side should contain at
all. Includes the single root, which this was long believed to gate and did not.
Every snippet here has been run; the outputs are what the VM actually prints.*

**This question is closed** — see
[COMPLETED](COMPLETED.md#25-class-side-versus-instance-side--closed) for the
verdict, and [below](#how-it-was-settled) for what settled it. The document is
kept because the reasoning is what makes the answer make sense, and because the
two sides still share one object: what changed is that the line between them is
now drawn and checked.

---

## A class is an object, and its slots are messages

There is no `class` keyword. `integer` is an ordinary object, and the messages
an integer understands are its slots. That is the whole model, and it is why the
language needed no separate notion of a class.

But look at what is actually in those slots:

```
integer:slots:size:print.        ; #24
```

Those 24 slots serve **two different audiences**:

| slot | sent as | who it is for |
| --- | --- | --- |
| `add`, `mul`, `print`, `asString` | `#45:add(#1)` | the **instance side** — what an integer understands |
| `new` | `integer:new` | the **class side** — what the class itself understands (it refuses, but it is still a slot on this side) |

One bag of slots, two roles, and nothing in the object distinguishes them.

## What that costs

### An instance answers a class-side message

```
#45:new(#1):print.               ; #1
[#1]:of(#1, #2):print.           ; [#1, #2]
```

`#45:new(#1)` is nonsense, and it works. Lookup for `#45` starts at `integer`,
and `new` is sitting there beside `add`.

### It used to be a crash going the other way

```
array:add(#1).      ; was: abort
array:size.         ; was: #0, read from whatever `array` is not
```

`array` is an object whose slots are the messages an *array* understands, so it
answers them itself — and `prim_array_add` then read the class object as an
array. That was roadmap 1.6, and it fell out of exactly this: one object, two
roles, and no way for a primitive to tell which one a send meant.

### Reflection has to say two different things

`slots` reports what is there; `respondsTo` asks the dispatch question. Since
1.6 those have different answers, and both are correct:

```
integer:respondsTo('add):print.  ; false  -- sending it would be refused
integer:respondsTo('new):print.  ; true
```

`integer:slots` still lists `add`, because the slot is genuinely there.

### The class side is populated wherever someone needed it

| | `new` | `of` |
| --- | --- | --- |
| `integer`, `float` | yes — refuses, and says what to write | — |
| `array` | yes — allocates | yes |
| `object` | yes — allocates and delegates | — |
| `string`, `symbol`, `block`, `boolean` | yes — refuses, and says what to write | — |

This document used to say there was no rule saying which classes should have a
class side, because **there is nowhere for a rule to live** — the class side not
being a place, only some slots that happen to sit beside the instance ones,
which is how one name came to mean four different things.

The second half of that is still true and the first half is not. A rule was
available the whole time: **`new` belongs where something is constructed, which
is where the instances are mutable.** An array and an object are references, so
`new` hands back a fresh, distinct one — `array:new:equals(array:new)` is false.
A string, a symbol, a boolean and a number are values, so there is no fresh
distinct one to hand back; `"":equals("")` is true, and a `string:new` could only
answer a literal spelled longer.

That rule sorts all nine classes correctly, and it agrees with the four
refusals. It also puts `integer:new` and `float:new` on the wrong side of its own
line, which [the question underneath](#the-question-underneath--answered-and-acted-on) reaches by a
different route.

What it does not do is give the rule somewhere to *live*. It is a rule about
this document rather than one the language enforces, and only the split would
change that.

The last row is recent, and it is the single root's doing rather than anyone
deciding those four wanted a `new`: once every built-in delegates to `object`
they would otherwise have inherited one, so they shadow it to refuse. See
[below](#the-one-thing-that-was-in-the-way).

---

## It is only a problem for the built-ins

This is the reframing that decides what the answer should be.

A user-defined object has no two sides at all:

```
point := object:new.
point:make := { ... }.           ; would be "class-side"
point:sum  := { ... }.           ; would be "instance-side"
p := point:new.                  ; p delegates to point, and sees both
```

That is coherent. It is prototypes doing what prototypes do, and `p:make`
working is the model being consistent rather than a bug.

The built-ins are the anomaly, and one line in `sol_vm_class_of` says why:

```c
case SOL_INT:   return vm->integer_class;      /* forced: one object */
case SOL_OBJ:   return SOL_AS_OBJ(value);      /* the object answers for itself */
```

An unboxed `#45` has no object of its own, so dispatch has to be given one — and
the only candidate is the same object the global `integer` names. **The two roles
are welded together by that line**, not by the object model.

### And a built-in cannot be subclassed, even deliberately

The natural next thought is that this is all a missing constructor: if
`integer:new` answered *an object delegating to `integer`* the way `object:new`
answers one delegating to its receiver, you would have a subclass of integer and
could add to it. For user-defined objects that is exactly how it works —
`point:new` and `tip := point:new` are the same operation, and whether one is an
instance or a subclass is how you use it.

It does not carry over, and the reason is worth seeing rather than arguing
about. Built as an experiment — `integer:new` with no argument answering
`sol_object_new(vm, vm->integer_class)`, on a throwaway copy of the tree — it
looks right at first:

```
a := integer:new.
a:isKindOf(integer):print.       ; true
a:tag := #7.
a:tag:print.                     ; #7     -- a real object, slots and all
```

and then:

```
a:add(#1).       solvm: 'add' expects an integer, got object
a:print.         solvm: 'print' expects an integer, got object

a:double := { self:mul(#2) }.
a:double.        solvm: 'mul' expects an integer, got object
```

**It inherits every method name and can run none of them.** The last line is the
one that settles it: a method *you* wrote fails too, the moment it touches
anything inherited.

`integer`'s methods are not Solum code. They are C primitives that do
`SOL_AS_INT(self)` and read an 8-byte payload, and an object does not have one.
So a built-in class hands down an **interface and no implementation** — which is
the same inert object `string:new` would have produced, and the reason those
four refuse rather than inherit.

Two independent things stop it, and either would be enough: an unboxed value
carries no class pointer, so there is nowhere to record a different class; and
the inherited methods require the exact value representation. Neither is fixed
by anything in this document — a behaviour object per built-in would not help,
because `#45` would still dispatch by type tag.

So there are two ways to give integers behaviour, and no third:

- **Extend `integer`** if it belongs to all integers.
  `integer:double := { self:mul(#2) }`.
- **Wrap one in an object** if you want a distinct type, and forward what you
  need. That object subclasses properly, because it is an object.

## Probably not metaclasses

The roadmap says this "needs a metaclass level". That is the Smalltalk answer,
and it is worth being sceptical of here.

Metaclasses answer *where do class-side methods live* for languages that have a
class/instance distinction built in. Solum does not: [design.md](design.md) says
plainly that whether an object is a class or an instance is **how it is used,
not what it is**. A metaclass tower would import a class-based concept to fix a
problem only the built-ins have. Smalltalk's loop-closing — `Metaclass class
class = Metaclass` — buys uniformity for a reflective browser this language does
not have and may never want.

## A smaller answer: a behaviour object

One extra plain object per built-in. No new concept, no tower.

```
integer             (the global)     slots: new
integer-behaviour   (internal)       slots: add, mul, print, asString, ...
```

and one changed line:

```c
case SOL_INT:   return vm->integer_behaviour;
```

What falls out:

| | today | after |
| --- | --- | --- |
| `#45:new(#1)` | answers `#1` | `integer does not understand 'new'` — it was never in the object `#45` dispatches to |
| `array:add(#1)` | needs 1.6's receiver check to refuse it | refuses structurally; `add` is not there to find |
| `integer:slots` | 24 slots, both sides mixed | the class side; the instance side is a separate object to ask |
| `slots` vs `respondsTo` | disagree | agree again |

**1.6's per-message receiver requirement becomes mostly redundant.** It exists
because a class object can reach an instance primitive, and afterwards it
cannot. Worth keeping as a cheap floor — the same argument as the send's stack
check, which the verifier also made redundant and which stayed — but it would
stop being load-bearing.

## The single root — done, and it was not gated by this

This section used to say the built-in classes deliberately do not delegate to
`object`, because `float` inheriting object's `new` would answer a plain object
rather than a float, and that a single root therefore waited on the split.

**That stopped being true and nobody noticed.** Two earlier commits removed it:

- `7ac6be6` gave `float` its own `new`; `integer` and `array` have theirs. Those
  three shadow object's rather than inherit it.
- `1.6` gave every primitive a receiver requirement. The only two messages
  `integer` does not already define — `via` and `parent` — are installed as
  `instance(vm->object_class, SOL_OBJ, ...)` and are refused for any receiver
  that is not an object.

So what `integer` would inherit was exactly two messages, and both were already
refused. It was tried on a throwaway copy, the whole suite passed untouched, and
it is now committed:

```
#45:isKindOf(object):print.            ; true
"s":isKindOf(object):print.            ; true
nil:isKindOf(object):print.            ; true
integer:parent:equals(object):print.   ; true
object:parent:print.                   ; nil   -- the chain ends here
```

Nothing leaked onto the values. `#45:parent` and `#45:via(...)` are refused by
the receiver check, three commits before anyone thought about a root.

What the root means for writing programs — one definition on `object` answered by
every value, and the line between inheriting behaviour and being an object — is
[one-hierarchy.md](one-hierarchy.md). This section is the decision; that page is
the consequence.

The cost is on the **miss** path only, and only because a miss now walks
object's thirteen slots before failing: a send that hits is unchanged, and
200,000 failed lookups cost about 10% more. That is the path that ends in *does
not understand*.

### The one thing that was in the way

`string`, `symbol`, `block` and `boolean` have no `new` of their own, so they
*would* have inherited object's — which answers a fresh object delegating to the
receiver. For `string` that is an object delegating to the `string` class
object, refusing every message a string understands. Inert rather than wrong,
and no use to anybody.

They shadow it now, and refuse:

```
string:new.
solvm: a string is written as a literal, not made with 'new' -- "" is the empty one

symbol:new.
solvm: a symbol is written 'name, or made from a string with asSymbol -- not with 'new'

block:new.
solvm: a block is written { ... } and compiled -- there is nothing for 'new' to make

boolean:new.
solvm: there are only two booleans, true and false -- 'new' makes neither
```

The rule underneath is worth stating once: **`new` means "make an object
delegating to me", and these four have instances that are not objects delegating
to them.** That asymmetry is inherent to unboxing rather than a wart, so the
right answer was to say so where each class is defined, and leave `object:new`
general.

The error is the only thing such a class has to offer here, so it teaches.

## The wrinkle to design carefully

`#45:isKindOf(integer)` must stay true, and after the split `#45`'s lookup
object is no longer the one `integer` names. The class object needs a link to
its behaviour object, with `isKindOf` and reflection following it. That is the
whole cost, and it is where the thinking time would go — not on the dispatch
change, which is one line.

A second question falls out of it: should the behaviour object be reachable from
the language? `integer:behaviour` would make reflection honest about the split.
Hiding it would keep the surface smaller and make `integer:slots` quietly
incomplete.

## How it was settled

Not by splitting the objects. **The line between the two sides is drawn by the
receiver each slot requires**, which 1.6 had already built for a different
reason — to stop `array:add(#1)` running against a class object — and which
turned out to be the whole mechanism the split was wanted for.

Three messages were on the wrong side of it. `new`, `slots` and `slotAt` were
registered for *any* receiver and then refused a value from inside the
primitive, so `respondsTo` said one thing and sending did another:

```
#45:respondsTo('new).       ; true
#45:new.                    ; an integer is written #45, and there is nothing for 'new' to make
```

The same gap let an instance answer a class-side message — `[#1]:new` handed
back a fresh empty array, and `[#1]:of(#2, #3)` a fresh one holding them.

Every class-side message requires an object receiver now: `new`, `of`,
`fromSeconds`, `slots`, `slotAt`. Ten registrations. `respondsTo` agrees with
sending everywhere, an instance cannot answer for its class, and the teaching
errors survive because they were always for the class:

```
integer:new.
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one
```

**The rule this document said had nowhere to live now lives in the registration
table**, where it is checked on every send: a slot that takes `SOL_OBJ` is class
side, a slot that takes a value type is instance side. And the two are separable
from inside the language, with nothing on neither side:

```
integer:slots:size.                                            ; #30
integer:slots:select({ s | integer:respondsTo(s) }):size.      ; #8
integer:slots:select({ s | #45:respondsTo(s) }):size.          ; #27
```

The five that overlap are `isKindOf`, `isNil`, `notNil`, `perform` and
`respondsTo` — reflection that serves both audiences, which is right rather than
sloppy.

## What the split would still buy



**One thing, and it is not worth a second object per built-in.**
`integer:slots` answers 30, listing both audiences. That is honest — they *are*
its own slots — and it is now explicable in one sentence, with a filter to show
it. The split would make it 8 by moving 22 somewhere else, at the cost of a
class-to-behaviour link that `isKindOf` and all four reflection messages would
have to keep honest.

The other two things it was for are gone: `#45:new(#1)` is refused, and the rule
about the class side has somewhere to live.

**The trigger to reopen this**: when `slots` on a built-in class is *read by a
program* rather than printed by an example. Across four programs written to do a
job and four libraries, reflection on a built-in class appears exactly once —
`integer:slots:size:print` in `examples/reflect.sol`, printing a count. Until
something reads that list and has to care which audience it is looking at, the
filter is enough.

**The single root was a separate decision, and it is already made** — see
[above](#the-single-root--done-and-it-was-not-gated-by-this). This paragraph
used to say the work was "eight lines and the answer to what `new` should do on
the four classes"; both were done, and the sentence outlived them. Nothing here
is waiting on that any more.

---

## What should the class side contain?

The same question, one level down, and separable from everything above: given
that there is a class side, what belongs on it?

`string`, `symbol`, `block` and `boolean` have none at all. Should they be given
one — and what would `new` even mean for a string, a symbol, a block, or a
boolean?

The answer is no for all four, and the reason is that `new` is already three
different operations sharing a spelling.

### `new` used to mean three things

```c
integer:new(#45)  ->  return args[0];                  /* identity, type-checked */
array:new         ->  sol_array_new(vm, 0)             /* allocates              */
object:new        ->  a fresh object delegating to self /* allocates and delegates */
```

The comment in `builtins.c` said the first one outright: *"Integers are immutable
values, so there is nothing to allocate — `integer:new(#45)` is the long form of
the literal `#45`."*

It was not even a uniform protocol, because the arities disagreed:

```
integer:new.        ; solvm: 'new' takes 1 argument, got 0
array:new(#1).      ; solvm: 'new' takes 0 arguments, got 1
```

So no generic code could send `new` without already knowing which class it was
talking to — which is the only thing a shared name would have bought.

**The first line is gone as of `d58918c`**, and the section below is what argued
for that. `new` now means one thing, *make me a new one*, and lives on the two
classes where something is made.

The arities agree now too, which was the other half of the complaint: every
class that constructs takes **no argument**, `object:new` and `array:new` and
every user-defined `point:new` alike. So generic code handed a constructing class
can send `new` without knowing which one it has. It still cannot send it blind to
*any* class, since six refuse — but a refusal that says what to write is a better
answer than one that hands back its own argument.

### Why none of the four wants a real one

They have a `new` now, but it refuses — and this is why nothing was built to
succeed instead:

- **`string`** would get the `integer` flavour: `string:new("hi")` answering
  `"hi"`, a no-op with a type check. A string is immutable, so unlike an array
  there is nothing to allocate and then fill, and `""` already is the empty
  string.
- **`symbol`**: `symbol:new("foo")` is `"foo":asSymbol`, which exists and reads
  better because it names the direction of the conversion. Adding `new` would
  give one operation two spellings.
- **`block`** has no possible meaning. A block's code comes from the compiler;
  there is nothing to construct at run time. This one is not a judgement call.
- **`boolean`** has exactly two values, both of them globals. `boolean:new(true)`
  is identity with extra steps.

Which is the argument for the refusal being the *right* implementation rather
than a placeholder: there is nothing better for these to do, and saying so is
worth more than answering something that is technically a value.

**There is a second motivation for wanting these, which the above does not
touch.** `a := string:new` reads as a *declaration* — `a` is a string variable,
not filled in yet — rather than as a construction, and that is a nicer thing to
want than any of the four flavours above. It is answered in
[absence.md](absence.md#nor-a-stringnew-that-means-a-string-not-filled-in-yet):
the language already has that declaration in `| a |` and `a := nil`, both of
which leave `isNil` able to answer, where starting a name at `""` trades "not
filled in" for "filled in with nothing".

That section also says why `array:new` is not the precedent it appears to be. It
answers a *fresh* array rather than the empty one — `array:new:equals(array:new)`
is false where `"":equals("")` is true — so the line between the classes that
construct and the classes that do not is **mutability**, not emptiness. That is
the rule this document says has nowhere to live, and it sorts all nine classes
correctly.

### The question underneath — **answered, and acted on**

The interesting question was not whether the four should gain `new`. It was
whether the two identity ones should have it. They should not, and as of
`d58918c` they do not.

`integer:new` and `float:new` allocate nothing and construct nothing. They are
the literal, spelled longer — and `float:new` was added in `7ac6be6` *for
symmetry with `integer:new`*, which is symmetry with something that does not do
anything.

They are also a **vestige of a design that was abandoned**. The original sketch
in [design.md](design.md#original-notes) reads:

```
        integer:new(a)  ; sends message "integer" to top Object to create an integer object
        a:set(#45)      ; assigns integer value #45 to integer object
```

That is a mutable integer object you construct and then fill. Numbers became
immutable unboxed values instead, `set` never existed, and `new` survived the
change with nothing left to do. It has been the identity function ever since,
because that is all that was left once the thing it constructed stopped being a
thing you construct.

And it is what makes one of the symptoms above possible: `#45:new(#1)` answers
because there is a `new` on `integer` at all.

**So the tidier direction was the opposite of the question**: leave the four
alone, and take `new` off `integer` and `float` — leaving it meaning one thing,
*make me a new one*, on the classes where something is actually made -- which
was `object` and `array`, and is `object`, `array` and `dictionary` now that
there is one more mutable thing to construct.

**They could not simply lose it.** Deleting the registration was tried, and
`integer:new` then inherited object's and answered *an object delegating to
`integer`*, which fails `print`. Worse than the identity function it replaced,
and the same trap that made the other four shadow rather than inherit. So the
two joined the refusers:

```
integer:new(#45).
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one
```

`#45:new(#1)` refuses along with it, which removes the first of the three
symptoms at the top of this document. The other two are untouched: `integer:slots`
still lists `new` beside `add`, because the slot is still there — it holds a
refusal rather than a constructor, and `slots` reports what is there.

Two things weighed against doing it. It is a breaking change to a documented
message, and [examples/hello.sol](../examples/hello.sol) used it deliberately —
*"integer:new is the explicit long form of the literal"* — as the closing of the
loop from the original notes. Both were paid: the example now closes that loop
better, by showing that the notes' `integer:new(a)` and `a:set(#45)` **both**
went, and why. Four tests changed.

The alternative, had they stayed, was to admit that `new` on a value class is a
**checked assertion** rather than a constructor and name it for that. Refusing
says the same thing in less space.

---

## Summary

- `integer` is one object holding both what an integer understands and what the
  class understands.
- Only the built-ins have this problem; user-defined objects have one side and
  delegation, which is coherent.
- A built-in cannot be subclassed even deliberately: a class made of C
  primitives hands down an interface and no implementation, so the object you
  get inherits every method name and can run none of them.
- It is welded by `sol_vm_class_of` having to hand an unboxed value some object
  to dispatch to.
- There **is** a rule for which classes should construct — `new` belongs where
  the instances are mutable, so there is a fresh distinct one to hand back. This
  document used to say no rule was available, and then that it had nowhere to
  live; it lives in the receiver each slot requires.
- `a := string:new` as a *declaration* rather than a construction is a separate
  wish, and a more reasonable one. It is answered in
  [absence.md](absence.md#nor-a-stringnew-that-means-a-string-not-filled-in-yet):
  `| a |` and `a := nil` already say it, and say it without trading "not filled
  in" for "filled in with nothing".
- 1.6 made it safe, one message at a time, without separating anything.
- Metaclasses are the Smalltalk answer to a question this language does not ask.
- A behaviour object per built-in is smaller than a metaclass level.
- The single root was **not** blocked by the split, which this document used to
  claim. It is done: every built-in class delegates to `object`, and the four
  classes that cannot construct their instances refuse `new` and say what to
  write instead.
- **The question is closed, and the split was not built.** Every class-side
  message requires an object receiver, so the line between the two sides is
  drawn by what each slot accepts and checked on every send. `respondsTo` agrees
  with sending, an instance cannot answer for its class, and the rule about the
  class side lives in the registration table.
- Separately: `new` *was* three operations sharing a name, and on `integer` and
  `float` it was the identity function left over from a design that was
  abandoned. Those two now refuse like the other four, so `new` means one thing
  and lives on `object` and `array`. `#45:new(#1)` refuses with them.
