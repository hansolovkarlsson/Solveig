# The class side and the instance side

*What roadmap [2.5](ROADMAP.md) is about, why it is only a problem for the
built-in classes, why the answer is probably not metaclasses, when it would be
worth doing — and, at the end, what the class side should contain at all. Every
snippet here has been run; the outputs are what the VM actually prints.*

This is the one design question still open. Nothing in it blocks a working
program today — it is recorded because the decision has a consequence that does
block something, and that consequence is easy to miss.

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
| `new` | `integer:new(#1)` | the **class side** — what the class itself understands |

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
| `integer`, `float` | yes | — |
| `array` | yes | yes |
| `object` | yes | — |
| `string`, `symbol`, `block`, `boolean` | — | — |

There is no rule saying which classes should have a class side, because **there
is nowhere for a rule to live**. The class side is not a place; it is some slots
that happen to sit beside the instance ones.

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

## The single root, which this was supposed to gate

The built-in classes deliberately do not delegate to `object`, because `float`
inheriting `object`'s `new` would answer a plain object rather than a float. So
there are two hierarchies that never meet:

```
integer:isKindOf(object):print.  ; false
#45:isKindOf(object):print.      ; false

p := object:new.
p:isKindOf(object):print.        ; true
```

`integer:parent` is not even a message the built-in classes answer:

```
integer:parent.
solvm: object does not understand 'parent'
```

### But the obstacle has mostly dissolved underneath that

The paragraph above is what this entry has said since it was written, and it is
now largely out of date. Two things happened to it.

`7ac6be6` gave `float` its own `new`, and `integer` and `array` have theirs, so
those three would **shadow** `object`'s rather than inherit it. And `1.6` gave
every primitive a receiver requirement, so what a built-in *would* inherit is
refused before it runs.

Measured rather than reasoned about. What `integer` would inherit from `object`
is exactly two messages — everything else it already defines itself:

```
['via, 'parent]
```

Both are installed as `instance(vm->object_class, SOL_OBJ, ...)`, so both are
refused for a receiver that is not an object.

**So it was tried.** Eight lines in `sol_builtins_install`, setting every
built-in class's `proto` to `object`, on a throwaway copy of the tree — not
committed, and not proposed here as a change. The **whole test suite passes
untouched**, and:

| | today | with the root |
| --- | --- | --- |
| `integer:isKindOf(object)` | false | **true** |
| `#45:isKindOf(object)` | false | **true** |
| `"s"`, `[#1]`, `true` `:isKindOf(object)` | false | **true** |
| `integer:parent` | `object does not understand 'parent'` | **`object`** |
| `#45:parent` | — | `'parent' expects an object, got integer` |
| `#45:via(integer)` | — | `'via' expects an object, got integer` |
| `#45:add(#1)` | `#46` | `#46` |

Nothing leaked onto the values. The last two rows are 1.6's receiver check doing
exactly the job it was built for, three commits before anyone thought about a
single root.

### What is actually left in the way

One message, on the four classes that have no `new` of their own:

```
string:respondsTo('new):print.   ; becomes true
string:new:print.
solvm: 'print' expects a string, got object
```

`string`, `symbol`, `block` and `boolean` would inherit `object:new`, which
answers a fresh object delegating to the receiver. For `string` that is an
object delegating to the `string` class object — **inert rather than wrong**: it
errors on every message a string understands, because the receiver check refuses
each one. Bad, but bad in the way a clear error is bad, not in the way a silent
half-value is.

So the decision is not "how do we build a metaclass level". It is **what should
`new` do on a class that cannot construct anything** — refuse explicitly, or not
be inherited at all. That is the same question the closing section of this
document asks from the other end.

Which means the single root and the class-side split are **less coupled than
this entry has been claiming**. The root looks like eight lines and one decision
about `new`; the split is worth doing on its own merits, and mostly for what it
does to `slots` and to `#45:new(#1)`.

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

## When to do it

**Not yet, and the case for it is weaker than it was.** The split was worth
doing largely because it gated the single root, and the measurement above says
it does not. What is left for it to fix is real but small:

- `#45:new(#1)` answers, which is nonsense nobody writes.
- `integer:slots` mixes the two sides, and lists a slot `respondsTo` will not
  answer.
- There is nowhere for a rule about the class side to live, which is why four
  classes have none and nobody noticed.

None of those bites a working program. So doing the split now would be
refactoring toward tidiness — worth it when reflection starts being used in
earnest and `slots` reporting two audiences at once becomes a thing to explain
rather than a thing to shrug at.

**The single root is a separate decision, and a smaller one.** If it is wanted,
the work is the eight lines and the answer to what `new` should do on the four
classes that cannot construct anything. It does not wait on this.

---

## What should the class side contain?

The same question, one level down, and separable from everything above: given
that there is a class side, what belongs on it?

`string`, `symbol`, `block` and `boolean` have none at all. Should they be given
one — and what would `new` even mean for a string, a symbol, a block, or a
boolean?

The answer is no for all four, and the reason is that `new` is already three
different operations sharing a spelling.

### `new` means three things

```c
integer:new(#45)  ->  return args[0];                  /* identity, type-checked */
array:new         ->  sol_array_new(vm, 0)             /* allocates              */
object:new        ->  a fresh object delegating to self /* allocates and delegates */
```

The comment in `builtins.c` says the first one outright: *"Integers are immutable
values, so there is nothing to allocate — `integer:new(#45)` is the long form of
the literal `#45`."*

It is not even a uniform protocol, because the arities disagree:

```
integer:new.        ; solvm: 'new' takes 1 argument, got 0
array:new(#1).      ; solvm: 'new' takes 0 arguments, got 1
```

So no generic code can send `new` without already knowing which class it is
talking to — which is the only thing a shared name would have bought.

### Why none of the four wants one

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

### The question underneath

The interesting question is not whether the four should gain `new`. It is
whether the two identity ones should have it.

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

**So the tidier direction is the opposite of the question**: leave the four
alone, and consider whether `integer:new` and `float:new` should go — leaving
`new` meaning one thing, *make me a new one*, on the two classes where something
is actually made.

Two things weigh against doing that. It is a breaking change to a documented
message, and [examples/hello.sol](../examples/hello.sol) uses it deliberately —
*"integer:new is the explicit long form of the literal"* — as the closing of the
loop from the original notes. It also costs nothing to keep.

If they stay, the honest framing is that `new` on a value class is a **checked
assertion** rather than a constructor, and it should be named for that. Either
way, `string`, `symbol`, `block` and `boolean` should not get one.

---

## Summary

- `integer` is one object holding both what an integer understands and what the
  class understands.
- Only the built-ins have this problem; user-defined objects have one side and
  delegation, which is coherent.
- It is welded by `sol_vm_class_of` having to hand an unboxed value some object
  to dispatch to.
- 1.6 made it safe, one message at a time, without separating anything.
- Metaclasses are the Smalltalk answer to a question this language does not ask.
- A behaviour object per built-in is smaller than a metaclass level.
- The single root is **not** blocked by the split, which this document used to
  claim. Tried on a throwaway copy: eight lines, the suite passes, and the only
  thing left in the way is what `new` should do on the four classes that cannot
  construct anything.
- Worth doing when the single root is wanted, not before.
- Separately: `new` is three operations sharing a name, and on `integer` and
  `float` it is the identity function left over from a design that was
  abandoned. The four classes without a class side should keep not having one.
