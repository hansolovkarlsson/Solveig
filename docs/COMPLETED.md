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

---

## 2. Language decisions

The two entries this section still holds live are in
[ROADMAP.md](ROADMAP.md#2-language-decisions-still-open): **2.5**, class side
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
[ROADMAP.md](ROADMAP.md#3-known-limitations). This one was a limitation until it
stopped being one.

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

## 6. Beyond the language

The rest of this section is live, and is in
[ROADMAP.md](ROADMAP.md#6-beyond-the-language).

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
number of its own: [6.10](ROADMAP.md#610-waiting-for-a-single-key).

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

### 6.23 An array cannot be popped, or asked what it holds — **done**

Both found by [lib/html.sol](../lib/html.sol), which keeps a stack of open
elements — the thing parsing a nesting format wants, and the thing an array did
not quite serve. Both workarounds were written and shipped before the messages
were, which is what made the case for them.

**`removeLast`** takes the last element off and answers it. The workaround had
been an object carrying its own `top` index, overwriting with `at_put` rather
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
[examples/manifest.sol](../examples/manifest.sol) had the workaround in it —
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
[examples/page.sol](../examples/page.sol) as a program on top of it, and the
entry predicted three things it would push on. All three happened, and one of
them answered a question that had been open since 3.5 was written.

**1. Error recovery, which nothing here had ever done.** Every other parser in
this project reports the first problem and stops — `solas`, `evaluator.sol`,
`json.sol` — and each is right to, because their input is written by somebody
who can fix it. HTML is generated, served, and wrong. A reader that stops is no
use, so this one recovers and keeps a list:

```
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
[6.21](ROADMAP.md#621-two-libraries-binding-one-name-collide-silently) happening
within ten minutes of being written down. The fix was to bind no global at all:
`integer:asUtf8` is a method on a built-in class, which needs no name of its
own. A namespace only helps if the name is one nobody else wants.

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
[manifest.sol](../examples/manifest.sol) for that reason and no other.

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

Found by writing [examples/log.sol](../examples/log.sol), the first program here
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

The other thing [examples/log.sol](../examples/log.sol) wanted, and it wanted it
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

