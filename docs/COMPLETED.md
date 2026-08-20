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
  files, and the `system` object

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
| 2.8 | Missing operations | Conversions, short-circuiting `and`/`or` over blocks, `notEquals` as the negation of `equals`, string ordering, `negated`/`abs`, sorting | `7ac6be6`, `246ae8e`, `113745f` |
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
