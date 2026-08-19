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

The language is Turing-complete and no longer leaks. What it is not yet is a
language you could write a real program in — there are no strings, no
collections, and no way to make a class.

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
which is the point. Capped at 255 elements by `OP_SEND`'s one-byte argument
count (4.2).

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

- **No escape sequences.** A string cannot contain a `"` or a newline written as
  `\n`, though a literal newline inside the quotes does work. Wants `\"`, `\n`,
  `\\` at least, which is lexer work.
- **Not interned.** `OP_STRING` allocates on every evaluation, so a literal in a
  loop makes a string per pass. Immutability means that is only a cost, never a
  semantic difference. Interning would fix it and give 4.3 its mechanism, but
  needs a weak table so interned strings can still die.
- **No ordering.** `lessThan` is not defined on strings, so they cannot be
  sorted.
- **No conversions.** Nothing turns a number into a string or back.

### 1.4 User-defined classes

Slots can only be added to the built-ins. Nothing in the language creates a new
object with slots of its own, so `point:new(#3, #4)` is out of reach. Needs a
primitive that makes an object with a given proto, and a decision about how a
class is spelled -- probably just an object bound to a global, given how far
`obj:name := value` already goes.

Moved after arrays: arrays are useful on their own, whereas a user-defined class
with nowhere to put a collection of instances is less so.

## 2. Language decisions still open

### 2.1 Division — **decided: floored, answering an integer**

`div` and `mod` on integers and floats.

Answering an integer was not really a free choice: a float result would let two
integers leave their type silently, which is the implicit coercion the language
refuses everywhere else. A fractional result therefore needs an explicit
conversion, which is why 2.8 matters more now than it did.

Floored rather than truncated, so the two differ only on negatives: `#-7:div(#2)`
is `#-4`. Floor was chosen for what it does to `mod` -- a floored remainder always
lands in `[0, n)` for positive `n`, which is what indexing, hashing, and cyclic
arithmetic want, where a truncated one takes the dividend's sign and needs
correcting at every use site. It is also Smalltalk's choice. The truncating pair
keeps the names `quo` and `rem` free if it is ever wanted alongside.

Division by zero splits along a line the language already had: integers trap,
because there is no integer infinity, while floats answer an infinity, because
float multiplication already overflows to one where integer multiplication traps.

`INT64_MIN div #-1` is guarded separately. It is the one division that overflows,
and in C it is undefined rather than merely wrong -- it raises SIGFPE on x86
rather than answering anything.

### 2.2 Statement terminator — **decision**

`.` is currently optional, which accepts the original notes as written but means
a missing terminator can never be caught. Making it required is a one-line
change; leaving it optional is fine too, but it should be a choice rather than an
accident.

### 2.3 Array indexing base — **decided: one-based**

An index in Solum is an ordinal, not an offset. There is no pointer arithmetic
and no address to be a displacement from, so the argument that makes zero-based
natural in C does not apply here. One-based also matches the Smalltalk lineage
the object model already came from.

Two consequences to carry forward:

- `at(#0)` is out of bounds, and so is caught rather than quietly reading the
  wrong element. A small safety win that falls out of the choice.
- Any later range or slice API should follow Smalltalk and use inclusive bounds
  on both ends. Half-open ranges are what make zero-based tidy; mixing a
  half-open convention into one-based indexing is where languages get confusing.

### 2.4 Array literal syntax — **decided: `[...]`, pure sugar**

`[#1, #2, #3]` compiles to exactly the bytecode for `array:of(#1, #2, #3)` -- the
same send, the same fresh mutable array. The two spellings are the same thing,
with no semantic difference whatever.

That costs almost nothing: two lexer tokens and one compiler branch. No new
opcode, no verifier change, no `.sob` change -- the VM never learns that array
literals exist.

Rejected: making `[...]` immutable so it could be pooled as a constant. Pooling
would only ever apply when every element is itself a compile-time constant
(`[a, b]` must be built at run time regardless), and the price is a rule the
reader has to re-check at every use site. See the design principle on two
spellings meaning one thing.

Both spellings cap at 255 elements, since `OP_SEND` carries a one-byte argument
count (4.2). Beyond that the compiler would need to fall back to `new` plus
repeated `add`.

### 2.5 Class side versus instance side

`integer` holds both `new` and `print` in one object, so `#45:new(#1)` resolves as
readily as `integer:new(#1)`. Separating them needs a metaclass level. Also
uneven today: `integer` has `new` and `float` does not.

### 2.6 Float literals have no exponent notation

`1e308` does not scan. It reads as the float `1` followed by an identifier
`e308`, so there is no way to write a very large or very small float at all.
Lexer work: an optional `e`/`E`, optional sign, and digits after the fraction.

### 2.7 Symbols

`'foo` scans to a token and has no runtime type. Wanted for reflection and any
`perform:`-style dynamic send. Cheap once strings exist.

### 2.8 Missing operations

Small, mechanical, and worth doing in one pass once 2.1 settles the numeric
questions:

- booleans: `and`, `or` (short-circuit, so they take blocks like `ifTrue` does)
- comparison: `lessOrEqual`, `greaterOrEqual`, `notEquals`, and ordering on
  strings so they can be sorted
- numbers: negation, absolute value
- **conversions**: `asFloat`, `asInteger`, and something turning a number into a
  string. Now the most missed of these, since floored integer division means
  there is otherwise no way to get a fractional answer from two integers.
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

That is low enough to be hit by ordinary code. Three ways out, in increasing
order of work: raise the cap, which costs stack because `SOL_STACK_MAX` is
derived from it; inline conditionals so a branch does not cost a frame (4.1),
which roughly doubles the usable depth; or make the limit dynamic rather than a
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

Doing this also roughly doubles the usable recursion depth (3.5), since a
conditional branch would stop costing a frame.

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

### 5.3 Float printing does not round-trip

`print` emits float text the scanner cannot read back. A large float prints as
`1e+256`, and feeding that to the compiler gives `solas: unexpected character` --
partly because of 2.6, partly because `%g` will also produce `inf` and `nan`,
which have no literal form at all. Output that cannot be read back is a trap for
anyone generating source, and for any future test that round-trips values.

### 5.4 No source position beyond the line

Errors report a line number and nothing finer. Columns and the offending source
text would make compile errors considerably more useful.

---

## Suggested order

1. **User-defined classes** (1.4) — the last thing standing between this and a
   language you could write a real program in.
2. **Conversions** (2.8) — `asFloat`, `asInteger`, number-to-string. Now the most
   missed, since floored integer division leaves no way to get a fractional
   answer from two integers.
3. **The rest of the missing operations** (2.8), **string escapes and ordering**
   (1.3), and **float exponents** (2.6) — small and independent of each other.
4. Everything else as it starts to hurt.

Done and off this list: garbage collection (1.1a, 1.1b, 1.1c), arrays entire
(1.2, 1.2a, 1.2b), strings (1.3), and division (2.1).

Still waiting on a call from you: the **statement terminator** (2.2).

Still waiting on a call from you: **division** (2.1) and the **statement
terminator** (2.2). Neither blocks anything above it.
