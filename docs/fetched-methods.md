# Fetching a method, and binding one

*What `slotAt` gives you, why it does not work on its own, and what `boundTo` is
for. Every snippet here has been run; the outputs are what the VM actually
prints.*

For the messages themselves see [REFERENCE.md](REFERENCE.md#fetching-a-method).
For a runnable version see [examples/reflect.sol](../examples/reflect.sol).

---

## A method is a block in a slot

Solum has no separate notion of a method. A method is a **block sitting in a
slot**, and binding one uses the same `:=` as any other assignment:

```
counter := object:new.
counter:n := #0.
counter:bump := { self:n:add(#1) }.
```

The right-hand side is evaluated and the result is bound. A slot holding a
block is what makes a method; a slot holding anything else is data. That is the
whole rule — `counter:n := #0` and `counter:bump := { ... }` are the same
operation, and they differ only in what the value turns out to be.

## Where `self` comes from

Look at that block again:

```
{ self:n:add(#1) }
```

There is no receiver anywhere in it. `self` is not stored in the block — it is
supplied by **the send**. When you write `c:bump`, the VM puts `c` into slot 0
of the new frame, and `self` inside the block reads that slot.

```
c := counter:new.
c:n := #41.
c:bump:print.                    ; #42
```

That is worth stating plainly because it is the thing everything else here
follows from:

> A block does not carry a receiver. A send provides one.

It is also what lets a block be built somewhere and installed somewhere else and
still behave correctly — the block does not care who it ends up belonging to,
because whoever sends to it will say.

## What goes wrong when you fetch one

`slotAt` is the only way to hold a method as a value:

```
m := counter:slotAt('bump).
m:print.                         ; <block>
```

That is the real method body. But look at what happens if you call it:

```
m:value.
solvm: nil does not understand 'n'
```

Nothing is telling it what `self` is. `value` runs the block with whatever
`self` was **where the block was written** — and a method written at the top
level was written with no receiver at all, so `self` is nil.

So a fetched method used to be a thing you could hold but not call. That is the
gap; `boundTo` is the fix.

## `boundTo`

It answers a **second block over the same code**, with `self` set:

```
a := counter:new. a:n := #10.
b := counter:new. b:n := #100.

m:boundTo(a):value:print.        ; #11
m:boundTo(b):value:print.        ; #101
```

One block of code, two receivers, two answers. Note that `m` itself is
untouched — `boundTo` answers a new block rather than modifying the old one, so
the same fetched method can be bound again and again:

```
[a, b]:collect({ e | m:boundTo(e):value }):print.     ; [#11, #101]
```

The receiver may be any value, because `self` may be any value — an integer, a
string, an array, an object.

### Binding and calling stay two things

This was the design decision, and it is why `boundTo` answers a block instead of
just running one. The alternative considered was `valueWith(receiver, ...)`,
calling immediately with the receiver as the first argument.

Answering a block follows `via`, which answers a delegating view rather than
performing the send. Keeping binding and calling apart means **`value` goes on
meaning exactly what it always meant**:

```
counter:scale := { k | self:n:mul(k) }.

s := counter:slotAt('scale):boundTo(c).
s:value(#2):print.               ; #82
```

The arguments are the block's own, and the receiver is nowhere among them.
Under `valueWith` the two would have shared one positional list, and
`m:valueWith(p)` on a one-argument block would be an arity error that reads like
a one-argument call.

It also means a bound method is a **value**: something to store in an array,
pass to `do`, hold in a slot, or call many times.

---

## What it is actually good for

Honestly: for most code you would never reach for it.

If you want to call `bump` on `c`, you write `c:bump`. If you want that as a
block, you write `{ c:bump }` — which is shorter than fetching and binding, and
clearer. `boundTo` is not a replacement for either.

**It earns its place when the method is chosen at run time.** You have a name in
a variable, or a block you got from `slots` and `slotAt`, and you want a callable
value out of it:

```
which := 'square.
op := counter:slotAt(which):boundTo(c).

{ i:lessThan(#3) }:whileTrue({ total := total:add(op:value). i := i:add(#1) }).
```

`op` is a plain callable now. The name is gone, the lookup has already happened,
and it goes anywhere a block goes.

### Against `perform`

`perform` already calls a method named at run time, so the two overlap. The
difference is what you get back:

| | |
| --- | --- |
| `c:perform(which)` | looks the name up **on every call**, and needs the name in hand every time |
| `c:slotAt(which):boundTo(c)` | looks it up **once**, and answers a value you can hold and call later |

`perform` is right when you are calling once. `boundTo` is right when you want
the *result of the lookup* as a thing.

If you know Python, this is exactly the `Point.sum` versus `p.sum` distinction —
a plain function that needs a receiver, against a bound method that carries one.

---

## Two things it does not do

### A send still wins

Put a bound block in a slot and it is an ordinary method again:

```
other := object:new. other:n := #7.
other:bump := m:boundTo(a).      ; bound to a, whose n is #10

other:bump:print.                ; #8 -- self is `other`, not `a`
```

That looks wrong the first time you see it. It has to be that way: *a send
supplies the receiver* is the rule that makes an installed block a method at
all. If a binding could override it, installing a bound block would produce a
method that ignored whoever called it.

So: binding chooses a receiver for `value`. It never overrides a send. There is
a test pinning that behaviour so it stays true.

### It does not lift the frame restriction

A block that reads its home frame is tied to that frame, and calling it after
the frame has returned is an error — "block outlived the frame it was written
in" ([ROADMAP.md](ROADMAP.md) 3.1). Binding does not change that:

```
f := { | t | t := #5. { t:add(#1) } }.
escaped := f:value.
escaped:boundTo(#1):value.
solvm: block outlived the frame it was written in
```

The home frame comes across unchanged, because **binding chooses a receiver, not
a lifetime**. Those are two different pieces of a block's context and only one
of them is being replaced.

---

## Summary

- A method is a block in a slot; `:=` binds it like anything else.
- A block carries no receiver. A send supplies one.
- So a method fetched with `slotAt` has no `self` and cannot be called as it
  stands.
- `boundTo(receiver)` answers a new block over the same code with `self` set.
- Binding and calling stay separate, so `value` and arity are unchanged and a
  bound method is a first-class value.
- A send still supplies its own receiver, and a captured frame is still a
  captured frame.
