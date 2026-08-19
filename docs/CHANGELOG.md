# Changelog

Notable changes to Solveig, newest first. Nothing is released yet, so everything
below is under `0.0.1` and the syntax is still moving.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md).

## Unreleased — 0.0.1

### The virtual machine is `bin/solvm` — `pending`, 2026-08-19

**Breaking: the command changed.** `./bin/solum program.sob` is now
`./bin/solvm program.sob`.

The machine has been called SolVM in prose since the project was named, while the
program on disk was still `solum`. Now they agree.

Its own messages agree too — a runtime error reads `solvm:` rather than `solum:`,
as do the fatal allocation failures in the runtime library.

The **sources stay under `solum/`**, and the include paths and `SOLUM_*` macros
with them. `solum` and `SOLVM` are the same word in two hands, so the directory
keeps the modern spelling and the program the older one. Renaming the tree as
well would touch every `#include` in the project for no gain a reader would feel.

### An object is rendered by asking it — `f55e105`, 2026-08-19

```
point:asString := { "point({}, {})":format([self:x, self:y]) }.

p:print.                     ; point(3, 4)
[p, q]:print.                ; [point(3, 4), point(0, 0)]
"at {}":format([p]):display. ; at point(3, 4)
```

One definition serves `print`, `display`, `format`, and an enclosing array,
because the renderer sends `asString` rather than reaching for a pointer.

The seam had to move: `sol_value_render` now takes a VM, which may be null. The
disassembler passes null — its constants are never objects — and falls back to
the address, which is also what an object without its own `asString` shows.

The recursion this invites is cut at the source: `object`'s default `asString`
writes the address directly instead of calling the renderer back. An `asString`
a user writes to render itself still recurses, but through real frames, so it
stops at the call-depth cap like any other runaway recursion.

### Fixed: error recovery could loop forever — `f55e105`

`synchronise` checked whether the previous token was a `.` *before* advancing, so
a statement that failed without consuming anything — `primary` reports an
unexpected token without taking it — was retried forever when the token before it
happened to be a `.`.

`b := { #1. | q | q }.` produced **three million identical error lines in three
seconds**. Recovery now advances before testing, so it always consumes at least
one token.

Pre-existing, and found by a typo in a test rather than by looking for it. Six
malformed inputs that used to hang are now regression tests.

### String escapes, and `display` — `c04cdca`, 2026-08-19

```
q := "she said \"hi\"".
q:print.                                     ; "she said \"hi\"" -- literal form
q:display.                                   ; she said "hi"      -- the text
"you have {} apples":format([#3]):display.   ; you have 3 apples
```

`\"`, `\\`, `\n`, `\t`, `\r`. An unknown escape is an error rather than a
literal backslash, so a typo is caught where it is written. There is no `\0`:
the chunk's text table is NUL-terminated in memory and one would truncate the
string.

The scanner only learns that a backslash claims the next character, so that `\"`
does not end the string. Which escapes are legal is decided once, in the
compiler, where they are decoded.

**Rendering puts the escapes back**, or a string holding a quote would render as
text that no longer reads as one string. A rendered string now compiles back to
the same string, the same round-trip floats hold to.

**`display`** was the gap escapes exposed. `print` shows the literal form, which
is right for reading a value back but wrong for output — a formatted string could
only be shown wearing quotes, and a string with newlines could not be written as
lines at all. `display` sends `asString` and writes those characters raw. Every
type answers it.

### Float exponents, and text that reads back — `c8cef1b`, 2026-08-19

```
a := 1.5e-3.  b := 1e308.        ; exponents scan now
1234567.0:print.                 ; 1234567   -- was 1.23457e+06
1.0:div(3.0):print.              ; 0.3333333333333333
infinity:print.  nan:print.
```

**This was a correctness bug, not only a cosmetic one.** `%g` gives six
significant digits, so `1234567.0` printed as `1.23457e+06` — a *different
number* — and `asString` baked that into a string. Printing could quietly show
the wrong value.

- A float now renders as the **shortest decimal that reads back as the same
  bits**, found by trying increasing precision until the text parses back
  identically.
- Shortest is not always clearest, so where a number has few enough whole digits
  the renderer keeps `%g` in fixed notation: `1000` rather than `1e+03`. More
  digits can never stop it round-tripping.
- Exponent notation scans: `1e3`, `1E+3`, `1.5e-3`. A bare `e` is left alone
  rather than claimed, so `1e` is a float and an identifier — which the statement
  rule then rejects, a clearer failure than a malformed number. `#` is exact, so
  an integer takes no exponent.
- Infinity and not-a-number are written by name, and `infinity` and `nan` are now
  globals, so those two read back. `-infinity` has no literal form; `asFloat`
  parses it.

The fix caught a drift it was meant to prevent: `prim_float_as_string` had its own
`snprintf("%g")` instead of using the renderer, so `print` and `asString`
disagreed about the same value until it was routed through.

Tested by rendering fifteen awkward doubles, feeding the text back in as source,
and requiring the result to be bit-identical.

### `.` is required between statements — `be13b07`, 2026-08-19

**Breaking, though nothing in the repository changed: every example and test
already wrote the dots.**

`.` separates statements rather than terminating them — required between two,
optional after the last:

```
a := #1
b := #2          ; solas: expected '.' between statements at 'b'

a := #1. b := #2 ; fine, the last needs none
```

This is what groups and blocks already enforced. The top level accepted its
absence anywhere, which meant a missing separator could never be reported, and
the same code stopped compiling merely by being moved into a method body.

Groups and blocks now name the missing separator as well, where they used to
complain about the closing bracket and send the reader looking in the wrong
place.

**It does not catch everything.** A line beginning with `:` continues the
expression above it, so `total := #10` followed by `:add(#5).` is genuinely one
statement with no separator missing. Only a newline-sensitive rule would see two,
and this is not that language. There is a test pinning the behaviour so it stays
a known limit rather than a surprise.

### Formatted output — `ca1369b`, 2026-08-19

```
"you have {} apples and {} pears":format([#3, #4]).
```

`{}` takes the next value and renders it by **sending** it `asString`, so a type
that overrides `asString` is honoured rather than bypassed:

```
point:asString := { "point(":concat(self:x:asString):concat(")") }.
"the answer is {}":format([p]).        ; "the answer is point(7)"
```

- **Both directions of mismatch are errors.** Too few values and too many are
  each reported with the counts. Filling a gap with blanks, or dropping extras,
  would turn a mistake into output that looks deliberate.
- `{{` writes a literal brace. `}` is never special and needs no escape, so `}}`
  is two of them — unlike Python, where `}` closes a placeholder that can carry
  content. Here a placeholder is exactly `{}`, so one escape rule is enough.
- Kept as its own message rather than an argument to `print`, so `print` goes on
  meaning one thing and the text can be used without printing it.

This needed **`sol_vm_send`**, a way for a primitive to call back into the
language. That also unblocks a better default `print` (5.2), which wants to send
`print` to an object rather than showing its address.

### The remaining operations — `7ac6be6`, 2026-08-19

```
x:greaterThan(#0):and({ x:lessThan(#10) }).   ; short-circuit
"abc":lessThan("abd").                        ; strings order
#-5:abs.  #5:negated.  #1:notEquals(#2).
[#1, "a", [#2]]:asString.                     ; "[#1, \"a\", [#2]]"
```

- **`and` and `or` take a block**, so the answer can be settled without running
  it — the same shape as `ifTrue`, and the reason they cannot simply take
  booleans. Strict about what the block answers, as `whileTrue` is.
- **`notEquals` is defined as the negation of `equals`**, so it inherits whatever
  equality means for each type: by value for strings, by identity for arrays.
- **Strings order** by characters, shorter first when one is a prefix — what
  sorting will want. `lessOrEqual` and `greaterOrEqual` on numbers and strings.
- `negated` and `abs`, trapping on the most negative integer, which has no
  positive counterpart — the same edge that guards `INT64_MIN div #-1`.
- `float:new`, for symmetry with `integer:new`.
- **Rendering moved into one place**, a text buffer in `value.c`, so `print` and a
  composite's `asString` produce the same text by construction rather than by
  two implementations agreeing.

Also records **formatted output** (2.11) as an open decision: building a sentence
is currently a chain of `concat` and `asString`, workable for two pieces and
unreadable for five.

### Conversions — `246ae8e`, 2026-08-19

```
"you have ":concat(#45:asString):concat(" apples").   ; "you have 45 apples"
#7:asFloat:div(#2:asFloat).                           ; 3.5
2.7:floor. 2.7:ceiling. 2.7:rounded. 2.7:truncated.   ; #2 #3 #3 #2
"45":asInteger.  "2.5":asFloat.
```

- **`asString` answers plain text; `print` shows the literal form.** `#45:asString`
  is `"45"`, not `"#45"` — the point of it is building text, and "you have #45
  apples" would be wrong. Two jobs, kept apart, as Smalltalk separates
  displayString from printString.
- **Narrowing names its direction.** There is no `asInteger` on a float: `floor`,
  `ceiling`, `rounded`, and `truncated` each say what they do, so there is no
  default to remember. Each can fail, since most floats have no integer
  counterpart — infinity, not-a-number, and anything out of range are errors.
- **Parsing is strict at both ends.** The whole string must be a number and
  nothing else, so `"12abc"`, `""`, `" 45"` and `"45 "` are all errors. The
  leading-space case needed an explicit check, since `strtoll` skips whitespace
  of its own accord and the two ends would otherwise have behaved differently.
- Widening an integer past 2^53 loses precision silently, which is what binary64
  is; erroring would be unlike every other language.

This also fills the gap floored division left: `#7:div(#2)` is `#3`, and
`#7:asFloat:div(#2:asFloat)` is `3.5`.

### `via`: calling the method you override — `a5aa9e0`, 2026-08-19

```
animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro.        ; "I am rex!"
```

Before this, an override could reach the ancestor's *code* but not with the right
receiver — naming the ancestor sends to it, so `self` inside became the ancestor
and `rex:intro` answered `"I am animal!"`. An overriding method could therefore
only extend one that never consulted `self`.

`self:via(ancestor)` answers a delegating view: a send to it begins the lookup at
the ancestor and runs what it finds with `self` still the receiver.

- **The ancestor is named rather than inferred.** A `super` keyword would have to
  resolve against the object where the running method was *defined*, which is
  bookkeeping no frame carried. Naming it needs none of that, stays correct
  however deep the receiver is, and cannot find the method again and recurse.
- `parent` reads the delegation link so a chain can be walked. Read-only: the
  link stays an internal pointer, so nothing a program writes can corrupt
  dispatch.
- Dispatch needed one change — a delegate receiver rewrites its own stack slot to
  the real receiver before lookup, after which every existing path reads `self`
  correctly without knowing delegates exist.

### User-defined objects — `d27176f`, 2026-08-19

```
point := object:new.
point:x := #0.                          ; a default every instance sees
point:sum := { self:x:add(self:y) }.    ; a method: a slot holding a block
point:make := { a, b | | p | p := self:new. p:x := a. p:y := b. p }.

p := point:make(#3, #4).
p:sum:print.                            ; #7
```

One primitive — `object:new`, answering a fresh object that delegates to the
receiver. That was the whole gap: slot assignment, proto-chain lookup, and
block-in-a-slot-is-a-method already existed, so this needed a primitive rather
than a mechanism.

- **There is no separate notion of a class.** An object given slots, and an
  object created from *that*, differ only in how you use them.
- Assigning on an instance always makes the instance's own slot, so it shadows
  the prototype rather than writing through — one instance cannot change all of
  them.
- Delegation chains, and the nearest slot wins, so overriding works at any depth.
- Equality is identity: two objects with the same slots are still two objects.
- The default `print` is overridable, since a `print` slot on the prototype is
  found before the primitive.

The built-in classes deliberately do not delegate to `object`: `float` inheriting
its `new` would answer a plain object rather than a float. That leaves two
hierarchies that do not meet, which is the class-side/instance-side question in
the roadmap.

### Division — `9ad8039`, 2026-08-19

`div` and `mod`, on integers and floats.

```
#7:div(#2):print.     ; #3
#-7:div(#2):print.    ; #-4   floored, not truncated
#-7:mod(#2):print.    ; #1    the divisor's sign, not the dividend's
```

- **Answering an integer was forced rather than chosen.** A float result would
  let two integers leave their type silently, which is the coercion the language
  refuses everywhere else. A fractional answer needs an explicit conversion —
  which does not exist yet, and is now the most-missed missing operation.
- **Floored, for what it does to `mod`.** A floored remainder always lands in
  `[0, n)` for positive `n`; a truncated one takes the dividend's sign and needs
  correcting at every use site. `quo`/`rem` stay free for the truncating pair.
- **Division by zero splits along a line the language already had.** Integers
  trap, having no infinity; floats answer one, since float multiplication already
  overflows to infinity where integer multiplication traps.
- `INT64_MIN div #-1` is guarded separately — the one division that overflows,
  and undefined behaviour in C rather than merely wrong, raising SIGFPE on x86.

Also recorded two gaps found while checking the above: float literals have no
exponent notation (`1e308` does not scan), and `print` emits float text the
scanner cannot read back (`1e+256`, `inf`).

### Strings — `e454192`, 2026-08-19

```
s := "hello".
s:concat(", world"):print.        ; "hello, world"
"hi":equals("hi"):print.          ; true
["ada", "grace"]:collect({ n | n:concat("!") }).
```

`SolString` and the `string` class: `print`, `size`, `equals`, `concat`, `at`.

- **Immutable, and therefore a value rather than a reference.** `equals` compares
  characters, where an array compares identity. That completes the split the
  language already had: numbers and strings are values, objects and blocks and
  arrays are references.
- One-based `at`, answering a one-character string since there is no character
  type. Strict `concat`: joining a string to a number is an error, not a
  conversion.
- Printed as it would be written — `"hello"`, not `hello` — the way `#45` prints
  as `#45`.
- **No `.sob` change was needed after all.** A literal's bytes ride in the chunk's
  interned text table beside selectors and global names, and `OP_STRING` builds
  the string at run time — which is also how the compiler emits one without
  having a VM to allocate in. Only the opcode set changed, so the format went to
  version 5.
- A string holds bytes, not values, so it has no outgoing edges for the collector
  — the difference from an array that made arrays the better first heap type.

Left open, each independent: escape sequences, interning, ordering, and
conversions to and from numbers.

### collect and select — `b9b9702`, 2026-08-19

```
[#1, #2, #3, #4, #5]:collect({ x | x:mul(x) }).      ; [#1, #4, #9, #16, #25]
[#1, #2, #3, #4, #5]:select({ x | x:greaterThan(#2) }).  ; [#3, #4, #5]
```

Both answer a new array and leave the receiver alone, so they chain into a
pipeline that reads left to right.

These are the first primitives to need a **temporary root**, and it turned out to
be load-bearing rather than cautious. They allocate a result array and then call
a block per element, and a block can allocate; between calls the result is
reachable only from a C local. Removing the root and running under
`SOLUM_GC_STRESS=1` with ASan turns the loop into a heap-use-after-free in
`sol_array_add` — the result is swept while it is still being filled.

`select` appends each element *before* testing it and winds the count back on
rejection, so the element is never held only in a C local across a block call.

`select` is strict about its block answering a boolean, as `whileTrue` is.

### Array literals — `63749ee`, 2026-08-19

```
xs := [#1, #2, #3].
n := [[#1, #2], [#3]].
e := [].
```

`[...]` is sugar for `array:of(...)` in the strict sense: the two forms compile
to byte-identical `.sob` files, and a test asserts it rather than trusting the
claim. Two lexer tokens and one compiler branch — no new opcode, no verifier
change, nothing the VM has to learn.

Because the desugaring is real rather than a lookalike, the `array` it sends to
is the ordinary global; rebinding that name moves both spellings together. They
cannot drift apart, which is the point.

A literal is a construction, not a pooled constant, so every evaluation answers a
fresh array — two calls to a method containing one do not share it. Capped at 255
elements by `OP_SEND`'s one-byte argument count.

### The project is named Solveig — `7db2b27`, 2026-08-19

The repository had no name distinct from its parts: "Solum" was serving as the
project, the virtual machine, and the language at once.

**Solveig** now names the project. The language stays **Solum**, and the programs
stay **Solas**, **SolVM**, and **Solis**. Old Norse *Sólveig*, from *sól* "sun"
and *veig*, usually read as "strength" -- the Norse cousin of the *sol-* root the
rest of the family already shares. The README carries the longer note, including
why *SolVM* and *solum* are the same word: classical Latin wrote V where we now
write U, so Roman inscriptions give SOLVM.

Documentation only. No code, no file names, and no behaviour changed.

### Arrays — `1d8c573`, 2026-08-19

Nothing in the language could hold more than one value, so no program could
accumulate a result.

```
a := array:of(#10, #20, #30).
a:at(#1):print.              ; #10 -- indices are one-based

b := array:new.
b:add(#1):add(#2):add(#3).   ; add answers the array, so it chains
b:do({ e | sum := sum:add(e) }).
```

- A `SolArray` heap type joins the collector, and **every element is a tracing
  edge** — the reason arrays were built before strings, whose bytes are not.
- One-based indices: an index is an ordinal, not an offset. `at(#0)` is out of
  bounds and therefore caught rather than silently off by one.
- Strictness carried through: an index must be an integer, and out of range is an
  error rather than nil.
- Arrays are references, like objects. `equals` is identity; comparing contents
  is a different question and will get its own name.
- `do` bounds the count once and re-reads the backing store each pass, since the
  block may grow the array and move the store underneath it.
- Printing is depth-limited, because `a:add(a)` is legal.
- No `.sob` change: an array is built at run time, never pooled as a constant.

Still to come: the `[...]` literal sugar, and `collect`/`select`.

### Roadmap audit — `470c6d3`, 2026-08-18

No code change. Audited the roadmap against the source and against everything
raised in review, and added the two real gaps it was missing:

- **Recursion is limited to about 30 levels** (3.5). `SOL_FRAMES_MAX` is 64 and
  each recursion level costs two frames in the idiomatic form -- the method's
  block, and the `ifElse` branch block carrying the recursive call. Measured: 30
  succeeds, 31 reports "call depth exceeded". Low enough for ordinary code to
  hit.
- **A caller-owned chunk must outlive blocks defined in it** (3.6). Freeing one
  while a reachable block points into it leaves that block undefined to call. The
  collector is safe -- a block caches its owning cell, so tracing never touches a
  freed chunk -- but nothing detects the call.

Also corrected a comment in the compiler claiming there were no blocks yet.

### The collector owns compiled code — `104a5e0`, 2026-08-18

Solis no longer retains every line's chunk. Over 60,000 REPL lines, peak resident
set went from **25.5 MB growing linearly to 1.9 MB flat**.

Ownership is dual rather than wholesale, because Solas has no VM to own a chunk
on its behalf. A chunk from `sol_chunk_init` is caller-owned and freed by hand;
one from `sol_code_new` belongs to a `SolCode` cell the collector sweeps.
`sol_chunk_add_method` propagates ownership as each subtree is added, so a caller
cannot forget to.

- Added `sol_gc_push_temp` / `sol_gc_pop_temp` for cells held only in a C local
  across an allocation. Solis uses them to protect a fresh code cell while it
  compiles into it.
- A chunk's constants are traced, since they will hold heap values as soon as
  strings exist.
- A block caches its owning cell rather than reading it back through
  `block->code->chunk`. A caller-owned chunk can be freed while blocks pointing
  into it are still on the heap — calling such a block was always wrong, but the
  tracer must not fault merely for walking past one. Stress mode under ASan found
  this as a use-after-free in `mark_code`.

### A garbage collector — `29d011a`, 2026-08-18

Mark–sweep, non-moving, stop-the-world. Objects and blocks are reclaimed while a
program runs; before this nothing was freed until the VM exited.

The motivating case — a block literal allocated once per loop iteration — over
two million allocations:

| | Peak RSS |
| --- | --- |
| before | 98 MB, growing linearly |
| after | 1.5 MB, flat |

- Both heap types now begin with a shared `SolGCHeader`, so one list threads the
  whole heap and one sweep loop walks it. A new heap type joins by embedding the
  header rather than adding another list.
- Marking uses an explicit worklist, not recursion, so a graph deeper than the C
  stack traces without overflowing it — a 200,000-link proto chain is a test.
- Collection happens *before* an allocation, so the new cell cannot be swept.
  `sol_vm_init` nulls the roots before its first allocation for the same reason.
- `SOLUM_GC_STRESS=1` collects on every allocation. The whole suite passes under
  it with ASan and UBSan.

Code is still owned by the chunk that compiled it, so Solis continues to retain
every line's chunk; that is roadmap 1.1b.

### `:=` became one operator — `7029d27`, 2026-08-18

**Breaking: method definitions changed shape, and `.sob` went to version 4.**

`:=` used to mean two different things depending on what stood to its left. In
`a := #45:add(#32)` it evaluated the right-hand side; in
`integer:fun() := #45:add(#32)` it did not — that was a definition form the
compiler pattern-matched, whose right-hand side was compiled to run later,
freshly, on every call.

Now there is one rule: `obj:name := value` evaluates and binds, exactly as
`a := value` does.

```
integer:double := { self:mul(#2) }.
integer:poly := { a, b | self:mul(a):add(b) }.
integer:quadruple := { | d | d := self:double. d:double }.
```

- A slot holds a value. A slot holding a **block** is a method: sending its name
  runs the block with the receiver as `self`. A slot holding anything else
  answers that value, so methods and data slots are no longer different kinds of
  thing.
- Because `:=` evaluates, a method can be **computed**:
  `integer:double := maker:value()`.
- Blocks gained parameters: `{ a, b | ... }`. A leading `|` still means
  temporaries.
- Capture now **chains**. With no separate notion of a method, every frame is a
  block's, so `OP_OUTER` carries a depth and the runtime walks the lexical chain,
  checking liveness at each hop.
- `self` is no longer resolved lexically at compile time — which block ends up
  invoked as a method is not knowable there. It compiles to slot 0 of the frame
  being entered; the VM captures the receiver into a block at creation, and a
  send to a slot holding it overrides slot 0.
- The method-definition special form left the compiler, and about 100 lines with
  it.

### Method temporaries must be declared — `343d776`, 2026-08-18

**Breaking: bodies that relied on implicit locals need `| ... |`.**

Fixes a real defect. Assignment inside a method used to declare a local for any
new name, so a global could not be updated from a method at all, and because the
local was declared before its own initializer was compiled,
`counter := counter:add(#1)` read the fresh nil local and failed with
"nil does not understand 'add'".

- Only parameters and names declared with `| a, b |` are locals. Everything else
  is a global, read or written.
- Only the script's top level may **create** a global, so an undeclared name
  inside a method or block must already exist — a typo is reported instead of
  quietly becoming a variable that looks local.
- Declarations may open any group or block body. A duplicate name in one frame is
  a compile error.

### Documented what verification does not promise — `be7fdca`, 2026-08-18

Verification guarantees a loaded chunk is safe to execute; it does not guarantee
the program terminates, and it should not. Established by fuzzing rather than
assumed: every hang seen while corrupting a `.sob` mapped to a constant payload
or code byte, never to a name, count, or length the loader parses, and a control
run over a program with no loop produced zero hangs.

### Blocks, booleans, and message-based control flow — `284d015`, 2026-08-18

**`.sob` went to version 3.**

```
#5:lessThan(#10):ifElse({ #100:print }, { #200:print }).
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

- `{ ... }` makes a block: code as a value, deferred rather than run.
- Control flow is ordinary message sending. `ifTrue`, `ifElse`, and `whileTrue`
  are plain primitives receiving an unevaluated block, so **the language has no
  control-flow syntax** and a user can add control structures the same way.
- The interpreter became re-entrant so a primitive can invoke a block.
- Added a boolean type with `true`/`false` and `not`, and `equals`, `lessThan`,
  `greaterThan` on numbers. Comparisons are as strict as arithmetic; `equals` is
  the exception, answering false across types rather than erroring.
- Capture is lexical, with two cheap measures instead of heap promotion: a block
  that does not touch its home frame may escape freely, and one that does records
  a frame id so calling it after that frame returned is reported.
- With conditionals, recursion can terminate — the language became
  Turing-complete.

### Methods, call frames, and locals — `dd31244`, 2026-08-18

**`.sob` went to version 2.**

Methods could be written in Solum source rather than only as C primitives, and
the VM grew call frames. A frame's slots point into the value stack at the
receiver, so nothing is copied to make a call. Solis began retaining every line's
chunk, because a class holds only a pointer to a method the chunk owns.

### The `.sob` bytecode file format — `2b2bea2`, 2026-08-18

Solas writes bytecode to a file and Solum loads and runs it. Little-endian and
host-independent; floats survive bit-identical; line numbers are run-length
encoded.

A `.sob` file is treated as untrusted input: the loader bounds-checks every read
and rejects a count that could not fit in the bytes remaining, and what survives
is verified before it can execute — every instruction fits, every operand indexes
something real, and the final instruction stops the machine so the dispatch loop
cannot run off the buffer.

### Initial commit — `52f2f01`, 2026-08-18

Solas (compiler), Solum (VM), and Solis (REPL) as three components sharing one
static library, with `solum/include/solum/bytecode.h` as the single contract
between compiler and VM.

Design decisions taken here: a name is a binding rather than an object and values
are immutable; `#` is a type tag, so `#45` is an integer and a bare `45` is a
float; arithmetic is strict and integer overflow traps rather than wrapping.
