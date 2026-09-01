# Ideas considered

*Each idea from the notes, with a verdict and the reasoning behind it. The ones
recommended against are here so the reasons survive, and so the same idea does
not have to be re-argued from scratch in six months.*

*The **trigger** each deferred entry names is the rule this page runs on, and
[method.md](method.md) states it along with the rest of how work here is decided
and checked.*

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
| `startsWith` / `endsWith` | **Built on 2026-08-30** in `lib/text.sol` — [the trigger had fired three times over](#the-trigger-fired-and-the-paragraph-above-is-wrong-about-the-cost): three programs, nine call sites, two independent `endsWith`s, a defect already caused, and the entry's *nothing is slower* wrong by 2000× on a non-match. Including it then caught `expect.sol` measuring a class it had just extended |
| What a string is — bytes or code points | **Defer, and toward bytes with a contract** — [the editor asked first](#what-a-string-is--bytes-code-points-or-bytes-with-a-contract), and was corrupting a file on `$x`. **Fixed on 2026-08-30 in the editor**, which is the argument against making `size` count characters — though [the estimate here was wrong](#and-the-editor-was-fixed-which-cost-more-than-this-entry-said): nine lines became seventeen definitions. A [`text` type with a `!"..."` literal](#a-text-type-beside-string-with-a-prefixed-literal-to-make-one) was asked and answered in the same entry — right instincts, wrong end of the pipe |
| `!character` literals, Unicode | **Defer** — gated on deciding what a string is, and [that entry recommends settling it against](#what-a-string-is--bytes-code-points-or-bytes-with-a-contract): the character type Unicode would want here is the one-character string the language already has |
| Checking that a link points at a heading | **Built**, on instruction and not on its trigger — [the entry says so](#nothing-checks-that-a-link-points-at-a-heading-that-exists). 1,313 links against 1,496 headings in `make test` on the day it went in. Writing it found two faults in `CHANGELOG.md` that it does not itself catch, and the throwaway's one reported finding turned out to be an artefact of its own fence rule |
| A truncating divide on integer | **Defer** — one customer, and its workaround is exact rather than approximate |
| A path with a NUL in it | **Defer, and it is a silent wrong answer rather than a missing feature** — [found by `sha256sum` on 2026-08-31](#a-path-with-a-nul-in-it-is-silently-a-different-path): a Solum string may hold a NUL and a C path may not, so `fileExists` and `readFile` both answered about a *prefix* and agreed with each other. The reference now says so; the check that would refuse it is small and has one customer with an exact workaround |
| Integer sizes: byte, word, long | **No — and it was tested on 2026-08-31** rather than argued again. SHA-256 is defined on mod-2^32 arithmetic and is [the first program here to want them](#it-was-written-on-2026-08-31-and-the-prediction-held-in-both-halves); it does not need them, because a 64-bit integer holds the sum of five 32-bit values with fifty-nine bits to spare. The cost of refusing is twenty-three masks in one program |
| Separate float and double | **No** — same reason, less benefit |
| `include` another file | **Built** — was the most valuable thing on the list |
| `System:exit(code)` | **Built** — as `system:exit`, and the `system` object grew well past it |
| Keyboard input | **Both built** — `readLine`, and `readKey` once it earned its own entry |
| File handling | **Built** — whole-file, and the filesystem around it |
| JIT to native code | **No** — possible, and it would dwarf the project; the cheap alternative it named was measured in the end and is [slower than the `switch`](#computed-goto-dispatch--measured-and-refused) |
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
| Infix operators, `@expr(a^2 + b/2)` | **Built**, on 2026-08-28 — [scoped in the morning and in by the evening](#infix-arithmetic-as-a-compile-time-notation): arithmetic, then `sin(x)` once *limiting* it turned out to be the expensive half, then comparison and logic, and the name with them |
| `@expr{...}`, a region that is a block | **Built on 2026-08-29**, the day after it was scoped — [the sentence was tried first and lost](#expr-a-region-that-is-a-block-rather-than-a-group); the entry predicted one hard part and the second was the one that mattered, a notation that silently stopped inlining |
| Phoenix — a second language whose output Solum uses | **Defer** — the machinery is proven three times over; [the unexplored half](#programs-that-would-press-on-something) is whether a hosted language can publish a *library* rather than a program |
| Programs that would press on something — Pascal, predicate logic, a parser toolkit, `tail`, and [which Unix tool next](#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31) | **Defer, and none needs permission** — each is [predicted to find one thing](#programs-that-would-press-on-something), written down before it is written. **The editor was written**, and found what this page said it would. **So was `sha256sum`, on 2026-08-31**, the first off the Unix survey and the first program here with no I/O in its inner loop: [the prediction held in both halves](#it-was-written-on-2026-08-31-and-the-prediction-held-in-both-halves) and produced the number it was written for — **208 bytecode instructions a byte, 4.3 ns each, 234M a second** |
| Networking, and sending code to a running machine | **The first half is built**, on 2026-08-29 — [extensions/net](../extensions/net/README.md), five messages, and the waiting question answered with a timeout rather than a block; [the second half](#networking-and-sending-code-to-a-machine-that-is-already-running) is untouched and still needs 3.4, 6.32 and a proxy |
| SQLite, SDL2, GTK | **One project, not three** — [extensions](#extensions-a-capability-from-a-binary-rather-than-from-the-vm); GTK and SDL2 fire that trigger and SQLite does not, and wanting *both* toolkits is what settles the mechanism |
| Graphics in SolaBasic, over SDL2 | **No — asked and closed on 2026-08-30, and the premise was wrong** to begin with: [graphics were never parked](#graphics-in-solabasic-through-the-sdl2-extension) for want of extensions, they were refused as *the PC*. No program wanted a screen, so the trigger never fired. The throwaway exercised the foundation without a language change — an extension send at 205ns, **`sdl:present` vsync-locked at 8.3ms**, and **1.49x from 0.39.0** on a globals-heavy loop. **A demo written that evening then corrected the entry**: a present keeps nothing, so immediate-mode `PSET` is not slow on this surface but absent. **And there is no oracle for a pixel**, which is what would decide it if it were ever asked again |
| What Python has that this does not | **Surveyed on 2026-08-30** — [most of it is already here under another name](#what-python-has-and-which-of-it-this-language-wants); five had no line on this page, and **named arguments were then investigated and refused** — `name:` is already a valid send, `=` lowers cheaply but [would not generalise](#and-the-lowering-is-cheap-which-is-not-the-same-as-being-right), and the options array turns out to catch every mistake it was accused of passing. Decorators turn out to be writable today; a backtrace is [already captured and then discarded](#read-on-2026-08-30-it-is-not-merely-available-it-is-thrown-away), though no handler in the tree could use one; a file being readable only whole is an absence the reference now states, with [the edge measured](#and-the-edge-was-measured-which-is-what-the-limit-was-missing) — 2 GB hard, twice the file while reading, and **since 2026-08-31 a [range](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) reads part of one** |
| `@dict[k=v]`, and `=` moved to `==` | **Half yes, half unnecessary** — [`=` never needed freeing](#a-dictionary-literal-and-the-message-that-has-to-come-first): the lexer's mode flag exists for `-` alone, and `:=` with `==` is half of C and half of Pascal. But `[...]` is *measurably* sugar over `array:of`, and there is no `dictionary:of` — **both built on 2026-08-30** — `dictionary:of`, then `#["key" = value]` over it — it shipped with no caller, and [converting `run`/`capture` was then scoped and refused](#converting-run-and-capture-to-take-one--scoped-and-refused): every options bag would grow 13 characters and lose the repeated-name error. Which is the best measured argument yet **for** the literal |
| Fuzzy logic | **A library that would teach nothing** — arithmetic on floats, and the arithmetic all landed |
| Namespaces for included files | **Defer** — the trigger is somebody else writing a library |
| Splitting the reference into pages | **Defer** — the trigger is the message reference outgrowing the rest |
| Restricting what a script may reach (6.32) | **Defer** — the trigger is a script somebody else wrote, or input from a stranger |
| Extensions: a capability from a C binary | **Triggered by GTK on 2026-08-28, [probed rather than argued](#gtk-and-the-afternoon-that-was-supposed-to-be-a-page), and built the same day** — `--extension=`, [extend.h](../solum/include/solum/extend.h), the ABI handshake and [the contract](extensions.md). `dlopen` beats embedding on a combinatorial argument; the callback into a main loop is free; the build blocker this page named was wrong and the real one was quieter. **The second half is `SolForeign` and a callback registry**, both built — real sockets found that bytes are the wrong currency for a scarce resource, so a foreign cell carries a collection pressure of its own; the registry nothing above anticipated, and it hands back a token so a released block *says so* rather than answering a plausible wrong one |
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
| The exported symbol surface | **First half built on 2026-08-30** — [146 exported where 23 were declared](#the-exported-symbol-surface-and-the-lto-it-is-blocking), so an ordinary refactor could break an extension silently. `SOL_API` and `-fvisibility=hidden` take it to 29, both directions tested; the `-flto` it unblocks is 5–29% and stays a separate call |
| Computed-goto dispatch | **No, and it was built to find out** — [1% to 13% *slower* than the `switch`](#computed-goto-dispatch--measured-and-refused) on all nine benchmarks and on a real program, because clang tail-merges the 21 dispatch sites back into one and the extra code size stays. The tail-call form is the technique that would work, and is much larger |
| An inline cache at the send site | **Defer, and the entry was about the wrong ten percent** — [profiled rather than argued](#an-inline-cache-at-the-send-site): lookup is 9.7% of the benchmark that asked for it, and the two things above it are a missing `inline` and `-flto`, which is 5–29% across the suite and silently takes the extension ABI with it |
| Making the interpreter faster — four candidates | **Two built on 2026-08-30**, [each measured first](#where-the-interpreters-time-actually-goes--two-built-two-left): the receiver check inlined, and a global remembered where it was found rather than hashed every time. 1.04–1.28× across the suite, 1.065× on a real program, and the CPython geometric mean 1.02 → 0.885. Computed-goto dispatch was then measured and [refused](#computed-goto-dispatch--measured-and-refused); the LTO symbol surface is the one left |

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

### Nothing checks that a link points at a heading that exists

**Found on 2026-08-31 by moving a heading.**
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done)
closed, so its section moved from [ROADMAP.md](ROADMAP.md) to
[COMPLETED.md](COMPLETED.md), and four links written that morning went on
pointing at an anchor that no longer existed. A sweep for the rest of them found
two more — one written the same day, one older — of which one pointed at a
heading in a *different file* from the one it named.

**[expect.sol](../programs/expect.sol) checks a great deal and not this.** It
runs every code block, recounts every marked number, holds `GRAMMAR.md` against
`solum.bnf` and checks that each changelog entry names a commit. A link is the
one cross-reference in these documents that nothing verifies — and this
repository moves headings, because an entry moving from one file to another when
it closes is the whole filing system.

**It is small.** Collect every `## `/`### ` heading per file, lower-case it,
strip everything but word characters, spaces and hyphens, and turn spaces into
hyphens — that is GitHub's rule and about ten lines. Then every markdown link
carrying a `#fragment`, in `docs/`, `README.md`, `index.md` and the `.sol`
headers, is either in the set or it is a finding. The sweep that found these three was that, in
Python, in a scratch directory.

**Against building it now**: it is a checker for the *documents*, and this
repository's checkers have all been asked for by something going wrong more than
once. This is once. Nothing that shipped was broken — a dead anchor lands the
reader at the top of the right file rather than nowhere.

**Trigger: a second time a heading moves and takes links with it**, which is a
release away — closing entries is the routine that does it. Or somebody
following a link in the published documentation and landing in the wrong place,
which is the version of this that costs a reader rather than a writer.

> **Built on 2026-09-01, and the trigger never fired.** There was no second
> heading move; it was built on instruction, and saying so is the whole use of
> having written a trigger down. It is in
> [expect.sol](../programs/expect.sol) and in `make test` — 1,313 links across
> 124 files against 1,496 headings the day it went in, and every anchor and
> every resolved link agreeing character for character with an independent
> implementation in Python. Those two totals move with every document that
> gains a link, so they are written here as of a day rather than given a
> `<!--count-->` marker: a marker that goes stale on every documentation commit
> is noise, which is the opposite of what the marked counts are for.
>
> **What the throwaway found is not what the checker finds, and that is the part
> worth keeping.** The Python version reported one dead anchor in
> `CHANGELOG.md`. Chasing it turned up two real faults in that file, both of
> them markdown that renders as something other than what it says: a paragraph
> wrapped so that ``` began a line, which is a code fence; and an inline code
> span wrapped so that `<if-statement>` began one, which kramdown reads as raw
> HTML and which stopped the published page rendering from there to the end of
> the file. **64 of that page's 327 headings reached the site**, and had not
> since 0.20.0.
>
> **The dead anchor it reported was neither of them.** It came from the
> throwaway's own fence rule, which closed a block on any line beginning with
> ``` rather than on a bare one; under the rule the renderer keeps, that link is
> fine, and the shipped checker reports nothing on a tree with both faults still
> in it. A finding that is right that something is wrong and wrong about what it
> is costs as much as a check that cannot fail, and this one was one edit away
> from being written up as a defect of the kind it was not.
>
> **What actually found them is not in `expect.sol`**: the count of headings the
> published site renders against the count in the file, over every page, which
> needs the network. That is the check with a case now, and it has no trigger
> written for it yet.

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

### A path with a NUL in it is silently a different path

**Found on 2026-08-31 by [sha256sum.sol](../programs/sha256sum.sol)**, reading a
checksum list written with `-z`, where each entry ends in a NUL rather than a
newline.

A Solum string is length-counted and may hold a NUL anywhere; a path handed to
the operating system is a C string and stops at the first one. So every
filesystem message on `system` answers about a **prefix** of the name it was
given, and says nothing:

```
system:writeFile("build/nul-path.txt", "hello\n").
name := "build/nul-path.txt":concat(#0:asCharacter):concat("zzz").
name:size:print.                  ; #22
system:fileExists(name):print.    ; true
system:fileSize(name):print.      ; #6    -- which is build/nul-path.txt
system:remove("build/nul-path.txt").
```

**What made it worth an entry is how it failed, not that it failed.** The
program printed

```text
h.txt<NUL>e258d248...  w.txt: OK
```

— and the digest in that line was *right*. `fileExists` and `readFile` both
quietly saw `h.txt` and agreed with each other about a file the program had not
asked about, so nothing anywhere raised, and the only visible symptom was a
mangled name in a line that said OK. **A wrong answer that agrees with itself is
the expensive kind**, and this language usually refuses rather than guessing:
arithmetic traps instead of wrapping ([strictness.sol](../examples/strictness.sol)),
a short read is an error rather than a shorter string, and `run` takes an array
so that nothing in it can be read as syntax. A path quietly becoming a different
path is out of character with all three.

**The documentation invited it.** The reference's paragraph on files says a NUL
is a byte like any other and that `split`, `indexOf` and `copyFrom` all go by
the length rather than stopping at one — which is true, and is about a file's
*contents*. Nothing said the *path* is the one string in the system that does
stop. That sentence has been added, because it is the fix that costs nothing and
is right whatever is decided below.

**The shape, if it is ever built.** One check, in whatever turns a Solum string
into a `const char *` path — if the length and `strlen` disagree, raise
`a path cannot contain a NUL` rather than proceeding. It is a handful of lines
in one place, it cannot break a program that was working (no reachable file has
such a name), and it converts a silently different answer into an error naming
the fault.

**Against building it now**: one program has hit it, in one place, and its
workaround is exact rather than approximate — a name is cut at the first NUL,
which is what a filename *is*, and the tool on this machine does the same. This
also cannot be reached by accident from a literal, since `\0` cannot be written
in one ([`#0:asCharacter`](REFERENCE.md#string-escapes) is the only way): the name has
to arrive from a file or a computation, which is exactly the `-z` case and
nothing else so far.

**Trigger: a second program building a path from input it did not write.**
Anything reading names out of a file, an argument, or a socket — a `-z`-aware
`xargs`, a manifest reader, a server mapping a request to a file. The third of
those is where a silent prefix stops being a curiosity, and it is also the case
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine) is about,
which is deferred rather than taken.

### `startsWith` and `endsWith`

**Found by writing [server.sol](../extensions/net/server.sol)** on 2026-08-29,
which reads a one-line protocol and wanted to ask whether a request began with
`"add "`. There is no `startsWith`, and the message it wrote instead is
`text:indexOf("add "):equals(#1)`.

**Deferred on 2026-08-29 — one customer, and the workaround is exact rather than
approximate.** `indexOf` answering `#1` *is* what starting with something means,
so nothing is being approximated and, it said, nothing is slower: *`indexOf`
stops at the first match either way.* What a `startsWith` would buy is that the
sentence reads as the question.

`endsWith` would come with it, and is the half with an actual argument: it is
`copyFrom` and a `size` subtraction today, which is three sends and an
off-by-one waiting to happen.

**The trigger is a second program**, as it was for `replace` — which waited for
the editor's port to want it three times in one line, and was built the day it
did.

#### The trigger fired, and the paragraph above is wrong about the cost

**Counted on 2026-08-30.** Three programs, nine call sites, and **two
independent implementations of `endsWith`**:

| where | what it wrote |
| --- | --- |
| [server.sol](../extensions/net/server.sol) | `text:indexOf("add "):equals(#1)`, with a comment saying there is no `startsWith` — the original customer |
| [expect.sol](../programs/expect.sol) | six `indexOf(...):equals(#1)` tests, **and its own `string:endsWith` method** |
| [plugins.sol](../examples/plugins.sol) | one of each, with `endsWith` written again as a local block |

**And the absence has already cost a defect**, which is more than a trigger.
expect.sol's own note records it: matching `.md` anywhere rather than at the end
*"called both of them files to check, and would have handed `a.md.sol` to the
markdown checker. Nothing in the tree is named that way today, which is exactly
how it went unnoticed."* That is the gap producing a bug, found by reading rather
than by failing.

**The claim that nothing is slower is false, and by three orders of magnitude.**
`indexOf` does stop at the first match — but when there is *no* match it has
scanned the whole string, and *no match* is exactly the case a prefix test is
written to detect. On a 128 KB string that does not contain the needle, 2000
repetitions each:

| | per call |
| --- | --- |
| `big:indexOf("add "):equals(#1)` | **308 µs** |
| `big:copyFrom(#1, #4):equals("add ")` | **150 ns** |

A prefix test is O(needle); the workaround is O(haystack). The entry compared
them on the matching case and generalised from it.

**It is also on network input.** server.sol's test runs on a UDP payload, and
[net.c](../extensions/net/net.c) receives into a 65536-byte buffer — so a
maximum-size datagram from a stranger buys a full scan for a question that should
read four bytes. Bounded, and a thousandfold.

#### Where they go, and why the first step is already taken

[text.sol](../lib/text.sol) is the precedent and says so itself: *a method on a
built-in class needs no name of its own, which is what control.sol does with its
loops, and it is the better answer whenever the thing being added is behaviour on
a value.* `string:startsWith` and `string:endsWith` belong there, and expect.sol
has **already written the second one in exactly that shape** — so the method
[the collections entry](#a-set-and-the-collections-that-are-not-there)
prescribes, *write it in Solum, use it, and measure before promoting it*, is a
step further along than it looks. Two programs wrote it; a third would be copying
rather than deciding.

A Solum `startsWith` is `copyFrom` and `equals`, which allocates a substring to
throw away but is **already the right complexity** — the win over `indexOf` is
the asymptote, not the allocation. Whether it then earns a primitive is the
measurement that comes after the library, not before it.

**Built the same day, in `lib/text.sol`, in Solum.** `startsWith` retired nine
call sites and one performance cliff; `endsWith` retired two copies of itself and
the bug that wrote one of them. Seventeen cases checked, the empty affix included
— it answers true both ways, and a prefix longer than the text answers false
rather than raising, which the `size` guard is there for rather than for speed.

**And including the library into `expect.sol` broke `expect.sol`, which is the
part worth keeping.** That program reports `integer:slots:size` as *the number of
messages an integer answers*, and `class-and-instance.md` states it. `text.sol`
puts `asUtf8` and `utf8Tail` on `integer`, so the figure moved 37 → 39 the moment
the include landed, and the checker caught its own contamination on the first
run. The rule it leaves is general and was not written down anywhere: **a program
that measures a class cannot measure it after loading a library that extends
it.** `scan.sol` had never shown this because it binds an object and adds nothing
to a built-in. Reading the number before the includes is the whole of the fix.

**`string:first` and `string:last` do not come with them.** The dominant idiom in
the tree is a different function: `copyFrom(#1, size:sub(n))` — *all but the last
n* — in shell.sol, basic.sol, edit.sol, serve.sol and expect.sol. `last(#n)` is
what both `endsWith` implementations use inside themselves, so it would follow
from the library rather than lead it, and *all but the last* has never been
named at all. Left where it is until the library above exists and says which of
the two it wanted.

### What a string is — bytes, code points, or bytes with a contract

Three documents point at this one and none of them owns it.
[`!character`](#character-literals-and-unicode) defers to it by name.
[2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only) files it as a
restriction the language lives under rather than a question waiting on an
answer. [performance.md](performance.md#what-is-not-fair-here-said-plainly) says
the strings row does not compare like with like and leaves it there.

Written up on 2026-08-30 because it was asked for, and the asking turned up
something none of the three had: **a program that has already got this wrong**,
which is further along than a deferred idea is supposed to be.

#### What is true today

```
"café":size:print.               ; #5   -- four characters, five bytes
"café":at(#4):asByte:print.      ; #195 -- 0xC3, the first byte of é
"café":indexOf("é"):print.       ; #4   -- a byte offset
"CAFÉ":asLowercase:display.      ; cafÉ -- case is a-z and A-Z, by range
```

A `SolString` is a length and a pointer
([object.h](../solum/include/solum/object.h)), immutable, compared by value,
with a one-byte string answered from the machine's cache rather than allocated.
Nothing in the VM interprets a byte except the two ASCII case ranges and the
digit parsing in `asInteger`. There is no encoding anywhere in it: a string is
as happy holding a JPEG as a sentence, and `#0:asCharacter` puts a NUL in one.

The sharp edge is the one 2.13 names, and it is silent — a cut on a byte
boundary answers a string whose last byte is the front half of a character, and
nothing anywhere says so:

```
"café":copyFrom(#1, #4):size:print.            ; #4    -- three letters and a piece
"café":copyFrom(#1, #4):at(#4):asByte:print.   ; #195  -- é's lead byte, orphaned
```

#### What is missing from today's model, rather than from a different one

`integer:asUtf8` in [text.sol](../lib/text.sol) turns a code point into bytes,
and has two customers: [json.sol](../lib/json.sol) for `\uXXXX` and
[html.sol](../lib/html.sol) for `&#233;`. **Nothing goes the other way.** No
message anywhere in the tree reads UTF-8 bytes back to a code point.

That gap looks like an oversight and is not one. Both customers are *producing*
text from a number some format handed them, and a decoder is wanted by something
*reading* text and asking what character is sitting there — which nothing here
did. The asymmetry in the library is an honest report of the asymmetry in the
programs, and it is the reason this decision has never been forced.

#### The three models

| | `size` answers | `at` answers | can hold a JPEG | the migration |
| --- | --- | --- | --- | --- |
| **A. Bytes** — today, and C | bytes | a one-byte string | yes | none; it is what is here |
| **B. Code points** — Python 3 | characters | a character | **no** — needs a second type | every message, every boundary |
| **C. Bytes with a contract** — Go, Rust | bytes | a one-byte string | yes | additive; nothing changes meaning |

#### The editor has already asked, and it is worth reading how

[edit.sol](../programs/edit.sol) says, in its own notes:

> **A tab is one byte and eight columns**, and everything that positions a
> cursor holds both numbers at once. Every editor ever written has this; it is
> where most of the arithmetic in this file went.

An `é` is **two bytes and one column** — the same mechanism with the numbers the
other way round, and the editor does not know about it. Driven with scripted
keys through [checks.sol](../programs/edit/checks.sol)'s harness, against a file
holding `café`:

```
file     "café\n"
keys     $x
written  "caf" and a lone 0xC3 -- half of é, on disk, with nothing said
```

`$` lands on the last *byte*, which is the second byte of `é`, and `x` deletes
it. The screen has the matching error: on `café x`, the cursor-positioning
escape the editor writes for `$` is `ESC[1;7H` — column seven, one to the right
of the `x` it is meant to be sitting on. `dw` on the same line deletes `caf` and
stops, because a byte above 127 is not a letter to its word test.

**But look at what fixing that needs.** `edit:expand` is nine lines and is
already the single place where bytes become columns; teaching it that a
continuation byte is worth no columns is
`c:asByte:bitAnd(#192):equals(#128)` — three sends, using nothing that is not
in the language today. The word test needs the same three. Neither wants `size`
to change its mind, and neither wants a character type.

*(That paragraph was written before the fix and got the size wrong by a factor
of five. What it got right is the part that matters — the three sends, and that
nothing in the language had to move. See
[below](#and-the-editor-was-fixed-which-cost-more-than-this-entry-said).)*

**That is evidence, and it points at C.** The program that finally asked for
Unicode asked for it *locally*, in the two places that face a screen, and what
it wants underneath is exactly the byte string it has: the cursor is a byte
index because `copyFrom` takes byte indices, and every edit is a `copyFrom`. A
language where `size` counted code points would have solved the editor's
problem by taking away the index it does its work with, and the editor would
have had to build it back.

#### Why B is the expensive one, and the encoder is not the expensive part

A string that promises code points cannot hold `readFile` of a JPEG, so a second
type appears beside it. Then every message has to be decided onto one type or
both; every boundary — `readFile`, `readLine`, `readKey`, `system:arguments`,
the `char *` in [extend.h](../solum/include/solum/extend.h), a socket in
[extensions/net](../extensions/net/README.md) — needs a declared encoding and an
answer for input that is not valid in it; and `equals` between the two types has
to be false in a way that surprises everybody exactly once. That split was the
costly half of Python's own 2-to-3 migration, and it is the whole of this work
rather than an aside to it.

The part that *looks* hard is already done and was cheap: the UTF-8 arithmetic
is under twenty lines of Solum in text.sol, first written before the language
even had `shiftRight` — with `div(#64)` for a shift and `mod(#64)` for a mask.
Carrying it is what made the case for the bit messages.

There is a second cost peculiar to here. A one-byte string is answered from the
machine's cache of 256 rather than allocated (`bytes` in
[vm.h](../solum/include/solum/vm.h)), which is the optimisation
[performance.md](performance.md) credits with making that benchmark row a fair
comparison at last. A code-point string does not have 256 of anything, and that
cache would go.

#### Why C is cheap here, and the reason is a shape the language already has

Go needs a `rune` and Rust needs a `char` because indexing a string in either
one hands you an integer. **`at` here answers a one-character string**, and
[vm.h](../solum/include/solum/vm.h) already says why in passing — *"`string:at`
answers a one-character string, there being no character type"*. So a
code-point-aware `at` answers a two-byte string, and no new type appears
anywhere:

```
"café":at(#4)              ; today: one byte, 0xC3 -- half a character
"café":characterAt(#4)     ; a sketch; not valid today -- "é"
```

`"é"` is already the literal for the value that would answer. Which settles
[`!character`](#character-literals-and-unicode) as a side effect, and settles it
*against*: the character type Unicode would want here is the one-character
string the language already has, so `!` never becomes the right spelling for
anything. That entry can stop waiting on this one.

The shape, and it is a sketch rather than a proposal: a small set of messages
that say *and I mean characters* — a character count, a character-indexed `at`,
a walk over characters, and the byte count of the character at a byte index,
which is the one the editor actually needs. Beside them, `size`, `at`,
`copyFrom` and `indexOf` keep meaning bytes, so no program written today changes
behaviour and no boundary grows an encoding.

**The cost of C, said plainly:** two answers to *how long is this*, and a reader
has to know which one a line wanted. That is what Go lives with and people do
trip over it. The defence is only that today there is one answer and it is the
wrong one for anything facing a screen, which is worse than ambiguous.

#### A `text` type beside `string`, with a prefixed literal to make one

**Asked on 2026-08-30**, in the same conversation this entry came from: a second
type specialised for Unicode, with a prefixed literal to build one, so that
`x := !"unicode text"` makes an instance of `text` and `"unicode text"` goes on
meaning bytes.

It deserves a hearing rather than a paragraph, because two of its instincts are
right and one of them is right about something this entry got wrong.

**The polarity is correct, and it is the opposite of Python 3's.** Python 3 made
Unicode the default and bytes the opt-in, which is why every `open` became an
encoding decision and why the migration cost what it did. This keeps bytes as
the default and makes Unicode the thing a program asks for. That is Python *2*'s
polarity — `str` and `u"..."` — and Python 2's version failed for one specific
reason that **does not apply here**: implicit coercion. `"a" + u"b"` decoded as
ASCII on the quiet and raised in production six months later. This language
refuses coercion as a matter of principle, and gives
[the same reason for refusing byte and word integers](#integer-sizes--byte-word-long);
`"abc":concat(!"déf")` would be a strict error, and the whole Python 2 failure
mode goes with it.

**And it is the only design where `copyFrom` cannot split a code point** — which
is a real advantage over C, and one this entry undersold above. Under C the
silent half-character is still reachable and the defence is that a programmer
remembers to reach for the other message. A `text` whose indices are character
indices makes the corruption unrepresentable. Invariant carried by the value
rather than by somebody's memory is the stronger design, and saying otherwise
would be dodging.

**Both spellings were already taken, which is the small objection — and is why
this page now writes `!` for a sigil nobody has proposed in earnest.** It was
asked as `$"..."`, and `$` is the hexadecimal prefix: `$FF08` is `#65288`, `%`
is binary, and the reference argues in as many words that `$FF` needs no `#`
because it has one reading. `&` was the second guess and is not free either —
it is logical *and* inside a [`@expr`](#infix-arithmetic-as-a-compile-time-notation)
region, `TOK_AMP` in the lexer. Between them the infix work and the bases have
spoken for twenty-six characters; what the lexer's switch never reaches is `!`,
`?`, `_` and a backtick, and of those `_` belongs to identifiers and a backtick
fights the prose it would be written in. That leaves two, and this entry spells
it `!` so that a future reading of the argument is not also a puzzle about which
`$` is meant.

And `text` is the name [text.sol](../lib/text.sol) deliberately declined to bind,
with the incident on record in its own header: the first draft bound a global
called `text`, the first program to use it had a variable called `text`, and the
library broke from a distance. A class is a global.

Neither of these decides anything — a spelling is the cheapest thing here to
change, which is what just happened to it. They are worth knowing before the
spelling is argued, and they are the reason the argument below is about the
*shape* rather than the character.

**The literal marks the wrong end of the pipe, which is the real objection.**
`!"unicode text"` and `"unicode text"` are *the same bytes in the source file*.
The prefix is not marking that the text contains Unicode; it is marking
*validate these as UTF-8 and tag the result* — so the type does all the work and
the literal is a constructor, which `"...":asText` already spells without
touching the grammar. And text worth worrying about never arrives in a literal.
It arrives through `readFile`, `readLine`, `readKey`, `system:arguments`, a
socket. A literal somebody typed is the one case that was never broken.

**So the coherent version is at the boundary — and that is where the editor
kills it.** Say `system:readFile(path, 'text)` decodes. Decoding needs an answer
for a byte that is not valid UTF-8, and both answers are wrong for the one
program that asked:

| answer | what the editor becomes |
| --- | --- |
| raise | an editor that cannot open a Latin-1 file, or a binary one, at all |
| replace with U+FFFD | an editor that silently corrupts on *write* — worse than today's defect, which damages only what was edited |

vi opens anything, and so does this editor. It would stay on bytes and keep
doing the code-point arithmetic locally, which is what its tab-and-column split
already is. That is not a coincidence: Vim's buffers are bytes and its cursor is
encoding-aware, for this reason. **A type the real programs decline to hold is a
type that rots**, and the honest test of a second type is which side `edit.sol`
comes down on.

**What it would cost.** Twenty-five registrations on `string_class` today, of
which about twenty want reimplementing for `text` — every message that counts,
indexes, cuts or compares. Then a fourteenth `SolValueType`, GC marking, a
`.sob` serializer tag, `print`, `display`, `asString` and `equals`, the
dictionary-key rule, and a decision at both foreign boundaries: `embed.h` and
the `char *` in [extend.h](../solum/include/solum/extend.h) — bought for a
guarantee the only customer cannot use.

**And it does not have to be paid to find out.** The trigger the
[extensions](#extensions-a-capability-from-a-binary-rather-than-from-the-vm)
entry set for putting a capability in C is *wanting something Solum cannot
express*, and this is not that. A `text` **object** over a byte string is
writable in a library today: it would hold the bytes, validate them once on the
way in, and answer a character count, a character-indexed `at` and a
character-safe cut, over `asByte` and the bit messages. What it could not have
is a literal, a `print` form, or `equals` against a string — and none of those is
needed to learn the only thing worth learning, which is whether any program
wants to hold one. That is the throwaway that comes before the design, and it
costs an afternoon rather than a fourteenth value type.

**What survives it, and it is the useful half.** The instinct — *an invariant
should be carried by a value, not remembered* — is right, and there is a cheap
form: a **validity predicate on a string** rather than a type. One primitive,
`isValidUtf8` or whatever it ends up called, invents no type, claims no global,
leaves the byte index where `copyFrom` needs it, and is the part of the `text`
type the editor would actually have called. It is the boundary check without the
boundary conversion.

And a separate type becomes right the day this language wants normalisation,
collation, locale-aware case, or grapheme clusters — those genuinely need an
invariant that a set of messages cannot enforce. None of them has a customer,
and none is near having one.

**Verdict on the variant: no — but it is model B with a better front door, and
the front door is on the wrong end.** Recorded at this length because it is the
kind of proposal that is re-made in six months by somebody who has not seen the
editor's answer to it.

#### And the editor was fixed, which cost more than this entry said

**On 2026-08-30, the same day.** Sixteen sessions were added to
[checks.sol](../programs/edit/checks.sol), eleven of which failed on the editor
as it stood; all 181 pass now, and the screen transcript
[session.out](../programs/edit/session.out) is byte-identical, sideways-scrolling
tab line included, which is what says the ASCII path did not move.

**The estimate above was wrong by a factor of five, and wrong in an interesting
direction.** *Nine lines in `expand`* turned out to be seventeen definitions and
four new helpers. `expand` was barely one of them: it draws the bytes, so the
column count had to move out into a `widthOf` beside it, and `visible` — which
sliced the drawn text with a `copyFrom` because a column was a byte — became a
walk.

**What the estimate got right is the part the decision rests on.** The three
sends really are the whole of it: `isTail` is `bitAnd(#192):equals(#128)`, and
`charSize`, `charAt` and `widthOf` are four lines each on top of it. Nothing in
the language moved. No message changed its mind about bytes, no boundary grew an
encoding, and the editor still opens a file that is not UTF-8 — a stray byte is
one character, `x` takes exactly it, and every byte the editor was not asked to
change is written back untouched.

**Two of the seventeen carried most of the weight**, and both are places the
program already had:

| where | what one line did |
| --- | --- |
| `clamp` | *a cursor is never inside a character*, made true for every command at once — `$` included, which is where the corruption was |
| `operateChars` | the single `add` that turns an inclusive motion's last character into a range: `d$`, `de`, `dfx` and `x`, answered together |

**And one exemption is load-bearing: insert mode.** A character outside ASCII
arrives from `readKey` one byte at a time, so the column *must* be allowed to
stand between the bytes of a character while it is being typed. The rule is
therefore about normal mode and not an invariant on the buffer — which is
exactly the shape a `text` type could not have had, and is the sharpest evidence
in this entry for keeping the invariant in the program rather than in the value.

**What this did not do**: `f` and `r` read one key, so they still take a byte;
they are safe because no ASCII byte appears inside a multi-byte UTF-8 character,
which is the property the encoding was designed around. There is still no
decoder in [text.sol](../lib/text.sol) — the fix never needed one, which is the
second prediction on this page that held.

#### Verdict

**Defer — and the model to defer toward is C, not B, including when B arrives
wearing
[a second type and a prefixed literal](#a-text-type-beside-string-with-a-prefixed-literal-to-make-one).**
The trigger has half fired: a program asked, and the same program can answer for
itself with what is already in the language. That is the outcome this page keeps
predicting, and it is worth noticing when it happens — the pressure that would have justified a
language change turned out to be pressure on one function in one program.

**Trigger for the language change: a second program wanting character
arithmetic.** The editor has now written the three sends once; a second program
writing them again is when they belong in the language, which is the rule
`replace` and the cursor were both built under. `isTail`, `charSize`, `charAt`
and `widthOf` in [edit.sol](../programs/edit.sol) are what that second program
would be copying, and copying them is the signal — not the inconvenience of
having to.

**Trigger for a decoder in text.sol: the editor's fix, if it is written.** It is
a dozen lines beside `asUtf8` and it is the inverse of code that is already
tested; what it has never had is a caller.

**And one thing is cheap enough to want a customer rather than a decision: a
validity check on a string.** One primitive, no type and no global, and it is
what a boundary actually needs — see
[the variant above](#a-text-type-beside-string-with-a-prefixed-literal-to-make-one),
which is where the case for it came from.

**What would not count.** Parsers, protocols, compilers, `solas`, `json`,
`html`, `pattern`, the Pascal front end, the assembler, the server — all
byte-shaped by nature, and all of them are most of what has been written here.
A program is not asking for Unicode because its input contains some; it is
asking when it has to *count* or *cut* characters and cannot say what it means
in bytes. Only a screen has wanted that so far.

### `!character` literals and Unicode

`!x` for a character, and `!😊` for one outside ASCII.

The character type on its own is small. The problem is that it cannot be decided
separately from what a string is, and today [a string is
bytes](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only): `size` counts
bytes, `at` answers a one-byte string, and `"café":size` is 5.

So `!x` forces the question. If a character is a **code point**, then `at` should
answer one, and `size` should count them, and every string operation changes —
that is the Unicode work, and it is a different piece of work rather than a
larger version of this one. If a character is a **byte**, then `!😊` cannot exist
and the type buys almost nothing over a one-character string.

Adding an ASCII-only `!x` now would make the Unicode decision harder later,
because there would be a character type with the wrong semantics to migrate.

**Trigger:** decide what a string is first. If strings become code-point aware,
a character type follows naturally and `!` is the right spelling for it.

**And that decision now has an entry of its own**, written on 2026-08-30 —
[what a string is](#what-a-string-is--bytes-code-points-or-bytes-with-a-contract).
It recommends against the branch this paragraph was waiting for, which removes the trigger rather than firing it: if
strings stay bytes and gain code-point *messages*, the value a character-aware
`at` answers is a two-byte string, `"é"` is already its literal, and there is
no type left for `!` to spell.

---

### What Python has, and which of it this language wants

**Asked on 2026-08-30.**
[lineage.md](lineage.md#what-the-relatives-have-that-this-does-not) says this
page carries the survey of what the relatives have that Solveig does not, and
names them: Smalltalk, Self, Io, Lua and Ruby. **Python is not among them**,
because when that sentence was written Python was not in the project. It is now
— nine matched programs, a geometric mean of 0.885,
[a fairness section](performance.md#what-is-not-fair-here-said-plainly) that
concedes two rows. Python arrived here as a stopwatch and was never asked what it
*has*, which is the gap this closes.

It is also the relative least like the rest. Smalltalk and Self are where the
object model came from and Lua is the size to aim at; Python shares ancestry with
none of that. Which is the reason to ask rather than a reason not to: a feature
that turns up in a language with different parents is likelier to be answering a
real problem than passing on a habit.

#### Already answered here, under another name

Most of it, which is the honest headline:

| Python | here |
| --- | --- |
| list and dict comprehensions | `collect`, `select` |
| `with`, context managers | [`ensure`](REFERENCE.md#block) — same guarantee, no protocol to implement |
| f-strings | `fill`, and `asString(spec)` for the padding half |
| `repr` and `str` | `print` and `display`, and one `asString` serves both |
| modules, `import` | `@include` and `exports`, with [namespaces deferred](#namespaces-for-included-files) |
| duck typing | the object model, which has no other kind |
| the REPL | `solis` |
| `enumerate`, `zip`, `any`, `all`, `sum` | named already in [the collections entry](#a-set-and-the-collections-that-are-not-there), with a method rather than a verdict |
| `str` as code points | [settled](#what-a-string-is--bytes-code-points-or-bytes-with-a-contract), toward bytes with a contract |
| tuple unpacking | refused as [multiple return values](#multiple-return-values) |
| arbitrary-precision integers | refused with [the integer sizes](#integer-sizes--byte-word-long); performance.md names the trade openly |
| generators, `yield` | refused with [coroutines](#coroutines), and the reason is the C stack rather than the idea |
| `assert` | [has its own entry](#an-assert-and-compiling-it-away) |

Five are left that this page has never had a line on.

#### Decorators — writable today, and the sharp edge is the interesting half

A decorator wraps a method in another one. That needs a slot read, a slot write
and a send, and all three exist:

```
counter := object:new.
counter:count := #0.
counter:bump := { self:count := self:count:inc }.

counter:bumpInner := counter:slotAt('bump).   ; the original, under a second name
counter:bump := { self:bumpInner:mul(#10) }.  ; and a wrapper that sends it

counter:bump:print.                           ; #10
counter:bump:print.                           ; #20
```

**The original has to be given a name, and that is not a wart.** The obvious
shorter version does not work:

```
c := object:new.
c:count := #0.
c:bump := { self:count := self:count:inc }.
c:slotAt('bump):value.
solvm: nil does not understand 'count'
```

`value` runs a block with **no receiver**. A method's `self` is bound by the
*send*, not by the block, which is exactly what makes one definition serve every
receiver — so a block pulled out of a slot and run directly has no `self` to
find `count` on. Putting it back under another name is how it gets sent again.

**Verdict: already writable, and it belongs in the guide rather than the VM.**
The thing worth writing down is not the recipe but the error above: it is the
one place where *a method is a block in a slot* stops being the whole story, and
a reader who has not met it will read that message as a bug in their program.

#### Named arguments — the one on this page with a customer already

Python has keyword arguments; Smalltalk had the same idea as *selectors*, and
[lineage.md](lineage.md) records dropping those deliberately — `copyFrom(#2, #4)`
and not `copyFrom:to:`. What the language does instead is in its own reference,
described as a workaround in as many words:

> an **array of alternating name and value** — the options bag this language can
> spell, since there is an array literal and no dictionary literal.

```
system:capture(noisy, ["stderr", 'discard]).
system:run(cmd, ["stdin", typed, "stdout", 'discard, "stderr", 'discard]).
```

Four call sites in the tree use that shape and every one of them is
`system:run` or `system:capture`.

**Looked at properly on 2026-08-30, and the case is much weaker than the
paragraph that used to sit here.** That paragraph said the pairing is positional
and silent — *a dropped element shifts every name onto the wrong value and
nothing says so*. That was written without trying it, and it is wrong.

#### What the options array actually does when it is wrong

Every way of getting it wrong is caught, and each by name:

```text
system:capture(cmd, ["stderr"]).
'capture' wants a value for every stream named, and got 1 of them

system:capture(cmd, ["stdrr", 'discard]).
'capture' does not know the stream "stdrr" -- there is "stdin", "stdout" and "stderr"

system:capture(cmd, ['discard, "stderr"]).
'capture' wants a stream's name as a string, and #1 is symbol

system:capture(cmd, ["stderr", 'discrd]).
'capture' does not know 'discrd' for "stderr" -- a stream takes 'share, 'discard, 'merge, or a path as a string
```

An odd count is caught, a misspelled name is caught *and the alternatives
listed*, a swapped pair is caught by type, and an unknown manner is caught with
its alternatives too. That is better than most languages' keyword arguments
manage.

**One case is silent, and it turns out to be a deliberate trade rather than a
gap.** The residue has to be even *and* a name has to land in a value slot:

```
system:run(cmd, ["stderr", "stdout"]).      ; the two manners dropped
```

That runs, answers `#0`, and writes the child's stderr into a file called
`stdout`. But the reference has already reasoned about exactly this: a value is
*"a manner, as a symbol, or a path, as a string — and the type is what tells them
apart, which is what keeps a file called `discard` a file."* A string is always a
path, on purpose. The silence is the price of that decision, taken knowingly, and
it lives in the option *values* rather than in the option *shape* — named
arguments would not touch it.

#### The spellings, and why the obvious one is not available

`name:` is not a free slot. It is an existing valid parse:

```
name := object:new.
name:v := #99.
show := { a, b | [a, b]:print }.
show:value(#1, name: v).        ; [#1, #99] -- a send, not a named argument
```

`:` is the send operator, so Smalltalk's own spelling is the one spelling this
language cannot have. `=` *is* free — outside a region it is refused today, with
an error that points at where operators live:

```text
show:value(#1, mode = #2).
solas: this is written as a send here; '@expr(...)' is where the operators are at '='
```

That refusal is what makes it available, and it is Python's spelling. It is not
free *inside* an [`@expr`](#infix-arithmetic-as-a-compile-time-notation) region,
where `=` is equality and a send's arguments are parsed as expressions, so
`obj:f(a = b)` already means *call `f` with the boolean*.

#### And the lowering is cheap, which is not the same as being right

`f(a, mode = v)` rewriting to `f(a, ["mode", v])` needs **no change to any
existing primitive**, because the array it lowers to is the one `run` and
`capture` already take. A parser rule, no new bytecode, no new value type, no VM
change.

**The objection is that it would not generalise, which is the objection that
already refused [`ifTrue{...}`](#iftrue--a-block-argument-without-parentheses).**
A pure rewrite lowers the same way whatever the receiver is, so
`f(a, mode = v)` is spelled like a language feature and works only where the
callee happens to take an options array as its last argument — a convention
encoded in syntax, which is worse than a convention in a library, because the
syntax promises something it cannot check. Making it *general* means a real
parameter kind: a calling convention, arity checking, bytecode. Cheap does not
generalise; general is not cheap.

**Verdict: no to the sugar, and the entry that used to say *defer* was
overstating a case it had not tested.** What is left standing is the smallest
part of the original observation — that an options bag is spelled as an array
because there is no dictionary literal — and that is a note about the literal
syntax rather than about arguments. If anything here ever moves it should be
[a dictionary literal](#a-dictionary-literal-and-the-message-that-has-to-come-first) — or rather the
`dictionary:of` underneath one, which serves every options bag and needs no new
rule about where a name may appear.

#### A file is read whole, or not at all

**Built on 2026-08-31 as a range**, and the entry is kept as it stood because the
reasoning below is what the answer was built to — `readFile(path, from, count)`,
no handle, nothing to close. It became
[3.22](ROADMAP.md#3-known-limitations) and then
[3.22 done](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done); what
finally moved it was that its own trigger — *nothing here has a file that does
not fit* — turned out to be a fact about this repository's inputs rather than
about the world, and a sparse file made one in four seconds.

`system:readFile` answers the whole file as one string, and there is no other way
to read one: no handle, no line at a time, no seek. `fileSize` answering without
reading is the single concession.

For everything in this tree that is correct rather than merely tolerable. The
editor loads a file to edit it, `solas` loads a source to compile it,
`expect.sol` loads a document to check it — **all three want the whole thing**,
and a handle would be ceremony around a single call. The largest input measured
here is a 50,000-line scan in [pattern.sol](../lib/pattern.sol), held entire
without complaint.

But it means **a program cannot read a file it cannot hold**, and the reference
never says so: its file section argues about missing files and copying modes and
mentions no limit at all. That is the part worth fixing regardless of the
verdict — an absence a reader cannot see is worse than one they can.

This is the gap Python's iterator protocol actually names. `for line in open(f)`
is the shape and generators are the machinery, and neither is proposed here:
generators go with [coroutines](#coroutines) and the refusal there is about the
C stack, not about laziness. Nor is a `readLines` answering an array the answer,
since that holds the file too.

#### And the edge was measured, which is what the limit was missing

**On 2026-08-30, the same day.** [mirror.sol](../programs/mirror.sol) had
already reached this conclusion for itself — *a whole-file copy is fine at this
size and not at every size* — and ended by saying it is worth knowing where the
edge is rather than discovering it. Nobody had gone and looked. It is now in
[the reference](REFERENCE.md#files), in the prose and in the limits table:

| | |
| --- | --- |
| hard stop | **2 GB**, a string's length being a signed 32-bit count, refused by name and checked *before* anything is allocated — instant on a sparse file of any size |
| peak cost | **twice the file**: read into a buffer, then copied into the string, which is what makes the string immutable |
| a copy | **twice, not three times** — `writeFile` streams from the string it was handed and adds nothing |
| speed | 256 MB in 0.17 s, peaking at 514 MB resident |

**The measurement corrected the program that asked for it**, which is the part
worth keeping. mirror.sol's note said a mirror of something large *holds it in
memory twice*, and read as though the copy were what doubled it. The copy is
free; `readFile` is the whole of the expense, and a mirror's rule is therefore
twice the largest **file**, not twice the largest pair. That note now says so.

#### If it is ever built, the cheap answer is not a handle

Worth writing down before the trigger fires, because the obvious design is the
expensive one and it is not the one this language wants.

**A handle** — `system:open`, `read(n)`, `close` — brings a lifetime with it,
and a lifetime is the thing this VM has been careful about: it needs a value
type or a foreign cell, a release discipline, a GC interaction, and an answer
for a handle used after closing. [extensions/net](../extensions/net/README.md)
paid all of that for sockets and the retain registry exists because of it. A
socket has no alternative; a file does.

**A ranged read** — `system:readFile(path, from, count)` — has none of it. No
new type, no lifetime, nothing to close, nothing to leak, and `ensure` is not
needed because there is nothing to unwind. `fileSize` already answers without
reading, so the pair composes: ask how big, then take it in pieces. It is one
primitive beside the one that exists, and it makes both costs above go away —
the 2 GB stop and the doubling are properties of *reading it all at once*, not
of files.

Its real cost is that a record spanning two chunks is the caller's problem, and
for line-oriented text that is the whole job rather than a detail. That is
writable in Solum and is the sort of thing [scan.sol](../lib/scan.sol) is
already shaped for.

**Verdict: defer, and toward the ranged read rather than a handle.** The trigger
is unchanged — a program with a file that does not fit — and the documentation
half is done, which was the part that never needed one.

#### A backtrace, and an error object that was built to carry one

The [reference](REFERENCE.md#the-error) says the error is an object rather than a
string so that it can *"say more about a failure later without breaking every
handler that already exists"*. Later has not arrived: `message` is still the only
message on it. Python hands a handler a traceback, Ruby a backtrace, Smalltalk
the live stack.

**The VM already has the information.** An uncaught error prints it:

```
solvm: nil does not understand 'count'
  [x.sol:3] in block
  [x.sol:4] in script
```

So this is plumbing rather than a new capability.

#### Read on 2026-08-30: it is not merely available, it is thrown away

`sol_vm_runtime_error` calls `append_stack_trace` **before** it sets the flag, so
the trace is captured while the frames are still standing and lands in
`vm->error_trace`. `error:raise` goes through the same function — *the message is
what was given, and the stack is where it was given*. Then `onError` catches:

```text
SolValue caught = error_from(vm, vm->error_message.chars, ...);
vm->had_error = false;
vm->error_message.length = 0;
vm->error_trace.length = 0;          <- two lines later
```

`error_from` builds the object out of the message alone, and the line after it
discards the trace. **The information is complete, correct, already paid for, and
dropped on the floor.** Putting it on the object is one `sol_string_new` and one
`sol_object_define`, at catch time only.

**And the capture is already free of the thing that would have made it costly.**
The walk is bounded — eight frames from the top, three from the bottom, and
*"... N more frames ..."* in between — so it does not grow with the stack.
Measured over 20,000 raise-and-catch pairs, the cost of raising and catching over
the cost of the same call not raising:

| stack depth | raise + catch |
| --- | --- |
| 0 | ~0.8 µs |
| 30 | ~1.0 µs |
| 200 | ~0.9 µs |

Flat, which is the elision doing its job. Nothing is saved today by discarding
the trace; the saving would have to come from not building it, and it is built
whether or not anyone catches.

#### But no handler in this tree wants it, and the reason is not laziness

Fifty-nine `onError` sites; forty-nine bind the error, thirty-eight read
`e:message`. Every handler that wants to say **where** already tracks that
itself, and could not use a stack trace if it had one:

| handler | what it says instead |
| --- | --- |
| [json.sol](../lib/json.sol) | its own cursor into the text — *'{}' is not four hex digits* |
| [html.sol](../lib/html.sol) | rewinds its cursor and complains at the mark |
| [manifest.sol](../programs/manifest.sol) | the path it was reading, with `e:message` after it |
| [serve.sol](../programs/serve.sol) | rewinds and takes the byte literally |

**A stack trace answers *where in the code*, and every one of these is asking
either *what now* or *where in the input*.** A trace handed to json.sol's handler
would say `[json.sol:87] in fail` — the library's own insides, and not the line
of the caller's JSON, which is the only location its user cares about. The
absence is not a gap these programs are working around. It is a different
question that none of them asks.

#### And it would not fix the re-raise caveat, which this page claimed it would

The paragraph above used to say a stack carried on the value would make the
lossy re-raise *"a non-question instead of an honest caveat"*. That is wrong.
`error:raise` takes a **string**, and builtins.c refuses a second spelling in as
many words — *two spellings of raising would have been a `new`-shaped mistake* —
so a re-raise constructs a fresh error and captures a fresh trace no matter what
the old value was carrying. A trace slot improves the **first** catch and does
nothing for the chain. Fixing the chain needs `raise` to accept an error, which
is the design that was deliberately not taken.

**Verdict: defer — and the trigger is narrower than this entry first said.** Not
*a program that catches an error and cannot say where it came from*, because
that is all of them and none of them mind. It is **a program that runs code it
did not write and has to report a failure to somebody else** — which is the
unbuilt half of
[sending code to a machine that is already running](#networking-and-sending-code-to-a-machine-that-is-already-running),
and is on this page already. Until something is executing a stranger's block,
the trace has no reader.

If it is ever built: a **string** first, since `vm->error_trace` already holds
exactly the formatted text, and an array of frames only when something needs to
*read* the trace rather than print it. That is the same order the reference gives
for not inventing a taxonomy of failures to go with a catch mechanism.

#### Negative indices — no, and `string:last` is a different question

`a[-1]` in Python. Here an array has `first(#n)` and `last(#n)`, and a **string
has neither** — the last three bytes are `copyFrom` and a `size` subtraction,
which is the same three sends and the same off-by-one that
[`endsWith`](#startswith-and-endswith) was deferred over.

**No to the negative index.** It gives one slot two meanings decided by sign, and
this language spent its literal convention — `#45` against `45` — on the
principle that a value's reading should not depend on inference. An index that is
sometimes from the front and sometimes from the back is that same trade taken the
other way, and `at(#-1)` on an empty array would have to mean something.

**`string:first` and `string:last` looked like the useful half and are not.**
Counting the tree on the same day found the dominant idiom is *all but the last
n* rather than *the last n*, and that what actually wants building is
[`startsWith` and `endsWith`](#the-trigger-fired-and-the-paragraph-above-is-wrong-about-the-cost),
whose trigger had already fired three times over. `last(#n)` is what an
`endsWith` uses inside itself, so it follows that library rather than leading
it.

### A dictionary literal, and the message that has to come first

**Asked on 2026-08-30**, as `@dict[key = value, key = value]`, together with
moving `@expr`'s equality to `==` so that `=` was free for it.

#### The freeing is not needed, and that is the whole of the second half

`=` is scanned unconditionally and given meaning by the parser's context.
[lexer.h](../solas/include/solas/lexer.h) says the mode flag exists for one
operator and names it: *the two are `-`, which is the reason for `infix`*.
Everything else — `+ * / ^ = & ~ < >` — is a token always, and refused where it
does not belong by the compiler rather than the lexer, which is why the
complaint is a compiler's:

```text
show:value(#1, mode = #2).
solas: this is written as a send here; '@expr(...)' is where the operators are at '='
```

Regions carry their own delimiters, so `@expr(...)` and a `@dict[...]` could
never overlap; `=` would mean equality in one and pairing in the other the way
`,` already means different things in an array literal and an argument list.

**And spending it would cost coherence.** This language assigns with `:=` and
compares with `=`, which is one convention — Pascal's, and BASIC's, which is the
family [the infix entry](#comparison-and-logic-and-the-rename-that-came-with-them)
took its precedence from. C's is `=` to assign and `==` to compare. Keeping `:=`
while taking `==` is half of each and lands on a pairing neither language uses,
and it strands `<>`, which would then want `!=` and drag a second change behind
the first. That entry already names this exact pull, in this exact operator set:
*C binds `!` tightest and would have read the other; that is the one place here
where a C habit misleads.*

#### And `@` is the wrong mechanism for a literal in any case

[The directives entry](#more--directives-define-ifdef-once) reserves `@` for what
happens while compiling and refuses a new one when the job is already done by
something that is not a directive. `@expr` earns its `@` by changing how a whole
region **parses**. A literal changes no parsing mode — it is grammar, and `[...]`
needs no directive to be one. If a spelling is ever wanted, `#{` is a lexer error
today (*expected digits after '#'*) and so is free, with no directive and no
operator moved.

#### What a literal would buy, measured: the spelling and nothing else

`[#1, #2, #3]` has no opcode of its own. It compiles to a global load and a send:

```text
GLOBAL 'array'      … then `of`
```

and it times the same as writing the send out by hand — 0.0138 s against
0.0131 s over 200,000 iterations. **The array literal is sugar over a message**,
and there is no `dictionary:of`, so a dictionary literal would be sugar over a
message that does not exist yet.

#### The message, and the case for it is the one the asker gave

A dictionary is **already** allowed as an argument:

```
show := { d | d:at("mode"):display }.
d := dictionary:new.
d:atPut("mode", "already works as an argument today").
show:value(d).                  ; already works as an argument today
```

What it cannot be is *built* as one. Three statements and a name, for a value
used once, is why every options bag in this tree is an array of alternating
names instead — which the reference calls, in as many words, *the options bag
this language can spell, since there is an array literal and no dictionary
literal*.

`dictionary:of("mode", 'quiet)` is one primitive, symmetric with `array:of`, and
needs no grammar at all. What it has to settle is small and none of it is new:
an odd argument count is an error; a key must satisfy `sol_dict_key_ok`, so a
value and never an object, because two objects that look alike would be two
keys; a repeated key takes the last value, as a repeated `atPut` does; and
`dictionary:of` with no arguments is an empty dictionary, as `array:of` is an
empty array.

**The 255-argument ceiling — 127 pairs — does not bind, and marks who this is
for.** The largest tables here are 53, 33, 26, 20 and 19 entries, and every one
of them maps a name to a **block**: the parsers and emitters in
[sola.sol](../programs/sola.sol), the builtins, the key tables in
[edit.sol](../programs/edit.sol). None wants `of`. Fifty-three arguments spread
over fifty-three lines reads worse than fifty-three `atPut` statements, each of
which is self-contained, greppable, and already where a reader would look. The
customer is the **small inline bag** — two to eight arguments, at a call site,
where the alternative is a temporary — and the eight escapes in
[json.sol](../lib/json.sol).

**Both built on 2026-08-30**, the message first and the literal after it, which
is the order the measurement asked for. `#["key" = value]` compiles to a global
load of `dictionary` and a send of `of`, held byte-for-byte against the
written-out form by a test — the same bargain `[...]` strikes with `array:of`.

**Bracket, not brace, and `=` did not have to be freed.** `[ ]` in this language
already says *a collection written out* and `{ }` says *code*, so the brace that
most languages use for a table is the one bracket here that means something
else. And `#[` is one token, the `[` following the `#` as a digit must, which is
what makes it unambiguous: a digit was the only thing that could ever follow a
`#`, so `#[` was a lexical error in every file written before it. The `=` cost
one flag on the compiler, saved and restored around the key so that
`#[#["a" = #1] = "x"]` nests; inside a region it is still equality and outside
one it is still a stray operator.

**It shipped with no caller, which is worth saying rather than hiding.** Every
`dictionary:new` in the tree is an accumulator filled a key at a time or a named
table of blocks, and neither is the inline shape; the only use is the
demonstration in [dictionaries.sol](../examples/dictionaries.sol). This was built
because it is what a literal would compile to and because it was asked for — not
because a program asked, which is the usual bar on this page and is not met here.
The honest test of whether it earns itself is whether the next options bag
written reaches for it.

#### Converting `run` and `capture` to take one — scoped, and refused

**The obvious first customer, measured on 2026-08-30 and it does not survive
the measurement.** These are the only options bags in the tree, four of them:

| today | as a dictionary | |
| --- | --- | --- |
| `["stderr", 'discard]` | `dictionary:of("stderr", 'discard)` | +13 |
| `["stdout", 'discard, "stderr", 'discard]` | `dictionary:of(…)` | +13 |
| `["stdin", typed, "stdout", 'discard, "stderr", 'discard]` | `dictionary:of(…)` | +13 |

**Every call site gets thirteen characters longer and nothing else changes** —
thirteen being exactly `dictionary:of` against `[` and `]`. The array is winning
because it has a literal and the dictionary does not, which is precisely what
[the reference](REFERENCE.md#where-the-childs-streams-go) said when it called the
array *the options bag this language can spell*. `dictionary:of` did not answer
that complaint. Only a literal would.

**And the conversion would lose an error.** The array form is checked harder
than a dictionary can be, because a dictionary has already thrown away what
`capture` wants to complain about:

```text
system:capture(cmd, ["stderr", 'merge, "stderr", 'discard]).
solvm: 'capture' is given "stderr" twice
```

A dictionary dedupes on the way in, so the same mistake would arrive as a single
setting and be obeyed. Of the five ways to get an options bag wrong — an odd
count, an unknown name, a name that is not a string, an unknown manner, and a
repeated name — the last one is **only** catchable because the argument is a
list. That is the general point and it is worth keeping: **an argument bag is not
a degenerate dictionary.** Deduplication is a feature of a dictionary and a
defect in an argument list, where saying the same thing twice means the writer
believed something untrue.

**The one argument for it is symmetry, and it is not enough.** `capture`
*answers* a dictionary — `at("output")`, `at("status")` — and takes an array, so
the two ends do not match. But they are not doing the same job: the input is a
list of settings to be checked, and the answer is a bag of results to be looked
up in. Each is shaped for its half.

**Verdict: no.** The array stays. What this scoping produced is the best
argument yet for the deferred literal, and it is a measured one: every options
bag in the language pays thirteen characters to become a dictionary, and a
literal is exactly what would give them back.

**Asked again once the literal existed, the same day**, because this paragraph
said it should be. The literal closes almost all of the gap:

| today | as a literal | |
| --- | --- | --- |
| `["stderr", 'discard]` | `#["stderr" = 'discard]` | +2 |
| `["stdout", 'discard, "stderr", 'discard]` | `#["stdout" = 'discard, "stderr" = 'discard]` | +3 |
| `["stdin", typed, "stdout", 'discard, "stderr", 'discard]` | `#["stdin" = typed, …]` | +4 |

Thirteen characters became two to four, and the pairing that a reader had to
count is now written down. **So the brevity objection is gone and the answer is
still no**, on the one ground that never depended on spelling: a dictionary
dedupes on the way in, so `'capture' is given "stderr" twice` — a mistake caught
today — would arrive as a single setting and be obeyed. **An argument bag is not
a degenerate dictionary.** That objection is now the whole of the case rather
than half of it, which is a better place for it to sit.

**And it sharpens what `dictionary:of` is for**, which needed sharpening after it
shipped with no caller: not argument bags, which want checking and ordering, but
values that want *looking up* — built where they are used rather than three
statements earlier.

**And the temporary root came out again, which is the part that taught
something.** The first draft rooted the new dictionary on the reasoning that
`sol_dict_put` grows its entries and growth allocates. Growth does allocate and
*cannot collect* — object.c says so where it does it, *calloc and free rather
than a heap allocation, so nothing can be collected in the middle of the
rebuild*. Removing the root and running 200 dictionaries and a 120-pair one
under `SOLUM_GC_STRESS` found no difference because there was none to find. A
guard against a hazard that is not there is worse than no guard: it tells the
next reader the hazard exists.

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
| an export boundary | **done** — `exports` draws one; from outside an object is its export list |
| declared dependencies | **absent, and not wanted** — see below |

**`system:load` keeps that first row true**, which took a second pass to get
right. It shipped without a once-only memory — a message that silently declined
to do its work looked like the stranger thing — and that was wrong for the
reason the row already gives: once-only is not a nicety, it is what lets two
files each load what they need without arranging between themselves who loads
what. The memory is now the machine's, keyed by realpath exactly as `@include`
keys its own, and the second load answers false rather than doing nothing
silently.

So the score is unchanged, and the trigger above is sharpened rather than moved.
A library arriving from outside was already the moment a flat space stops
working; a library arriving already compiled, from someone who never saw your
names, is that moment with less warning. The two absent rows are still absent,
and they are the ones a namespace would answer.

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

**The export boundary is built**, and this paragraph used to say why it could
not be. It said privacy needed something the language has not got, since slots
cannot be removed and `slots` lists everything, so it would be a new concept
rather than a use of existing ones.

Half of that was right. It *is* a new concept — a slot now carries a bit saying
whether anything outside the object may reach it, which is a thing the object
model did not have. What was wrong was the implied conclusion that a new concept
is too expensive. It is one message, `exports`, and one rule: from outside, an
object that has drawn a boundary is its export list, and a name off the list can
be neither sent nor bound. Nothing was removed and `slots` still lists
everything — to the object itself. From outside it lists what is exported, which
is the same answer to a different question.

`json:digits := "abc"` from outside is now refused, and drawing the line on
`json` immediately found something: `quote` and `keyText` had to be exported too,
because `string:asJson` is a method on *string* that calls back into `json`, so
its sends arrive from outside. They were public in fact before they were public
on purpose, and nothing had ever said so.

**Two triggers, either of which is enough:**

- Somebody other than the author writes a Solum library.
- One program needs two libraries that clash on a name. Today the answer is
  "rename one", which works right up until you do not own one of them.

#### Declared dependencies: the row that should stay empty

The other three rows each closed on a failure somebody could hit — a file run
twice, two libraries claiming one name, a private slot overwritten from outside.
This one has no such failure behind it, and the case against it is worth writing
down rather than leaving as an omission.

**`@include "json.sol".` is a declared dependency.** It stands alone as a
statement, it comes at the top, it names exactly what the file needs, and the
compiler acts on it. What a module system adds is not the declaration but the
*separation* of declaring from fetching — which earns its place when the thing
has to be found among alternatives, resolved against a version, or fetched from
somewhere. None of those exists here. A file is beside you or on the search
path, and there is one of it.

**The mechanical jobs are already done by the two rows above it.** Ordering and
cycles are what dependency graphs are usually computed for, and both mechanisms
settle them without anyone declaring anything: `@include` is once-only keyed by
realpath and says a cycle "ends on purpose", and `system:load` now does the same
at run time. Two files may each ask for what they need without arranging between
themselves who asks — which is the outcome a dependency declaration is meant to
buy, arrived at without one.

**It would be a fourth mechanism where three already reach.** That is the
objection this document used against
[`@ifdef`](#more--directives-define-ifdef-once), and it applied to the namespace
row too, where an object holding slots turned out to be a namespace already.

**The one real gap, recorded so the trigger is legible.** A `.sob` does not say
what it needs. `@include` is gone by the time a program runs — it leaves no
trace in the bytecode, deliberately — and `system:load` is a message, so a
compiled file's requirements are not visible without running it. Today that
costs nothing, because a `.sob` either finds what it wants in the globals or
fails on the send that wanted it. It would start costing something if anybody
wanted to ship compiled Solum and know before running it what else must be
loaded first, and in what order.

**So the trigger is packaging**, and it is a different trigger from the two
above. Those turned on somebody else writing a library. This one turns on
somebody else *distributing* one as bytecode — and until that happens, a
declaration would be a form to fill in with information nothing reads.

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

> **That paragraph was written from reading and is wrong in both halves.** It
> was measured on 2026-08-28 and the truth is narrower, worse, and fixed by one
> linker flag rather than by changing how the project ships —
> [below](#gtk-and-the-afternoon-that-was-supposed-to-be-a-page).

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

#### GTK, and the afternoon that was supposed to be a page

**Asked on 2026-08-28, and it fires the trigger.** A window cannot be written in
Solum, which is the test this entry sets. But the question came with a
constraint the entry above had not considered, and the constraint is the more
interesting half:

> *I don't want it permanent in the core of solvm but something that can be
> linked in as an API — because I'd also like SDL2, or other graphics libraries,
> and they can't all co-exist in the core. Embedding creates another problem: if
> I later want a large-number-math library together with GTK, I have to create a
> host for every combination.*

**That argument is correct and it is the one that settles the mechanism.** The
entry above treated embedding and loading as two routes to the same place. They
are not, and the difference is arithmetic. A host is a *binary*, so *n*
capabilities is 2<sup>n</sup> binaries and every new library re-multiplies the
ones already there. A bundle is a *file*, so *n* capabilities is *n* files and
the combination is chosen when the program runs rather than when it is compiled.
Nothing else here needed a combinatorial argument, which is why it had not come
up: this is the first want that is a *set* of wants.

So: **`dlopen`, not embedding.** That much is decided by the question.

**Then the entry's own instruction was followed** — *write one throwaway
extension, build it, load it, and find out what the path actually wants; an
afternoon of that would settle more than another page of this.* It was an
afternoon, and it settled five things, three of which this page had guessed
wrong. Measured on macOS/arm64 against 0.35.0, with GTK4 from Homebrew.

**One. The loader is smaller than the paragraph describing it.** Seventy lines
of host — `dlopen`, `dlsym("sol_extension_init")`, call it with the VM and an
ABI number before `sol_vm_run` — and forty lines of bundle, which is a working
`hash:fnv1a("hello")`. No VM change of any kind.

**Two. The build blocker above is wrong, and the real one is quieter.** It is
not true that nothing is exported: `dyld_info -exports bin/solvm` lists **100**
`sol_*` symbols today. A Mach-O executable exports its global symbols without
being asked, and adding `-Wl,-export_dynamic` to the probe host changed the
count not at all — 118 either way.

What actually fails is that **a symbol is exported only if the executable
already referenced it**, because a linker takes objects out of an archive on
demand and leaves the rest. `bin/solvm` exports `sol_object_new`,
`sol_object_define_primitive`, `sol_vm_runtime_error` and `sol_vm_call_block`,
because `builtins.c` uses all four. It does **not** export `sol_vm_set_global`
or `sol_vm_global_text`, because those live in `embed.c` and no front end calls
them. The first load of the probe died on exactly that:

```
dlopen: symbol not found in flat namespace '_sol_vm_set_global'
```

**Which is worse than a blocker, because a blocker is visible.** The surface an
extension may link against is not a decision anybody took. It is a side effect
of which objects the front end happened to pull out of the archive, it differs
between `solvm` and `solis` and `solid`, and it would change silently on the day
a front end stops calling something. An `extend.h` promising a surface that is
determined this way is promising nothing.

The fix is one flag rather than a change to how the project ships:
`-Wl,-force_load,build/libsol.a` on macOS, `-Wl,--whole-archive` on Linux — and
on Linux `-rdynamic` as well, because ELF executables really do export nothing
by default and Mach-O's generosity is the outlier here. Exports went 118 to 139,
and the probe ran. *The Linux half is reasoned, not measured: the probe ran on
macOS only.*

**Three. A foreign main loop calling back into the VM needs nothing built.**
`gtk:every(#5, { ... })` handed a Solum block to `g_timeout_add`, and `gtk:run`
called `g_main_loop_run`. Five ticks, the loop quit when the block answered
`false`, `gtk:run` returned, and the statement after it ran. `sol_vm_call_block`
re-enters from a GLib callback exactly as it does from `array:do`. An error
raised inside a callback set `had_error` and formatted a trace that named the
frame beneath it — `[tick.sol:9] in script`, which is the `gtk:run` line. This
was the half expected to be hard. It is free.

**Four. And that is what makes the collector the problem, in the worst form it
could take.** A block held as GTK's `gpointer user_data` lives in a C struct.
`mark_roots` walks the value stack, the frames, the eight temporaries and the
class objects, and that struct is none of them. The same program with
`gc_stress` on:

```
#1
probe: callback failed: 'block' takes 1 argument, got 0
```

Tick one ran. The collection between ticks swept the block. Tick two called
whatever now occupied that cell — the inner `{ x | x:asString }` from the same
script — and **the failure is an arity complaint about a block the program never
registered anywhere.** Not a crash, not a null, not anything that points at the
collector. Four lines putting the block into an array hung on the extension's
own global — somewhere `mark_roots` already walks — and the same binary under
the same stress runs all five ticks and prints `"done"`.

**This is the finding the afternoon was for.** The foreign cell designed above
is for what an extension hands *out*, and the whole discussion of it is about
release. It says nothing about what an extension holds *onto*, which is a
separate requirement with a separate mechanism, and which a database connection
would never have revealed — SQLite does not call you back. **A callback registry
is not an optimisation of the foreign cell; it is the other half**, and its
failure mode is silent misdispatch, which is the kind of bug that costs a week.

**Five. Two bundles into one machine, which was the question underneath the
question.** `./host hash.so gtk.so both.sol`: GTK's main loop calling a Solum
block that calls the other bundle's primitive. Independent `dlopen`s, any
number, any order, no arrangement between them. The combinatorial problem is not
mitigated by this design — it does not arise in it.

GTK4 also comes up from inside a loaded bundle: `gtk_init_check` succeeds and
widgets build. The toolkit half was never in doubt and is now not in question.

##### And a third platform, which changes one decision

**Added on 2026-08-28, and parked the same day.** Solveig is to be ported to an
operating system being written from scratch. That OS will have neither GTK nor
SDL, and will probably have a Plan 9 `draw`-style interface instead.

> **Parked, deliberately, within the hour.** The port waits until that system is
> ready, and it will have `dlopen` by then — so designing for its absence now
> would be paying for a problem that has been promised not to arrive. The
> trigger for taking this back up is the port actually starting; the reason it
> is written down anyway is that **two of its conclusions were kept, on grounds
> that have nothing to do with the port**, and a later reader should be able to
> tell which. They are marked below. Everything else here is future work with a
> named trigger rather than a decision anybody is acting on.

Three things follow, and the first one is not about graphics at all.

**The risk is not the toolkit. It is that a from-scratch OS has no dynamic
linker.** `dlopen` is not a small thing to be owed — it is image loading,
relocation, and symbol resolution — and a young system runs static binaries for
a long time before it has one. A mechanism that *is* `dlopen` cannot be ported;
it can only be replaced.

**So the contract and the loader must be two things, and `extend.h` must not
mention `dlopen`.** One registration contract, two ways to reach it:

```c
/* extend.h -- no operating system anywhere in it */
#define SOL_EXTENSION_ABI 1
typedef int (*SolExtensionInit)(SolVM *vm, int abi);

/* An extension linked into this binary. Needs nothing from the platform. */
bool sol_extension_register(SolVM *vm, SolExtensionInit init,
                            const char *name, char **error);
```

with `sol_extension_load(vm, path, &error)` — the `dlopen` half — alone in
`solum/src/extend_dl.c`, **a file a port does not compile**. `--extension=NAME`
resolves against the statically registered table first and the filesystem
second, so a build with no dynamic linker answers the same flag, and the `.sol`
file is unchanged either way.

**Kept — and not for the port.** This is what makes the thing testable now: The plan's test for step 0 was going to have to build a shared
object *during* the test run, which is fragile on any CI and impossible on some.
A statically registered extension compiled into `tests/test_extension.c` needs no
compiler at test time and runs everywhere. The port requirement and the test
requirement want the same design, which is usually the sign of a right one.

**Second: `draw` inverts control back, and the easier way.** GTK and SDL own the
loop and call into the VM, which is what makes
[the rooting problem](#gtk-and-the-afternoon-that-was-supposed-to-be-a-page)
unavoidable there. Plan 9 does not: `/dev/mouse` and `/dev/kbd` are read, so the
*program* owns its loop and an event is an ordinary blocking primitive —

```
{ running } whileTrue({
    ev := draw:nextEvent.
    ... }).
```

— with no block held by foreign code and nothing for the collector to lose. So
**the callback registry must be a service an extension may use, not the shape an
extension has to take.** Designed the other way, the `draw` backend would spend
its life pretending to be GTK.

**Kept, and also not for the port — SDL2 is already the second back end, on the
same machine. The one that is expensive to reverse: do not let GTK's vocabulary
become the language's.** If the first bundle publishes `window`, `widget` and
`signal`, that wording reaches the examples and the tutorial, and every later
backend has to emulate a toolkit it has nothing to do with. Each backend should
publish **its own global in its own idiom** — `sdl`, `draw` — and any portable
layer over them should be written **in Solum, on top**, where it costs a `.sol`
file and can be rewritten per platform. A common C abstraction underneath would
be the same mistake as one host per combination, made in a place that is harder
to get back out of.

**And the reframing the measurement produced.** The core is already ISO C:
`vm.c`, `gc.c`, `object.c`, `bytecode.c`, `serialize.c`, `value.c`, `embed.c`
and the whole of Solas include nothing but `<string.h>`, `<stdio.h>`,
`<stdlib.h>` and their kin. **The entire platform surface is two files** —
`builtins.c` (`fork`, `execvp`, `waitpid`, `pipe`, `dup2`, `dirent`, `stat`,
`termios`) and `stdin.c` (`poll`, `termios`).

Which means extensions are not only how a window gets *in*. They are how the
POSIX half gets *out*. `system:run` has no `fork` to call on a system that has
no `fork`, and today that is a compile error in the core rather than a capability
somebody declined to load. **Nothing here proposes moving it** — but the contract
must be good enough that it *could* move, which means an extension's primitive
has to be indistinguishable from a built-in in registration, in speed, and in
what it may rely on. It already is. The point is to keep it that way rather than
to let extensions become a second class with a smaller surface.

**What this does not change.** The verdict, the ordering, the foreign cell, and
the argument against a message or an `@link` directive all stand. `draw` gives
file descriptors and image ids exactly as SDL gives textures and the socket demo
gives a bare `int`, so it is a third customer for `SolForeign` rather than a
reason to reconsider it. What changes is one decision: **`dlopen` is a back end
of the loader, not the loader**, and the static path is a first-class front door
rather than a fallback.

##### What is left, and which parts are decisions

| | |
| --- | --- |
| **The link change** | `-force_load` / `--whole-archive` + `-rdynamic`. Not a decision — the alternative is a surface nobody chose. Costs nothing to anyone who never loads a bundle, and **applies only to a build that compiles the `dlopen` back end**: a static port needs none of it, because nothing is being resolved at run time. |
| **Two doors, one contract** | `sol_extension_register` for an extension linked in, `sol_extension_load` for one `dlopen`ed, and `extend.h` mentioning only the first. The dynamic half lives alone in a file a port omits. Not a decision either, once the port is a goal — and it is what makes the whole thing testable without building a shared object mid-test. |
| **`extend.h`** | The three the entry above already names, plus a fourth found here: **an extension must check `had_error` after every `sol_vm_call_block`.** A limit-stop sets it, and a main loop that does not look will keep calling into a machine that has been stopped. |
| **The ABI handshake** | Still nothing to compare. Copy `.sob`'s policy exactly — equality, refuse, do not guess. |
| **`SolForeign`** | **Built on 2026-08-28.** As designed above, and the entry's best argument held: release runs from `free_cell`, which both the sweep and `sol_gc_free_all` go through, so a stopped program's sockets are closed too. Two things the design did not have — a `kind` checked with `strcmp`, so one extension's handle cannot reach another's primitive, and a `footprint`, without which `--memory` would measure the pointer rather than the texture. And one thing only real sockets could have found: **bytes are the wrong currency for a scarce resource**, so foreign cells carry a collection pressure of their own. |
| **A callback registry** | **Built on 2026-08-28.** New, from finding four; nothing above anticipated it. A token rather than a value, because the point is that a released one *says so* where a stale value answers a plausible wrong block — the same silent misdispatch, one layer up. Still a **service an extension may use** and not the shape an extension takes: a `draw` back end owns its own loop and needs none of it. |
| **Where loading is invoked from** | **A decision, and the one to take deliberately.** |

**On that last one, the recommendation is a flag on the binary** —
`solvm --extension=gtk.so program.sol` — and not a message, and emphatically not
a directive.

A message (`system:extension("gtk")`) puts the decision to load native code
inside the script, which is [6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
run backwards: *a mechanism a script can invoke is not a mechanism a host can
withhold*, and this is the largest possible thing to be unable to withhold. An
`@link` directive is worse again, because it would put `dlopen` in **Solas** —
the compiler would load native code to compile a file, and a `.sob` would carry
the requirement into every machine that ever ran it. The flag keeps the choice
where 6.32 established that this kind of choice belongs: with whoever starts the
program, settable from C before the run, with argv as one front end over it
rather than the thing itself.

**And the front-page sentence survives, if extensions stay out of the default
build.** *No dependencies beyond a C11 compiler and `make`* stops being true the
moment CI needs GTK to build the tree. It does not stop being true if a bundle
lives in its own directory, outside `make all`, outside the default matrix, and
built by whoever wants it. The four binaries still build wherever `cc` does.
That is the shape to insist on — and it means **GTK does not go in this
repository**, which is a smaller sacrifice than it sounds, because the whole
point of the mechanism is that it does not need to.

**One thing to know before starting rather than after.** GTK must own the main
thread on macOS. That costs nothing today, since a VM is one thread's and
[3.11](ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads) already says so
— but it forecloses ever running a UI on a second thread, and it is easier to
accept that now than to discover it.

> **The first three steps were built on 2026-08-28**, within hours of this being
> written: the link change, `extend.h`, `sol_extension_load` and
> `sol_extension_register`, the ABI handshake, `--extension=` on `solvm`,
> `solis` and `solid` — every front end that *runs* a program, and pointedly not
> Solas — [docs/extensions.md](extensions.md),
> [tests/test_extension.c](../tests/test_extension.c) and a real bundle in
> [tests/ext_probe.c](../tests/ext_probe.c). One thing written below turned out
> to be wrong in the building and is corrected there: the test that checks the
> link cannot live in the test binary, because a binary that calls
> `sol_vm_set_global` itself finds it exported however the link was done. **The
> two steps that remain are the ones with the real surface area.**
>
> **And then the foreign cell**, the same day: `SolForeign` with its release
> hook, `foreign` bound as a class object, `tests/test_foreign.c`, and
> `design.md`'s *"nothing has to be released"* rewritten rather than left
> standing. The design above survived contact except in one place, and that
> place was found by opening real sockets rather than by reasoning: **the byte
> threshold is the wrong currency for a scarce resource.** A foreign cell is
> forty bytes however scarce the thing it holds, so a program opening
> descriptors in a loop died at a 256-descriptor ceiling with no collection
> having happened. Foreign cells now have a pressure count of their own. Nothing
> on this page anticipated that, and nothing would have: it is not visible until
> the resource is real.
>
> **And the callback registry**, which was the smallest of the four and turned
> up one bug of its own on the way: a slot's `next_free` meant both *in use* and
> *end of the free list*, so releasing into an empty list marked the slot live
> again. Two states in one field, caught by the test that looked least likely to
> fail. The probe that started all of this has been rewritten onto it and its
> `#ifdef PROBE_ROOTED` is gone.
>
> **And GTK itself**, in its own repository, which is where this entry's whole
> cost argument lands: *no dependencies beyond a C11 compiler and `make`* is
> still true, and still checked on three platforms, because the toolkit is not
> here. Fourteen messages, a widget as a foreign handle, every callback held
> through the registry — and the two things nobody could settle by reasoning
> both hold. A GTK signal handler re-enters `sol_vm_call_block` exactly as
> `array:do` does, and `g_object_ref_sink` makes widget lifetimes and the
> collector agree rather than compete.
>
> **The four steps are done and the entry is closed.** What it asked for on
> 2026-08-25 — *somebody wants a capability that cannot be written in Solum and
> is not worth putting in the VM* — was asked on 2026-08-28 and answered the
> same day, in the order this page set, with the throwaway first.

**Recommended order, each step falsifiable before the next:** the link change
with `extend.h` and the handshake and the flag, tested by the *hash* bundle and
nothing graphical; then `SolForeign` with its finalizer; then the callback
registry; then GTK, out of tree, as the first bundle that was worth it. SDL2
after that changes nothing about any of the four, which is the whole claim.

**The port is parked and the order is unchanged.** Two small things survive it
on their own merits: step one keeps the `register`/`load` split, because its test
wants a statically registered extension rather than a shared object built
mid-test, and no back end gets to name itself the general case, because SDL2 is
already the second one. Neither costs anything. Everything else about the third
platform waits for the port to start.

### Graphics in SolaBasic, through the SDL2 extension

**Asked on 2026-08-30, and the premise needs correcting before the answer is
any use.** The question was put as *we stopped SolaBasic at the point of not
supporting graphics because we didn't have the foundation for it* — but nothing
in this repository ever said that. [SOLABASIC.md](SOLABASIC.md#never--the-pc)
puts `SCREEN`, `PSET`, `LINE`, `CIRCLE`, `PAINT`, `PALETTE` and `GET`/`PUT`
under **Never — the PC**, alongside `PEEK`, `POKE` and `CALL INTERRUPT`, and the
[*Not yet*](SOLABASIC.md#not-yet) table beside it — the one that does hold
deferred work, each with a trigger — has never mentioned graphics. Stage 7 was
the last stage and it is done. **SolaBasic did not stop at graphics; it finished
without them, on purpose.**

That matters because it changes what is being asked. This is not resuming a
parked stage. It is reversing the single claim the document is built on:

> Everything QBasic has that CB80 also had is language. Everything QBasic adds
> beyond it is either the PC or convenience, and neither is here.

Graphics is the flagship example of *the PC*. There is no reading of that
sentence under which `SCREEN 13` is language.

**The throwaway went first, and it answered the engineering question so
completely that only the design question is left.** Half an afternoon, no
changes to anything tracked — the five programs are parked in
[experiment/graphics-probe/](../experiment/graphics-probe/), so every number
below can be re-run rather than believed:

- [solveig-sdl](https://github.com/hansolovkarlsson/solveig-sdl) builds clean
  against 0.39.0 and draws. `SOL_EXTENSION_ABI` is still 1 and the restricted
  export surface took nothing it uses. **The foundation is not in question.**
- **An extension send costs 205ns against an ordinary send's 55ns** — 200,000
  `sdl:fill` calls in 41ms, 200,000 ordinary four-argument sends in 11ms. Cheap.
  A per-pixel graphics API through `dlopen` is affordable, which was the thing
  most likely to have killed this.
- **`sdl:present` costs 8.3ms**, because it is vsync-locked. 200 of them is
  1.66 seconds. **This, and not drawing, is the whole design problem**, and it
  is the finding no amount of reading would have produced.

The last one deserves its own line, because it is a *language* problem wearing
an implementation problem's clothes. **QBasic graphics is immediate-mode**:
`PSET` draws, and you see it. **SDL is double-buffered**, and the buffer is
shown by a call that waits for the display. A faithful `PSET` would present
after every statement, at 8.3ms each — **120 pixels per second**, so a QBasic
program drawing a circle would take a minute.

**And that is the optimistic reading.** A present does not keep the canvas, so
`PSET` after `PSET` would not accumulate a picture at all: each one would show
its own dot on a field of undefined memory. QBasic's model assumes a screen that
*stays drawn*, and a renderer of this shape has none — which means immediate
mode is not slow here, it is absent, and any `SCREEN` built on this surface
would have to buffer a whole frame and decide for itself when the frame is
finished. That is a language-visible decision, not an implementation detail.

Measured three ways, same Mandelbrot, 320×200, 400 iterations:

| | 0.38.0 | 0.39.0 |
| --- | --- | --- |
| the arithmetic alone, no graphics | 1.59s | **1.07s** |
| drawn, presenting once per row | 2.20s | 1.90s |
| drawn, presenting at most every 16ms | — | **1.29s** |

**The two drawn rows measure a call pattern and not a picture**, and that
correction arrived on 2026-08-30 when a real example was written and looked at.
Neither of them drew the Mandelbrot. `sdl:present` does not preserve what was
drawn — the buffer handed back for the next frame holds undefined memory rather
than the picture just shown, checked in C against SDL's Metal renderer — so
presenting once per row shows one row of fractal and stale video memory
everywhere else, and presenting every 16ms shows one strip of it. Both numbers
are honest measurements of what those call patterns *cost*. Neither is a
measurement of two ways of drawing the same thing, because the thing was never
drawn.

**Which sharpens the finding rather than weakening it.** The policy is not
*present less often*, it is **present only a frame that is complete** — five
presents on this program rather than a hundred and eighty. And the price of
getting it wrong is not a slow picture. It is not a picture at all.

**And the optimisations answer for themselves in the left column.** 1.59s to
1.07s is **1.49x** on a program written after they landed and chosen to be
unkind to them — a loop whose every operand is a global, which is
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)'s
exact case. It is a larger gain than any of the nine CPython pairs recorded,
and it is a fair number rather than a flattering one: nothing here was tuned,
and the program was written to draw a picture rather than to win.

#### How it would be built, and why the mechanism is already there

Nothing new is needed in the compiler's shape. `sola.sol` already has the
escape hatch this wants, and file handling already uses it: a **builtin** emits
an arbitrary send sequence, and `SOLAREADFILE$` is `emitGlobal("system")` plus
`emitSend("readFile", #1)`. Graphics is the same move against a different
global:

```text
builtins:atPut("SOLAGFILL", [['integer, 'integer, 'integer, 'integer], 'integer, 'block,
    { m, args |
        m:emitGlobal("sdl").
        m:emitGlobal("SOLAGSCREEN").
        m:builtinArg(args, #1, 'integer). ...
        m:emitSend("fill", #5) }]).
```

Above that, the runtime SUBs are written in SolaBasic like every other one —
`SOLAPSET`, `SOLACIRCLE`, the 16-colour palette table, and whatever decides a
frame is finished —
and the statement parsers and emitters are the most mechanical work in the file.
**`solas` still loads nothing**, which is the property
[extensions.md](extensions.md#who-decides) protects: the compiler only ever
emits the *name* `sdl`, and a name costs nothing to write down.

#### The counter-argument, which is not weak

**The `.sob` inherits a requirement it cannot state.** `solas` refuses to load
extensions precisely so that compiling cannot put a native dependency into the
bytecode, "where every machine that ever ran it would inherit it — including one
that only wanted to disassemble it". Emitting `sdl:` sends puts that dependency
in anyway. It arrives later and with a better error — `undefined name 'sdl'` at
the first graphics statement rather than a failure at load — but a SolaBasic
program with `SCREEN` in it is no longer a program that any Solum runs. That is
the disease the rule was written against, with a longer incubation.

**The eleven messages do not reach.** `start window clear colour fill line
present poll wait ticks` is what solveig-sdl has. `PSET` is a 1×1 `fill` and
`LINE`'s `B`/`BF` forms are `line` and `fill`, so those are free. `CIRCLE` has
no message either, and **that one has since been answered by a program rather
than left hypothetical**: solveig-sdl's `examples/circles.sol` draws a filled
disc in six lines, one `sdl:line` per row with half the width the square root of
`r² - dy²`, and the extension was deliberately *not* grown to hold it. One
customer satisfied in six lines of the language is not a trigger, and every
later back end would have had to match a circle it has no equivalent for. So
`CIRCLE` is a runtime SUB and not a message. **`PAINT` needs to read a pixel
back and there is no message that can**; and `LOCATE`/`PRINT` on a
graphics screen needs a font, which is a larger piece of SDL than everything
else here combined. So this is not *the graphics statements*. It is a subset,
and two repositories change rather than one.

**And the divergence list grows by a semantic rather than a detail.** The eight
entries in [Where this is not QBasic](SOLABASIC.md#where-this-is-not-qbasic) are
things like *no `SINGLE`* and *a file is written with line feeds* — narrow,
checkable, and none of them changes when a statement takes effect. *Drawing
appears when the runtime decides to present it* is a different kind of entry.

#### And there is no oracle for any of it

**This is the argument that decides the entry, and it did not turn up until the
rest had been written.** Every SolaBasic feature is held against a real
QuickBASIC 4.5 under DOSBox, and [oracle.sh](../programs/sola/oracle.sh) works
by comparing *printed bytes*: `agree/` must match to the byte, `differ/` must
not. **Graphics print nothing.** There is no way for that harness to check a
single pixel.

So graphics would be the first part of this language checked only against
transcripts its own author recorded — which is the exact failure the oracle
exists to prevent, and which its own header names: eighty-three claims in
`basic.sol` caught none of the seven real defects the NBS suite found, *because
those check what the author thought to check*.

The hole is the same size whether graphics go in the language or in a module.
What differs is what it costs: inside the language, *SolaBasic is verified
against a real implementation* quietly stops being true of a whole area.

#### Verdict — not built, and the reason is the trigger rule

**Asked on 2026-08-30 and closed the same day. No program wanted a screen.**

The question came with two halves — implement the graphics statements, and
exercise the extension foundation and the new optimisations. When the design
question was put back as *is there a SolaBasic program you want to write that
needs a screen?*, the answer was that it had really only ever been the second
half. **So the trigger never fired**, and the language change is not made:
`SCREEN` and the rest stay under [Never — the
PC](SOLABASIC.md#never--the-pc), that section is not amended, and the three
documents that promise *the whole of the PC is not coming* stay true.

**The exercising happened anyway, and cost no language change at all.** Every
measurement above was taken with Solum programs talking to `sdl:` directly —
which is the honest shape of the finding, since it is also the cheapest way to
get a picture on a screen out of this project. The foundation was exercised, and
the answer is that it holds: a clean build against a release it predates, an
extension send at 205ns, and one genuine surprise in `sdl:present`.

**Kept for whenever the trigger does fire.** Everything above the verdict is the
design, and it is worth more now than it would be later: the mechanism is
identified (a builtin, exactly as `SOLAREADFILE$` reaches `system`), the frame
question is settled by measurement rather than argument — a `SCREEN` here has to
buffer and decide when a frame is done, because the surface keeps nothing — and
the two things out of reach, `PAINT` needing a pixel read back and text on a
graphics screen needing a font, are named. **The recommended shape, if it is ever built, is
an opt-in `'$GRAPHICS` metacommand in QBasic's own idiom** rather than the
language growing a screen, so that the CB80 cut line survives unamended and the
`.sob`'s extension requirement is visible in the listing that produced it. That
is a recommendation held in reserve, not a plan.

**The premise correction is the part to remember**, and it is why this entry is
long for something that was not built. *We stopped at graphics because the
foundation was missing* was a memory of a decision that never happened. The
foundation was never the reason and was never asked. Writing it down here is
cheaper than having the same wrong recollection start the same afternoon again.

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

### Infix arithmetic, as a compile-time notation

`@expr(a^2 + 3 * ((a/2):sin + b:sqrt))`, lowering to exactly the sends it reads
as. **Raised on 2026-08-28 from use rather than from reasoning**: equations are
hard to write in this language and harder to check by eye.

**The difficulty is narrower than *arithmetic is unreadable*, and naming it
narrowly is what makes the answer small.** A send chain reads strictly
left-to-right and arithmetic precedence does not. A linear formula is already
fine — `x:add(y):mul(z)` *is* `(x + y) * z`, in that order. What breaks is
nesting: the outermost operation ends up in the middle of the line and an
argument runs to the end of it. With `a` = 5 and `b` = 9:

```
5.0:pow(2.0):add(3:mul(5.0:div(2.0):sin:add(9.0:sqrt))):print.  ; 35.79541643231187
```

That is `a^2 + 3*(sin(a/2) + sqrt(b))`, and the two are hard to check against
each other, which is the whole complaint.

**The counter-argument first, because it is a real one.** The existing style
already answers the general case by naming the parts: `stddev` in
[bench.sol](../programs/bench.sol) is a mean, a squared deviation and a division,
each with a name, and it reads perfectly. A notation for dense one-liners makes
it *possible* to write the density that naming avoids. So the case for this is
not everyday arithmetic — it is **transcription fidelity**: when a program
implements a standard, the dense form is the checkable form, because it is the
form printed in the standard being copied from. That is the same argument
[sola.sol](../programs/sola.sol) and [pascal.sol](../programs/pascal.sol) already
run on, and it is the argument this entry rests on. If it turns out that nothing
here transcribes a formula, the answer is *don't*.

#### Two things already on the record pull opposite ways

**For it**, [design.md](design.md) states the rule this would live under: *two
spellings of the same thing mean the same thing; where a shorthand exists it is
notation, never a second semantics*. `[#1, #2]` and `array:of(#1, #2)` produce
identical bytecode, and the compiler gets there by supplying the selector name
itself — `array_literal()` emits a global load and an `of` send, both from names
it makes up. An infix form that lowers to `add`, `sub`, `mul`, `div` and `pow`
is the second member of that family rather than a new mechanism.

**Against it**, [solum.bnf](../programs/check_syntax/solum.bnf) opens by saying
*there are no operators, no control-flow syntax and no keywords*, and offers
that as the point of the language rather than a fact about the file. And
[`ifTrue{...}`](#iftrue--a-block-argument-without-parentheses) was refused for
making a message send look like syntax exactly where the language works hardest
to prove it is not one.

**What does not apply is the refusal of
[the rest of the preprocessor](#more--directives-define-ifdef-once).** `@ifdef`
was turned down because *the text on the screen stops being the program* — a
reader has to know which switches were set before they can say what a file
means. This has no switches: it is a total, local, deterministic
transliteration, and the same characters mean the same thing on every build.
That entry ends by setting the test this one has to pass — *if a real one
appears, `@` is ready, and the case for it will be that nothing in the language
already does the job* — and the honest reading is that the language does do the
job, badly. This is a legibility argument, which is a weaker kind of argument
and has to say so.

#### Four findings from the compiler

**One: it has to be named, and `@expr(` is free.** The lexer requires a letter
after `@` and makes the whole directive a single lexeme, so `@include` is one
token and never an identifier following a symbol. `@expr` lexes today with no
change at all; `@(` does not lex and would need one.

**Two: it would be the first directive that is an expression.** `primary()`
refuses one now — *a directive must stand alone as a statement* — and the
grammar says the same in prose: `@include` is the only statement that is not an
expression, because there is nowhere inside an expression to compile a file
into. `result := @expr(...)` changes what `@` means from *a compile-time
statement* to *a compile-time thing that can also be a value*. The code change
is small and the conceptual one is not, and it is the part to argue about.

**Three: `-` is the one genuine conflict, and it is provably harmless.** A
leading `-` belongs to the *literal* today — there is no negation operator to
mistake it for, and `b := a - 3.` fails with *'-' must be followed by digits*.
So the region needs a lexical mode in which `-` is an operator, which is the
kind of thing this language avoids. What makes it acceptable is that
**it changes the meaning of no program that is currently legal**: `a - 3` and
`a-3` in expression position are both syntax errors as things stand. Inside the
region a bare `-3` reads as unary minus applied to `3`, which is the same value;
fold it at compile time and it is the same *bytes*. One character conflicts, and
the conflict is value-preserving — which is a claim a test can hold.

**Four: bare numbers are already floats, so no coercion rule has to be
invented.** `3` is a float and `#3` an integer, which means
`a^2 + 3 * (...)` reads correctly exactly as written. This was the collision
expected to sink the idea — sugar that looks like ordinary mathematics, in a
language that refuses to coerce — and it does not happen. The strictness shows
through in one place instead: `pow`, `sqrt` and the trigonometry are float-only,
so `#4^#2` is a run-time *integer does not understand 'pow'*. That is the
existing language being visible, not a new rule, and it is the right behaviour.

#### What it should be, and what it should not

**In:** `+ - * /` onto `add sub mul div`; `^` onto `pow`, right-associative and
binding tighter than unary minus so that `-2^2` is `-(2^2)`. That last call has
already been made once here — `sola:parsePower` is the only right-associative
level in SolaBasic's ladder and sits exactly there — and agreeing with it costs
nothing.

**Out, at least to begin with: prefix function calls.** `sin(a/2)` needs a rule
mapping `f(x)` to `x:f`, and the rule breaks on the second and third cases it
meets: `atan2` is class-side `float:atan2(y, x)`, and `pow` takes an argument.
A rule with exceptions is precisely what
[`ifTrue{...}`](#iftrue--a-block-argument-without-parentheses) was refused for.
Leave a *term* as an ordinary Solum expression and the difficulty disappears
along with the rule:

```text
result := @expr( a^2 + 3 * ((a/2):sin + b:sqrt) ).
```

Nothing new to learn, no second naming convention, and the stated problem is
solved. Whether `sin(x)` earns a place is a **second** decision, and the thing
that should settle it is a page of real transcribed formulas rather than the one
example that prompted this.

#### Cost, including the part that is not code

A precedence climber lands exactly on the emission the compiler already does —
compile the left operand, compile the right, emit a one-argument `OP_SEND` — and
that is byte-for-byte what `a:add(b)` produces today. Call it 150 to 200 lines
in `solas`, of which the ladder is the small half; the ladders in
[sola.sol](../programs/sola.sol) and [basic.sol](../programs/basic.sol) are 71
and 36 lines respectively, and Pascal's is 224 only because it carries a type
system through each level, which this must not.

**The tail is longer than the head.** [GRAMMAR.md](GRAMMAR.md) and
[solum.bnf](../programs/check_syntax/solum.bnf) both change and are held against
each other production by production; [check_syntax.sol](../programs/check_syntax.sol)
reserves every word-shaped literal a rule mentions; the reference, the guide and
the cheatsheet each gain a section; an example is owed. And `solum.bnf`'s
opening boast becomes *there are no operators outside `@expr`*, which is a
sentence somebody has to be willing to write.

**Trigger.** Partly fired already, from use rather than from a program — which
is a weaker report than this document usually acts on, and is why it was here
rather than in the roadmap. What would have settled it is a file in `programs/`
or `lib/` that transcribes formulas from a reference and is checked against it.

#### Built the same day, and the four findings held

`@expr(...)` is in `solas`. The estimate was 150 to 200 lines and the ladder
itself is about ninety; each of the four findings above came out as written, and
the byte-identity claim is a test rather than a hope — eighteen pairs, `@expr(
a + b )` against `a:add(b)`, compared as bytes and not as answers.

**The fold works, which was the sharpest of the four.** `@expr( -3 )` and `-3`
compile to identical files, so the region's `-` is value-preserving to the byte
and not merely to the value. It needed one token of lookahead, because `^` binds
tighter than the minus and in `-2^2` the literal is not what is being negated —
and scanning a copy of the lexer to settle a question before a byte is written
is what `inlinable_arguments` already does.

**The grammar found a fifth finding, and it is the one worth keeping.** The
first draft put the ladder inside a `math` production of its own, which is the
obvious shape and is wrong: a region is *lexical*, so an argument, an array
element, a group and a block body all read as infix within one, and a ladder
that only the region reaches cannot say that without duplicating the whole
expression grammar — eight productions, on a page whose virtue is being short.
Writing the ladder once at the top of `expression` says it in five, and
[GRAMMAR.md](GRAMMAR.md) and
[solum.bnf](../programs/check_syntax/solum.bnf) agree on 28 productions where
they agreed on 23.

**What that costs is one line in a table that already existed.** The grammar now
admits `a + 2` outside a region, which the compiler refuses — so it joins `self`
at the top level and a bad string escape in GRAMMAR.md's short list of *refused
by the compiler rather than by the grammar*. And `float` lost the leading `-` it
used to claim, since a lexical grammar has no regions to be inside of and `-3`
read as the operator applied to `3` is the same value either way.

#### And the prefix form went in the same day, on a weaker trigger than the one written down

**The trigger written above was a page of transcribed formulas. What fired was a
report from use** — the notation worked, and the question came back: should the
functions have the prefix form too? That is the same weight of evidence that
produced `@expr` itself, and it is recorded as weaker than this document usually
acts on rather than dressed up as something else.

**The proposal was to limit it to `float`, and the limit turned out to be the
expensive half.** A blessed list of names has to appear in
[solum.bnf](../programs/check_syntax/solum.bnf) as word literals, and
`check_syntax` reserves every word-shaped literal a syntactic rule mentions —
so it answers `reserved against <identifier>: cos sin`, and the language's
*there are no reserved words at all* stops being true. That claim is checked:
`test_cli` asserts the report has no such line. Scoping to the mathematical
functions would have cost a checked property of the language; the general rule
costs nothing, because `identifier` is not a word.

**And the general rule has no exceptions once it is unary.** The objection
recorded above was that `f(x)` to `x:f` breaks on `float:atan2`, which is
class-side, and on `pow`, which takes an argument. Both are *two-argument*. A
prefix form that takes exactly one has no two-argument form for them to break,
so `float:atan2(y, x)` is written out as the class-side send it is and `^`
covers `pow`. The objection dissolved rather than being worked around, which is
worth separating from the ones that were simply overruled.

So `sin(x)` is `x:sin` — **prefix application is a send to its argument** — for
any name, one argument, inside a region. The line this entry opened with is now
the line it can be written as:

```text
result := @expr( a^2 + 3 * (sin(a/2) + sqrt(b)) ).
```

**What it costs is one thing a reader has to be told**, and it is the reason to
hesitate: prefix looks like calling a function and is not calling a *block*. A
global holding one is called with `value`, so `f(3)` is `3:f`, and somebody will
write `f := { x | x:mul(x) }. @expr( f(3) )` and get *float does not understand
'f'*. It fails loudly rather than doing the other thing quietly, which is the
trade taken and not a defect that went unnoticed.

#### Comparison and logic, and the rename that came with them

**The region covers `= <> < > <= >=`, `~`, `&` and `|` as well**, decided the
same evening — and once it did, `@math` was describing the first half of its
job. It is `@expr` now. The rename cost nothing because the feature was hours
old and nothing outside this repository used it; in six months it would have
cost a deprecation, which is the whole argument for doing it at the moment the
scope changed rather than later.

**Three calls were needed and all three are visible in the grammar.**

`~` is **looser than a comparison**, so `~a = b` is `~(a = b)` — what the words
say, and what BASIC reads, its `NOT` sitting below the comparisons and above
`AND`. C binds `!` tightest and would have read the other; that is the one place
here where a C habit misleads.

**This entry used to say Pascal read it that way too, and Pascal is a
counter-example.** [pascal.bnf](../programs/check_syntax/pascal.bnf) has
`factor = ... | "not" factor`, which is the tightest level there is — so Pascal
sides with C, and the disproof of the citation had been in this repository since
the day that grammar went in. Corrected on 2026-08-29, when the question came
back from the other side: *why is `~` not tight, the way a prefix minus is?* The
verdict is unchanged and its support is one language and the words rather than
two languages, which is narrower and true.

**Comparison does not chain.** `a < b < c` would compare a boolean to `c` and
fail while running, so it is refused while compiling instead. In the grammar
that is not a check at all, it is the shape of the rule: an optional tail rather
than a repeated one.

**`|` was the one operator the language already used**, for a block's parameters
and a group's temporaries. Those are matched before a body is, so a `|` reaching
the operators is one standing where an operator may stand — `{ a | b }` is still
a block taking `a`, inside a region exactly as outside. That is a rule with a
position in it, which this language mostly refuses, and it was taken because the
position was already load-bearing and the alternative was an asymmetric `&` with
no `|` beside it. There is no third character: `||` stops at the same parameter
scanner, and `!` and `?` mean other things to every reader.

**`&` and `|` are the only operators whose right-hand side is not compiled where
it stands.** `and` and `or` take a block so that they can stop early, so the
right side goes where the block's body would have gone, behind the jump — and
the bytes are still the block form's bytes, short-circuiting included, which a
test compares.

**The grammar checker paid for itself twice in one evening.** It refused the
first draft of the operator list — *'<' is written before '<=' and would always
win, the longer one has to come first* — which is an ordering bug the
hand-written lexer never had, because it peeks. And the suite found that
`a := #1 & #2.` had been a fixture for *both* the compiler and the grammar
refusing a file; `&` is an operator now, so the grammar admits it and only the
compiler refuses, which is the third row of that table and now has an assertion
of its own.

### `@expr{...}`, a region that is a block rather than a group

**Asked on 2026-08-29, the day after the notation shipped.** `@expr(...)` takes
a `(`, and this language already teaches that `(a group)` runs now while
`{a block}` is code held as a value — [the guide has a page on
it](GUIDE.md#group-and-block). So a reader who knows that pair will predict
`@expr{...}`, a block whose body reads infix, and will not find it: `@expr{ a +
#1 }` answers *expected '(' after '@expr'* pointing at the brace. The question
is whether the prediction should come true.

#### It is already sayable, twice, and one of the two is not widely known

The region covers nested constructs, which was decided when the notation was
built and is what makes `f:value(-3)` mean what it looks like. That has a
consequence nobody wrote down: **a whole loop fits in one region, condition
block and body block together.**

```
j := #0. total := #0.
@expr( { j < #5 }:whileTrue({ j := j + #1. total := total + j }) ).
total:print.                                  ; #15

k := #0.
{ @expr( k < #3 ) }:whileTrue({ k := @expr( k + #1 ) }).
k:print.                                      ; #3
```

The first wraps the statement and converts the body as well as the condition.
The second pushes the marker inside each block and converts one expression per
marker. Both work today, and `@expr{...}` would be a third spelling of the same
bytes.

#### Three programs reached for the same one, and it was not the outer wrap

Every use of `@expr` in this repository outside
[examples/operators.sol](../examples/operators.sol) is inside a block with the
marker pushed inward:

| | |
| --- | --- |
| [tick.sol](../experiment/extension-probe/tick.sol) | `n := @expr(n + #1).` in a timer callback |
| [game.sol](../experiment/extension-probe/game.sol) | `frame := @expr(frame + #1).` in a frame loop |
| [both.sol](../experiment/extension-probe/both.sol) | `gtk:every(#5, { n := @expr(n + #1). ... })` |

Three programs, written the day the notation landed, for reasons that had
nothing to do with it. The outer wrap was available to all three and taken by
none. **That is the trigger rule satisfied without anyone setting out to satisfy
it** — not a document arguing for a feature, but the only three programs that
have used the notation landing on the same shape.

#### The argument that is not taste: a region is not inert

`-` is the one character whose meaning the mode changes. Outside a region a
leading `-` belongs to the literal; inside one it is always the operator, which
is the whole reason `infix` exists in the lexer. So **the width of a region has
semantic reach**, and the outer wrap buys its convenience by widening: `@expr(
gtk:every(#5, {...}) )` swallows the receiver and the other argument in order to
reach the block.

`@expr{...}` makes the region exactly the block, which is the narrowest true
scope for what is being asked. A notation whose extent can be stated precisely
is worth more than one that has to be widened to reach, and this is the same
argument the region itself was built on — a lexical mode that says where it
begins and ends.

#### What it would cost

Small, with one wrinkle that is worth naming because it is where the subtle bugs
in a lexical mode live.

| | |
| --- | --- |
| **The mode's edges** | `math_directive` sets the mode before consuming `(` and clears it before `)`, so the tokens either side are scanned by the rules of where they are. A block's `}` is consumed inside `block_body`, so that discipline needs a flag threaded through it — two call sites. This is the only part that is not mechanical. |
| **The directive** | A `{` branch beside the `(` one. `@expr{` is a clean error today, so nothing that compiles now can contain one. |
| **The bytes** | None. `@expr{...}` emits exactly what `{ @expr(...) }` emits, so *notation, never a second semantics* holds without a new rule. |
| **Parameters** | Free. `@expr( xs:collect({ x | x * 2 }) )` already answers `[2, 4, 6]`, so a block in a region already keeps its parameters and `@expr{ x | x * 2 }` inherits that. |
| **The tail** | One alternative in [GRAMMAR.md](GRAMMAR.md) and [solum.bnf](../programs/check_syntax/solum.bnf), the reference table, the guide, the cheatsheet, the example, and `tests/test_expr.c`. |

#### The alternative that costs a sentence

It is possible the outer wrap is **undocumented rather than rejected**. Nothing
in the reference or the guide says a region covers a nested block body, and the
three programs above may have pushed the marker inward because nobody knew the
other form existed rather than because it reads worse.

If that is the whole of it, the fix is a line in the guide and a converted
example, not a notation. **The way to tell them apart is to rewrite those three
call sites both ways and read them**, which costs ten minutes and is the same
method the extension entry used: build the throwaway before trusting the
argument.

**Recommendation: build it, and try the sentence first.** The sentence is
cheaper and might be enough, but it cannot fix the scope argument — the outer
wrap will still be a region wider than the thing it is marking, and the
narrowest form of what a program wants to say will still be unsayable. If the
rewrite makes the outer wrap read well, this becomes documentation and the
entry closes; if it does not, the case is already made three times over in
`experiment/`.

#### Built on 2026-08-29, and the sentence lost

The rewrite was done first, as the recommendation said, and `tick.sol`'s loop
settled it: the outer wrap makes a reader hold an open region across the send
and its argument list, closes on `) )`, and puts `gtk:every` and `#5` inside a
mode neither needs. So the notation, and it is `@expr{...}` — the block form
answering the block, the group form answering what its expression comes to.

**The entry named the hard part and it was not the hard part.** Handing the mode
back at the closing brace took what this predicted — one value threaded through
`block_body`, which is now *the mode that should hold once the block is closed*
and is the mode already in force for every block but this one. That was fifteen
minutes.

**What it missed was the inlining**, which is the whole reason the notation is
free. `{ ... }:whileTrue({ ... })` written literally compiles to jumps, and the
probes that decide so compared against `TOK_LBRACE` — so the first working
version of `@expr{...}` parsed, ran, and quietly emitted a real send with two
blocks in it. Twenty-nine bytes against fifty, a frame per pass, and every test
of what it *answered* passing.

It was caught by the one test that compares bytes rather than answers, which is
in the suite because the notation's claim is *the bytes are the chain's bytes*
and a claim about bytes has to be checked in bytes. **A notation that stops
inlining is a second semantics**, whatever it answers.

The fix is two probe helpers that read a block in either spelling, and the part
worth keeping is why they set the probe's mode: scanning `@expr{ x - 1 }` under
the file's mode gives *'-' must be followed by digits*, an error token, which
reads as *not inlinable* — so the region would have cost the jumps exactly where
its body used the operator that makes a region necessary. The mode is put back
after each block, so a plain block beside one in an argument list is read by its
own rules.

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

#### It was built, and as a compiler — so this prediction was wrong before it started

**2026-08-27, written before the first line.** The decision was to compile Pascal
to `.sob` rather than to interpret it, the way
[sola.sol](../programs/sola.sol) does SolaBasic, and that **takes away the value
this entry predicted**. A tree-walker spends three to six host frames per
interpreted call; a compiled call is one `OP_SEND` and one frame. So Pascal
recursion would reach something like 250 levels rather than 40, and 3.5 is met
*less* squarely than an interpreter would have met it. The entry's own reasoning
still holds — it is the shape that changed, not the argument.

**Measured when the compiler was finished: 254.** Which is the machine's plain
recursion limit exactly, so a compiled Pascal call costs **one frame and not a
byte more** — there is no wrapper, no trampoline and no bookkeeping frame
between a Pascal call and an `OP_SEND`. The guess of "something like 250" was
close by luck rather than by reasoning, and the exact number is the more useful
fact: it says the compiler adds nothing, which is not what a guess can say.

Recorded rather than quietly dropped, because a prediction that is falsified by
a decision is still a prediction that paid: it is the reason anybody looked at
the frame cost before choosing the shape.

**Two better predictions take its place, and both are falsifiable.**

**Both were settled on 2026-08-27, and both held.** Stage 4 of the compiler is
nested procedures, and it needed nothing added to the machine: a nested
procedure is a block made inside its parent's activation, `OP_OUTER depth slot`
is the static link, and the blocks it produces are the first in this repository
to set the capture flag. Nothing a conforming Pascal program can write reaches
3.1, which was the falsifiable half. The predictions are left below as they were
written.

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

**Phoenix — a second language whose output Solum *uses*.** Proposed on
2026-08-28, alongside
[the infix notation above](#infix-arithmetic-as-a-compile-time-notation), and
the two arrived together for the same reason: equations are awkward to write
here. **The equation motivation is the wrong reason for this one**, and saying
so is most of what this entry is for. A language whose distinguishing feature is
infix arithmetic is a few thousand lines answering a question that a notation
answers in two hundred — and then there are two languages to keep true, two
grammars and two references, with the warning the self-hosting entry already
recorded: *two compilers rot; every language change becomes two changes and the
second is easy to forget.*

**The machinery, though, is not in doubt, and that is worth stating precisely
because it is the part that usually kills an idea like this.** Three compilers
here already target `.sob`: [sola.sol](../programs/sola.sol) at 4,778 lines,
[pascal.sol](../programs/pascal.sol) at 2,840 — **eight stages in a single
day** — and [experiment/](../experiment/), a Solum compiler in Solum at 1,619
lines that compiles itself to a fixpoint. [lib/sob.sol](../lib/sob.sol) writes a
whole `.sob` from a plain dictionary, so the file-format half costs **nothing**;
`experiment/compile.sol` is a 70-line command-line shell to copy; and a
precedence ladder is forty to seventy lines. A small typed imperative language
is on the order of 2,800 lines and a few focused days. *(For the record, since
it is easy to get backwards:
[basic.sol](../programs/basic.sol) is an interpreter. The BASIC that emits
bytecode is [sola.sol](../programs/sola.sol).)*

**So the question is not whether another language can be written. It is the
half of the proposal that has no precedent here at all: could its output be a
*library* rather than a program?** Every hosted language in this repository
produces a closed program. Neither `sola.sol` nor `pascal.sol` emits an
`exports` call; both end their chunk with `HALT`, so a `system:load` of one
would run it and halt the loader; Pascal's globals are deliberately prefixed
`pas.` so that they *cannot* collide with the machine's, which is the opposite
of an interface. The mechanisms are all present — nested method chunks,
capturing blocks, `system:load` keyed by realpath, `exports` inherited by
whatever an object makes — and **not one of them has ever been pointed at a
chunk a different front end produced.**

**The prediction, written before anything is built, so that *it found nothing*
stays available.** `.sob` is a language-neutral object format, and a second
language can publish an object Solum sends messages to with nothing added to the
machine — the same shape Pascal's stage 4 prediction had, and it held. **The way
to falsify it is one thing a hosted compiler cannot emit that a Solum library
can.** The two candidates worth watching are the `HALT` at the end of a
top-level chunk, which is a real difference between *a program* and *a file you
load*, and whatever it turns out an `exports` list has to be built out of at the
point where a foreign compiler wants to write one.

**And it would put a second customer on two entries that have only ever had
one.** [3.4](ROADMAP.md#34-no-compatibility-across-sob-versions) — no
compatibility across `.sob` versions — currently costs one compiler a version
bump; it would cost two, and the second is the one that finds out whether the
number is checked anywhere it matters.
[3.8](ROADMAP.md#38-a-host-and-a-script-agree-a-name-and-nothing-checks-that-they-do)
is a host and a script agreeing a name with nothing checking, and a cross-language
`exports` boundary is that entry with the stakes raised: the two sides are now
written in different languages, so the shared name is not even the same kind of
identifier at each end.

**What it should not be.** A dialect of Solum with infix and classes. Solum is
already object-oriented, `system:load` and `exports` are already three of a
module system's four jobs, and the fourth is
[refused in writing](#namespaces-for-included-files). A second language earns
its place by being a *different* language — a different type discipline, a
different notion of what a program is — or by answering the interop question
above. Being a nicer skin on this one is the case that has to be refused.

**Trigger:** wanting a library that Solum consumes and that is not written in
Solum. Nothing has wanted one. The name, should it happen, is Phoenix.

**Fuzzy logic.** A library, and worth an honest note rather than a place in the
queue: it is arithmetic on floats, and all of the arithmetic landed with
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done). It would teach
nothing about the language. Build it if the thing itself is wanted; not to find
something.

#### Two absences noticed on 2026-08-31 that nothing has asked for

Both were seen while building the range and `tail`, and neither is a roadmap
entry, because nothing wanted either and could not have it. They are here so the
observation survives and so the trigger is written down rather than re-derived.

**A positioned write.** `system:readFile(path, from, count)` was built this
morning and there is no `writeFile(path, from, text)` beside it: a write either
replaces the file or goes on the end. The asymmetry is not obviously wrong —
reading part of a file is how you work on one too large to hold, and *writing*
part of one is a different and rarer thing — but it is an asymmetry that arrived
today rather than one that was decided.

**Trigger: `sort`,** or anything else that writes runs to temporary files and
merges them. An external merge sort is the shape that wants it, and it is on the
survey below as the finding `sort` is predicted to produce. A second would be a
program updating a record in place in a file it cannot hold.

**Whether standard input is a terminal.** [tail.sol](../programs/tail.sol) wanted
to know, because its no-argument case means two things — the house rule says
*demonstrate on input you carry* and `... | tail` says *read standard input* —
and no other program has had that collide.

**It found an exact answer rather than a workaround**, which is why this is a
note and not an entry: `system:keyWaiting(0.0)` answers *is there a byte right
now*, and it is documented as **true at the end of input**, so a pipe says true
whether it is full or finished and an idle terminal says false. That property is
a nuisance in every other program and is precisely the question here. Verified
through a pseudo-terminal both ways.

**That paragraph is wrong and is kept because of how.** It enumerates three
cases, each correct, and reads as though they are all the cases. There is a
fourth — **a pipe that is open, empty and not yet finished** — which answers
false exactly as an idle terminal does, because *no byte right now* is true of
both. Both programs printed their demonstration and threw away the input of any
pipeline slow to produce its first byte, and it went unnoticed because a
pipeline in a test has its first byte ready before the program starts. Found on
2026-08-31 while *building* the replacement, by asking what the old spelling had
been answering. **An enumeration is a proof only if it is complete**, and the
way to check one is to ask what states the thing actually has: a pipe has four,
and the fourth has neither data nor an end.

So the case for an `isatty` is not that the question cannot be answered — it is
that the answer arrives through a message about *reading*, and a reader coming
to that line has to be told why it works. **Trigger: a second program wanting
it**, or a first one wanting it about standard *output*, which `keyWaiting`
cannot answer at all and which is the more common thing to want — whether to
colour output, or to draw a progress line.

**The trigger fired the same day it was written**, which is why this paragraph
is here rather than the note being edited.
[sha256sum.sol](../programs/sha256sum.sol) hit the identical collision — the
house rule says demonstrate on input you carry, `... | sha256sum` says read
standard input, and both are an empty command line — and it was built the same
day as
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done),
`system:isTerminal('input)`.

**And writing that entry found the output half was answerable too.**
`system:terminalSize` calls `ioctl` on standard *output* and answers nil when
that fails, so `terminalSize:notNil` is `isatty(1)` today. The note above
predicted `keyWaiting` "cannot answer at all" about output and was right about
`keyWaiting` and wrong about the machine: a second accident was already there,
in a message written for something else. Checked through a pseudo-terminal both
ways rather than read out of the source.

#### Which Unix tool next, and what each would press on — surveyed 2026-08-31

**Written after sed and tail**, and the survey is here rather than in the roadmap
because [ROADMAP.md](ROADMAP.md)'s admission rule is that an entry means *a
program wanted something and could not have it*. None of these has been written,
so none of them has wanted anything. What follows is a prediction apiece.

**The tools written so far are all parsers or filters over text**, and three axes
have never been touched: pure arithmetic, an algorithm over two inputs at once,
and array-heavy work. That is the shape of the list rather than any tool's
popularity.

**And the oracle is why these are worth more than a library would be.** It is not
a text-tool trick that runs out on leaving text: `sha256sum` has published
vectors, `diff` has `diff`, `gzip` has `gzip`, a matrix multiply has numpy, a
Prolog has swipl. **What the frontier directions lose is exactly the oracle** — a
neural net has no byte-for-byte answer to be held to — which is the argument for
spending the cheap oracles on the questions those directions depend on, while
they are still cheap.

##### `sha256sum` — the first program here with no I/O in its inner loop

Sixty-four rounds of shifts, masks and additions per sixty-four bytes, and
nothing else. Every other program here spends its time in `split`, `indexOf` or a
syscall.

**It presses on a refusal rather than a gap.** The [At a glance](#at-a-glance)
table says **No** to integer sizes — byte, word, long — on the grounds that they
reintroduce the coercion this language refuses. SHA-256 is defined on mod-2³²
arithmetic, so it is the first thing to want them. It is *writable* without them:
a 64-bit integer holds the sum of two 32-bit values without the overflow trap
firing, and a `bitAnd` puts it back in range. So the prediction is **not**
impossibility.

**Predicted finding: the number.** Megabytes a second, hashing a file. That is
the cheapest possible answer to the question standing behind every numeric
ambition on this page — *what does this interpreter cost per arithmetic operation
when there is nothing else going on* — and it is a measurement no amount of
reading the dispatch loop will produce. Second, an ergonomic report on whether a
mask after every add reads as arithmetic or as bookkeeping.

Oracle: `/usr/bin/shasum` and the published test vectors, which are two
independent checks rather than one. Perhaps two hundred lines.

##### It was written on 2026-08-31, and the prediction held in both halves

**Kept above the outcome rather than rewritten**, which is what this section
does with predictions. [programs/sha256sum.sol](../programs/sha256sum.sol) has
the full account; what belongs here is whether the entry above was right.

**The prediction was *not impossibility*, and that held.** A 64-bit integer
holds the sum of five 32-bit values with fifty-nine bits to spare, so every
addition is exact and the mask is a narrowing rather than a repair. Nothing in
SHA-256 comes near
[3.12](ROADMAP.md#312-no-shift-can-produce-a-negative-integer): the largest
shift in the program moves a value under 2^32 left by thirty places, which
lands under 2^62. **That is luck rather than design** — SHA-512 rotates a
64-bit word and could not be written this way at all — and it is the answer to
whether `byte`, `word` and `long` are wanted. They are not. Twenty-three masks
is what refusing them costs one program, against a coercion rule on every
arithmetic operation in the language.

**The prediction was *the number*, and here it is.** Measured rather than
counted, with `--steps=N`, which stops a program after N instructions: the
smallest N that lets a run finish is that run's exact instruction count, and a
binary search finds it.

| bytes hashed | instructions | blocks | per block |
| ---: | ---: | ---: | ---: |
| 0 | 14,671 | 1 | |
| 64 | 28,049 | 2 | 13,378 |
| 640 | 147,767 | 11 | 13,302 |
| 6,400 | 1,344,947 | 101 | 13,302 |

**13,302 instructions per 64-byte block — 208 per byte — and a megabyte takes
9.30 s at `-O2` for ten of them.** So the interpreter runs **234 million
bytecode instructions a second and each one costs 4.3 nanoseconds**, which is
the first absolute
figure this project has for what an instruction costs. Everything in
[performance.md](performance.md) is a ratio against CPython or against an
earlier Solveig.

In megabytes: **1.08 a second**, against `/sbin/sha256sum` at about 1800 and
Perl's `shasum -a 256` at about 320, each measured on 200 MB. The first is C plus the M2's SHA
instructions and is not a fair comparison; the second is the interesting one,
because it is an interpreter too and is about three hundred times faster for not interpreting
the hash.

**The ergonomic half, which the entry asked for in one sentence: it reads as
bookkeeping.** Not because the mask is hard but because it is not in the
standard — every line a reader wants to check against FIPS 180-4 carries a term
FIPS 180-4 does not have.

**And three things the entry did not predict.**

- **A third of the program was a method call.** On a megabyte, `rotr` written
  as a method takes 1.36 s, written out in the rounds 1.10, written out in the
  schedule too 0.92 — **1.48x**. The arithmetic is identical in all three and so
  is the digest; what the method cost was a frame and a return, ten times a
  round. Worth holding against
  [the inline cache entry](#an-inline-cache-at-the-send-site), which measured
  *lookup* at 9.7% of the benchmark that asked for it. This is the call itself.
- **`@expr` has no bit operators**, so the one file here that is nothing but
  shifts, xors and masks is the one file that cannot use the notation at all.
  `&` and `|` are already taken, by the short-circuiting logical pair. Not an
  argument for adding them — one program is one program — but a notation
  introduced for "a formula you are transcribing" met a formula it could not.
- **The `-g` default build costs 4.9x here**, against the 1.9x to 4.1x the nine
  benchmarks show, which is what a program that is nothing but arithmetic
  inside the dispatch loop should be expected to do.

**It fired one trigger on this page**: the
[isatty note](#two-absences-noticed-on-2026-08-31-that-nothing-has-asked-for)
got its second program, and is now
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done).

**It did not fire [the early exit](#an-early-exit-from-a-loop), and a draft of
this paragraph said it did** — which is worth keeping, because the mistake is
one an entry can invite. `sha256sum` carries a flag through four `ifTrue`s to
decide whether a line is a checksum line, so it *looks* like the sixth file's
idiom. It is not: that entry is about
[3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing), a loop
that must stop from inside, and there is no loop here — it is a straight-line
guard chain wanting a *return*, which is
[3.2](ROADMAP.md#32-no-non-local-return). One spelling, two limitations, and
counting the second as an instance of the first would have made the case look
stronger than it is. **The entry had already stopped counting files** for
exactly that reason, having watched the number go stale twice.

Where 3.2 did turn up is worth its own line: **in the parsing, not the
hashing**. Every loop in the block function runs a fixed number of times and
none wants out early, which is what a specified algorithm looks like — so
`tail`'s prediction that 3.1 and 3.2 would not appear was right about the file
work and the gap is where it has always been.

##### `diff` — the first program here that computes rather than recognises

Everything written so far reads one input and reports on its structure. `diff`
holds two and computes a relationship between them.

**Predicted findings**, in the order they are expected to bite:
[3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels), because the
divide-and-conquer form of Myers recurses on the halves of the edit graph and a
large file has many; a two-dimensional array, which nothing here has needed and
which is an array of arrays with a send per index; and memory at scale, where the
classic table is quadratic and the linear-space refinement is the interesting
half of the algorithm rather than an optimisation.

**It is also the first tool whose *output format* is hard.** Unified diff hunk
headers, context, and the rules for coalescing nearby changes are fiddly in a way
`tail`'s were not, so the corpus would earn its keep before the algorithm did.

Oracle: `/usr/bin/diff`. Around four hundred lines.

##### `gzip -d` — the one that answers the question behind the neural net

Inflate only; compression is a second program and a harder one. A 32 KB sliding
window, a bit-level reader over a byte-level input, and two Huffman tables
rebuilt per block.

**This is the array-heavy workload with a definitive oracle**, which is what
makes it worth more than a tensor experiment. A `SolValue` is a tag and a union,
so a 32 KB window is 32,768 tagged values rather than 32,768 bytes, and every
access is a send. **Predicted finding: the cost of that, in a number**, on a
problem where the right answer is known to the byte. If packed numeric arrays are
ever going to be needed — and
[extensions](#extensions-a-capability-from-a-binary-rather-than-from-the-vm)
is the likely shape rather than a new core type — this is the cheapest place to
find out, and the only one on this page that cannot be argued with afterwards.

Oracle: `gzip`, on files `gzip` produced. The largest of the three.

##### Three that would press on less, and one that cannot be written at all

**`sort`.** `array:sorted(block)` at scale, and its stability, which nothing has
had to care about. **Its real finding is predicted to be a gap we already know
about and nothing has wanted**: an external merge sort writes runs to temporary
files and merges them, and there is no positioned write — `writeFile` replaces
and `appendFile` appends. That is the mirror of the ranged read built this
morning, and `sort` would be its first customer. Oracle: `sort` under `LC_ALL=C`,
since collation is otherwise a divergence about locales rather than about the
program.

**`unzip -l`.** A foreign binary format, which nothing has read — `sob.sol`
reads one this repository wrote. The central directory is at the **end** of the
file and is found by scanning backwards from it, which is the ranged read's
textbook case, and every field is a little-endian integer that has to be
assembled from bytes by hand. Small, and it would say whether byte-level
unpacking wants a message of its own.

**`xargs -P`.** **Unwritable today, and that is the whole finding.**
`system:run` blocks and there is no spawn, so nothing can have two children at
once — and [3.11](ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads) is
about threads rather than about processes, so the gap is not even the one the
roadmap records. Worth writing down here precisely because attempting it would
produce a page rather than a program.

**And the ones worth skipping**: `grep`, `cut`, `tr`, `uniq`, `wc`, `head`. Each
is the ground [sed.sol](../programs/sed.sol) already covered, through the same
code paths, and the rule this page runs on is that a program that cannot report
anything is not worth writing. `grep` is the least bad of them, and only if the
point is to force a decision about `pattern.sol`'s missing half — groups,
alternation and case folding, which its own header says want a different engine.

##### The counter-argument, which is on the page already

[design.md](design.md#what-the-language-is-for) records that *there is no
geometry anywhere near this language* was "a true sentence about seventeen
programs and an empty one about a language", and nearly lost the language its
trigonometry. **Every text tool added makes that sentence truer and more
misleading at once.** `sha256sum` and `gzip -d` are on this list partly because
they are not text tools wearing the same clothes: they are numeric experiments
that happen to have a Unix name and an oracle.


#### `tail`, and the file this language cannot read — scoped 2026-08-31

**Chosen out of the Unix tools because it is the one where reading a file whole
stops being a cost and becomes a wall.** [sed](../programs/sed.sol) priced the
whole-file route on 2026-08-30 — about 4.7 times the file for a line-oriented
program, against a flat 2.5 MB for the same work through a pipe — and closed by
saying [3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done)'s trigger had
still not fired, because nothing here has a file that does not fit.

**That is no longer true, and it took four seconds to stop being true.** A
sparse file is 3 GB of holes and 8 KB of disk, and this is what the two sides
say about one:

```text
/usr/bin/tail -n 3   0.003 s, and the right three lines
system:fileSize      #3221225623, immediately
system:readFile      '...' is too large to read into a string
```

**The language can measure that file and cannot read a byte of it.** Not slowly:
`readFile` checks the size before allocating and refuses by name, which is the
entry's own documented behaviour working exactly as written. This is measured
rather than predicted — it is a fact about `readFile` and needs no `tail` to
establish it. What `tail` adds is a program with an obvious reason to care, and
a shape to ask for.

##### The order in this entry was wrong, and the measurement above is why

**Corrected the same day it was written, on the question *what was tail for?***
The entry below recommended writing `tail` on the whole-file read first, and
deciding the language change afterwards, on the reasoning that a program asks
and a page does not. That is the rule, and it is not what happened here: **the
evidence arrived before the program did.** Four seconds, a sparse file, and no
`tail` anywhere.

The original recommendation is kept in the calls below rather than replaced,
because a recommendation quietly rewritten teaches nobody why it was made.

**What was wrong with it is sharper than being unnecessary.** A `tail` written
on the whole-file read **cannot call the thing it is supposed to be asking
about**. It would re-prove a wall already measured and say nothing whatever
about whether `readFile(path, from, count)` is the right shape, because it could
not use it. So the program that was meant to inform the design is the one
program guaranteed not to.

**The question splits in two, and only one half still wants a program.**

- **Whether** — settled by the measurement above. A file the language can
  measure and cannot read is as clear as evidence gets, and 3.22 already names
  the shape: no handle, no lifetime, nothing to close.
- **What shape** — not settled, and a caller is what settles it. Which means the
  caller has to come *after* the call exists.

**So: build the ranged read first, and write `tail` against it as the check.**
Then `tail` does the job it is actually good for — first caller, and the report
on whether the shape survives contact — instead of re-proving what is proved.
This is [method.md](method.md)'s *throwaway before the design* with the order
put right: fifty lines that use the new call are worth more than two hundred
that cannot.

**And building it is small.** `prim_system_read_file` already opens the file,
`fseek`s to `SEEK_END` and `ftell`s to size it. The ranged form is that function
taking one argument or three — primitives answer at two arities, as `at(key)`
and `at(key, default)` do — with `fseek` to `from - 1` in place of the `rewind`
and an `fread` of `count`.

**One line already in that function decides call 3 below.** It reads:

> *A short read is a failure rather than a shorter string: `fopen` on a
> directory succeeds on some systems, and reading one does not.*

Right for a whole-file read and **wrong for a ranged one**: asking for 4 KB
from a hundred bytes before the end is an ordinary thing to do, and a hundred
bytes is the correct answer rather than an error. So *clamp or refuse* is not a
matter of taste — the policy that is there cannot carry over, and whichever
replaces it needs writing down beside that comment saying why the two reads
differ.

**The subset.** `-n N` and `-n +N`, `-c N` and `-c +N`, several files with their
`==> name <==` headings, `-q` and `-v`, standard input when no file is named,
and a default of ten lines. Left out: `-r`, `-F`, and `--pid`, which are BSD or
GNU rather than the tool. Expected size 150 to 200 lines, or 200 to 250 with
`-f` — about a third of sed, because there is no script to parse.

**Predicted finding, the one it is for.** `tail` is the first program here that
**cannot be written correctly at all**, rather than written awkwardly or
expensively. Above 2 GB it must refuse a file that `/usr/bin/tail` answers in
three milliseconds, and no amount of care in the program changes that. If
3.22's ranged `readFile(path, from, count)` is ever built, this is its first
customer and the first thing able to say what shape it actually wants — which
is what the entry has been missing, since a proposal argued on a page cannot
report that its own arguments are in the wrong order.

**Predicted finding, second: `-f` has nothing to wait on.** There is no
`system:sleep`. The only thing in this language that waits is
`system:keyWaiting(seconds)`, which waits on *standard input* and is documented
as answering **true at the end of input** — so a follow loop built on it spins
at a hundred percent the moment standard input is closed, which is how `tail -f`
is ordinarily run. **The predicted resolution is not the absence but the
price**: `-f` gets written with `shell:run("sleep 1")`, a fork per poll, and the
finding is what that costs. That is exactly how the terminal's size went — the
number was always reachable through `stty` at 7 ms an ask, and
[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done) was
raised on the price rather than on the absence.

##### Both halves were tested on 2026-08-31, and the second was wrong

**Kept above the outcome rather than rewritten**, which is what this section
does with predictions.

**The first half held.** `keyWaiting` cannot stand in for a wait, and the numbers
say why — twenty asks of `keyWaiting(0.5)`:

| standard input is | twenty asks take |
| --- | --- |
| an idle terminal | 10.02 s — it genuinely waits |
| a pipe at its end | 56 microseconds — it spins |
| a pipe with something in it | 32 microseconds — it spins |

**The second half was wrong, and it was wrong in its analogy.** The prediction
was that `shell:run("sleep 1")` would work and *the price would be the finding*,
the way the terminal's size was reachable through `stty` at 7 ms an ask and the
price was what made [6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done)
an entry. A fork of `/bin/sleep` measured **2.23 ms**, which at a one-second poll
is **0.22%** — perfectly livable. The `stty` case was a fork *per keystroke* and
this is a fork *per second*, and the entry reasoned from one to the other without
noticing they differ by four orders of magnitude in how often they happen.

**So the case for `system:sleep` had to be made on something else**, and it was:
waiting is one call to the kernel, a program should not start a process to do it
or depend on where a system keeps its `sleep`, and of the twenty-eight messages
on `system` this was the only obvious hole — `clock` and `time` could say how
much time had passed and nothing could spend any. It was built, and `-f` with it.

**That is a weaker argument than the one predicted, and it is the true one.**
Worth more than being right for the reason expected, and the reason this
paragraph exists rather than a quiet correction.

**Predicted finding, third and weakest: following a growing file is quadratic.**
Each poll re-reads the whole file, so a minute of following a log that gains a
line a second reads it sixty times. This is a second and independent argument
for the same change, and it is the one that says the change wants *both* `from`
and `count` rather than a *read the last N bytes* convenience.

**What it is predicted *not* to find**, so that *it found nothing* stays an
available answer for most of the file:

- **`-c` is bytes, and so is a Solum string** — NUL included, which the reference
  states of `readLine` and `readFile` both. Byte-exact output is expected to work
  without comment. If it does not, that is news about strings rather than about
  `tail`.
- **No lookahead problem.** sed needed a line of it for `$`; `tail` knows where
  the end is by construction, and the reader it wants is simpler.
- **3.1 and 3.2 are not expected to appear.** There is no early exit worth the
  name and no closure to outlive anything.
- **The missing final newline will come up again** and is expected to teach
  nothing new: sed already found that `readLine` cannot report it, and the same
  three-case treatment should carry over unchanged.

**The oracle corpus**, in the shape [sed's](../programs/oracle.sh) already
has, since it generalises for the cost of a different `args:` line: default ten;
fewer, more and exactly N lines; `-n 0`; `-n +N`; `-c N`; `-c +N`; an empty
file; no trailing newline; one line; several files and their headings; `-q`;
`-v`; standard input; NUL bytes. Around twenty cases, each run both by name and
by pipe.

#### The calls only you can make

1. **Order. This entry recommended one thing and now recommends the opposite**,
   and both are here on purpose.

   *As first written:* write `tail` on the whole-file read first, then decide
   the language change — because that is how the evidence is produced and it is
   what sed did.

   *Corrected:* **build the ranged `readFile` first and write `tail` against
   it.** The evidence was already in hand before the program was proposed, and a
   `tail` on the whole-file read cannot call the thing it is meant to be asking
   about. The section above has the reasoning.

   What is left for you is not really the order any more but the **appetite**:
   this makes the next piece of work a change to the machine rather than a
   program, which is a different kind of afternoon and wants saying out loud.
2. **`-f`, or not.** ~~It presses hardest on the missing wait, and it is the one
   part an oracle cannot check the ordinary way: it does not terminate, so it
   needs a timeout harness that the other twenty cases do not.~~ **Built on
   2026-08-31**, and the timeout harness turned out to be fifteen lines of shell
   in [tail/follow.sh](../programs/tail/follow.sh) rather than a reason to leave
   it out — *give it a deadline* is the whole idea. It found a real difference
   on its fourth scenario, which is more than the case for skipping it expected.
3. **If the ranged read follows**, four things 3.22 does not settle:
   - **`from` one-based**, like every other index in the language? Recommended
     yes; anything else makes it the only zero-based index here.
   - **Past the end: clamp or refuse?** The language has both conventions —
     `first(#n)` and `last(#n)` clamp, `copyFrom` refuses. **Recommended clamp**,
     and the argument is a race rather than a taste: a file's size can change
     between the `fileSize` and the read, so refusing turns an ordinary race into
     an error a caller cannot prevent.
   - **A negative `from`, meaning from the end?** Tempting for exactly this
     program. **Recommended no** — no other index here is negative, and
     `fileSize` already composes.
   - **Does a short read say so**, or must the caller compare what it got against
     what it asked for? Falls out of the clamp answer and should be decided with
     it rather than after.
4. **Does the corpus carry the 3 GB case?** It needs a sparse file and a way to
   say *this is expected to fail until the language changes*, which is the state
   argued against on 2026-08-31 for the `pattern.sol` defect: a red case in
   `agree/` that is meant to be red teaches the next reader to ignore red.
   **Recommended: a separate opt-in script**, run when somebody wants to know,
   the way `oracle.sh` and `experiment/prove.sh` are.

**Trigger:** none needed — a program needs no permission. What needs a decision
is the language change it is predicted to ask for, and that is what the four
calls above are.

### Networking, and sending code to a machine that is already running

**A socket exists now, and it is not in the VM.**
[ext_net.c](../experiment/extension-probe/ext_net.c) is 156 lines of UDP loaded
with `--extension=`: `net:udp` answers a `<socket>` foreign cell, `port` asks
the kernel which one it got, `send` writes a datagram to loopback and `poll`
takes one if it is waiting. There is no `close` — the
collector closes a socket the program has let go of, and teardown closes one it
was still holding, which is the case an explicit close could never cover. It
lives in [experiment/extension-probe](../experiment/extension-probe/README.md),
off the search path, because it was written to press on the extension mechanism
at full size rather than to give this language networking.

**It was not a demo, which is why it counts as evidence.** It was the argument
for `SolForeign`: the first version handed a descriptor back as a plain integer,
so nothing closed it when a program was stopped, it went uncounted against
`--memory`, and a program could invent one and pass it to `close`. All three
became the case for the foreign cell, made by a file that needed it rather than
by a paragraph. Opening real sockets through it is also what found that **bytes
are the wrong currency for a scarce resource** — forty-byte cells holding
descriptors exhausted the process at a 256-descriptor ceiling with the heap
still nearly empty — which is where the collector's foreign pressure count came
from.

So the sentence this entry used to open with — *there is no socket anywhere in
this repository* — is false, and the conclusion it carried goes with it. **A
client and server pair no longer means new primitives in the VM.** That was true
while the VM was the only place a capability could come from; since
[extensions](#extensions-a-capability-from-a-binary-rather-than-from-the-vm) it
is a choice, and the choice is the entry now.

**The extension argument does not settle it, because sockets are the other
shape.** `dlopen` won for GTK on a combinatorial one: two toolkits, neither
wanted by most programs, every pair of them a build, and a dependency that would
have cost *no dependencies beyond a C11 compiler and `make`*. There is one
sockets library, everyone who wants networking wants the same one, and it costs
no dependency beyond POSIX — so the reasoning that put GTK outside does not
reach it. **Recommendation: an extension all the same, when it happens.** A
socket in the VM is a capability every script gets whether or not the host meant
to grant it, which answers
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine) by
pre-empting it; a bundle a host names on the command line is that entry's
coarsest form already built. Moving it inward later is easy, and moving it back
out is not.

**What the probe dodged is the part worth naming.** Its `poll` is non-blocking
and runs from a frame loop SDL owned, so the socket never had to wait for
anything — the graphics library did the waiting. A server owns its own loop, and
*waiting* is what this machine has no answer for: a blocking read stops the only
thread there is, there is no second one
([3.11](ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads)), and
concurrency is [recommended against](#go-style-concurrency) on the grounds that
it changes the whole VM. `connect`, `bind`, `listen` and `accept` are an
afternoon. **How a program waits on one of two things is the entry**, and no
amount of extension mechanism supplies it.

**Sending code fragments to a running `solvm` is a step further, and depends on
three things rather than one.** The sockets above; then
[3.4](ROADMAP.md#34-no-compatibility-across-sob-versions), because a `.sob` is
not compatible across versions, so a service and its clients are lockstep or the
wire carries source; and then
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine), because
this is that entry's threat model stated exactly — *input from a stranger* — and
it is deferred precisely because nobody had one. Extensions shade that third
dependency without removing it: a host that does not name the bundle has no
networking at all, decided from C before the program runs, which is the shape
6.32 asked for and not the granularity it asked for.

It has a fourth dependency that is a feature rather than a decision. **A remote
object is the canonical customer for
[intercepting a message that was not understood](#intercepting-a-message-that-was-not-understood)**,
which is deferred below because nothing has wanted a proxy. Networking would
want one, and the two should be considered together if either is.

**The trigger fired on 2026-08-29**, and from the direction this entry did not
name: not two machines, but the question *can we pull the probe's socket out and
have two programs talk?* — which is the same want one step short of the wording.
[serve.sol](../programs/serve.sol) still answers HTTP through environment
variables; what is new is beside it.

#### Built: the sockets, as [extensions/net](../extensions/net/README.md)

Five messages — `udp`, `port`, `send`, `receive`, `waitFor` — and a
[client](../extensions/net/client.sol) and [server](../extensions/net/server.sol)
that hold a counter between them. **An extension and not a machine**, which is
the recommendation this entry made when it was re-read: a socket in the VM is a
capability every script gets whether or not the host meant to grant it.

**Two things the programs decided that no argument here had.**

A packet has to say *who sent it*. The probe read with `recv`, so the first pair
written against it could not answer each other — the client wrote its own port
inside the message for the server to parse out. That is a protocol invented to
work around a missing field, which is what a missing field looks like from
inside a program.

And **waiting is bounded rather than blocking**, which this entry had guessed
was the hard part and was right about for the wrong reason. It is not only that
a blocking read stops the only thread there is: it stops the *dispatch loop*,
which is where `--steps` counts and `--memory` is checked. A program parked in a
syscall inside a primitive is a program no limit can reach, so a blocking read
would quietly suspend
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done).
A timeout keeps that window a window.

What is still absent is absent for the usual reason: no TCP, no IPv6, and no
name resolution — `getaddrinfo` blocks, which is the thing above.

#### Still deferred: sending code to a machine that is already running

Untouched by any of that. It still wants
[3.4](ROADMAP.md#34-no-compatibility-across-sob-versions),
[6.32](#632-a-script-cannot-be-run-with-less-than-the-whole-machine) and a
proxy, and now that a socket exists the second of those is the one that matters:
*input from a stranger* stopped being hypothetical the moment a program could
receive a datagram. Nothing here does anything with what it receives except
compare it against three words, which is the shape to keep until 6.32 is
decided.

### An inline cache at the send site

**Where this came from.** Solveig was measured against CPython 3.14 on
2026-08-29 — nine matched programs, interleaved through
[bench.sol](../programs/bench.sol), the first time anything here had been
compared with another implementation. Level overall, and two of the nine stood
out as losses: a character scan at 2.13×, which turned out to be a defect and
is [4.4](COMPLETED.md#44-a-one-byte-string-is-allocated-per-character-read--done),
and recursion at 2.03× — eighteen million sends of one method — which is this
entry.

**The proposal.** Cache the resolved slot at each send site, so a monomorphic
call site stops walking the proto chain after the first time. It is the standard
answer, CPython has done a version of it since 3.11, and
[the JIT entry](#a-jit-to-native-code) already names it as the thing that would
have to exist first for a JIT to be worth anything.

**And the claim made for it was wrong.** It was written down as *most of the
recursion gap*, on no evidence. Measuring says lookup is **9.7%** of that
benchmark:

```text
$ sample <solvm running fib(34)>          807 samples

   run_frames                    525   65%   the dispatch loop itself
   sol_object_lookup_interned     78   9.7%  the proto-chain walk
   receiver_suits                                                    ⎫
   + sol_slot_accepts            106   13%   the per-send receiver check
   push_frame                     44   5.5%
   prim_less / sub / add          42   5.2%  the arithmetic being asked for
   sol_chunk_name                 12   1.5%
```

The second measurement agrees. Two programs identical but for how far the method
sits from the receiver — one where it is the receiver's own first slot, one five
objects up a chain with four slots to skip at each level — differ by **18%**
(391 ms against 462 ms). So the *entire* walk in a deliberately deep case is
about a sixth of the run, and `fib` is not that case: `self:of` finds its slot
immediately, every time. A cache would remove something that is already nearly
free.

**What the profile points at instead is more interesting than the proposal.**
`sol_slot_accepts` is three predictable branches — is there a primitive, does it
take any receiver, does the type match — and it costs more than the lookup does,
because it lives in `object.c` and is called from `vm.c` on every send with no
inlining across the two. That is not a design question at all.

**Which is where the build flag beat the design change.** Compiled `-O2 -flto`,
with no source change, the machine is faster on **all nine** benchmarks:

| | |
| --- | --- |
| `strloop` 1.29× · `float` 1.27× · `loop` 1.27× · `array` 1.25× | |
| `higher` 1.21× · `fib` 1.18× · `object` 1.17× · `strlib` 1.07× · `dict` 1.05× | |
| so `fib` against CPython | 2.03× → **1.61×** |

**And it silently breaks extensions, which is why this is a decision and not a
flag.** The Makefile takes some care to publish the `sol_*` surface a loaded
bundle resolves against — whole-archive linking, and the comment beside it
explains that four binaries used to export four different accidental sets.
Link-time optimisation undoes exactly that:

```text
sol_* symbols exported by bin/solvm      -O2  147      -O2 -flto  0
```

`make test` catches it — `test_an_extension_reaches_the_program` fails, having
loaded a bundle that can no longer find a single one of the functions
[extend.h](../solum/include/solum/extend.h) promises it. So LTO here is not free
speed, it is speed traded for the extension ABI, and taking it would mean
keeping those 147 deliberately — an exported-symbols list, or visibility
attributes — which is a real piece of work and a new thing to keep in step.
Worth doing before anything on this page, and worth its own entry when somebody
wants it.

**If all of that were done, an inline cache would still be worth about a
tenth**, and the shape it would take here is awkward in a way worth writing down
now. There are no hidden classes to key on. An object is a slot list and a proto
pointer, slots are added at any time — `p:x := #1` defines one — and nothing is
ever removed, so a cache needs an invalidation story that a global modification
counter would answer badly: the `object` benchmark defines two slots per pass
and would invalidate every cache in the program four million times. Keying on
the receiver's own address works well for the case that prompted this, `self:of`
sending to the same object eighteen million times, and not much beyond it. The
cheap version and the general version are different features, and the cheap one
is the one whose customer exists.

**Verdict: defer**, and not for the usual reason. This one was measured rather
than argued, and the measurement says the entry was about the wrong ten percent.

**Trigger:** a program that is actually too slow, with a profile putting
`sol_object_lookup_interned` at the top of it. Nothing here is and nothing here
does — and the two things above it in that profile are a missing `inline` and a
linker flag, neither of which is a language change.

### Where the interpreter's time actually goes — two built, two left

The entry above ended by pointing at two things above the inline cache in the
profile. Asked what else could be done, the answer was got the same way: profile
six benchmarks and a **real program** — [basic.sol](../programs/basic.sol)
interpreting 39,000 BASIC statements, which is 2,774 lines of Solveig with
objects, methods and dictionaries in it, rather than a loop somebody wrote to be
timed.

```text
$ sample <solvm running basic.sob>        ~1550 samples

   run_frames                        851   55%   the dispatch loop itself
   sol_object_lookup_interned        205   13%   name → slot
   receiver_suits + sol_slot_accepts  195   12.6% the per-send receiver check
   push_frame                         61    4%
   find_entry, memcmp, malloc        ...          the program's own work
```

Four candidates came out of it, ranked by what they were measured to be worth
against what they cost. **Two are built and are
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done);
two are still here.**

**1. The per-send receiver check, inlined — built.** `sol_slot_accepts` is three
predictable branches, and it lived in `object.c` while its only caller lived in
`vm.c`, so every send paid a call across a translation unit for them. Moving it
to a `static inline` in the header is 1.4% to 6.5% depending on how send-heavy
the program is. It takes one symbol off the export table, 147 to 146, and that
one appears in neither [extend.h](../solum/include/solum/extend.h)'s surface nor
[extensions.md](extensions.md), so nothing documented lost anything.

**2. A global is a hash lookup — built.** The measurement that found it: the
same loop written with globals and with block temporaries, which differ in
nothing else, are **1.255×** apart, and the profile agrees independently —
`sol_object_lookup_interned` falls from 218 samples to 25. Every top-level
script and every REPL line pays it. The fix is to remember the slot at the site,
and it is safe for a reason that is *this* language's rather than a general one:
a slot is malloc'd on its own and linked, and **nothing removes one**, so the
address is good for the life of the machine. ROADMAP 3.10 records that fact as a
problem; here it is a guarantee.

**3. Computed-goto dispatch — built, measured, and it is *slower*. No.** It was
the biggest thing left, at 55% of a real program, and it was the one item here
with an estimate rather than a measurement behind it. The estimate was wrong:
threading the loop with labels-as-values is **1% to 13% slower than the
`switch`**, on all nine benchmarks and on the real program. See
[below](#computed-goto-dispatch--measured-and-refused).

**4. Keeping the exported symbols under LTO — still open, and the only one
left.** `-O2 -flto` is 5–29% faster across the suite with no source change and
takes the whole extension ABI with it. It has an entry of its own now:
[the exported symbol surface](#the-exported-symbol-surface-and-the-lto-it-is-blocking),
where the finding is that the surface is worth declaring whether or not LTO ever
follows — 146 symbols are exported, 22 are declared, and 13 are used.

**What the two built ones came to**, measured against the same source without
them, all at `-O2`:

| | |
| --- | --- |
| `basic.sol` interpreting BASIC | **1.065×** |
| `loop` 1.284 · `float` 1.276 · `array` 1.237 · `strloop` 1.228 | |
| `higher` 1.126 · `object` 1.120 · `dict` 1.054 · `strlib` 1.037 | |
| `fib`, which touches no global at all | 1.003 — unmoved, and see 4.5 |

Against CPython 3.14 the suite's geometric mean went **1.02 to 0.885**, and
Solveig is now ahead on five of the nine rather than four.

**The verdict this changes is the inline cache's, and only by agreeing with
it.** Two of the four things worth doing to the dispatch loop were a missing
`inline` and a table lookup, and neither is a design question. That remains the
finding.

### The exported symbol surface, and the LTO it is blocking

**Two things, and the second is the reason the first got looked at.** They are
worth separating, because one of them is worth doing on its own and the other is
a trade.

#### What is actually exported

An extension is a separate `.so` whose calls back into the machine are left
unresolved on purpose — `-Wl,-undefined,dynamic_lookup` — and bound at `dlopen`
against the symbols `bin/solvm` exports. So **the executable's symbol table is
the ABI**, and the Makefile works to make one exist: a linker takes objects out
of an archive on demand, so `-Wl,-force_load` (and `--whole-archive` on ELF) is
what stops the four binaries exporting four different accidental sets, which is
what [they used to do](../Makefile).

That fixed the inconsistency and left the size:

| | |
| --- | --- |
| `sol_*` functions [extensions/net](../extensions/net/) actually calls | **10** |
| union of what every bundle in this repository needs | **13** |
| `sol_*` functions [extend.h](../solum/include/solum/extend.h) declares | **22** |
| `sol_*` functions `bin/solvm` exports | **146** |

**The surface is not chosen, it is whatever is not `static`.** An extension can
bind to any internal function that happens to have external linkage, and there
is no declared line between *the contract* and *the insides*. So an ordinary
refactor — marking something `static`, renaming it, changing a signature —
breaks a third-party extension silently, and nothing in the tree notices.

**That is not hypothetical, and it nearly happened here.**
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)
made `sol_slot_accepts` a `static inline`, which took it off the export table:
147 symbols to 146. It was checked by hand against `extend.h` and it was not
there, so nothing was owed. **Nothing in the build checked**, and nothing would
have said so if the answer had been the other way.

#### What LTO does to it

`-O2 -flto` is **5% to 29% faster across the benchmark suite** with no source
change at all — the largest unclaimed number this project has. It also deletes
the entire ABI, because internalising symbols nothing in the program references
is exactly what whole-program optimisation is for, and no extension is part of
the link:

```text
exported sol_* symbols      -O2  146      -O2 -flto  0
```

```text
$ solvm --extension=build/extensions/net.so probe.sob
solvm: cannot load extension build/extensions/net.so:
       dlopen(...): symbol not found in flat namespace '_sol_foreign_handle'
```

**It compiles, links, and passes everything that does not load an extension.**
`test_an_extension_reaches_the_program` is the whole of what stands between that
and a release.

#### The two halves

**Declaring the surface is worth doing whether or not LTO ever follows.** It
turns 146 accidental symbols into a decision, and it is testable: compare `nm`
against the declaration and fail the build when they disagree, which is a check
this repository has no equivalent of today. It is also the only way to find out
what the 146 minus 22 are — some of them are certainly wanted and undocumented.

**Turning LTO on is a separate call with its own costs**, and they are not
small: links get much slower, inlined frames make a profile and a debugger
harder to read, and `make` builds `-g` — so the thing developed against and the
thing shipped would diverge further than they already do. A bug that appears
only under `-O2 -flto` is a bad one to go looking for. Worth remembering too
that hand-inlining *one* function was 6.5% on a real program: selective
inlining takes part of the win with none of the cost.

**The mechanism, and the objection it has to answer.** macOS wants
`-exported_symbols_list`, ELF wants `--dynamic-list` or `-fvisibility=hidden`
with explicit `default` on the exports. Either way that is a list — and this
Makefile argues in three places that a hand-kept list goes stale. So the list
must be *generated*: a `SOL_API` marker on each intended export, and the build
writing the linker's file from those, the way `$(BUILD)/config.h` is already
written and replaced only when it changes. Then the surface is declared at the
function it belongs to and there is no second place to forget.

**The first half is built and is
[4.6](COMPLETED.md#46-the-extension-abi-is-whatever-is-not-static--done)**:
`SOL_API` on each export, `-fvisibility=hidden` on everything else, 146 exported
symbols down to 29, and both directions tested. Six were promoted on review,
three of them closing the dictionary gap [extensions.md](extensions.md) had
already written down as waiting for somebody to decide.

**The second half stays deferred**, and now on its own merits rather than
because it breaks extensions. `-flto` is 5–29% and costs slower links, inlined
frames in a profile and a debugger, and a wider gap between the `-g` build
developed against and the one shipped. **Trigger: a program that is too slow at
`-O2`.** Nothing here is, and hand-inlining one function was already 6.5% on a
real program.

## Recommended against

### Computed-goto dispatch — measured, and refused

**The textbook optimisation for a bytecode interpreter, and here it is slower.**
Replace the `switch` with a table of label addresses and end every opcode with
its own `goto *table[next]`, so that each one gets its own indirect branch and
the predictor learns which opcode tends to follow which. It is what every
account of interpreter performance recommends, and
[the JIT entry](#a-jit-to-native-code) named it as this project's cheap
alternative at "10–20%".

**Built, run, and refused on the numbers.**

| | |
| --- | --- |
| `fib` 0.89 · `float` 0.91 · `array` 0.94 · `higher` 0.94 · `strloop` 0.95 | |
| `loop` 0.97 · `object` 0.98 · `strlib` 0.98 · `dict` 0.99 | |
| **`basic.sol` interpreting BASIC** | **0.92** |

Every one below 1, which here means the `switch` is faster — by 1% to 13%, and
by 8% on the real program. The transformation is behaviour-preserving and was
checked as such: all nine benchmarks print the same answers and the whole suite
passes against it.

**The reason is that the compiler undid it**, and the disassembly says so
plainly:

```text
                        indirect branches   instructions   bytes
   switch                        2               954        3816
   computed goto                 1              1086        4344
```

**One.** Twenty-one hand-written `goto *table[...]` sites were tail-merged back
into a single dispatch point — which is the shape a `switch` already compiles
to, except now with 132 more instructions and 528 more bytes wrapped around it.
Clang merges identical tails; identical tails are exactly what this technique
consists of. So the benefit is optimised away and the cost is not, on a loop
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)
had already shown to be instruction-cache sensitive to within 8.5%.

Two things were checked before concluding, because a negative result from a bad
prototype is worth nothing. Padding the jump table to 256 entries to remove the
per-dispatch bounds test changed nothing (`fib` 0.87, `basic.sol` 0.92). And the
`switch` version already carries two indirect branches rather than one, so clang
had done a little of this duplication by itself, unasked.

**It also would have cost the C11 promise.** Labels-as-values is a GNU
extension, so this needs `&&label` behind a `__GNUC__` guard, a second copy of
the dispatch structure for compilers without it, and `-Wpedantic` silenced where
the table is declared. Paying that for a slowdown is an easy decision; it is
worth writing down that even a *speedup* would have had to be worth those three
things.

**If this is ever revisited, the technique to revisit is a different one.** The
modern answer on clang is the **tail-call interpreter** — each opcode a function
ending in a `musttail` call to the next — which gets the per-opcode indirect
branch in a form the optimiser cannot merge away, and which is what CPython 3.14
itself adopted. That is 21 functions rather than 21 labels and a much larger
change, and no program here is waiting on it. Recorded so the next person starts
from the measurement rather than from the folklore.

**Trigger:** somebody willing to write the tail-call form, with a profile
showing the dispatch loop still on top. The 55% is real; this particular way of
attacking it is not.

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
  interpreter does, in more code. [The inline cache was later
  profiled](#an-inline-cache-at-the-send-site) and is worth a tenth of the one
  benchmark that wanted it, so the first step of that bigger machine is smaller
  than it looks and buys less.
- **It fights the stated goal.** The VM is written for clarity first, and 4.1
  and 4.3 got the language 40% faster with changes that fit in a paragraph.

**The cheap alternative, if speed is ever wanted:** computed-goto dispatch
(`&&label` threading) in place of the `switch` — a contained change to one
function, and the folklore puts it at 10–20% on interpreter-bound work.

**That was written before anybody tried it, and it is wrong here.** Threading
this loop is *slower* than the `switch` on all nine benchmarks and on a real
program, because clang tail-merges the twenty-one dispatch sites back into one
and leaves the extra code size behind — see
[computed-goto dispatch](#computed-goto-dispatch--measured-and-refused). The
sentence above is kept as it was written, because being wrong in public is what
this page is for.

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

**One has since been proposed, and it is judged against that sentence rather
than around it.**
[An infix notation for arithmetic](#infix-arithmetic-as-a-compile-time-notation)
would be the second thing in the namespace and the first directive that is an
expression. It does not pass the test as written — the language *does* do the
job, since `a:add(b)` computes the sum — so it has to argue on legibility
instead, which is a weaker kind of argument. What it does not share with the
three above is the reason they were refused: it has no switches, so the text on
the screen never stops being the program.

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
