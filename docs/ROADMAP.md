# Roadmap

Everything still outstanding, grouped by what it blocks. This is the single list
— [design.md](design.md) describes how the language works today and points here
for what is unresolved, [CHANGELOG.md](CHANGELOG.md) records what has already
changed, [COMPLETED.md](COMPLETED.md) keeps the entries for work that is done,
and [ideas.md](ideas.md) records what was considered and turned down, with the
reasoning.

Nothing finished is kept here. An entry moves to
[COMPLETED.md](COMPLETED.md) when the work lands, which is where the case for it
survives — what the problem was, what the options were, and why the shape chosen
was the one taken. Numbers are never reused, so a gap below is a record rather
than a mistake.

Items marked **decision** need a call from you before they can be built; the
rest are work with a clear shape.

## Where things stand

Working: the scanner, the single-pass compiler, the re-entrant dispatch loop
with call frames, blocks with lexical capture and parameters, message-based
control flow, a mark-sweep collector over objects, blocks and compiled code, the
`.sob` format with its verifier, and every built-in type the language has.

The language is Turing-complete, does not leak, and has strings, arrays,
dictionaries, symbols, user-defined objects, reflection, sorting, formatted
output, and the conversions between every pair of types that has an unambiguous
one.

A string can be taken apart and put back — `split`, `indexOf`, `copyFrom`,
`join` — and an array can be folded, sliced and asked for its first or last few.
`isNil` and `notNil` ask whether a value is there. A program is split across
files with `@include "lib.sol".`, `@` marking the one thing in the language that
happens while compiling, and a name not found beside the includer is looked for
on a search path — which is how the library that ships with the language is
reached.

Conditionals, `whileTrue`, `doUntil` and `and`/`or` written literally compile to
jumps; the counted loops are primitives, which measured faster than jumps would
have been. Side-table operands are two bytes, a send compares pointers, and the
script's frame has slots like every other, so a temporary may be declared
anywhere.

**What is left is no longer the language.** Section 6 is a program's dealings
with the world outside it — reading input, writing files, stopping with a
status. Section 3 is the restrictions the language lives under on purpose. And
section 2 holds the one design question still open.

Sections 1, 4 and 5 are gone from this document. Everything they held is built:
the collector and its roots, arrays, strings, user-defined objects, the three
crashes that led the list, the inlining, the two-byte operands, dispatch by
pointer, the prompt, and source positions in compile errors. The entries are in
[COMPLETED.md](COMPLETED.md).

---

## 2. Language decisions still open

One question is still open, **2.5**. Everything else this section held has since
been decided and built, and the reasoning went to the changelog rather than being
kept in two places -- the [Settled table](COMPLETED.md#settled) gives each
verdict and names the entry to read for why. What those decisions left unfinished
is 2.14.

### 2.5 Class side versus instance side

`integer` holds both `new` and `print` in one object, so `#45:new(#1)` resolves
as readily as `integer:new(#1)`. It used to *answer*, which was nonsense that
worked; both refuse now that `new` has been taken off the value classes, so that
symptom is gone. `integer:slots` still lists both sides together, and still lists
`add`, which `integer:respondsTo('add)` correctly says it will not answer:
`slots` reports what is there and `respondsTo` asks the dispatch question, and
here the two have different answers.

The unevenness this entry used to record — `integer` having `new` where `float`
did not — was half fixed in `7ac6be6`, and is worth restating accurately, since
it is a symptom of the same thing. The class side is populated where somebody
needed it and nowhere else:

| | `new` | `of` |
| --- | --- | --- |
| `integer`, `float` | yes — refuses, and says what to write | — |
| `array` | yes — allocates | yes |
| `object` | yes — allocates and delegates | — |
| `string`, `symbol`, `block`, `boolean` | yes — refuses, and says what to write | — |

The last row came with the single root rather than from anyone deciding those
four wanted a `new`: delegating to `object` would have given them one, so they
shadow it to refuse.

There *is* a rule about which classes should construct, and this entry used to
say there was not. **`new` belongs where something is made, which is where the
instances are mutable**: `array:new:equals(array:new)` is false and
`"":equals("")` is true, so a value class has no fresh distinct thing to hand
back. It sorts all nine correctly. What is still missing is somewhere for that
rule to *live* — the class side is not a place, only some slots that happen to
sit beside the instance ones, so the rule holds in a document rather than in the
language. See
[class-and-instance.md](class-and-instance.md#the-class-side-is-populated-wherever-someone-needed-it).

This entry used to say a single root "needs this question answered first",
and that was wrong. **The root is done** — every built-in class delegates to
`object` and `#45:isKindOf(object)` is true. The obstacle it named had already
dissolved: `7ac6be6` gave `float` its own `new` to shadow object's, and 1.6's
receiver checks refuse the only two messages `integer` does not already define.
The four classes that cannot construct their instances now refuse `new` and say
what to write instead. See
[class-and-instance.md](class-and-instance.md#the-single-root--done-and-it-was-not-gated-by-this).

So what remains here is the split itself, and it is smaller than it looked. It
buys `#45:new(#1)` being refused, `slots` reporting one audience, and somewhere
for a rule about the class side to live. It is not what the root was waiting
on.

1.6 answered this **in the small**: each primitive records the receiver it needs
and the dispatcher checks before entering it, one message at a time. That was
enough to stop the two crashes, and it is not the same as splitting the two sides
into separate objects, which is what remains open.

**[class-and-instance.md](class-and-instance.md)** is the long version: why this
is only a problem for the built-ins, why the answer is probably not metaclasses,
what a behaviour object per built-in would cost and unblock, and the trigger
worth waiting for.

### 2.14 Loose ends from the decided items

Small, and each falls out of a decision above rather than being a question of its
own.

- ~~**`isNil`**~~ (2.8) — **done**, with `notNil` beside it. Both on every type,
  because the receiver is exactly what is not known when you ask. `notNil` is
  not merely `isNil:not`: the negative is the form that gets written, since
  running out of input is how a loop finishes, and a version with only `isNil`
  would have left the one real use of it reading worse than the
  `notEquals(nil)` it replaced.
- ~~**A fetched method is unbound**~~ (2.10) — **done**. `boundTo(receiver)`
  answers a second block over the same code with `self` set, which is then
  called like any other block. Answering a block rather than calling it follows
  `via`: binding and calling stay two things, so `value` goes on meaning what it
  meant and the receiver is never one of the arguments. It chooses a receiver,
  not a lifetime — a capturing block is no freer for being bound — and a send
  still supplies its own receiver, so installing a bound block makes an ordinary
  method.
- **Reflection cannot write** (2.10). There is no `slotAtPut`; no way to remove a
  slot, so a shadowing one cannot be un-shadowed (1.4); and no re-parenting,
  which would need the delegation link to become a real slot rather than the
  internal pointer that keeps dispatch safe (2.9).

  The strongest argument for `slotAtPut` used to be that it would make an object
  serve as a dictionary. [6.15](COMPLETED.md#615-there-is-no-dictionary-and-no-way-to-build-one)
  looked into that and found it would not: a slot name is interned in the VM's
  *permanent* name table, so keys read from a file would leak a name apiece, and
  slots are a linked list walked linearly, so it would not have been faster than
  the array of pairs it replaced. A real dictionary was built instead, and what
  is left here is reflection for its own sake.
- **No `clone`** (1.4). `new` delegates rather than copying, which is cheaper and
  more useful, but there is no way to take a snapshot of an object's slots.
- **A later range or slice API should use inclusive bounds at both ends** (2.3),
  following Smalltalk. Half-open ranges are what make zero-based indexing tidy;
  mixing a half-open convention into one-based indexing is where languages get
  confusing.

## 3. Known limitations

These are deliberate, safe, and documented. Each is a real restriction rather
than a bug.

### 2.13 Text is bytes, and case is ASCII only

`asUppercase` and `asLowercase` change `a`-`z` and `A`-`Z` and pass every other
byte through, by explicit range rather than `toupper` -- which follows the C
locale, so under a Turkish locale the same program would answer differently on
two machines.

That is the whole of the language's view of text: a string is bytes, `size`
counts bytes, and `at` answers a byte. `"café":size` is 5. `split` and `indexOf`
compare bytes, so a multi-byte separator works as written; `copyFrom` takes byte
offsets, so bounds that came from anywhere but `indexOf` can cut a code point in
half. Real Unicode -- code
points, a case mapping where one letter becomes two, normalisation, and knowing
how many characters a string has -- is a different piece of work rather than a
larger version of this one, and would want a decision about what a string is
before any of it is written.

Kept here rather than in section 2 because it is a restriction the language
lives under, not a question waiting on an answer. The number is the one the
changelog cites.

### 3.1 Capturing blocks cannot escape their frame

A block that reads or writes its home frame is tied to it. Calling one after that
frame returned is reported — "block outlived the frame it was written in" —
rather than reading slots that now belong to someone else. Non-capturing blocks
escape freely, which covers `{ #42 }` and most conditional branches.

Real closures need the captured slots promoted to the heap when a frame dies.
That is the upgrade path; the frame-id check is what makes today's restriction
safe rather than silently wrong.

### 3.2 No non-local return

A block answers its last expression. Smalltalk's `^` returns from the enclosing
*method* from inside a block, which needs frames unwound and is a much larger
change. Plenty of languages do without it.

### 3.3 Verification does not promise termination

A corrupted `.sob` can pass every check and still be a well-formed program that
loops forever. That is the VM behaving correctly — a bad program is not a broken
VM. Established by fuzzing, not assumed; see `docs/design.md`.

Inlining `whileTrue` (4.1) made this explicit rather than incidental. There is
now an opcode that jumps backwards, so a crafted file can spin without so much
as a send. It could already spin through a loop built from sends, and the source
language can say `{ true }:whileTrue({})` in eleven characters, so nothing became
reachable that was not reachable before. The verifier checks that a jump lands on
an instruction inside the chunk and that it arrives at the height that
instruction runs at (3.9), and stops there.

### 3.4 No compatibility across `.sob` versions

Each opcode-set change bumps the version and older files are refused outright.
Fine while nothing is released; worth a policy before anything is.

---

### 3.5 Recursion is limited to about 62 levels

`SOL_FRAMES_MAX` is 64 and a recursion level costs one frame, so 62 levels
succeed and 63 reports "call depth exceeded". Measured again after the `new`
change, and it is exactly 62:

```
integer:down := { self:greaterThan(#0):ifTrue({ self:sub(#1):down }). self }.
#62:down.   ; ok
#63:down.   ; solvm: call depth exceeded
```

**It used to be 30**, and this entry was titled that way for longer than it was
true. A level cost **two** frames then -- one for the method's block, one for the
`ifElse` branch block carrying the recursive call. Inlining conditionals (4.1)
took the second one away. Recursion through a `whileTrue` body stayed at 30 until
the loop was inlined too, for exactly the same reason; both forms reach 62 now.

The two remaining ways to go further: raise the cap, which costs stack because
`SOL_STACK_MAX` is derived from it; or make the limit dynamic rather than a
fixed array.

### 3.6 A caller-owned chunk must outlive blocks defined in it

Chunks from `sol_chunk_init` are freed by the caller. A block defined in one and
still reachable afterwards holds a pointer into freed memory, and calling it is
undefined. The collector itself is safe -- a block caches its owning cell, so
tracing never dereferences a freed chunk -- but nothing detects the call.

Solis avoids this entirely by using `sol_code_new`. It bites only code that mixes
caller-owned chunks with a long-lived VM, which today is the test suite.
Collapsing the two ownership modes into one would fix it, at the cost of giving
Solas a VM it otherwise does not need.

### 1.1d Collection is stop-the-world and non-incremental

Fine at this size and not worth touching yet. Noted so it is a choice rather than
an oversight: a program holding a large live set will pause proportionally to it.

Kept here rather than under the collector, which is otherwise done. The number is
the one the changelog cites.

## 6. Beyond the language

Sections 1 to 5 were about making Solum a language, and they are done — the
entries are in [COMPLETED.md](COMPLETED.md). This one is about making it a
language you can write a *program* in: a program has to be split across files,
read input, write files, and stop with a status. None of it needs a new idea.
Splitting a program across files is done, and so are stopping, reading input,
and files themselves. What is left of it is smaller than what has gone.

Raised in a notes file and assessed in [ideas.md](ideas.md), which also records
what was **not** worth building and why — integer widths, a JIT, cascades,
trailing-block syntax, and Go-style concurrency among them.

### 6.10 Waiting for a single key

Reading a *line* is done (6.3). Reading a keypress is a different job, and was
split off rather than carried along with it: it needs raw terminal mode, which is
`termios` on Unix and something else on Windows, and it would be the first piece
of the runtime that behaves differently by platform.

Worth doing when a program needs it, and behind its own decision rather than as
a footnote to line input.

### 6.17 There is no `ensure`

Catching a failure is built. Running something *regardless* of whether one
happened is not: there is no `ensure`, `finally`, or `unwind-protect`.

```
{ risky:value }:ensure({ cleanUp:value }).
```

Nothing needs it yet, which is why it was left out rather than guessed at. The
things `ensure` usually protects are handles and locks, and there are neither:
a file is read or written whole, and there is no concurrency. The one thing it
would buy today is restoring a value a block changed, which is rare enough to
write by hand.

It is worth building when something acquires a thing that must be given back.
The shape is the same as `onError` — a primitive that calls the receiver, notes
whether it failed, runs the second block either way, and then either answers or
goes on failing — with one wrinkle: a failure in the cleanup block while an
error is already travelling has to decide which of the two survives, and the
first one is the one worth reporting, as it is everywhere else here.

### 6.12 Taking a binary file apart

Reading and writing binary files already works: a string is bytes, a NUL is a
byte like any other, and reading a file and writing it back copies it exactly.
Since [6.11](COMPLETED.md#611-a-string-cannot-be-split), `split`, `indexOf` and
`copyFrom` work on one too — all three go by the length rather than stopping at
the first NUL, so a binary file can be cut up by a marker.

What is still missing is a *number* for a byte. `at` answers a one-character
string, and there is nothing to do arithmetic on.

What this wants is a byte-buffer type. An array of integers would work and would
cost sixteen bytes a byte. Worth building when a program needs it rather than on
the chance that one might.

## Suggested order

**Section 6 is the whole of the live list**, and it came from the right place:
notes about what a program would want, rather than a plan written before there
were any programs. The two newest entries came from further along the same road
— from a program that wanted something and could not have it, and one of them is
already built. Fourteen of its items are built — a program can be split across
files, stop with a status, read its input, read and write files, take a string
apart and put it back together, keep values under keys, slice an array, and time
itself; the instruction set has a
reference the test suite keeps honest, the guide contrasts a group with a block,
and every concept the guide names now has a runnable example; and the include
that started it has since been given a syntax that admits what it is (6.13) —
so in order of what would be missed next:

**Nothing is left here that came from a program wanting it.** Both entries that
did — [6.15](COMPLETED.md#615-there-is-no-dictionary-and-no-way-to-build-one)
and [6.16](COMPLETED.md#616-an-array-cannot-be-sliced) — are built, and so is
all of [6.6](COMPLETED.md#66-the-loop-constructs-are-library-code-and-pay-for-it).

What remains is **6.10** and **6.12**, both explicitly waiting for a program
that needs them, and the decision below. The way to move this list is to write
something and find out what it wants — which is how the last two entries got
here, and both paid for themselves.

Not ordered: **a single keypress** (6.10) and **a byte type** (6.12) both wait
for a program that needs them. That was true of the whole list until
[log.sol](../examples/log.sol) was written; it is worth noticing which entries
survived contact with a real program and which did not come up at all.

One decision is outstanding: **2.5**, class side versus instance side. 1.6
answered it one message at a time, which was enough to stop the crashes;
splitting the two sides into separate objects is still open. Every other question
section 2 held has been decided and built.

[ideas.md](ideas.md) records what was considered and turned down, so the same
arguments do not have to be had twice, and [COMPLETED.md](COMPLETED.md) records
what was built, so the reasoning does not leave with the entry.
