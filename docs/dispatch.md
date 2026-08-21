# Choosing what to do

Solum has no `switch`, no `case`, and no `match`. It does not need one, and the
thing it has instead is faster than a chain of comparisons — but it comes with
two traps worth knowing before you meet them.

There are two shapes of the question, and they want different answers:

| The question | The answer | Cost |
| --- | --- | --- |
| Which of these **values** is it? | a [dictionary of blocks](#a-dictionary-of-blocks) | one hash, whatever the number of cases |
| Which of these **conditions** holds? | [predicates tried in turn](#when-equality-is-not-the-question) | one test per case until one matches |

Most `switch` statements in most languages are the first, written in a form that
only knows how to do the second.

---

## A dictionary of blocks

A block is a value and a dictionary holds values, so a table of blocks under
keys is a jump table:

```
action := dictionary:new.
action:atPut('red,   { "stop" }).
action:atPut('amber, { "wait" }).
action:atPut('green, { "go" }).

action:at('red):value:display.        ; stop
```

**`at(key, default)` is the whole trick.** It is what makes the default case one
message rather than a lookup, a test, and a branch:

```
switch := { light | action:at(light, { "not a light" }):value }.

switch:value('green):display.         ; go
switch:value('purple):display.        ; not a light
```

That form was added so a counter could say `counts:at(word, #0):add(#1)`. It
turns out to be exactly what a switch wants, which is usually a sign that a
thing was shaped right rather than shaped for its first use.

The blocks may take arguments, so a case can use what it matched:

```
reply := dictionary:new.
reply:atPut(#404, { n | "no page {}":fill([n]) }).

reply:at(#404, { n | "status {}":fill([n]) }):value(#404):display.  ; no page 404
reply:at(#500, { n | "status {}":fill([n]) }):value(#500):display.  ; status 500
```

Anything that can be a dictionary key can be a case: integers, strings, symbols,
booleans, floats, times, nil. Symbols are the usual choice, being interned names
compared by pointer — which is what an enum is for.

### What it costs

Twenty cases, asking for the last one, two thousand times:

```
predicate caseOf  0.015111 s
dictionary table  0.000805 s
faster by         18.8x
```

The gap is not a constant. A dictionary hashes once whatever the table holds,
where a chain of comparisons walks until it matches — so twenty cases is
nineteen tests on average and a hundred cases is ninety-nine. The dictionary
does the same work for both.

---

## Two traps

Both come from the same place: **the blocks in the table are closures**, and a
closure remembers where it was written.

### Building the table in a loop

This is the natural thing to write, and it does not work:

```
u := dictionary:new.
i := #1.
{ i:lessOrEqual(#3) }:whileTrue({ | n |
    n := i.
    u:atPut(n, { n:mul(#10) }).
    i := i:add(#1) }).

u:at(#2, { #0 }):value.
solvm: block outlived the frame it was written in
```

The block reads `n`, which is a temporary of the loop body's frame, and that
frame has returned by the time anything calls the block. That is
[restriction 3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame), and
it fails **loudly**, which is the good case.

### The same thing capturing a global

Move the counter out to a global and the failure goes away. So does the
correctness:

```
v := dictionary:new.
k := #1.
{ k:lessOrEqual(#3) }:whileTrue({ v:atPut(k, { k:mul(#10) }). k := k:add(#1) }).

v:at(#1, { #0 }):value:print.         ; #40
v:at(#2, { #0 }):value:print.         ; #40
v:at(#3, { #0 }):value:print.         ; #40
```

Every block reads the same global, and by the time any of them runs, `k` is
`#4`. This is the closure-in-a-loop bug that every language with closures has,
and Solum does not protect you from it: a block captures a *name*, not the value
the name had.

**Write the table's blocks literally, where the table is built.** That is what a
switch statement looks like anyway, and a literal block that reads nothing
outside itself has nothing to capture and nothing to go stale.

---

## When equality is not the question

A dictionary dispatches on **equality**. It cannot answer "is it more than a
hundred", "is it between these two", or "does it start with a slash". For those
the cases have to be tried in turn, and a case is a pair of blocks — one that
tests, one that answers:

```
object:caseOf := { pairs | | answer, found |
    answer := nil. found := false.
    pairs:do({ pair |
        found:not:and({ pair:at(#1):value(self) }):ifTrue({
            found := true. answer := pair:at(#2):value }) }).
    answer }.

#150:caseOf([
    [{ n | n:lessThan(#100) },  { "small" }],
    [{ n | n:lessThan(#1000) }, { "medium" }],
    [{ n | true },              { "large" }]
]):display.                           ; medium
```

The last pair with a condition of `true` is the default, and it has to come
last, because the first match wins.

This is in [ideas.md](ideas.md#already-there-or-already-writable) and is
deliberately **not** in the library. It is a fine demonstration that the
language needs no `switch` syntax, and an array of two-element arrays of blocks
reached into with `pair:at(#1)` is not an interface worth committing to. Copy it
into a program that needs it, and shape it to that program.

---

## Which to reach for

Equality on a value you have — a status code, a command name, a symbol — is the
common case and the dictionary is better at it in every way: faster, and with no
interface to learn beyond `atPut` and `at`.

Conditions, ranges and guards are the other case, and there the tests have to
run. If a program is doing both, doing them separately reads better than forcing
one into the shape of the other: look the value up, and fall back to the
conditions when the lookup misses.

```
byName := lookup:at(command, nil).
byName:isNil:ifElse({ ...try the conditions... }, { byName:value }).
```
