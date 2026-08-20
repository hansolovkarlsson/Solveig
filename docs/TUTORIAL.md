# Tutorial: build a stock report

*One program, from nothing to something useful, introducing each idea at the
moment you need it. Every snippet here has been run; the outputs are what the VM
actually prints.*

If you would rather have the concepts surveyed in order than discovered while
building, read [GUIDE.md](GUIDE.md) instead. When you want to look a message up,
that is [REFERENCE.md](REFERENCE.md).

The finished program is [examples/stock.sol](../examples/stock.sol).

---

## Getting something to run

Build the three programs first:

```sh
make
```

`solis` is the prompt. It reads until what you have typed could compile, then
compiles and runs it:

```
$ ./bin/solis
> "hello":display.
hello
```

So a method body may span as many lines as it likes — the `.. ` prompt means
Solis is still waiting for a bracket or a string to close:

```
> integer:double := {
..     self:mul(#2)
.. }.
> #21:double:print.
#42
```

Everything below can be typed at that prompt, or put in a file and compiled:

```sh
./bin/solas stock.sol      # writes stock.sob
./bin/solvm stock.sob
```

One thing to know before we start: **`:` sends a message and `.` ends a
statement**. There is no operator syntax, so arithmetic is message sending too:

```
> #2:add(#3):print.
#5
```

`#2` is an integer — the `#` is a type tag. A bare `2` would be a float. That
distinction is going to matter in about four minutes.

---

## Step 1: an item

We are building a report over stock. So: an item, with a name, a price, and a
quantity.

There is no `class` keyword. An object is a bag of named slots, and `object:new`
answers a fresh one:

```
item := object:new.
item:name  := "".
item:price := 0.0.
item:qty   := #0.
```

`:=` binds a name — the same operator for a global as for a slot on an object.
The values given here are **defaults**: any item made from this one sees them
until it sets its own.

Note `0.0` and `#0`. A price is a float, a quantity is an integer, and the
literal is what says which.

## Step 2: a method

A method is not a separate kind of thing. It is **a block bound to a slot**:

```
item:total := { self:price:mul(self:qty:asFloat) }.
```

`{ ... }` makes a block — code as a value, which runs nothing when written.
`self` is the receiver, and it arrives when the message is sent.

Now make one and ask it:

```
apples := item:new.
apples:name := "apples".
apples:price := 1.25.
apples:qty := #3.

apples:total:print.
```
```
3.75
```

### The `asFloat` is not noise

Try writing `self:price:mul(self:qty)` instead and you get:

```
solvm: 'mul' expects float, got integer (no implicit coercion)
```

Integers and floats **never** mix on their own. There is no rule to remember
about which way a value gets promoted, because no value ever gets promoted —
where you want a widening you write one. That is the first place the language's
strictness shows up, and it is deliberate: `#7:div(#2)` is `#3`, and if you
wanted `3.5` you were owed a chance to say so.

## Step 3: making them without the ceremony

Four statements per item will not do. Give the prototype a maker:

```
item:make := { n, p, q |
    | it |
    it := self:new.
    it:name := n. it:price := p. it:qty := q.
    it
}.
```

Two new pieces of syntax, both in the block header:

- `n, p, q |` are **parameters**.
- `| it |` declares a **temporary** — a name local to this call.

A block answers its last expression, so ending with `it` hands the new item
back. And because `self` is the receiver, `self:new` means "a new one of
whatever I was sent to" — which will matter in the last step.

```
stock := [
    item:make("apples",  1.25, #3),
    item:make("pears",   0.5,  #12),
    item:make("quinces", 7.5,  #1)
].

stock:size:print.
stock:at(#2):name:print.
stock:at(#2):total:print.
```
```
#3
"pears"
6
```

`[...]` is an array literal — sugar for `array:of(...)`, and nothing more.
**Indices start at one**: an index here is an ordinal, not an offset into
anything, so `at(#1)` is the first element and `at(#0)` is an error rather than
a quiet mistake.

## Step 4: walking the collection

`do` runs a block once per element:

```
sum := 0.0.
stock:do({ e | sum := sum:add(e:total) }).
sum:print.
```
```
17.25
```

`sum` has to exist before the block assigns it. Assignment inside a block will
not create a global — a typo would otherwise bring a new name into being where
it looked like a local.

`collect` answers a new array of the block's answers, and `select` keeps the
elements the block approves of:

```
stock:collect({ e | e:name }):print.
stock:select({ e | e:total:greaterThan(5.0) }):collect({ e | e:name }):print.
```
```
["apples", "pears", "quinces"]
["pears", "quinces"]
```

`sorted` takes a block saying which of two comes first, so your own type sorts
itself without the array knowing anything about it:

```
stock:sorted({ a, b | a:total:greaterThan(b:total) }):collect({ e | e:name }):print.
```
```
["quinces", "pears", "apples"]
```

### An aside: there is no `if` in this language

You have been writing blocks for three steps, so this will not be a shock:
control flow is message sending. `ifTrue`, `ifElse`, and `whileTrue` are
ordinary messages that take unevaluated blocks.

```
> #5:lessThan(#10):ifElse({ "small" }, { "large" }):display.
small
```

The boolean receives the message and decides which block to run. Nothing is
special about them — you could write your own — and written literally they
compile to jumps anyway, so they cost what an `if` costs elsewhere.

## Step 5: making an item print itself

`stock:at(#1):print` at this point shows an address, which is no use. An object
is **rendered by asking it**, so define `asString`:

```
item:asString := { "{} x{} @ {}":fill([self:name, self:qty, self:price]) }.

stock:at(#1):print.
stock:print.
```
```
apples x3 @ 1.25
[apples x3 @ 1.25, pears x12 @ 0.5, quinces x1 @ 7.5]
```

One definition and `print`, `display`, `fill`, and array rendering all use it.

`fill` fills a template: each `{}` takes the next value and renders it by
*sending* it `asString` — which is why an array of items renders element by
element without being told how.

## Step 6: the report

`asString` also takes a **format spec**:

```
[align] [','] ['0'] [width] ['.' decimals]
```

There is no conversion letter, because the receiver already knows its own type
and nothing could contradict it. Text aligns left and numbers align right, so a
column falls out of the widths:

```
row := { e |
    "{}{}{}":fill([ e:name:asString("<10"),
                    e:qty:asString("5"),
                    e:total:asString(",12.2") ])
}.

"stock report":display.
stock:sorted({ a, b | a:total:greaterThan(b:total) }):do({ e | row:value(e):display }).
```
```
stock report
quinces       1        7.50
pears        12        6.00
apples        3        3.75
```

`,12.2` is: group thousands, width 12, two decimals. `<10` is: left-aligned,
width 10.

## Step 7: a kind of item

Say some stock is sold at a discount. There is still no `class` keyword, and
there is still nothing to learn — `new` answers an object that **delegates** to
the receiver, so a "subclass" is an object that overrides a slot:

```
sale := item:new.
sale:total := { self:via(item):total:mul(0.9) }.
```

`self:via(item)` reaches the method this one overrides, running it with `self`
still the discounted item. The ancestor is **named** rather than inferred —
there is no `super` — so the method keeps working however deep the receiver
turns out to be, and cannot accidentally find itself and recurse.

```
full   := item:make("quinces", 7.5, #2).
marked := sale:make("quinces", 7.5, #2).

full:total:print.
marked:total:print.
```
```
15
13.5
```

Look at what did *not* need changing. `sale:make` is `item`'s maker, inherited,
and `self:new` inside it answered a `sale` rather than an `item` because `self`
was `sale`. And:

```
marked:isKindOf(item):print.
row:value(marked):display.
```
```
true
quinces       2       13.50
```

The report row works unchanged, because it only ever asked for `name`, `qty`,
and `total`.

---

## What you have used

Nearly the whole language, without meeting it as a list:

| | |
| --- | --- |
| messages, `:=`, statements | steps 1–2 |
| objects, slots, defaults | step 1 |
| blocks, `self`, methods | step 2 |
| strict numbers, no coercion | step 2 |
| parameters and temporaries | step 3 |
| arrays, one-based indices | step 3 |
| `do`, `collect`, `select`, `sorted` | step 4 |
| control flow as messages | step 4 |
| `asString`, `fill`, format specs | steps 5–6 |
| delegation, overriding, `via` | step 7 |
| `isKindOf` | step 7 |

## Where next

- [GUIDE.md](GUIDE.md) — the same ground surveyed in order, plus symbols,
  reflection, values against references, and the restrictions worth knowing.
- [fetched-methods.md](fetched-methods.md) — holding a method as a value.
- [absence.md](absence.md) — nil, empty, and unset, and what a name holds before
  you fill it.
- [REFERENCE.md](REFERENCE.md) — every message, for looking things up.
- [examples/](../examples/) — fifteen more programs, each on one topic.
