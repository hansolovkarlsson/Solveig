# Ideas considered

*Each idea from the notes, with a verdict and the reasoning behind it. The ones
worth building are in [ROADMAP.md](ROADMAP.md) section 6; the ones recommended
against are here so the reasons survive, and so the same idea does not have to
be re-argued from scratch in six months.*

Every code sample here has been run against the current build unless it is
marked as a sketch.

## At a glance

| Idea | Verdict |
| --- | --- |
| `do` is `forEach`? | **Yes** — and `collect` is map, `select` is filter |
| Bytecode / assembly reference | **Build it** — and design.md's table is missing six opcodes |
| `$character` literals, Unicode | **Defer** — gated on deciding what a string is |
| Integer sizes: byte, word, long | **No** — reintroduces the coercion the language refuses |
| Separate float and double | **No** — same reason, less benefit |
| `include` another file | **Built** — was the most valuable thing on the list |
| `System:exit(code)` | **Build it** — small and plainly needed |
| Keyboard input | **Build `readLine`**; single-key is a different job |
| File handling | **Build it**, whole-file first |
| JIT to native code | **No** — possible, and it would dwarf the project |
| More examples covering everything | **Yes** — audit which concepts have none |
| `doUntil` | **Already writable**; worth building in for the inlining |
| switch / case | **Already writable** — no new syntax needed |
| `#10:repeat({...})` | **Already writable**; cheap to build in |
| `for` loop with start/end/step | **Already writable** |
| `forIn` | **It is `do`** |
| `ifTrue{...}` without parentheses | **No** — it would teach a rule that does not generalise |
| Performance timing | **Build it** — needs a clock |
| `['red,'green,'blue]` as an enum | **Works today** — document the pattern |
| `A:with{ :m1(#1). }` cascades | **No** — chaining already covers it |
| Document `(group)` versus `{block}` | **Yes** — with your own example |
| Go-style concurrency | **No, for now** — it changes the whole VM |
| Subclass `integer`, a `byte` subclass | **Not possible** — see below |

---

## Already there, or already writable

The language has no control-flow syntax, so **most of the loop and branch ideas
are library code, not language changes.** All of these run today — and the loops
among them have since been collected into
[lib/control.sol](../lib/control.sol), which ships on the search path, so a
program has them with one line:

```
@include "control.sol".
```

`repeat`, `doUntil`, `toDo`, `toByDo` and `timesCollect` are there. `caseOf`
below is deliberately not: it is a fine demonstration that the language needs no
`switch`, and an array of two-element arrays of blocks reached into with
`pair:at(#1)` is not an interface worth committing to. A library is a promise,
and the bar is higher than "it works".

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

## Worth building

These are in [ROADMAP.md](ROADMAP.md) section 6 with the detail. In rough order
of what a real program would miss first:

**`include`** was the one that mattered, and it is built —
`@include "lib.sol".`, and
[the reference](REFERENCE.md#splitting-a-program-across-files) has the rules.
The design question was never the mechanism but the namespace, and it stayed
flat: an included file's globals are the including file's, exactly as though its
text had been written there. A module system with a namespace of its own is a
much larger change to the object model, and nothing so far has needed it.

**A `system` object** — `exit(code)` first, then arguments and a clock. Small,
and `exit` is the difference between a script and a program.

**A clock**, which is what the performance-timing idea needs. This project's own
changelog is full of measurements taken with `/usr/bin/time`; being able to take
them from inside the language would be better.

**Reading input**, starting with a whole line. `readLine` is a few lines of C and
portable. Waiting for a single key is a different job — it needs raw terminal
mode, which is platform-specific and belongs behind its own decision.

**File handling**, whole-file first: read a file into a string, write a string to
a file. That covers most of what scripts do. Binary files want a byte-array type
and should wait for a program that needs one.

**A bytecode reference.** design.md has an instruction table that is **missing
six opcodes** — `OP_JUMP`, `OP_JUMP_IF_FALSE`, `OP_EXIT_IF_FALSE`, `OP_LOOP`,
`OP_CHECK_BOOL` and `OP_SYMBOL`, which is every jump and the newest two. The
disassembler already exists and prints them; the document simply fell behind.

**More examples**, chosen by auditing which concepts have none rather than by
adding more of what is already covered.

**A `(group)` versus `{block}` document.** Your own example is the whole of it:

```
m := { x | x:add(#1) }.
(m:value(#42)):print.        ; #43      -- a group evaluates
{ m:value(#42) }:print.      ; <block>  -- a block does not
```

Both are "code in brackets"; one runs now and one is a value. That distinction
is obvious once you have it and invisible before, which is exactly what a
tutorial section is for.

---

## Deferred, with a trigger

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

### Cascades: `A:with{ :m1(#1). :m2(#45). }`

Smalltalk needs cascades because its setters answer the argument, so
`a add: 1; add: 2` is the only way to chain. **Solum already avoided that
problem**: `add` answers the array, so `b:add(#1):add(#2):add(#3)` chains
natively — the changelog records that as a deliberate choice.

So the syntax would buy a second way to do something the language already does,
at the cost of a construct where `:m1(#1)` means a send to a receiver that is
not written down. That is a large exception to "`:` sends to what is on the
left".

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
[2.5](ROADMAP.md#25-class-side-versus-instance-side).
