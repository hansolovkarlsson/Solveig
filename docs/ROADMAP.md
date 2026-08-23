All of it is built. `solvm --trace` writes the call tree, a trace names the file
as well as the line
([6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done)), a frame
slot knows what it was called
([6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done)), and
[Solid](COMPLETED.md#629-a-stepper--solid--done) stops a program where it is
running and shows both.

Those three arrived in that order on purpose, and the order was the useful part:
each one made the next worth having. A trace that could not name a file was
misleading; a debugger that could not name a local would have been most of the
work for a fraction of the use.

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

**What is left is section 3, and nothing else.** No work, and no decision.

Section 3 holds the restrictions the language lives under, each documented where
a program would meet it. The older ones were chosen; the six newest were found —
[3.7](#37-a-limit-bounds-dispatch-not-work) by running a program the way its own
case would;
[3.8](#38-a-host-and-a-script-agree-a-name-and-nothing-checks-that-they-do),
[3.10](#310-a-vm-cannot-be-reused-across-runs) and
[3.11](#311-a-chunk-cannot-be-shared-between-threads) by writing down what a host
embedding the machine may rely on, which meant writing down what it may not;
[3.12](#312-no-shift-can-produce-a-negative-integer) by a program trying to
decode a `.sob`; and
[3.13](#313-a-loop-is-left-by-its-condition-or-by-failing) by counting how many
loops in this repository carry a boolean whose only job is to stop them.

Section 2 has no open design question — the last one, 2.5, is closed. And
section 6, a program's dealings with the world outside it, is built: reading
input, writing files, stopping with a status, walking the filesystem, knowing
the time, a prompt with history, a debugger, and running another program.

**The last decision was deferred rather than taken**, on 2026-08-22.
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine) —
whether a script should be able to run with less than the whole machine — is in
[ideas.md](ideas.md) now, with the rest of what waits on a trigger. It was the
only entry here that came from a *concern* rather than from a program wanting
something, and the concern is about a use this language does not have. The
trigger is somebody running a script they did not write.

Its other half was never a decision and is built.
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
was the same webserver's other problem — a script that never finishes is a
request that never finishes — and is now a step limit and a memory ceiling a
host sets before the program runs.

So this document no longer says what to build next. **The way to add to it is to
write a program and find out what it wants**, which is how nearly every entry
since the first dozen arrived — several of them from a library breaking rather
than from anyone reasoning about the design.

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
- **A later range API should use inclusive bounds at both ends** (2.3),
  following Smalltalk. Half-open ranges are what make zero-based indexing tidy;
  mixing a half-open convention into one-based indexing is where languages get
  confusing.

  **The slice half of this is settled and was decided by being built.**
  `copyFrom(first, last)` is inclusive at both ends on strings and arrays —
  `"abcdef":copyFrom(#2, #4)` answers `"bcd"` — so the convention above is the
  one the language already keeps, rather than a preference waiting to be
  applied. What is still hypothetical is a range as a *value*: there is no
  `#1:to(#5)`, and `toDo` takes the two bounds and a block instead.

## 3. Known limitations

Safe, and documented. Each is a real restriction rather than a bug.

**3.1 through 3.6 were chosen** — a decision taken and written down. **3.7, 3.8,
3.10, 3.11, 3.12, 3.13, 3.14, 3.15, 3.16 and 3.17 were not.** Each is a consequence of a decision taken elsewhere,
noticed afterwards, and each is kept here rather than in section 6 because the
ways of answering it cost more than what they buy is currently worth. That
distinction is worth keeping visible: a restriction chosen and a restriction
discovered ask different questions of whoever reads the list.

**The last three arrived together**, from writing
[the embedding interface](embedding.md) down. Stating what a host may rely on
means stating what it may not, and three of those turned out to be real
limitations that had never had a number — they were living in one document
while this one claimed to be the single list. Numbering them is what makes that
claim true again, and it is a use for writing a contract that nobody had in mind
going in: an interface document is an audit of everything it declines to
promise.

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

**Two shipped libraries have now hit it**, and what they wanted was narrower
than what this entry offers. [lib/json.sol](../lib/json.sol) and
[lib/html.sol](../lib/html.sol) both cite this number for a loop they could not
leave, and neither wanted to return from an enclosing *method* — they wanted to
stop a loop. That is [3.13](#313-a-loop-is-left-by-its-condition-or-by-failing),
which is a smaller thing that `^` would also answer.

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

**What changed, and what did not.**
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
lets a host bound how long a program runs and how much it holds, so a chunk that
spins forever need no longer spin *unboundedly* — `solvm --steps=N` ends it. That
does not touch what this entry says. The verifier still does not decide
termination and could not: proving a program stops is not a property of
well-formedness, and no amount of checking a file would make it one. A limit is
the other answer to the same problem — not knowing whether it will stop, and
stopping it anyway. Which is why it is a limit and not a proof, and why nothing
here is now promised that was not promised before.

### 3.4 No compatibility across `.sob` versions

Each format change bumps the version and older files are refused outright.

**It has happened three times.** Version 11 stood from 0.1.0 through nine
releases; 12 broke it to record which file each line came from
([6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done)), 13 to
record what each frame slot was called
([6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done)), and
14 to make the code stream little-endian like the rest of the file, which is the
only one of the three that bought consistency rather than a capability. So the
policy is no longer hypothetical, and what it turned out to be is:

- **Refuse, do not guess.** An older file is rejected by version with a message
  saying so, rather than read hopefully. That was already the behaviour and it
  is the half that matters, since misreading bytecode is how a verifier gets
  bypassed.
- **The remedy is to recompile**, which costs nothing: a `.sob` is derived from
  a `.sol` that is still there, and nothing here ships bytecode without its
  source.
- **`solvm --version` says which format a build speaks**, so the question "will
  this file run" is answerable without trying it.

What is deliberately *not* promised is reading old versions. A loader that
handled two formats would double what the verifier has to be right about, and
the thing it would buy — not recompiling — is worth less than that.

---

### 3.5 Recursion is limited to about 254 levels

`SOL_FRAMES_MAX` is 256 and a recursion level costs one frame, so 254 levels
succeed and 255 reports "call depth exceeded":

```
integer:down := { self:greaterThan(#0):ifTrue({ self:sub(#1):down }). self }.
#254:down:print.                     ; #254
{ #255:down }:onError({ e | e:message:display }).   ; call depth exceeded
```

**It was 62 until 0.23.0, and 30 before that**, and this entry was titled each of
those for longer than it was true. A level cost *two* frames at 30 -- one for the
method's block, one for the `ifElse` branch block carrying the recursive call --
and inlining conditionals (4.1) took the second away.

#### What moving it cost, which was the whole question

The cap had been left alone because raising it looked expensive: `SOL_STACK_MAX`
was `SOL_FRAMES_MAX * 256`, on the reasoning that a frame may hold 256 slots
since a slot index is a `u8`. A `SolVM` holds both arrays inline and lives on
the C stack -- `embed/host.c` and every test writes `SolVM vm;` -- so at 64
frames the machine was already 260KB, nearly all of it stack. Raising the cap
eightfold would have made a VM too big to put on a thread, where the default
stack is often 512KB.

**The two numbers did not have to be one number.** Frames are 56 bytes each; the
stack is sized on its own now, for how many values a program actually holds live
rather than for a worst case no program reaches. Both ends are checked and both
failures are ordinary catchable ones -- `call depth exceeded` at one, `stack
overflow` at the other -- so nothing became a crash that was not one before.

| | frames | stack | `sizeof(SolVM)` |
| --- | --- | --- | --- |
| before | 64 | 16,384 values, derived | 266,120 bytes |
| after | **256** | 16,384 values, its own number | **276,872 bytes** |

**Four times the depth for four percent more memory**, and the thread case is
untouched.

#### What it bought

| | before | after |
| --- | --- | --- |
| plain recursion | 62 | **254** |
| [evaluator.sol](../programs/evaluator.sol), brackets deep | 18 | **83** |
| [lib/json.sol](../lib/json.sol), levels of nesting | 28 | **124** |
| [lib/compiler.sol](../experiment/compiler.sol), nested blocks in a file it compiles | 9 | **41** |
| `.sol` files in this repository it compiles to `solas`'s exact bytes | 42 of 46 | **all 47** |

That last row is the one that mattered. The Solum compiler could not compile its
own source, and now it can: it compiles itself, and the compiler that comes out
compiles itself again to the same bytes.
[ideas.md](ideas.md#solas-written-in-solum--self-hosting) has that.

#### What is left

**This is still a limit**, and a deep enough program still meets it -- 254 is a
bigger number than 62 and not a different kind of number. What has not been done
is making the limit dynamic rather than a fixed array, which is what would
remove it rather than move it, and nothing has yet wanted that.

What makes it bearable, and was not obvious: **the failure is catchable.** `call
depth exceeded` arrives at `onError` like any other, is reported like any other,
and the program carries on afterwards -- running out of frames is exactly the
sort of failure a machine might not be able to recover from, and this one can.

#### Both halves of the compiler run out together

Worth keeping, because the first account of it was wrong. When the Solum
compiler could not compile four files, the parser was blamed and an explicit
stack in it was proposed. Splitting the compiler into
[lib/compiler.sol](../experiment/compiler.sol) so a tree nobody parsed could be handed
to it directly showed otherwise: parsing alone and compiling alone stopped at
**exactly the same depth**, about six frames a level each. Fixing one would have
bought nothing. The test that measured it is still in the suite, and it asserts
the shape rather than the number, so it survives the cap moving.

### 3.6 A caller-owned chunk must outlive blocks defined in it

Chunks from `sol_chunk_init` are freed by the caller. A block defined in one and
still reachable afterwards holds a pointer into freed memory, and calling it is
undefined. The collector itself is safe -- a block caches its owning cell, so
tracing never dereferences a freed chunk -- but nothing detects the call.

Solis avoids this entirely by using `sol_code_new`. It bites only code that mixes
caller-owned chunks with a long-lived VM, which today is the test suite.
Collapsing the two ownership modes into one would fix it, at the cost of giving
Solas a VM it otherwise does not need.

### 3.7 A limit bounds dispatch, not work

[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
counts instructions, and an instruction is not a fixed amount of work. A
primitive that reads a file, scans a string or joins an array does all of it
between one step and the next, so a program can spend an unbounded amount of
time and memory without spending steps.

[serve.sol](../programs/serve.sol) answers a request in 393 to 798 instructions
depending on which one, which is the sort of number a host would set a limit
from. It is also the number that stops meaning anything the moment a request can
name a file. Measured with the smallest program that shows it:

| program | steps | time |
| --- | --- | --- |
| `nil:print.` | 4 | — |
| `readFile` of 64MB, then `indexOf` over all of it | **8** | 0.27s |
| the same over 256MB | **8** | 1.10s |

The step count does not move with the size, because the size is not what it is
counting. Four of those eight are the four the empty program spends.

The memory ceiling is the same fact from the other side. It is checked in
`sol_gc_maybe_collect`, so an allocation is measured **after** it has been made:
under `--memory=1M` the 256MB read completes, and the program is stopped at the
next instruction holding 268,450,673 live bytes. It was stopped for going over
by a factor of 256, having already gone over by a factor of 256.

**What this does not undo.** A program still cannot loop forever, which is what
6.33 was for: an inlined loop spends a step per turn and the ceiling stops a
program that keeps what it makes. Both limits do the job they were built for.
What they do not do is bound the *cost of one request* — which is the number a
webserver wants, and the case 6.33 came from — because a single message can be
arbitrarily expensive.

**Two shapes of answer**, neither obviously right, which is why this is here
rather than in section 6:

- **Charge a primitive for what it handles**: `readFile` costs a step per
  kilobyte, `indexOf` a step per kilobyte scanned. That makes the limit mean
  work again, and it gives up the sentence the design leans on — that a step is
  one instruction and therefore countable without anyone deciding a rate. Every
  rate would be a number somebody chose.
- **Refuse the allocation instead of noticing it afterwards**: check the ceiling
  before a large allocation rather than after. That bounds the footprint
  properly and needs every primitive that allocates to unwind cleanly from the
  middle, which is a change to each of them rather than one to the collector.

**And the honest note**: this makes the caveat 6.32 already carries larger, not
different. A restricted script can still fill a disk or compute the wrong
answer; it turns out it can also spend a minute and a gigabyte inside a limit
that was set to stop exactly that. Found by writing
[serve.sol](../programs/serve.sol) and running it the way its own case would —
as a guest, with an allowance — which is a thing nobody had done to a program
here before, because every earlier program was run by the person who wrote it.

### 3.8 A host and a script agree a name, and nothing checks that they do

A host hands a script its input by binding a global and takes the answer back by
reading one — `sol_vm_set_global_text(vm, "request", ...)` on one side,
`request` on the other. Both sides have to say the same word. Nothing verifies
it, and getting it wrong fails as *undefined name 'request'* at run time, or, if
the host reads a name the script never bound, as a silent `NULL`.

This is the weakest joint in
[the embedding interface](embedding.md#what-is-deliberately-not-promised), and
it is a convention wearing a contract's clothes. It is written down as such
rather than dressed up.

**Why it is not simply a defect.** The alternative is a declared interface — a
script saying what it expects and what it produces — and that is a language
feature, not a C one. There is nowhere in Solum to write such a declaration
today, and inventing somewhere is a larger change than the problem justifies
while one person owns both sides of every call.

**The trigger is somebody else writing the script.** A host and a script written
by the same person can keep a convention. A host running a script it did not
write cannot, and that is
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)'s case
exactly — so if that entry is ever decided, this one is decided with it rather
than after.

**What is cheap in the meantime** and has not been done: a host could ask
whether a name is bound before running, and answer its own error rather than the
language's. `sol_vm_global` already answers false for an unbound name, so this
is a check a host may make and no help the interface gives it.

### 3.10 A VM cannot be reused across runs

It works, and it leaks meaning. Globals are one flat namespace and nothing
unbinds them, so a second run on the same machine sees everything the first one
bound — its variables, its methods on built-in classes, and its mistakes.

A host serving requests therefore builds a fresh VM per request, which is what
[embed/host.c](../embed/host.c) does and what
[embedding.md](embedding.md#what-is-deliberately-not-promised) says is the only
safe choice. That is not free: discarding a machine discards the interned names
and the built-in classes with it, so every request pays to build them again.

**Measured, and it is a third of a request.** On
[serve.sol](../programs/serve.sol) answering `/`:

| | debug build | `-O2` |
| --- | --- | --- |
| build a machine and free it | 52.3µs | 40.5µs |
| that, plus one whole request | 155.7µs | 121.0µs |
| **so the machine is** | **33.6%** | **33.4%** |

The ratio barely moves with the optimiser, which is what makes it a property of
the design rather than of the build: **a third of the time a host spends on a
request goes on rebuilding a machine that the last request had already built.**

For scale, compiling that script is 279µs at `-O2` — about twice a request, and
paid once. So the one-off cost of the flat namespace is nothing and the
per-request cost is a third of everything, which is the shape of the argument
for fixing this rather than the shape of an argument for tolerating it.

What it is not yet is a *problem*: 121µs a request is 8,000 requests a second on
one thread, and nothing here is serving any. The measurement is recorded so that
whoever needs it has a number rather than a feeling.

**It is the same flatness `@include` relies on**, seen from the side where it
hurts. An included file's globals are the includer's, deliberately, because a
module system with a namespace of its own is a much larger change to the object
model — see
[namespaces for included files](ideas.md#namespaces-for-included-files), which is
deferred for that reason and would answer this too.

**The narrower fix, if the wider one stays deferred**: something that resets a
VM to the state `sol_vm_init` left it in, cheaper than freeing and rebuilding.
The obstacle is that "the state it started in" is not currently a thing the VM
records — the built-in classes are ordinary objects with ordinary slots by the
time a script has run, and telling the ones it added from the ones it changed
would need a mark the collector does not keep.

### 3.11 A chunk cannot be shared between threads

**Settled by measurement**, which is what the entry said would settle it — it
read *"nothing is known about threads"* and *"what would settle it is a test,
not a design decision"* for about an hour. [tests/test_threads.c](../tests/test_threads.c)
is the test. It found two things, and only the first was the one it was looking
for.

**The serial was not atomic, and that is fixed.** `sol_vm_init` stamped each
machine from a plain `next_vm_id++` — a read-modify-write, so two threads
building a machine at once could be handed the same number, and a chunk they
shared would then believe it was already resolved for the second and dispatch
against the first's name table. The 0.14.1 use-after-free, reappearing inside
its own fix.

The window looked negligible and was not:

| | |
| --- | --- |
| machines built, 16 threads | 480,000 |
| duplicate serials, before | **10,319** — a rate of 2.1% |
| duplicate serials, after `_Atomic` | **0** |

Three instructions inside a `sol_vm_init` that takes 52µs, and it collided one
time in fifty. A contended increment is nothing like as brief as its
instruction count suggests, which is the part worth remembering.

**A chunk still cannot be shared, and no synchronisation inside the machine
would help.** Running a chunk *mutates* it: `sol_vm_intern_chunk` resolves the
names to whichever machine is about to run them and caches the result on the
chunk, freeing what the last one left. Two threads running one chunk free and
rebuild that table under each other.

| eight threads, one chunk, 2,400 runs | |
| --- | --- |
| runs concurrent | **segmentation fault** |
| runs serialised behind a mutex | **0 failures** |

So the fault is entirely in the sharing. A host *could* put a mutex around
`sol_vm_run`, and that serialises all execution, which is the opposite of why
anybody wanted threads.

**What is safe, and is now tested**: one VM and one chunk per thread. Source
text may be shared freely, because reading text mutates nothing — so threads
share the `.sol` and each compiles its own chunk. That is what the test does,
including with a collection on every allocation, since each machine owns its
heap and the collector never leaves it.

**Two threads in one VM is not supported and not tested.** A machine has one
stack, one heap and one frame array, and nothing guards any of them. There is no
plan to change that.

**What fixing the chunk would take**, if a host ever needs to compile once and
serve from many threads: the interned table has to stop living on the chunk. It
is per-VM state cached on shared data, which is the whole of the problem. Moving
it to the machine means a lookup per chunk on a path that is currently one array
index, and every nested method chunk has a table of its own — so it is a real
cost on the hottest code there is, for a use nobody has yet. Recompiling per
thread is **279µs once** — measured on [serve.sol](../programs/serve.sol) at
`-O2`, and see [3.10](#310-a-vm-cannot-be-reused-across-runs) for the numbers
around it. That is the trade, and it is not close today.

### 3.12 No shift can produce a negative integer

There is no unsigned integer type, and `shiftLeft` traps on overflow rather than
wrapping. So `#255:shiftLeft(#56)` is an error: as a *value* it is larger than an
i64 holds, whatever the bit pattern was meant to be. **No shift can put a one in
bit 63**, which is the whole of this entry.

It is a consequence of two decisions this project would take again — one integer
type, and arithmetic that refuses rather than silently wrapping
([strictness.sol](../examples/strictness.sol)) — and it costs almost nothing,
because arithmetic reaches what shifting cannot:

```
b:shiftLeft(#56)                    ; error, for any b of 128 or more
b:sub(#256):mul(#72057594037927936) ; the same number, every step in range
```

`b - 256` is between -128 and -1, so the product lands between INT64_MIN and
-2^56 and nothing overflows on the way. [disasm.sol](../programs/disasm.sol)
decodes every i64 in a `.sob` this way, INT64_MIN included, and agrees with
`solvm --dump` on all of them.

**This entry began as a much larger claim and was wrong.** disasm.sol reported
`<i64 too large to read>` for a day, and this page was about to record that
Solum could write an integer into a `.sob` that it could not read back — on the
strength of the shift failing. One route failing is not the number being
unreachable. Writing the limitation down is what forced the check that disproved
it, which is the second time in two days that has happened: the first was a
claim that `sol_vm_intern_chunk` had to be called by a host, also written up
before being tried.

**What is left to want**, and it is small: a way to say "these bits" rather than
"this number". A `bitPattern`-style reader, or an unsigned type, or shifts that
wrap. All three are larger than the arithmetic above, and only a program
assembling machine words from bytes wants any of them — which is one program,
which has a workaround, and which now carries the comment explaining it.

### 3.13 A loop is left by its condition, or by failing

A `whileTrue` body cannot end its own loop. Setting a flag ends it at the *next*
test, after the rest of the body has run, and the only exit from inside the body
is `error:raise` caught by an `onError` outside it — failure machinery doing
control flow's job.

That second route works, including out of a loop the compiler has inlined to
jumps, and [lib/json.sol](../lib/json.sol) already uses it for parse failure.
What it cannot be is *ordinary*: leaving a loop because you found what you were
looking for is not an error, and spelling it as one costs a handler on every
caller who must then tell a real failure from a deliberate exit.

**Nine sites carry the workaround, and two of them mention it.** Of 69
`whileTrue` sites across `lib/`, `programs/` and `examples/`:

| | sites |
| --- | --- |
| a `done` boolean whose only job is to stop the loop | **6** — `json.sol` ×3, `html.sol` ×2, `keys.sol` |
| an accumulator tested for the same purpose | **3** — `html.sol:97`, `expect.sol` ×2 |
| said anything about it | **2** |

The seven silent ones are the better evidence. A complaint is somebody noticing;
seven files reaching for the same shape without comment is an idiom.

The two that spoke:

> *"There is no early return (ROADMAP 3.2), so a loop that stops on a closing
> bracket carries a flag to stop it. It reads worse than a `break` would and it
> is the only shape available; both collections below have the same skeleton."*
> — [lib/json.sol](../lib/json.sol)

> *"The loop stops as soon as there is a match, which is the shape a `break`
> would have written more plainly."* — [lib/html.sol](../lib/html.sol)

**They are not equal weight.** `json.sol`'s `done` is pure overhead — a boolean
declared in three methods for no reason but to stop a loop. `html.sol`'s `found`
is the answer the method returns anyway, and testing it costs one send in the
condition. One is a wart; the other is a loop reading its own result.

**And a flag is sometimes right.** `html:closeThrough` sets `done` and then runs
`self:pop` deliberately — the rest of the body is wanted. A `break` there would
be wrong. Any answer has to leave that case alone.

**What an answer would cost, and the fork is the whole of it.** `whileTrue`
written literally compiles to jumps, so a `break` inside one is a jump the
compiler already knows how to emit. But `do`, `collect`, `select`, `repeat`,
`toDo` and `toByDo` are primitives that call a block per element, and there a
`break` needs a run-time signal from a block to whoever called it — which is
[3.2](#32-no-non-local-return)'s machinery, not something smaller. So:

| | |
| --- | --- |
| a jump-based `break` | works only in the spelling the compiler inlines — and the inlining is documented as *"an optimisation only; the meaning is exactly that of the message"*, so this would make a feature of it |
| a signal from block to caller | covers every loop, and is most of 3.2 |
| leave it | nine sites, seven of them content |

**Two things it may not be called.** `break` and `continue` are already Solid's
commands ([the reference](REFERENCE.md#the-keys) lists them), so a language
`break` collides with the toolchain's own vocabulary. And control flow here is
message sending — a `break` keyword would be the language's first control-flow
keyword, which is the objection that already refused
[`ifTrue{...}`](ideas.md#iftrue--a-block-argument-without-parentheses): it makes
a message send look like syntax exactly where the language works hardest to
prove it is not one.

**Recorded rather than answered**, and the shape an answer might take is in
[ideas.md](ideas.md#an-early-exit-from-a-loop) with a trigger — which now
includes a **working library prototype**: `{ ... }:forever` with `break` and
`continue` as messages on `boolean`, so nothing is a keyword and the first of
the two naming objections above dissolves. It costs 1.7× the flag idiom for a
`break` and 5.0× when a `continue` fires every other pass, because a skipped
iteration is a raise. Both sides of the fork below now have numbers. What would make
this urgent is a loop whose body must *skip its remainder* once the flag is set:
today every site either sets it at the tail of a branch or wants the rest to
run, and the moment one does not, the flag has to be threaded through the body
as `done:not:ifTrue({ ... })` and the workaround starts nesting.

### 3.14 There is no source of randomness

**No random number anywhere in the language.** Not on `system`, not on
`integer`, not in the library. A program that wants one writes a generator, and
the usual one cannot be written here at all: a linear congruential generator
relies on the multiplication wrapping, and integer arithmetic traps on overflow
instead. What works is Lehmer's, whose multiplier and modulus are chosen so the
product cannot exceed 64 bits — [bench.sol](../programs/bench.sol) carries one.
The seed can only come from `system:clock`, that being the only entropy a Solum
program can reach.

That is not a complaint about the trap, which is right. It is that **"write your
own generator" is narrower advice than it sounds** when the construction
everybody knows is unavailable for a reason that has nothing to do with
randomness.

**This entry was larger and is now this.** It read *there is no square root, no
minimum, and no randomness*, and the arithmetic half was answered — `sqrt` is a
message a float understands and `min`, `max` and `between` are in
[math.sol](../lib/math.sol). What that half cost is recorded below, because it
is the more useful half of the finding. It also stays the home for the rest of
the mathematics that is not here — `pow`, `log`, `exp` and trigonometry — each
deferred with a trigger at the end.

**Why `sqrt` became a primitive and the comparisons did not.** Both were
writable. `min` and `max` were written correctly the first time, in one line
each, and there is nothing to get wrong. `sqrt` was written **twice, and both
versions were wrong and silent about it**:

| | |
| --- | --- |
| twenty fixed iterations | Right to twelve places at 2, and `sqrt(1e10)` answered `100000.000156`. Newton converges quadratically once the guess is near; from `x` itself the approach is one halving per octave, so seventeen of the twenty iterations went before the good part began. |
| iterate until it stops moving, capped at sixty steps | Written to fix the first, and worse. The cap is needed, because in floating point Newton can settle into an oscillation between two adjacent values rather than a fixed point — but a value above about 1e21 has not finished halving in sixty steps, so the loop returns `x` divided by 2^60. `sqrt(1e300)` answered `8.67e281` rather than `1e150`. **Nineteen orders of magnitude, silently.** |

Getting it right means scaling by the exponent before iterating, which is asking
a script to know how a double is laid out. The C library already knows and is
correctly rounded, so the answer is one line of C and no lines of Solum.

**The second version was checked and passed.** Its 1e300 answer was printed and
read, and what the reading found was a bug in the *formatter* — the over-read
fixed in 0.21.0 — because 8.67e281 rendered at six decimal places is 157
characters out of a 64-byte buffer. The formatter was fixed, the digits were
compared against the C library, they matched, and the value they were the digits
*of* was never compared to anything. A wrong number can survive being looked at
carefully if what you look at is how it is printed.

**What is left, and why it is an entry rather than a commit.** A random number
is *state*, and this language has nowhere obvious to put it:

| | |
| --- | --- |
| on `system` | A machine stops being a value with no history, and two runs of one chunk stop being identical — which [embedding.md](embedding.md) currently promises. |
| in an object a program makes and holds | Honest, and it is `object:new` for something most callers want exactly one of. |
| seeded from where | The clock is not entropy, and there is no other source. |
| set by a host | Matters to anybody embedding: a reproducible run is worth more than an unpredictable one for most of what this language does. |

**Still not urgent**, and the reason is unchanged: ten programs came before the
one that wanted this, and it wanted it for how it measures rather than for what
it does. What would change that is a program wanting randomness for the work — a
sample, a shuffle, a simulation, a test that generates its own inputs.

**`pow`, `log` and `exp` are still not here either**, and were not added with
`sqrt`. C has them and they would each be a line, but no program in this
repository has asked for one, and *the ones a program has asked for rather than
all of `<math.h>`* is the rule this entry set for itself.

**Nor is there any trigonometry, or a `pi`.** Asked about directly, so the
answer belongs here rather than in a conversation.

The case for building it is the one that made `sqrt` a primitive, and it is
**stronger** rather than weaker. A hand-written sine fails the same silent way
and fails harder: the series is the easy half, and the difficulty is argument
reduction. Reducing `x` modulo 2π needs π to far more bits than a double holds,
so the obvious `x:sub(twoPi:mul(x:div(twoPi):rounded))` loses a digit of the
answer for every octave of the argument and is returning noise well before 1e16.
That is the same shape as the defect this entry already records — plausible
output, catastrophically wrong in a range nobody thinks to test, silent
throughout. If *a thing every program would get wrong the same way belongs in
the machine* is the rule, trigonometry meets it more clearly than `sqrt` did.

**What it is waiting for is a program, and that is all it is waiting for.** No
file here has ever wanted an angle. The first draft of this paragraph gave a
second reason — that the ten programs are text and process work, so geometry is
not what this language is for — and that reason is **wrong and is worth leaving
recorded as wrong**. The programs are the tools this project needed while
building itself; they describe what has been written, not what may be. Solum is
meant to be a general-purpose language, which
[design.md](design.md#what-the-language-is-for) now states outright, and no
entry in this document should be read as ruling a direction out because nothing
has gone that way yet.

So the trigger is ordinary: **a program that wants an angle** — a plotter, a
simulation, anything with coordinates or a waveform. When one arrives, the
sensible thing is to land trigonometry and `pow`/`log`/`exp` as a **single
decision** rather than a message at a time, since arriving one convenience at a
time is exactly what the rule above exists to prevent.

Three questions it raises that `sqrt` did not, worth having answered before a
program forces them:

| | |
| --- | --- |
| where `pi` lives | `infinity` and `nan` are globals, so `pi` would be the third — and the first that is not an IEEE special. `float:pi` as a class-side slot is the alternative, and the two read very differently on the page. |
| radians or degrees | Decided once and regretted afterwards, in every language that has chosen. C gives radians; the places a person types an angle by hand usually want degrees. |
| `atan2` belongs to neither argument | It takes two coordinates and there is no receiver that is obviously the subject, so `y:atan2(x)` reads badly in a language where the receiver is what the sentence is about. |

And a note on size, since it is the one argument that is about the shape of the
language rather than about the maths: `float` answers 21 messages today, and
`sin`, `cos`, `tan`, `asin`, `acos`, `atan` and `atan2` would be a third again.
That is a reason to add them deliberately and together, not a reason to refuse.

### 3.15 A child's streams cannot be redirected

`system:run` shares this program's stdout and stderr with the child.
`system:capture` keeps the child's stdout and answers it with the exit status.
There is no third thing, and in particular **no way to discard a child's stderr**
or to send either stream to a file.

Found by [bench.sol](../programs/bench.sol), where it is sharper than it sounds:
a benchmark harness must run a command many times without its output getting
into the report, and a command that complains on stderr writes straight over
that report through `capture`. The way round is the shell —
`["/bin/sh", "-c", "\"$@\" 2>/dev/null", "sh", ...]`, which passes the
arguments as positional parameters and so keeps the array's safety — and a
benchmark harness is the one program that cannot afford it: a shell is another
fork and another exec on **every measurement**, of the same order as the thing
being measured. So the program takes the noise instead, and the numbers stay the
command's.

What it costs everywhere else is smaller but real: a program that shells out to
something chatty has no way to quieten it, and a program that wants a child's
output in a file has to capture it and write it, which holds the whole of it in
memory first.

**The shape of an answer is the open question.** A fourth argument to `capture`
is the smallest thing that works and the least general. `system:capture` already
answers a dictionary; taking one — `system:capture(argv, ["stderr", "discard"])`
— generalises without new messages, at the cost of an options bag, which is a
shape nothing else in this language uses. Neither is obviously right, and
nothing is blocked while it stays undecided.

### 3.16 What the checker does not check

The odd one out in this section: it is about this repository's own verification
rather than about the language. It is here because this document claims to be
the single list of what is outstanding, and a gap in what `make test` proves is
outstanding.

[expect.sol](../programs/expect.sol) checks 589 claims across 40 files on every
build. Two kinds of thing in those same files are outside it.

**A fenced block that does not compile is not checked and not a failure.** It is
counted and reported — 42 of 155 blocks — and the classification is *continues
one further up, or shows syntax rather than a program*, both of which are real:
a `$ ./bin/solis` transcript is not a program, and a block that carries on from
the one above it cannot be run alone. But a block with a typo in it lands in
exactly the same bucket, and one did: **`README.md`'s opening snippet, the four
lines that introduce the language to everybody who arrives, was missing the `.`
after `a := #45`** and had been seen and skipped every run.

**Prose is not checked at all.** The checker reads comments in `.sol` files and
fenced blocks in `.md` files. A sentence that states a number — *"586 claims on
every build"*, *"`integer` has 24 slots"*, *"the fifth program here"* — is
outside both. The second of those was found because it also appeared in a block;
the first was stale for a day and was found by reading. Every count this
repository states about itself in a sentence has the standing that the examples'
comments had before any of this existed.

**And it happened again the day after this was written.**
[programs.md](programs.md) said *the nine files in programs/*, *one of these
seven*, and *what the seven have in common*, on a page describing ten programs —
three stale counts on one page, two of them wrong by three. Found by reading it
for another reason. That is the third instance, which is enough to say the
category is not hypothetical: **this document's third row, recomputing the
handful of counts the repository states about itself, is the one worth building
if any of them is.**

**A claim on a line that does not itself print is not checked either**, and this
one was found by writing [CHEATSHEET.md](CHEATSHEET.md), which is 64 examples on
one page and so met every edge the checker has. A block that ends

```
point := object:new.
point:x := #3.
point:show := { self:x:print }.
point:show.                     ; #3
```

runs, prints `#3`, and checks nothing: the expectation is read from the line
that *says* `print` or `display`, and here the printing happens inside the
method. The same goes for a second and third line of output written under the
first — only the first carries a claim. **The checker says so** — it counts
those lines and reports *N lines print without saying what, and are not
checked* — so this is a milder thing than the two above, which is why it is a
paragraph rather than a row. But a page of sixty examples makes it easy for one
to drift into that bucket, and the fix on the document's side is to write the
example so the printing line is the claiming line.

**What an answer would cost.**

| | |
| --- | --- |
| a marker for a block that is deliberately not a program | Smallest, and it puts the work on every document. A fence could be ` ```text ` where it is not Solum, and then a block that *claims* to be Solum and does not compile is a failure. The cost is that the convention has to be applied to 42 blocks before it can be enforced on the 43rd, and a document is a bad place to be strict about something a reader cannot see. |
| report the two categories separately | Cheap and partial: *continues one above* is detectable (the block does not compile *and* the one before it exists), where *does not compile at all and starts a new thought* is the suspicious case. It would have caught the README. It would not catch a block that compiles and is wrong about what it prints, but that case is already checked. |
| check the prose | Not obviously possible, and probably not worth it. A number in a sentence has no notation saying what it counts. What is available is narrower and might be enough: this repository states a handful of counts about *itself*, and a test could recompute those and grep for a stale one. |

**Nothing is blocked**, and the reason it is written down rather than fixed is
that the second column is a judgement about documents rather than about code,
which is yours. What the entry preserves is the specific failure: the category
that keeps a checker honest about what it cannot check is also the place a real
fault can hide.

### 3.17 A global is found by walking a list

`OP_GLOBAL` resolves a name by walking the root object's slots and comparing
interned pointers — `sol_object_lookup_interned` in
[object.c](../solum/src/object.c). It is **linear in the number of globals**,
and exactly linear. One million reads of a name with `n` globals ahead of it:

| globals ahead | time |
| --- | --- |
| 0 | 0.034s |
| 100 | 0.156s |
| 200 | 0.299s |
| 400 | 0.590s |
| 800 | 1.111s |

About **1.35ns per slot walked**, so at 800 globals a read costs 16× what
pushing a constant costs.

**And the order is recency**: a new slot goes on the front of the list, so the
name a *library* bound first is the slowest to read and the one the program
bound last is the fastest. That is the wrong way round for the case it matters
in — a library's constant, read in somebody's loop.

**Nothing here is slow because of it**, which is why this is a limitation rather
than a defect. A real program's root holds the 15 built-in globals plus what it
binds: 23 in [expect.sol](../programs/expect.sol), 14 in
[serve.sol](../programs/serve.sol), 1 in `lib/html.sol`, which a library binds
once and hangs everything else off. At 38 globals a badly-placed read costs about
50ns and a well-placed one about 2ns. The 16× wants 800 globals, and nothing here
has 40.

**Two ways out, and both help every read.** A hash on the root object, which is
what every other name table in the VM already is; or an inline cache at the
`OP_GLOBAL` site, since the answer for a given site almost never changes. Either
speeds up every global in every program, which is the argument that decided
against the alternative — see
[constants](ideas.md#constants-and-whether-they-should-be-a-thing) in ideas.md,
where a compile-time constant would have sped up only the names somebody
remembered to declare.

**How this was found is worth recording**, because it was not found by anything
being slow. It came out of asking whether the language should have constants:
the case for them is that a constant is faster than a global, which is true, and
measuring *how much* faster turned up the reason rather than the number.

### 1.1d Collection is stop-the-world and non-incremental

Fine at this size and not worth touching yet. Noted so it is a choice rather than
an oversight: a program holding a large live set will pause proportionally to it.

Kept here rather than under the collector, which is otherwise done. The number is
the one the changelog cites.

## 6. Beyond the language — gone from this document

Sections 1 to 5 were about making Solum a language. This one was about making it
a language you can write a *program* in: split across files, reading input,
writing files, stopping with a status, running another program, a prompt, a
debugger. **All of it is built**, and the entries are in
[COMPLETED.md](COMPLETED.md).

The one thing that was left was never work — it was a decision, and it has been
**deferred rather than taken**:
[6.32, a script cannot be run with less than the whole machine](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine),
now in [ideas.md](ideas.md) with the rest of what is deferred with a trigger.

It went there because of what it was: a concern raised about a use nobody has —
a webserver running Solum, where injection could make untrusted input into code
the server runs — rather than anything a program wanted and could not have. This
is an experimental language and was never planned for web services; the question
was asked because it *might* become a thing, not because it is one. The
reasoning, the threat model and everything the last four days added to it are
kept in full, because deciding it later from a blank page would cost more than
keeping it did. The number stays 6.32 and is not reused.

## How this list emptied

**Nothing is on it.** Sections 2, 3 and 6 held the whole of what was left to
decide or build, and 2 and 6 are done — what remains in 3 are restrictions kept
on purpose, each documented where a program would meet it.

That is worth a paragraph, because *how* it emptied is the part that transfers.

**Section 6 came from the right place**: notes about what a program would want,
rather than a plan written before there were any programs. And once those ran
out, every further entry arrived the same way — somebody wrote a program and
found out what it wanted.

- [log.sol](../programs/log.sol) asked for a **dictionary** and **array
  slicing**, and got both.
- [evaluator.sol](../programs/evaluator.sol) found the **frame limit**, and that
  it is catchable.
- [manifest.sol](../programs/manifest.sol) and `lib/json.sol` found that a
  **byte had no number** — for text rather than for the binary files the entry
  had been written about — and put a price on how the value dispatch is written.
- [page.sol](../programs/page.sol) and `lib/html.sol` found that **an array
  cannot be popped**, and that the frame limit is about traversal rather than
  about data.
- [mirror.sol](../programs/mirror.sol) found a **defect in `modifiedAt`**, and
  asked for a file's mode and time.
- `lib/text.sol` broke a program **from a distance** by claiming a common global
  name, ten minutes after the entry saying that could happen was written.
- [serve.sol](../programs/serve.sol) found that **a limit bounds dispatch and
  not work** (3.7), and that the permission a webserver cannot do without is the
  one that hands over its secrets — which is the first argument 6.32 has for
  capabilities finer than one per message. The first program here whose input
  does not come from whoever ran it.
- [expect.sol](../programs/expect.sol) found that **nothing had ever checked
  the examples' own comments** — about four hundred claims about what each line
  prints, true because somebody once looked. All of them hold; what was wrong
  was that three different comment conventions had grown up unnoticed. It runs
  in `make test` now.
- **`lib/json.sol` and `lib/html.sol` between them** found that **a loop cannot
  be left from inside its body** (3.13) — each carrying a boolean to stop one,
  and each saying so. Counting the idiom afterwards found seven more sites that
  had never mentioned it, which is the better evidence.
- [bench.sol](../programs/bench.sol) found that **there is no square root, no
  minimum and no randomness** (3.14) — all of them writable, and the point is
  what writing them costs: the `sqrt` written here was wrong **twice**, and both
  times said nothing, which is why it is a primitive now and `min`, `max` and
  `between` are only a library. The textbook random generator cannot be written
  here at all, because integer arithmetic traps on overflow rather than wrapping,
  and that half of the entry is still open. It also found that **a child's
  streams cannot be redirected** (3.15), and, by testing its own square root at
  1e300, **a stack over-read in the float formatter** that let a script print the
  bytes behind a buffer. The first program here written to press on a gap rather
  than to do a job.
- [disasm.sol](../programs/disasm.sol) found **three faults in this project's
  own documents** by being a second implementation of a format that had one:
  BYTECODE.md gave no opcode numbers, design.md said both "big-endian" and
  "little-endian throughout" about the same bytes in different sections, and the
  `.sob` format table had been missing three sections since version 12. All
  three are fixed, and the opcode numbers now have a test. It also found that
  the language can write an i64 into a file that it cannot read back.

**Four of the entries were papercuts a library tripped over**, not things anybody
reasoned out in advance:
[6.19](COMPLETED.md#619-a-symbol-cannot-be-ordered--done),
[6.21](COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done),
[6.22](COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done)
and [6.23](COMPLETED.md#623-an-array-cannot-be-popped-or-asked-what-it-holds--done).

**The last four came from a different question**: not *what does a program want*
but *how would one be debugged*. They had to be done in order, and the order was
the useful part — `solvm --trace`, then
[6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done) because a
trace that could not name a file was misleading rather than thin, then
[6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done) because
a debugger that could not name a local would have been most of the work for a
fraction of the use, and only then
[Solid](COMPLETED.md#629-a-stepper--solid--done).

**No decision is outstanding.** 2.5, the last *language* question, is closed:
1.6 had answered it one message at a time to stop the crashes, and finishing
that — every class-side message requiring an object receiver — turned out to be
the whole of what splitting the two objects would have bought. And 6.32, the
last one of any kind, was deferred to
[ideas.md](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
rather than answered, which is a decision about a decision and the honest one:
it guards against a use nobody has.

**A new entry means a program wanted something and could not have it** — or,
twice, that something became possible and wanted a decision about it.
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine) came from
noticing what `system:run` had opened up rather than from anything going wrong,
and
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
came from asking what 6.32 would not cover. The second turned out to be
buildable without deciding anything, and was built; the first turned out not to
need deciding yet, and went to the idea box.

Those two arrived a third way, worth naming because it is the one this document
did not have before: **from a use nobody had written yet**. Not a program that
wanted something, but a description of where the language might end up — inside
a webserver, with untrusted input reaching it — which asked questions the
existing programs could not, because every program so far was run by the person
who wrote it. The measurement in 6.33 exists only because that question got
asked; on a command line nobody would have thought to take it.

That aside, wanting is how they have all arrived, including the two after the
list emptied:
[6.30](COMPLETED.md#630-a-program-cannot-run-another-program--done), because a
language for scripting an OS that cannot invoke another program is working with
one hand, and
[6.31](COMPLETED.md#631-text-from-another-program-arrives-padded--done) within
the hour, because `wc -l` answers `"     100\n"` and `asInteger` will not have
it. Both are built.


[ideas.md](ideas.md) records what was considered and turned down, so the same
arguments do not have to be had twice, and [COMPLETED.md](COMPLETED.md) records
what was built, so the reasoning does not leave with the entry.
