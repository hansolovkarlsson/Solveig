# Roadmap

Everything still outstanding, grouped by what it blocks. This is the single list
— `docs/design.md` describes how the language works today and points here for
what is unresolved.

Items marked **decision** need a call from you before they can be built; the
rest are work with a clear shape.

## Where things stand

Working: the scanner, the single-pass compiler, the re-entrant dispatch loop with
call frames, blocks with lexical capture and parameters, message-based control
flow, the `.sob` format with its verifier, and built-in `integer`, `float`,
`boolean`, `nil`, and `block`.

The language is Turing-complete. What it is not yet is a language you could write
a real program in — there are no strings, no collections, no way to make a class,
and nothing is ever freed.

---

## 1. Blocking real programs

### 1.1 Garbage collection

**1.1a and 1.1b are done.** Objects, blocks, and compiled code are all
collected. 1.1c remains, and is deliberately left until strings need it.

The motivating case, a block literal allocated once per loop iteration:

```
{ i:lessThan(#2000000) }:whileTrue({ i := i:add(#1). b := { #1 }. }).
```

Peak resident set over two million allocations went from **98 MB to 1.5 MB**, and
from growing linearly to flat.

**The heap is two types.** Everything allocated at run time is either a
`SolObject` (with its owned `SolSlot` chain) or a `SolBlock`. Chunks, code,
constants, names, and `SolMethod` are compile-time data owned by whoever compiled
them. So the tracer needs exactly three edges:

```
SolObject.proto          -> SolObject
SolObject.slots[].value  -> SolValue
SolBlock.self            -> SolValue
```

**Roots are nearly free**, because of two properties of the current design.
Frame locals live inside the value stack -- `push_frame` sets
`slots = stack_top - argc - 1` and fills the rest by pushing -- so scanning
`stack[0 .. stack_top)` covers every local of every frame with no separate frame
walk. And a primitive's arguments are still on the stack while it runs, since the
dispatch loop drops them only after it returns. That leaves the root set as the
value stack, `vm->root`, and the five class objects.

**Mark-sweep, non-moving, stop-the-world.** A copying collector would have to fix
up every `SolValue` in the stack, in slots, and in `block->self`, for no benefit
at this size. Reference counting is the wrong shape: objects cycle freely -- a
class's slot can hold a block whose `self` is that class -- and inc/dec would
touch every `SolValue` copy in the VM.

Staged, because "is my tracing correct" and "did I get ownership right" fail in
different ways and are worth not mixing.

#### 1.1a The collector — **done**

- One shared GC header (`next`, `marked`, `type`) embedded in both heap types,
  merging the two lists into one, so each future heap type does not add another
  list and another sweep loop.
- Mark from the roots above using an **explicit gray worklist, not C recursion**:
  a deep object graph would otherwise overflow the C stack.
- Sweep the list, free unmarked, clear marks on survivors.
- Trigger on bytes allocated with a growth factor, plus a **stress mode**
  (`SOLUM_GC_STRESS=1`) collecting on every allocation. The whole suite passes
  under `SOLUM_GC_STRESS=1` with ASan and UBSan, which is what makes a missing
  root a caught bug rather than a latent one.

The ordering trap was real: `sol_vm_init` nulls `vm->root` and the class fields
before the first allocation, or a stress-mode collection during setup would trace
uninitialised pointers.

#### 1.1b GC-owned code — **done**

Solis no longer retains anything. Over 60,000 REPL lines, peak resident set went
from **25.5 MB, growing linearly, to 1.9 MB, flat**.

Ownership is dual rather than wholesale, because Solas has no VM to own a chunk
on its behalf. A `SolChunk` created by `sol_chunk_init` is caller-owned and freed
by hand, as Solas and the tests do; one created by `sol_code_new` belongs to a
`SolCode` cell the collector sweeps. `sol_chunk_add_method` propagates ownership
as each subtree is added, so a caller cannot forget to.

Two things this turned up:

- A block caches its owning cell rather than reading it back through
  `block->code->chunk`. A caller-owned chunk can be freed while blocks pointing
  into it are still on the heap; calling such a block was always wrong, but the
  tracer must not fault merely for walking past one. Stress mode under ASan found
  this as a use-after-free in `mark_code`.
- A chunk's constants are traced, since they will hold heap values as soon as
  strings exist.

#### 1.1c Temporary roots for primitives

The mechanism exists -- `sol_gc_push_temp` / `sol_gc_pop_temp`, used by Solis to
protect a fresh code cell across compilation. What remains is applying it inside
primitives, which only matters once one of them allocates. Today none do: the
sole allocation reachable from running code is `sol_block_new` at `OP_BLOCK`,
where everything live is already on the stack or in globals. Strings end that,
because concatenation allocates while holding intermediates in C locals the
collector cannot see. Build it with 1.2.

### 1.2 Strings

`"hello"` scans to a token and the compiler rejects it with a clear message.
Making it real means the first heap-allocated value with contents, which is what
makes 1.1 matter rather than merely accrue. Needs interning or not (decide),
`print`, concatenation, comparison, and a constant tag in `.sob`.

### 1.3 User-defined classes

Slots can only be added to the built-ins. Nothing in the language creates a new
object with slots of its own, so `point:new(#3, #4)` is out of reach. Needs a
primitive that makes an object with a given proto, and a decision about how a
class is spelled — probably just an object bound to a global, given how far
`obj:name := value` already goes.

### 1.4 Collections and an iteration protocol

There are no arrays or lists at all. Block parameters exist and no built-in
protocol uses them yet — `do:`-style iteration is the obvious first customer.
Depends on 1.1 and 1.3.

---

## 2. Language decisions still open

### 2.1 Division — **decision**

Deliberately absent. Under strict typing, integer division has to pick one:

- truncate toward zero (C, Java),
- floor (Python, Smalltalk),
- or answer a float, which breaks strictness since `#7:div(#2)` would leave the
  integers.

Modulo follows whichever is chosen, and the sign rules follow from it.

### 2.2 Statement terminator — **decision**

`.` is currently optional, which accepts the original notes as written but means
a missing terminator can never be caught. Making it required is a one-line
change; leaving it optional is fine too, but it should be a choice rather than an
accident.

### 2.3 Class side versus instance side

`integer` holds both `new` and `print` in one object, so `#45:new(#1)` resolves as
readily as `integer:new(#1)`. Separating them needs a metaclass level. Also
uneven today: `integer` has `new` and `float` does not.

### 2.4 Symbols

`'foo` scans to a token and has no runtime type. Wanted for reflection and any
`perform:`-style dynamic send. Cheap once strings exist.

### 2.5 Missing operations

Small, mechanical, and worth doing in one pass once 2.1 settles the numeric
questions:

- booleans: `and`, `or` (short-circuit, so they take blocks like `ifTrue` does)
- comparison: `lessOrEqual`, `greaterOrEqual`, `notEquals`
- numbers: division, modulo, negation, absolute value
- `float:new`, for symmetry with `integer:new`
- `nil` answers almost nothing

---

## 3. Known limitations

These are deliberate, safe, and documented. Each is a real restriction rather
than a bug.

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

### 3.4 No compatibility across `.sob` versions

Each opcode-set change bumps the version and older files are refused outright.
Fine while nothing is released; worth a policy before anything is.

---

## 4. Performance

Nothing here is urgent — the VM is written for clarity first — but each has a
known shape.

### 4.1 Conditionals are real calls

`ifTrue` is a message, so every conditional costs a block allocation and a frame.
Production Smalltalks recognise these selectors in the compiler and emit jumps
instead. That is an optimisation, not a change to what the language means.

It needs jump opcodes, which in turn changes the verifier: today it is enough
that the **final** instruction stops the machine, because execution is linear.
With jumps that has to become a check that every target lands on an instruction
boundary.

### 4.2 One-byte operands

`OP_CONST`, `OP_SEND`, and the name operands carry a single byte, capping a chunk
at 256 constants and 256 names. A `CONST_LONG`-style variant is the fix when a
real program hits it.

### 4.3 Dispatch does a string compare per send

`sol_object_lookup` walks a linked list comparing names with `strcmp`. Interned
symbols with pointer equality, or an inline cache per send site, are the usual
answers.

---

## 5. Tooling and ergonomics

### 5.1 Solis is line-at-a-time

`fgets` per line, so a method body spanning several lines has to go in a file.
The REPL should buffer until brackets and parentheses balance.

### 5.2 `print` on an object dumps its address

`sol_value_print` prints `<object 0x...>` instead of sending `print` to the
object. Wants dispatch from inside the printer, or a `printOn:`-style protocol.

### 5.3 No source position beyond the line

Errors report a line number and nothing finer. Columns and the offending source
text would make compile errors considerably more useful.

---

## Suggested order

1. ~~**Garbage collection** (1.1a, 1.1b)~~ — done. 1.1c lands with strings.
2. **Strings** (1.2) — the first real heap value, and the thing that proves the
   collector.
3. **User-defined classes** (1.3), then **collections** (1.4).
4. **Division** (2.1) and the **missing operations** (2.5) — small, and they make
   the language usable for arithmetic-shaped programs.
5. Everything else as it starts to hurt.
