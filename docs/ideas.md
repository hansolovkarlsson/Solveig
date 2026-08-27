# Ideas considered

*Each idea from the notes, with a verdict and the reasoning behind it. The ones
recommended against are here so the reasons survive, and so the same idea does
not have to be re-argued from scratch in six months.*

*Everything this document said to build has been built, and the entries are in
[COMPLETED.md](COMPLETED.md). So the verdicts below are read backwards now — not
as a queue, but as a record of what was guessed and how the guess turned out.*

*[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine) arrived
here the other way round: it was a roadmap entry, the last open decision, and
came back to the idea box on 2026-08-22 without being taken. It kept its number.*

Every code sample here has been run against the current build unless it is
marked as a sketch.

## At a glance

| Idea | Verdict |
| --- | --- |
| `do` is `forEach`? | **Yes** — and `collect` is map, `select` is filter |
| Bytecode / assembly reference | **Built** — [BYTECODE.md](BYTECODE.md), checked against the header by the test suite |
| `$character` literals, Unicode | **Defer** — gated on deciding what a string is |
| A truncating divide on integer | **Defer** — one customer, and its workaround is exact rather than approximate |
| Integer sizes: byte, word, long | **No** — reintroduces the coercion the language refuses |
| Separate float and double | **No** — same reason, less benefit |
| `include` another file | **Built** — was the most valuable thing on the list |
| `System:exit(code)` | **Built** — as `system:exit`, and the `system` object grew well past it |
| Keyboard input | **Both built** — `readLine`, and `readKey` once it earned its own entry |
| File handling | **Built** — whole-file, and the filesystem around it |
| JIT to native code | **No** — possible, and it would dwarf the project |
| More examples covering everything | **Audited** — the guide was clean; four messages had no demonstration and now have one |
| `doUntil` | **Built in** — and inlined, so a definition in Solum would now be bypassed |
| switch / case | **Already writable**, and now written — [`array:ifElseIf`](REFERENCE.md#the-library) in control.sol, once an interface turned up worth committing to |
| `#10:repeat({...})` | **Built in** — a primitive, measured 3.2x the version written in Solum |
| `for` loop with start/end/step | **Built in** — `[#a, #b, #step]:loop` |
| `forIn` | **It is `do`** |
| `ifTrue{...}` without parentheses | **No** — it would teach a rule that does not generalise |
| Performance timing | **Built** — the clock came with it |
| `['red,'green,'blue]` as an enum | **Works today** — document the pattern |
| `A:with{ :m1(#1). }` cascades | **No** — chaining already covers it |
| Document `(group)` versus `{block}` | **Written** — [in the guide](GUIDE.md#group-and-block), with your own example |
| Go-style concurrency | **No, for now** — it changes the whole VM |
| Subclass `integer`, a `byte` subclass | **Not possible** — see below |
| More `@` directives: `@define`, `@ifdef`, `@once` | **No** — each one's job is already done by something that is not a directive |
| Programs that would press on something — Pascal, predicate logic, a parser toolkit | **Defer, and none needs permission** — each is [predicted to find one thing](#programs-that-would-press-on-something), written down before it is written. **The editor was written**, and found what this page said it would |
| Networking, and sending code to a running machine | **Defer** — [no socket exists](#networking-and-sending-code-to-a-machine-that-is-already-running); the second needs 3.4 and 6.32 as well |
| SQLite, SDL2 | **One project, not two** — [extensions](#extensions-a-capability-from-a-binary-rather-than-from-the-vm); SDL2 fires that trigger and SQLite does not |
| Fuzzy logic | **A library that would teach nothing** — arithmetic on floats, and the arithmetic all landed |
| Namespaces for included files | **Defer** — the trigger is somebody else writing a library |
| Splitting the reference into pages | **Defer** — the trigger is the message reference outgrowing the rest |
| Restricting what a script may reach (6.32) | **Defer** — the trigger is a script somebody else wrote, or input from a stranger |
| Extensions: a capability from a C binary | **Defer** — doable, and half of it works today; the trigger is wanting something Solum cannot express |
| Regular expressions | **No** to a literal; **defer** the engine to an [extension](#regular-expressions); the cursor that repeats instead is [built](COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done) |
| An early exit from a loop | **Defer** — the flag idiom recurs across six files; the trigger is a body that must skip its remainder ([3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)) |
| Intercepting a message not understood | **Defer** — Smalltalk's `doesNotUnderstand`; small to build, and nothing has wanted a proxy |
| A set, and the collections that are not there | **Defer** — write them in Solum and measure first, as the four loops did |
| Mathematics, and randomness | **Promoted, and built** — `sqrt`, the comparisons, `random:new`, and then the whole of [3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done): `pow`, `exp`, `log`, the trigonometry, `float:pi` and `float:atan2` |
| Tail calls | **No** — the programs that seem to ask for them are recursive-descent parsers, which never recurse in tail position |
| Coroutines | **No** — the interpreter re-enters on the C stack, so a Solum stack is not a value |
| Multiple return values | **No** — every send has a fixed stack effect, and the verifier checks height on that basis |
| Resuming from an error | **No** — the frames are gone by the time a handler runs; `retry` is writable, resuming is not |
| More than one parent | **No** — `via` already names an ancestor, which is what multiple parents are wanted for |
| An `assert` that compiles away | **No** to stripping; **defer** the message itself |
| Default values for block parameters | **Defer** — the trigger is a program threading a nil it did not want to pass; the case for it is that built-ins already do this and user code cannot |
| Constants | **Defer, and probably no** — the speed argument pointed at [3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done), which is now built and took the argument with it; the memory argument runs backwards |
| Solas written in Solum — self-hosting | **Proved, then parked** — it compiles itself to a fixpoint; the code is in [experiment/](../experiment/), off the search path, [below](#solas-written-in-solum--self-hosting) |

---

## Already there, or already writable

The language has no control-flow syntax, so **most of the loop and branch ideas
are library code, not language changes.** All of these run today, and all of
them were written in Solum first — which is the verdict this section was making
and it was the right one.

**Four of the five then left the library for the VM.** They were collected into
[lib/control.sol](../lib/control.sol), measured, and `repeat`, `doUntil` and the
counted loop all turned out to be worth building in as primitives; a primitive
`repeat` measured 3.2x the version that lived in the file. What is left in
`control.sol` is `timesCollect`, the one nobody has measured, and a comment
saying why the others are not there — redefining one now would shadow the
primitive with the slow version, and for `doUntil` the compiler splices the loop
in anyway, so the definition would be bypassed exactly where it was most wanted.

So the snippets below are still the record of what the language can express
without help, which is what they were written to show. They are no longer how
you would get these loops:

```
@include "control.sol".
```

`caseOf` was deliberately never in that file: it is a fine demonstration that
the language needs no `switch`, and an array of two-element arrays of blocks
reached into with `pair:at(#1)` is not an interface worth committing to. A
library is a promise, and the bar is higher than "it works".

The snippets here also end in demonstration calls, which a library file must
not: including one should bind names and print nothing.

```
integer:repeat := { body | | i | i := #0.
    { i:lessThan(self) }:whileTrue({ body:value. i := i:add(#1) }). nil }.
block:repeat := { n | n:repeat(self) }.

#3:repeat({ "tick":display }).        ; tick tick tick
{ "tock":display }:repeat(#2).        ; tock tock
```

`doUntil`, running the body before the test:

```
block:doUntil := { cond | | done |
    done := false.
    { done:not }:whileTrue({ self:value. done := cond:value }).
    nil }.

i := #0.
{ i := i:add(#1) }:doUntil({ i:greaterOrEqual(#3) }).
i:print.                              ; #3
```

A `for` loop with start, end and step:

```
integer:toByDo := { limit, step, body | | i |
    i := self.
    { i:lessOrEqual(limit) }:whileTrue({ body:value(i). i := i:add(step) }).
    nil }.

#1:toByDo(#10, #3, { n | n:display }).    ; 1 4 7 10
```

**`forIn` is `do`.** `["a", "b"]:do({ e | e:display })` is the loop being asked
for; there is nothing to add.

**switch/case needs no syntax either.** A list of test-and-action pairs does it,
and reads better than a `switch` would:

```
object:caseOf := { pairs | | answer, found |
    answer := nil. found := false.
    pairs:do({ pair |
        found:not:and({ pair:at(#1):value(self) }):ifTrue({
            found := true. answer := pair:at(#2):value })
    }).
    answer }.

#2:caseOf([
    [{ n | n:equals(#1) }, { "one" }],
    [{ n | n:equals(#2) }, { "two" }],
    [{ n | true },         { "many" }]
]):display.                           ; two
```

There used to be an `integer:caseOf := object:slotAt('caseOf)` above that call,
copying the method onto `integer` so a number could be sent it, and a note about
how `slotAt` fetches a method and binds it to another class because `self` comes
from the send. Both are still true of `slotAt`, and the line is no longer
needed: since every built-in class delegates to `object`, a method defined there
is found from a number, a string, or anything else. The single root took a
paragraph of cleverness and made it unnecessary, which is the better outcome.

The dispatch this shows is the *conditional* kind, tried in turn. For the far
commoner question — which of these **values** is it — a dictionary of blocks is
one hash rather than a walk, and is roughly nineteen times faster over twenty
cases. [dispatch.md](dispatch.md) has both, and the two traps that come with
putting blocks in a table.

#### And it is in the library now, which took the interface rather than the idea

`caseOf` above was refused a place in `control.sol` on a specific ground, and it
is worth re-reading before the update: *an array of two-element arrays of blocks
reached into with `pair:at(#1)` is not an interface worth committing to. A
library is a promise, and the bar is higher than "it works".*

**That judgement was right, and what changed is the interface.**
[`array:ifElseIf`](REFERENCE.md#the-library) went into `control.sol` on
2026-08-23 in this shape:

```
@include "control.sol".

n := #2.
[{ n:equals(#1) }, { "one" },
 { n:equals(#2) }, { "two" },
                   { "many" }]:ifElseIf:display.        ; two
```

Three differences from `caseOf`, and each is why it cleared the bar:

- **Flat, not pairs of pairs.** No `pair:at(#1)` anywhere, and the conditions
  and their answers line up in two columns a reader can scan.
- **The conditions are plain blocks that close over whatever they test**, rather
  than one-argument blocks handed the receiver. That gives up switching neatly
  on `self` and buys testing anything at all — which is what a scanner deciding
  between `isAlpha`, `isDigit` and six literal characters actually needs.
- **The else is the odd one out**, positionally, rather than `{ n | true }`. A
  list of pairs with one left over is exactly a list of pairs and a default.

**What prompted it was not this entry.** It was a real complaint about real
code: a ten-deep nest of `ifElse` in the scanner of the parked Solum compiler,
and a four-deep one in [disasm.sol](../programs/disasm.sol) that is now flat. So
this stayed an idea for as long as it was an idea, and became a library method
when a program made the case — which is the same rule the roadmap runs on,
applied to a library.

The cost is measured and is in [control.sol](../lib/control.sol): 5.8× a nested
chain over 200,000 dispatches, because the chain compiles to jumps and this
makes a block call per condition; and three frames a level through a recursion,
against none. Flat dispatch yes, recursive descent no.

**Symbols already are enums.** `['red, 'green, 'blue]` is a list of interned
names compared by pointer, which is what an enum is for. The only thing missing
is exhaustiveness checking, which needs a type system.

**And yes, `do` is `forEach`.** `collect` is map and `select` is filter; the
names are Smalltalk's rather than JavaScript's.

### So what would building them buy?

Only speed, and only for the loops. `whileTrue` written literally compiles to
jumps; a `repeat` written in Solum costs a block and a frame per iteration.
Building `repeat` and `doUntil` in makes them inlinable the same way. That is a
real but modest gain, and it is in the roadmap as 6.6 rather than here.

---

## Worth building — and every one is now built

These were in [ROADMAP.md](ROADMAP.md) section 6 with the detail, in rough order
of what a real program would miss first. The order held: the list was worked
down roughly as written, and the entries are now in
[COMPLETED.md](COMPLETED.md).

Kept here with the original reasoning, and with what each one turned out to be,
because **the guesses are the part worth keeping** — and the ones that missed
are noted below, in place, rather than quietly corrected.

**`include`** was the one that mattered, and it is built —
`@include "lib.sol".`, and
[the reference](REFERENCE.md#splitting-a-program-across-files) has the rules.
The design question was never the mechanism but the namespace, and it stayed
flat: an included file's globals are the including file's, exactly as though its
text had been written there. A module system with a namespace of its own is a
much larger change to the object model, and nothing so far has needed it.

**A `system` object** — `exit(code)` first, then arguments and a clock. Small,
and `exit` is the difference between a script and a program.

> Built, and it did not stay small: `system` answers its arguments and the
> environment, walks the filesystem, and runs another program. `exit` turned out
> to matter for a second reason nobody had in mind here — it unwinds rather than
> leaving from under the machine, so a script that exits ends *itself* and hands
> the decision back to whoever called. That is what lets a host survive the
> script it is running, and
> [6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
> names it as the behaviour an embedding would most expect to be wrong.

**A clock**, which is what the performance-timing idea needs. This project's own
changelog is full of measurements taken with `/usr/bin/time`; being able to take
them from inside the language would be better.

> Built. The `time` class is there, and performance timing came with it.

**Reading input**, starting with a whole line. `readLine` is a few lines of C and
portable. Waiting for a single key is a different job — it needs raw terminal
mode, which is platform-specific and belongs behind its own decision.

> Both built, and splitting them was right: `readLine` came first and single-key
> went off to be its own entry,
> [6.10](COMPLETED.md#610-waiting-for-a-single-key--done). What that entry
> then caught is the thing worth remembering: it was **closed once by mistake**,
> because Solis had grown raw-mode line editing for its own prompt — the same
> machinery, and not the same thing, since a *program* still could not read a
> key. `system:readKey` is the message. It answers one byte rather than one key:
> an arrow is three bytes, and which bytes make a key belongs to the terminal
> rather than to the language.

**File handling**, whole-file first: read a file into a string, write a string to
a file. That covers most of what scripts do. Binary files want a byte-array type
and should wait for a program that needs one.

> That last sentence was half right. A program did turn up wanting a byte's
> number — `lib/json.sol`, and for text rather than for binary files — and what
> it needed was not a byte-array type but two messages,
> [`asByte` and `asCharacter`](REFERENCE.md#a-byte-and-its-number), on the types
> that already existed. Waiting was correct; the shape guessed at was not.

**A bytecode reference.** design.md has an instruction table that is **missing
six opcodes** — `OP_JUMP`, `OP_JUMP_IF_FALSE`, `OP_EXIT_IF_FALSE`, `OP_LOOP`,
`OP_CHECK_BOOL` and `OP_SYMBOL`, which is every jump and the newest two. The
disassembler already exists and prints them; the document simply fell behind.

> Built, as [BYTECODE.md](BYTECODE.md), and the fix for *why* it fell behind is
> the more useful half: the table is checked against
> `solum/include/solum/bytecode.h` by `tests/test_bytecode.c`, so an opcode
> added without a line describing it fails the suite. design.md now points here
> rather than keeping a second table, because one document that cannot drift
> beats two that agree today.

**More examples**, chosen by auditing which concepts have none rather than by
adding more of what is already covered.

> **Done, and the split is what made it answerable.** The files now sit in two
> directories — `examples/` for the twenty-five written to show a feature,
> `programs/` for the seven written to do a job — so the question had a shape:
> does every concept the guide names have a demonstration in `examples/`?
>
> The guide came out clean. All 22 of its sections carry a `Run:` pointer and
> every pointer resolves. What the audit found was on the message axis: **four
> of 121 built-in messages were sent by nothing in `examples/`** — `values`, and
> `modeOf`, `setMode` and `setModifiedAt`. Not lost in the move. They had never
> had a demonstration, and had been carried the whole time by `mirror.sol` and
> `log.sol` happening to need them, which is precisely what nobody notices by
> reading.
>
> Each went into the example it belonged in, and the coverage test now asks for
> `examples/` alone, so a program can no longer stand in for a demonstration.
> Three examples the guide discussed without naming — `walk`, `time`, `keys` —
> are named now, and §18 gained the two paragraphs its pointer was promising.

**A `(group)` versus `{block}` document.** Your own example is the whole of it:

```
m := { x | x:add(#1) }.
(m:value(#42)):print.        ; #43      -- a group evaluates
{ m:value(#42) }:print.      ; <block>  -- a block does not
```

Both are "code in brackets"; one runs now and one is a value. That distinction
is obvious once you have it and invisible before, which is exactly what a
tutorial section is for.

> Written: [`(group)` and `{block}`](GUIDE.md#group-and-block) in the guide, and
> the entry is
> [6.8](COMPLETED.md#68-group-and-block-are-not-contrasted-anywhere--done). Your
> example is what it opens with, unchanged.

---

## Being built

### Solas written in Solum — self-hosting

**The question**, asked on 2026-08-23: could the compiler be written in Solum
itself? Not to replace `solas`, but as proof that this is a language you can
write a system in rather than a scripting language that happens to be pleasant.

Nothing here had ever discussed it. No roadmap entry, no idea, no note — so this
is the first record.

**The strongest form of the proof is the classic one**: the Solum-written
compiler, compiled by itself, produces the same bytes the C compiler produces.
That is checkable to the byte, and this repository already knows how to make
that comparison — [disasm.sol](../programs/disasm.sol) was written to check one
implementation of the `.sob` format against another and found three faults doing
it.

#### What was measured before anything was written

Four things could have killed it. None did.

| | |
| --- | --- |
| Solum can **read** a `.sob` | Already shipped. `disasm.sol` decodes the whole format, i64 sign edge included, and agrees with `solvm --dump` over 5,737 instructions. **Half the format work exists.** |
| Solum can **write** arbitrary binary | The one real unknown. All 256 byte values, NUL included, built with `asCharacter`, joined, written and read back identical. |
| The format is **documented** | [serialize.h](../solum/include/solum/serialize.h) gives every field, [BYTECODE.md](BYTECODE.md) every opcode, and a test holds the document to the header. |
| It is **fast enough** | `disasm.sol` decodes a 12.6KB `.sob` — 1,462 instructions — and prints all of it in 60ms of CPU. Compiling is heavier per byte than decoding; this says seconds, not minutes. |

**And the verifier is on the writer's side.** A `.sob` is untrusted input, so
`solvm` verifies every chunk before running it. A Solum-emitted file with a bad
jump target or a wrong stack height is *reported*, not run — which turns a class
of emitter bug into a message instead of a crash.

#### What is actually hard

- **The frame limit dictates the parser's shape.**
  [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) was 62 frames and a
  recursive-descent parser spends about three per nesting level — `evaluator.sol`
  managed 18 brackets and `lib/json.sol` 28. A Solum parser for Solum would run out
  on ordinary source, so **it must carry an explicit stack**. That is not a
  workaround invented for this: `lib/html.sol` already does it and reaches a
  thousand levels.
- **The size.** `solas` is 2,323 lines of C. The Solum version is likely 2,500 to
  3,500, against 3,774 lines of Solum in `programs/` and `lib/` together — it
  roughly doubles the Solum in the repository.
- **Two compilers rot.** Every language change becomes two changes and the second
  is easy to forget. The mitigation is not discipline, it is the corpus test in
  stage 2: compile every `.sol` here with both and compare, in `make test`, so
  the rot is immediate rather than silent.

#### The stages, and the gate

| | |
| --- | --- |
| **0** | **Done** — [emit.sol](../experiment/emit.sol). Two chunks written out by hand, both byte-identical to `solas`, both running, both decoded by `disasm.sol`. In `make test` as `cmp`. |
| **1** | **Done** — [compile.sol](../experiment/compile.sol) turns source into bytes, and `examples/hello.sol` comes out byte-identical to `solas`. [lexer.sol](../experiment/lexer.sol), [parser.sol](../experiment/parser.sol) and [sob.sol](../lib/sob.sol) are the three pieces. Blocks, temporaries, methods and `@include` are stage 2. |
| **2** | The full language, checked over every `.sol` here: both compilers, same bytes, in `make test`. **Done, and stopped by the frame limit rather than by a missing construct** — 42 of 46 files identical, 0 disagreements. The 4 refusals are `call depth exceeded` ([3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels)), including on this compiler's own source. |
| **3** | **Done.** The Solum compiler compiles its own source and produces the file `solas` produced from it; the compiler that comes out compiles its own source again to the same bytes, and still agrees with `solas` on everything else. In `make test`. |

Where byte-identity turns out to rest on something arbitrary — a table ordering
neither compiler is obliged to agree on — the fallback is instruction-level
equivalence through `disasm.sol`.

#### What stage 0 found

**The back end is not the problem.** `"hi":display.` and `#45:print.` both come
out of [emit.sol](../experiment/emit.sol) byte-identical to `solas`, run, and
disassemble. Between them they cover every section a method-free chunk has:
names, constants, code, line runs, files, file runs, slot names.

- **Writing an i64 is easier than reading one**, which was not the expected
  direction. `disasm.sol` carries careful arithmetic because rebuilding the top
  byte by shifting it into bit 63 overflows and this language traps; writing,
  `shiftRight` is arithmetic and masking after it is right for negatives as
  readily as positives.
- **The verifier catches a bad emitter.** One corrupted opcode byte gets
  *bytecode is internally inconsistent* and exit 65 rather than a crash, so a
  whole class of back-end bug arrives as a message.
- **A float constant is the one thing not yet writable**, and the reason was
  already on the record: nothing reinterprets a float's bits as an integer, so
  `readFloat` in `disasm.sol` takes a double apart field by field and the
  emitter needs that inverted. Laborious, not blocked, and no program compiled
  so far has a float literal.

**So the gate is passed and stage 1 is a real option** rather than a hope. What
it costs is unchanged: 2,500 to 3,500 lines, and a second compiler that has to
be kept honest by the corpus test.

#### What stage 1 has found so far — the tokenizer question, answered

[lexer.sol](../experiment/lexer.sol) scans every token Solum has, and the test suite
compares it against [solas/src/lexer.c](../solas/src/lexer.c) over every `.sol`
file in the repository: **33,034 tokens across 44 files, kind, line, column and
text, all identical.**

**The question it was written to answer was whether a pattern class or a
built-in scanner had to come first. It did not.** The evidence is the file:

| | |
| --- | --- |
| `solas/src/lexer.c` | 265 lines |
| `experiment/lexer.sol` | 297 lines, 169 of them code |

Solum needed **fewer lines of code than the C** to say the same rules, and what
it wanted was `at`, `copyFrom` and comparison — all of which the language had
before it had a collector. Nothing was added for this and nothing was missed.
The one place the language showed through is that a 14-way character dispatch is
a nest of `ifElse` where C has a `switch`, and the punctuation half of it moved
into a dictionary of symbols to keep it flat. That is a readability note, not a
capability gap, and it is [3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)'s
territory rather than a new entry.

**Speed**: 3,470 tokens from a 475-line file in **62ms**, VM start included.
Slow next to C and irrelevant at this scale — a 500-line file scans in the time
it takes to fork a process.

**And the corpus was not enough on its own**, which is the more useful finding.
It passed on the first run, so a rule was deliberately broken to check the test
could fail — and the corpus still passed, because **33,000 tokens of working
Solum contain no `1e` followed by a non-digit**. Working code does not contain
the corners. A fixture of them now runs beside the corpus: bare exponents, `45.`
against `45.5`, a string with a newline inside it, and five ways to be wrong,
since an error token has a position too and both scanners have to recover from
it identically or everything after it disagrees.

#### And stage 1 is done: source in, the same bytes out

[compile.sol](../experiment/compile.sol) compiles
[examples/hello.sol](../examples/hello.sol) to the file `solas` produces from
it, byte for byte, first attempt. The test offers **every** `.sol` file in the
repository to it: **3 accepted and identical, 43 refused as outside the subset,
0 disagreements.** The zero is the number that matters — nothing is quietly
mis-compiled — and the shape of the test means a construct that starts
compiling is counted the moment it does.

**Byte-identity earned its keep.** It forces agreement on what a compiler is
otherwise free to decide, and each of these had to be worked out rather than
guessed:

- Names are interned **when the instruction mentioning them is emitted**, so the
  table's order is the order the code refers to things.
- Constants are shared by value **and type**. `#45` and `45` are two entries,
  and keying them by text alone produces a program that pushes an integer where
  a float was written — which runs, and is wrong. Breaking exactly that is what
  the test was checked against.
- Line runs count bytes rather than instructions.

**The one thing that was real work** is the float encoder in
[sob.sol](../lib/sob.sol). Nothing reinterprets a float's bits as an integer, so
a double is taken apart by arithmetic — sign, the exponent by halving and
doubling into `[1, 2)`, then 52 bits of mantissa — and reassembled as two 32-bit
halves so nothing has to reach bit 63, which would overflow on the way in
exactly as it does when reading. Checked against the C library at twelve values
including `-0.0`, `DBL_MAX` and infinity, **bit for bit**, because a byte count
would have passed on any of them. Stage 0 had listed this as the one thing not
yet writable; it is written.

**Still nothing added to the language.** Three library files and a program, all
in Solum as it already was.

#### Stage 2, first half: blocks and the frames they need

Blocks, parameters, temporaries, groups, slot assignment, frame slot allocation,
lexical capture and nested chunks. **9 of the repository's 46 `.sol` files now
compile byte-identically, and 0 disagree** — the 37 refusals are all the same
thing, a file using control flow that `solas` compiles to jumps.

Two things it got wrong, both caught by the byte comparison and neither by
anything else:

- **A chunk's slot count was written twice** — once in the method header, where
  the format wants it, and again at the head of the nested chunk. The file was
  four bytes long and ran perfectly well, because nothing reads past what it
  needs.
- **A byte takes the line of the token just consumed**, not the line its
  construct began on. Those coincide for one-line statements, which is the whole
  of `hello.sol`, so stage 1 passed without knowing. `parser.sol` now records an
  emit line on every node for this alone.

**The refusals are deliberate and are the interesting design decision here.**
Compiling `ifTrue` as a real send would produce a file that runs correctly and
compares differently. That is the one answer this program must not give, because
the whole value of the exercise is that the comparison means something — so it
refuses by name instead.

#### Stage 2, second half: control flow compiled to jumps

`ifTrue`, `ifFalse`, `ifElse`, `and`, `or`, `whileTrue` and `doUntil`, with the
jump patching, the backward loop, and the two restrictions that keep the
optimisation from changing what a program means — every block written right
there, with no parameters and no temporaries, or it falls back to a real send.

**33 of 46 files now compile byte-identically, up from 9, and 0 disagree.** All
thirteen refusals are `@include`, which is the last construct in the language
this does not do.

One mistake, and it was the interesting kind: the first version **never compiled
the receiver**. In `solas` the condition is already on the stack by the time the
selector is read, because the send loop put it there; splitting the inlined path
out into its own method dropped that step silently, and the jump offsets then
looked wrong in a way that pointed at the patching rather than at the missing
value. The lesson is the ordinary one about extracting a function from a loop —
what the loop had already done for you goes with it.

#### `@include`, and the wall at the end of it

The last construct: the search-beside-then-search-path rule, compile-once, the
depth limit, and the per-chunk file table that lets a line number say which file
it is in. **42 of 46 files now compile byte-identically and 0 disagree.**

**The four that do not are not a missing construct. They are `call depth
exceeded`** — and this is the finding the whole exercise was most likely to
produce. It manages nine levels of nested blocks and fails at ten; `solas`,
recursing on the C stack, is untroubled at thirty. The files that nest deeper
include `experiment/lexer.sol`, `experiment/parser.sol` and the compiler's own source.

**So the language cannot yet compile its own compiler, and the reason is a
documented limitation of the language rather than anything about the compiler.**
That is [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) with the
best evidence it will ever have, and it was predicted here before any of this
was written: *the deep case, a block inside a block inside a block, is the one
this subset does not do yet — when it does, it will carry an explicit stack the
way `lib/html.sol` does*.

**The prediction named the right fix and the wrong half**, which took a
measurement to find out. The first account of this said the parser was what ran
out and an explicit stack in it was the answer. So the compiler was split into
[compiler.sol](../experiment/compiler.sol) — a library rather than part of the program,
so that a tree nobody parsed could be handed to it directly — and it fails at
**exactly the same depth**: nine levels pass, ten do not, whether you parse
alone, compile a hand-built tree alone, or do both. Each half spends about six
frames a level.

So fixing the parser alone buys nothing at all, and the honest options are two:
both halves carry their own stack, or the cap moves. Built with
`SOL_FRAMES_MAX` at 512 rather than 64 both halves reach 83 levels — the same
six frames a level with eight times the room — which is the one-line change 3.5
has always named, and a decision about the language rather than about this
program.

One thing worth recording about the comparison: **both compilers have to be
given the same search path.** The file table records where an included file was
found, so the path is part of the output, and `solas` derives its default from
where its own binary sits — which nothing in Solum can see.

#### Stage 3: it compiles itself

**Solum is self-hosting.** `solas` compiles
[compile.sol](../experiment/compile.sol) to a first generation; that generation
compiles its own source to a second, **byte-identical to the first**; the second
compiles its own source to a third, identical again; and the second still agrees
with `solas` on every other file. All four claims are in `make test`.

**It was one line of C away the whole time, and the line was not in the
compiler.** The last four files failed on `call depth exceeded`, and the cap had
been left at 64 frames because `SOL_STACK_MAX` was derived from it -- so raising
it looked like it meant an eightfold larger `SolVM`, which lives on the C stack
and would no longer fit on a thread. The two numbers did not have to be one
number. Frames are 56 bytes; giving the stack its own size made 256 frames cost
**4% more memory for four times the depth**, and
[3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) has the table.

What that bought, beyond the compiler: plain recursion from 62 levels to 254,
`evaluator.sol` from 18 brackets to 83, `lib/json.sol` from 28 levels of nesting
to 124. Three programs that had each written down a limit found it moved.

**The whole exercise added nothing to the language** except a number that was
always a choice. Six library files and two programs, in Solum as it already was:
[lexer.sol](../experiment/lexer.sol), [parser.sol](../experiment/parser.sol),
[compiler.sol](../experiment/compiler.sol), [sob.sol](../lib/sob.sol),
[emit.sol](../experiment/emit.sol) and [compile.sol](../experiment/compile.sol).

#### Parked, on purpose

**The proof is finished, so the code stops being maintained.** Everything moved
to [experiment/](../experiment/): the four libraries off the search path, the
two programs out of `programs/`, and all of it out of `make test`.

The reason is the one the roadmap's admission rule would give. A second compiler
has to be taught every construct the first one learns, and that tax falls on
every change to `solas` — for no gain, because **the proof does not need
repeating to stay true.** It was true on 2026-08-23 and the account of what was
true is written down.

So this is expected to fall behind the language, and the first sign will be a
file in there failing to compile. That is the trade, not a defect.
[experiment/prove.sh](../experiment/prove.sh) runs both halves again on demand —
the 47-file comparison and the fixpoint — and
[experiment/README.md](../experiment/README.md) says what would have to happen
to bring it back: not the compiler, which is correct on every input here, but
the front door, where an error is raised with a VM stack trace instead of
reported the way `solas` reports one.

#### An aside: the trap the cheatsheet warns about, walked into

`self:included:includes(path):ifTrue({ nil }):ifFalse({ ... })` — chaining
`ifTrue` into `ifFalse`, which the cheatsheet's *six rules that bite* names in
so many words. `ifTrue` answers the block's value, so the `ifFalse` went to nil
and the send failed. Written by the same hand that wrote the warning, four hours
later.

**The test's `it runs` check turned out to be three different claims**, and only
one of them was true. Requiring exit zero failed on the examples that exit
non-zero deliberately. Comparing the two files' output failed because a
byte-identical program that reads the clock prints something different every
time. What is left is the only thing a byte comparison cannot already tell you:
that the file gets past the verifier.

#### No features were added to make it possible, and that is the point

The suggestion that raised this also proposed a pattern class and a built-in
tokenizer, to make the compiler shorter to write. **Deliberately not done**, for
two reasons.

The first is that it would weaken the claim: a language that compiles itself with
help from a tokenizer written in C is proving something smaller, and the proof is
strongest when nothing was added to make it possible.

The second is the more useful one. **A 3,000-line Solum program is the biggest
evidence generator this repository will ever have.** It presses on the frame
limit, on blocks that cannot escape their frame, on the absence of an early
return, and on string building at a scale nothing here has reached — all at once,
in one program that has to work. Adding features in advance to smooth its path
throws that evidence away before it is collected. Whatever it genuinely cannot
have becomes an entry the ordinary way, with a program behind it.

**The tokenizer question specifically is open and gets answered by stage 1**: the
lexer gets written by hand, and if 300 lines of character scanning is tolerable
the question is closed, while if it fights the language that is the entry.
Nothing here argues against a scanner — only against building one before knowing.
Worth noting that pattern matching has never appeared in this document at all,
so stage 1 would be the first evidence either way; and that Solum's own lexer is
265 lines of C for a language with no keywords, which is a small thing for a
regular expression engine to be bigger than.

---

## Deferred, with a trigger

### A truncating divide on integer

`quotient(n)` and `remainder(n)` beside `div` and `mod` — the same division
cutting **towards nought** instead of flooring.

**The floored pair is not in question and should not change.** `#-7:div(#2)` is
`#-4` and `#-7:mod(#2)` is `#1`, which keeps a remainder inside `[0, n)` where
indexing and cyclic arithmetic want it; [design.md](design.md) gives that
reason and it is the right default. This is about the *other* pair, which some
languages mean by the same two symbols.

**One program wants it.** BASIC's `\` and `MOD` cut towards nought and take the
sign of the left-hand side — `-7 \ 2` is `-3` and `-7 MOD 2` is `-1` — and so
do C's `/` and `%`. [programs/sola.sol](../programs/sola.sol) compiles them, and
is the only customer there has ever been.

**It already gets the right answer, which is why this is deferred and not
needed.** The truncating quotient is the floored one plus one when there is a
remainder *and* the two signs differ, and nothing in that leaves i64:

```
#-7:div(#2).                     ; #-4   -- floored
#-7:mod(#2).                     ; #1    -- so there is a remainder
; the signs differ, so add one:  ; #-3   -- which is what BASIC says
```

So the case for building it is **size and speed, not correctness**: one send
against twelve instructions and two frame slots, at every `\` and every `MOD` a
listing writes.

**What it replaced is the useful part of the story.** The first version of that
compiler went through the float divide — `a:asFloat:div(b:asFloat):truncated` —
which is four sends, gets every sign right, and is **wrong above 2^53** where a
double can no longer hold every whole number:

```
#9007199254740993 \ #1     via float 9007199254740992     exact 9007199254740993
#9007199254740993 \ #3     via float 3002399751580330     exact 3002399751580331
```

That is the shape of thing this list exists to catch: a workaround that looks
like a performance trade and is quietly a correctness one. Trading bytes in a
file nobody reads for an answer that is always right is the easy direction, and
it was taken.

**Not `divRounded`**, which was the first name suggested for it and is wrong
twice over. Rounding is a third operation and it disagrees with truncation in
*both* directions, so it would fix nothing and break the positive case that
already works:

| | true | `div` (floored) | rounded | truncating (wanted) |
| --- | --- | --- | --- | --- |
| `#-7 ? #2` | -3.5 | **-4** | **-4** | **-3** |
| `#7 ? #2` | 3.5 | 3 | **4** | **3** |

`quotient` and `remainder` are the ordinary names for the truncating pair, they
do not collide with `div` and `mod`, and they sit beside a float half that
already says which way it goes — `floor`, `ceiling`, `rounded`, `truncated`.

**Trigger:** a second customer, or somebody measuring a SolaBasic loop where `\`
or `MOD` is the cost. One program wanting a message is what
[`indexOf(what, #from)`](REFERENCE.md#string) had before a second one turned up
and it was built; this is at the same stage.

---

### `$character` literals and Unicode

`$x` for a character, and `$😊` for one outside ASCII.

The character type on its own is small. The problem is that it cannot be decided
separately from what a string is, and today [a string is
bytes](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only): `size` counts
bytes, `at` answers a one-byte string, and `"café":size` is 5.

So `$x` forces the question. If a character is a **code point**, then `at` should
answer one, and `size` should count them, and every string operation changes —
that is the Unicode work, and it is a different piece of work rather than a
larger version of this one. If a character is a **byte**, then `$😊` cannot exist
and the type buys almost nothing over a one-character string.

Adding an ASCII-only `$x` now would make the Unicode decision harder later,
because there would be a character type with the wrong semantics to migrate.

**Trigger:** decide what a string is first. If strings become code-point aware,
a character type follows naturally and `$` is the right spelling for it.

---

### Namespaces for included files

An included file binds into the one global namespace, so a library's names and a
program's names sit in the same space. Should an include get a namespace of its
own?

**Not yet, and the trigger is somebody other than you writing a library.** A
flat global space works while one person can see every name in it; that is the
thing which stops being true first when a library arrives from outside.

**What is already covering it.** A module system does four jobs, and the score
today is one and a half:

| job | status |
| --- | --- |
| once-only initialization | **done** — a file is compiled once, keyed by where it lands on disk |
| a namespace | **approximated** — `json:read(...)` is namespaced access already; only the name `json` is in the flat space, and a collision on it is a compile-time warning ([6.21](COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done)) |
| an export boundary | **absent** |
| declared dependencies | **absent** |

And the [three tiers](COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done)
that came out of 6.21 do most of the rest. Two of the four shipped libraries
claim **no global at all** — `integer:asUtf8` and `integer:timesCollect` are
sends rather than bindings, so there is nothing there to collide with. The other
two claim one name each.

**The design argument against, which this document has used before.** A module
is a new *kind* of thing: not an object, not a message, but a compile-time
scope. That is the same objection that turned down
[`@ifdef`](#more--directives-define-ifdef-once) — a second mechanism where an
existing one does the job — and an object holding slots already is a namespace.

**If it is ever built, the shape is an object rather than a module.** Not a
module system: an include that binds into an object instead of into the root,
with the includer naming it.

```
Json := @include "json.sol".      ; a sketch; not valid today
Json:read(text).
```

Two things make that more tractable than it was:

- **The compiler already tracks which names each file binds.** That record —
  `BoundName { name, file }`, shared across a compilation — went in for the
  rebinding warning. Sending those bindings to a fresh object rather than to the
  root is a smaller step from there than it looks.
- It would not touch methods on built-in classes, and should not: `integer:asUtf8`
  belongs to `integer` rather than to whoever included the file.

The obstacle is syntactic rather than deep. `@include` is deliberately a
statement — `x := (@include "lib.sol")` is refused by name — so the binding form
would have to be designed rather than falling out.

**What it still would not give you** is the export boundary, which is the half
worth having once libraries come from elsewhere. `json:digits := "abc"` breaks
the parser from outside it, and namespacing the name `json` does not change
that. Privacy needs something the language has not got: slots cannot be removed
and `slots` lists everything, so it would be a new concept rather than a use of
existing ones.

**Two triggers, either of which is enough:**

- Somebody other than the author writes a Solum library.
- One program needs two libraries that clash on a name. Today the answer is
  "rename one", which works right up until you do not own one of them.

### 6.32 A script cannot be run with less than the whole machine

**Deferred, and it kept its roadmap number** — cited from about thirty places,
and numbers are never reused. It sat in section 6 for four days as the last open
decision and was moved here on 2026-08-22 without being taken.

**Why it is here and not there.** Every other entry that reached the roadmap came
from a program wanting something and not having it. This one came from a
*concern* about a use nobody has: a webserver producing pages by running Solum,
where injection could turn untrusted input into code the server runs. That is a
real risk in that shape and the shape is hypothetical. Solveig is an experimental
language and was never planned for web services; the question was asked because
this *might* one day be a thing, not because it is one — and it may never be,
in which case the right amount of mechanism to have built is none.

**The trigger, said exactly:** somebody runs a Solum script they did not write,
or embeds the machine somewhere its input arrives from a stranger. Either makes
this urgent and neither has happened. Until then the honest position is the one
[embedding.md](embedding.md) already takes — a host gets limits, and gets told
plainly that nothing here is a sandbox.

**What was learned while it was open is kept in full below**, because deciding
this later from a blank page would cost far more than keeping it does. Two
things came out of it that were worth having on their own and are already built:
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done),
the limits a host may set, and the whole
[embedding interface](embedding.md), which exists because working out what a
permission would attach to meant first saying what a host may rely on.

---

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

**That has now been tried, and then written down** — in that order, and the
order was the useful part. [embed/host.c](../embed/host.c) holds a machine and
runs [serve.sol](../programs/serve.sol) once per request; it is 136 lines of
code, two more than `solvm`'s own front end. It **found a use-after-free on its
first run**: a chunk recorded which VM had interned its names by pointer, and a
host builds each request's VM as a local, so every one landed at the same
address and the chunk went on reading the freed machine's name table. Fixed in
0.14.1 — the record is a serial now — and the point for this entry was that
nothing in the repository was shaped to catch it, because nothing had ever run
two VMs in sequence at one address.

**The interface is now stated.** [solum/embed.h](../solum/include/solum/embed.h)
is the whole supported surface, [embedding.md](embedding.md) is the contract in
prose, and [tests/test_embed.c](../tests/test_embed.c) has a case for every
promise it makes. Writing it caught a second mistake at once: this project had
said a host must call `sol_vm_intern_chunk`, and `sol_vm_run` does it — the
defect was inside that function rather than in a call somebody could miss, so
the interface is one rule simpler than it had been written up as.

**So this entry's precondition is met.** A permission is a promise about what a
host may rely on, and there is a list of that now — including what is
deliberately *not* promised, which is where a permission scheme would have to
live: no route for a run's output except by an agreed name, no way to silence a
failing run's stderr, and a fresh VM per request being the only safe choice.
What remains here is the decision itself, unchanged in kind and better furnished
than it was.

**Which way round is the default** still matters for the command line, where the
chooser is a person. Safe-by-default with `--unsafe` to enable protects the
script you did not write and breaks every existing use, including this
repository's own tests and `programs/tools.sol`. Unsafe-by-default with `--safe`
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

**And one capability per message is not fine enough either.**
[serve.sol](../programs/serve.sol) is the case written down, and it is told what
it was asked entirely through `system:environment` — `PATH_INFO` and
`QUERY_STRING` are how CGI hands a handler its request. So a scheme that can
only say yes or no to `environment` has to say yes, and has then also said yes
to `AWS_SECRET_ACCESS_KEY` and everything else the server process is holding.
The permission that a webserver *must* grant is the one that gives away its
secrets.

That does not settle the shape, but it rules one out: the granularity has to be
finer than the message where the message names something. Which is a familiar
answer — it is a list of allowed variables, or of allowed paths — and it is more
work again, since a capability that names things is a capability that has to be
matched against them.

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
[3.3](ROADMAP.md#33-verification-does-not-promise-termination), which says the verifier
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

### Extensions: a capability from a binary rather than from the VM

**Asked again on 2026-08-25, with two customers named: SQLite and SDL2.** They
do not stand alike, and the difference is this entry's own trigger — *wanting
something Solum cannot express*.

**SDL2 fires it.** A graphics surface cannot be expressed in Solum at all, at
any speed, and no amount of library writing gets there. That is the trigger
stated exactly.

**SQLite does not.** A database *can* be written in Solum — slowly, and without
thirty years of somebody else's work in it, but written. The argument for it is
performance and ecosystem, which are good arguments and are not this one. It
would ride along after the mechanism exists rather than justifying it.

**And the cost is the sentence on the front page.** *No dependencies beyond a
C11 compiler and `make`* is checked on three platforms by CI, and an extension
mechanism is the first crack in it even if every extension is optional. That is
possibly worth paying and it should be paid **deliberately**, which is why this
is a decision and not a task.

Could Solum gain something it cannot express — a database, a graphics surface, a
compression codec — from a C library loaded at run time, rather than by growing
the core VM? The sketch offered with the question was a `load` message for the
binary and a `.sol` file providing the interface.

**Yes, and the architecture is more ready for it than anyone had noticed.** A
primitive is already nothing but a C function pointer hung on an object, the
functions that hang it there are already public, and `system` — the closest
thing here to a namespace of C functions — is built from exactly the three calls
an extension would make: `sol_object_new`, `sol_object_define` into the root,
then a run of registrations. The `.sol`-interface half of the sketch needs no
invention at all; it is [lib/shell.sol](../lib/shell.sol)'s shape exactly, one
global with everything hung off it.

**Half of it works today**, for anyone building their own binary.
[embed/host.c](../embed/host.c) is most of the example: include
`solum/object.h`, call `sol_object_define_primitive` before `sol_vm_run`, and
the messages are there. That is how all 285 built-in slots are installed, and
nothing distinguishes an extension's from a built-in's.

The catch is a promise rather than a mechanism.
[embed.h](../solum/include/solum/embed.h) says it is *the whole supported
surface*, and that anything else under `solum/include` is the machine's own
business and may change without notice — and `SolPrimitive` lives in
`object.h`, outside it. So it works, and nothing says it will keep working.

**Three things are missing**, in ascending order of difficulty.

*A supported surface.* An `extend.h` standing to extensions as `embed.h` stands
to hosts, saying what an extension may rely on. It would have to state three
things a newcomer gets wrong: arity is not checked for you, only the receiver
type is; errors are out of band, through `sol_vm_runtime_error`; and the
collector's rule, which is that nothing may hold a heap pointer across an
allocation unless it is reachable from a root. That last one has a trap worth
naming — the temporary-root stack is eight deep and overflowing it calls
`exit(1)` with no diagnostic.

*A loader and an ABI.* `dlopen`, one exported entry point per library, and a
version handshake. There is no ABI version today: `SOLUM_VERSION` is printed and
never compared to anything, and the only version check in the project is
`.sob`'s exact-equality refusal, whose policy — refuse, do not guess, recompile
— is the one to copy. `SolValue` is passed by value and `SolObject`'s layout is
exposed, so nearly any struct change is an ABI break.

There is also a concrete build blocker. `libsol.a` is a static archive and the
four binaries each link a private copy, with no `-fPIC` and nothing exported.
**As built, a loaded bundle could not resolve `sol_*` back into `solvm` at
all.** The fix is to build `libsol` shared and link everything against it, which
is a real change to how the project ships.

*Somewhere for a foreign resource to live, and something to close it.* This is
the only real design decision, and it is the interesting one.

**The collector has no finalizer of any kind.** Sweeping frees a cell's own
parts and then the cell; nothing user-supplied runs. So a database connection
stashed in a Solum value would be never marked (harmless), **never freed**, and
never counted against `--memory`. The shape that answers it is a foreign cell
carrying its own release function —

```c
typedef struct {
    SolGCHeader gc;
    void       *handle;
    void      (*release)(void *handle);
    const char *kind;      /* "sqlite connection", for the error message */
} SolForeign;
```

— as a new value type rather than as a use of `SolObject.payload`, which is
declared, written once as zero, read by nothing in the whole tree, and would
still leave no home for the release function. A new *value* type also earns a
compiler warning from `mark_value`, which has no `default` on purpose; the two
to watch are `free_cell` and `cell_size`, which are `if`-chains and will not
warn.

**And that shape dissolves what would otherwise be ugly.** A limit-stop is
deliberately not catchable and `ensure` does not run
([6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)),
so a script relying on an explicit `close` leaks every time it is stopped. But
the whole heap is freed at VM teardown regardless of reachability, and
[3.10](ROADMAP.md#310-a-vm-cannot-be-reused-across-runs) already says a fresh VM
per request is the only safe choice — so the VM always dies, and a release hook
fires even for a program that was taken away. Explicit `close` has no such
property.

**What it would cost, said plainly.**

- **It falsifies a sentence the design leans on.** `design.md` says *"nothing
  has to be released: a file is read or written whole, and no message hands back
  anything a program is obliged to close."* A connection would be the first, and
  that sentence is the reason an uncatchable stop is cheap.
- **Loading native code is unlimited authority**, past every check there is —
  which reopens
  [6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine) in the
  largest possible way. True of every language's FFI, and the mitigation is the
  same: a host that does not want it does not enable it.
- **An ABI is a promise that constrains refactoring.** Today `SolObject` and
  `SolValue` can change freely because everything is rebuilt together.
- **Extensions are where a portability story goes to die.** Four binaries and a
  static archive build wherever `cc` does; bundles and `dlopen` do not.

**Trigger:** somebody wants a capability that cannot be written in Solum and is
not worth putting in the VM. A database, a window, a codec. Nothing wants one
today, and the language has managed four days of real programs without.

**And if it is ever picked up, the first move is not any of the above.** Write
one throwaway extension — fifty lines, something with nothing to release, a
hash or a checksum — build it, load it, and find out what the path actually
wants. That is the method that has paid here repeatedly:
[serve.sol](../programs/serve.sol) found 3.7, [host.c](../embed/host.c) found a
use-after-free, [disasm.sol](../programs/disasm.sol) found three faults in the
documents it was written from. An afternoon of that would settle more than
another page of this.

**The first candidate to be proposed for this was a regular expression engine**,
on 2026-08-24, and it is worth saying where that landed: it fails the trigger
above, because a matcher can be written in Solum and this entry is for things
that cannot — but it is close to the ideal *throwaway*, because a compiled
pattern is the smallest thing that has to be given back and so the smallest test
of the foreign cell. The reasoning is [below](#regular-expressions).

### Regular expressions

**No to a literal; defer the capability; and the most useful finding is neither
of those.** Raised on 2026-08-24, with a second question behind it: if the
objection to an engine is its size, is this what
[extensions](#extensions-a-capability-from-a-binary-rather-than-from-the-vm) are
for? It is. But size was the weakest of the four objections, and two of the
other three turned out to be answered already, by things this repository had
decided for other reasons.

#### The argument that was not available, and would have been false

*No program here has wanted one* is exactly the reading of an absence that
[design.md](design.md#what-the-language-is-for) now rules out, and it was written
down two days before this was asked. So the question had to be settled on shape.

It is also untrue. Every `.sol` file in the repository was surveyed for
hand-written scanning, and there is **roughly 460 lines of genuine
character-class, repetition and alternation work**:

| file | scanning lines | what |
| --- | --- | --- |
| [lib/html.sol](../lib/html.sol) | ~150 of 475 | names, entities, attribute values, text runs |
| [experiment/lexer.sol](../experiment/lexer.sol) | ~120 | every token class; the float scanner backtracks by hand |
| [programs/expect.sol](../programs/expect.sol) | ~100 | `commentAt`, `asCount`, `wordBefore`, `markersIn` |
| [lib/json.sol](../lib/json.sol) | ~70 | the number grammar, string escapes, control bytes on output |
| [programs/serve.sol](../programs/serve.sol) | ~20 | `urlDecoded`, `isNoteName` |

`json.sol` has `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?` written out by
hand — the canonical textbook expression — and `html.sol` has three-way
alternation over quoted attribute values. The demand is real and it is not
small.

#### What repeats is the cursor, not the pattern

Three idioms account for most of it, and the counts are the finding:

| idiom | sites | what it is |
| --- | --- | --- |
| `{ pred(peek) }:whileTrue({ step })`, then `copyFrom(start, pos:dec)` | at least 15 | `X+` with a capture |
| `"<set>":indexOf(c):notNil` | at least 12 | a character class |
| `split(x):join(y)` | 2 | replace, which the language does not have |

The first is `takeWhile`; the second is a character-class predicate. Neither is
a pattern *language* — they are methods on something holding a position, and
every one of the five files above hand-rolls that same cursor. `page.sol` even
fakes a six-way alternation out of one: `"h1 h2 h3 h4 h5 h6":indexOf(node:name)`.

**So the actionable half of this entry is a `lib/scan.sol`** — `peek`, `match`,
`skipWhile`, `takeWhile`, `takeUntil` — which is perhaps eighty lines of Solum,
needs no change to the VM, adds no notation, forces no decision about what a
string is, and is bounded by `--steps` because every step it spends is an
instruction. It would collapse the first idiom across five files. Nothing about
it requires this entry to be settled first.

**That half is built.** It went to ROADMAP 5.5 on 2026-08-25 and is
[done](COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done) the same
day — `lib/scan.sol`, with `json.sol` converted onto it. The survey above was
its case: five programs wanted a cursor and
each wrote its own, which is the admission rule met as duplication rather than
as a failure. What stays here is the argument about regular expressions, which
is what this entry is for. The two are separable, and separating them is most of
the finding.

#### And [3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) decides its shape

Whatever gets built, the combinator spelling — the one everybody reaches for
first, where a matcher is a block returning a block — does not work:

```
makeDigit := { | lo, hi |
    lo := "0". hi := "9".
    { c | c:greaterOrEqual(lo):and({ c:lessOrEqual(hi) }) } }.

makeDigit:value:value("7"):print.
solvm: block outlived the frame it was written in
```

It has to be object-shaped instead, which composes today with nothing added:

```
range := object:new.
range:lo := "0".
range:hi := "9".
range:matches := { c | c:greaterOrEqual(self:lo):and({ c:lessOrEqual(self:hi) }) }.

runOf := object:new.
runOf:inner := nil.
runOf:matches := { s | | i, n |
    i := #1. n := #0.
    { i:lessOrEqual(s:size):and({ self:inner:matches(s:at(i)) }) }:whileTrue({
        n := n:inc. i := i:inc }).
    n }.

digits := runOf:new.
digits:inner := range:new.
digits:matches("8080ab"):print.       ; #4
```

That is not a workaround: a cursor holds a position, and position is state, so
the object spelling is the one the thing wanted anyway. It is the same finding
[lib/html.sol](../lib/html.sol) reached by writing an explicit stack.

#### Against a literal in the language, and this part is a firm no

A regular expression is a second language with its own operators — `*`, `+`,
`?`, `|`, `{n,m}` — its own precedence, its own escaping, and its own control
flow, since alternation and repetition are branching and looping. Put in a
literal, it is invisible to `solas`, unreportable until run, and **the one thing
here that could not be overridden**: `integer:add := ...` works, and no
spelling of `regex:\d := ...` ever could.

The precedent is already set at a smaller scale and went the other way.
`fill` was kept from growing into a format language — bases went out to `asBase`
and `asInteger(#n)` so that, as the reference puts it, *nothing in the spec
starts looking like a conversion character*. The three notations that do live
inside strings here — `fill`'s blanks, `asString`'s padding spec, `asTime`'s
`strptime` format — are descriptive and terminate trivially. A pattern is
computational. That is the line, and it was drawn before this came up.

#### But a *library* carrying a foreign grammar in a string is settled precedent

[lib/shell.sol](../lib/shell.sol) takes an entire second language inside a
string — sh, with operators, quoting, globbing and `&&` — and the design
accepted it, with the bargain written into the header: *build the command out of
things you wrote, not out of things a file or a user gave you.*

A `lib/re.sol` taking a pattern as an ordinary string is that shape exactly,
down to the identical hazard: a pattern built from a stranger's input is the
same class of mistake as a command built from one. **So the objection above is
to the literal, not to a library**, and conflating the two was an error made in
arguing this out.

#### As an extension, which was the question

Of the four objections, the extension route settles two outright:

| objection | does an extension answer it? |
| --- | --- |
| ~1,500 lines, and the third-largest C file in the project | **Yes** — and POSIX regex is in libc, so it is zero lines |
| [2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only): byte semantics become migration debt | **Yes** — an extension's semantics are not a language promise; version the bundle |
| `sōlum`: a second language in a string | **Not its to answer** — `shell.sol` answered it, for libraries |
| [3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work): unbounded work inside one instruction | **No** — but see below; the engine decides this, not the mechanism |

The last one was argued badly. Catastrophic backtracking is a *Perl* property,
not a regex property: POSIX requires leftmost-longest and ERE has no
backreferences, which pushes an implementation towards simulating the automaton
rather than backtracking through it. Measured against the system `regexec`, the
classic bad patterns are flat —

```text
^(a+)+b$          n=24…40    0.0 ms
^(a|a)*b$         n=18…34    0.0 ms
^(a|aa)+b$        n=18…34    0.0 ms
^(a*)*b$          n=18…34    0.0 ms
^(a?){20}a{20}$   n=18…26    0.0 ms
```

— and matching is linear in the input, four times the bytes for four times the
time: 77ms at 1MB, 2,562ms at 64MB. 3.7's own table has `indexOf` over 64MB at
0.27s, so this is **the same complexity class, about ten times the constant**.
It is not a new hole in `--steps`; it is the existing one, one primitive wider.
Choosing POSIX ERE over PCRE2 removes the objection and the dependency together,
and leaves a bundle that builds wherever `cc` does — which softens *extensions
are where a portability story goes to die* rather more than a third-party engine
would.

#### It fails the trigger, and suits the first experiment

The trigger above is *a capability that cannot be written in Solum and is not
worth putting in the VM*. Regex satisfies the second half and **fails the
first** — a POSIX-semantics matcher is a couple of hundred lines of Solum, built
the object way for the reason given above. A codec, a socket, a window cannot be
written here. This can.

But the extensions entry closes by asking for something else: one throwaway,
fifty lines, *something with nothing to release*, built to find out what the
path actually wants. **Regex is close to the ideal thing to build it with, and
the wrong thing to want it for.** `regcomp` allocates a `regex_t` that
`regfree` must take back, which makes a compiled pattern the smallest possible
test of the one real design decision in that entry — the foreign cell carrying
its own release function, and whether the hook fires for a program stopped by a
limit. A checksum cannot test that. A database can, but costs a dependency, I/O
and a network first. A compiled pattern is deterministic and holds exactly one
thing that must be given back.

Staged, that is two afternoons: **v0** compiles, matches and frees in one call,
retaining nothing — the literal *nothing to release* case, which finds out what
`dlopen` and the version handshake want. **v1** keeps the compiled pattern and
tests the finalizer, including under a limit-stop. Both come after the build
restructure and the supported surface, which are the real work and are
regex-independent: `libsol.a` is still a static archive with no `-fPIC`, so as
built, a loaded bundle could not resolve `sol_*` back into `solvm` at all.

#### One thing the survey found that is not about patterns at all

`expect.sol` used `indexOf(suffix):notNil` where it meant `endsWith`, at six
sites, because the language has neither `startsWith` nor `endsWith`:

```text
isSol:value("hello.sol.bak").   ; true  -- not meant
isSol:value("notes.solid").     ; true  -- not meant
isMd:value("draft.md.orig").    ; true  -- not meant
isMd:value("a.md.sol").         ; true  -- a .sol file, checked as markdown
```

`check` dispatched on `path:indexOf(".md"):isNil`, so the last of those would
have been run through the markdown checker. Nothing triggered it — no such file
exists — but `notes.solid` is not a fanciful spelling in a repository that ships
a binary called `solid`. That is a real defect with a program behind it, and it
is the one thing here that satisfies the roadmap's admission rule outright.

**Fixed the same day.** Not by adding `endsWith` to the language: the six sites
share one helper in the program that needed it, which is the answer this entry
reaches for scanning as a whole, at a scale small enough to settle in an
afternoon.

```
string:endsWith := { suffix |
    self:size:greaterOrEqual(suffix:size):and({
        self:copyFrom(self:size:sub(suffix:size):add(#1), self:size)
            :equals(suffix) }) }.

"hello.sol":endsWith(".sol"):print.       ; true
"hello.sol.bak":endsWith(".sol"):print.   ; false
"a.md.sol":endsWith(".md"):print.         ; false
```

Whether that belongs on `string` for everyone is the same question
`lib/scan.sol` asks, and it is not answered by one program wanting it once.

**Trigger:** `lib/scan.sol` never got one — it became
[5.5](COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done) and is
built. For regex itself, the trigger is the extension
mechanism existing, which has its own trigger and is not this one. The literal
stays refused whatever happens to the other two.

### An early exit from a loop

[3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing) records the
fact: a `whileTrue` body cannot end its own loop, so a loop that must stop from
inside carries a boolean whose only job is to stop it, and the only other exit is
to raise an error and catch it outside. Six files do the first, and that entry
deliberately no longer counts them — the number went stale twice and is not what
the case rests on. This is the feature
that would answer it, and why it is not being built yet.

**What the relatives do:**

| | |
| --- | --- |
| Lua, Ruby, JavaScript, C | a `break` keyword |
| Ruby, additionally | `throw`/`catch` — a *tagged* non-local exit, kept deliberately separate from exceptions because leaving a loop is control flow and not failure |
| Common Lisp | `block` / `return-from`, named and lexical |
| Smalltalk | nothing of its own — `detect:ifNone:` and friends, each implemented *with* `^` |
| Scheme | `call/cc`, which is every answer at once and none of them small |

Ruby's pair is the interesting one, because it is exactly the distinction Solum
is missing: `error:raise` already works as an exit and is the wrong register, in
the same way `throw` exists in Ruby so that leaving a loop does not have to
pretend to be an error.

**Why not a `break` keyword.** Two reasons, neither about difficulty. Control
flow here is message sending, and a keyword would be the language's first
control-flow keyword — which is the argument that already refused
[`ifTrue{...}`](#iftrue--a-block-argument-without-parentheses): it makes a
message send look like syntax exactly where the language works hardest to prove
it is not one. And `break` and `continue` are already Solid's commands, so the
word is taken inside the project's own toolchain.

**Why not `detect` and its family**, which is the Smalltalk-flavoured answer:
neither site it would have to serve is a collection enumeration.
`html:element:find` is a worklist traversal that pushes onto the very array it
is walking, and `json:parseArray` is a scanner over a cursor. It would also have
to answer the reference's standing argument against multiplying search messages
— *"one message that answers where is worth more than two, one of which only
answers whether"* — which is why there is no `includes`.

**The shape that would fit**, if this is ever built: a message a block sends to
leave the loop it is the body of, answering a value, and distinct from
`error:raise` so that a caller's `onError` is not the thing that catches it.
Cheap in the spelling the compiler inlines and not cheap anywhere else — see
3.13 for that fork, which is the whole cost.

**Trigger, said exactly:** a loop whose body must *skip its remainder* once the
flag is set. Today none does — every site either sets the flag at the tail of a
branch or wants the rest to run, and `html:closeThrough` deliberately runs a
`self:pop` after setting it. The moment one does not, the flag has to be
threaded through the body as `done:not:ifTrue({ ... })` and the workaround stops
being a condition and starts nesting. That is a bug class rather than a
readability complaint, and you would know it had happened.

#### `forever`, and `break` as a message — 2026-08-23

A shape was proposed that this entry had not considered: a loop with **no
condition at all**, left only by breaking out of it.

```
{ ... :break ... :continue ... }:forever
```

Two things about it are better than what is above, and one problem survives
untouched.

**`break` need not be a keyword.** Written as a message on `boolean` it reads
`i:greaterThan(#10):break.` — a send, sitting exactly where `ifTrue` would sit,
and answering nil when the receiver is false. That dissolves the first of the
two objections recorded above: there is no new keyword, and nothing starts
looking like syntax. The second objection survives: `break` and `continue` are
still Solid's commands, and the word is still taken inside the project's own
toolchain.

**A conditionless loop makes `break` unambiguous.** Bolting an exit onto
`whileTrue` raises the question of what it means when the condition would also
have stopped the loop; `forever` has nothing but its exits, so a `break` is the
only thing it can be about. That is a cleaner construct than the one this entry
was imagining, not merely a different spelling.

**And it is writable today, entirely in the library**, with `break` and
`continue` raising markers that `forever` catches and anything else passing
through:

```
boolean:break := { self:ifTrue({ error:raise("--break--") }) }.

block:forever := {
    { { true }:whileTrue({ self:value }) }:onError({ e |
        e:message:equals("--break--"):ifFalse({ error:raise(e:message) }) }).
    nil }.
```

**What it costs, measured over 200 runs of a 1,000-iteration loop against the
flag idiom it would replace:**

| | |
| --- | --- |
| the flag, in a literal `whileTrue` the compiler inlines | 0.058s |
| `forever` with `break` | 0.097s — **1.7×** |
| `forever` with a `continue` firing every other pass | 0.289s — **5.0×** |

Some of that is unavoidable in any library loop: `control.sol` records about
1.30× for a block call per iteration, which `{ ... }:forever` pays and an
inlined `whileTrue` does not. The rest is the error machinery, and **`continue`
is where it hurts** — a raise per skipped iteration, which is exactly backwards,
since skipping is meant to be the cheap case.

**So the fork in [3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing)
is unchanged and now has numbers on both sides.** A compiled `forever` is free —
a backward jump, a forward jump, and a jump to the top — and makes the inlining
semantic, which the compiler's own comment warns against by calling it *"an
optimisation only; the meaning is exactly that of the message"*. A library
`forever` exists, works, and costs 1.7× to 5×.

**The trigger has still not fired**, and it is worth being exact about why, since
this proposal is nearly it. The trigger is *a loop whose body must skip its
remainder* — which is what `continue` is for. But wanting the construct is not
the same as a loop needing it: no loop in this repository has yet had to thread
`done:not:ifTrue({ ... })` through its body. The prototype above is what to
reach for on the day one does.

### Intercepting a message that was not understood

Smalltalk's `doesNotUnderstand:` and Io's `forward`: when a lookup fails, send
the receiver a message *about* the failed send instead of reporting it. It is
the single largest capability on this list — proxies, recording mocks, remote
objects, a DSL that answers anything — and it has never been considered here.

**A customer for it was named on 2026-08-25**, and it is not a proxy for its own
sake: sending code to a machine that is already running wants a **remote
object**, which is the canonical use of this message everywhere it exists. See
[networking](#networking-and-sending-code-to-a-machine-that-is-already-running).
Neither has fired; if either does, they arrive together.

**Mechanically it is small**, which is the surprise. There are exactly two real
lookup failures in the machine: `vm.c` in the dispatch loop, and again in
`sol_vm_send` for the C-side entry. At the first, the receiver and its arguments
are still laid out on the value stack in frame order and nothing has been popped
— which is most of what a re-send needs.

**Three things it would cost.**

A recursion guard: a receiver whose `doesNotUnderstand` is itself missing would
come straight back to the same site.

The error message. Today a typo answers *"integer does not understand 'pritn'"*
and that is one of the language's better diagnostics; the default handler would
have to keep producing it, so the feature is really "a hook *before* the
existing error" rather than a replacement for it.

And a third site that cannot play. Inlined conditionals report *"boolean does
not understand 'ifTrue'"* from a synthesised failure with no receiver object and
no lookup — the compiler kept the selector purely so the complaint matches. A
program could not intercept that one, so the feature would be *almost* uniform,
which is the kind of exception this language usually declines.

**Trigger:** a program that wants to stand in front of an object — a proxy, a
recorder, a stub — and cannot. Nothing here has wanted one; every program so far
has owned both sides of every call.

### A set, and the collections that are not there

There is no set, no bag, and no way to ask whether a value is in one except
`indexOf(v):notNil` down an array. A dictionary with values nobody reads is the
only stand-in, and `dictionaries.sol` uses exactly that shape to count distinct
words.

Related absences, all of them writable in Solum today: `detect`, `reject`,
`any`, `all`, `sortBy`, `zip`, `flatten`, `reverse`, `isEmpty`, `sum`.

**The measured lesson applies before any of it is built.** Four loops began in
[lib/control.sol](../lib/control.sol) and left for the VM because a Solum
version costs a block and a frame per element — a primitive `repeat` measured
3.2× the library one. So the answer to "should there be a `detect`" is not yes
or no but *write it in Solum, use it, and measure before promoting it*, which is
the route every one of those loops took.

A set is different in kind: it wants hashing, and `sol_dict_key_ok` already
settles what may be hashed — values only, never an object, because two that look
alike would be two keys.

**Trigger:** a program that keeps a dictionary whose values it never reads.

### Mathematics, and a source of randomness

`integer` and `float` have arithmetic, comparison, bit operations and rounding,
and nothing else. There is no `sqrt`, `pow`, `min`, `max`, `between` or `clamp`,
no trigonometry, no `pi`, and — more conspicuously for a scripting language —
**no random number source at all**, anywhere in the VM, the library or `system`.

`min` and `max` are two lines of Solum and want no decision. The rest divides:

- **Pure functions of a number** — `sqrt`, `pow`, `abs` on a float — are
  primitives over `libm` and cost nothing but the decision to have them.
- **Randomness is not a function**, it is state, and where that state lives is
  the actual question: a global seed makes two runs of a program differ, which
  is exactly what a test suite is built to prevent, and this project's own
  suite compares output byte for byte. So a random source wants to be a *thing
  you make* with a seed you can name, not a message on `integer`.

**Trigger:** a program that wants one. None has — and the absence has gone
unnoticed for nine programs, which is itself a finding about what this language
has been used for.

**The trigger fired**, with the tenth.
[bench.sol](../programs/bench.sol) wanted a standard deviation, a minimum, a
maximum and two uses of randomness, and carried all of them itself. The entry
moved to [3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done).

**Half of it is now answered, and the split is the interesting part.** `sqrt` is
a primitive; `min`, `max` and `between` are [math.sol](../lib/math.sol), a
library file with no VM change behind it. The line between them is not
importance — it is that the comparisons were written correctly the first time
and there is nothing in them to get wrong, and the square root was written
*twice* and was wrong both times without saying so, the second version worse
than the first by nineteen orders of magnitude above 1e21. A thing every program
would get wrong the same way belongs in the machine.

**The paragraph above about where randomness should live was right, and it is
what got built.** *A random source wants to be a thing you make with a seed you
can name, not a message on `integer`* — which is `random:new` and
`random:new(#seed)`, state in the object, nothing global, written here before
anything was measured and not improved on afterwards.

**The trigger was the part that was wrong.** It said this waited on a program
wanting randomness *for what it does rather than for how it measures*, and
counted `bench.sol` as the second kind. That misread the program: its product is
the confidence interval and the interval is computed by bootstrap resampling, so
the randomness is the algorithm rather than the instrumentation. The trigger had
fired on the day it was written and went on looking unfired for four releases.

What actually settled it was measuring the generator that program carried. It
was correct and its *seeding* was not — the clock being the only entropy a Solum
program can reach, two runs a microsecond apart got consecutive seeds, and the
first coin flip was then exactly the parity of the start time. Neither that nor
the modulo bias on the way out could be fixed in Solum, which is the argument
that made `sqrt` a primitive.

The trigonometry named at the top of this entry went to 3.14 too, with its own
trigger and the reason it would be a primitive rather than a library — argument
reduction, harder to get right than the square root was and failing the same
way. The trigger fired on 2026-08-25 and it is
[built](COMPLETED.md#314-the-mathematics-that-is-not-here--done).

### Splitting the reference into pages

`docs/REFERENCE.md` is about 2,500 lines. Should it become several pages?

**Not yet**, and the trigger is measurable rather than a feeling: **when the
message reference is longer than everything above it.**

**What one page is worth.** A reference is read by searching, and one page means
one search. Splitting it means knowing which page a thing is on *before* looking
for it — which is the question the reader had in the first place. Every
multi-page reference answers that with an index, and an index is what was just
added, so the split would be paying a cost to buy something already in hand.

**The seam is already visible**, which is the useful part of asking early. The
sections divide cleanly in two:

| | lines |
| --- | --- |
| the language — syntax, values, blocks, control flow, objects, errors | ~1,910 |
| [Message reference](REFERENCE.md#message-reference) — what each type answers | ~700 |

Everything above the message reference describes a language that has nearly
stopped changing; the message reference grows with every built-in. So the split,
when it comes, is **the language** and **the messages**, and the
[message index](REFERENCE.md#message-index) becomes the bridge between them
rather than a thing to build later.

**The trigger, said exactly**: when *Message reference* exceeds the sum of the
sections above it. That is a number the file can be measured for, it does not
depend on anyone's patience with scrolling, and it marks the point where the
document is mostly a catalogue with a language attached rather than the other
way round. At roughly 700 against 1,910 it is not close.

**What to do before then, if it gets uncomfortable sooner**: the message
reference could move to its own page while everything else stays, which is one
file and one link rather than a reorganisation. That is the same split, taken
early, and it is worth preferring to a scheme with four pages and a navigation
scheme of its own — this project has one reader today and adding a table of
contents to a table of contents is not what would help them.

**Re-measured**, since a trigger nobody checks is a trigger that never fires:
the file is about 2,800 lines, the message reference is about 700 of them, and
everything above it about 1,910. Both halves grew and the *ratio* barely moved,
which is the answer — the language sections have gone on growing alongside the
catalogue rather than standing still while it filled up. Not close, and not
trending towards close.

### An `assert`, and compiling it away

Two proposals in one: a message that raises when a claim is false, and a
compile-time switch that removes it from a production build.

**The switch: no.** Three reasons, and the third is the one that decides it.

It reopens conditional compilation, which is turned down
[above](#more--directives-define-ifdef-once) on the grounds that a file would
stop being the program you can read. An `@assert` that vanishes has exactly that
property. **Side effects vanish with it** — `assert(advance())` is a bug C
programmers have been making for forty years, and it is silent.

And the reason particular to this language: **the checks people write here are
validation, not assertion**, and those are not the same thing at all.

| | what it checks | may it be stripped? | in this repository |
| --- | --- | --- | --- |
| validation | the input is wrong | **never** — it is the program's error handling | ~23 |
| assertion | *my own code* is wrong | in principle | **none** |

Every hand-rolled check in the examples and libraries is the first kind.
`bracket:equals("["):ifFalse({ error:raise("not an arrow") })` in
[keys.sol](../examples/keys.sol) reads exactly like an assert and must never
vanish: it is parsing input from a terminal. A switch that removes one kind will
be pointed at the other by somebody wanting a faster loop, and what it deletes
is the error handling.

**The message itself: defer**, and the reason is the count. This project let
`inc` and `dec` in on the strength of `add(#1)` being three in ten arithmetic
sends. The equivalent number here is zero — nothing in the tree writes a
debug-only invariant check, and what it does write is served by what exists:

```
x:greaterThan(#0):ifFalse({ error:raise("x must be positive") }).
```

**What it costs, measured** over 300,000 turns of a loop, since the argument for
stripping is speed:

| | seconds | against a bare loop |
| --- | --- | --- |
| bare loop | 0.0424 | — |
| a library `assert` helper | 0.1051 | 2.5× |
| the condition written inline, as above | 0.0615 | 1.4× |

The expense is the **helper call**, not the check: `ifFalse` written literally
compiles to a jump, and a helper is a block call per iteration. So the fast form
already exists, and 1.4× on an *empty* loop is the worst case there is.

**If it is ever added**, the shape is a message the compiler inlines the way it
inlines `ifFalse` — `x:greaterThan(#0):assert("must be positive")` — costing a
comparison and a branch, and **always running**. That adds the word without
adding a second meaning to the same file.

**The trigger**: a program that writes a check it would genuinely want off in
production, and can say why the inline form is not enough. None has.

### Default values for block parameters

Asked on 2026-08-23: if a block takes a parameter the caller usually gives the
same value for, could it carry that value itself?

```
myfun := { x := #0 | doSomething }.   ; a sketch; not valid today
myfun:value.                          ; -- x would be #0
myfun:value(#5).                      ; -- x would be #5
```

**The case for it is stronger than convenience, and it is not the syntax.** The
language already has defaulted arguments — it is just that only C can write
them:

```
d := dictionary:new.
d:atPut("port", #80).
d:at("port"):print.             ; #80    -- one argument
d:at("host", "any"):display.    ; any    -- two, and the second is a default
"45":asInteger:print.           ; #45
"2d":asInteger(#16):print.      ; #45    -- and again
```

`at`, `asInteger`, `asString`, `sorted`, `first`, `last`, `timeToRun` and
`perform` all take an argument or do not, and in several of them the extra
argument is *exactly* a default value. A block cannot:

```
f := { x | x }.
{ f:value }:onError({ e | e:message:display }).   ; 'block' takes 1 argument, got 0
```

So this is one of the few places where **user code cannot do what built-in code
does**, and the language otherwise works hard to keep those the same thing — a
class is an object, control flow is message sending, `[a, b]` really is
`array:of(a, b)`. That asymmetry is the argument, and it is a better one than
saving a word at a call site.

#### Three spellings, and the third is the one to build

Two were proposed, and the difference between them is not taste — one of them
answers a design question the other leaves open.

```
{ x := #0 | body }        ; a sketch; the first proposal
{ x:{#0} | body }         ; a sketch; the second
{ x := { #0 } | body }    ; a sketch; what they suggest between them
```

**All three are free.** The grammar refuses each today, so nothing becomes
ambiguous:

```
> f := { a:{45} | a }.
[line 1:10] solas: expected a message name after ':' at '{'
> f := { a := #0 | a }.
[line 1:16] solas: expected '.' between statements at '|'
```

**`{ x := #0 | ... }`** reads the way a default reads and costs the most to
scan. `solas` decides parameters with a copy of the lexer rather than a parser,
skipping identifiers and commas; this makes it skip an *arbitrary expression* to
find the `|`, and one containing a block means balancing braces anyway.

**`{ x:{#0} | ... }`** is cheaper to scan and says the wrong thing. Cheaper
because `skip_block` already exists — it balances braces and is what the
inlining probe uses — so the rule is `IDENT COLON LBRACE`, and the scan is
bounded by construction. Wrong because **`:` is how this language sends a
message**, and `a:{45}` is not one. That is
[the objection that refused `ifTrue{...}`](#iftrue--a-block-argument-without-parentheses)
seen from the other side: that proposal made a send look like syntax, and this
makes syntax look like a send. The language spends a lot of ink insisting `:` is
always a send; a second meaning for it is expensive in a way fifteen lines of
parser is not.

**`{ x := { #0 } | ... }` takes what each got right.** `:=` still means bind,
which is what a default does; the default is a block, so the scan is `skip_block`
and stays bounded; and — the part that matters most — **the default is code that
runs when the argument is missing**, rather than a value fixed once.

That last point settles one of the three questions below before it is asked.
`{ xs := { [] } | ... }` makes a fresh array per call, where a value evaluated
once would share one array between every caller — the mistake nearly every
language with this feature has shipped at least once, and Python's
`def f(xs=[])` is the famous one. The block spelling makes the right answer the
only one that can be written.

It costs two characters against the first proposal and reads honestly: a block
is code, and a default that can call `system:clock` was always going to be code.
A parameter defaulting to a block *value* nests, `{ x := { { #0 } } | ... }`,
which is consistent and rare.

**None of this is built.** The trigger below has not fired, and the syntax being
settled does not change that — it means the entry is ready if it does.

**The machine is the larger half, and it reaches the file format.**

| | |
| --- | --- |
| arity stops being a number | It becomes a range, `[required, total]`. `.sob` carries `u16 arity` per method ([serialize.h](../solum/include/solum/serialize.h)), so a second number is a **format version bump** — every `.sob` recompiled. |
| the callee has to know what it got | `sol_vm_call` checks `argc != code->arity` and builds the frame; nothing tells the body how many arguments actually arrived, and filling defaults means knowing. |
| a default is code, not a constant | `{ x := system:clock \| ... }` has to run *somewhere*. Running it in the callee's frame gives a block a prologue with jumps — the same shape an inlined conditional has, but generated rather than written. |

**Two questions left to settle**, the third having been answered by the spelling
above: may a default see an earlier parameter (`{ a, b := { a:inc } | ... }`),
which decides whether the prologue is one pass or ordered; and what `respondsTo`
and the arity error should say about a block that takes one argument or two.

**What works today**, and it is not nothing. The caller says nil and the block
substitutes:

```
greet := { name |
    name:isNil:ifTrue({ name := "world" }).
    "hello, {}":fill([name]):display }.
greet:value(nil).               ; hello, world
```

Or one parameter carries the options, and the defaults are spelled with the tool
the language already has:

```
draw := { options |
    "{} at {}":fill([options:at("shape", "circle"),
                     options:at("size", #10)]):display }.
o := dictionary:new.
o:atPut("shape", "square").
draw:value(o).                  ; square at 10
```

Both cost the caller something — a `nil` it did not want to write, or a
dictionary to build — and neither is wrong.

**Trigger: a program here writing the same block twice, or threading a `nil`
through a call it did not want to make, for one optional argument.** Nothing has
yet. This is written down rather than started because
[ROADMAP.md](ROADMAP.md)'s admission rule is that an entry means *a program
wanted something and could not have it*, and no program here has — the idea came
from thinking about the language rather than from writing in it, which is what
this document is for.

### Constants, and whether they should be a thing

Asked on 2026-08-23. There are no constants: every name is a binding and `:=`
can rebind any of them. Two ways to add them were put:

1. **New syntax** — a second kind of assignment the compiler refuses to rebind.
   Set aside by whoever asked, on the grounds that the syntax is clean and this
   would cost some of that.
2. **A directive** — `@constant pi 3.14159`, which the compiler knows, refuses
   to rebind, and can substitute at the use site. Then `pi` need not be a
   primitive; it can live in a library and cost nothing at run time.

**Two different things are being asked for**, and only one is new. *A name for a
value* already exists — the [`@define` entry](#more--directives-define-ifdef-once)
settled it: `maxRetries := #3.` is a name holding a value, and it obeys scope.
The idiom for a library is a slot on an object, `math:pi := 3.141592653589793.`,
which needs no language change and namespaces better than a flat directive
could: two libraries with `@constant max` would be an unshadowable collision
where two objects with a `max` slot are simply two objects.

*Enforced immutability* is the new part, and it collides with a bargain already
struck. The collision warning (6.21) is a warning rather than an error, and
[compiler.c](../solas/src/compiler.c) says why: **"rebinding is legal and
sometimes meant: a program may want to replace something a library bound."** A
constant would be the first name a program is forbidden to replace.

The language holds both positions at once, which is worth seeing together. The
inlined `and`/`or` emit a **constant** `true`/`false` rather than reading the
globals, because *"a program can rebind"* them and the shortcut and the long
path would disagree. And `[a, b]` deliberately sends to the **ordinary global**
`array`, so that rebinding that name changes both spellings and they cannot
drift apart. Rebindability is a hazard in one place and load-bearing in the
other.

#### The performance argument is right, and it points somewhere else

The case for constants is that `OP_CONST` is an array index where `OP_GLOBAL` is
a lookup. That is true, and measuring how *much* it is true is what made this
entry interesting: global lookup walks a list, linearly, at about 1.35ns a slot
— [3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done) has the numbers. At
800 globals a constant is 16× faster.

**But the fix that number argues for is not constants.** A hash on the root
speeds up **every** global read in every program; a constant speeds up only the
names somebody remembered to declare. That is the same reasoning the `@define`
entry gave for making loops primitives rather than macros — *it speeds up every
caller rather than the ones who remembered*.

**That is now built**, and it argues against constants harder than this entry
did. An object with more than a dozen slots keeps a table beside its list, and a
global read is a constant-time lookup at any depth: 2.88× at 60 globals, 1.37×
at 16. It also turned out to be worth more to *sends* than to globals, which is
the half of the reasoning nothing here had — the built-in messages are
registered in order and a new slot goes on the front, so `add` sat 35 slots down
`integer`'s list of 38 and every integer send paid for it. Real programs came
out 1.09× to 1.31× faster with no change to the language at all. See
[3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done).

#### The memory argument runs backwards

A constant is *not* cheaper to hold than a global, because **the constant table
is per chunk and a block is a chunk**. Three blocks using the same literal:

```
a := { 3.141592653589793 }.
b := { 3.141592653589793 }.
c := { 3.141592653589793 }.
```

compiles to three chunks with **one constant each** — three copies of the
double. The global it would have replaced is one slot on one object, read from
all three. So substituting a constant into `n` chunks costs `n` copies where the
binding cost one.

#### Verdict

**Defer, and probably no.** Not because the speed argument is wrong — it is
right — but because the measurement it rests on argues for fixing the lookup,
which helps everything, over adding a second kind of name, which helps what it
is told to. And a second kind of name is expensive in a language that has one
kind of everything: `:=` binds, later wins, the warning says so, and `slots`
lists what is there.

**Trigger:** a program measurably slowed by global reads — which was
[3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done), and is now
done, so this would have to be a program still slowed by a lookup that is
already constant-time; or a case where a name genuinely must not be rebindable
and a warning is not enough.

`pi` needs none of this, incidentally, and in the end it did not go in
[math.sol](../lib/math.sol) either. It is `float:pi`, a class-side message that
arrived with the trigonometry
([3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done)) — the argument
being that `infinity` and `nan` are globals because they are values the
arithmetic *reaches*, while `pi` is a constant and `pi` is a name a program is
entitled to want.

### Programs that would press on something

These are programs rather than language features, and they are here because what
makes each of them interesting is the **language question it would answer**. A
program needs no permission to be written — the rule this repository runs on is
that you write one and find out what it wants. What follows is the finding each
is predicted to produce, written down *before* it is written, so that *it found
nothing* stays an available answer.

**One of the four has been written since**, and its prediction is kept above its
outcome rather than replaced by it — a prediction rewritten after the fact
teaches nobody anything.

**A terminal editor**, in the manner of vi. **Written on 2026-08-25, and the
prediction held.** It is
[programs/edit.sol](../programs/edit.sol), and it wanted the terminal's size in
its first hour, exactly as this entry said it would. The prediction as it stood:

> Predicted finding, and this one is already confirmed absent rather than
> guessed: **nothing lets a program ask the terminal its size**. No rows, no
> columns, and no notification when either changes. Every full-screen editor
> needs that in its first hour. `system:write` and `system:readKey` cover the
> rest — escape sequences out, raw bytes in — and both landed on 2026-08-25, so
> the editor is the first program in a position to want the third thing.

**What the writing added to it** is the part the prediction could not have: the
number was always *reachable*, through `stty size` in a shell, at 7ms an ask. A
program that measures every time it draws forks a process per keystroke; one
that measures at startup draws a resized window wrong until it is restarted. So
the absence was never the finding — **the price was**, and one ioctl at about a
microsecond is what made the missing resize notification stop mattering.
[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done) was
raised and closed the same day.

It also confirmed something that had only ever been a warning: a byte-level
reader **cannot tell the escape key from the start of a sequence**, which
[examples/keys.sol](../examples/keys.sol) had said in the abstract because
nothing had yet bound that key. A modal editor binds it to the most frequent
action there is — and that warning became
[6.35](COMPLETED.md#635-a-read-that-gives-up--done) the next morning, which is
the oldest known gap in this language closed by the first program to be annoyed
by it.

**Finished on 2026-08-26, and the score is worth keeping.** The prediction named
one finding and the program produced **four**, plus a first customer for an
entry that had been waiting for one:

| | |
| --- | --- |
| [6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done) | the terminal's size — **the predicted one** |
| [6.35](COMPLETED.md#635-a-read-that-gives-up--done) | a read that gives up, so the escape key can be told from an arrow |
| [6.36](COMPLETED.md#636-readline-and-readkey-did-not-share-an-input-buffer--done) | two readers that did not share a buffer, found by reading the code beside 6.35 |
| [6.37](COMPLETED.md#637-indexof-cannot-say-where-to-start--done) | `indexOf` could not say where to start, wanted by the matcher its search needed |
| [3.2](ROADMAP.md#32-no-non-local-return) | its first real customer: a dispatcher that wants to leave a *method* |

Eleven commits, ten of them inside one morning, and
[the postmortem](journal.md) is in the journal. **The prediction being partly
wrong is the useful part**: what the editor could not have was never in doubt,
and what that cost — a fork per keystroke to ask `stty` — is what made it an
entry rather than a shrug.

**A Pascal interpreter.** Not another BASIC: that shape has been taken, and
[basic.sol](../programs/basic.sol) argues at length that a line-numbered
language never nests and *that* is why it fits inside 254 frames. Pascal's
recursive procedures are the case the comment sets up and never runs. A
tree-walker for a lexically nested language spends frames in proportion to the
**interpreted** program's call depth, so
[3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) would be met head
on rather than dodged. That is the whole of its value, and it is a real one.

#### It is being built, and as a compiler — so this prediction is wrong before it starts

**2026-08-27, written before the first line.** The decision is to compile Pascal
to `.sob` rather than to interpret it, the way
[sola.sol](../programs/sola.sol) does SolaBasic, and that **takes away the value
this entry predicted**. A tree-walker spends three to six host frames per
interpreted call; a compiled call is one `OP_SEND` and one frame. So Pascal
recursion would reach something like 250 levels rather than 40, and 3.5 is met
*less* squarely than an interpreter would have met it. The entry's own reasoning
still holds — it is the shape that changed, not the argument.

Recorded rather than quietly dropped, because a prediction that is falsified by
a decision is still a prediction that paid: it is the reason anybody looked at
the frame cost before choosing the shape.

**Two better predictions take its place, and both are falsifiable.**

**One: [3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) is not a
limitation for this language, it is the language's own rule.** A capturing block
may not outlive the frame it was written in. A Pascal nested procedure may not
be called after its enclosing procedure has returned. Those are the same
sentence, and if they really are, then the entry that has been open since the
start is — for Pascal exactly — the specification. **The prediction is that
nothing in a conforming Pascal program can reach the restriction**, and the way
to falsify it is one program that does.

**Two: `OP_OUTER` gets its first customer from a compiler.** The instruction
takes a depth and a slot, which is a static link by another name, and Pascal's
uplevel variable access is what static links were invented for. `sola.sol`
emits neither `OP_OUTER` nor `OP_SET_OUTER` — SolaBasic has no nested
procedures — so no compiler here has ever produced one. **The prediction is that
Pascal's scoping needs no mechanism the machine does not already have.**

What neither prediction covers is the type system, which is where the work
actually is: Pascal has records, sets, subranges, enumerations, pointers and
files, and SolVM has objects, arrays, strings and two kinds of number. That is a
mapping to be argued rather than a limit to be found, and
[PASCAL.md](PASCAL.md) is where it is argued.

**Predicate logic** — unification, resolution and backtracking. Wanted:
coroutines, continuations, and a non-local return, all three of which are
recorded as **No** further down this page with reasons. It would need an
explicit trail and choice-point stack instead, which is exactly what `basic.sol`
found `GOSUB` and `FOR` to be, so the shape is not unprecedented. Prediction: it
works, awkwardly, and 3.5 bites on deep resolution. The sharpest single finding
on this list and the largest job.

**A parser toolkit** in the manner of lex, yacc, sed and awk — grammars written
in something like BNF. **The most interesting of these**, because the answer to
the obvious design is already on record: [lib/scan.sol](../lib/scan.sol) says a
matcher built the combinator way dies with `block outlived the frame it was
written in`, which is
[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame). So this program
either gives that entry its first customer, or shows that a non-combinator
design is fine and the limitation is livable. Both outcomes are worth having,
which is rare enough to be the reason to pick it.

**A first data point arrived on 2026-08-26, from the side.**
[lib/pattern.sol](../lib/pattern.sol) is a matcher rather than a toolkit and was
written because an editor wanted `/`, not to answer this — and it is
non-combinator by construction: the pattern compiles to an **array of items**
walked by a loop, and 3.1 never came up, because nothing there is a block that
outlives anything. It also measured what recursion costs when it is unavoidable:
one frame per `*`, so 250 of them fit. **That is the smaller half of the
question.** A grammar is a tree where a pattern is a list, and a tree is exactly
what multiplies that measurement — so the entry stands, with its second outcome
now the likelier of the two.

**Built on 2026-08-26 — and the second outcome is the one that happened.**
[check_syntax.sol](../programs/check_syntax.sol) reads a grammar in Wirth's EBNF
and checks a file against it, with [pascal.bnf](../programs/check_syntax/pascal.bnf)
as its first customer. **[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame)
never came up.** Not because it was worked around, but because the design that
avoids it is also the design that is right: the grammar is a tree of objects and
the matcher is one method that recurses over it, so nothing is ever a block that
has to outlive the frame it was made in. The combinator shape is the one 3.1
refuses, and it was never reached for.

**What multiplied instead was the measurement, exactly as predicted.** A tree
cost one frame per node and about two per rule reference, which against Wirth's
Pascal was **19 levels of nested `begin … if` and 28 nested parentheses**. That
was the number this entry had been waiting for, and it read at the time as
saying the limitation was livable — 19 being past anything written by hand and
short of what a generator emits.

**It was not livable, and the file that said so was already here.** See below.

**The finding worth carrying back here is a different one.** Inlining a rule's
alternation into the reference that names it should be worth a third of the
frames — one of the three per level — and it was worth **a sixth**, 16 levels
becoming 19. Most of Wirth's Pascal rules have a sequence for a body rather than
an alternation, so most never had the middle frame to save. **A measurement of
the matcher predicts a third; only a measurement through a real grammar gives a
sixth** — which is the same lesson `programs/` keeps producing, that a program
written to suit a feature cannot report that the feature was awkward.

**And then it was settled, the same day.** This entry said an explicit stack
machine — its own instruction list, its own backtrack stack — would have no
depth limit at all and would meet 3.5 head on rather than living inside it, and
that `check_syntax.sol` had recorded the trade rather than taken it. What took
it was not an argument but a file: `experiment/lexer.sol`, already in this
repository, nests `ifElse` 24 deep and the tree walker could not read it.

The matcher is [LPeg](https://www.inf.puc-rio.br/~roberto/docs/peg.pdf)'s
instruction set now — `Call`, `Ret`, `Choice`, `Commit` — and 2,000 levels of
nesting check where 13 did. **The prediction this page made about a tree
multiplying a measurement taken on a list was right, and the fix is the one it
named.**

**What the page could not have predicted is the price: 38% of the running time**,
and 3.7% of that recovered by two hand optimisations that were expected to be
worth far more. The dispatch loop's cost is the instruction fetch and the sends
inside an arm, not the comparisons that choose the arm. **An interpreter written
in this language pays for its dispatch and cannot get it back by hand** — which
is worth carrying to the two entries above this one, since both of them are
proposals for interpreters.

**Fuzzy logic.** A library, and worth an honest note rather than a place in the
queue: it is arithmetic on floats, and all of the arithmetic landed with
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done). It would teach
nothing about the language. Build it if the thing itself is wanted; not to find
something.

### Networking, and sending code to a machine that is already running

[serve.sol](../programs/serve.sol) answers an HTTP request through environment
variables — *there is no socket anywhere in this repository*. So a client and
server pair that talk to each other means new primitives in the VM: connect,
bind, listen, accept, and a read and a write that are not files.

**Sending code fragments to a running `solvm` is a step further, and depends on
three things rather than one.** The sockets above; then
[3.4](ROADMAP.md#34-no-compatibility-across-sob-versions), because a `.sob` is
not compatible across versions, so a service and its clients are lockstep or the
wire carries source; and then
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine), because
this is that entry's threat model stated exactly — *input from a stranger* — and
it is deferred precisely because nobody had one.

It has a fourth dependency that is a feature rather than a decision. **A remote
object is the canonical customer for
[intercepting a message that was not understood](#intercepting-a-message-that-was-not-understood)**,
which is deferred below because nothing has wanted a proxy. Networking would
want one, and the two should be considered together if either is.

**The trigger: two machines that need to talk.** Nothing here has needed one,
and `serve.sol` was written to answer a request without a socket precisely so
that it would not need to.

## Recommended against

### Integer sizes — byte, word, long

Numbers ride unboxed in `SolValue`: an integer is a tag and 8 bytes of payload,
with overflow that traps rather than wraps. Adding widths breaks that in a way
the language would feel everywhere.

- **It reintroduces coercion.** `#1b:add(#1L)` has to either promote — which is
  exactly the implicit coercion the language refuses between integer and float,
  with an error message that says so — or be an error, which means every
  arithmetic expression has to be width-annotated.
- **Each width multiplies the pairs.** Two numeric types today means one
  coercion question, already answered "never". Five means ten.
- **The usual reason does not apply.** Widths buy packed memory, and there is no
  packed array here: a `SolArray` holds `SolValue`s, so a byte array would cost
  16 bytes per byte either way. The saving would be zero until there is a real
  byte-buffer type, which is a different feature.
- **The actual need is a range check.** "This must fit in a byte" is
  `n:between(#0, #255)`, not a type.

If binary file handling arrives it will want a byte buffer — but that is one new
*collection*, not five new *number types*.

### Separate float and double

The same argument with less upside. `float` is C `double` — binary64 — which is
what a language this size should have exactly one of. A 32-bit float would add a
third numeric type, a third set of coercion questions, and a rounding surprise
between them, in exchange for memory that nothing here is short of.

### A JIT to native code

**Possible?** Yes — any bytecode VM can be JITted, and this one has a clean
dispatch loop to start from.

**Worth it here?** No, and not close.

- It would be **larger than everything else in the project combined.** Code
  generation per architecture, register allocation, `W^X` handling, unwinding,
  and a second correctness surface that the `.sob` verifier does not cover.
- **There is nothing to specialise on.** A JIT wins by turning dynamic dispatch
  into direct calls, and that needs type feedback and inline caches first —
  which is a bigger machine again. Without them a JIT emits the same lookups the
  interpreter does, in more code.
- **It fights the stated goal.** The VM is written for clarity first, and 4.1
  and 4.3 got the language 40% faster with changes that fit in a paragraph.

**The cheap alternative, if speed is ever wanted:** computed-goto dispatch
(`&&label` threading) in place of the `switch`. It is a contained change to one
function, typically worth 10–20% on interpreter-bound work, and it does not
change anything else about the system.

### `ifTrue{...}` — a block argument without parentheses

```
a:equals(b):ifTrue({ dosomething }).     ; today
a:equals(b):ifTrue{ dosomething }.       ; proposed
```

**Decided against** — but not for the reason this entry first gave, and the
first reason was wrong enough to be worth correcting rather than quietly
replacing.

#### What the rule actually is

This entry originally called it a special case: it works for `ifTrue` and
`whileTrue` and not for `ifElse`. That misread the proposal. The rule is not an
exception carved out for two messages, it is:

> A lone block argument may drop its parentheses.

`ifElse` is not an exception to that. It is *outside* it, having two arguments.
And the rule reaches most of the language rather than a corner of it — of the
eleven messages that take a block, nine take exactly one:

`and` `collect` `do` `ifFalse` `ifTrue` `or` `select` `sorted` `whileTrue`

`ifElse` does not, and neither does `inject`, which came later and takes a
starting value before its block. So the rule is close to uniform, and the
special-case objection does not apply to it.

That `inject` moved the count is worth noticing: the rule's reach is a fact
about which messages happen to exist, not a property of the design, and a
language that keeps growing will keep moving it. It was never the deciding
argument here — the objection that carried the day was about what the shorthand
would teach a reader — but an argument that rests on a headcount is worth less
than one that does not.

#### Nor is the cost

The grammar has room. A block cannot follow a send today, so nothing becomes
ambiguous:

```
> #1:print { #2 }:value:print.
[line 1:10] solas: expected '.' between statements at '{'
  #1:print { #2 }:value:print.
           ^
```

It is one branch in the argument parser and one in the inlining probe. Perhaps
fifteen lines. Cost is not why this is not being built.

Neither is "a second spelling for one thing", which this entry also gave. That
objection does not distinguish the idea from `[...]`, which is a second spelling
for `array:of(...)` and was accepted — because it is *byte-identical* sugar, and
a trailing block would be too. The principle is satisfied either way.

#### Why not, then

**It makes a message send look like syntax, exactly where the language works
hardest to prove it is not one.**

```
a:equals(b):ifTrue{ dosomething }
```

reads as `if (...) { ... }`. Every document in the project makes a point of
saying there is no `if` here — the tutorial's aside is titled *"An aside: there
is no `if` in this language"* — and the parenthesised form is the proof, sitting
at every use site. `ifTrue(...)` is visibly a message with an argument;
`ifTrue{...}` is visibly a keyword with a body.

What makes that awkward is that the objection is **use-site specific**. On
`stock:do{ e | ... }` or `stock:collect{ e | e:name }` it barely applies —
nothing there is pretending to be syntax, and the parentheses are noise around a
closing `})`. So the rule is least costly where it is least needed and most
costly on the conditionals, where it reads best. One rule cannot tell those apart
without becoming the special case it set out not to be.

**And it teaches a rule that does not generalise**, which is the decisive one.

A reader meeting `ifTrue{ ... }` in an example has no way to see where the rule
stops. The natural next guess is `ifElse{ ... }{ ... }`, which is not valid and
never will be, and the guess after that is that braces attach to selectors
generally. The shorthand's cost is not paid by someone who learns the rule
properly from the reference — it is paid by someone who infers it from a
snippet, and infers something wider than what is there.

The parenthesised form has no edge to fall off. A block is an argument, and it
is written where arguments are written, in every case, with no rule to remember
about when it may be written otherwise.

### More `@` directives: `@define`, `@ifdef`, `@once`

`@` was reserved for the things that happen while compiling rather than while
running, and `@include` is the only one in it. The question is whether the rest
of C's preprocessor belongs there too. **None of it does, and the reason is the
same each time: the job is already done by something that is not a directive.**

**`@once` is already the behaviour**, unconditionally. A file is compiled once
per compilation, keyed by where it lands on disk. C needs `#pragma once` because
C compiles an included file every time it is reached and leaves each file to
guard itself; Solum does not, so the directive would be a way of asking for what
you already have. There is nothing for it to switch on.

**`@define` has three jobs and Solum has three answers.**

A *named constant* is a binding. `maxRetries := #3.` is a name holding a value
rather than a name standing for text, which means it obeys scope and cannot
surprise anybody by expanding in the middle of an expression.

A *function-like macro* is a block. And the one thing macros have over
functions in C — that their arguments are not evaluated before the call — is
the thing blocks were built for:

```
unless := { condition, body | condition:not:ifTrue({ body:value }) }.
unless:value(false, { "only now":display }).
```

`ifTrue` itself is that shape, so a user-defined control structure is ordinary
code and needs no macro. A block goes further than a macro can: it is a value,
so it can be stored, passed on, and called later.

*Compile-time computation to avoid a run-time cost* is the job left, and the
answer here has consistently been to **measure and make it a primitive** — which
is what happened to the four loop constructs. That is the better answer, because
it speeds up every caller rather than the ones who remembered to use the macro.

**`@ifdef` is the one worth arguing about, and it is still no.**

- *Platform differences.* The language has none. The VM absorbs them in C, which
  is where they belong; even [6.10](COMPLETED.md#610-waiting-for-a-single-key--done),
  the first genuinely platform-divergent feature, would diverge inside the VM
  rather than in Solum source.
- *Debug and release builds.* `system:environment` answers at run time, and a
  block that is never called costs a slot.
- *Feature detection*, which is the real one: a program that wants to run on two
  releases cannot use `asByte` on the one that has not got it. **`respondsTo`
  already answers that**, at run time, with no second language:

```
"A":respondsTo('asByte):print.          ; true
"A":respondsTo('asRunicGlyph):print.    ; false
```

What `@ifdef` would cost is out of proportion to that. It introduces a second
language with its own scoping rules, and it makes the text on the screen stop
being the program — a reader, and every tool, has to know which switches were
set before they can say what a file means. This language has spent its whole
design avoiding that kind of second mechanism: control flow is message sending,
a class is an object, a method is a slot holding a block.

**So `@` stays a namespace with one thing in it.** That is a result rather than
an oversight. The reserved space says *this is where compile-time things go if
any more turn up*, and the honest position after looking is that none have —
each candidate is answered by a binding, a block, or a message. If a real one
appears, `@` is ready, and the case for it will be that nothing in the language
already does the job.

### Cascades: `A:with{ :m1(#1). :m2(#45). }`

Smalltalk needs cascades because its setters answer the argument, so
`a add: 1; add: 2` is the only way to chain. **Solum already avoided that
problem**: `add` answers the array, so `b:add(#1):add(#2):add(#3)` chains
natively — the changelog records that as a deliberate choice.

So the syntax would buy a second way to do something the language already does,
at the cost of a construct where `:m1(#1)` means a send to a receiver that is
not written down. That is a large exception to "`:` sends to what is on the
left".

### Tail calls

The obvious motivation is [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels):
recursion stopped at about 62 levels then, two programs had hit it, and a language
that reuses the frame for a call in tail position would relieve that. Scheme
requires it, Lua has it, Smalltalk does not.

**It would not have helped either program**, which is the whole entry.
[evaluator.sol](../programs/evaluator.sol) stopped at 18 brackets and
[lib/json.sol](../lib/json.sol) at 28 levels of nesting — 83 and 124 since the
cap moved — and both are
recursive-descent parsers — where the recursion is *never* in tail position:

```
parseExpression := { | left |
    left := parseTerm:value.                    ; the recursive call, and then
    { isOneOf:value("+-") }:whileTrue({ | op |
        op := next:value:text.
        left := binary:value(op, left, parseTerm:value) }).    ; work after it
    left }.
```

`parseFactor` is the same: it calls `parseExpression`, then checks for a closing
bracket, then answers. A tree walk has work waiting on the way out by
definition, so the frames cannot be reused and the depth is real.

So tail calls would buy loops-written-as-recursion, which nothing here writes,
because the language has loops. **Verdict: no** — not because it is hard, but
because the case for it evaporates on inspection, and the programs that appear
to ask for it are asking for something else.

### Coroutines

Lua's headline feature and one of Io's, and the natural way to write a generator,
an incremental parser, or a scheduler. Rejected for a reason more specific than
the one that refused [Go-style concurrency](#go-style-concurrency) below.

**The interpreter re-enters itself on the C stack.** When a primitive calls back
into the language — `whileTrue` calling its body, `collect` calling its block —
`sol_vm_call_block` calls `run_frames` *again*, nested inside the C frame of the
primitive, which is nested inside the `run_frames` that dispatched it. So the
live state of a running Solum program is not only in `vm->frames`: it is also
`prim_while_true`'s `for(;;)`, `prim_array_collect`'s loop index, and the GC
temp-root push each of them is holding.

A coroutine has to suspend a Solum stack and resume it elsewhere. The Solum
frames would move — `SolFrame` is plain data and `slots` points into a stack
that could be relocated. **The C frames interleaved with them cannot.**

**Verdict: no**, and the note worth keeping is that this is a consequence of a
choice that has paid elsewhere: re-entrancy is what lets `ifTrue` and
`whileTrue` be ordinary messages implemented in C, which is the thing this
language is most pleased with. The price is that its stack is not a value.

### Multiple return values

Lua's `a, b = f()`. **No.** Every send here has a fixed stack effect — the
design leans on `SEND 'add' (1 args)` always having exactly two values beneath
it, and the verifier checks the height at every instruction on that basis. A
second return value would make the height depend on what a method decided at run
time, which is the property the verifier exists to have.

An array already carries several answers, and
[programs/disasm.sol](../programs/disasm.sol) returns `['ok, page]` pairs
throughout without the shape being uncomfortable.

### Resuming from an error

Smalltalk's `retry`, `resume:` and `pass`. **No.** The error system is
unwind-only on purpose and the reference says so — *"What is gone is the
frames. Nothing can be resumed."* By the time a handler runs, the stack between
the raise and the catch is gone; resuming would mean keeping it, which is a
different error system rather than an addition to this one.

`retry` specifically is writable today: a block that calls itself, or a loop
around the `onError`. What is not writable is resuming *at the raise*, and that
is the part that would cost the design.

### More than one parent

Self allows an object several parent slots, and multiple inheritance with it.
**No.** One `proto` is the model, and the thing multiple parents are usually
wanted for — reaching a specific ancestor's version of a message — is already
`self:via(ancestor)`, which names the ancestor rather than inferring it. That
naming is what lets no frame record where a method was found; several parents
would put the ambiguity back and need a rule to resolve it.

### Go-style concurrency

Goroutines and channels are a whole-VM change, not a feature:

- The interpreter is **re-entrant but single-threaded**, and frames live in one
  fixed `SolFrame` array on the VM.
- The collector is **stop-the-world over one heap** with no synchronisation, so
  every allocation would need a lock or a per-thread nursery.
- Globals are **one shared namespace** with no memory model to say what a write
  on one thread means to a read on another.

Go's model also depends on a scheduler that can preempt, which needs either
safepoints in the dispatch loop or OS threads with all of the above.

Not a bad idea in itself — a bad *fit* for a VM of this size, and the sort of
thing that is designed in from the start or bolted on painfully. If concurrency
becomes the point of the project, it is a rewrite worth planning, not an item to
add to a list.

### Subclassing `integer`, or a `byte` as a subclass

Not possible, and the reasons are worked through with a demonstration in
[class-and-instance.md](class-and-instance.md#and-a-built-in-cannot-be-subclassed-even-deliberately).

In short: an unboxed value carries no class pointer, so there is nowhere to
record a different class; and `integer`'s methods are C primitives that read an
8-byte payload, so a class made of them hands down an **interface and no
implementation**. An object delegating to `integer` inherits every method name
and can run none of them — including methods you write yourself, the moment they
touch anything inherited.

Adding methods to `integer` itself works and is the supported route. A distinct
type wants an object that holds a value.

The "properties on the metaclass" half is the open design question in
[2.5](COMPLETED.md#25-class-side-versus-instance-side--closed).
