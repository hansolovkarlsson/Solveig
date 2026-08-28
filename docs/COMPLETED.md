# Completed roadmap items

*The case for each piece of work as it was argued before the work was done — the
problem, what the options were, and why the shape chosen was the one taken. This
is where a roadmap entry goes when it is finished, rather than being deleted.*

What actually landed, and when, is in [CHANGELOG.md](CHANGELOG.md), which names
the commit for each. What is still outstanding is in [ROADMAP.md](ROADMAP.md).
What was considered and turned down is in [ideas.md](ideas.md).

The numbers are the original ones and are never reused. The changelog cites
them, and a number that meant two things at two times would make every one of
those citations ambiguous — so the gaps in the roadmap are themselves a record
of what has gone.

Entries that were removed before this document existed are not here; their
reasoning went to the changelog at the time, and the verdicts are in
[Settled](#settled) below.

- [1. Blocking real programs](#1-blocking-real-programs) — the collector, arrays,
  strings, user-defined objects, and the three crashes that led the list
- [2. Language decisions](#2-language-decisions) — the settled table, one verdict
  per row
- [3. Known limitations](#3-known-limitations) — the one that stopped being a
  limitation
- [4. Performance](#4-performance) — inlining, operand width, dispatch
- [5. Tooling and ergonomics](#5-tooling-and-ergonomics) — the prompt, rendering,
  float text, compile errors
- [6. Beyond the language](#6-beyond-the-language) — splitting a program across
  files, the `system` object, reading input, and file handling

---

## 1. Blocking real programs

### 1.1 Garbage collection — **done**

Mark-sweep over objects, blocks, and compiled code. `SOLUM_GC_STRESS=1` collects
on every allocation; running the suite under it with ASan is what makes a missing
root a caught bug rather than a latent one.

How it works is in [design.md](design.md#garbage-collection); what changed is in
[CHANGELOG.md](CHANGELOG.md). Two results worth keeping in view, both measured
against the commit before each change:

| | Before | After |
| --- | --- | --- |
| A block literal allocated per loop iteration, 2M iterations | 98 MB, linear | 1.5 MB, flat |
| 60,000 REPL lines | 25.5 MB, linear | 1.9 MB, flat |

**1.1a the collector** and **1.1b GC-owned code** are done, and so is 1.1c,
which was still open when this entry was written:

#### 1.1c Temporary roots inside primitives — **done**

The mechanism exists and Solis uses it; no primitive allocates yet, so nothing
applies it. Arrays are what changed that -- see [1.2a](#12a-temporary-roots-finally-needed--done).

**1.1d** is not work but a standing restriction — collection is stop-the-world
and non-incremental — so it stayed behind, in
[ROADMAP.md](ROADMAP.md#11d-collection-is-stop-the-world-and-non-incremental).


### 1.2 Arrays — **done**

`SolArray` and the `array` class: `new`, `of`, `size`, `at`, `atPut`, `add`,
`do`, `collect`, `select`, `print`, `equals`, plus the `[...]` literal. Indices
are one-based, an index must be an integer, and out of bounds is an error.
Arrays are references, like objects.

Arrays come before strings deliberately, for a reason that only became clear once
the collector existed: **an array holds `SolValue`s, so the tracer gains a real
outgoing edge**. A string holds bytes and has none. Arrays therefore exercise the
collector in a way strings cannot, and they are the first thing that can hold a
reference the collector must not lose.

Reference semantics, like objects: `a := b` makes two names for one array, and
mutating through either is visible to both -- the established split, numbers are
values and objects are references, so it needed no new rule.

No `.sob` change. Arrays are mutable, so a literal is a construction rather than
a pooled constant, and `check_constants` rejects one outright.

Three details worth keeping in view:

- `add` answers the array so it chains. Smalltalk answers the added element, but
  it has cascades for that and Solum does not -- `;` is a comment here.
- `do` bounds the count once and re-reads the backing store each pass, because
  the block may grow the array underneath it and move the store.
- Printing is depth-limited. `a:add(a)` is legal, so the printer cannot assume
  the structure is finite.

#### 1.2b `[...]` literal sugar — **done**

`[#1, #2]` compiles to the bytecode for `array:of(#1, #2)` -- literally, not
merely equivalently: the two forms produce byte-identical `.sob` files, and a
test asserts it. Two lexer tokens and one compiler branch, no new opcode.

The desugaring is real rather than a lookalike, which has one visible
consequence worth knowing: the `array` it sends to is the ordinary global, so
rebinding that name moves both spellings together. They cannot drift apart,
which is the point. Capped at 255 elements by `OP_SEND`'s argument count, which
stayed one byte when the index operands widened (4.2).

#### 1.2a Temporary roots, finally needed — **done**

`sol_gc_push_temp` / `sol_gc_pop_temp` exist and Solis uses them. Arrays are what
force them into primitives, and precisely which ones is worth being exact about:

- `do` does not need them, and now that it exists this is confirmed rather than
  predicted: the array is the receiver, so it is on the stack and rooted for the
  whole call.
- `collect` and `select` do, and this turned out to be load-bearing rather than
  cautious. Removing the root and running under `SOLUM_GC_STRESS=1` with ASan
  turns the loop into a heap-use-after-free in `sol_array_add`: the result array
  is swept while it is still being filled.

`select` appends each element to the result *before* testing it, winding the
count back when the block rejects it. Otherwise the element would live only in a
C local while the block ran, and a block that replaced it in the source would
leave nothing pointing at it.

### 1.3 Strings — **done**

`SolString` and the `string` class: `print`, `size`, `equals`, `concat`, `at`.
Immutable, and therefore a *value* rather than a reference -- `equals` compares
characters, where an array compares identity. One-based `at`, answering a
one-character string since there is no character type. Strict `concat`: joining
a string to a number is an error, not a conversion.

It needed no `.sob` change after all. A literal's bytes ride in the chunk's
interned text table, alongside selectors and global names, and `OP_STRING` builds
the string from them at run time. That table was already serialised, so only the
opcode set changed. A literal whose bytes match a selector shares one entry,
harmlessly.

What is left, small and separable:

- **Escapes are done**: `\"`, `\\`, `\n`, `\t`, `\r`. An unknown escape is an
  error rather than a literal backslash. There is no `\0`, because the chunk's
  text table is NUL-terminated in memory and one would truncate the string --
  the wire format already carries lengths, so lifting that means giving the
  in-memory table lengths too.
- **Not interned.** `OP_STRING` allocates on every evaluation, so a literal in a
  loop makes a string per pass. Immutability means that is only a cost, never a
  semantic difference. Interning would fix it and give 4.3 its mechanism, but
  needs a weak table so interned strings can still die.
Ordering and conversions have since been added (2.8).

### 1.4 User-defined objects — **done**

A global `object`, whose `new` answers a fresh object delegating to the receiver.
That was the whole gap: slot assignment, proto-chain lookup, and
block-in-a-slot-is-a-method all already existed, so classes needed one primitive
rather than a mechanism.

There is no separate notion of a class. An object created from `object` can be
given slots; an object created from *that* delegates to it and finds them.
Whether a given object is a class or an instance is how it is used, not what it
is. Assigning a slot on an instance always makes the instance's own, so it
shadows the prototype rather than writing through.

Left open:

- **No `clone`.** `new` delegates rather than copying, which is cheaper and more
  useful, but there is no way to take a snapshot of an object's slots.
- **No way to remove a slot**, so a shadowing slot cannot be un-shadowed.
- **The default `print` still shows an address** (5.2). Overridable, since a
  `print` slot on the prototype is found first, but the fallback is poor and much
  more visible now that user objects exist.

---

The next two were the only urgent items in this document, and they were one bug
wearing two hats. Both are fixed.

### 1.5 `array:print` crashed the VM — **done**

```text
array:print.        ; was: segmentation fault
block:print.        ; was: segmentation fault
```

Rendering an object asks it for `asString`. On the class objects `array` and
`block`, lookup started at the object itself and found the `asString` those
classes define for their *instances*, which renders — and rendered the same
value again. `render` does carry a depth, but the count restarted at zero every
time the recursion left through `sol_value_render`, and it is C recursion, so
`SOL_FRAMES_MAX` never saw it: a primitive called from `sol_vm_send` pushes no
VM frame.

It fell out of 1.6 as predicted. The receiver check refuses `asString` to a
class object, so the cycle cannot start; there is no longer a route into
`prim_rendered_as_string` that does not hold an array or a block. Every other
route back into the renderer goes through a block a user wrote, and a block
costs a frame, so the call-depth cap bounds it as it bounds any other runaway
recursion.

One thing did have to move. A class object nested inside something being
rendered -- `[array]:print` -- would have raised 1.6's error from inside a
`print`, which is not the renderer's business. So the renderer now asks only an
object that can answer, and shows one that cannot as its address, exactly as it
already showed an object with no `asString` at all.

The depth that restarts is still wrong in principle and is now unreachable:
closing the loop needs a primitive that renders a receiver it did not check, and
there is no longer one. Left as it is rather than carrying state on the VM for a
case nothing can produce.

### 1.6 A class object answered its instances' messages — **done**

```
array:add(#1).      ; was: abort
array:size.         ; was: #0, read from whatever `array` is not
```

`array` is an object whose slots are the messages an *array* understands, and it
answers them itself. `prim_array_add` then did `SOL_AS_ARRAY(self)` on the class
object, because a primitive reached through a class had always been entitled to
assume its receiver's type. That holds for every instance and fails for the one
object that is not one.

Each primitive now records the receiver it needs, and the dispatcher checks
before entering it — one check in one place rather than 64 copies of the same
`if`, and both dispatch sites go through it, so `perform` and the renderer are
covered as well as `OP_SEND`.

```
array:add(#1).
solvm: 'add' expects an array, got object
```

The requirement is per message, not per class, because a class object is the
genuine receiver of some of them. `array:of`, `array:new`, `integer:new`,
`float:new` take any receiver, as does reflection, which reads either side. The
installation lists say which is which one message at a time:

```c
instance(vm->array_class, SOL_ARRAY, "add", prim_array_add);
any_receiver(vm->array_class, "of", prim_array_of);
```

That is 2.5 answered in the small — for each message, rather than by splitting
the two sides into separate objects, which still wants a metaclass level.

`respondsTo` asks the same question the dispatcher does, so it cannot claim a
message that sending would refuse: `array:respondsTo('add)` is false and
`array:respondsTo('of)` is true. Binding a block over a primitive clears the
requirement along with it, so a class can be given messages of its own.

Costs one comparison per primitive send: 4.0% on a loop that is nearly all
sends, 2.1% on a more ordinary one.

Found by fuzzing the loop work (4.1) and present as far back as the array
primitives. `tests/test_class_side.c` covers every built-in class, and the fuzz
sweep that found the two crashes -- 3205 corrupted variants -- now reports
nothing.

### 1.7 A temporary declared in a top-level group — **done**

`( | t | ... )` declares temporaries of the frame the group sits in. Inside a
block or a method that is a frame, and it worked. At the top level of a script
there is no frame -- the script's chunk reserves no slots -- and the compiler
emitted `OP_SET_LOCAL 0` anyway, writing over the bottom of the expression
stack.

```
#1:add(( | t | t := #5. t )):print.
```

The receiver `#1` was sitting in that slot, so `t := #5` overwrote it and the
answer was `#10` instead of `#6`. Silently: no error, just arithmetic on the
wrong number.

**Refused in the compiler**, which of the three ways out was the smallest
correct one and forecloses neither of the others:

```
[line 1] solas: a temporary needs a frame, so declare it inside a block at '|'
```

It reports at the `|`, where the mistake is, and both front ends now say the
same thing -- which they did not before. Compiled, the verifier had always
caught it, so `sol_chunk_save` refused to write the file and said `bytecode is
internally inconsistent`: true, and useless, since the problem was three tokens
of source. Solis never verifies, because it runs what it just compiled and
trusts its own compiler, so there the wrong answer simply appeared.

That trust was the larger half, and the reason this is worth more than ten lines
of parser. Solis is right to hold it -- verifying every REPL line to catch the
compiler's own bugs is the wrong shape -- but nothing was checking that it was
earned. `tests/test_compile.c` now does: every shipped example and every
accepted form in a growing list is compiled and handed to `sol_chunk_verify`,
so **whatever Solas accepts, the verifier accepts** is a property with a test
behind it rather than an assumption. Anything the compiler learns to accept
belongs in that list.

The refusal also had to recover properly. Reporting and returning left the
parser on the `|`, so recovery resumed inside the group, cleared the panic flag
at the `.` between its statements, and complained a second time about the `)`.
Every other error in this compiler produces exactly one message, and a test
asserts this one does too.

Found by auditing REFERENCE.md against the implementation, not by fuzzing: the
reference claimed declarations may open any group, and they could not.

---

## 2. Language decisions

The two entries this section still holds live are in
[ROADMAP.md](ROADMAP.md#2-language-decisions): **2.5**, class side
versus instance side, and **2.14**, the loose ends the decided items left.

### Settled

The numbers stay because the changelog cites them. Each row is the verdict; the
entry named is where the reasoning lives.

| | Question | Decided | Entry |
| --- | --- | --- | --- |
| 2.1 | Division | Floored, answering an integer. Integers trap on zero, floats answer an infinity; `quo`/`rem` stay free for the truncating pair | `9ad8039` |
| 2.2 | Statement terminator | `.` separates rather than terminates: required between two statements, optional after the last | `be13b07` |
| 2.3 | Array indexing base | One-based. An index is an ordinal, not an offset, so `at(#0)` is out of bounds and caught | `1d8c573` |
| 2.4 | Array literal syntax | `[...]`, pure sugar -- byte-identical to `array:of(...)`, with no new opcode | `63749ee` |
| 2.6 | Float exponents | `1e3`, `1E+3`, `1.5e-3`. A bare `e` is left alone; `#` is exact and takes no exponent | `c8cef1b` |
| 2.7 | Symbols | `'foo`, interned, compared by pointer. The intern table is weak | `5a15fc9` |
| 2.8 | Missing operations | Conversions, short-circuiting `and`/`or` over blocks, `notEquals` as the negation of `equals`, string ordering, `negated`/`abs`, sorting, `isNil`/`notNil` | `7ac6be6`, `246ae8e`, `113745f`, `10ddf25` |
| 2.9 | Calling the method you override | `self:via(ancestor)`, the ancestor named rather than inferred | `a5aa9e0` |
| 2.10 | Reflection | `slots`, `slotAt`, `respondsTo`, `isKindOf`, `perform`, named by symbol. Reads only | `a7310a7` |
| 2.11 | Filling a template | `{}` placeholders and `fill`, matched exactly, each value rendered by *sending* `asString` | `ca1369b`, `4a70ef0` |
| 2.12 | Formatting a single value | A spec argument to `asString`. No conversion letter, no sign mode; bases are a message, not a letter | `3524c70`, `95074c9`, `f4b909d` |
| 2.13 | Case and text | ASCII only, by explicit range rather than `toupper`. Still live, and in the roadmap's section 3 | `91d413c` |

---

## 3. Known limitations

The limitations themselves are still live and are in
[ROADMAP.md](ROADMAP.md#3-known-limitations). These were limitations until they
stopped being ones.

### 3.21 A changelog hash is written by hand and nothing checks it — **done**

The second entry here about this repository's own verification rather than about
the language, after [3.16](#316-what-the-checker-does-not-check--done), and the
same shape as the third gap that one closed: a fact stated by hand, in a place
nothing reads, that goes wrong quietly.

Every entry in [CHANGELOG.md](CHANGELOG.md) names the commit it landed in, and a
commit cannot carry its own hash — so the entry goes in saying `pending` and a
follow-up commit substitutes the real one. **The substitution failed once and
the failure survived two days**: the PRINT USING entry of 2026-08-26 carried a
literal `%s` where its hash belonged, through every `make test` in between,
because nothing asked whether a hash looked like one. It was found by a person
reading the page while cutting 0.35.0.

**The rule is what an entry's heading looks like.** A heading is

```text
### PRINT USING, measured before it was written — `078bd92`, 2026-08-26
```

and everything backticked after the **last** em dash is a commit: seven
hexadecimal characters, or the literal `pending` while the follow-up is not in
yet. `%s` is neither, and neither is anything else a substitution can leave
behind. The last em dash rather than the first, because a title may contain one
of its own; *everything* backticked rather than the first thing, because two
entries are not shaped like the rest — one names two commits joined by `and`,
and one names a commit and no date. Both are right as they are, and a
rule that read only the first token would have been a rule those two had to be
rewritten to satisfy.

**The weaker guard, deliberately.** The entry named a stronger version: ask git
whether the hash names a commit that exists, which catches a well-formed hash
that is simply wrong. That wants a repository to ask, and
[expect.sol](../programs/expect.sol) does not have one — it reads files and runs
programs, and a tarball with no `.git` in it checks clean. The weaker guard
catches the failure that actually happened and keeps that property, which is the
trade the entry had already argued for and which building it did not change.

**What it cannot see, said out loud.** A heading that loses the em dash and
everything after it is indistinguishable from a section *inside* an entry, and
five headings are genuinely that. So both numbers are reported — *how many
entries name a commit, and how many headings name none* — rather than passed
over in silence, and the second one moving is visible to whoever reads a run. A
floor in `test_cli` catches the other direction, a guard that quietly stops
finding hashes to check, exactly as the floors beside it do for claims, counts,
positions, SolaBasic blocks and grammar productions.

It also reports a `pending` still waiting, which is the state the release cut is
looking for and previously had to look for by eye.

### 3.20 Five shipped libraries published everything they had — **done**

`exports` shipped with one library using it. This closed the other five, and
four of them now say what they publish:

| library | publishes | keeps |
| --- | --- | --- |
| `scan` | the fifteen the reference documents | `src`, the text a cursor is a position in |
| `pattern` | the ten the reference documents | thirteen — one matcher taken apart |
| `sob` | `file`, `version` | eight — a byte writer and the buffer it fills |
| `html` | `read`, `complaints` | four dozen — one HTML parser taken apart |
| `html:element` | eleven | `add` and `at` were meant to be among the kept; see below |

**`shell` drew none, and that is the answer rather than an omission.** It has
four slots and all four are the API. A line listing everything hides nothing,
and a boundary that hides nothing is the decoration this document rejects
elsewhere.

**Two objects, not one, in `html`.** It binds a parser and the node prototype a
read answers, and they need separate lines — with the inner one drawn first,
since `html`'s own boundary would otherwise put `element` outside it and refuse
the very next statement.

**What drawing the lines found.**

`html:element` publishes eleven names rather than nine, for the reason
`json:quote` was published there: the parser builds the tree from *outside* an
element. `html:newElement` is a method on `html`, and a new node delegates to
`html:element` rather than to `html`, so both the position it stamps (`at`) and
the way it hangs a child on a parent (`add`) arrive from outside. They were
public in fact long before anything said so.

**And one library was reaching into another's internals.** `html` sliced a
cursor's own text — `self:cur:src:copyFrom(start, self:cur:pos:sub(#1))` —
where `scan:since(start)` says the same thing and had existed the whole time.
The two are the same slice; `since` guards `pos == start`, which the test above
it had already ruled out. Nothing had stopped it, so nothing had noticed. That
is the boundary paying for itself: not by preventing a bug, but by finding a
place where an API had been bypassed and reimplemented.

**The semantics changed to make any of it worth doing.** As shipped, a boundary
was per-object, and `scan` and `pattern` are prototypes — so hiding `scan:src`
would have hidden the prototype's default and left every actual cursor's `src`
public, which is the half that matters. Boundaries are inherited now: an object
under one *is* its export list, whether it drew the line or got it from its
prototype. That needed a second rule to stay usable — a method on a prototype
may reach into an object made from it, which is what a constructor is, and
without it every library would be forbidden from filling in what it hands out.
Only downward: reaching up into a prototype by name is still refused.

**Cost.** The assignment path settles `self:x := ...` with two comparisons
before consulting anything, that being nearly every assignment a method makes.
Against the previous build, a send-only loop differs by about 2% in one ordering
and is indistinguishable in the other, and a real program is indistinguishable —
which is to say it is at the noise floor rather than clearly below it.

### 3.19 A program cannot write to standard error — **done**

**`system:writeError(text)` is the answer**, landed the day after the entry was
written and the day it was raised. The case is kept below as it stood.

**`display`, `print` and `system:write` all go to standard output, and nothing
goes to standard error.** So a program has no way to separate what it *produced*
from what went *wrong* with producing it.

**The machine has the stream the language does not.** `solvm` writes its own
diagnostics to standard error, and a test holds it to that — *a mistake goes to
stderr*. A Solum program running on that machine cannot do the same thing.

#### The program, and why the earlier ones do not count

[basic.sol](../programs/basic.sol) run over a `.bas` file reports a bad listing
on standard output:

```text
$ solvm basic.sob broken.bas > out.txt
$ cat out.txt
line 10: there is no line 999
```

The error is *in the output file*, and `2>/dev/null` does not suppress it. The
status is right — that was fixed the same day — and the stream is not, so a
shell can tell the run failed but cannot separate the failure from the results.

**Two programs here already mention stderr and neither is this.**
[bench.sol](../programs/bench.sol) discards a *child's* stderr so a noisy
command cannot write over its report, and [expect.sol](../programs/expect.sol)
keeps a child's stderr apart from its stdout so a complaint cannot accidentally
satisfy an expectation. Both are about reading somebody else's stderr, which
[3.15](COMPLETED.md#315-a-childs-streams-cannot-be-redirected--done) settled.
This is the first program that wants to **write** one.

#### Both workarounds, measured

| | |
| --- | --- |
| `system:writeFile("/dev/stderr", text)` | Works on this machine. It is a path that only exists on Unix, `writeFile` opens and truncates a file per call, and the whole thing is spelled as writing a *file* — which is what it is, and not what was meant. |
| `system:run(["sh", "-c", "echo ... 1>&2"])` | Also works, and costs a process. **0.5 seconds for a hundred diagnostics** — five milliseconds a line to write a line. |

Neither is worse than the gap the way
[3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done)'s
was: they are ugly rather than wrong. That makes this a smaller entry than that
one, and it is why it is written down rather than worked around.

#### What it would take, and the question to answer first

One primitive, and the question is the same shape as 3.18's and has a different
answer available:

| | |
| --- | --- |
| `system:writeError(text)` | Its own message, beside `write`. Says what it does, and the pair reads as the two streams a process has. |
| `system:write(text, 'error)` | One message with a destination. Fewer names, and it makes the common case carry an argument it never wants. |

**What should not happen is a second `display`.** `display` and `print` are
about rendering a value, they serve every type, and a variant of each that goes
somewhere else would be exactly the second mechanism behind the first that this
language exists to refuse. Whatever this becomes, it belongs beside `write` on
`system` — which is where 3.18 put the first half for the same reason.

#### What was decided

**Its own message, not a destination on `write`.** Of the two shapes the entry
offered, `system:write(text, 'error)` would make the common case carry an
argument it never wants, and every call site would have to say which stream it
meant even though almost all of them mean the same one. Two names read as the
two streams a process has.

**And no second `display`.** That was the thing to get right rather than the
naming: `display` and `print` are about rendering a value and serve every type,
so a variant of each pointing elsewhere would be the second mechanism behind the
first that this language exists to refuse. There is one way to reach standard
error and it is spelled as writing, not as displaying.

**It flushes**, which C does not require — stderr is unbuffered — but the whole
point of both `write` and this is text that arrives when it is written, and that
is not worth depending on a platform for.

#### What it fixed, in the program that asked

`solvm basic.sob broken.bas` now puts the program's output on one stream and the
complaint on the other:

```text
$ solvm basic.sob half.bas > out.txt
line 20: division by zero
$ cat out.txt
A
```

`A` is what the listing printed before it failed; the diagnostic is not part of
that and is no longer in the file. `2>/dev/null` silences the complaint without
silencing the program, and the status is still 1.

**[examples/reading.sol](../examples/reading.sol) had the same bug** and was
fixed by the same message. Its *nothing on standard input* complaint had always
gone to standard output, mixed in with the numbered lines that are its actual
result. Nobody had noticed, because until this there was nowhere else to put it.

**One test had to be rewritten, and the way it failed is the entry in
miniature.** It compared the merged streams — `2>&1` — and broke the moment they
were separated, both because the two now carry different things and because
merging them puts them in the wrong order: stdout is block-buffered down a pipe
and stderr is not. It asserts each stream on its own now.

### 3.18 A program cannot write without ending the line — **done**

**`system:write(text)` is the answer, landed the same day this was written.**
It takes a string, adds nothing to it, and writes to the same `stdout` the rest
of the machine writes to. What the entry argued is kept below as it stood.

**`display` and `print` are the only ways a Solum program has to put text on its
own output, and both end the line.** So a prompt cannot sit beside the answer to
it, a counter cannot be overwritten in place, and a line cannot be built from
pieces that are decided as it goes.

**Unlike everything else in this section, this one is not kept on purpose.** The
restrictions around it were chosen, or found and then judged worth living with.
This is work with a clear shape and a program already waiting on it.

**The program is [basic.sol](../programs/basic.sol), and the statement is
`INPUT`.** BASIC prompts with `?` and reads the answer typed after it on the
same line; this interpreter prints the `?` and reads the answer from the line
below, which is not what a BASIC program looks like:

```text
TWO NUMBERS, SEPARATED BY A COMMA
?
SUM IS 7
```

#### The workaround exists and is worse than the gap

`system:writeFile("/dev/stdout", "? ")` writes without a newline and looks like
the answer. It is not, and the way it fails is the reason this entry is worth
writing down rather than leaving as folklore.

`writeFile` opens its own stream on the file. `display` writes through the one
the process started with. When the output is a terminal that stream is
line-buffered and the two happen to interleave correctly; when it is a pipe or a
file it is block-buffered, and everything written with `display` is still sitting
in a buffer while the `writeFile` goes straight out. Measured:

```text
one          $ what the program printed, in order
two? four? one
three        $ what came out of a pipe
five
```

The prompt arrives before the three lines written before it. **It works when
tried by hand and silently reorders the transcript the moment anything is
redirected**, which is the same shape as the two hand-written square roots in
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done): plausible under the test anybody
runs, wrong under the conditions nobody thinks to try.

#### What it would take, and the one question it raises

One primitive that writes a string to standard output and adds nothing. The
question is not how but where it goes, and it is a real one, because this
language has kept its output on `display` and `print` — messages every object
answers, on the object being written.

| | |
| --- | --- |
| `system:write(text)` | Puts it beside `readLine`, which is the symmetry: the two halves of a terminal. Against it: everything else that writes is a message on the value, and this would be the first that is not. |
| `string:write` | Keeps the receiver as the thing being written, next to `display`. Against it: it reads as a third of a pair whose other two members serve every type, and a `write` that only strings answer is not that. |

Either would be one line of C. Neither should be added on the way past
something else — a language whose whole claim is that there is no second
mechanism should not gain a third way to print without deciding which of the
three is the one.

#### What was decided, and the one thing the entry did not think of

**It went on `system`, beside `readLine`.** The entry offered that or
`string:write` and called the question real, which it was. What settled it:
`print`, `display` and `asString` are a trio about *rendering a value* — the
literal form, the text, and the text as a value — and this is not a fourth
member of that family. It is about a **destination**, and the destination is
where `readLine` already lives. The two are the two halves of one terminal.

**A string and not any value**, following `writeFile`, which is the neighbour it
most resembles. `system:write(#42:asString)` says which of the two renderings it
wants, so there is no second rule to remember about how a value becomes text.

**It flushes, which the entry did not think about and which is the whole point.**
Text not followed by a newline sits in a line-buffered `stdout` until one
arrives — and for a prompt, that means until after the answer has been read,
which is the bug this was built to fix wearing a different hat. So the primitive
flushes and the ordering holds:

```text
one
two? three
four? five
```

That is the same program whose broken output is recorded above, now through a
pipe and in the order it was written.

**[basic.sol](../programs/basic.sol)'s `INPUT` is what asked, and it got more
than it asked for.** Whatever a `PRINT` left open is now written out without a
newline before the `?`, so a prompt the listing wrote and the `?` the
interpreter writes land on one line:

```text
TWO NUMBERS, SEPARATED BY A COMMA? 3, 4
SUM IS 7
```

That was two lines and a stray `?` for the two days between the statement being
written and this being closed.

### 3.14 The mathematics that is not here — **done**

**The title is the problem as it stood, and it stood for a long time.** All of
it landed on 2026-08-25, as one decision: `pow`, `exp`, `log`, `sin`, `cos`,
`tan`, `asin`, `acos`, `atan` on `float`, and `float:pi` and `float:atan2(y, x)`
on the class. `float` went from 26 messages to
35<!--count float-answers-->. What the entry argued about for weeks is kept
below in full, because the argument is the part worth having.

**No `pow`, no `log`, no `exp`, no trigonometry and no `pi`.** C has all of them
and each would be a line, and none is here because no program in this repository
has asked for one — *the ones a program has asked for rather than all of
`<math.h>`* being the rule this entry set for itself.

**This entry was larger twice and is now this.** It read *there is no square
root, no minimum, and no randomness*, and both of those halves have since been
answered. What each cost is recorded here, because the cost is the useful part.

#### The square root, and why it is a primitive

`sqrt` is a message a float understands and `min`, `max` and `between` are in
[math.sol](../lib/math.sol). Both were writable in Solum; the line between them
is not importance. `min` and `max` were written correctly the first time, in one
line each, and there is nothing in them to get wrong. `sqrt` was written
**twice, and both versions were wrong and silent about it**:

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

#### And randomness, which was the open half until it was measured

**`random:new` is the answer, and the question was where the state lives.** It
lives in an object you make, seeded by the machine or by a number you name —
never on `system`, because a generator there would give a VM a history and two
runs of one chunk would stop being identical. That is not a promise
[embedding.md](embedding.md) makes in so many words, and the wording of this
entry used to say it was: what that page promises is *one chunk, any number of
machines*, which a chunk carrying a generator's state would not be. A program
that never says `random:new`
is exactly as deterministic as it was before any of this existed.

**What settled it was measuring the generator that was already here.**
[bench.sol](../programs/bench.sol) carried Lehmer's — multiplier 16807, modulus
2^31-1, chosen so the product could not exceed a signed 64-bit integer, because
integer arithmetic traps on overflow rather than wrapping and so the generator
everybody knows cannot be written in this language at all. It was correct, and
in bulk it was fine: 100,232 heads in 200,000 flips, and 21 buckets over 210,000
draws spread from 9,799 to 10,157.

**The seeding was the defect, and it was invisible.** The clock was the only
entropy a Solum program could reach, so two runs a microsecond apart got
consecutive seeds — and a Lehmer generator's first output moves by the
multiplier when its seed moves by one:

| | before | after |
| --- | --- | --- |
| the first coin flip, over consecutive seeds | `1, 2, 1, 2, 1, 2, …` — **the parity of the start time** | no pattern |
| the first resample index of 21, over 2,000 consecutive seeds | **3 distinct values** of 21 | **21** |

Neither shows in the output, and neither was fixable in Solum: mixing a seed
properly needs the wrapping multiplication that traps here, and there is no
entropy but the clock for a *program* — the machine has `/dev/urandom` sitting
right there, which is the asymmetry the whole entry turned on. Add the modulo
bias that `mod n` leaves on the way out and there are three ways to get this
wrong that a reader cannot see, which is the argument that made `sqrt` a
primitive, holding more clearly here than it did there.

**The generator is PCG XSH RR 32/64**, its 64 bits of state are the object's
payload so an instance allocates nothing, `upTo` draws again rather than taking
a remainder, and the seed is recorded in an ordinary slot so a run the machine
seeded can be had back by writing the number down.

**What the trigger taught, since the entry named one and it was the wrong one.**
It said this waited for *a program wanting randomness for the work rather than
for how it measures*, and counted `bench.sol` as the second kind. That was a
misreading of that program: its product is the confidence interval, and the
interval is computed by bootstrap resampling. The randomness is the algorithm,
not the instrumentation. **A trigger can be written down wrongly and go on
looking unfired**, which is worth more than the entry it was attached to.

#### What is left

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

**What it was waiting for was a program, and the program has arrived.** For most
of this entry's life no file here had ever wanted an angle. The first draft of
this paragraph gave a
second reason — that the fifteen<!--count programs--> programs are text and process
work, so geometry is
not what this language is for — and that reason is **wrong and is worth leaving
recorded as wrong**. The programs are the tools this project needed while
building itself; they describe what has been written, not what may be. Solum is
meant to be a general-purpose language, which
[design.md](design.md#what-the-language-is-for) now states outright, and no
entry in this document should be read as ruling a direction out because nothing
has gone that way yet.

So the trigger was ordinary: **a program that wants an angle** — a plotter, a
simulation, anything with coordinates or a waveform. When one arrived, the
sensible thing would be to land trigonometry and `pow`/`log`/`exp` as a **single
decision** rather than a message at a time, since arriving one convenience at a
time is exactly what the rule above exists to prevent.

#### The program that arrived, and why it is a harder case than a plotter

[basic.sol](../programs/basic.sol) is an interpreter for **ECMA-55 Minimal BASIC
(1978)**. Six of that standard's eleven supplied functions are `SIN`, `COS`,
`TAN`, `ATN`, `EXP` and `LOG`, and its `^` operator needs `pow`.

**The difference from a plotter is that this program cannot decide to want less.**
A plotter that wanted one angle could be written to want none — plot something
else, or take the coordinates ready-made. An interpreter is measured against a
document it did not write. Either `PRINT SIN(0)` gives `0` or the interpreter is
not an interpreter for that language, and no amount of taste about what belongs
in a small language changes what is on page 27 of the standard. That is the
strongest form the trigger could have taken, and it took it by accident: the
program was chosen for being a different *shape* from the other ten, not for
wanting arithmetic.

**`^` is where it bites first, and it is the same failure this entry already
records twice.** The obvious stub is repeated multiplication, which is exact for
`2^3` and cannot answer `2^0.5` at all; the next one is `exp(y * log x)`, which
needs two of the six missing functions. So `basic.sol` raises on `^` and names
this entry, rather than shipping an operator that is right in the cases anybody
tests and silently wrong outside them — which is precisely how both hand-written
square roots got through.

**What is decided by BASIC rather than by us**, of the three questions below:
the standard's functions take **radians**, and its `ATN` takes one argument, so
`atan2`'s missing receiver need not be answered to unblock this program. Only
where `pi` lives is still open, and Minimal BASIC has no `PI` at all — so even
that can wait for the second program.

Stage three of `basic.sol` is the supplied functions, and it cannot start until
this is decided.

Three questions it raises that `sqrt` did not, worth having answered before a
program forces them:

| | |
| --- | --- |
| where `pi` lives | `infinity` and `nan` are globals, so `pi` would be the third — and the first that is not an IEEE special. `float:pi` as a class-side slot is the alternative, and the two read very differently on the page. |
| radians or degrees | Decided once and regretted afterwards, in every language that has chosen. C gives radians; the places a person types an angle by hand usually want degrees. |
| `atan2` belongs to neither argument | It takes two coordinates and there is no receiver that is obviously the subject, so `y:atan2(x)` reads badly in a language where the receiver is what the sentence is about. |

And a note on size, since it is the one argument that is about the shape of the
language rather than about the maths: `float` answers 35<!--count float-answers-->
messages today, and
`sin`, `cos`, `tan`, `asin`, `acos`, `atan` and `atan2` would be a third again.
That is a reason to add them deliberately and together, not a reason to refuse.

#### How it was decided, and what the deciding was actually about

**The program was [basic.sol](../programs/basic.sol), and it fired the trigger
by accident.** BASIC was chosen for being a different *shape* from the other ten
programs here — an interpreter for another language rather than a tool for this
one — and not for wanting arithmetic. It turned out to want six functions and an
exponent operator, because they are on the page of ECMA-55 Minimal BASIC it is
measured against.

**That made it a harder case than the plotter this entry imagined.** A plotter
that wanted one angle could have been written to want none. An interpreter is
measured against a document it did not write: either `PRINT SIN(0)` gives `0`,
or it is not an interpreter for that language. There was no version of the
program that wanted less.

**Eleven, not the seven that were wanted.** `asin`, `acos`, `atan2` and `pi` are
here although no program has asked for one, and the reason is this entry's own
rule rather than generosity. Written by hand, `asin(x)` is
`atan(x / sqrt(1 - x*x))`, which divides by zero at the ends of its own domain;
`atan2` is `atan(y/x)` with quadrant fixups everybody gets wrong on the axes.
Both fail the same test `sqrt` failed. **`pi` is the one member that does not** —
anybody can type 3.141592653589793 and have the nearest double exactly. It is
here so that a language with `sin` and `cos` is not one where the first thing
every program does is write out a constant.

**The three questions above were answered, two of them by BASIC.**

| | |
| --- | --- |
| where `pi` lives | `float:pi`, on the class, not a third global. `infinity` and `nan` are globals because they are values this arithmetic *reaches* and has no other way to name. `pi` is a constant — and `pi` is a name a program is entitled to want, which is the argument [math.sol](../lib/math.sol) already makes for binding no global of its own. |
| radians or degrees | **Radians**, following C and following the standard `basic.sol` implements. No degree variants: a conversion is a multiplication, and a multiplication is not something the machine has to supply. That is the same line this entry drew between `sqrt` and `min`. |
| `atan2` belongs to neither argument | So neither argument is the receiver. `float:atan2(y, x)` is class-side, the way `time:fromSeconds` and `array:of` are, and then the arguments are in the order the name has always had them. |

**None of them raise.** `sqrt` answers `nan` for a negative and division reaches
`infinity`, so `log(0)` is `-infinity` and `log` of a negative is `nan`. A
language with stricter rules imposes them itself, and `basic.sol` demonstrates
exactly that: it raises for `SQR(-1)` and `LOG(0)` because ECMA-55 says to, on
top of a Solum that quietly answers `nan`. The stricter rule belongs to the
language being interpreted.

**And the size argument this entry worried about turned out to be the small
part.** Eleven primitives are eleven lines of C. The work was the four things a
new message obliges, each held by a test: it must be sent by an example with a
checked claim, be in the reference's type table, be in the message index, and be
on the cheatsheet. That is where the afternoon went, and it is the right place
for it to go.

### 3.15 A child's streams cannot be redirected — **done**

`system:run` gave the child this program's stdout and stderr; `system:capture`
kept the child's stdout and answered it with the status. There was no third
thing, and in particular **no way to discard a child's stderr** or to send
either stream to a file.

**Both messages now take an optional second argument** saying where the child's
streams go — an array of alternating name and value:

```text
system:run(["make"], ["stderr", 'discard]).
system:capture(argv, ["stderr", 'merge]).
system:run(argv, ["stdout", "build.log", "stderr", 'merge]).
```

A value is either a **manner, as a symbol** — `'share`, `'discard`, and
`'merge` for stderr alone — or a **path, as a string**. The type is what tells
them apart, which is what keeps a file called `discard` a file.

#### The shape was the whole question, and the language answered it

The entry named two candidates and picked neither: a fourth argument to
`capture`, which is the smallest thing that works and the least general, or an
options bag, which generalises without new messages at the cost of a shape
nothing else here uses.

**The bag won, and then the language chose how to spell it.** The argument for
the bag is that there are four things a caller might want to say and positional
arguments cannot carry four optional ones — and the fourth is the one this entry
never mentioned: there was no way to give a child anything to *read*, either.
`stdin` was inherited by both messages and unmentioned by the roadmap, which is
what settled it. But the bag could not be a dictionary, because **this language
has an array literal and no dictionary literal** — a dictionary here would have
cost three statements at every call site to say one thing:

```text
opts := dictionary:new.
opts:atPut("stderr", 'discard).
system:capture(argv, opts).
```

So it is an array of alternating name and value, which is the notation the entry
itself had sketched before either question was asked. The names are the strings
`capture` already answers with, so a stream is spelled the same going in as
coming out.

#### What it cost, and what it caught

Thirty lines of plumbing around code that already forked, and the rest was
refusals. Every one of them reports rather than guesses: a stream named twice, a
name that is not a stream, `'merge` on anything but stderr, a manner that does
not exist, a value that is neither a symbol nor a string, and `"stdout"` handed
to `capture` — which is refused whatever the value, since keeping stdout is what
that message is for.

Two decisions in the plumbing are worth the words they took:

- **The files are opened before the fork**, so a path that cannot be opened is
  the caller's error to read rather than a child that silently did nothing.
  They are opened close-on-exec, and the copy `dup2` makes is the only one the
  child carries, `dup2` not passing the flag on.
- **`'merge` follows stdout to where it is now**, which is `>file 2>&1` and not
  `2>&1 >file`. Those are the two orders a shell distinguishes and the classic
  way to get this wrong, and it falls out of doing stdout first.

**[bench.sol](../programs/bench.sol) is the proof, because it is what asked.**
It had used `capture` so that a timed command could not write over the report,
and stderr went straight through that and did exactly what `capture` was there
to prevent. The way round was `/bin/sh -c '"$@" 2>/dev/null' sh ...` — a second
fork and a second exec on *every measurement*, of the same order as the thing
being measured, which is the one program that cannot pay it. It now passes
`["stderr", 'discard]` and its report is clean:

```text
$ ./bin/solvm programs/bench.sob 8 /bin/sh -c 'echo noise 1>&2; true'
  runs     8
  min         4.594 ms
  median      5.278 ms
```

The noise goes and the failure does not: what says a command failed is the
status, which `'discard` leaves alone.

**The test that mattered watches its own stderr.** `'discard` is the claim whose
failure is invisible — output that should not appear looks exactly like output
that appeared somewhere else — so the test points the *test process's* stderr at
a file for the length of the call and reads it back empty. Three hundred
redirected children in a loop afterwards say nothing was left open, which under
a 256-descriptor limit is a claim that fails loudly if it is false.

### 3.17 A global is found by walking a list — **done**

`OP_GLOBAL` resolved a name by walking the root object's slots and comparing
interned pointers, and every *send* resolved its message the same way, down the
class object's slots. Linear, and exactly linear: about 1.35ns a slot walked, so
a name with 800 globals ahead of it cost 16× what pushing a constant costs.

**An object with more than a dozen slots now keeps a table beside its list.**
Not instead of it: the list is still the object's state — it holds definition
order, which `slots` answers with, and it is what the collector walks and frees.
The table is a lookup index over the same slots, open-addressed on the interned
name pointer, which is the identity of a name and stable for the life of the VM.
Below the threshold there is no table at all, so a point with three slots pays
nothing, in memory or in a branch.

#### What it was worth, and what it cost

Against the same programs, `bin/solvm` before and after, 21 runs each through
[bench.sol](../programs/bench.sol):

| | |
| --- | --- |
| a global with 60 ahead of it | **2.88×** |
| a global with 16 ahead of it | **1.37×** |
| a send to a slot 400 deep | **4.89×** |
| a send to `add`, 35 deep on `integer` | **1.35×** |
| [disasm.sol](../programs/disasm.sol) over an 8.7K `.sob` | **1.31×** |
| [page.sol](../programs/page.sol) over the site | **1.20×** |
| [evaluator.sol](../programs/evaluator.sol) | **1.09×** |
| [manifest.sol](../programs/manifest.sol) | 1.06×, and the interval crosses 1 |
| [log.sol](../programs/log.sol) | unchanged |
| **a send to a slot 4 deep** | **0.88× — 12% slower** |
| **reading the most recently bound global** | **0.89× — 11% slower** |

**The last two rows are the trade, and they are real** — both intervals sit
entirely below 1. A hash is a constant where a walk is a step, so the shallowest
lookups pay for the deepest ones. What makes that the right way round is that
the shallow case was never the one that mattered: the old order was *recency*,
so the name a library bound first was the slowest to read and the one the
program bound last was the fastest, which is backwards for the case it matters
in — a library's constant, read in somebody's loop. Every real program measured
is faster or unchanged.

**Memory is not the cost it looks like.** Peak RSS over `disasm.sol` is 0.94 MB
before and after: the tables are two seats a slot at sixteen bytes, so the ten
built-in classes come to about six kilobytes between them, and nothing else in
the repository has enough slots to get one.

#### What the measuring found, which was not what the entry expected

The entry is about globals. **Sends turned out to be where the time was**, and
for a reason the entry did not see: the built-in messages are registered in
order and a new slot goes on the *front* of the list, so `add`, `sub`, `mul` and
`print` — registered first, used most — ended up deepest. `add` sat 35 slots
down a list of 38. Padding `integer` and timing the walk gave 1.1ns a slot on
the send path, the same as on the global path, which is what made it clear the
fix belonged in `sol_object_lookup_interned` rather than at the `OP_GLOBAL` site.

**The first version was 30% slower on a shallow send**, and finding out why is
what produced the design that shipped. A counter said 2.00 probes a lookup; the
table held slot pointers alone, so each probe had to follow one to read
`slot->name` — three dependent loads where the list has one. **A short linked
list is not slow**: an object's slots are allocated together, so the walk reads
memory the prefetcher has already fetched. Putting the key in the table beside
the slot, in the same sixteen bytes, took the shallow-send loss from 30% to 12%.

Two things measured the opposite of the obvious guess. **A stronger hash was
slower** — splitmix64's finaliser is two multiplies on the critical path of
every lookup in the language, and it bought fewer probes than it cost. And
**a table twice the size made no difference** once the key moved into it, so the
density stayed at two seats a slot rather than four.

#### One thing worth leaving behind

Breaking the growth rule deliberately, to check that the test would catch it,
**hung the suite** instead of failing it: a full table makes linear probing spin
rather than answer wrongly. The insert loop is bounded now, so the same mistake
is an assertion. A wrong answer is a bug; a hang is a bug that takes the test
run with it.

---

### 3.16 What the checker does not check — **done**

The odd one out of the whole list: about this repository's own verification
rather than about the language. It was here because [ROADMAP.md](ROADMAP.md)
claims to be the single list of what is outstanding, and a gap in what
`make test` proves is outstanding.

It named three gaps. Two were closed by reading a page as a page and making an
unrunnable block a failure; the third was closed by giving a number in a
sentence a notation saying what it counts.

#### A block that would not run

It was counted and reported rather than failed, on the reading that it
*continues one further up, or shows syntax rather than a program*. Both are
real. Both are also true of a block with a typo in it — `README.md`'s opening
snippet, the four lines that introduce the language to everybody who arrives,
was missing the `.` after `a := #45` and had been seen and skipped on every run.

**Counting what was inside those blocks settled it: 54 claims in 42 blocks,
against 672 checked. One claim in thirteen.** And the split says where, which is
not where the entry guessed — it proposed telling the two categories apart on
the theory that *would not compile* was the suspicious one, since that is what
caught the README. It is the opposite:

| | blocks | claims inside them |
| --- | --- | --- |
| would not compile | 10 | **2** |
| compiled, then failed at run time | 31 | **52** |

The compile failures were the shell and REPL transcripts, as harmless as they
looked. A name defined in the block above is not a fragment showing syntax; it
is a program with its first half on the previous page.

**So a page is read as a page.** Each block that runs joins the document's
context, and a block that will not run alone is run again on everything accepted
before it — which is what the prose says out loud, since *continuing the `point`
above* stands 370 lines and ninety blocks after the `point` in question. That
accounts for 28 of the 42. The cheaper thing does not work: a fixed window of
the nearest blocks recovers 24 of the 54 claims at a depth of five and not one
more at twenty, because the distance is not the problem, what is between them
is.

Three things had to be right, and each was wrong first.

- **The context may not satisfy the block's claims.** What it writes alone is
  measured before the block is appended, and only what came after is read.
- **A complaint is read wherever it lands.** With stderr merged the streams
  interleave by buffering rather than by source, so taking the context's line
  *count* off the front does not take its *lines* off the front. It left
  `solvm: undefined name 'animal'` in the part being skipped, and nine blocks
  were accepted as having run when they had produced nothing.
- **The program has to say it reached the end.** `system:exit` unwinds, which is
  documented behaviour with a block of its own in the reference — and that block
  joined the context, after which the page's context was a program that exited
  before reaching anything, for ninety blocks. A line printing a word nothing
  else prints is appended, and if it does not come back the context does not
  grow.

**And a block that is not a program says so**, with a word after its fence. The
cost the entry named — *the convention has to be applied to 42 blocks before it
can be enforced on the 43rd* — was 14 blocks, because 28 of the 42 were programs
all along. The documents were already tagging 31 fences `sh` and `c`; a `text`
tag joins them. **A reader can see a fence that says `text`; nobody can see a
silence in a count.** With that, a block claiming to be Solum and failing to run
is a failure, confirmed by breaking one both ways.

#### A number in a sentence

*"Prose is not checked at all"* was the second gap, and the difficulty is exact:
**a number in a sentence has no notation saying what it counts.** So it is given
one. The comment renders as nothing and the reader sees the sentence:

```text
[expect.sol](../programs/expect.sol) checks 992<!--count claims--> claims
```

[expect.sol](../programs/expect.sol) recounts each of them from the repository
as it stands — the programs on disk, the slots a class holds, the claims this
run checked — and **a name the table does not know is a failure**, so a marker
cannot be misspelled into silence, which is the failure mode the entry is about.
The counts that are facts about a particular run are deferred rather than
compared when the run covered less than everything.

A position needs no marker, because the phrase is already one: nine programs
open with *The fifth program here*, and [programs.md](programs.md) puts them in
that order under its headings. The two are now held together.

**What it found**, all of it by recounting rather than by reading:

| | said | is |
| --- | --- | --- |
| ROADMAP 3.14, on whether `float` should gain trigonometry | `float` answers **21** messages | **35**<!--count float-answers--> — the count that entry's whole size argument rests on, five releases out of date |
| [REFERENCE.md](REFERENCE.md)'s message index | **121** messages across **215** registrations | **122** across **216** |
| [programs.md](programs.md)'s sample output | 21 files, **398** claims | 22 files, **549**<!--count examples-claims--> claims |
| `README.md`, `programs.md` and the entry itself | **589** claims | **992**<!--count claims--> |

#### What is left, which is not a gap

A sentence can say anything, and no checker reaches that. The entry's own
example is the sharpest one: `expect.sol` carried a comment promising that the
report *says how far apart the match was found when it was not the next line*,
which it has never done — the fault the program exists to catch, sitting in the
program, in the one place it does not look. That is now corrected in place, and
what replaced it says the checker does not detect a coincidental match.

A claim on a line that does not itself print is still not checked, and **the
report says so** — it counts those lines and prints the count. The same goes for
a transcript in a fence: [programs.md](programs.md) shows what `expect.sol`
prints, and nothing can hold a transcript to anything. Both are visible in the
output rather than hidden in it, which is the difference this entry was about.

**What it costs**: `make test` went from about seven seconds to about twenty. A
page's context is a second program that grows with the page and is re-run for
every block under it. The cheap version — adding up what each block wrote by
itself instead of measuring the two together — is wrong in the way that matters,
because being one line out is not a failure that shows, it is a claim matched
against somebody else's output.

---

### 3.9 The verifier does not know the stack height — **done**

`OP_SEND` carries `argc` in a byte the file supplies, and whether that many
arguments are really on the stack depends on the height at that instruction.
Nothing computed it, so nothing structural could tell a real count from a
corrupted one. Fuzzing the loop work found the shape: 227 arguments on a stack
one deep, reading the receiver from below the frame.

The verifier computes the height at every instruction now, by walking control
flow from the entry and following each branch. The rule is the JVM's — **the
paths into a point must agree**: an instruction reached from two places at two
different heights has no height, and that is what corruption looks like. This
came last of the four rather than first because it needed the other three:
every opcode's length is known, and every branch target is already established
to be an instruction boundary, so the walk can only land where an instruction
begins.

Measured over 1,750 single-byte corruptions of one `.sob`:

| | before | after |
| --- | --- | --- |
| refused at load | 1031 | **1066** |
| failed part-way through a run | 236 | **208** |
| ran to completion | 483 | **476** |

The last row is the one worth having. Those seven were corrupt files that passed
every check and that the runtime never objected to — they ran, on an inconsistent
stack, and produced output. Twenty-eight more moved from failing mid-run to
being refused at the door. About 5% on load, paid once.

**The runtime check stays**, which is the one place this departs from what the
entry above expected. The two cover different populations rather than one being
redundant: the verifier runs when a `.sob` is loaded, and Solis runs what it just
compiled without verifying — deliberately, since verifying every REPL line to
catch the compiler's own bugs is the wrong shape — while the C API will run any
chunk it is handed. One comparison per send is a cheap floor to keep under all
of that.

Code no path reaches is never given a height and is not required to have one: it
cannot run. Its operands are still checked by the structural pass, and a jump
into it would make it reachable, at which point it is checked like anything
else.

---

## 4. Performance

Nothing here was urgent — the VM is written for clarity first — and all of it is
now done. Kept rather than deleted because each entry records what was measured
and why the shape chosen was the one taken; the detail is in the changelog.

### 4.1 Conditionals and loops are real calls — **done**

`ifTrue`, `ifFalse`, `ifElse`, `whileTrue`, `and`, and `or` written literally
compile to jumps: no block allocated, no frame entered. They are still ordinary messages,
and still reachable as such through `perform` or with a block held in a
variable.

Inlining applies only when every block involved is written right there with no
parameters and no temporaries. Both restrictions are about meaning, not
convenience: a block with parameters is an arity error when `ifElse` calls it
with none, and inlining would quietly make it work; a block's temporaries belong
to its own frame, so inlining would declare them in the enclosing one where they
could collide with a name already there. Anything else falls back to a real
send, and there are tests that the two forms agree.

`whileTrue` is the awkward one, because its condition is the *receiver*: by the
time the selector has been read, an ordinary compile has already emitted an
OP_BLOCK for it. So the compiler reads ahead over the whole `{ ... }:whileTrue(
{ ... })` before compiling any of it, and the parser stays single-pass in the
sense that matters -- it never revisits a token it has already emitted for.

Measured at each step, all three builds timed together on one machine so the
columns are comparable:

| | before 4.1 | conditionals | and loops |
|---|---|---|---|
| recursion, plain | 30 | **62** | 62 |
| recursion through a loop body | 20 | 30 | **62** |
| a tight two-million-pass loop | 0.53s | 0.52s | **0.44s** |
| the same loop with a conditional in it | 1.44s | 1.13s | **1.06s** |

The depth is the real result. Each level of that second row used to cost three
frames -- the method, the `ifTrue` branch, and the `whileTrue` body -- and now
costs one, so recursion that happens to run inside a loop reaches exactly as far
as recursion that does not. The seconds are worth less than they look, and 4.1's
own entry measured its 1.60s on another day; these were all taken today.

The verifier changed as predicted, twice. It records where each instruction
starts and checks every branch target lands on one, in range. The backward jump
is its own opcode, OP_LOOP, so that "forward" stays the default and the one
instruction that can move the ip towards zero is easy to find.

What a backward jump costs is that verified bytecode can now run forever. That
is not a new capability and the verifier does not try to prevent it: `{ true
}:whileTrue({})` is a legal program, and before this a corrupted file could
already spin through a loop built from real sends. Landing on an instruction,
inside the chunk, remains the whole promise. Termination never was.

The loop's test is a second opcode, OP_EXIT_IF_FALSE, rather than a reuse of
OP_JUMP_IF_FALSE, and only because the two complain differently: for `ifTrue`
the boolean is the receiver, so a non-boolean does not understand the message;
for `whileTrue` it is what a block answered, which is a different sentence. Both
sentences now come from one function, so the inlined form and the send cannot
drift apart -- the failure 5.3 records, in advance this time.

Instruction lengths are also down to one table now, `sol_op_length`, which the
emitter, the verifier, the disassembler, and the tests all read. Four copies of
that table and a jump landing mid-instruction is what disagreement looks like.

`and` and `or` came last, and needed one thing the conditionals did not. They
answer a boolean on both paths, and on the long path the boolean is whatever the
block said -- so the block's answer is the reply *and* has to be checked. That is
neither of the existing tests: OP_JUMP_IF_FALSE and OP_EXIT_IF_FALSE both consume
the value they branch on. **OP_CHECK_BOOL** examines the top of the stack and
leaves it, naming the message so the complaint is the one the send would have
made. `.sob` went to version 10.

The short-circuit answer is a constant rather than the global `true` or `false`.
Those are ordinary globals a program can rebind, and reading one would let the
two paths disagree about what `and` answers.

| | before | after |
|---|---|---|
| a two-million-pass loop, mostly `and`/`or` | 2.31s | **1.83s** |
| recursion through an `and`/`or` block | 31 | **62** |

The depth is again the better number, and for the same reason as above: the
block was costing a frame that the jumps do not.

### 4.2 One-byte operands — **done**

`OP_CONST`, `OP_SEND`, and the name operands each carried a single byte, so a
chunk could hold 256 constants and 256 names, and a literal-heavy program
stopped compiling well before it stopped making sense. Those operands are two
bytes now and the ceiling is 65536.

Not the `CONST_LONG`-style pair this entry expected, and the reason is the rule
4.1 arrived at: an opcode should mean something. `OP_LOOP` is its own
instruction because a backward jump is a different thing from a forward one;
`OP_EXIT_IF_FALSE` is its own because it complains differently. A `CONST_LONG`
means exactly what `OP_CONST` means and differs only in how wide its operand is
-- and it would not have come alone. Nine instructions carry a side-table index,
so it would have been nine more opcodes, in the length table, the verifier, the
disassembler, and the dispatch loop: four more copies of the agreement 4.1 spent
its time collapsing into one.

So the width belongs to the operand rather than to the opcode, and there is one
rule for it. An index into a side table -- a constant, a name, a nested method
-- is a u16, because those tables grow with the program. A frame
slot, a nesting depth, an argument count stays a u8, because those are bounded
by the machine rather than by the source: a frame of more than 255 slots is
refused before it runs. Jump offsets were u16 already, so sixteen bits is now
the only width the format has, and `sol_read_u16` is the one place it is
decoded.

The constant pool also interns, which it never did -- `#1` written three times
was three slots and is now one. The loader still appends rather than interning,
for the reason the name table already did: a file refers to both tables by
position, so folding a duplicate on load would shift every index after it.
Constants are compared by their bits rather than by `==`, which keeps -0.0
distinct from 0.0 and stops a NaN from folding onto itself.

Interning paid for much of the widening. Across the eight examples the `.sob`
files grew 3.2% in total, and `arrays.sol` *shrank* by 3.9% -- its top-level
constant pool went from 41 entries to 12. Run time did not move: three
benchmarks, all inside ±1%, which is the noise on this machine. The second byte
costs a read the jumps were already doing.

| | before | after |
|---|---|---|
| constants and names per chunk | 256 | 65536 |
| the eight examples, total `.sob` bytes | 9934 | 10250 |
| `arrays.sol` top-level constants | 41 | 12 |
| a tight two-million-pass loop | 0.251s | 0.252s |
| the same loop with a conditional in it | 0.457s | 0.455s |
| a million sends of a user-defined method | 0.159s | 0.158s |

Raising the ceiling exposed something the old one had been hiding. Both tables
intern by walking themselves, which costs nothing at 256 entries and is
quadratic at 65536:

| distinct names and constants | compile |
|---|---|
| 1000 | 0.02s |
| 4000 | 0.08s |
| 16000 | 0.87s |
| 32000 | 3.52s |

The scan was always this shape -- the name table has done a `strcmp` per entry
since the beginning -- but a cap of 256 meant it could never be reached. Nothing
anyone writes by hand is near 16000 distinct literals, and a generator can be,
so the cap and the algorithm no longer match. A hash on the way in is the fix,
and it is the same table 4.3 wants for dispatch: intern once, compare pointers
after.

What is left at 255 is the argument count, and through it an array literal
(1.2b). That one is not an operand-width problem: a longer literal needs a
different construction -- `array:new` and repeated `add` -- rather than a wider
`argc`.

### 4.3 Dispatch does a string compare per send — **done**

A selector is compared by pointer now. Every slot name and every selector goes
through one table on the VM which answers the same address for the same
characters, and a chunk's name table is resolved through it once before the
chunk runs -- so the hash is paid per name per chunk, and a send reads a pointer
that is already resolved.

| | before | after |
|---|---|---|
| 3M sends in a loop | 1.36s | **0.74s** |
| 1M sends to a user-defined method | 0.51s | **0.29s** |
| 1M sends four levels up a proto chain | 0.38s | **0.21s** |

The table is deliberately **not** the weak symbol table behind `'foo`, which was
the obvious place to put it. The two hold their contents differently for a
reason: a symbol is a value a program can drop, so that table is weak and a
symbol nothing mentions can die -- the measured result in `5a15fc9`. A name is
pointed at by slots and by chunks, neither of which can announce that they are
done with one, so these live as long as the VM and are freed with it. Sharing
the weak table would have meant marking every slot name on every collection,
which is the cost that table exists to avoid.

`sol_object_lookup` still compares spelling, because C callers and tests hold
ordinary literals; the dispatch loop uses `sol_object_lookup_interned`. Handing
the second one a name that never went through the table would answer NULL rather
than fail, so `-DSOLUM_CHECK_INTERNED` compiles in an assertion that it did --
the same bargain as `SOLUM_GC_STRESS`, a check too expensive to leave on and too
useful never to run. The suite passes under it.

#### 4.3a The side tables' linear scan — **done**

The other half, and the one that had begun to hurt: 4.2 raised the tables from
256 entries to 65536 without touching the linear scan that filled them, so
compiling many distinct literals was quadratic.

| | before | after |
|---|---|---|
| 10,000 distinct names and constants | 0.43s | **0.01s** |
| 20,000 | 1.44s | **0.02s** |
| 40,000 | 6.17s | **0.04s** |

A chunk keeps a hash index over each side table, and the emitted bytecode is
byte-identical -- the same entry lands at the same position, only faster to find.
Below sixteen entries there is no index at all and the scan stands, which is
where it was always cheaper anyway and is why a method body, a block, or a REPL
line costs nothing extra: measured, 60,000 REPL lines still peak at 1.9 MB.

---

## 5. Tooling and ergonomics

### 5.1a Error recovery could loop forever — **fixed**

`synchronise` tested whether the previous token was a `.` before advancing, so a
statement that failed *without consuming anything* -- `primary` reports an
unexpected token without taking it -- was retried forever when the token before it
happened to be a `.`. `b := { #1. | q | q }.` produced three million identical
error lines in three seconds.

Recovery now advances before testing, so it always consumes at least one token.
Found by a typo in a test, not by looking for it.

### 5.1 Solis is line-at-a-time, and lines are capped — **done**

Solis reads until the input could compile, then compiles and runs it. A line was
never a unit of anything in this language -- `.` separates statements and a
newline is ordinary whitespace -- so a method body may now span as many lines as
it likes, with `.. ` for the continuation prompt.

Two things say the input could still be finished: an unclosed bracket, and an
unclosed string. Both outlive a line, so the state carries across them. Counting
brackets naively would have been wrong twice over, and both cases are real rather
than theoretical: a brace inside a string is not a bracket, and `fill` templates
are made of braces; a `;` comment runs to the end of its line, so anything in one
is text. A stray closer does not take the depth below zero, or a mistyped `)`
would leave the prompt waiting for input that could never balance it.

The 1024-byte cap is gone rather than reported. The buffer grows, and a line is
read in pieces until its newline arrives, so nothing is cut. That cap was the
cause of the confusing session this entry recorded: a generated 255-element array
literal looked like it failed to compile when it had merely been severed
mid-token, and its tail arrived as if it were the next line. A 5000-byte line now
arrives whole, and there is a test that the next line is still the next line.

Deciding this is in `solis/src/input.c` rather than in the loop, so it can be
tested -- which also gave Solis the `cmd/` and `src/` split the other two
components already had.

Not done, and not obviously wanted: a way to abandon a half-typed submission.
Ctrl-D at a continuation prompt leaves, and typing the closing bracket gets a
compile error, which are two workable ways out. A blank line would be the usual
third, but a blank line inside a method body is ordinary formatting here.

### 5.2 `print` on an object — **done**

An object is rendered by asking it: the renderer sends `asString`, so one that
defines its own is shown that way by `print`, by `display`, by `fill`, and
inside an enclosing array -- one definition serving all four.

The seam did have to move. `sol_value_render` now takes a VM, which may be null;
the disassembler passes null, its constants never being objects, and falls back
to the address.

The recursion this invites is broken at the source: `object`'s default `asString`
writes the address directly rather than calling the renderer back. An `asString`
a user writes to render itself still recurses, but through real frames, so it
stops at the call-depth cap like any other runaway recursion rather than
smashing the C stack.

That was true of an ordinary object and **false of a class object**, which was
1.5: `array:print` smashed the C stack, because lookup on `array` starts at the
object itself and found the `asString` that class defines for its instances.
Fixed by 1.6's receiver check, which refuses it. The renderer now asks only an
object that can answer and shows one that cannot as its address, so a class
object nested in an array renders rather than raising.

Still missing: nothing asks an object for a *literal* form distinct from its
display form, the way `#45` prints as `#45` but displays as `45`. Objects have
one representation, which is probably right.

This entry also used to end by saying `sol_value_print` prints `<object 0x...>`
instead of sending `print` to the object, and wants dispatch from inside the
printer. That was read off the function's name rather than off what it is
handed, and it had not been true since `f55e105`. `print` the message goes
through `prim_print`, which has a VM and does send `asString`. The function had
exactly one caller — the disassembler, rendering a pooled constant — and a
constant is only ever an immutable scalar, since `check_constants` refuses
objects, blocks, arrays, strings, delegates and symbols outright. There was
never a receiver there to ask.

It is now a static `print_constant` in `bytecode.c` beside its only caller,
named for what it prints, so the name cannot suggest the gap again.

### 5.3 Float text round-tripping — **done**

A float now renders as the shortest decimal that reads back as the same bits, and
that text compiles.

This was worse than "does not round-trip". `%g` gives six significant digits, so
`1234567.0` printed as `1.23457e+06` -- a *different number* -- and `asString`
baked that into a string. Printing could quietly show the wrong value.

Shortest is not always clearest, so where a number has few enough whole digits
the renderer asks for enough precision to keep `%g` in fixed notation: `1000`
rather than `1e+03`. More digits can never stop it round-tripping.

Infinity and not-a-number are written by name, and `infinity` and `nan` are now
globals so those two read back. `-infinity` has no literal form; `asFloat` parses
it, since `strtod` accepts the word.

The fix also caught a drift it was meant to prevent: `prim_float_as_string` had
its own `snprintf("%g")` rather than going through the renderer, so `print` and
`asString` disagreed about the same value until it was routed through.

### 5.4 No source position beyond the line — **done** for compile errors

A compile error names the line and the column, and shows the line with the
offending token underlined:

```
[line 2:9] solas: expected '.' between statements at ','
  b := #2 , .
          ^
```

A token now records where it *began* rather than where the scanner stopped,
which is what places a string spanning several lines at its opening quote
instead of wherever it ran out. Error tokens changed shape for this: the
complaint moved to a `message` field so that `start` and `length` point into the
source for every kind of token, and an unterminated string can be underlined
like anything else.

Two details that are easy to get wrong and are pinned by tests. The pad before
the caret is built from the line's own characters, so a tab in the source is a
tab in the pad and the two line up whatever width the terminal gives it. And a
long line is windowed around the token rather than spilled whole -- which
matters more since 5.1, because Solis will now read a line of any length.

**Runtime errors stay at line granularity**, and that is a size question rather
than an oversight: a chunk records a line per byte of bytecode, so a column
would be a second table in every `.sob`, carried always and printed only when
something has already gone wrong. Worth revisiting if a debugger ever wants it.

---


### 5.5 Five programs each wrote the same cursor — **done**

[lib/scan.sol](../lib/scan.sol) — a position and the questions you ask at one.
Raised on 2026-08-25 out of a survey done for a different reason, and closed the
same day.

**The case.** `lib/json.sol`, `lib/html.sol` and `experiment/lexer.sol` each
defined `pos`, `peek` and a step — two calling it `step` and the third
`advance` — and `programs/expect.sol` and `programs/serve.sol` did the same
scanning inline without naming a cursor at all. Roughly 460 lines of it.
Nothing was blocked, which is why it went in section 5 rather than section 1:
the cost was that a fix to the cursor was a fix in five places, and nobody
would make the other four.

**The entry said: write it, convert `json.sol` only, and let that say whether
the interface is right before anything else moves.** That is what happened, and
the conversion changed the interface twice.

| | |
| --- | --- |
| **`since(start)`** | `takeWhile` describes a run of *one* kind of character. JSON's number is a sign, then digits, then perhaps a fraction and an exponent, and the caller wants all of it. Not in the entry's list; the conversion demanded it. |
| **`take(#n)`** | `\uXXXX` wants exactly four characters. Also not in the list. |
| **The block is never handed nil** | Every hand-written version opened `peek:notNil:and({ ... })`. That is the cursor's business: a predicate is a question about a character, and running out is not a character. |

**What it cost and what it paid.** All five are converted now, and the honest
total is that the library roughly pays for itself and no more:

| file | code lines | |
| --- | --- | --- |
| `lib/json.sol` | 215 → 197 | −18 |
| `lib/html.sol` | 296 → 277 | −19 |
| `experiment/lexer.sol` | 169 → 163 | −6 |
| `programs/serve.sol` | 129 → 126 | −3 |
| `programs/expect.sol` | 534 → 534 | 0 |
| **`lib/scan.sol`** | | **+48** |

**46 recovered against 48 spent.** Anyone expecting a library to shrink the
repository should read that and stop expecting it. What was actually bought is
that there is one implementation of a cursor instead of five, and the two files
that could not agree whether the method is called `step` or `advance` no longer
have the choice.

**`expect.sol` returned nothing, and that is the finding that corrects the
survey.** The survey counted four scanning sites in it. Only one — `commentAt` —
is cursor-shaped. `wordBefore` runs *backwards* from the end of a line;
`markersIn` searches for a substring rather than reading characters; `asCount`
filters every character rather than stopping at one. A cursor is forward,
character-at-a-time, and stops. Counting a program's scanning by eye counted
three things that were not this.

**The conversion was proved rather than asserted.** 38 inputs through
`json:read`, output recorded before and after, identical at the end. It caught
one difference no test covered: `hex4` built on `take` moved before it checked,
so a malformed `\u00` complained about a character four further on than it used
to. The check is asked before the take now.

**And the baseline found a defect that had nothing to do with any of this**:
`json:read` had been unable to read a string containing `\n` since 2026-08-21,
because the escape table was deleted and the two lines reading it were left
behind. Four days, four releases. Two of the 38 inputs were already wrong before
the refactor started.

**The one thing this did not answer** is whether `endsWith` belongs on `string`
for everyone, deferred on 2026-08-24. `scan.sol` did not need it, so it is still
open and still has no program behind it.

#### What the conversions turned up that was not about cursors

Two defects, neither of them in the code being changed.

**`json.sol` could not read a newline**, and had not been able to since
2026-08-21 — found by recording a baseline before the refactor rather than by
looking for it. Two of the 38 inputs were wrong before a line was touched.

**`experiment/prove.sh` built one generation with a different search path from
the others.** `bin/solas experiment/compile.sol` had no `-I lib`, because the
experiment's files only ever included each other; every other invocation had it.
The moment `lexer.sol` included `scan.sol` the fixpoint failed — and failed on
*file names*, because a `.sob` records the file each line came from and
`lib/scan.sol` found two ways is two different strings. Both compilers agreed
about every instruction. The asymmetry had been there since the proof was
written and could not be seen until something crossed it.


## 6. Beyond the language

The rest of this section is live, and is in
[ROADMAP.md](ROADMAP.md#6-beyond-the-language--gone-from-this-document).

### 6.37 `indexOf` cannot say where to start — **done**

**`indexOf(s, #from)`**, a second arity on the message that was already there.

**Two shipped files had written the workaround**, which is the number this
repository has taken to mean *build it* — [6.19](#619-a-symbol-cannot-be-ordered--done)
and [6.23](#623-an-array-cannot-be-popped-or-asked-what-it-holds--done) were
papercuts of the same shape. A second search in the same string could only be
written by copying what was left of it:

```text
lib/pattern.sol     text:copyFrom(from, text:size):indexOf(leader)
programs/expect.sol rest:copyFrom(at:add(marker:size), rest:size):indexOf("-->")
```

**A second arity rather than a second message**, because it is the same
question. `at(key)` and `at(key, default)` set that shape and `run`, `sorted`,
`asString`, `random:new` and `timeToRun` all follow it. The message count does
not move: 138 before and after.

`#from` may be **one past the end**, where the answer is nil rather than an
error — the rule `copyFrom` has, so a walk that runs off the end gets an answer
rather than a fault. Further out is a mistake and says so, as is a float.

#### What it was worth, measured, including where it was worth nothing

**The honest part first.** On the workload that started this — a global
substitution over 50,000 short lines — it is **2.35s to 2.25s**, four per cent,
which is nothing. A short line makes a short copy, and copying a short line is
cheap.

**Where it matters is a long line**, because the copy is quadratic in the length
of one. Searching a single 80,000-character line for a pattern with a common
first character and no match:

| | |
| --- | --- |
| copying the tail at every candidate | 0.14 s |
| searching from a position | **0.05 s** |

Minified JSON, generated code and a log line are all one long line, and the
editor will meet one. A megabyte on one line would have been twenty seconds and
is now under a second.

**And the second customer got shorter rather than faster.**
`programs/expect.sol` walked its markers by cutting the line down after each
one, with arithmetic to keep track of where the cuts had come from. It walks an
index over one string now: four lines shorter, one variable fewer, and the
copies gone. That is the better argument of the two — a primitive that lets a
program say what it means removes the bookkeeping that saying it another way
required.

### 6.36 `readLine` and `readKey` did not share an input buffer — **done**

**A program that called `readLine` and then `readKey` lost input, silently.**

```text
printf 'one\nXY\n' | solvm program.sob     # readLine → "one";  readKey → nil
```

`readLine` read through stdio, which reads a **block** ahead into the C
library's buffer. `readKey` — and `keyWaiting` — read the file descriptor
underneath it. The bytes that arrived in the same block as the line were held
where `read` could not see them, and nothing said so.

**It was found by reading the code rather than by being bitten**, an hour after
[6.35](#635-a-read-that-gives-up--done) had been built on top of it. The comment
above `readKey` claimed the two were *"kept from disagreeing by flushing what
stdio holds before going underneath it"* — and there was no such flush, and
there cannot portably be one: `fflush` on an input stream is undefined in C. The
comment described an intention. **Every other entry on that list came from
somebody wanting something and not getting it; this one came from somebody being
told they already had it.**

#### What it is now

`solum/src/stdin.c`, a window over standard input that everything reads
through — `system:readLine`, `system:readKey`, `system:keyWaiting`, and **Solis'
own reader**, both the line editor at a terminal and the plain reader behind a
pipe. Four kilobytes, filled by one `read`, handed out as lines or as bytes.

**It belongs to the process, not to a VM.** Standard input is one descriptor
however many machines are pointed at it, and a per-VM buffer would divide what
the operating system does not. `sol_vm_init` forgets whatever is held, which is
what lets a test replace stdin between cases and start clean — and is the one
place the process-wide thing and the per-VM thing touch.

**The terminal modes moved there too**, out of `builtins.c`. A byte is read in
non-canonical mode so a keypress needs no newline; `keyWaiting` sets the same
mode for the length of its question. `readKey` is four lines now.

#### Three things that came with it

**`keyWaiting` had to learn about the window**, or one buffer would have been
worse than two: it would have answered *nothing is coming* while holding a byte.
It answers true for a held byte without asking the system anything.

**Solis is exact now rather than nearly.** The reference has always said *the
program and the prompt are reading the same input*; behind a pipe, the prompt
read a block ahead through `fgets` and a script asking for a key got whatever
was left. Both of Solis' readers take from the window, and its
`sol_input_read_line` lost its `FILE *` parameter — it reads standard input,
which is the only thing it was ever given.

**A line may hold a NUL.** `fgets` plus `strlen` ended a line at the first one
and threw the rest of the line away; taking the line by length makes `readLine`
agree with `readFile`, which has always kept them. That was not the point of the
change and is the best thing in it.

#### What it does not change

**Reading ahead still reads ahead** — up to four kilobytes from a pipe or a
file. That matters only when another *process* wants the same input: a program
that reads a line and then hands standard input to a child with `run` may find
the child short of what the window holds. It was true of stdio's buffer before
and is true of this one now, with the difference that it is this repository's
behaviour to describe rather than the C library's to discover. A terminal is
unaffected: it delivers a line at a time, so nothing is taken that was not asked
for.

### 6.35 A read that gives up — **done**

**`system:keyWaiting(seconds)`**, answering true or false: is there a byte to
read, waiting up to that long for one to arrive.

**The oldest known gap in this language, and the one with the longest paper
trail.** [6.10](#610-waiting-for-a-single-key--done) closed with a paragraph
headed *what it cannot do*: tell the escape key from the start of an escape
sequence, because an arrow is three bytes and `readKey` answers one and blocks.
[examples/keys.sol](../examples/keys.sol) said the same thing on the day it was
written, and ended *"worth knowing before writing anything that binds the escape
key on its own"*. Nothing bound it. The warning sat there, correct and untested,
until [programs/edit.sol](../programs/edit.sol) bound it to the most frequent
action a modal editor has and found that escape did nothing until the next key
arrived.

**A question, not a second reader.** The obvious shape is `readKey(seconds)`
answering the byte or nil, and it has a collision in it: **nil already means the
end of input**, which is how every read loop in this language finishes. Adding
*nothing yet* to the same answer leaves a program unable to tell *there is
nobody there* from *they have not typed yet* — the first final, the second
normal, and a loop that confuses them either spins for ever or stops early. So
`readKey` is untouched and this answers a boolean. Two messages, each with one
meaning.

**True at the end of input**, where the `readKey` after it answers nil. That is
the coherent pair: there is something to read, and what is there is the end.

**Seconds as a float**, like every other duration here, and `0.0` is a question
about right now. A negative wait is refused rather than taken for *wait for
ever*, which is what `poll` would make of it — a hidden mode reached by a sign
is not an interface.

#### What it cost to get right, which was not the poll

Fifteen lines of `poll` and a boolean, and then a bug that no test in this
repository could have caught, because every test here reads through a pipe.

**A terminal in canonical mode holds what is typed until a newline.** `readKey`
sets non-canonical mode for the length of one read and puts it back, so between
two reads the terminal is canonical again — and a `poll` there is told that
nothing has been typed however much has. The arrow keys this message exists to
recognise stopped working the moment it was used, their `[` and `B` sitting in
the driver's line buffer where `poll` cannot see them. **A pipe has no line
discipline**, so all 118 of the editor's behaviour checks and every C test
passed either way.

It was found on a pseudo-terminal, by driving the editor through one and
pressing an arrow. The fix is the same raw-mode dance `readKey` does, around a
call that reads nothing:

    tcsetattr → poll → tcsetattr back

and the test that pins it makes its own pseudo-terminal, writes `[B` with no
newline, and asks. Without the dance that test fails and every other test in the
suite passes.

#### What it did not know about, for one hour

`readLine`'s buffer. This read the file descriptor, like `readKey`, and neither
could see bytes the C library had already read ahead — so `keyWaiting` would
answer *nothing is coming* while a byte sat in stdio.

**That is [6.36](#636-readline-and-readkey-did-not-share-an-input-buffer--done),
opened an hour after this landed by reading the code beside it, and closed the
same day.** There is one window over standard input now, and `keyWaiting` was
taught about it rather than left underneath it: it answers true for a held byte
without asking the system anything, which is the first line of
`sol_stdin_waiting`.

Left recorded rather than deleted, because it is the reason the two entries had
to land together. **One buffer would have been worse than two** had this half
been forgotten — a poll that cannot see what the reader is already holding does
not fail, it answers *nothing is coming*, confidently and wrongly.

### 6.34 A program cannot ask how big the terminal is — **done**

**`system:terminalSize`**, answering a dictionary of `"rows"` and `"columns"`,
or **nil** when the output is not a terminal.

**The program that wanted it was [edit.sol](../programs/edit.sol)**, and it
wanted it in its first hour, exactly as
[ideas.md](ideas.md#programs-that-would-press-on-something) predicted it would
before the editor was written. That prediction is the only one of the four on
that list that was made about an absence already confirmed rather than guessed
at, which is why it is the one that closed the same day.

**What the workaround was, and what it cost.** There is no environment variable
to read — `COLUMNS` and `LINES` are shell locals and are not exported, so a
program sees neither — so the only route to the number was to run a program that
asks the kernel and read what it printed:

| asked | each ask |
| --- | --- |
| `stty size` through `/bin/sh` | 7.0 ms |
| `stty size` with no shell | 2.3 ms |
| `system:environment`, which does not answer the question | 0.0002 ms |
| the ioctl this message is | about 0.001 ms |

7ms is a fork, an exec and a pipe **per keystroke** if the size is asked for on
every redraw, so the editor asked once at startup instead — and a window resized
after that was a window the editor drew wrong until it was restarted. **That is
the whole finding**: not that the number was unreachable, but that reaching it
cost enough to change the design around it.

**And the obvious second answer is worse.** `tput lines` down a pipe answers the
terminfo default rather than failing — 24, confidently, whatever the screen is —
which is a wrong number that looks like a right one.

#### The four decisions in it

**One message answering both numbers**, rather than `rows` and `columns`. Two
asks can straddle a resize and compose a screen that never existed: an old width
with a new height. One ask cannot, and there is no version of this where two
messages are the safer pair.

**A dictionary**, the way `capture` answers `"output"` and `"status"`. An array
would be two integers in an order the reader has to remember, and rows and
columns are precisely the pair that everybody remembers backwards.

**Nil rather than 24 by 80**, which is what `readLine`, `readKey` and
`environment` all answer for absence. A default is a lie a program cannot see
through, and what to do without a terminal is the program's decision and not the
language's: an editor picks a size, a pager gives up, a report ignores the
question. edit.sol picks 24 by 80 — in its own file, where a reader can see it.

**The output's size**, not the input's. That is where the drawing goes, and it
means a program whose standard input is a script and whose output is a terminal
still gets a true answer — which is what makes a full-screen program testable at
all. One whose output is a file gets nil, which is the truth about the file.

#### What it deliberately does not do

**There is no notification that the size changed.** A resize is a signal,
`SIGWINCH`, and the language has no signals and gains none here. It does not
need them at this price: one system call per redraw is about a microsecond, so a
program that draws can measure every time it draws and never be wrong for longer
than one frame. edit.sol does exactly that, in three lines with the reason
written beside them. **The cheap ask is what makes the missing signal not
matter**, and if the ask had stayed at 7ms this entry would have had to answer a
much larger question.

#### Testing it

The suite makes its own terminal: `posix_openpt`, `grantpt`, `unlockpt`, a
`TIOCSWINSZ` of a size the test chose, and `dup2` over standard output for the
length of one run. `openpty` would have been shorter and wants `-lutil` on
Linux, which the front page's *no dependencies beyond a C11 compiler and make*
does not allow. So the size is arranged rather than inherited, and the test says
31 by 101 because a real terminal never is.

The three allocations — the dictionary and its two key strings — are one root
and a GC-stress case. Removing the root and running under ASan reports a
heap-use-after-free inside `sol_dict_put`, which is the proof that it is
load-bearing rather than decorative.

### 6.1 There is no way to split a program across files — **done**

Nothing above a few hundred lines fits in one file, and there is no `include`.
This is the item a real program hits first.

The mechanism is easy — Solas reads the named file and compiles it in — and the
question is the namespace. Globals are one flat space, so textual inclusion is
consistent with what exists: names collide, and the second definition wins,
exactly as two `:=` in one file already do. A module system with its own
namespace is a much larger change to the object model and would want the
class-side question (2.5) settled first, since a module is a thing with two
sides.

Start textual. Record the collision rule, and whether a file included twice is
compiled twice.

Built as `8922138`, and textual it stayed: `"library.sol":include.` compiles that
file in at that point, the namespace stays flat, and a file included twice is
compiled *once* — a second copy could only rebind names already bound and repeat
whatever the file did on the way, and C's alternative needs conditional
compilation that Solum has not got. The rules are in
[REFERENCE.md](REFERENCE.md#splitting-a-program-across-files).

The spelling did not survive. It was `"library.sol":include.` here, and that
shape was a disguise: it read as a send to a string and never was one. It is
`@include "library.sol".` now — see [6.13](#613-include-was-spelled-as-a-message--done)
for what the disguise cost and why the sigil was worth introducing.

### 6.2 A `system` object — **done**

`system:exit(code)` is the difference between a script and a program: there is
currently no way to say *stop, and here is why*. Alongside it, the two other
things a program asks the world for: its arguments, and the time.

- `system:exit(#0)` — leave with a status.
- `system:arguments` — an array of strings.
- `system:clock` — monotonic, for 6.5.

Small, self-contained, and the natural home for anything else that is about the
process rather than about a value.

Built as `e8d4fe8`. All three, and the shape they took: `system` is one object
bound to a global rather than a class, since there is one process and it has no
instances. `exit` **unwinds** rather than calling `exit(3)`, so every frame is
discarded the way an error discards them and whatever the C library was holding
is flushed on the way out; a status is #0 to #255 and anything else is refused,
POSIX keeping only the low eight bits. `arguments` turned out to want no
primitive at all — it is a data slot holding an array, which is what it is.
`clock` is monotonic seconds as a float, the epoch left unspecified because only
differences mean anything. The rules are in
[REFERENCE.md](REFERENCE.md#the-program-and-its-process).

### 6.3 Reading input — **done**

`system:readLine`, answering a string or nil at end of input. A few lines of C,
portable, and enough for anything that reads a file line by line or prompts.

Built as `4aefa0c`. `system:readLine` answers a line without its terminator, or
nil at the end -- the one place absence is not treated as a mistake here, since
running out of input is how a loop that reads to the end finishes rather than
something that went wrong. An empty line is `""` and is not the end, so the two
never get confused. `\r\n` counts as one terminator and a last line with no
newline of its own still counts as a line.

The half of this entry about waiting for a single key stayed behind, under a
number of its own: [6.10](#610-waiting-for-a-single-key--done), which is
still open. `solis` grew raw-mode line editing for its own prompt in
[6.24](#624-the-prompt-has-no-history--done), which needed the same machinery and
is not the same thing: that is the front end reading keys, where 6.10 is a
message a *program* can send.

### 6.4 File handling — **done**

Whole-file first, which covers most of what a script does:

- `"path":readFile` — answers the contents as a string.
- `"path":writeFile(text)` — replaces the contents.

Errors are the design work rather than the reading: the language has no
exceptions, so a missing file has to be a runtime error like any other, or
answer nil and make every caller check. Given how strict everything else is, an
error is the consistent choice, and a `system:fileExists` gives the caller a way
to ask first.

Built as `63bb836`, and on `system` rather than on the string naming the file —
`system:readFile(path)`, `system:writeFile(path, text)`,
`system:fileExists(path)`. `"notes.txt":readFile` reads better and is what this
entry sketched, but a string knows nothing about files, `system` is already
where what belongs to the world outside the program lives, and — at the time —
`"lib.sol":include` already meant something quite different on a string literal.

That third reason has since dissolved: [6.13](#613-include-was-spelled-as-a-message--done)
made an include `@include "lib.sol"`, which looks like nothing else, so there is
no longer a collision to avoid. The decision stands on the first two reasons,
which were the load-bearing ones.

The error question this entry called the real work went the way it predicted: a
missing file is an error, the same answer an out-of-range index gets, and
`fileExists` is how to ask first. It answers false for a directory, since that is
what `readFile` says about one too — a `fileExists` that disagreed with `readFile`
would be a trap rather than a way to look before leaping.

The binary half stayed behind, under a number of its own:
[6.12](#612-taking-a-binary-file-apart--done). And a gap this opened is
[6.11](#611-a-string-cannot-be-split--done) — a file arrives as one string
and there is no way to take it apart.

---

### 6.5 Measuring from inside the language — **done**

Every performance number in the changelog was taken with `/usr/bin/time` around
a whole process. Timing a block from inside Solum would be better, and was a few
lines once [6.2](#62-a-system-object--done) had provided `system:clock`:

```
{ #20:factorial }:timeToRun:print.
```

The design question the entry named was what it answers, and a float of seconds
was the obvious choice for the reason it gave: it is the only answer that needs
no duration type. It also subtracts and compares like any other number, and
`asString(".3")` already formats it.

Built as `661408d`. The block's own answer is dropped — what was asked for was
the time, and a message answering both would have to answer an array or an
object, which is worse to take apart than writing `{ ... }:value` when the
answer is wanted too.

**The entry missed something, and it changed the shape.** The clock has a floor.
On the machine this was written on it is a microsecond — `clock_getres` says so
and so does watching the smallest step between two readings — while one send and
one add costs well under a tenth of that. So a single run measures the floor
rather than the block: `0` most times, one whole microsecond when the two
readings fall either side of a tick.

That is fatal to the entry's own purpose. The numbers it wanted to take from
inside the language, rather than with `/usr/bin/time` around a process, are all
sub-microsecond. Without a repeat count the message cannot measure any of them.

So `timeToRun(#n)` as well, running the block `n` times and answering the
**total**. The total rather than the average, because the total is the
measurement and the average is a division the caller can do — and keeping the
count in view is what says whether the floor was cleared. A count below `#1` is
refused: the answer would be `0.0` whatever the block, which tells you nothing
and is more likely a mistaken count than an intention.

What is measured includes the cost of calling the block, a frame pushed and
popped. That is not overhead to subtract; it is what running the block costs.

This is also what [6.6](#66-the-loop-constructs-are-library-code-and-pay-for-it--done)
was waiting for. Inlining the loop constructs buys speed rather than
expressiveness, and now the Solum-written version and the inlined `whileTrue`
can be measured against each other before anything is built.

---

### 6.7 The instruction set has no complete reference — **done**

design.md had a table of the instruction set that was **missing six opcodes** —
`OP_JUMP`, `OP_JUMP_IF_FALSE`, `OP_EXIT_IF_FALSE`, `OP_LOOP`, `OP_CHECK_BOOL`
and `OP_SYMBOL`. That is every jump and the two newest, so the table described
the machine as it was before 4.1.

The disassembler printed all of them and `bytecode.h` documented each one at its
definition, so the material existed and the document had fallen behind. The
entry asked for a reference page generated from, or at least checked against,
the header — the same problem the examples solved by being compiled in the test
suite.

Built as `8d7c558`. [BYTECODE.md](BYTECODE.md) describes all twenty-one opcodes:
operands, instruction length, effect on the stack, and why the three jump
instructions carry a name index they never push. design.md keeps the
operand-width rule and points at it, having no table of its own any more.

**Checked rather than generated**, and three ways, by `tests/test_bytecode.c`:

- every opcode the header defines appears in the document — the check that would
  have caught the six that went missing;
- every `OP_` name in the document still exists in the header, which catches the
  opposite drift;
- every instruction length the document gives matches `sol_op_length`, so a row
  saying three where the executor reads five cannot sit there sending a reader
  off by two on every following offset.

None of it needs a list of opcodes maintained in the test. **The names come out
of the enum in the order they are written, which is also their value**, since a C
enum with no initialisers numbers from zero upwards — so the header alone gives
name and value both, and the check has nothing of its own to fall behind in.

Writing that parser was where the one real mistake was. Taking any `OP_` at the
head of a line gave twenty-three opcodes rather than twenty-one: the comments
wrap, and `OP_JUMP_IF_FALSE only in the complaint it makes` begins a line too.
Two phantom members shifted every value after them, which showed up as
`OP_JUMP_IF_FALSE` apparently being three bytes long. What separates a member
from a mention is what *follows* it — a comma, or the comment when it is the
last one.

All three checks were then confirmed to fail when they should: a renamed opcode,
a removed one, and a wrong length each stop the suite with a message naming the
file and the opcode. The three disassembly listings in the page were diffed
against real `--dump` output rather than transcribed.

---

### 6.8 `(group)` and `{block}` are not contrasted anywhere — **done**

Both are code in brackets; one evaluates now and one is a value. The tutorial
introduced each separately and never put them side by side, which is where the
difference actually lands.

Built as `4001efa`: a subsection at the end of the guide's §7, a short one in
the reference beside `Grouping`, and a section in
[examples/blocks.sol](../examples/blocks.sol) so the concept has runnable code
and not only prose.

The entry supplied the example and it is the one used:

```
m := { x | x:add(#1) }.
(m:value(#42)):print.            ; #43
{ m:value(#42) }:print.          ; <block>
```

Writing it up turned up a better one, though, and it is the reason the contrast
matters rather than a curiosity about brackets. **An argument is evaluated before
the send, like any other argument.** So handing `ifTrue` a group means the group
has already run by the time `ifTrue` gets to decide anything:

```
false:ifTrue(("the group ran anyway":display. nil)).
false:ifTrue({ "the block did not":display }).
```

Only the first prints. Nothing in the compiler knows what `ifTrue` means; the
block simply has not been run, and `ifTrue` chose not to run it. Every
conditional and every loop in the language rests on that one fact, and a reader
who has not seen a group and a block side by side has no way to see it.

The third difference is frames, and it explains a restriction §3 already
describes without saying why: **a block makes a frame, a group borrows the one
it is in.** A group's temporaries are the enclosing block's, which is why a group
may declare them only somewhere that already has a frame, and why declaring one
at the top level of a script is refused.

---

### 6.9 The examples do not cover everything — **done**

Seventeen examples, chosen by what was being built at the time rather than by
what a reader needs. The entry asked for an audit: list every concept the guide
names, find which have no example, and fill the gaps rather than adding more of
what is covered.

The audit was run two ways, and **the answer was not the one the entry
assumed.**

Against the guide, five of its nineteen sections pointed at no example: §2 names
and binding, §3 statements and groups and temporaries, §11 overriding and `via`,
§14 fetching a method, and §16 errors and strictness.

Against the built-in messages — every selector registered in `builtins.c`, which
is the sharper question — **exactly one had never been sent in any example**:
`lessOrEqual`. Coverage was far better than "chosen by what was being built at
the time" suggests. The gaps were conceptual rather than material, and two of
the five were not gaps at all: `via` was in objects.sol and `slotAt`/`boundTo`
were in reflect.sol, neither pointed at from the section that teaches them.

Built as `8a2546c`:

- **[binding.sol](../examples/binding.sol)** for §2 and §3 — the plumbing every
  other example uses without stopping to look at it. `:=` meaning one thing
  everywhere, a computed method falling out of that, `.` separating rather than
  terminating, a leading `:` continuing a line, groups, and where a temporary
  may be declared.
- **[strictness.sol](../examples/strictness.sol)** for §16 — every refusal with
  its real error text and what to write instead. It **ends by failing on
  purpose**, three frames deep, because a stack trace is the one thing in that
  section no working program can show you.
- Pointers added for §11 and §14, which needed nothing else.
- `lessOrEqual` now sent, in strictness.sol.

Every section but §19, which is prose about what is left, now points at
something runnable, and all sixty-five built-in messages are sent by at least one
example.

**And the audit is now a test**, for the same reason 6.7's reference is:
`tests/test_compile.c` reads the registrations out of `builtins.c` and checks
each selector is sent by some example, with `;` comments blanked out first so a
message that only appears in an error transcript does not count as covered. That
blanking respects string literals, because files.sol has a `;` inside one. A
second check walks `examples/` and refuses any `.sol` missing from the list the
file verifies, so an example cannot ship unchecked.

Both were confirmed to fail when they should. Commenting out the single
`lessOrEqual` send makes the first one name it.

One thing the audit turned up that was not about examples at all: index.md said
**"Twelve programs"** and listed twelve, while seventeen shipped. It lists all
nineteen now.

---

### 6.11 A string cannot be split — **done**

`readFile` answers a whole file as one string, which is what made this visible:
there was no `split`, no `indexOf`, and no substring. `at(#i)` answers a
one-character string, so breaking a file into lines was a character-at-a-time
loop — [examples/files.sol](../examples/files.sol) had one, and it was the least
pleasant code in the examples.

The shape was not in doubt, only how much of it to build. `split(separator)`
answering an array of strings covers most of what a script does to a file.
`indexOf` and a substring message are the more general pair, and each raised the
same question: what to answer when there is no match. Nil, or `#0` as an
out-of-band index — and the first is more in keeping, since `#0` is not a valid
index here and would be a second way of saying "nothing" beside the one the
language already has.

Built as `4d35540`, all three: `split(s)`, `indexOf(s)`, `copyFrom(#a, #b)`.

**`split` keeps every piece.** There are always occurrences + 1 of them, so a
separator at either end or two together gives an empty string where the missing
piece would be. That is what makes the answer predictable: the pieces put back
together with the separator between them are the string you started with,
whatever it was. Dropping empties reads more kindly on `" a  b "` and loses the
difference between `"a,,b"` and `"a,b"` — which a program parsing a file is
usually the one thing that matters to it. No occurrence gives one piece, the
whole string, which keeps the rule rather than making a special case of it.

**`indexOf` answers nil**, as the entry expected. The argument for it got
stronger on the way: `#0` would not merely be out-of-band, it would be a second
spelling of a thing the language already spells, and `text:indexOf(","):equals(nil)`
is the same question that an unset slot and the end of input are already asked.

**`copyFrom` includes both ends** and both are one-based, so `copyFrom(#i, #i)`
is exactly `at(#i)`. The one thing this entry did not anticipate was needing to
say *nothing*: cutting a string at a mark has no answer for the front half when
the mark is the first character. So an empty result is spelled with `to` one
before `from`, and only that far — anything further apart is a mistake rather
than a wider empty. `from` may be one past the end, which is where the empty tail
is.

Neither `split` nor `indexOf` will look for the empty string. Every position in
every string contains it, so the answer would be arbitrary; refusing says so
where the mistake was made.

All three go by the length rather than stopping at the first NUL, which was not
free — `strstr` was the obvious implementation and would have been wrong on
exactly the files [6.12](#612-taking-a-binary-file-apart--done) is about. A
test reads a file holding a NUL and splits it.

The inverse was left out and is [6.14](#614-an-array-of-strings-cannot-be-joined--done):
there is no `join`, so putting pieces back is still a walk with `do`, and
underneath that there is no `inject` or `fold` either.

---

### 6.13 `include` was spelled as a message — **done**

[6.1](#61-there-is-no-way-to-split-a-program-across-files--done) built the include and
spelled it `"library.sol":include.`, for the honest reason that the language had
no directive syntax and no keyword to spare, and that shape already parsed.

It was a disguise, and the compiler paid for it in three places. `statement`
copied the lexer and looked **two tokens ahead** to spot one before the string
had been consumed. `primary` carried a special error — *an include must stand
alone as a statement* — because the shape parsed everywhere and worked in one
place. And `include_follows` existed at all, a probe nothing else in the grammar
needed.

The cost that mattered was not in the compiler though. A construct that looks
like ordinary syntax and obeys different rules teaches the wrong model: a reader
who accepts `"lib.sol":include` as a send has learned that a send might happen
at compile time, and that is not true of any other send in the language. It is
the objection that sank the trailing-block shorthand in
[ideas.md](ideas.md), and it applies harder here — the shorthand would at least
still have been a message.

One argument for keeping it nearly held: that in Solum everything happening at
run time has a colon in it, so a colon-free statement already reads as not-a-send
and no sigil is needed. It is false. `x.` is a legal statement, colon-free and
entirely a run-time one.

So `@`, and a distinct token rather than a keyword:

```
@include "library.sol".
```

The token is `@include`, `@` and all, which is why this costs nothing anywhere
else. There is no lookahead — a directive announces itself at its first
character. There is no reserved word — no identifier can begin with `@`, so
`include` stays an ordinary name any object may use for a slot. The probe and
the special-case error are both gone, and `primary` now only has to say that a
directive belongs on its own.

`@` names a space rather than one word: what follows it happens while compiling,
and nothing in it is a message. An unknown directive is refused rather than
passed through, since a name in the compiler's own space that the compiler does
not know is a mistake and not something that might come to mean something later.
`@include` is the only member so far, and the space may never have a second one
— it earns its keep with one, by marking the single construct in the language
that is not run time.

Built as `e215440`. Semantics are untouched: the same splice into the includer's
scope, the same resolution relative to the including file, the same
once-per-compilation keying by where the file turns out to be on disk, the same
cycle stop.
---

### 6.14 An array of strings cannot be joined — **done**

[6.11](#611-a-string-cannot-be-split--done) built `split` and left its inverse out.
Putting the pieces back was a walk with `do` and a flag for whether the
separator goes in front — six lines to say something that ought to be one.

The entry asked a larger question first, and it was the right one to ask: there
was no `inject` or `fold` either, so *every* reduction over an array was that
same walk with an accumulator declared outside it. `join` was one instance of a
gap, not the gap.

Built as `72df16b`, and both. The entry set them against each other — a fold
answers the gap once, where `join` is the case that keeps coming up — but that
was a false choice, and building one showed why. A fold **cannot** express
`join` well: the separator goes between pieces rather than before each, so
folding one needs a flag or a test for the empty accumulation, which is the very
six lines being replaced. They are not the general and the specific case of one
thing. They are two things.

**`inject(start, block)`** completes the iteration messages. `do` throws its
answers away, `collect` and `select` each answer an array, and this answers one
value. An empty array answers `start` without calling the block, so a fold is
safe to write without asking first whether there is anything to fold. What
accumulates need not be the elements' type. And unlike `do` it is an expression,
so a reduction can stand in the middle of one rather than only at the top of a
frame where an accumulator could be declared — which was the real cost of not
having it.

**`join(separator)`** is on array rather than on string, because it is the array
that has the pieces. Strict about them: an array holding anything but a string is
an error rather than a silent `asString` on each, since `asString` and `fill` are
already the messages that render things and a second quiet route to the same
place is worth refusing.

Its separator **may** be empty, where `split`'s may not, and the asymmetry is
not an oversight. Nothing can be looked for — every position in every string
contains the empty string — but putting nothing between the pieces is exactly
concatenation.

`s:split(sep):join(sep)` is `s`, for every string and every separator. That
round trip is what `split` keeping its empty pieces was for, and it is now
testable rather than merely argued.

One note on the collector. `inject` holds its accumulated value on the value
stack for the length of the fold, since `sol_gc_push_temp` cannot hold an
integer or a nil — neither has a header to push. That root is **defensive rather
than load-bearing**, and taking it out passes under `SOLUM_GC_STRESS=1`:
`sol_vm_call_block` pushes the receiver and arguments before it can allocate, so
the value is already rooted wherever a collection can happen. It costs one stack
slot and buys not having to rely on what another function does with its
arguments, across an unbounded number of calls back into the language.


---

### 6.12 Taking a binary file apart — **done**

Reading and writing binary files always worked: a string is bytes, a NUL is a
byte like any other, and `split`, `indexOf` and `copyFrom` all go by the length
rather than stopping at the first NUL, so a binary file could be cut up by a
marker. What was missing was a **number** for a byte — `at` answered a
one-character string, and there was nothing to do arithmetic on.

The entry proposed a **byte-buffer type**, and said an array of integers would
work at sixteen bytes a byte. It also said to build it when a program needed it
rather than on the chance that one might, and that turned out to be the load-
bearing sentence: when a program finally needed it, it wanted something much
smaller.

**The program was not the one expected.** This entry was written about binary
files. What needed a byte's number first was *text* —
[lib/json.sol](../lib/json.sol) has to read `\u0041` and answer `"A"`, and write
a control byte back out as `\u00XX`. Neither direction existed, so the library
carried the printable ASCII range as a string literal to index into and refused
everything else, `é` included.

**What was built is two primitives and no new type:**

```
"A":asByte:print.            ; #65
#65:asCharacter:display.     ; A
```

`asByte` takes a one-character string and answers an integer; `asCharacter`
takes an integer `#0` to `#255` and answers a one-character string. Both ends
already existed, which is why this is two functions in `builtins.c` rather than
a type with a representation, a printer, a GC visit and a `.sob` encoding.

**Named for what each answers**, which was a decision rather than a shrug. A
string is bytes ([2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only)),
so `asByte` is honest where `asCode` would have promised a code point:

```
"é":asByte.
solvm: 'asByte' wants one byte, and this string has 2 -- a character outside ASCII is more than one of them
```

Refusing is what keeps the pair exact inverses, and the test is the whole range
rather than a sample of it: every byte `#0` to `#255` survives
`asCharacter:asByte`.

**It is a foundation and not a fix, which is the good part.** A code point above
127 is more than one byte, so `#233:asCharacter` is Latin-1 rather than the two
bytes UTF-8 spells `é` with. Encoding a code point is *arithmetic* once a number
can become a byte — and arithmetic belongs where the format is known. So the
UTF-8 encoder lives in `lib/json.sol`, in Solum, and reaches all of Unicode:

```
json:read("\"caf\u00e9\"").          ; café          -- two bytes
json:read("\"\u4e2d\u6587\"").       ; 中文           -- three bytes each
json:read("\"\ud83d\ude00\"").       ; 😀            -- a surrogate pair, four bytes
```

Solum has no bitwise operators, so the shifts and masks are `div` and `mod` and
the tag bits go on with `add` — exact, the bits being disjoint by construction,
and it reads about as well as the C would.

**One thing came free.** There is no `\0` in a string literal, so
`#0:asCharacter` is the only way to write a NUL. Strings are length-counted
rather than NUL-terminated and already carried one through `readFile` and
`writeFile` byte-for-byte, so this added a spelling rather than a hazard.

**What is still not here** is the byte-buffer type the entry opened with, and
nothing is asking for it. A byte from a string is a number now, which is what
every use met so far actually wanted. If a program turns up that needs a large
mutable buffer, that is a new entry with its own case, not this one reopened.

### 2.5 Class side versus instance side — **closed**

The last open question in the language, and it is closed by **not** splitting the
objects — because the thing the split was for turned out to be reachable without
it.

`integer` holds both `new` and `add` in one object. The complaint was that
nothing separates the two audiences, and the fix on offer was a behaviour object
per built-in, with a class-to-behaviour link that `isKindOf` and all four
reflection messages would have to follow.

**What was actually wrong was smaller and worse.** Three messages — `new`,
`slots` and `slotAt` — were registered for *any* receiver and then refused a
value from inside the primitive. So `respondsTo` said one thing and sending did
another, which is precisely what `respondsTo` is documented not to do:

```
#45:respondsTo('new).       ; true
#45:new.                    ; an integer is written #45, and there is nothing for 'new' to make
```

And the same shape let an instance answer a class-side message:

```
[#1]:new.                   ; []          -- a fresh empty array
[#1]:of(#2, #3).            ; [#2, #3]
dictionary:new:new.         ; <dictionary>
```

**The fix is that every class-side message requires an object receiver** —
`new`, `of`, `fromSeconds`, and the reflection that needs an object to look
inside. Ten registrations changed from `any_receiver` to `instance(..., SOL_OBJ,
...)`. All four of those sends are refused now, and `respondsTo` agrees with
sending everywhere.

The teaching errors survive, because they were always for the *class*:

```
integer:new.
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one
```

**The line between the two sides is drawn by the receiver each slot requires**,
rather than by which object holds the slot. That is the rule this entry said had
nowhere to live, and it lives in the registration table now, where the compiler
checks it: a slot that takes SOL_OBJ is class side, a slot that takes a value
type is instance side.

The two sides are separable from inside the language, and every slot belongs to
at least one:

```
integer:slots:size.                                            ; #30
integer:slots:select({ s | integer:respondsTo(s) }):size.      ; #8   -- class side
integer:slots:select({ s | #45:respondsTo(s) }):size.          ; #27  -- instance side
```

Eight and twenty-seven overlap by five, and the five are `isKindOf`, `isNil`,
`notNil`, `perform` and `respondsTo` — reflection that genuinely serves both
audiences, which is the right answer rather than an oversight. **Nothing is on
neither side**, and there is a test asserting exactly that.

**What the split would still buy, and why it is not worth it.** `integer:slots`
answers 30, listing both audiences. That is honest — they *are* its own slots —
and it is now explicable in one sentence with a filter to demonstrate it. The
split would make it 8 by moving 22 elsewhere, at the cost of a second object per
built-in and a link every reflection path must keep honest.

**The trigger to reopen this**: when `slots` on a built-in class is read by a
program rather than printed by an example. In four programs written to do a job
and four libraries, reflection on a built-in class appears exactly once —
`integer:slots:size:print` in `examples/reflect.sol`, printing a count. Until
something reads that list and has to care which audience it is looking at, the
filter is enough.

### 6.23 An array cannot be popped, or asked what it holds — **done**

Both found by [lib/html.sol](../lib/html.sol), which keeps a stack of open
elements — the thing parsing a nesting format wants, and the thing an array did
not quite serve. Both workarounds were written and shipped before the messages
were, which is what made the case for them.

**`removeLast`** takes the last element off and answers it. The workaround had
been an object carrying its own `top` index, overwriting with `atPut` rather
than shrinking — eight lines, written twice in one file before being factored
out. The library is a plain array again:

```
html:push := { e | self:open:add(e). e }.
html:pop  := { self:open:removeLast }.
```

**It refuses an empty array** rather than answering nil, which was the decision
in it. `at` already refuses an index out of range, and nil would be a second way
of saying "nothing" beside the one the language has — worse, it would turn a
mistake into a value that fails somewhere further on. A caller that might be
empty asks `size` first, which is the shape a stack's loop condition already
has, so nothing is made harder by the strictness.

**`indexOf`** answers a one-based position or nil, exactly like
[`string:indexOf`](REFERENCE.md#string). The library's element-name sets had
been *strings* searched with the delimiters kept on so that `p` did not match
`pre` — the trick every shell script uses, for the same reason. They are arrays
now.

**And no `includes`**, which the entry had been unsure about. `indexOf(v):notNil`
is that question, so a second message would answer less with more surface: one
that says *where* is worth more than one that says only *whether*. The entry's
argument against `includes` — that a dictionary answers set membership in O(1)
and an array cannot — survives; what it missed is that `indexOf` earns its place
by answering something a dictionary cannot.

Equality is `sol_value_equals`, the one the language uses everywhere: by content
for values, by identity for arrays, blocks, objects and dictionaries.

```
["a", "b", "c"]:indexOf("b").    ; #2
[[#1]]:indexOf([#1]).            ; nil  -- an equal-looking array is a different one
```

### 6.30 A program cannot run another program — **done**

`system:run(argv)` and `system:capture(argv)`, and
[lib/shell.sol](../lib/shell.sol) over them.

**The first entry raised after the list emptied**, and it came the way the list
says entries come: something was wanted and could not be had. A language aimed
at scripting an OS that cannot invoke another program is doing the job with one
hand — most of what a shell script does is arrange other programs.

**An array of arguments, not a command line**, which is the whole decision:

```
system:run(["rm", name]).       ; one argument, whatever `name` holds
```

A file called `; rm -rf ~` is a *name* there, because it is one string. Handed
to a shell as text it is a sentence. Every scripting language that took the
convenient form regrets it, and the regret is a deleted home directory rather
than a lint warning. Demonstrated rather than asserted: a directory holding a
file of exactly that name survives being listed and measured.

**The shell is reachable and spelled out**, `["/bin/sh", "-c", "..."]`, which
says what it is doing where it is done. `lib/shell.sol` wraps that with `run`,
`capture`, `read` and `line`, so the convenience is one line away and the hazard
is named in the file that takes it rather than hidden in a primitive.

**`capture` answers a dictionary** of `"output"` and `"status"` rather than the
text alone, because a command's output is worth little without knowing whether
it worked: `grep` finding nothing is not `grep` failing, and only the status
separates them.

**Conventions taken from the shell rather than invented.** A command that cannot
be run answers `#127`; one killed by a signal answers 128 plus the signal.
Neither raises — a script asking whether a tool is installed is asking a
question, not making a mistake.

**Reading before waiting.** `capture` drains the pipe and only then waits for
the child, because a program writing more than a pipe holds would block forever
against a parent waiting for it to exit. Tested with 1.3 MB of output.

### 6.31 Text from another program arrives padded — **done**

`string:trim`, wanted within an hour of
[6.30](#630-a-program-cannot-run-another-program--done) by the first program that
read a command's output.

`wc -l` answers `"     100\n"`. `asInteger` is strict about the whole string
being a number — rightly, since `"12abc"` is a mistake rather than twelve — so
the padding has to come off first. Every command-line tool pads a number, and
every script that reads one trims it.

Space, tab, newline and carriage return: the four a terminal produces. Nothing
else, because a string is bytes and deciding what counts as blank in a text this
language cannot otherwise read would be a promise it could not keep. A string
with nothing to remove answers itself.

### 6.33 A running program cannot be stopped from outside — **done**

`sol_vm_set_step_limit` and `sol_vm_set_memory_limit`, set by whoever embeds the
machine before the program runs, and `solvm --steps=N` and `--memory=N` as the
front end for them. Reaching either answers `SOL_STOPPED` and exits with 124.

**The case.** A program that did not stop could not be made to. No time limit,
no instruction budget, no ceiling on what it could hold; a host that started one
had given away the thread and the heap until the program felt like giving them
back. That had always been true and had never mattered, because the caller was a
person with a terminal and a ctrl-c. It mattered as soon as the caller might be
a webserver, where a request that never finishes is a worker that never returns,
and enough of them is the whole server — with nothing dangerous called and no
injection needed. It is the half of
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
that gets forgotten, because permissions are what people ask for and limits are
what the case actually needed.

**Why not the debug hook**, which already existed and could already stop a
running program — Solid quits out of one that way. Because the hook is offered
when the line or the frame changes, and a loop written literally compiles to
jumps: it enters no frame and returns to no caller, so neither moves. Measured
before anything was written, with a breakpoint on the loop:

| loop | iterations | times the hook was offered a stop |
| --- | --- | --- |
| `{ ... }:whileTrue({ ... })`, one line | 3,000,000 | 1 |
| `#1:toDo(#5, step)` | 5 | 5 |

The inlined loop was offered once and then ran to completion. It is the same
inlining that makes `--trace` quiet on a long loop, seen from the other side:
what makes the trace bearable makes the program unstoppable. So the counter went
in the dispatch loop, which is the one place every instruction goes through — a
limit checked anywhere else is a limit with a way around it.

**A step rather than a second**, because a unit of work does not vary with the
machine, its load, or what else is running. A limit chosen once means the same
thing everywhere, which a wall-clock timeout does not.

**Cost, and why there is no test for whether a limit was set.** With none, the
counter starts at `UINT64_MAX`, so the unlimited case runs the same
post-decrement and compare as the limited one and reaches zero five hundred
years from now. One branch either way rather than two.

Measured on a five-million-turn inlined loop, which is around twenty million
instructions: 0.74-0.75s with the counter and 0.76-1.04s without it. That is not
a speed-up, it is the measurement saying the cost is below its own noise -- but
it does put a ceiling on it, which is what the number was wanted for.

**Memory is measured after a collection**, which is the whole difficulty.
`bytes_allocated` before a sweep counts everything the program has ever asked
for and not yet had taken back, most of which may be unreachable; a ceiling read
off that figure stops a program for litter rather than for what it is holding,
and a loop building one small string at a time would trip it however small the
strings were. So going over is a reason to collect, and being over once that has
happened is a reason to stop. Two programs make the same amount of garbage under
the same ceiling and only the one still holding it is stopped, which is a test.

**A stop is not catchable, and that is the point rather than an omission.** It
travels by `had_error`, as an exit does, so it unwinds through every loop that
already tests that flag — but `onError` lets it past and `ensure` does not run
its cleanup. A handler is code; running a handler is spending the allowance that
just ran out; and a handler wrapped around everything, which is the shape people
write, would turn the limit into a suggestion. `ensure` is the sharper case,
because it works by setting the failure aside precisely so that more code may
run, and a program could otherwise put its work in a cleanup and carry on. What
that costs is small here, because nothing in this language has to be released: a
file is read or written whole, and no message hands back anything a program is
obliged to close.

**And nothing inside the language can reach either limit** — no message sets,
clears or reads one. A program cannot find out what it was given and cannot give
itself more, which is the whole of what makes them limits rather than
suggestions.

**124 rather than 70**, because the program did not fail. It was taken away, and
a host reading that as an ordinary failure would go looking for a bug that is
not there. It is what `timeout` answers, for the same reason.

**What it does not do.** It bounds a program that *loops* -- which is what the
entry was written about -- and not what it reaches for: a stopped program may
already have deleted the files it was going to delete. That is 6.32, which is
still a decision.

**And it does not bound the cost of one message**, which this entry originally
claimed it did by saying it bounded a program's work. A step is a unit of
dispatch, so a primitive that reads a file or scans a string spends one of them
however large the file is: `readFile` of 256MB plus an `indexOf` over all of it
is eight instructions, and under a 1MB ceiling that read completes before the
program is stopped holding 256 times its allowance. Found by writing
[serve.sol](../programs/serve.sol) and running it as a guest with an allowance,
and recorded as
[3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work).

### 6.29 A stepper — **Solid** — **done**

`bin/solid`, the fourth program. It runs a program, stops before its first line,
and takes commands: step, next, finish, continue, breakpoints, a backtrace, and
the locals of any frame by name.

```
(solid) break report.sol:5
break at report.sol:5
(solid) continue
report.sol:5  in block
    5      after:lessThan(#0):ifTrue({ error:raise("overdrawn") }).
(solid) locals
  self             <object 0x10122e250>
  amount           #30
  after            #70
```

**The machine knows nothing about debugging.** The VM offers a stop before each
instruction that begins a new line or enters a new frame, and calls a hook if
one is set; Solid decides whether that stop is interesting. Stepping,
breakpoints and what a person means by "over" all live in `solid/`, and `solum/`
gained one function pointer and a branch.

**The branch costs nothing measurable.** Three million loop turns: 0.43s with the
check, 0.43s without.

**It stops where a program breaks**, which is the thing
[`solis --interactive`](#624-the-prompt-has-no-history--done) cannot do, since
that begins after the unwind and sees only globals:

```
-- division by zero in 'div'
breaks.sol:2  in block
(solid) locals
  a                #100
  b                #0
```

Nothing resumes from there — the unwind is decided by the time the error is
reported — but the frames are still standing and the value that caused it is in
one. `sol_vm_runtime_error` calls the hook after building the trace and before
returning, guarded against re-entry.

**Three bugs, all in deciding when to stop**, and all found by using it:

- **`next` stopped twice on one line.** Returning from a call lands on the line
  the call was written on, so stepping over took two presses and looked like one
  had been missed. It now requires a different line as well as the same frame.
- **A breakpoint fired twice for one visit**, for the same reason. The signal
  that tells them apart is the frame count *dropping* since the last offer,
  which happens only on a return.
- **A breakpoint in a loop fired once.** The first fix was too broad — it
  suppressed by line and depth, which a loop repeats — and then the VM's own
  gate turned out to be wrong too: a block whose whole body is one line, called
  from a primitive, never changes line *or* depth. Frames carry an id unique for
  the life of the VM, and gating on that is what makes a new frame always a new
  place to be.

The third of those is the one worth remembering: **two independent off-by-one
judgements about "the same place", one in each component**, both invisible until
a loop body happened to be a single line.

**A line breakpoint matches any frame at that line**, which includes the frame
that *defines* a block when the block's literal ends there. That is right and it
made two tests wrong before it made them careful — the test programs now use a
line only the body can be on.

### 6.28 Local variables have no names at run time — **done**

A chunk records what each frame slot was called, so `--trace` names its
arguments:

```
  [locals.sol:7] value(numbers: [#10, #20, #33])
    [locals.sol:4] value(n: #10)
    -> #1
```

**The compiler always knew** — it had to, to resolve `total` to slot 2 — and
threw it away once the index was emitted. The disassembly is what the runtime
had left:

```
SETLOCL     2
LOCAL       3
```

A slot is an index at run time and that is the right thing: an access is not a
lookup. What was missing is the name beside it, for anything looking *at* a
running frame rather than running in it.

**A table per chunk, in slot order.** Written straight rather than run-length
encoded, since neighbouring slots share nothing, and indexed by slot rather than
filled in the order names arrive — a slot nobody named, like slot 0 which holds
the receiver, still takes a place, so index N is slot N. There is a test that
names slots out of order and leaves a gap, because that is the property worth
holding: an off-by-one here would put the wrong name against the right value,
which is worse than no name at all.

**`--trace` naming arguments is how the table was checked.** If `amount:` lines
up with `#30` then the right name is against the right slot, and that is visible
rather than asserted at a distance.

**The second `.sob` format change in two releases**, 12 to 13. The entry had said
this should have ridden along with
[6.27](#627-a-stack-trace-does-not-say-which-file--done) and it did not, so the
honest accounting is: a bump costs a recompile, a recompile is cheap and
automatic, and nothing here ships bytecode without its source. Two bumps cost
two recompiles.

The size, against version 12: +0.2% on `numbers.sob`, +3.4% on `page.sob`. Far
cheaper than the file table, because a name is stored once per slot rather than
once per method chunk.

**What it unblocks** is [Solid](COMPLETED.md#629-a-stepper--solid--done). A stepper
showing `slot 3 = #180` would have been most of the work for a fraction of the
use; it can show `average = #180`.

### 6.27 A stack trace does not say which file — **done**

A trace names the file as well as the line:

```
solvm: index #99 is out of bounds for a string of size 4
  [lib/parse.sol:4] in block
  [main.sol:3] in script
```

**It was misleading rather than merely thin**, which is what made it worth a
format change. The example above has a three-line `main.sol`, and the old trace
said `[line 4] in block` — a line that does not exist in the file anybody would
have gone to look at. Had `main.sol` been longer it would have pointed
confidently at the wrong line of the wrong file.

A `.sob` is **one chunk**: `@include` compiles a library's code into the same
one, and the line numbers come with it while the file name does not.

**The fix mirrors what was already there.** The chunk carried a line per byte,
run-length encoded in the file because neighbouring instructions share a line.
Now it carries a file per byte the same way, plus a table of the paths — and the
runs are even better here, since a method body comes from one file and is one
run.

`--trace` reads the same table, so it names files too, for free.

**What it cost.** The first `.sob` format change since 0.1.0: version 11 stood
for nine releases and this is 12. Files from an earlier build are refused with
`unsupported bytecode version` rather than misread, and the remedy is to
recompile.

The size, measured across the examples:

| | v11 | v12 | |
| --- | --- | --- | --- |
| `hello.sob` | 279 | 315 | +12.9% |
| `numbers.sob` | 1,633 | 1,671 | +2.3% |
| `mirror.sob` | 4,580 | 5,100 | +11.4% |
| `manifest.sob` | 15,176 | 17,547 | +15.6% |
| `page.sob` | 18,694 | 21,005 | +12.4% |

The spread is the number of method chunks: **each carries its own file table**,
so a program with ninety small methods stores its path ninety times. Sharing one
table from the top-level chunk would recover most of it, and was not done —
every chunk verifying on its own is a property worth more than two kilobytes,
and `.sob` files are tens of kilobytes to begin with.

**A chunk with no file still says just the line.** The prompt compiles from text
rather than from a file, so it has no path to give, and prints `[line 1] in
script` exactly as before. That case was found by a test rather than by thinking
about it: the writer emitted file ids into an empty table, and the loader
refused its own output.

### 6.25 `makeDirectory` refuses one that is already there — **done**

It answers whether it made one instead: **true** if it did, **false** if a
directory was already there, and an error for anything else.

```
system:makeDirectory("build/out").      ; true  -- made it
system:makeDirectory("build/out").      ; false -- already there
```

**The case was that every script carried the same block.**
[mirror.sol](../programs/mirror.sol) and [files.sol](../examples/files.sol) both
had a version of `isDirectory:ifFalse({ makeDirectory })`, because "make sure
this exists" is what a script wants nine times in ten and refusing made it a
test and a make.

**What decided the shape was a thing the entry had not noticed.** It offered two
options — a second message, or answering instead of raising — and the argument
for the second turned out to be stronger than "one message is tidier": refusing
could not be told apart from failing. `mkdir` reports `EEXIST` both for a
directory that is already there and for a **file** sitting at that name, so a
caller who wanted to know had to catch the error and read its text, and even
then got the same words for two situations that are not the same news:

```
cannot make directory 'perm/already': File exists
cannot make directory 'perm/afile':   File exists
```

The first is fine and the second never will be. So the file case is separated
out and says what it is:

```
cannot make directory 'perm/afile': something that is not a directory is already there
```

Answering `true` or `false` puts the ordinary fact where a caller can use it or
ignore it, and leaves errors for the things that are actually wrong: no
permission, no parent, or something else in the way.

**One level still.** `mkdir -p` is a different message and nothing has asked for
it; this entry was only ever about the case where the work is already done.

### 6.26 A file's mode and time cannot be read or set — **done**

`system:modeOf`, `system:setMode`, `system:setModifiedAt`.

**The case was one program.** [programs/mirror.sol](../programs/mirror.sol)
copies a tree with `readFile` and `writeFile`, which carry bytes and nothing
else, so what arrived was:

```
source:      -rwxr-xr-x  script.sh
destination: -rw-r--r--  script.sh
```

A backup of anything holding scripts was not runnable. For a language aimed at
scripting an OS that is a floor rather than a nicety, which is why this went
ahead of the two entries beside it.

**A mode is an integer**, and the alternative considered was a string of nine
letters — `"rwxr-xr-x"` — which is what `ls` prints and what a person
recognises. It was turned down because it would be a second representation of a
number, needing its own parser and its own refusals, where `asBase` already
crosses that gap for every base:

```
system:modeOf(path):asBase(#8).      ; "755"
"755":asInteger(#8).                 ; #493
```

Solum has no octal literal, so `#493` is what `0755` looks like written down.
That reads badly on its own and is why the pair above is the thing to know.

**The file-type bits are masked off.** What comes back is permissions alone, so
`setMode(to, modeOf(from))` — the whole reason both exist — cannot try to change
a file into a directory. A mode outside `#0` to `#4095` is refused rather than
partly applied, which is what `chmod` would do with bits it does not recognise.

**`setModifiedAt` closed a corner that could not be closed before.** A copy is
stamped *now*, so the only question a mirror could ask was *is the source
newer?* — and a source file replaced with an **older** copy of itself is not
newer, so it went unnoticed. With the time carried across, a matching pair
compares **equal**, and the older replacement is seen:

```
1 files to copy
    notes
```

Only the modification time. The access time is left alone with `UTIME_OMIT`,
because nothing has wanted it and setting it silently would be a second thing
happening. Times before 1970 split by flooring rather than truncating, and there
is a test that reads one back.

**What the program gained besides**: it can now tell a file whose bytes are
right and whose permissions are wrong, and fix that without reading the file
again — which is the shape every real mirroring tool has.

### 6.10 Waiting for a single key — **done**

`system:readKey`, answering one byte without waiting for return.

**Closed once by mistake and reopened.** The first time, `solis` grew raw-mode
line editing for its own prompt — the same machinery, and not the same thing,
since a *program* still could not read a key. That work is
[6.24](#624-the-prompt-has-no-history--done). This is the message.

The entry left three questions and they are answered:

**One byte, not a whole key.** An arrow is three bytes and a function key can be
more, and which is which belongs to the terminal rather than to the language.
Answering the byte is the smaller promise: a program that wants arrows assembles
them, and one that only wants *any key* is not made to unpick a sequence it
never asked about. It comes back as a one-character string, so `asByte` gives
the number and the value is a value like any other.

**nil at the end of input**, which is `readLine`'s answer and for the same
reason: running out of input is how a loop that reads finishes.

**No echo.** Raw mode does not, and a program that wants the key shown prints
it. Showing it would be a second thing happening.

Raw mode **only when standard input is a terminal**. Through a pipe or a file a
byte is already a byte, so this reads the same way under
`solvm program.sob < input` — which is what makes it testable without a
terminal, and the pipe test is the deterministic one. `ISIG` stays on, so
ctrl-c interrupts a program that is waiting for a key rather than handing it the
byte.

**What it cannot do**, and no byte-level reader can: tell the escape key from
the start of a sequence. Pressing escape and then tab reads the tab as the byte
after the escape. A terminal tells them apart by waiting a few milliseconds and
giving up, which needs a read with a timeout.
[examples/keys.sol](../examples/keys.sol) demonstrates the assembly and says
this out loud.

**The raw-mode dance is written twice**, here and in `solis/src/line.c`, and
that is deliberate: the prompt holds raw mode across a whole line of editing
where this holds it for one byte, and an interface with both lifetimes in it
would have been larger than the twelve lines it saved.

**A harness bug came out of testing it.** `session_expect` in `test_line.c`
counted turns of its loop against a two-second deadline, so it gave up after a
hundred reads however fast they arrived — which a long line reaches while it is
still being echoed, a keystroke at a time. It counts two seconds of *silence*
now. Every test in that file was passing beforehand; the one with a line long
enough to notice was the one that found it.

### 6.24 The prompt has no history — **done**

**This entry was filed under 6.10 and should not have been.** 6.10 is *waiting
for a single key*, and it is the program-facing half of
[6.3](#63-reading-input--done): `system:readLine` lets a Solum program read a
line, and 6.10 is the message that would let it read a keypress. What was built
here is raw terminal mode **inside solis**, for its own prompt. It needed the
same machinery and it is not the same thing — a program still cannot read a key,
and `system:readKey` does not exist. 6.10 is back on the roadmap, where it was
before being closed by mistake, and this is the work under a number of its own.

**It came from using the prompt**: type something wrong, get an error, and want
to press up and fix it rather than type the line again. From using the prompt: type something wrong, get an
error, and want to press up and fix it. The terminal does line editing itself in
its usual cooked mode, which is why `fgets` was enough to begin with — backspace
worked because the tty handled it before solis saw the line. What the tty does
not do is history, so an arrow key arrived as the three bytes of its escape
sequence and was compiled as if they had been typed.

Getting history means taking the editing over, which is what made this a piece
of work rather than a small addition.

**What it does.** Up and down through history, left and right within the line,
home and end, backspace and delete, ctrl-a, ctrl-e, ctrl-u, ctrl-l. Ctrl-d ends
the session on an empty line and deletes forwards otherwise, which is what it
means everywhere else.

Three details worth the words:

- **A half-typed line survives browsing.** Step away with up and the line you
  were writing is kept, so down brings it back rather than an empty line.
- **The same line twice running is one entry.** Re-running something to watch it
  fail again should not mean pressing up twice to get past it.
- **`ISIG` stays on**, so ctrl-c still interrupts and ctrl-z still suspends.
  Those belong to the terminal, and taking them over would be a surprise.

**It degrades rather than depending on anything.** `sol_line_editing_available`
asks whether stdin and stdout are terminals and whether `TERM` is something
better than `dumb`; when they are not, the prompt reads a line exactly as it did
before. That is what keeps `solis < script`, `solis program.sol` and the test
suite working, and it is why this is a fallback rather than a dependency — no
readline, no libedit, and the build still needs nothing but a C11 compiler and
`make`.

**Bytes, not characters.** The cursor moves a byte at a time, so a multi-byte
character is split by a left arrow. That is the same limitation the language
has — [2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only) — rather than
a new one, and it will be answered when that one is.

**The redraw is the whole line, every time.** Wasteful in principle, invisible
in practice at these lengths, and it is the version that cannot drift: tracking
what the terminal already shows would be a second model of the same thing, which
is the usual source of a display that disagrees with the buffer.

**Testing it needed a terminal**, so `tests/test_line.c` opens one with
`posix_openpt` — POSIX, and needing no library, where `forkpty` lives in
different headers on different systems and would have changed the Makefile. Two
things that took a second attempt:

- **Keys sent before solis starts are lost.** Raw mode is entered with
  `TCSAFLUSH`, which discards input already received, so the test waits for the
  prompt — written from inside the reader, after the mode change — before
  sending anything.
- **The assertions are on what ran, not on what the screen shows.** The first
  version matched painted text, and since the editor paints every keystroke, a
  test looking for `kept` after typing `"kept":display.` matched the painting
  rather than the running and drifted a keystroke out of step from there. The
  values are now chosen so the output never appears in the input: nothing in
  `#100:add(#5):print.` spells `#105`.

### 6.19 A symbol cannot be ordered — **done**

`lessThan`, `greaterThan`, `lessOrEqual` and `greaterOrEqual` on symbols,
comparing the text.

The question the entry raised was whether that is worth it, since **interning is
what makes `equals` on two symbols a pointer comparison** — and it is exactly
what makes their addresses say nothing about their order. So these four are the
only symbol operations that have to look at the characters.

It is worth it, and the reason is the one that gets anything sorted: a tally
kept under symbol keys needs a stable order to print in. Symbols are values and
make good dictionary keys, so tallying by symbol is the natural thing to write,
and then the report could not be printed the same way twice.
[programs/manifest.sol](../programs/manifest.sol) had the workaround in it —
`collect` the keys to strings, sort those, convert back with `asSymbol` to look
each one up — and writing that is what made the case:

```
kinds:keys:sorted:do({ kind |
    "  {} {}":fill([kinds:at(kind):asString("4"), kind]):display }).
```

Nothing new was needed for `sorted` itself: with no block it **sends**
`lessThan`, so defining one on symbols is all it took. That is the same
arrangement that lets a user-defined type order itself.

### 6.20 An HTML parser — **done**

Written to find out what the language wanted, which is how the last three
entries here got their case. It is [lib/html.sol](../lib/html.sol), with
[programs/page.sol](../programs/page.sol) as a program on top of it, and the
entry predicted three things it would push on. All three happened, and one of
them answered a question that had been open since 3.5 was written.

**1. Error recovery, which nothing here had ever done.** Every other parser in
this project reports the first problem and stops — `solas`, `evaluator.sol`,
`json.sol` — and each is right to, because their input is written by somebody
who can fix it. HTML is generated, served, and wrong. A reader that stops is no
use, so this one recovers and keeps a list:

```
@include "html.sol".

page := html:read("<b>bold</i>").
page:text:display.                              ; bold
html:complaints:do({ c | c:display }).
; </i> at character 10 closes nothing that is open
; <b> opened at character 1 is never closed
```

The shape that made it work is that **recovery is not error handling**. There is
no `onError` anywhere in the library: a stray end tag is not an exception to
recover from, it is an ordinary branch that appends to a list and carries on.
Trying to build it on `error:raise` would have meant unwinding past the very
stack that holds the recovery state.

**2. A tree built against a stack, and 3.5 does not reach it.** The entry asked
whether building against a stack of open elements would sidestep the frame
limit. It does, completely:

| | deepest that works |
| --- | --- |
| `json.sol`, recursive descent | **28** levels |
| `html:read`, an explicit stack | **50,000** levels, and no limit found |

**The catch was on the way back down.** The tree built 50,000 deep could not be
*walked* 30 deep, because `text`, `find` and `findAll` were written the obvious
recursive way and spend a frame per level:

| | before | after |
| --- | --- | --- |
| `text`, `find`, `findAll` | **28** levels | **50,000** |

They are written with an explicit stack now too. The lesson is sharper than
"use a stack": **the limit is not a property of the data, it is a property of
how you traverse it**, and a library can be half-safe without anybody noticing —
the constructor was the part everyone thought about.

**3. Character work in bulk, which `asByte` handled.** Numeric entities
(`&#233;`, `&#x1F600;`) need a code point to become bytes, which is
[6.12](#612-taking-a-binary-file-apart--done) from a second direction and the
first test of whether that pair was the right size of fix. It was: the encoder
moved to [lib/text.sol](../lib/text.sol) unchanged and both libraries include
it. That file is the first library here included by another library rather than
by a program.

**What it cost that was not predicted.** An array cannot be popped and cannot be
asked whether it holds something — [6.23](#623-an-array-cannot-be-popped-or-asked-what-it-holds--done).
And `lib/text.sol` first bound a global called `text`, which the first program
to use it shadowed with a variable of its own, breaking the library from a
distance with `string does not understand 'utf8'`. That is
[6.21](#621-two-libraries-binding-one-name-collide-silently--done) happening
within ten minutes of being written down. The fix was to bind no global at all:
`integer:asUtf8` is a method on a built-in class, which needs no name of its
own. A namespace only helps if the name is one nobody else wants.

### 6.21 Two libraries binding one name collide silently — **done**

Top-level rebinding is legal and an included file binds into the one global
namespace, so two files that both use a name did not collide — the later one
won, quietly, and which one a program got depended on include order rather than
on anything written where the name was used. The failure was not a message but a
different answer.

**The entry said nothing had tripped over it. That lasted about ten minutes.**
[lib/text.sol](../lib/text.sol) was written to hold what the JSON and HTML
readers both needed, and bound one object called `text` — following the advice
in the reference about claiming one name instead of a dozen. The first program
to use it had a variable called `text`, and the library broke from a distance:

```
solvm: string does not understand 'utf8'
```

A run-time message about a type, for a compile-time collision between two files.

**The compiler says it now**, at the line where it happens:

```
[prog.sol:3:1] solas: warning: 'text' was already bound by lib/text.sol -- this one wins, and nothing else will say so
  text := v.
  ^^^^
```

A warning and not an error, for the reason the self-include warning is one:
rebinding is legal and sometimes meant — a program may want to replace something
a library bound — so saying so without forbidding it is the right bargain.

**A claim, not an update.** `count := count:add(#1)` reads the name before
writing it, so it is working on somebody else's global rather than declaring its
own, and files legitimately do that across an include. The rule is that **a name
you read in the course of assigning it is one you are updating**, and only a
claim warns. That removed the one false positive in the whole tree — a test
fixture that increments a counter from an included file — and it is what makes
the warning quiet enough to keep: the 28 examples, four libraries and every test
compile without one.

**What it does not fix.** This is the cheap half of a namespace and nothing else.
There is still no export boundary — every slot on `json` and `html` is public
and writable, and `json:digits := "abc"` breaks the parser from outside it — and
no declared dependencies. Those need things the language does not have: slots
cannot be removed and `slots` lists everything, so privacy would be a new concept
rather than a use of existing ones.

**The three tiers that came out of it**, which are the working advice now:

| what a library adds | how to bind it | globals claimed |
| --- | --- | --- |
| behaviour on an existing type | a method on the class | **none** — `control.sol`, `text.sol` |
| a thing with state and its own operations | one object, everything on it | **one** — `json`, `html` |
| several unrelated names | nothing better than several globals | **several** |

The top tier is the discovery. `integer:asUtf8` and `integer:timesCollect` need
no name of their own, because they extend a class that already has one — a send
rather than an assignment, so this warning never sees them and there is nothing
to collide with.

### 6.22 A file that includes a library of its own name silently does nothing — **done**

The search path looks beside the includer first, and a file is compiled once. So
`@include "json.sol"` written *in* a file called `json.sol` finds itself, has
already started, and contributes nothing. The program compiled cleanly and failed
at run time with `undefined name 'json'`, a long way from the line that caused
it.

**It was documented before it was diagnosed**, and that turned out not to be
enough: the reference called it *occasionally a trap*, and it still took about a
minute to fall into once `lib/` had a second file to collide with. The example
built on the JSON library is called
[manifest.sol](../programs/manifest.sol) for that reason and no other.

The compiler is holding both halves of the question — it knows the file it is
compiling and the file the include resolved to — so it says so:

```
[greet.sol:1:10] solas: warning: this file includes itself, so the include does nothing -- a file beside the includer wins, and 'lib/greet.sol' on the search path is what it shadowed
  @include "greet.sol".
           ^^^^^^^^^^^
```

**A warning and not an error**, which was the decision in it. Shadowing is C's
rule and worth keeping, the file is still valid, and the status is unchanged —
so this is a note about something that will not do what it looks like, not a
refusal. It is the first warning the compiler has; `sol_parser_warning` shares
the location and the echoed line with `sol_parser_error` and sets neither
`had_error` nor the panic flag.

**Naming what was shadowed is the useful half.** "This does nothing" tells you
something is wrong; `'lib/greet.sol' on the search path is what it shadowed`
tells you what you were expecting to get. When nothing of that name is on the
path there is nothing to name, and the warning says the first half alone.

**Only the direct case.** Two files that include each other are a cycle that
include-once ends on purpose, and a file reached twice by different routes is
the ordinary reason include-once exists. Both are silent, and there are tests
for both — a warning that fired on either would be worse than the trap it was
added for.

### 6.15 There is no dictionary, and no way to build one — **done**

Found by writing [programs/log.sol](../programs/log.sol), the first program here
written to do a job rather than to show a feature. Counting by key is most of
what a log analyser does, and the language could not express it: the tally was an
array of key/count objects walked from the top, O(n) a lookup and O(n²) over a
file.

The entry weighed two answers and called the first one smaller: **`slotAtPut`**,
completing the reflection triple against `slotAt` and `perform`, so that an
object could serve as a dictionary; or **a real dictionary type**.

**Checking made the choice, and it was not the one the entry expected.**
`slotAtPut` would not have worked at all:

- A slot name is interned in the VM's **permanent** name table. `vm.h` says so
  outright — those names outlive every slot and are freed only with the VM. A
  dictionary of keys read from a file would leak a name apiece, by design.
- Slots are a **linked list, walked linearly** (`sol_object_lookup`). So an
  object-as-dictionary would have had exactly the complexity of the array of
  pairs it was meant to replace.

It was not the smaller option. It was the wrong one: prettier syntax for the
same algorithm, plus a leak. So: the real type.

Built as `7e0726d`. `dictionary:new`, `at`, `at(key, default)`, `atPut`,
`includes`, `remove`, `size`, `keys`, `values`, `do`, `keysAndValuesDo`. Open
addressing, one allocation for the entries, tombstones for removal, and a
rebuild that drops them once they crowd the table.

**Keys are values.** Integers, floats, strings, symbols, booleans and nil are
compared by content, so two keys that look alike are one key; arrays, blocks,
objects and dictionaries are compared by identity, so two that look alike would
be two keys — right for `equals`, useless here, and refused rather than
surprising anybody. That is the same line the language already draws between
values and references, so it needed no new idea.

Two consequences fell out of taking it seriously. `-0.0` has to hash as `0.0`,
since `0.0:equals(-0.0)` is true and the table would otherwise disagree with
`equals` about what one key being another means. And `nan` can be stored and
never found, since it equals nothing including itself — IEEE showing through
rather than a decision.

**`sol_value_equals` now exists**, in object.c, and `prim_equals` calls it. A
dictionary asks the same question of its keys that `equals` asks, and two
definitions could have drifted.

#### What went wrong, and why it was allowed to

A dictionary is the first type whose **keys** are edges as well as its values,
and adding a value type touches six places. Five are switches over
`SolValueType` with no `default`, so `-Wswitch` named them all at the first
build: `sol_type_name`, `sol_vm_class_of`, the renderer, the serializer's
constant writer, and its check.

The sixth was `mark_value` in the collector, and it was a chain of
`if (SOL_IS_...)`. It compiled without a word and swept live dictionaries
instead, which took a segfault at 500 keys and a stack trace to find —
`entries=0x2, capacity=388`, a struct that had been freed and reused.

It is now a switch, with the comment saying why. The check was worth having at
the sixth site too, and the only reason it was missing is that nobody had added a
type since the check became the habit.

`tests/test_dict.c` has eleven groups, including growth past several rehashes,
churn until tombstones force a rebuild, a dictionary holding itself, and two
hundred freshly-allocated keys and values surviving a collection. That last one
fails if the marking is removed, which was confirmed rather than assumed.


---

### 6.16 An array cannot be sliced — **done**

The other thing [programs/log.sol](../programs/log.sol) wanted, and it wanted it
twice. There was no `first(#n)`, no `last(#n)` and no slice, so taking the head
of a sorted array was a walk with an index that the example carried as a
`firstFew` helper.

Built as `b156bcd`: `copyFrom(#a, #b)`, `first(#n)`, `last(#n)`. `firstFew` is
gone from log.sol, which now says `:first(#5)`.

**`copyFrom` is the string's rule, transcribed rather than reinvented.** Both
ends included, both one-based, the empty slice spelled with `to` one before
`from` and only that far, `from` allowed one past the end, and anything outside
that an error — following `at`. Two collections disagreeing about what a slice
means would be worse than either rule is good, and the string got there first.

**`first` and `last` clamp, and that is a second rule on purpose.** The entry
did not ask the question; writing it did. `copyFrom` names *positions*, and a
position outside the array is a program wrong about something. `first` names a
*quantity* — give me the top five — and a list of three has answered that
correctly by handing over three. Refusing there would make every ranked report
check the size first, which is the whole of what these exist to avoid.

One rule would have been tidier and wrong. A negative count is refused by both,
since clamping is for asking for more than there is rather than for asking for
nonsense.

All three answer a new array and leave the receiver alone, like `collect`,
`select` and `sorted`, and they share the elements rather than copying them —
an array holds references, so a slice of an array of arrays sees the same inner
arrays. There is a test for that surviving a collection.

#### And a report that was not repeatable

Replacing `firstFew` exposed something else. `log.sol`'s "busiest paths" ranks
by count, and four paths tie at two apiece for three places — so which three
appeared depended on the order `dictionary:values` happened to hand them back.
That order is arbitrary but not random, so the output was stable per build and
looked fine; it had quietly changed when the tally became a dictionary.

Arbitrary is not good enough for something a person reads twice, so the report
now breaks ties on the key, and the comparison block says why. The example is
the same every run, and it demonstrates a two-key sort into the bargain.


---

### 6.6 The loop constructs are library code, and pay for it — **done**

All four, and **the entry's premise was wrong about three of them.** It asked
for inlining. `doUntil` got inlining, because it deserved it. `repeat`, `toDo`
and `toByDo` became primitives instead, which is both cheaper to build and
faster to run than the inlining the entry wanted.

The entry sat unbuilt for a long time because the gain looked modest — 1.30x for
`repeat`, measured once `timeToRun(#n)` existed. **The mistake was measuring the
wrong one.** `repeat` pays for one block call an iteration; `doUntil` pays for
two, its condition being a block as well as its body, plus the `done:not` send
the library version needs. Measured properly, over 200,000 iterations:

```
library doUntil   0.0706 s
hand-written flag 0.0395 s
inlined doUntil   0.0309 s
```

**2.29x the library version, and 1.28x the loop it replaces.** That second
number is the one worth having: writing the loop out yourself needs a `done`
flag outside it, and that flag costs two sends an iteration the jumps do not
need. So `doUntil` is not a convenience you pay for — it is now the fastest way
to write that loop.

Built as `413c57b`, in two pieces. A primitive on `block`, so the message exists
whether or not it is written literally, and an inliner beside `inline_while`.

**The wrinkle was the complaint, not the loop.** The shape is `whileTrue`'s with
the body moved in front of the test and the sense inverted, and there is no
`OP_EXIT_IF_TRUE`. Adding one would have meant a new opcode — and a name index
on it, since `OP_EXIT_IF_FALSE` carries none and words its error as `whileTrue`,
which is the wrong message for a program that wrote `doUntil`.

`OP_CHECK_BOOL` already carries a name and already refuses a non-boolean, so it
goes in front:

```
top:  body / POP / condition / CHECK_BOOL 'doUntil'
      EXIT_IF_FALSE -> again        ; false: go round
      JUMP          -> end          ; true: leave
again: LOOP -> top
end:  NIL
```

By the time `OP_EXIT_IF_FALSE` sees the value it can only be a boolean, so its
wording is unreachable. No new opcode, no `.sob` version change, and the
invariant holds: a test asserts the inlined and sent forms produce the same
first line, and that neither says `whileTrue`.

**It came out of the library.** `lib/control.sol` defined `doUntil` and does
not any more — a definition there would be a trap rather than an override, since
the compiler splices the loop in when both blocks are written on the spot and
would bypass it exactly where it was most wanted. The file says so where the
definition used to be.


---

### 6.6, continued — the counted loops, and why not inlining

Recorded separately because the answer contradicts what the entry asked for.

`repeat`, `toDo` and `toByDo` were to be inlined the way `whileTrue` and
`doUntil` are. Two things came out of trying.

**Inlining them faithfully needs an instruction that does not exist.** A counted
loop's receiver is whatever expression you wrote, and its type is not known
while compiling. `1.5:repeat({ ... })` has to go on saying *float does not
understand 'repeat'* — the rule that an inlined message complains exactly as the
sent one does. Inlined jumps would reach the counter comparison first and
complain about that instead, so getting it right needs a type-guard instruction
carrying the message name, the way `OP_JUMP_IF_FALSE` carries one for `ifElse`.
That is a new opcode and a `.sob` version with it.

**And it would have been the slower answer anyway.** Per iteration the Solum
version pays a block call for the body, a `lessThan` send and an `add` send for
the counter. Inlining removes the block call and keeps the two sends. A
primitive removes the two sends and keeps the block call. Measured over 200,000
iterations:

```
library (Solum)      0.0601 s
inlined by hand      0.0470 s     -- what the entry asked for
primitive            0.0186 s
```

**3.2× the library version, and 2.5× faster than inlining would have been.** The
sends cost more than the block call, which is the opposite of what the entry
assumed and is why it is worth writing down.

The receiver check comes free with the primitive: `repeat` is installed for
`SOL_INT` receivers, so a float never finds it and dispatch says so in the words
it always used. The thing inlining would have needed a new opcode for is what
dispatch already does.

`toByDo` gained two things it could not have as Solum. A step of `#0` is an
error rather than a printed complaint the library could only follow with a
silent no-op. And a step that would carry the index past `INT64_MAX` ends the
loop instead of wrapping to the bottom and running for ever — there is a test
for both directions.

**The library is nearly empty now**, and that is the record rather than a
regret: it opened with five loops, four were measured, and all four were worth
building in. `timesCollect` is what is left, being the one nobody has measured.
The search path and `@include` finding a name it was not told the location of
are unchanged, and were always the part that mattered.


---

### 6.17 There is no `ensure` — **done**

Written down when `onError` landed, on the grounds that nothing needed it yet:
the things `ensure` usually protects are handles and locks, and there are
neither. Built the next thing anyway, because the entry named the one wrinkle it
would have and that wrinkle turned out to be the whole of it.

Built as `e001b8e`. `{ body }:ensure({ cleanUp })` runs the cleanup whether the
body finished or not, then goes on doing whatever the body was going to do. It
answers the **body's** answer; the cleanup's is discarded, the cleanup not being
what the expression is about.

**The difficulty is that a failure has to be set aside for the cleanup to run at
all.** `had_error` is what stops the machine, and the dispatch loop tests it
after every instruction — so a cleanup started with the flag still up would
manage one instruction and stop. The failure is lifted out complete with its
message and its stack, the VM given fresh empty buffers for the duration, and
the whole thing put back afterwards. The texts are moved rather than copied, so
anything the cleanup reports lands somewhere else and is thrown away.

**`system:exit` is set aside the same way**, which the entry did not anticipate.
It travels by the same flag, and giving back a thing you borrowed is as
necessary when a program is stopping as when it is failing — more so. The
cleanup runs and the program still leaves with its status.

**When both fail, the body's failure wins.** That was the wrinkle the entry
named, and the answer it guessed was right: the first error wins here as it does
everywhere, and the second is usually a consequence of the first.

An uncaught failure that passed through a cleanup keeps its own message and its
own stack, so it still names where it happened rather than where it was tidied
up after. There is a test for that, and one for twenty thousand cleanups in a
loop leaving the stack and the collector's temporaries where they were.

Unlike `onError`'s handler, the cleanup **always** runs, so one that is not a
block is refused every time rather than only when something fails — which is a
difference in what the two messages promise rather than an inconsistency.


---

### 6.18 There is no date or time — **done**

Written down when `system:fileSize` landed without a matching `modifiedAt`,
because a timestamp wants to be a date rather than a number of seconds and
answering an integer then would have been an interface a date type had to
change. Built the next thing, on the lines the entry set out.

Built as `eaa2fa4`. A **value type**, `SOL_TIME`, held as nanoseconds since
1970-01-01T00:00:00Z.

**A value, not an object**, which the entry called and which the rule that
sorted out `new` confirms: two of the same instant are the same time, nothing
mutates one, so it belongs beside integer and float rather than being slots.
That makes `equals` exact, makes a time a dictionary key for free, and means
`time:new` refuses like the other value classes.

**Nanoseconds as an integer, not a float of seconds.** The language is strict
about integers and floats, and a point in time being a float invites
`t:add(1.5)` — a question with two plausible answers. Integers are exact,
`nan` cannot get in, and int64 nanoseconds reach from 1678 to 2262.

**Everything is UTC.** The entry named time zones as where every date library
goes wrong, and the answer is not to have them: a zone is a political fact that
changes by legislation, twice a year in most places and retroactively in some.
An instant is unambiguous; a wall-clock reading is not.

**`secondsSince`, not `sub`.** A time minus a time is not a time, so `sub` would
have answered a different kind of thing from every other `sub` in the language,
and would have invited `t:sub(#5)`. The name carries the direction and the unit.

**`asString(format)` hands the format to `strftime`.** The entry worried about
inventing a second spec language; the answer was to invent neither. The
number-formatting spec is about width and digits and has nothing to say about a
Tuesday, and `strftime`'s alphabet is the one everybody already knows.

#### What the entry did not plan, and building it found

**Nothing could name a particular moment.** With only `system:time` and
`system:modifiedAt`, the sole instants a program can have are the current one
and a file's — which is enough to stamp a log, and not enough to say when
something is due, or to test any of this against a date somebody knows. Two
tests in, that was obvious. `time:fromSeconds(f)` and `asSeconds` are the pair
that fixes it, and they are also how an instant gets written to a file and read
back.

**Splitting an instant has to floor.** C division truncates towards zero, so
half a second before the epoch divides to zero seconds and lands on 1970 rather
than 1969. There is a test for the day before the epoch and for the sliver
before it.

`system:modifiedAt` is the companion `fileSize` was waiting for, and could not
have been written until this existed.

