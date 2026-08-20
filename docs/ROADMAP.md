# Roadmap

Everything still outstanding, grouped by what it blocks. This is the single list
— [design.md](design.md) describes how the language works today and points here
for what is unresolved, and [CHANGELOG.md](CHANGELOG.md) records what has already
changed.

Finished work is summarised here only where it gives context for something still
live; the detail belongs in the changelog rather than being kept twice.

Items marked **decision** need a call from you before they can be built; the
rest are work with a clear shape.

## Where things stand

Working: the scanner, the single-pass compiler, the re-entrant dispatch loop with
call frames, blocks with lexical capture and parameters, message-based control
flow, a mark-sweep collector over objects, blocks, and compiled code, the `.sob`
format with its verifier, and built-in `integer`, `float`, `boolean`, `nil`, and
`block`.

The language is Turing-complete, no longer leaks, and has strings, arrays,
symbols, user-defined objects, reflection, sorting, formatted output, and
conversions between every pair of types that has an unambiguous one. What is
left is not breadth any more: it is the items below, which are a correctness
question, two performance shapes, and the tooling.

The three bugs that led this list — 1.5 and 1.6, reachable from three words of
source, and 1.7, which answered wrongly rather than crashing — are all fixed,
and section 1 is done again.


---

## 1. Blocking real programs

### 1.1 Garbage collection — mostly done

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

**1.1a the collector** and **1.1b GC-owned code** are done. What remains:

#### 1.1c Temporary roots inside primitives

The mechanism exists and Solis uses it; no primitive allocates yet, so nothing
applies it. Arrays are what changed that -- see [1.2a](#12a-temporary-roots-finally-needed--done).

#### 1.1d Collection is stop-the-world and non-incremental

Fine at this size and not worth touching yet. Noted so it is a choice rather than
an oversight: a program holding a large live set will pause proportionally to it.

### 1.2 Arrays — **done**

`SolArray` and the `array` class: `new`, `of`, `size`, `at`, `at_put`, `add`,
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

```
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

## 2. Language decisions still open

One question is still open, **2.5**. Everything else this section held has since
been decided and built, and the reasoning went to the changelog rather than being
kept in two places -- the table at the end gives each verdict and names the entry
to read for why. What those decisions left unfinished is 2.14.

### 2.5 Class side versus instance side

`integer` holds both `new` and `print` in one object, so `#45:new(#1)` resolves as
readily as `integer:new(#1)`. Separating them needs a metaclass level. Also
uneven today: `integer` has `new` and `float` does not.

User-defined objects sharpen this. The built-in classes deliberately do *not*
delegate to `object`, because `float` inheriting object's `new` would answer a
plain object rather than a float -- so the built-in and user-defined sides are
two hierarchies that do not meet. A single root would be tidier, and needs this
question answered first.

1.6 answered this **in the small**: each primitive records the receiver it needs
and the dispatcher checks before entering it, one message at a time. That was
enough to stop the two crashes, and it is not the same as splitting the two sides
into separate objects, which is what remains open.

### 2.14 Loose ends from the decided items

Small, and each falls out of a decision above rather than being a question of its
own.

- **`isNil`** (2.8) is absent, though `x:equals(nil)` says it.
- **A fetched method is unbound** (2.10). `slotAt` answers the plain block, and
  `self` comes from a send rather than being carried by the block, so `m:value`
  runs with `self` nil. Calling one with a chosen receiver wants something like
  `valueWith(receiver, ...)`, which is a real question and not that one. Item 2
  in the suggested order.
- **Reflection cannot write** (2.10). There is no `slotAtPut`; no way to remove a
  slot, so a shadowing one cannot be un-shadowed (1.4); and no re-parenting,
  which would need the delegation link to become a real slot rather than the
  internal pointer that keeps dispatch safe (2.9).
- **No `clone`** (1.4). `new` delegates rather than copying, which is cheaper and
  more useful, but there is no way to take a snapshot of an object's slots.
- **A later range or slice API should use inclusive bounds at both ends** (2.3),
  following Smalltalk. Half-open ranges are what make zero-based indexing tidy;
  mixing a half-open convention into one-based indexing is where languages get
  confusing.

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
| 2.8 | Missing operations | Conversions, short-circuiting `and`/`or` over blocks, `notEquals` as the negation of `equals`, string ordering, `negated`/`abs`, sorting | `7ac6be6`, `246ae8e`, `113745f` |
| 2.9 | Calling the method you override | `self:via(ancestor)`, the ancestor named rather than inferred | `a5aa9e0` |
| 2.10 | Reflection | `slots`, `slotAt`, `respondsTo`, `isKindOf`, `perform`, named by symbol. Reads only | `a7310a7` |
| 2.11 | Filling a template | `{}` placeholders and `fill`, matched exactly, each value rendered by *sending* `asString` | `ca1369b`, `4a70ef0` |
| 2.12 | Formatting a single value | A spec argument to `asString`. No conversion letter, no sign mode; bases are a message, not a letter | `3524c70`, `95074c9`, `f4b909d` |
| 2.13 | Case and text | ASCII only, by explicit range rather than `toupper`. Still live, and now in section 3 | `91d413c` |

## 3. Known limitations

These are deliberate, safe, and documented. Each is a real restriction rather
than a bug.

### 2.13 Text is bytes, and case is ASCII only

`asUppercase` and `asLowercase` change `a`-`z` and `A`-`Z` and pass every other
byte through, by explicit range rather than `toupper` -- which follows the C
locale, so under a Turkish locale the same program would answer differently on
two machines.

That is the whole of the language's view of text: a string is bytes, `size`
counts bytes, and `at` answers a byte. `"café":size` is 5. Real Unicode -- code
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
an instruction inside the chunk, and stops there.

### 3.4 No compatibility across `.sob` versions

Each opcode-set change bumps the version and older files are refused outright.
Fine while nothing is released; worth a policy before anything is.

---

### 3.5 Recursion is limited to about 30 levels

`SOL_FRAMES_MAX` is 64, and in the idiomatic form each recursion level costs
**two** frames -- one for the method's block, one for the `ifElse` branch block
that carries the recursive call. Measured: 30 levels succeed, 31 reports "call
depth exceeded".

```
integer:countdown := { self:lessThan(#1):ifElse({ #0 }, { self:sub(#1):countdown }) }.
#30:countdown.   ; ok
#31:countdown.   ; solum: call depth exceeded
```

**Now 62**, since inlining conditionals (4.1) means a branch no longer costs a
frame. Recursion that went through a `whileTrue` body stayed at 30 until the
loop was inlined too, for exactly the same reason; both forms now reach 62.

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

### 3.9 The verifier does not know the stack height

`OP_SEND` carries `argc` in a byte, and nothing checks that many arguments are
really on the stack: the answer depends on the stack height at that
instruction, which the verifier does not compute. A corrupted count read the
receiver from below the frame — 227 arguments on a stack one deep — which
fuzzing the loop work turned up.

Bounded now at the point of use, where a send refuses to reach below its own
frame. The real answer is the JVM's: with instruction boundaries and every jump
target already known, the stack height at each instruction can be computed by
walking the code once and requiring the branches into a point to agree. That
would let the runtime checks go, and would catch a corrupted `argc` at load
rather than at the send.

## 4. Performance

Nothing here is urgent — the VM is written for clarity first — but each has a
known shape.

### 4.1 Conditionals and loops are real calls — **done**

`ifTrue`, `ifFalse`, `ifElse`, and `whileTrue` written literally compile to
jumps: no block allocated, no frame entered. They are still ordinary messages,
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

Still a send, and the same mechanism would serve: `and`/`or`, which
short-circuit through a block.

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
-- is a big-endian u16, because those tables grow with the program. A frame
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

### 4.3 Dispatch does a string compare per send

Symbols now exist, and interned names are exactly what this wants: a selector
compared by pointer rather than by `strcmp`. The work is in the chunk's text
table and slot names, not in inventing the mechanism.

`sol_object_lookup` walks a linked list comparing names with `strcmp`. Interned
symbols with pointer equality, or an inline cache per send site, are the usual
answers.

The chunk's own interning wants the same table, and now has a reason to: 4.2
raised the side tables from 256 entries to 65536 without changing the linear
scan that fills them, so compiling tens of thousands of distinct literals is
quadratic. One hash would serve both the compiler filling a chunk and the VM
resolving a send.

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

### 5.1 Solis is line-at-a-time, and lines are capped

`fgets` per line, so a method body spanning several lines has to go in a file.
The REPL should buffer until brackets, parentheses, and braces balance.

The buffer is also 1024 bytes with no overflow check: a longer line is silently
cut, and the tail arrives as if it were the next line. That has already produced
one confusing result -- a generated 255-element array literal appeared to fail to
compile when it had merely been truncated mid-token. It should at minimum report
the truncation.

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

`sol_value_print` prints `<object 0x...>` instead of sending `print` to the
object. Wants dispatch from inside the printer, or a `printOn:`-style protocol.

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

### 5.4 No source position beyond the line

Errors report a line number and nothing finer. Columns and the offending source
text would make compile errors considerably more useful.

---

## Suggested order

Everything that stood between this and a language you could write a real
program in is built. Section 1 held nothing until fuzzing the loop work put two
crashes into it, and both are now fixed — the receiver check in 1.6 took 1.5
with it, as that entry guessed it would.

Nothing here is urgent. The remaining items are roughly in order of how soon
they would be missed:

1. **Dispatch by pointer** (4.3) — symbols exist; a send still does `strcmp`,
   and the compiler's own interning wants the same hash table now that 4.2 has
   raised the side tables to 65536 entries.
2. **Calling a fetched method** — `slotAt` hands back an unbound block (2.14).
3. **Inlining `and` and `or`** (4.1) — the last two that short-circuit through a
   block. Nothing new is needed; the jumps are all there now.
4. **Stack heights in the verifier** (3.9) — would catch a corrupted argument
   count at load rather than at the send, and let the runtime checks go.
5. Everything else as it starts to hurt.

Done and off this list: garbage collection (1.1a, 1.1b, 1.1c), arrays entire
(1.2, 1.2a, 1.2b), strings (1.3), user-defined objects (1.4), division (2.1),
calling the method you override (2.9), the missing operations (2.8),
formatted output (2.11), the statement separator (2.2), float exponents and
round-tripping (2.6, 5.3), string escapes (1.3), rendering an object by asking
it (5.2), symbols (2.7), reflection (2.10), sorting, inlined conditionals and
loops (4.1), the two class-object crashes (1.5, 1.6), the side-table operands
(4.2), and the frameless temporary (1.7).

One decision is outstanding: **2.5**, class side versus instance side. 1.6
answered it one message at a time, which was enough to stop the crashes;
splitting the two sides into separate objects is still open. Every other
question section 2 held has been decided and built -- the table there records
the verdicts, and 2.14 the loose ends they left.
