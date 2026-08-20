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

The language is Turing-complete, no longer leaks, and now has strings, arrays,
and user-defined objects. What it lacks is mostly breadth: no conversions between
types, a thin set of operations, and rough edges around printing and literals.

**Two crashes are open and lead the list** — 1.5 and 1.6, both reachable from
three words of source, both found by fuzzing work that did not cause them.


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

The next two are why this section is not empty after all, and they are the only
urgent items in this document. Both crash the VM outright, both are reached from
three words of ordinary source, and the REPL goes down the same way. Neither
came from the work that found them — fuzzing the inlined loops turned them up,
and both bisect to commits well before it — but a crash belongs here rather than
among the known limitations, and ahead of everything in sections 4 and 5.

They are one bug wearing two hats: a class object holds the messages its
*instances* understand, and answers them itself.

### 1.5 `array:print` crashes the VM — **open, high priority**

```
array:print.        ; segmentation fault
block:print.        ; segmentation fault
array:asString.     ; segmentation fault
```

Found by fuzzing the loop work, bisected to `f55e105` — the commit that made
`print` on an object ask the object (5.2). It has nothing to do with jumps, and
three words of ordinary source reach it; the REPL goes down the same way.

The cycle is exact. Rendering an `SOL_OBJ` sends it `asString`. For the class
objects `array` and `block`, lookup starts at the object itself and finds the
`asString` those classes define for their *instances*, which is
`prim_rendered_as_string` — and that calls the renderer back on the same value.
`render` does carry a depth, and the array case uses it, but the count restarts
at zero every time the recursion leaves through `sol_value_render`. Nothing
bounds it, and it is C recursion, so `SOL_FRAMES_MAX` never sees it: a primitive
called from `sol_vm_send` does not push a VM frame.

The comment at `value.c` says the default `asString` on `object` "is what stops
the renderer's ask-the-object from recurring forever". That is true of an
ordinary object and false of a class object, which is the gap.

The fix is to carry the depth across the send rather than restart it — hold it
on the VM, seed `sol_value_render` from it, and let a cycle bottom out the way a
self-containing array already does with `[...]`. Wants its own commit and its
own tests.

Worth doing 1.6 first and looking again: a receiver check on
`prim_rendered_as_string` would answer "expects an array, got object" here and
never start the cycle, which may leave nothing for this entry to fix. The depth
that restarts would still be wrong in principle, and cheap to make right while
the file is open.

### 1.6 A class object answers its instances' messages — **open, high priority**

```
array:add(#1).      ; abort
array:size:print.   ; #0, read from whatever `array` is not
```

`array` is an object whose slots are the messages an *array* understands, and
sending one to `array` itself finds it. `prim_array_add` then does
`SOL_AS_ARRAY(self)` on the class object, because a primitive reached through a
class has always been able to assume its receiver's type. That assumption holds
for every instance and fails for the one object that is not one.

Some primitives happen to check — `concat` and `add` on other types answer a
proper "expects a string, got object" — so the gap is uneven rather than total,
which is its own argument for fixing it in one place. Found by fuzzing the loop
work, and present as far back as the array primitives; 1.5 is the same shape
reached through the renderer.

The fix is a receiver check the class-side primitives share, rather than 40
copies of the same `if`. It touches every built-in class, so it wants its own
commit; 2.5 (class side versus instance side) is the design question underneath
it, and answering that first may make this fall out.

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

### 2.2 Statement terminator — **decided: a separator, required between**

`.` separates statements rather than terminating them: required between two,
optional after the last. That is what groups and blocks already enforced; the top
level used to accept its absence anywhere, so a missing one could never be
reported and the same code stopped compiling merely by being moved into a method
body.

```
a := #1
b := #2          ; solas: expected '.' between statements at 'b'

a := #1. b := #2 ; fine -- the last needs none
```

Groups and blocks now name the missing separator too, where they used to
complain about the closing bracket and send the reader looking in the wrong
place.

Nothing existing broke, since every example and test already wrote the dots.

**What it does not catch**, recorded so it is a known limit rather than a
surprise: a line beginning with `:` continues the expression above it, so

```
total := #10
:add(#5).
```

is genuinely one statement and no separator is missing. Only a
newline-sensitive rule would see those as two, and Solveig is not that.

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

User-defined objects sharpen this. The built-in classes deliberately do *not*
delegate to `object`, because `float` inheriting object's `new` would answer a
plain object rather than a float -- so the built-in and user-defined sides are
two hierarchies that do not meet. A single root would be tidier, and needs this
question answered first.

### 2.6 Float exponents — **done**

`1e3`, `1E+3`, `1.5e-3`, `1e308`. A bare `e` is left alone rather than claimed,
so `1e` stays a float followed by an identifier -- which the statement rule then
rejects as two things with no separator, a clearer failure than a malformed
number. `#` is exact, so an integer takes no exponent.

### 2.13 Case and text are ASCII only

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

### 2.7 Symbols — **done**

`'foo` is an interned name. Two symbols spelling the same thing are the same
symbol, so equality is a pointer comparison rather than a walk over characters --
which is the whole reason to have them apart from strings, a name being compared
far more often than it is read. `"foo":asSymbol` finds the one that already
exists.

**The intern table is weak**, and that turned out to matter more than memory.
With a strong table a program interning twenty thousand names does not finish in
sixty seconds, because every collection has to mark every symbol ever interned.
With a weak one the same program runs instantly at 1.7 MB. Pruning happens
between marking and sweeping, so the table never names a cell the sweep is about
to free.

A symbol never equals a string; `asString` gives its name.

### 2.8 Missing operations — **done**

Conversions: `asString` on every value, `asFloat` on integers, `floor` /
`ceiling` / `rounded` / `truncated` on floats, and `asInteger` / `asFloat`
parsing back from a string.

Logic: `and` and `or`, short-circuit, taking a block as `ifTrue` does -- which is
the reason they cannot simply take booleans.

Comparison: `notEquals` everywhere, defined as the negation of `equals` so the
two cannot disagree about what equality means for a type; `lessOrEqual` and
`greaterOrEqual` on numbers and strings; and ordering on strings, by characters
with the shorter first when one is a prefix.

Numbers: `negated` and `abs`, trapping on the most negative integer, which has no
positive counterpart. `float:new`, for symmetry with `integer:new`.

Rendering moved into one place -- a text buffer in `value.c` -- so `print` and a
composite's `asString` produce the same text by construction rather than by
agreement.

Still absent, and small: `isNil`, though `x:equals(nil)` says it.

Sorting is done: `sorted` and `sorted(block)`, stable, ordering by a real send of
`lessThan` so a user-defined type sorts itself.

---

### 2.9 Calling the method you override — **decided: `via`**

```
animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro.        ; "I am rex!"
```

`self:via(ancestor)` answers a delegating view: a send to it begins the lookup at
the ancestor but runs whatever it finds with `self` still the receiver. Naming
the ancestor directly would send to *it*, so `self` inside would become the
ancestor.

The ancestor is **named rather than inferred**. A `super` keyword would have to
resolve against the object where the running method was *defined*, which is
bookkeeping no frame carried; naming it needs none of that, keeps working however
deep the receiver turns out to be, and cannot accidentally find the method again
and recurse.

`parent` reads the delegation link, so a chain can be walked and compared. It is
read-only: the link stays an internal pointer, so nothing a program writes can
corrupt dispatch. Re-parenting at run time would need it to become a real slot,
which is a separate question.

### 2.10 Reflection — **done**

`slots`, `slotAt`, `respondsTo`, `isKindOf`, and `perform`, on every type. Names
are given as symbols, which is what 2.7 was wanted for.

`slots` answers own slots in definition order; the rest search the chain as a
send does. A value answers for the class it dispatches to, so
`#45:isKindOf(integer)` holds, and the built-in classes are objects whose slots
hold primitives, so `integer:slots` lists what an integer understands.

Two things this deliberately does not do:

- **A fetched method is unbound.** `slotAt` answers the plain block, and `self`
  comes from a send rather than being carried by the block, so `m:value` runs
  with `self` nil. Calling a method with a chosen receiver would need something
  like `valueWith(receiver, ...)`, which is a real question and not this one.
- **Nothing here can write.** There is no `slotAtPut`, no re-parenting (2.9a),
  and no way to remove a slot. Reflection reads; the assignment syntax writes.

### 2.11 Filling a template — **decided: placeholders and `fill`**

```
"you have {} apples and {} pears":fill([#3, #4]).
```

`{}` takes the next value and renders it by **sending** it `asString`, so a type
that overrides `asString` is honoured rather than bypassed. `{{` writes a literal
brace.

Placeholders and values must match exactly; too few and too many are both errors.
Filling a gap with blanks, or dropping the extras, would turn a mistake into
output that looks deliberate.

`}` is never special and needs no escape, so `}}` is two of them. That differs
from Python, where `}` closes a placeholder that may carry content -- here a
placeholder is exactly `{}`, so a lone `}` cannot be ambiguous and one escape
rule is enough.

Kept as a separate message rather than an argument to `print`, so `print` goes on
meaning one thing and the filled text can be used without printing it.

Named `fill` rather than `format`. The placeholders are blanks and this fills
them; `format` belongs to formatting a *single value* against a spec, where the
value is the receiver. `"...":fill(...)` is a template acting on values, which is
a different job from `45.8:asString("5.2")`. Not `replace`, which
`string:replace(old, new)` will want.

This needed `sol_vm_send`, so a primitive can call back into the language. That
is also what 5.2 wants, to make the default `print` on an object send `print` to
it rather than showing an address.

## 3. Known limitations

These are deliberate, safe, and documented. Each is a real restriction rather
than a bug.

### 2.12 Formatting a single value — **done**

An optional spec argument to `asString`:

```
[align] [','] ['0'] [width] ['.' decimals]

45.8:asString("6.2")         ->  " 45.80"
45.8:asString("08.2")        ->  "00045.80"
#1234567:asString(",")       ->  "1,234,567"
1234.5:asString(",10.2")     ->  "  1,234.50"
"ab":asString(">6")          ->  "    ab"
```

Smaller than printf on purpose. **No conversion letter** -- the receiver knows
its own type, so there is nothing that could contradict it. **No sign mode** -- a
leading space for a positive number falls out of the width, since numbers align
right, which removed a whole mode from the design.

Numbers align right and text aligns left by default; `<`, `>`, `^` override.
Decimals belong to floats, and asking an integer, a string, a boolean, or an
array for them is an error rather than a no-op. Zero fill must align right, since
padding a number on the left with zeros would change what it says, and the zeros
go after any sign so `-45` in width 6 is `-00045`. A value wider than the width
is never cut: losing digits would be worse than a ragged column.

No argument means what it always meant, so `display`, `fill`, and array rendering
are untouched.

`,` groups whole-number digits in threes, and only those: a sign, a fraction, and
an exponent pass through untouched. It is fixed at `,` rather than configurable,
a separator that varies by locale being a much larger door to open than a report
column is worth. It cannot be combined with zero fill, since the leading zeros
would not themselves be grouped -- Python renders that as `001,234.50`, which
reads as a mistake -- and the flags have one order, so there is one way to write
a given spec.

Two extensions considered and **not** built:

- **Forcing exponent form**, `"10.2e"`. The renderer already switches on
  magnitude, so this only serves a table that wants `1.00e+00` on every row
  regardless of size. Against it: `e` looks exactly like the conversion letter
  deliberately left out, and invites the reader to try `f` and `d`, which do not
  exist. Worth adding when something needs it, not before.
**Integer bases are done**, but not as a spec letter. `#255:asBase(#16)` answers
`"ff"`, and `"ff":asInteger(#16)` reads it back. A letter would have looked like
printf's conversion character, the very thing the spec was designed without, and
one letter buys one base where a number buys all thirty-five. Padding still comes
from the spec, by chaining: `#255:asBase(#16):asString("08")`.

Digits above nine are lowercase; `asUppercase` gives the other form, which is why
a case message was the right answer rather than a second base message.

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

### 4.2 One-byte operands

`OP_CONST`, `OP_SEND`, and the name operands carry a single byte, capping a chunk
at 256 constants and 256 names. A `CONST_LONG`-style variant is the fix when a
real program hits it.

### 4.3 Dispatch does a string compare per send

Symbols now exist, and interned names are exactly what this wants: a selector
compared by pointer rather than by `strcmp`. The work is in the chunk's text
table and slot names, not in inventing the mechanism.

`sol_object_lookup` walks a linked list comparing names with `strcmp`. Interned
symbols with pointer equality, or an inline cache per send site, are the usual
answers.

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

**That is true of an ordinary object and false of a class object**, which is
1.5: `array:print` smashes the C stack today. Lookup on `array` starts at the
object itself and finds the `asString` that class defines for its instances,
which renders -- and the depth `render` carries restarts at zero on the way
back in. Found by fuzzing the loop work, and bisected to this commit.

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
crashes back into it, and those are the only urgent items on this list:

1. **`array:add(#1)` aborts** (1.6) — a class object answers the messages its
   instances understand, and the primitive reads it as an instance. First
   because a shared receiver check is the fix, and it may take the next one with
   it. 2.5 is the design question underneath.
2. **`array:print` smashes the C stack** (1.5) — the same shape through the
   renderer, which asks an object for `asString` and gets the one meant for its
   instances. Look again after 1.6; the depth that restarts is worth fixing
   either way.

Three words of ordinary source reach either, and the REPL goes down the same
way, so they outrank everything below however small the fix turns out to be.
After them, nothing is urgent. The rest are roughly in order of how soon they
would be missed:

3. **A bigger constant pool** (4.2) — a literal-heavy program hits the 256-entry
   cap well before anything else. Sorting two thousand literals was not possible
   without generating them at run time.
4. **Dispatch by pointer** (4.3) — symbols exist; a send still does `strcmp`.
5. **Calling a fetched method** — `slotAt` hands back an unbound block (2.10).
6. **Inlining `and` and `or`** (4.1) — the last two that short-circuit through a
   block. Nothing new is needed; the jumps are all there now.
7. **Stack heights in the verifier** (3.9) — would catch a corrupted argument
   count at load rather than at the send, and let the runtime checks go.
8. Everything else as it starts to hurt.

Done and off this list: garbage collection (1.1a, 1.1b, 1.1c), arrays entire
(1.2, 1.2a, 1.2b), strings (1.3), user-defined objects (1.4), division (2.1),
calling the method you override (2.9), the missing operations (2.8),
formatted output (2.11), the statement separator (2.2), float exponents and
round-tripping (2.6, 5.3), string escapes (1.3), rendering an object by asking
it (5.2), symbols (2.7), reflection (2.10), sorting, and inlined conditionals
and loops (4.1).

One decision is outstanding, and it now has two crashes resting on it: **2.5**,
class side versus instance side. Answering it may make 1.5 and 1.6 fall out.

Still waiting on a call from you: **division** (2.1) and the **statement
terminator** (2.2). Neither blocks anything above it.
