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

**What is left is section 3, and one decision.** Section 3 holds the
restrictions the language lives under on purpose, each documented where a
program would meet it. Section 2 has no open design question — the last one,
2.5, is closed. And section 6, a program's dealings with the world outside it,
is built: reading input, writing files, stopping with a status, walking the
filesystem, knowing the time, a prompt with history, a debugger, and running
another program.

The decision is
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine): whether a
script should be able to run with less than the whole machine, now that it can
reach all of it. Nothing is asking for it; it is recorded because the shape of
the answer is much cheaper to choose now than later.

Its other half is built.
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
was the same webserver's other problem — a script that never finishes is a
request that never finishes — and is now a step limit and a memory ceiling a
host sets before the program runs. Permissions are still a decision; limits are
not.

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

**It has happened once, at 0.9.0 to 0.10.0.** Version 11 stood from 0.1.0
through nine releases, and 12 broke it to record which file each line came from
([6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done)). So the
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

**One entry**, and it is a decision rather than work waiting to be done.

Raised in a notes file and assessed in [ideas.md](ideas.md), which also records
what was **not** worth building and why — integer widths, a JIT, cascades,
trailing-block syntax, and Go-style concurrency among them.

### 6.32 A script cannot be run with less than the whole machine

Everything a program can reach, it can reach: run another program, delete a
file, write anywhere it has permission to. That is right for a script somebody
wrote for themselves and wrong for one that arrived from elsewhere, and there is
currently no way to say which this is.

The shape suggested is a **restricted mode**, with the dangerous messages
refusing, and a flag to allow them.

**The case this came from is an embedding, not a shell.** A webserver that
produces pages by running Solum, where the risk is injection — untrusted input
reaching the program and becoming part of what it runs. The one choosing the
restriction is the webserver, and what it is protecting is itself.

That is a different shape from a person running a script they were sent, and it
moves three things.

*Who chooses, and how often.* Not somebody at a prompt who may not think to
ask, but a program that decides once, at startup, and then runs the same policy
over every request for as long as it is up. A server author thinks about this
exactly once and deliberately, which weakens the argument that the protection
must be on before anybody considers it — and strengthens a different one: **the
restriction has to be settable from C, before the program runs.** A `--unsafe`
argument is one front end for that, not the mechanism. If the mechanism is argv
parsing, the case that asked for it cannot use it.

*What is untrusted.* Not the file — the server wrote that. The **data**. So the
permission cannot be attached to where the code came from, or decided per file:
it is a property of the run, fixed before the first instruction and the same
for everything the program subsequently reaches.

*And embedding is not a documented use today.* The headers make it possible and
nothing claims it: no page says how to hold a `SolVM` inside another program.
Deciding this is therefore also deciding to have an embedding interface, which
is the larger of the two and should be admitted up front rather than discovered
halfway.

**Which way round is the default** still matters for the command line, where the
chooser is a person. Safe-by-default with `--unsafe` to enable protects the
script you did not write and breaks every existing use, including this
repository's own tests and `examples/tools.sol`. Unsafe-by-default with `--safe`
breaks nothing and helps only the people who remember to ask. For a person, that
argues for safe-by-default and for paying the breakage; for an embedding it
barely signifies, since the host states what it wants either way.

**What "dangerous" means is two things, not one.** The suggestion names the
messages that *change* the machine, and there is a second set that *reveals* it:

| | messages |
| --- | --- |
| changes | `run`, `capture`, `remove`, `makeDirectory`, `rename`, `writeFile`, `appendFile`, `setMode`, `setModifiedAt` |
| reveals | `readFile`, `filesIn`, `isDirectory`, `fileExists`, `fileSize`, `modifiedAt`, `modeOf`, `environment` |

Reading `~/.ssh/id_rsa` and printing it changes nothing and is not safe.
`environment` alone will hand over a token from half the CI systems there are.
So a mode that only stops writing is a mode that stops the obvious half — and
in a server the revealing half is the worse one, since the process it is
running inside holds the credentials the pages are built from.

`system:exit` was in the first list and has been taken out of it: it sets a flag
the interpreter loop unwinds on and `sol_vm_run` answers `SOL_EXIT`, so a script
that exits ends *itself* and hands the decision back to whoever called. A
webserver stays up. That is already the right behaviour and is worth naming
here, because it is the one an embedding would most expect to be wrong.

That suggests **capabilities rather than a switch** — something nearer
`--allow-read --allow-run` than one flag — which is more useful and more work,
and the embedding case wants it: a template renderer wants to read files and
never to run a program, which one boolean cannot say.

**A complication worth knowing before starting**: `@include` reads files, and
the search path reads the shipped library. A mode with no reading at all cannot
compile a program that uses `lib/json.sol`, so reading the *program* is not the
same permission as reading *a file the program names*, and the line runs between
them rather than around `readFile`.

**Enforcement is cheap and must not be reachable from inside.** A flag on the VM
and a check in each primitive costs a branch on messages that are already doing
system calls. What matters more is that there is no message to turn it off:
whatever sets it must be the host, before the program runs, or the whole thing
is a suggestion.

**And it is not a sandbox**, which is the thing to say loudest, because "safe
mode" invites more trust than it can earn. A restricted script can still loop
forever, allocate until the machine swaps, fill a disk through a file it *is*
allowed to write, or simply compute the wrong answer and be believed. It stops a
script reaching for the machine; it does not make a hostile script harmless.
This is the same honesty as
[3.3](#33-verification-does-not-promise-termination), which says the verifier
proves a chunk is well-formed and not that it stops.

The webserver case is what makes that caveat expensive rather than academic: on
a command line a program that does not stop is an annoyance, and on a server it
is the server. That half was
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
and is built: a host may now say how many instructions a program gets and how
much it may hold. It was a different decision — limits, not permissions — which
is why the two were separable, and why one of them could be settled while this
one is still being thought about.

**Raised after the fact**, by noticing what `system:run` had made possible
rather than by anything going wrong; the embedding case above was supplied the
following day as the reason it had occurred to anybody. Nothing is asking for it
yet, and it is written down because the decisions above — where the mechanism
lives, which default, capabilities or a switch — are much cheaper to take now
than after somebody has written scripts that depend on either answer.

## How this list emptied

**Nothing is on it.** Sections 2, 3 and 6 held the whole of what was left to
decide or build, and 2 and 6 are done — what remains in 3 are restrictions kept
on purpose, each documented where a program would meet it.

That is worth a paragraph, because *how* it emptied is the part that transfers.

**Section 6 came from the right place**: notes about what a program would want,
rather than a plan written before there were any programs. And once those ran
out, every further entry arrived the same way — somebody wrote a program and
found out what it wanted.

- [log.sol](../examples/log.sol) asked for a **dictionary** and **array
  slicing**, and got both.
- [evaluator.sol](../examples/evaluator.sol) found the **frame limit**, and that
  it is catchable.
- [manifest.sol](../examples/manifest.sol) and `lib/json.sol` found that a
  **byte had no number** — for text rather than for the binary files the entry
  had been written about — and put a price on how the value dispatch is written.
- [page.sol](../examples/page.sol) and `lib/html.sol` found that **an array
  cannot be popped**, and that the frame limit is about traversal rather than
  about data.
- [mirror.sol](../examples/mirror.sol) found a **defect in `modifiedAt`**, and
  asked for a file's mode and time.
- `lib/text.sol` broke a program **from a distance** by claiming a common global
  name, ten minutes after the entry saying that could happen was written.

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

**No decision is outstanding.** 2.5, the last one, is closed: 1.6 had answered it
one message at a time to stop the crashes, and finishing that — every class-side
message requiring an object receiver — turned out to be the whole of what
splitting the two objects would have bought.

**A new entry means a program wanted something and could not have it** — or,
twice, that something became possible and wanted a decision about it.
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine) came from
noticing what `system:run` had opened up rather than from anything going wrong,
and
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
came from asking what 6.32 would not cover. The second turned out to be
buildable without deciding anything, and was built; the first is still a
decision.

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
