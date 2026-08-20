# The class side and the instance side

*What roadmap [2.5](ROADMAP.md) is about, why it is only a problem for the
built-in classes, why the answer is probably not metaclasses, and when it would
be worth doing. Every snippet here has been run; the outputs are what the VM
actually prints.*

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

## What it unblocks, which is the real reason

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

With the sides split, `object`'s `new` lives on the **class side**, so a built-in
class's class side can delegate to it without leaking anything onto float
values. The hierarchies join, `integer:isKindOf(object)` becomes true, and a
single root stops being blocked.

That is why 2.5 sits under a tidy-sounding name and gates a structural change.

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

**Not yet.** None of today's symptoms bite a working program: `#45:new(#1)` is
nonsense nobody writes, and mixed `slots` is cosmetic. Doing this now would be
refactoring toward tidiness.

The thing worth having is the single root. So the trigger is **the first time
`integer:isKindOf(object)` being false gets in the way** — when something wants
to be generic over "any value" and finds the hierarchies do not meet. Done then,
it removes a real obstacle, and the design will be better for having a concrete
case pushing on it rather than a preference.

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
- A behaviour object per built-in is smaller, and is what unblocks a single root.
- Worth doing when the single root is wanted, not before.
