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

**What is left is section 3, and only section 3.** Those are the restrictions
the language lives under on purpose, each documented where a program would meet
it. Section 2 has no open design question — the last one, 2.5, is closed — and
section 6, a program's dealings with the world outside it, is finished: reading
input, writing files, stopping with a status, walking the filesystem, knowing
the time, and as of the last entry, a prompt with history.

So this document no longer says what to build next. **The way to add to it is to
write a program and find out what it wants**, which is how every one of the last
eight entries arrived — several of them from a library breaking rather than from
anyone reasoning about the design.

Sections 1, 4 and 5 are gone from this document. Everything they held is built:
the collector and its roots, arrays, strings, user-defined objects, the three
crashes that led the list, the inlining, the two-byte operands, dispatch by
pointer, the prompt, and source positions in compile errors. The entries are in
[COMPLETED.md](COMPLETED.md).

---

## 2. Language decisions

**Nothing here is open.** The last question was **2.5**, class side versus
instance side, and it is
[closed](COMPLETED.md#25-class-side-versus-instance-side--closed): the line
between the two is drawn by the receiver each slot requires rather than by
splitting the objects, which is what the split would have bought. Everything
else this section held was decided and built, and the reasoning went to the
changelog rather than being kept in two places -- the
[Settled table](COMPLETED.md#settled) gives each verdict and names the entry to
read for why. What those decisions left unfinished is 2.14, and 2.13 is a
limitation rather than a question.

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
  serve as a dictionary. [6.15](COMPLETED.md#615-there-is-no-dictionary-and-no-way-to-build-one--done)
  looked into that and found it would not: a slot name is interned in the VM's
  *permanent* name table, so keys read from a file would leak a name apiece, and
  slots are a linked list walked linearly, so it would not have been faster than
  the array of pairs it replaced. A real dictionary was built instead, and what
  is left here is reflection for its own sake.
- **`via` refuses a value receiver** (2.9). Override on a value class a message
  that `object` defines and the override cannot reach the one it displaced:
  `self:via(object)` answers *'via' expects an object, got integer*. The check
  predates the single root, when a value's chain ended at its own class and
  there was nothing above to name; every class delegates to `object` now, so a
  value has a well-defined chain to walk. `slotAt(...):boundTo(self)` does the
  job today. See
  [one-hierarchy.md](one-hierarchy.md#the-one-place-the-difference-shows).
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

**The unwinding half of it exists now**, which is worth noticing: `onError`
stops an error part-way out and carries on, and `ensure` sets a failure aside
and puts it back. Both had to leave the machine level -- frames, stack and the
collector's temporaries -- which is most of what a non-local return would need
as well. What is still missing is the *naming*: `^` has to identify which
enclosing frame to return from, and a block that has outlived that frame has to
be refused rather than returning into it. That is the part 3.1 already has an
answer to, in the frame ids it checks.

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

**A program has now reached it.** [examples/evaluator.sol](../examples/evaluator.sol)
is a recursive-descent parser, which spends about three frames per level of
bracket nesting — expression calls term calls factor calls expression again —
so it manages **18 brackets deep** and stops at 19. That is more than anybody
writes by hand and less than a generated expression might hold.

**A second one has now reached it, and put a number on the idiom.**
[lib/json.sol](../lib/json.sol) is the same shape of parser over a format people
generate rather than type, and it measured the cost of *how* the value dispatch
is written:

| dispatching on the first character | levels of JSON nesting before the cap |
| --- | --- |
| a dictionary of blocks, as [dispatch.md](dispatch.md) recommends | **18** |
| a chain of `ifElse` | **28** |

`table:at(c, default):value` puts one more frame between a value and the value
inside it, and that frame is paid again at every level of the document — ten
levels of nesting for one message. Both recommendations are right on their own;
they pull against each other only where the cases recurse. The library takes the
chain and says why in a comment.

It also moves the number from "more than anybody writes by hand" to something
closer: 28 levels of JSON is not deep for a document a program produced.

What makes it bearable, and was not obvious: **the failure is catchable.** `call
depth exceeded` arrives at `onError` like any other, is reported like any other,
and the program carries on afterwards — running out of frames is exactly the
sort of failure a machine might not be able to recover from, and this one can.
So the limit is a limit rather than a crash, which lowers what raising it would
buy.

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
entries are in [COMPLETED.md](COMPLETED.md). This one was about making it a
language you can write a *program* in: a program has to be split across files,
read input, write files, and stop with a status.

**One entry is left**, and it is here because closing it was a mistake rather
than because it was never done.

Raised in a notes file and assessed in [ideas.md](ideas.md), which also records
what was **not** worth building and why — integer widths, a JIT, cascades,
trailing-block syntax, and Go-style concurrency among them.

### 6.10 Waiting for a single key

Reading a *line* is done — [6.3](COMPLETED.md#63-reading-input--done) gave a
program `system:readLine`. Reading a keypress is the other half of that entry
and is still missing: there is no `system:readKey`, so a Solum program cannot
ask for one character without waiting for return.

**This was closed once by mistake.** `solis` grew raw-mode line editing for its
own prompt, which needed exactly the machinery this asks for, and the work was
filed here — see [6.24](COMPLETED.md#624-the-prompt-has-no-history--done). It is
the front end reading its own keys. A program still cannot, and nothing in the
language changed.

**What is left is smaller than it was**, and that is the one good thing to come
out of the mix-up. `solis/src/line.c` already puts a terminal into raw mode,
reads a byte, and restores the mode afterwards, with the platform guard around
it. A `system:readKey` is that, without the editing:

- one byte, or a whole escape sequence? A program wanting arrow keys wants the
  sequence; one wanting *any key* wants the byte. Answering the byte is the
  smaller promise and lets a program assemble the rest.
- what does it answer with no terminal — a pipe, a file? `readLine` answers nil
  at the end of input, and the same answer fits: nothing to read.
- does it echo? Raw mode does not, and a program that wants the key shown can
  print it.

Still waiting for a program that needs it, which is now a fair test rather than
an excuse: an interactive one would want it on the first screen.

## Suggested order

**Nothing is on the live list.** Section 6 came from the right place:
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

**Nothing here is blocking a program.** [6.12](COMPLETED.md#612-taking-a-binary-file-apart--done)
was, for about a day: it waited for something to need a number for a byte, and
`lib/json.sol` needed one — not for the binary files the entry was written
about, but for `\u0041`, which is text. `asByte` and `asCharacter` are built and
it is done.

**6.10 is the only thing here**, and it is open again after being closed by
mistake. `solis` grew raw-mode line editing for its own prompt
([6.24](COMPLETED.md#624-the-prompt-has-no-history--done)), which needed the same
machinery — and a *program* still cannot read a keypress, which is what this
entry is. The machinery being built is the reason it is now small. The four papercuts —
[6.19](COMPLETED.md#619-a-symbol-cannot-be-ordered--done),
[6.21](COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done),
[6.22](COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done)
and [6.23](COMPLETED.md#623-an-array-cannot-be-popped-or-asked-what-it-holds--done)
— were all found by writing programs, and two of them by a library breaking from
a distance rather than by anybody reasoning about the design.

Three programs have now been written to do a job rather than to show a feature,
and each one moved this list:
[log.sol](../examples/log.sol) asked for a dictionary and array slicing and got
both; [evaluator.sol](../examples/evaluator.sol) found the frame limit and that
it is catchable; [manifest.sol](../examples/manifest.sol) and the library under
it found the three above. It is worth noticing which entries survived contact
with a real program and which have still never come up.

**No decision is outstanding.** 2.5, the last one, is closed: 1.6 had answered
it one message at a time to stop the crashes, and finishing that -- every
class-side message requiring an object receiver -- turned out to be the whole of
what splitting the two objects would have bought. Every question section 2 held
has now been decided.

[ideas.md](ideas.md) records what was considered and turned down, so the same
arguments do not have to be had twice, and [COMPLETED.md](COMPLETED.md) records
what was built, so the reasoning does not leave with the entry.
