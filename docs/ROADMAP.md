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

**A capability the machine does not have can be loaded into it** rather than
grown: [extensions](extensions.md) are C compiled on its own, named with
`--extension=` when a program starts and never from inside one. A resource an
extension owns is a value the collector gives back, on the sweep and at
teardown. Two bundles live out of tree —
[GTK4](https://github.com/hansolovkarlsson/solveig-gtk) and
[SDL2](https://github.com/hansolovkarlsson/solveig-sdl) — which is what keeps
*no dependencies beyond a C11 compiler and `make`* true.

**Both draw now, and the GTK one is the mechanism's first real re-test.** A
canvas arrived there on 2026-08-30: a widget whose content is a callback GTK
drives on its own schedule, which is a different *kind* of callback from the
click and the timer the retain registry was built for. It needed nothing new —
the same registry, the same re-entry, the same limit checks. That bundle's
README had predicted exactly this, in the form *the expensive work was
per-toolkit rather than per-function, and it is done*, and the canvas is the
first case that could have falsified it.

**One ships here**, and for the same sentence read the other way:
[net](NET.md) is UDP sockets, and sockets need POSIX rather than anything a
reader would have to install. `make` builds it, `make install` puts it beside
the library, and no program has networking until a host names `--extension=`.
The language answers the same messages it did before it existed.

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

**One entry opened and closed on 2026-08-26**, which is the shortest life any
has had: [6.36](COMPLETED.md#636-readline-and-readkey-did-not-share-an-input-buffer--done)
— `readLine` and `readKey` read the same input through two buffers and lost what
fell between them. It was found by reading the code beside a message being
built, where a comment claimed the problem was already handled and it never had
been. It is one window now, Solis reading through it too.

**Section 3 is what is left, and nothing on it is open.** One program put three
entries there and all three are closed: two on the day they were raised and the
third on the next.
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done) spent its whole
life waiting for a program that wanted an angle;
[basic.sol](../programs/basic.sol) was one, wanting six of them and an exponent
operator because they are in the standard it implements. It was decided rather
than deferred — eleven messages, landed as one set — and is
[done](COMPLETED.md#314-the-mathematics-that-is-not-here--done).

The same program's `INPUT` then found
[3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done) —
no way to write to standard output without ending the line, so a prompt could
not sit beside its answer. That one was work rather than a decision, and it is
`system:write` now.

**And then the same program found a third**, an hour after the list had emptied:
[3.19](COMPLETED.md#319-a-program-cannot-write-to-standard-error--done), no way
to write to standard error, so a listing that fails put its diagnostic in the
output file. That is `system:writeError` now. Three entries from one program,
all three closed — the mechanism this document describes running at speed rather
than an exception to it, and a fair warning that *empty* is a description of a
moment rather than a destination.

**And the next entry arrived the same way, from a program written to find out
what it would want.** [edit.sol](../programs/edit.sol) is a terminal editor, and
[ideas.md](ideas.md#programs-that-would-press-on-something) had written down
before it existed what it would find: *nothing lets a program ask the terminal
its size*. It found that in its first hour, and
[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done)
closed it the same day — `system:terminalSize`, one message answering both
numbers, nil when there is no screen. The prediction having been written first
is the part worth keeping: it is what would have made *it found nothing* a real
answer rather than a disappointment.

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

Section 2 has no open design question — the last one, 2.5, is closed. Section
6, a program's dealings with the world outside it, is nearly all built: reading
input, writing files, stopping with a status, walking the filesystem, knowing
the time, a prompt with history, a debugger, and running another program.
**Nothing is open on it.** The last two entries were both raised on 2026-09-02
by [diff.sol](../programs/diff.sol):
[6.45](COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done) closed
on 2026-09-04 as `system:readUpTo(#n)`, the only entry here whose open question
was a **name** and which therefore could not be closed by anybody but you, and
[6.44](COMPLETED.md#644-an-instant-cannot-be-written-in-local-time--done) closed
on 2026-09-12 as `system:utcOffset(t)`, eight days after the roadmap called it
not urgent, on the day it was shown that the wrongness it waited for was on
every file untouched since March.

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

**The way to add to this document is to write a program and find out what it
wants**, which is how nearly every entry since the first dozen arrived —
several of them from a library breaking rather than from anyone reasoning about
the design, and the two newest from a `diff` that had to reproduce another
tool's bytes from a pipe.

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

  **The globals are further out of reach than "reflection cannot write" says.**
  A slot can be read by computed name (`slotAt`) and a message sent by one
  (`perform`); a global can be reached only by writing its name literally, in
  either direction, because the object holding the globals has no name in the
  language — `object` is the root *class*, a different object. So there is no
  reading a global by computed name either, which is a gap the sentence above
  does not cover. Nothing here has wanted one: no file in `programs/` or `lib/`
  uses `perform` at all. The trigger would be a program that does — an
  interpreter with an environment, a debugger handed a name, a serialiser. See
  [design.md](design.md#why-binding-is-syntax-and-not-a-message) for why binding
  is syntax in the first place.

  **The narrow form arrived on 2026-09-15, from a fourth shape the list above
  did not name: a database row.** `object:new(dictionary)` makes a fresh object
  with a slot per pair, the names from the dictionary's keys, at construction
  and never after; [the entry](ideas.md#the-database-as-objects-and-the-first-slot-made-from-a-run-time-name-scoped-2026-09-15)
  weighed it against a full `slotAtPut` and against rows as dictionaries, and
  built it after the dictionary version had run so that the program asked and
  not the page. 6.15's two arguments were weighed again: the name leak is
  bounded by a schema where it was not by a file of keys, and the linear walk
  is what a slot index already answers past twelve slots. What this entry says
  still holds for everything after construction: no `slotAtPut`, no removal, no
  re-parenting, and no global by computed name.
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
  `#1:to(#5)`, and `[#1,#5]:loop` takes the bounds as an array instead.

## 3. Known limitations

Safe, and documented. Each is a real restriction rather than a bug.

**3.22 is gone from here**, and it is the one whose trigger fired rather than
being argued away. It said a file is read whole or not at all, and named its own
trigger as *a program with a file that does not fit* — which nothing here had,
until somebody made one. A sparse file is 3 GB and 8 KB of disk, and on one of
those `fileSize` answered and `readFile` refused: the language could measure a
file and not read a byte of it. `readFile(path, from, count)` is a **range
rather than a handle**, which is the shape the entry had already argued for and
which held up.
[COMPLETED.md](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) has
the account, including the order it was nearly built in and why that was wrong.

**3.27 was here for an afternoon**, raised on 2026-09-15 from the first
program to want a positioned write and closed the same day as
`writeFile(path, from, text)`, the mirror of the read. It is the second entry
in this section whose trigger fired rather than being argued away, and it is
in [COMPLETED.md](COMPLETED.md#327-a-file-is-written-whole-or-appended-to-and-nothing-in-between--done)
with the table that closed it.

**3.20 and 3.21 are gone from here too.** 3.20 opened and closed on the same
day — the only entry whose answer was partly *don't*: `shell` publishes four
names, all four are the API, and a boundary listing them would have hidden
nothing. 3.21 was the second entry here about this repository's own verification
rather than about the language, after 3.16, and it closed the way it said it
would: the weaker guard, which reads a heading rather than asking git, so a
tarball with no `.git` in it goes on checking clean.

**3.9, 3.15, 3.16 and 3.17 are gone from here** and are in
[COMPLETED.md](COMPLETED.md#3-known-limitations). 3.15 closed by giving `run`
and `capture` an optional second argument saying where the child's streams go,
which is the entry that had named two possible shapes and picked neither — and
the half that decided it was the half the entry never mentioned, that a child
could not be given anything to read either. 3.16 was the odd one out —
about this repository's own verification rather than about the language — and it
closed by reading a document as a document, failing on a block that will not
run, and giving a number in a sentence a notation saying what it counts. 3.17
closed by giving an object with more than a dozen slots a table beside its list,
which turned out to be worth more to *sends* than to the globals it was written
about.

**3.1 through 3.6 were chosen** — a decision taken and written down. **3.7, 3.8,
3.10, 3.11, 3.12 and 3.13 were not.** Each is a consequence of a decision taken elsewhere,
noticed afterwards, and each is kept here rather than in section 6 because the
ways of answering it cost more than what they buy is currently worth. That
distinction is worth keeping visible: a restriction chosen and a restriction
discovered ask different questions of whoever reads the list.

**3.23 to 3.26 arrived together on 2026-09-15, and none of them is new.** All
four were found by Parasol between 2026-08-31 and 2026-09-13, while it was a
repository of its own, and were written up in its
[notes on Solveig](PARASOL-SOLVEIG-NOTES.md) as a log *kept there rather than
raised here*, to be taken into this numbering when somebody decided they were
worth taking. The day the log became a page of these documents, *there* and
*here* became one place, and a list of open defects that is not on the single
list makes the single list false. So they are numbered, and the account of
each stays where it was written. Each still reproduces on the tree of that
day. None is a blocker, and each is small: the four together are the shape of
what a second customer sees that the first does not, a compiler and a machine
driven from a command line by something that generated their input.

**The last three before those arrived together**, from writing
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

**And the decision this entry said it would want was made on 2026-08-30**, in
[ideas.md](ideas.md#what-a-string-is--bytes-code-points-or-bytes-with-a-contract):
bytes, with code-point *messages* where a program needs them, rather than a
string that counts characters or a second text type beside this one. The case
was settled by the editor — the one program that asked for Unicode asked for it
locally, in the two places facing a screen, and answered itself with three sends
the language already had. Its cursor is a byte index because `copyFrom` takes
byte indices, and every edit is a `copyFrom`; a `size` that counted code points
would have taken that away.

So this entry stays exactly as it is, and is now a restriction with a reasoned
floor under it rather than an open question. What would still change it is a
second program wanting character arithmetic.

### 3.1 Capturing blocks cannot escape their frame

A block that reads or writes its home frame is tied to it. Calling one after that
frame returned is reported — "block outlived the frame it was written in" —
rather than reading slots that now belong to someone else. Non-capturing blocks
escape freely, which covers `{ #42 }` and most conditional branches.

Real closures need the captured slots promoted to the heap when a frame dies.
That is the upgrade path; the frame-id check is what makes today's restriction
safe rather than silently wrong.

#### Settled by Pascal, which is the language this entry describes

**2026-08-27.** [pascal.sol](../programs/pascal.sol) reached nested procedures,
and the prediction written into
[ideas.md](ideas.md#programs-that-would-press-on-something) before the stage was
started held exactly:

> A capturing block may not outlive the frame it was written in. A Pascal nested
> procedure may not be called after its enclosing procedure has returned. Those
> are the same sentence.

They are. A nested procedure is compiled to a block made **inside its parent's
activation**, so `OP_BLOCK` captures the right frame and `OP_OUTER depth slot`
reaches the right variables — and the block is unreachable the moment the parent
returns, because the only thing holding it was a slot of that frame. **Nothing a
conforming Pascal program can write reaches the restriction**, which was the
falsifiable half, and it stayed unfalsified through nesting two levels deep,
through recursion of the enclosing procedure, and through a nested procedure
writing an enclosing `var` parameter.

**So this entry is not a limitation for that language, it is its scoping rule.**
That does not close the entry — Solum is not Pascal, and a Solum program can
still write a block that outlives its home and be told so. What it does is say
what the restriction *is*: not an accident of the implementation, but the rule
a language with lexical nesting and no first-class functions already has.

**And the second prediction held too**, which is
[3.5](#35-recursion-is-limited-to-about-254-levels)'s business rather than this
entry's: `OP_OUTER` needed nothing added. Fourteen Pascal programs agree with
`fpc -Miso` byte for byte, and the nested ones are **the first blocks this
repository has produced that set the capture flag at all** — `sola.sol` has
never emitted one, SolaBasic having no nested procedures.

**A program predicted to hit this did not, and that is worth as much as one that
did.** [ideas.md](ideas.md#programs-that-would-press-on-something) had a parser toolkit down as the
most interesting thing on its list *because* either answer would be informative:
it would give this entry its first customer, or it would show that a
non-combinator design is fine and the restriction is livable.
[check_syntax.sol](../programs/check_syntax.sol) was built on 2026-08-26 and
never came near it.

**Not because it was worked around.** The design that avoids this entry is the
design the job wanted anyway: a grammar is a tree of objects and the matcher is
one method that recurses over it, so nothing is ever a block that has to outlive
the frame it was made in. The combinator shape — a matcher that *answers*
another matcher — is the one this entry refuses, and it was never reached for.
[lib/scan.sol](../lib/scan.sol) arrived at the same place from the other end and
says so in its own comments: a cursor is an object because the combinator form
is not available, and the spelling the language allows is the one that was
wanted.

So the second outcome, and the entry stays as it is. Real closures remain the
upgrade path, and nothing shipped here has yet needed them.

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

**And on 2026-08-26 a program hit the entry itself**, rather than the loop half
of it. [programs/edit.sol](../programs/edit.sol)'s key dispatcher decides what a
key is — an operator, a motion, an action — and the first branch that answers
wants to *stop the method*, not a loop: `dd` having been handled, nothing after
it applies. It carries a `done` flag and wraps the remainder in
`done:ifFalse({ ... })`, which is the same workaround the libraries wrote for
the smaller case. **This is the local case rather than the non-local one** — the
method wants to leave its own body, not an enclosing frame — and it is worth
recording because a chain of *this key, else that key* is a shape every dispatch
table has, and the flag grows one nesting level per branch.

**And on 2026-09-01 a second program hit the entry itself**, at a rate the
first did not. [programs/awk.sol](../programs/awk.sol) wanted it three separate
times in one file, and `^` was written three times before remembering it is not
there. An interpreter dispatching on a tag is the shape that wants to answer and
leave: without it, `evalBinary` guards every arithmetic branch against having
already settled `~`, and five unwinding statements become five flags. It is the
same local case `edit.sol` found, three sites in one file rather than one, and
it arrived unpredicted by
[the scoping](ideas.md#programs-that-would-press-on-something) whose whole job
was to say what awk would want.

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

**And on 2026-09-01 this stopped being a policy this repository keeps and became
one it states.** The difference is not academic: everything above was true of
`solvm`'s own past, and a producer *outside* this repository could read the
equality in the source without knowing whether it was a rule or an accident of
the reader. A rule nobody has written down cannot be relied on, because it can
change without anybody noticing they have broken it.

So it is written down twice, for the two audiences:
[BYTECODE.md](BYTECODE.md#the-format-version-and-what-it-promises) beside the
format, and [PRODUCING.md](PRODUCING.md#the-version-and-what-it-promises-you)
for whoever emits one. **Format 15 will refuse 14 and everything before it, and
14 refuses 15** — the check is an equality rather than a floor, so a newer file
is exactly as unreadable as an older one. It needed no code; the behaviour was
already that, verified by handing `solvm` files claiming 13 and 15.

This entry stays here rather than closing, because it is still a limitation: it
is the *chosen* kind, and 6.42 asked what it promised rather than asking for it
to change.

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

#### A program that met this entry and then left it

**2026-08-26.** [check_syntax.sol](../programs/check_syntax.sol) walks a grammar,
so its depth is a fact about what it was *handed* rather than about its own
source — the first program here of which that is true. It was a tree walk, one
frame per node, and the limits were measured through real grammars rather than
guessed from the matcher:

| | |
| --- | --- |
| [pascal.bnf](../programs/check_syntax/pascal.bnf) | 19 levels of nested `begin … if`, 28 nested parentheses |
| [solum.bnf](../programs/check_syntax/solum.bnf) | 13 nested blocks |

Much smaller than the 83 brackets `evaluator.sol` reaches, and the reason is
worth keeping: **a grammar rule is not one frame.** One level of a language's
own nesting costs about four rule references and a reference costs two frames,
so the multiplier is the *grammar* rather than the matcher — which is what
[ideas.md](ideas.md#programs-that-would-press-on-something) predicted when it
said a tree is what multiplies a measurement taken on a list.

**A compiled Pascal reaches this exactly, which is the best result available.**
[pascal.sol](../programs/pascal.sol) compiles ISO 7185 to `.sob`, and a
recursive Pascal function manages **254 levels** — this entry's plain recursion
limit, to the level. A Pascal call costs one frame and nothing else: no wrapper,
no trampoline, no bookkeeping frame between it and an `OP_SEND`. Where
`evaluator.sol` spends three frames per bracket and `check_syntax.sol` spent two
per grammar rule, a compiler for a language that has procedures of its own can
spend one — and this entry's number is then that language's number too.

**A file somebody actually wrote reached it**, and that is what settled the
question. `experiment/lexer.sol` holds a 24-level nested `ifElse` staircase, the
deepest expression in this repository; `solas` compiles it and the checker ran
out of frames on it. Every earlier measurement on this entry needed a generator
— `evaluator.sol` counts brackets it produced itself, and the Pascal figures
come from a script emitting nesting nobody would type. This one was already
sitting here. **And the shape that did it is the shape
[control.sol](../lib/control.sol) recommends**, a staircase of `ifElse` written
instead of `switch` precisely to save frames. Both are right: it saves them in
the program doing the dispatching and costs them in anything that walks the
result as a tree.

**So the matcher is an explicit stack machine now, and the limit is gone.** The
instruction set is LPeg's — `Call`, `Ret`, `Choice`, `Commit`, and terminals —
and the stack is a Solum array rather than the machine's frames. **2,000 levels
of nesting check in both languages**, against 19 and 13. What bounds depth is
memory.

Three things about that are worth this entry's space.

**It cost 38% of the running time.** `programs/sola.sol` went from 3.79 seconds
to 5.25. Two attempts to get that back — reordering the dispatch by frequency,
and spelling out the hottest comparison rather than calling it — are worth 3.7%
between them. The loop's cost is the instruction fetch and the sends inside an
arm, not the comparisons that choose the arm. **An interpreter written in this
language pays for its dispatch and cannot get it back by hand**, which is the
same finding `basic.sol` reported from the other direction.

**What is left of the limit moved somewhere better.** Compiling a grammar still
recurses over its tree, so a grammar nesting brackets a few hundred deep still
runs out. That is a property of the *grammar file*, reported identically every
run and before any subject is read — not a property of the input, discovered on
the one file that happened to be deep.

**And it is still catchable either way**, which is what made the limit liveable
for as long as it was: `call depth exceeded` arrives at `onError` like any other
failure, so a checker that ran out said so rather than dying.

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

**An extension is this entry at full size**, and the reason it is not a new one.
A primitive that scans 256MB spends eight steps; a primitive that *is* somebody
else's C spends eight steps doing anything at all, and `gtk:run` spends eight
steps waiting for a person. Extensions did not create the hole, they widened a
hole that was already the honest description of a primitive — which is why
[docs/extensions.md](extensions.md) states it as a rule an extension keeps
(check `had_error` after calling back in) rather than as a promise the machine
makes. What bounds a program with a window is the extension's discipline, and
that is written where an extension author reads it.

**And the first bundle shipped here was designed around this entry**, which is
the most useful thing it has done. [net](NET.md) could have offered a blocking
read — every sockets library does — and a program waiting for a datagram that
never comes would then be a program no limit could reach, for as long as the
peer stayed silent. So it does not: `net:waitFor(socket, #ms)` bounds the wait
and answers whether anything arrived, and going round again is the program's
decision rather than the kernel's. The hole this entry describes is still there,
and its width is now something a bundle chooses.

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

**An extension is a second instance of the same joint**, added in 0.36.0 and
recorded here rather than given an entry of its own. A bundle binds `gtk` and a
program says `gtk`; nothing checks that they agree, and a program started
without its bundle fails as *undefined name 'gtk'* at the first line that names
one. The difference from a host is only that the failure is easier to read,
since the missing thing was named on the command line a moment earlier — the
joint is identical, and so is the reason it is not simply a defect.

**[net](NET.md) is the third**, and the first inside this repository, so the
failure is now something the tree can demonstrate rather than describe: run
either program in `extensions/net/` without `--extension=` and it stops at the
line that first says `net`. That is the arrangement working — a capability
nobody granted is a capability the program does not have — and it is the same
unchecked agreement all the same.

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

**And `system:load` now reaches it from a third direction.** A file loaded at
run time binds into the same one namespace, for the same reason and with the
same consequence: whichever file binds a name last owns it, silently. What is
new is only that the collision can now happen between two files that were
compiled separately and never saw each other, which makes it likelier rather
than different. Loading a file twice is no longer one of the ways it happens —
that memory exists — but two different files claiming one name is untouched by
it. The deferred answer above is still the answer.

It adds a second list that nothing shortens, beside the globals: the files this
machine has loaded. That is the same shape of leak this entry is about, and a
reset would have to clear it too.

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

**There are two such tables now**, not one:
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)
added `global_slots` beside `interned`, holding where each of the chunk's
globals was found on *that* machine's root. It is emptied by the same
`interned_for` serial and for the same reason, so it adds no new hazard — it is
the same hazard with a second thing in it, and an entry that named one table
would have gone quietly out of date rather than wrong.

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

**The workaround has a shape, and it recurs**, in two forms, across `lib/`,
`programs/` and `examples/`:

| | where |
| --- | --- |
| a `done` boolean whose only job is to stop the loop | [json.sol](../lib/json.sol), [html.sol](../lib/html.sol), [control.sol](../lib/control.sol), [keys.sol](../examples/keys.sol) |
| an accumulator or a nil tested for the same purpose | [html.sol](../lib/html.sol), [expect.sol](../programs/expect.sol), [basic.sol](../programs/basic.sol) |

**Almost none of them says anything about it, and that is the better evidence.**
A complaint is somebody noticing; a file reaching for the same shape without
comment is an idiom. Two did say something, and they are quoted below.

#### There was a count here, and it is gone on purpose

It said **nine sites**, and it was nine when it was written and is not now:
`basic.sol` alone added two, one of them the loop its prompt runs on.

A repository that keeps finding stale numbers in its own prose should not keep a
number it has no way to check. Every other count in these documents carries a
marker the build recounts — and **this one cannot**. *A loop carrying a flag* is
a property of source text, not of the running machine, and a grep cannot tell it
from an ordinary counted loop: the first attempt at recounting returned **sixty**,
which is how that was learned rather than assumed.

The argument here never rested on the number. It rests on the shape recurring,
which it does, in more files than when this was written.

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
compiler already knows how to emit. But `do`, `collect`, `select`,
`repeat` and `loop` are primitives that call a block per element, and there a
`break` needs a run-time signal from a block to whoever called it — which is
[3.2](#32-no-non-local-return)'s machinery, not something smaller. So:

| | |
| --- | --- |
| a jump-based `break` | works only in the spelling the compiler inlines — and the inlining is documented as *"an optimisation only; the meaning is exactly that of the message"*, so this would make a feature of it |
| a signal from block to caller | covers every loop, and is most of 3.2 |
| leave it | the sites are content, and nearly all of them silent about it |

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

### 3.23 Program output and a run-time error come out in the wrong order

Down a pipe, a program that prints and then fails shows the error *before*
its output: standard output is block-buffered when it is not a terminal and
standard error is not buffered at all, so the complaint overtakes everything
printed and not yet flushed. Interactively stdout is line-buffered and the
order happens to be right, which is why nothing here had seen it. The fix is
an `fflush(stdout)` before a run-time error is written, and probably before
the machine stops for `--steps` or `--memory`, which fail the same way.
[PARASOL-SOLVEIG-NOTES.md](PARASOL-SOLVEIG-NOTES.md#1-program-output-and-a-runtime-error-come-out-in-the-wrong-order)
1 has the repro. Found on 2026-08-31 by a `make test` that captured both
streams and read a print that had happened as one that had not.

### 3.24 A generated file cannot say where it came from

`solas`, `solvm` and `solid` report positions in the file they were handed,
and there is no way to tell any of them the file was generated. Parasol
writes a map beside every `.sol` it emits, so the information exists, on
Parasol's side; everybody who is not Parasol looks the position up by hand.
Three shapes, in order of how little each asks: `solas --source-name=<path>`,
one flag and one field, which fixes the file and not the line; a
`#line`-style directive, `@line 25 "vectors.psol".`, which fixes both and
costs a directive and a lexer case; the chunk carrying a map, right and much
larger, and not before something asks. The path and line are already in the
`.sob` and already reported, so the mechanism is there and what is missing is
a way to set what goes into it.
[PARASOL-SOLVEIG-NOTES.md](PARASOL-SOLVEIG-NOTES.md#2-a-generated-file-cannot-say-where-it-came-from)
2. Since 2026-09-14 `parasol --sob` holds `solas` on a pipe, which is the
other route to the same end and asks nothing of this side; Parasol's roadmap
holds that one.

### 3.25 The machine counts instructions and will not say how many

`--steps=N` stops a program after N instructions, so the machine is counting,
and nothing reports the count: a run that finishes says nothing, and one that
is stopped names the limit rather than the position. The workaround is the
one [programs.md](programs.md) describes, a binary search on N for the
smallest that lets the run finish, which is exact and is 28 full runs of the
program to learn a number the machine had after the first. Smallest fix
first: `--steps` with no `=N`, run to completion and write the count to
stderr; a count in the stop message; `system:steps` from inside, which
changes what a program can observe about itself and is a decision rather
than a flag.
[PARASOL-SOLVEIG-NOTES.md](PARASOL-SOLVEIG-NOTES.md#3-the-machine-counts-instructions-and-will-not-say-how-many)
3. What wanted it was a measurement of 5% found by running two programs 56
times.

### 3.26 A run-time trace carries a line and no column

A compile error is reported with a column, `[prog.sol:1:7]`, and a run-time
frame is not, `[bignum.sol:27] in block`. For a written file that is a small
loss; for a generated one a line is often a span, a `while` body or an `if`
arm emitted on one line, so `bignum.sol:27` is four lines of the `.psol` and a
map exact to the column has nothing to look up. The fix is to carry the
column in the line table beside the line and print it in the frame, which the
compiler had when it emitted the instruction; the other half, keeping a
source line break inside an expanded hole, is Parasol's and on its roadmap,
and either alone would do.
[PARASOL-SOLVEIG-NOTES.md](PARASOL-SOLVEIG-NOTES.md#4-a-run-time-trace-carries-a-line-and-no-column)
4. Found on 2026-09-13 by `programs/bignum`, which put a deliberate error in
a copy of its library to test the map across two modules.

### 1.1d Collection is stop-the-world and non-incremental

Fine at this size and not worth touching yet. Noted so it is a choice rather than
an oversight: a program holding a large live set will pause proportionally to it.

Kept here rather than under the collector, which is otherwise done. The number is
the one the changelog cites.

## 6. Beyond the language — gone from this document

Sections 1 to 5 were about making Solum a language. This one was about making it
a language you can write a *program* in: split across files, reading input,
writing files, stopping with a status, running another program, a prompt, a
debugger, and — since an editor asked for them — the size of the screen it draws
on and a read that gives up. Nearly all of that is built, and the entries are in
[COMPLETED.md](COMPLETED.md) — including
[6.38](COMPLETED.md#638-nothing-says-what-a-compiled-file-exports--done), added
on 2026-08-29 and closed the same afternoon, which is the section still doing
what it was for: saying what a program written against this needs and has not
got.

**Nothing is open here.** The last entry,
[6.44](COMPLETED.md#644-an-instant-cannot-be-written-in-local-time--done), an
instant cannot be written in local time, was raised on 2026-09-02 by
[diff.sol](../programs/diff.sol) and closed on 2026-09-12 as
`system:utcOffset(t)`. It sat for ten days marked *not urgent* because the
wrongness "needs a file older than the last clock change to show", and that is
not a rare file: on 2026-09-12 two files stamped in January and July were put
through the program and the January one came out an hour late. The oracle had
not seen it because it writes its operands fresh, so both stamps are always on
the same side of the change.

**Its neighbour closed on 2026-09-04.**
[6.45](COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done) was what
[6.43](COMPLETED.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers---done)
left behind when it closed on 2026-09-03 — raised by `sort` rather than by
`diff`, wanted again by `gzip -d` two days later, and the one thing the
whole-pipe read did not help with. It is `system:readUpTo(#n)` now.

Before them the four entries this section held on 2026-09-01 all
closed the same day, including
[6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done)
— the first entry on this list opened by somebody who does not work on this
repository, and closed by four pieces of work in the order it recommended and
mostly not the shape it recommended.
[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done),
added on 2026-08-31, was that a program cannot tell whether two paths are the
same file; `system:fileId` answers it, and `tail -f` stopped losing a line to a
same-size rotation.
[6.41](COMPLETED.md#641-a-path-that-stops-existing-is-an-error-rather-than-an-answer--done),
added and closed on 2026-09-01, was that a path which stops existing is an error
rather than an answer — `tail -f` did not merely fail to follow a rotation, it
died on one, and that was the half of the problem which has nothing to do with
identity. It went in front of 6.39 and had to.
6.40 was opened and closed on 2026-08-31 —
[a program cannot ask whether a stream is a terminal](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done),
answered by `system:isTerminal`.

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

## 7. Parasol

Parasol's open entries, carried here on 2026-09-15 when its roadmap froze
under [docs/parasol/](parasol/ROADMAP.md) with the rest of its records. Each
keeps its words; the numbers are new, and a Parasol entry closes the way any
other does, into [COMPLETED.md](COMPLETED.md) with its case. What the frozen
page keeps is what was settled on it: *Retracted*, and *Not planned, and why*,
which are the refusals (a dialect that changes the lexer, a rule that begins
with a nonterminal, emitting bytecode, `@expr`, a signed bare number) and stand
as written; a refusal reopened is argued again here or in
[ideas.md](ideas.md), not there. The plan that made Parasol a member of the
toolkit is on that page too, under *A member of the toolkit*, with four of its
five steps and three of the fifth's five sub-steps marked done; the fourth
and fifth sub-steps were done the day it froze, the fifth being
[7.2](COMPLETED.md#72-what-is-left-in-parasol--done), and what is left of the
plan is 7.1.

### 7.1 One version for the tree, at the next release

**Parasol's version is its own, and so is its Makefile, and the second waits
on the first.** *Decided on 2026-09-14, in the evening: one version. And the
Makefile did not wait after all: the merge was step 2 of the plan and went in
the same evening, the version half being all that is left of this entry. From the
next Solveig release `parasol --version` reports the tree's number, this
changelog's entries carry it, `PARASOL_SOLVEIG_MINIMUM` goes since the parent
is the version by construction, and Parasol's `dist` goes with it. The entry
stays open until that release does it, and is step 1 of the plan under* A
member of the toolkit *below.* Parasol is `0.17.0` inside a tree that is `0.44.0`, with its
own changelog and its own `dist` tarball, because it arrived as a
subproject with its history and nothing about that was decided at the time
beyond *not now*. Since 2026-09-13 its compiler is built into Solveig's
`bin/` beside the four, which is as far as the build has been folded. The
next Parasol release is what forces the question: one version and one release
for the whole tree, or two as today. Folding the Makefile into Solveig's was
asked about the same day and declined for the same reason, since a merge
before that answer would settle the version by the back door. What holds it
apart today is also what the separate file enforces: every one of Parasol's
`test`, `clean`, `install` and `dist` collides with the root's, `dist` cuts
a tarball under Parasol's own number, and the Makefile's opening claim, that
the build needs no Solveig and reaches it only through `bin/`, is a claim a
separate file keeps mechanical where one file would keep it by discipline.
What would have to be true: one version for the tree. Then `dist` and
`install` are one thing, the collision list empties, and the Makefiles
merge in the same move, keeping the claim as a comment on the Parasol rules
and a check that no Parasol object is built with a solum include path.

### 7.3 Grouping `programs/` into kinds

**Grouping `programs/` and `examples/` into kinds.** Asked by Hans on
2026-09-14 after step 4 had put seven directories beside twenty-two
programs and twelve corpora: should the two directories be organised, `lang`,
`utils` and so on? Held, with a trigger, and the reasons. `examples/` is
already organised by the guide, one file per concept it names, every name its
own category, and the checker, the Makefile and the guide's twenty-nine links
all read it flat. `programs/` is mixed, four kinds of program and two kinds
of directory, but it has a convention already: `x.sol`, and `x/` when it has
data or an oracle. What a move costs is the records: 400 links name
`programs/<name>.sol`, the checker verifies each one path by path, and
most of them are in the changelog, the ideas and the journal, which say
where a file *was* and are not supposed to be rewritten. So the map is the
place to group, and `docs/programs.md` says of itself that it is the map:
its table by kind (tools, languages, the project's own, demonstrations,
written in Parasol) is an hour and moves nothing. What would fire the
directories moving: the flat listing stopping being readable, or a kind of
program the map cannot place. And it would need one thing first: the
checker accepting a historical link through a moved-from table, so that a
2026-08 entry naming `programs/log.sol` stays true after the file goes to
`programs/tools/log.sol`. Rewriting the records instead is the option that
is not on the table.

### 7.4 A hole's kind is one choice, with no alternation

**A hole's kind is one choice, with no alternation.** `lib/clike.psol` wanted *a
block, or another use of me* for C's `else` and could not say it, so a chain
wants its braces. Worked around; recorded because it is the same shape as
optional parts and would want deciding with them.

**Two strangers have been put in front of the workaround and neither paid for
it.** [second-reader.md](PARASOL-SECOND-READER.md)'s second run was designed to force
the chain, and the reader wrote `else { if (…) { … } }` on the first attempt
without trying `else if` once — because `lib/clike.psol` spends eleven lines on
it **at the declaration itself**, naming the silent `{ { … } }` failure and
spelling the fix. Their words: *I would have tried `else if` first if the
dialect file had not spent a paragraph on it.*

> **A limitation explained where it is declared is not a limitation a reader
> pays for. It is one its author paid for once.**

**Run 3 narrowed this on 2026-09-04, and it needed narrowing.** The
`print`-is-a-repr trap is explained at the line it is about and the third
reader read that comment, quoted it back, wrote `:print` anyway and paid the
cycle. **The rule holds for a refusal and not for a silence**: `else if` is
something a reader must choose to type, so a warning read beforehand removes
the option; `:print` compiles, runs, and looks right, so the warning describes
something they cannot recognise until they already have it.

> **A warning prevents a failure you would have chosen. It does not prevent one
> you would have walked into believing you had succeeded.**

It is kept rather than replaced, because it is true of what it was measured on.
[POSTMORTEM.md](parasol/POSTMORTEM.md) 26 is why it should not have been stated wider
than that on one reader.

**And since 0.17.0 the compiler says it too.** *Once* was once **per dialect**:
`lib/clike.psol`'s author paid it, and the next dialect with a `block` hole has
an author who has not. The hole-kind diagnostic now carries `wrap it in braces
-- '{' before this and '}' after it`, which is the workaround this entry is
about, prescribed at the failure by the only part of the system that reaches a
reader who has read nothing. **It does not make `else if` work and it is not a
step towards alternation** — it makes the wall say how to climb it. See
[COMPLETED.md](parasol/COMPLETED.md) 17, which argues why only `block` gets a
prescription.

**Two more readers met a `block` hole afterwards and neither wanted alternation
either.** Run 3 used `lib/clike.psol` and needed no cascade; run 4 **declared a
form with a `block` hole of its own** and reported expecting to need two
declarations for a one-statement and a two-statement body — *the way
`control.psol` needs two for `if` and `if/else`* — and finding one enough. **A
hole that asks for a block does not care how much is in it**, which is the
nearest thing to alternation anybody has actually wanted.

**So this drops below where it was**, and for the fourth time an entry here has
been answered by a customer declining to need it — the first time by a customer
being *told* in advance rather than by one working it out. What would move it is
a use where the workaround is not merely verbose but **unwritable**, and neither
of the two dialects that wanted alternation has produced one.

### 7.5 A template's constants are never folded

**A template's constants are never folded, and it costs what the template
saves.** `@infix >>> 55 => (left:shiftRight(right)):bitOr((left:shiftLeft(#32:sub(right))):bitAnd(#4294967295)).`
expands with `#32:sub(#17)` inside it, evaluated once per use at run time.
`programs/digest` measured both halves on a 4 KB hash, by binary search on
`--steps`:

| | instructions |
| --- | ---: |
| `>>>` expanded as a template | 1,362,533 |
| `>>>` as a method on `integer` | 1,437,417 |
| saved by not calling | 74,884 — 2.03 per rotation |
| spent on the unfolded constant | 73,728 — 2.00 per rotation |

**A form gives back 98% of what it saves**, so *a form is a method that costs
nothing at run time* is not true today. Folding would win 5.4% on that program.

**A second customer, and it argues the other way.** `programs/ledger` names its
precision once — `@syntax scale => #100.` — and round-half-up then wants half a
unit, so `scale:div(#2)` expands to `#100:div(#2)`: the same shape, reached from
a different direction. Measured the same way, against a hand-folded copy:

| | instructions |
| --- | ---: |
| as written | 4,258 |
| every constant folded by hand | 4,250 |
| saved | 8 — **0.19%** |

**A dialect's constants cost per *use*, and this dialect's uses are outside the
loop.** SHA-256 rotates inside sixty-four rounds of every block, so
`#32:sub(#17)` runs 36,864 times on a 4 KB input; a ledger writes `*` and
`percent` once each and keeps writing them once whether it has five
transactions or five thousand,
the loop over them carrying no constant at all.

So the number is 5.4% or 0.19% depending on where the dialect sits, and **one
measurement made this look larger than it is**. What survives is the claim, not
the figure: *a form is a method that costs nothing at run time* is either true
or it is not.

**A third customer, and it declines.** `programs/bignum` has its base in the
inner loop, which is `digest`'s shape, and no send in its generated code has
two literal operands: `digit(t)` is `t:mod(#1000000000)`, and nothing is
*derived* from the base the way `ledger` derived half a unit from its scale. A
folder would find nothing to do. Predicted before the program was written, and
right, so this entry moves by a customer declining rather than by a figure.

**It is not obviously safe, which is why this is an entry and not a patch.**
Folding `#32:sub(#17)` means evaluating a send at expand time, and `integer:sub`
is a slot a Solveig program may assign — run rather than assumed:

```
integer:sub := { other | #999 }.
(#32:sub(#17)):print.               ; #999 -- and not #15
```

So an expander that folds has decided some sends are safe to run, and has
decided it on behalf of a program it cannot see. That is the same question
[rules-and-logic.md](PARASOL-RULES-AND-LOGIC.md) asks about guards, one size smaller.
Guards ask *may parsing depend on evaluation*, and are answered no, because
otherwise no tool could read a `.psol` without running it. This asks *may
expansion depend on evaluation*. Both answers today are the same uniform
**nothing runs at expand time**, and folding puts the first hole in it.

**The rule to settle first.**

**Which sends may be evaluated at expand time, and who is allowed to have
redefined them.** Three shapes, cheapest first, and what each concedes:

| | |
| --- | --- |
| **An allowlist, over literal receivers only** | Fold a send whose receiver and arguments are all literals and whose selector is on a fixed list — `add`, `sub`, `mul`, `shiftLeft`, `bitAnd`. Nothing with a name in it, so `#32:sub(#17)` qualifies and `x:sub(#17)` never does. Small, and it reaches the case that motivates the entry. **It concedes a guarantee Parasol cannot check**: a program that reassigns `integer:sub` gets one answer from folded code and another from unfolded, and nothing will say so. |
| **Fold only what the module provably does not reassign** | Sound, and it does not apply. The reassignment may live in a `.sol` reached by `@include`, which Parasol passes through without reading — by design, since a dialect provides syntax and `@include` provides code. Undecidable at exactly the boundary this project put there on purpose. |
| **Expand-time arithmetic that is not Solveig** | Keep *nothing runs at expand time* exactly as it stands, and give a template a separate notation for computing on its holes. Correct, and it costs a second language inside the first — the tower [rules-and-logic.md](PARASOL-RULES-AND-LOGIC.md) spends its length refusing. |

**The first is the only cheap one, and it is cheap because it moves a guarantee
onto the programmer.** It would be the first time Parasol says *this is correct
unless you did something Parasol cannot see*, and every rule on this page is the
other way round: a `.psol` means what it says, by reading it. That is the
decision, and it is not a decision about performance.

**What would make it worth starting.** A second program wanting it — one
customer is not a reason to grow a surface, which is
[conventions.md](method.md#what-came-in-from-parasols-conventionsmd-and-what-was-retired)'s standing rule and Solveig's before that — or
a decision that *a form is a method that costs nothing at run time* is worth
making true for its own sake. **The number is small and the claim is not**: 5.4%
on one program is not an argument, but a sentence in the README that is 98% true
is a different kind of debt.

### 7.6 A dialect ends at its domain and cannot say where

**A dialect ends at its domain and cannot say where. Three programs now, and
the third had no trap, which is the first proposal.**
`programs/digest` declares `+` as addition modulo 2³², right for every line of
SHA-256 and a trap for the loop counters beside it — `shift - #8` at zero is
`#4294967288` and the loop never ends. `programs/ledger` declares `/` as
rounding to the nearest hundredth, right for splitting a bill four ways and
wrong for taking `-1225` apart into `-12.25`, which wants the floored whole part
and remainder. Both write those lines with sends and a comment.

**A pattern rather than an anecdote, and the second instance narrowed it
twice.** The trapping operator is not predictable from outside the domain —
`ledger`
predicted `*` and was bitten by `/` — so nothing here should promise that a
dialect's danger is findable by inspection. And the boundary is not only at the
domain's *edge*: `ratio interest to subtotal` answers `0.07` where the exact
value is `0.074995…`, because a ledger has amounts wanting two places and rates
wanting five, and a dialect has one scale to give. **The same dialect can be
wrong for a second quantity inside its own domain.**

A dialect that could say where it ends would have to say it per operator and
per quantity, which is a type system and a larger thing than this project is.

**`programs/bignum` was written on 2026-09-13 to find the boundary, in two
modules whose headers were meant to disagree about `+`, and found there was
none to find.** Its values are objects, so `+` is `add` and the receiver
decides; the library's `*` is an integer product on one line and a bignum
product two methods down under one declaration, and the loop counters beside
the domain are as safe as the domain. The proposal is not a feature: **a
dialect traps its scaffolding exactly when its domain's values are the
substrate's own**, because then a template on the spelling is the only place
the rule can go and a template cannot look at its receiver. A 32-bit word and
an amount in hundredths are integers, so `digest` and `ledger` had to invent
and were bitten; a bignum is not, so nothing was invented and nothing bit. The
question to ask before writing a domain dialect is therefore *are its values
the substrate's own*, and if they are, the trap is certain and the workaround
is the one both programs used. [does-it-pay.md](PARASOL-DOES-IT-PAY.md) has the
argument under *The seventh program*.

### 7.7 Optional and repeated parts, then a guard

**Declined three times, and the last two with the same reason.**

`programs/ember` wanted neither: no variadic notation, and `if`/`else` as two
declarations was fine.

`programs/grammar` was written partly to settle it, being the program most
likely to want repetition -- EBNF writes `sum = term { op term }` and means it.
It wants repetition and **a repeated pattern part would not have helped**: a
grammar cannot be written as forms at all, because a template cannot declare a
form, so the rules live in a table as data and the repetition wanted is in the
object language rather than in Parasol. Both grammars have a `whileTrue` where
EBNF has a brace, and no Parasol feature would have removed it.

`programs/basic` met both again and declined both from the far side. BASIC's
`PRINT a, b, c` is a repetition and its `STEP` clause is an optional part, and
they are `while opIs(",") do …` and `if wordIs("STEP")` in an ordinary parser —
**in the interpreted language, one level below anything a header can reach.**
Same reason as `grammar`'s, arrived at from a domain with no grammar in it.

That is a reason rather than a shrug, and it moves this below whatever the next
program finds. **Three programs have now been offered the feature and none has
wanted it**, which is the strongest form of evidence this project collects.

**`if <c> then <a> else <b>` is a second declaration rather than an optional
tail**, which is honest and costs a line. Repetition — a form taking a list —
has no spelling at all, and wants one before anybody writes `sum of <a> <b> <c>`
three times.

Two more part kinds in an array the matcher already walks. **The property to
keep is that an optional part begins with a word**, for the reason a pattern
does: it is what lets one token decide whether the part is there, and it is what
keeps the matcher free of backtracking.

**Then a guard, and the evaluator it needs is Solveig.** `solum/embed.h` was
built for it — one of the three cases it names is *a tool scripted in Solum* —
and `embed/host.c` already wrote the loop: compile one script once, run it many
times, each under its own allowance. Compile the guard once, run it per use, and
`serve_one` becomes `check_one`.

It costs *the build needs no Solveig*, which is real. It does not cost *no
privileged access*, which is the claim that matters: `embed.h` is a declared
surface, and using it is the mirror of solveig-sdl using `extend.h`. **The rule
to fix before any of it is written: a guard validates, it does not select** —
otherwise parsing depends on evaluation and no tool can read a `.psol` without
running it.

0.6.0 is the reason this is not urgent. The five kinds cover what a guard would
mostly have been used for, and they cover it without an evaluator.
[rules-and-logic.md](PARASOL-RULES-AND-LOGIC.md) argues the whole of it.

### 7.8 A selector built from a `name` hole

**Asked twice, and the second time the asker turned out not to want it.**
`instantiate` in `parasol/src/expand.c` replaces a parameter only where it
stands as a name node, an expression; a send's selector is text on the send
node, so `it:n := e` in a template keeps its `n` whatever the hole held.
`programs/grammar` met this first, prediction 4 in its README, and keyed its
rules by symbol instead: `rule 'expr is { ... }` was the predicted spelling
and the one written.

The second ask came from Solveig on 2026-09-14, where a region that reads
every statement as a slot write on one receiver, `@with rect { x := #0. ... }`,
was scoped and held (Solveig's `ideas.md`, *`@with obj { ... }`, a region where
an assignment is a slot write*). Could Parasol carry it instead? The block form
cannot be a template at all, since a template places a block hole whole and
nothing walks the statements inside one. The line form was tried:

```text
@syntax on <o> => it := o.
@syntax slot <n: name> is <e> => it:n := e.

on rect.
slot x is #0.                     ; emits  it:n := #0
```

It compiles, emits `it:n := #0` for every slot, and `rect:make` is then not
understood. So the ask is for exactly this feature. But had it worked, the
output would read `it:x := #0`, since a template cannot remember `on rect`
from one use to the next, and the property that made Parasol the attractive
home, a `.sol` that still says `rect:x := #0` and can be grepped for it, is
lost either way. **The second customer, examined, does not get what it came
for from this feature**, so the count stays at one that was fine without it.

**The change itself is small**, a check in `instantiate` for a `name`-kind
parameter standing where a selector is, and it is the one piece of the
Solveig ask that is Parasol's to build. It waits for a customer who would keep
the result.

### 7.9 Two spellings with no customer: postfix operators, and a logical xor

**No postfix operators.** Parasol has prefix and infix; `x++`, `a[i]` and
`p->f`-in-postfix-position have no spelling at all. `lib/clike.psol` names it as
one of the four things C has that it cannot. Not a rule that could be relaxed —
the extension point does not exist. No customer has been blocked by it.

**A logical xor still has no spelling, and now needs one less.** For booleans,
xor *is* not-equals, and the argument for `^^` was that a module using
`lib/arith.psol` had no way to write one at all. It has `!=` since 2026-09-02, so
`a != b` on two booleans is an xor in both shipped dialects and the gap that
argument pointed at is closed. Nothing here has ever needed one.
[REFERENCE.md](PARASOL-REFERENCE.md) records that the spelling would be `^^` if it were
ever declared, so the question stays settled before it is asked.

### 7.10 Rough edges

**Filed severities on this list are guesses until somebody checks one.** A
fifth row lived in `README.md` saying a `@use` path is not normalised, that
`examples/../lib/control.psol` is what a diagnostic shows, and that two spellings
of one file are two files — filed as cosmetic, with `realpath` already named as
the fix. It was checked on 2026-09-04 and the second clause was the whole
defect: the same string comparison decided whether a file had been read, so a
diamond spelled two ways warned that a file collided with itself and a cycle
spelled two ways was reported as *nested more than 64 deep*.
[POSTMORTEM.md](parasol/POSTMORTEM.md) 24.

**The sentence was right and the severity was wrong**, because the entry
described what a diagnostic *shows* and never asked what else compared those
strings. **What makes a rough edge cheap to leave is exactly what makes it cheap
to file without looking.**

**A second row has since been checked, and it also matters.** Run 4 of the
reader experiment produced the failure this project names as the one that kills
syntax-extension systems — `solvm` reporting `undefined name 'total'` at
`banner.sol:8`, a line in the **generated** file, after seven lines of correct
output. **No map had been written**, because the map is opt-in. With one, the
recovery is exact: generated `8:5` is source `10:5`, the line the reader wrote.

**The mechanism works and was switched off**, and that is the whole argument for
changing the default: a map costs one file and nothing else, and the invocation
that omits it is the shortest one — which is the one a person types.

**It is not settled, and the reason is [POSTMORTEM.md](parasol/POSTMORTEM.md) 27**: the
reader was *told* to invoke it without `--map` by the experiment's own prompt,
which differs from `README.md`'s quickstart. So the cost of the minimal
invocation is measured and the likelihood of a reader choosing it is not. **The
next run uses the published invocation**, and that is what would settle it.

The two rows still unchecked are long send chains and `t__1` names; temporaries
in a group is a stated absence rather than a severity guess. A fifth row was
added on 2026-09-13 and checked the day it was found.

| | |
| --- | --- |
| Long send chains are not wrapped | A block that will not fit is broken across lines; `a:b(c):d(e):f(g)` is not. |
| Temporaries in a group | `( \| t \| … )` is Solveig's; Parasol reads `( expr. expr )`. |
| The map is written only with `--map` | The Makefile always passes it, and so does `README.md`'s quickstart. **A reader run reached the failure the map exists for, with no map written** — see below. |
| A generated name is `t__1` | Legible, and it collides with nothing because the whole module's identifiers are checked. It is still a name a person could have wanted. |
| A generated line is a span | A `while` body or an `if` arm is emitted on one line, and a run-time trace carries a line and no column, so the map, exact to the column, cannot narrow it. Checked on `programs/bignum`: 16 of the library's 103 generated lines carry more than one source line, four at worst. Either Parasol keeps a line break inside an expanded hole, or Solveig's trace gains the column its compile errors have. Neither built; `solveig-notes.md` 4 is the second half. |

## How this list emptied, and how it filled and emptied again

**It emptied for the fifth time on 2026-09-12**, when
[6.44](COMPLETED.md#644-an-instant-cannot-be-written-in-local-time--done) closed
as `system:utcOffset(t)`. It had been the only entry since 6.45 closed on
2026-09-04, and it closed by the same route as the one before it: not by a
second customer but by the first one being shown wrong on an ordinary input.

**It emptied for the fourth time on 2026-09-01 and did not stay empty.** Two
entries went on it the next day but one, both from
[diff.sol](../programs/diff.sol) --
[6.43](COMPLETED.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers---done),
about standard input, and
[6.44](COMPLETED.md#644-an-instant-cannot-be-written-in-local-time--done), about
the header. That is the mechanism working rather than an exception to it:
*empty* is a description of a moment, which this document has said since the
last time it was true.

**6.43 closed on 2026-09-03 and left one behind.** Its two clauses turned out to
be one job -- the only reason a program could not read a pipe whole was that the
call which should have done it returned early -- and what did not close was a
want recorded *inside* it by a second customer. That became
[6.45](COMPLETED.md#645-a-pipe-cannot-be-taken-in-bounded-pieces--done), with a number of its
own, because a want kept inside a closed entry is a want nothing will find
again — **and giving it one is what got it built**, three days later and by two
more customers, where leaving it in the body of a closed entry would have left
it where the roadmap is not read.

The four entries open at some
point on 2026-09-01 all closed the same day — which had not happened before that
morning and then happened twice.

[6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done)
is the one worth naming, because **somebody else put it there**: Phoenix emits
`.sob` from outside this repository, and there was no one place saying what a
producer must get right. Answering it wrote a document, split one diagnosis into
thirty-two, pinned thirteen of them with cases, and turned an implementation
detail into a stated promise about the format version. Two of the author's three
questions were answered by fixing documents rather than code, and the third —
*is the grammar current?* — by a sweep nobody had ever run.

[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done)
arrived on 2026-08-31: a program cannot tell whether two paths are the same
file. **Its trigger never fired.** One customer and one flag, for two days, and
it was built on instruction rather than because a second caller arrived — which
the entry says, because a list that quietly becomes right about its own
admission rule is worth less than one that records being overruled.

**What moved was the case, not the trigger.** The entry said a rotation makes
`tail` print from the wrong offset. Driving it said worse: a replacement of the
same size reads as *unchanged*, and a line written to the log never appears —
no error, no notice, no status. That was measurable on the day the entry was
written and was not measured, which is the more useful lesson than anything
about triggers.

**3.23 arrived and left on 2026-09-01**, and it is the second entry to do that
in one day. It was the opposite case to 6.39 — no trigger to wait for, because
the fault had already shipped — and it is
[done](COMPLETED.md#323-nothing-checks-the-pages-that-are-actually-published--done):
[site.sh](../programs/site.sh) holds every published page against the source at
`origin/main`. **Writing it found a second fault class the entry did not know
about**, which is the argument for it stated better than the entry managed: a
markdown link whose text wraps across a line loses the site's baseurl, and
eleven of them were 404s on pages that read correctly as markdown.

**6.41 arrived and left on 2026-09-01**, out of an hour spent driving `tail`
through a real rotation before designing anything for 6.39 — and it was **the
entry 6.39 was standing in front of**. `tail -f` did not fail to follow a
rotation, it exited 1 on one, because `fileSize` raised where `fileExists` and
`isDirectory` answered. A defect in a shipped message, no new kind of value, and
most of what `-F` is; it is
[done](COMPLETED.md#641-a-path-that-stops-existing-is-an-error-rather-than-an-answer--done)
and 6.39 is the same size it was.
[method.md](method.md#a-scoping-can-be-wrong-about-the-order-not-only-the-answer)
already had the shape: a scoping can be wrong about the order rather than the
answer. This is the second time it has fired, and both times the way it was
noticed was to run the thing rather than read about it.

**6.40 arrived and left the same day**, and it arrived the way this list would
like everything to: **its trigger was written down first and then fired.**
`tail` found that `keyWaiting(0.0)` answers *is standard input a terminal* by
accident and recorded it as a note with *a second program wanting it* as the
trigger rather than arguing an entry into existence on the spot; `sha256sum`
wanted it the same afternoon; the promotion cost one sentence because the
reasoning was already on the page.

**And building it found the workaround had been wrong all along**, which no
amount of arguing the entry would have produced.
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done)
has it: `keyWaiting(0.0)` answers false for an idle terminal *and* for a pipe
that is open, empty and not yet finished, so both programs printed their
demonstration and threw away a slow pipeline's input. The entry called the
workaround *exact rather than approximate* and it was neither.

**This paragraph said *nothing is on it* for two days and was true when written**,
which is the failure it is worth recording here rather than quietly editing: a
list's summary goes stale the moment the list moves, and nothing recounts a
sentence. The same day found three other statements in the same condition —
`pattern.sol`'s worked example, 3.22's *nothing here has a file that does not
fit*, and four count markers on historical releases — so this was the fourth
instance of one shape and the shape is in
[method.md](method.md#a-sentence-that-was-true-when-written-is-not-checked-by-anything).

**And the day did not stop at four**, which is the more useful number.
2026-08-31 ended with **eleven**, and they are not all the same shape: some were
true when written and went stale, and some were **never checked at all** — a
comment saying a blank line is fine "in either tool" that had asked neither, a
chunk size described as making "no measurable difference" that nobody had timed,
a claim of being the first check of its kind that
[the NBS suite](../programs/basic/conformance.sh) had already been for months,
and `keyWaiting`'s *exact rather than approximate*, which enumerated three cases
correctly out of four. **Every one was in prose about working code**: no program
was wrong, no check failed, and each was caught by doing the thing again rather
than by reading it again. The day's account is in
[journal.md](journal.md#2026-08-31-closing--a-day-of-working-code-and-eleven-wrong-sentences-about-it).

Before that the list was empty, and the last thing arrived and left inside one
afternoon, on 2026-08-29:
[6.38](COMPLETED.md#638-nothing-says-what-a-compiled-file-exports--done),
a tool that says what a `.sob` or a `.so` exports. It is the one entry here that
no program asked for and no document implied — **somebody asked for it in a
sentence**, which is a trigger this list had not previously recorded and is
worth naming as one. Everything below arrived from a program that wanted
something, and that is still the better source; it is not the only one.

Before that it was a guard rather than a feature:
[3.21](COMPLETED.md#321-a-changelog-hash-is-written-by-hand-and-nothing-checks-it--done),
which a literal `%s` sitting in the changelog for two days asked for, opened on
2026-08-27 and closed on 2026-08-28.

Before that it was empty too, having gained one on 2026-08-27 and lost it the
same day:
[3.20](COMPLETED.md#320-five-shipped-libraries-published-everything-they-had--done),
five libraries that had not said what they publish, four of which now do and the
fifth of which turned out to have nothing to hide. Sections 2, 3 and 6 held the
whole of what was left to decide or build, and 2 and 6 are done — what remains
in 3 are restrictions kept on purpose, each documented where a program would
meet it. Two
of them were only kept *until a program wanted otherwise*, and on 2026-08-25 one
program wanted both:
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done) and
[3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done),
raised and closed between breakfast and the afternoon. The same program then
raised [3.19](COMPLETED.md#319-a-program-cannot-write-to-standard-error--done),
which was closed the next day.

It gained one back on 2026-08-25 and lost it the same day:
[5.5](COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done), a cursor
that five programs had each written for themselves. That is worth saying,
because *how* it emptied is the part that transfers, and 5.5 arriving and
leaving is that paragraph continuing rather than an exception to it.

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
  here at all, because integer arithmetic traps on overflow rather than wrapping
  — and the one this program wrote instead was correct and **seeded from the
  clock**, which measuring it found was the actual defect: `random:new` closed
  that half. It also found that **a child's
  streams could not be redirected** ([3.15](COMPLETED.md#315-a-childs-streams-cannot-be-redirected--done),
  closed), and, by testing its own square root at
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
- [basic.sol](../programs/basic.sol) fired the trigger **3.14** had been holding
  open — `pow`, `log`, `exp` and trigonometry, waiting for a program that wanted
  an angle. An interpreter for ECMA-55 Minimal BASIC wants six of them and an
  exponent operator, and cannot decide to want fewer: the functions are in the
  standard it is being measured against. Decided and
  [built](COMPLETED.md#314-the-mathematics-that-is-not-here--done) the same day,
  as one set of eleven rather than the seven that were wanted. It also found, more cheerfully, that
  **line numbers are what make the job fit inside the frame limit** — a program
  counter over a sorted table of lines nests no frames at all, where a
  tree-walking interpreter for a modern language would spend them in proportion
  to how deeply its input nests. Its `INPUT` statement then found
  [3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done) — **no way to
  write without ending the line** — and, more usefully, that the obvious
  workaround reorders the whole transcript the moment the output is not a
  terminal. `system:write` closed it the same day, on `system` beside
  `readLine`, being about a destination rather than about rendering a value. Its
  sibling [3.19](COMPLETED.md#319-a-program-cannot-write-to-standard-error--done) — no way to write
  to standard *error*, so a failing listing put its diagnostic in the output
  file — was raised an hour after the list had emptied and closed the next day,
  as `system:writeError`.
- [edit.sol](../programs/edit.sol) also found the **read that gives up**
  ([6.35](COMPLETED.md#635-a-read-that-gives-up--done)) — the oldest known gap
  in the language, written down twice and never fixed because nothing had bound
  the escape key. A modal editor binds it to the most frequent action there is.
  Fifteen lines of `poll`, and then a bug no test here could have caught: a
  terminal in canonical mode holds what is typed until a newline, so asking
  *between* two reads is told nothing was typed, and every arrow key stopped
  working while all 118 of the editor's checks kept passing — because they run
  through a pipe, and a pipe has no line discipline. Found on a pseudo-terminal,
  which the suite now makes for itself.
- [edit.sol](../programs/edit.sol) found that **nothing could ask the terminal
  its size** ([6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done)),
  which [ideas.md](ideas.md#programs-that-would-press-on-something) had predicted
  in writing before the editor was written. What made it an entry rather than a
  shrug was the **measurement**: the workaround is `stty size` through a shell at
  7ms an ask, so an editor that measured on every redraw would fork a process per
  keystroke, and one that measured at startup drew a resized window wrong until
  it was restarted. The ioctl behind `system:terminalSize` is about a
  microsecond, so the editor asks every frame and the resize signal the language
  has not got stops mattering. It also confirmed, by binding the most-used key in
  a modal editor to it, what [examples/keys.sol](../examples/keys.sol) had only
  warned about: **the escape key cannot be told from the start of an escape
  sequence** without a read that times out.

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

**One entry arrived a way this document had not seen before**, and left the same
day: [6.36](COMPLETED.md#636-readline-and-readkey-did-not-share-an-input-buffer--done)
came not from a program wanting something, but from **reading the code beside a
message being built** and finding a comment that described an intention as
though it were the behaviour. Every other entry here came from somebody wanting
something and not getting it; that one came from somebody being told they
already had it.

**Nothing is undecided and nothing is outstanding.** 3.14 was the first decision
since 6.32 was deferred, and unlike 6.32 it had a program behind it rather than a
use nobody has — so it was taken rather than deferred, the same day it was
raised. 3.18 and 3.19 were work rather than decisions and are done. The older
questions stay closed. 2.5, the last *language* question, is closed: 1.6 had answered it one message at a time to stop the crashes, and finishing
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
