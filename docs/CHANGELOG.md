# Changelog

Notable changes to Solveig, newest first. Nothing is released yet, so everything
below is under `0.0.1` and the syntax is still moving.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md).

## Unreleased — 0.0.1

### Inlined loops — `pending`, 2026-08-19

**`.sob` goes to version 8.**

`whileTrue` written literally now compiles to jumps too. There is no block and
no frame; the condition is re-run in place, and a backward jump closes the loop:

```
0005 GLOBAL      0 'i'
0007 CONST       1 '#5'
0009 SEND        1 'lessThan' (1 args)
0012 EXITIFF    13 -> 28
0015 GLOBAL      0 'i'
0017 CONST       2 '#1'
0019 SEND        2 'add' (1 args)
0022 SETGLOB     0 'i'
0024 POP
0025 LOOP       23 -> 5
0028 NIL
```

| | before 4.1 | inlined conditionals | and now loops |
| --- | --- | --- | --- |
| Recursion, plain | 30 | **62** | 62 |
| Recursion through a loop body | 20 | 30 | **62** |
| A tight 2,000,000-pass loop | 0.53s | 0.52s | **0.44s** |
| The same loop with a conditional in it | 1.44s | 1.13s | **1.06s** |

All three builds were timed together on one machine, so the columns compare;
the 1.60s in the entry below was measured on another day.

The depth is the result worth having. A level of that second row used to cost
three frames — the method, the `ifTrue` branch, and the `whileTrue` body — and
now costs one, so recursion that happens to run inside a loop reaches exactly as
far as recursion that does not. The seconds are worth less than they look: 15%
off a loop that does nothing but count.

**`whileTrue` is the awkward one to inline, because its condition is the
receiver.** By the time the selector has been read, an ordinary compile has
already emitted an OP_BLOCK for it. So the compiler now reads ahead over the
whole `{ ... }:whileTrue({ ... })` before compiling any of it. The parser stays
single-pass in the sense that matters: it never revisits a token it has already
emitted for.

The same two restrictions as the conditionals, and now on the receiver as well —
both blocks must be written on the spot with no parameters and no temporaries.
`whileTrue` calls each with no arguments, so a parameter is an arity error that
inlining would quietly fix, and a temporary belongs to a frame that inlining
would take away. Anything else is an ordinary send. `examples/blocks.sol` runs
the same loop both ways and prints both answers.

**Two opcodes, not one.** `OP_LOOP` jumps backward, and is deliberately separate
from `OP_JUMP` so that forward remains the default and the one instruction that
can move the ip towards zero is easy to find. `OP_EXIT_IF_FALSE` tests the
condition, and is separate from `OP_JUMP_IF_FALSE` because the two complain
differently: for `ifTrue` the boolean is the receiver, so a non-boolean does not
understand the message; for `whileTrue` it is what a block answered, which is a
different sentence.

```
{ #1 }:whileTrue({ #2 }).
solvm: whileTrue expects the condition block to answer a boolean, got integer
```

Both sentences now come from one function, so the inlined form and the send
cannot drift apart — the failure 5.3 records, avoided in advance this time. A
test captures stderr from both and compares them.

**What a backward jump costs the verifier**, which was the open question: a
verified chunk can now run forever. It is not a new capability. `{ true
}:whileTrue({})` is a legal program, and before this a corrupted file could
already spin through a loop built from real sends — the earlier fuzz runs
recorded exactly that, as semantic timeouts rather than memory faults. So the
verifier does not try to prevent it. It checks that every branch target, forward
or backward, lands on the start of an instruction inside the chunk, and stops
there. There are tests for a backward target one byte into an instruction, for
one before the start of the chunk, and one asserting that a loop jumping to
itself is *accepted* — a spin is a bad program, not a broken VM.

Fuzzed: 3205 single-byte corruptions of a loop-bearing `.sob`, run under
ASan and UBSan. Two sanitizer reports, neither from the jumps and both
reproducible from ordinary source — 3.7 and 3.8 in the roadmap. Thirty-four
runs timed out, which is the spin, and is the expected answer rather than a
fault. The same sweep against the previous commit, 4276 variants, found the
argument count fixed below and nothing else.

Instruction lengths are down to one table, `sol_op_length`, read by the emitter,
the verifier, the disassembler, and the tests. There had been four copies, and
two of them disagreeing is precisely how a jump comes to land mid-instruction.

**Also fixed here, because the fuzzing found it: a send with a corrupted
argument count read below the frame.** `OP_SEND` carries `argc` in a byte, and
nothing checked that many arguments were on the stack — a `sub` claiming 227 of
them on a stack one deep read the receiver from 3.6 KB below. Whether a count is
honest depends on the stack height at that instruction, which the verifier does
not compute (3.9), so the send now refuses to reach below its own frame. Not a
new fault: the same fuzzing against the previous commit reproduces it, and the
regression test is a stack-buffer-overflow without the check.

**Found here and deliberately not fixed here: `array:print` crashes the VM.**

```
array:print.        ; segmentation fault
```

Three words of ordinary source, and the REPL goes the same way. Rendering an
object asks it for `asString`; on the class objects `array` and `block` that
finds the one they define for their instances, which renders the same value
again, and the depth `render` carries restarts at zero each time round. Bisected
to `f55e105`, which is where rendering began asking — it has nothing to do with
jumps. Written up as 3.7 with the fix it wants, which is its own commit.

The second report is the same shape by a different route, and also from source:

```
array:add(#1).      ; abort
```

`array` is an object whose slots are the messages an array understands, so
sending one to `array` itself finds it, and `prim_array_add` then reads the
class object as if it were an array. Written up as 3.8. Both wait on a decision
rather than on work — 2.5 is the design question under them — so neither is
fixed here.

### Inlined conditionals — `54e2ae1`, 2026-08-19

**`.sob` goes to version 7.**

`ifTrue`, `ifFalse`, and `ifElse` written literally now compile to jumps — no
block allocated, no frame entered:

```
0000 CONST       0 '#1'
0002 CONST       1 '#2'
0004 SEND        0 'lessThan' (1 args)
0007 JUMP_IF_FALSE    5 -> 16 (ifElse)
0011 STRING      2 'yes'
0013 JUMP        2 -> 18
0016 STRING      3 'no'
```

| | before | after |
| --- | --- | --- |
| Recursion depth | 30 | **62** |
| 2,000,000 conditionals | 1.60s | **1.12s** |

They are still ordinary messages on a boolean, still reachable through `perform`
or with a block held in a variable. Inlining applies only when every argument is
a block written on the spot with no parameters and no temporaries — a block with
parameters is an arity error when `ifElse` calls it with none, and inlining
would quietly make it work; a block's temporaries belong to its own frame, and
inlining would declare them in the enclosing one where they could collide.
Everything else falls back to a real send, and there are tests that the two
forms agree on every combination.

**The verifier changed, as 4.1 predicted it would have to.** Execution is no
longer linear, so it records where each instruction begins and checks every
branch target lands on one, in range. A crafted target one byte into a send
would otherwise have its operands executed as opcodes; there is a test for
exactly that. Offsets are unsigned and so forward-only, which is also why
verified bytecode cannot loop through a jump — 1798 corrupted variants of a
jump-bearing file gave no sanitizer report and no timeout.

The remaining cost in that loop is `whileTrue`, still a send with a block call
per iteration. It needs a backward jump, and is now first on the list.

### Sorting — `113745f`, 2026-08-19

```
[#3, #1, #2]:sorted:print.                            ; [#1, #2, #3]
[#1, #3, #2]:sorted({ a, b | b:lessThan(a) }):print.  ; [#3, #2, #1]
```

`sorted` answers a **new array**, like `collect` and `select`; nothing sorts in
place. With no block the order comes from *sending* `lessThan`, so a type that
defines one sorts itself, the way `fill` honours an overridden `asString`
instead of going around it. Mixed types are an error rather than an arbitrary
order — `lessThan` has no coercion to fall back on.

**Stable**, and tested as such: sorting twice orders by two keys, minor first.

Merge sort, chosen for two reasons past the O(n log n). It is stable. And it
cannot be walked off the end by a comparison that contradicts itself — a program
is free to write `{ a, b | true }`, and the indices are bounded by the halves
rather than by what the comparison claims. A quicksort partition trusting the
comparison would not be. There is a test that a self-contradicting comparison
loses no element.

The comparison calls back into the VM, so it can allocate and collect mid-merge.
Removing the root on the result array gives `heap-use-after-free` in
`merge_sort` under stress. What makes it safe is that a value is *copied* into
the scratch array and never moved, so until the copy back it is still in the
rooted result — an invariant of how merging works, now written down where the
next person will need it.

Checked against a reference sort on 2000 runtime-generated values, and under
ASan with GC stress on every comparison.

No `.sob` change: `sorted` is a primitive, so the format stays at version 6.

### Reflection — `a7310a7`, 2026-08-19

```
point:slots:print.               ; ['x, 'y, 'show]
p:isKindOf(point):print.         ; true
p:respondsTo('show):print.       ; true
p:perform('show):display.        ; (3, 4)
```

Five messages, on every type: `slots`, `slotAt`, `respondsTo`, `isKindOf`,
`perform`. Names are given as symbols, which is what symbols were wanted for.

`slots` answers own slots in **definition order** — the slot list is kept newest
first, so it is filled backwards. Inherited names are not yours; `parent:slots`
asks about those. The rest search the chain as a send does. A value answers for
the class it dispatches to, so `#45:isKindOf(integer)` holds, and since the
built-in classes are objects whose slots hold primitives, `integer:slots` lists
what an integer understands.

Installed in a loop over every class rather than nine times over. That is not
brevity: a message that answers what an object understands is wrong the moment
one class quietly lacks it.

**A fetched method is unbound**, and this is documented rather than papered
over. `slotAt` answers the plain block; `self` comes from a send, so `m:value`
runs with `self` nil. Fetching is for passing a method around; to call one, send
it. Binding a receiver to a fetched block is now item 3 in the suggested order.

Building the `slots` array interns a symbol per slot, and interning allocates —
so the half-built array is a temp root. Removing it gives
`heap-use-after-free at builtins.c:1562` under stress, which is what the new
test in `tests/test_reflect.c` guards.

No `.sob` change: these are all primitives, so the format stays at version 6.

### Symbols — `5a15fc9`, 2026-08-19

**`.sob` goes to version 6.**

```
a := 'foo.
"foo":asSymbol:equals('foo)      ; true  -- the very same symbol

state := 'running.
state:equals('running):ifElse({ "go" }, { "stop" }):display.
```

An interned name. Two symbols spelling the same thing are the *same* symbol, so
equality is a pointer comparison rather than a walk over characters — which is
the whole reason to have them apart from strings, a name being compared far more
often than it is read. A symbol never equals a string; `asString` gives its name.

**The intern table is weak, and that mattered more than memory.** Measured by
disabling the pruning:

| | 20,000 interned names |
| --- | --- |
| strong table | did not finish in 60 seconds |
| weak table | instant, 1.7 MB |

With a strong table every collection has to mark every symbol ever interned, so
the work grows with the total rather than the live set. Pruning runs between
marking and sweeping, so the table never names a cell the sweep is about to free
— and there is a test that a kept symbol survives a collection *and* that
re-interning afterwards finds the same one back.

This also gives 4.3 its mechanism: interned names are exactly what selector
dispatch wants instead of a `strcmp` per send.

### `asUppercase` and `asLowercase` — `91d413c`, 2026-08-19

```
#255:asBase(#16):asUppercase     ; "FF"    -- uppercase hex at last
"Hello, World!":asLowercase      ; "hello, world!"
```

ASCII letters only, and **by explicit range rather than `toupper`**, which
follows the C locale: under a Turkish locale `toupper('i')` is a dotted capital
I, so the same program would answer differently on two machines. Predictability
is worth more than the locales this cannot serve anyway.

Every other byte passes through untouched, so `"café":asUppercase` is `"CAFé"`
rather than mangled.

A string with nothing to change answers itself. Strings are immutable, so nothing
can tell the difference, and it saves an allocation.

This closes the gap integer bases left — `asBase` writes lowercase digits, and a
case message is a more general answer than an uppercase variant of it would have
been.

Also records what the language thinks text is (roadmap 2.13): a string is bytes,
`size` counts bytes, `at` answers a byte, and `"café":size` is 5. Real Unicode is
a different piece of work, not a larger version of this one.

### Integer bases — `f4b909d`, 2026-08-19

```
#255:asBase(#16)                    ; "ff"
#255:asBase(#2)                     ; "11111111"
#255:asBase(#16):asString("08")     ; "000000ff"
"ff":asInteger(#16)                 ; #255
```

**A message, not a letter in the format spec.** The roadmap had sketched
`#255:asString("x")`, which is exactly what the spec was designed without — a
letter that looks like printf's conversion character and invites a reader to try
`f` and `d`. A number covers every base from 2 to 36 where a letter covers one,
and padding still comes from the spec by chaining.

- The most negative integer converts like any other. Its magnitude is taken
  unsigned, so there is no negation to overflow.
- `asInteger(#n)` reads it back, and every base round-trips — there is a test
  walking 2 through 36 over a set of values including `INT64_MIN + 1`.
- Strict: no `0x` prefix, no leading whitespace, and a digit outside the base is
  an error rather than a truncated parse. `strtoll` would have accepted the first
  two.
- Digits above nine are lowercase. Uppercase hex wants `asUppercase` on strings,
  which is a more general thing to have than a second base message, and is now
  the noted gap.

### Digit grouping in format specs — `95074c9`, 2026-08-19

```
#1234567:asString(",")       ; "1,234,567"
1234.5:asString(",10.2")     ; "  1,234.50"
#-1234567:asString(",")      ; "-1,234,567"
```

`,` groups whole-number digits in threes, and **only** those — a sign, a
fraction, and an exponent all pass through untouched, so `1234567.891` becomes
`1,234,567.89` and `1e20` stays `1e+20`.

- **Fixed at `,`.** A separator that varies by locale is a much larger door to
  open than a report column is worth.
- **Cannot be combined with zero fill.** The leading zeros would not themselves
  be grouped — Python renders that as `001,234.50` — which reads as a mistake, so
  it is refused rather than produced.
- The flags have one order, so there is one way to write a given spec.
- Grouping belongs to numbers; asking a string, boolean, nil, array, or object
  for it is an error.

Two extensions were considered and deliberately **not** built, both recorded in
the roadmap: forcing exponent form (`"10.2e"`), which the renderer already does
on magnitude, and integer bases (`"x"`). Both reintroduce something that looks
like the conversion letter the spec was designed without, and invite a reader to
try letters that do not exist.

### Format specs — `3524c70`, 2026-08-19

`asString` takes an optional spec:

```
[align] ['0'] [width] ['.' decimals]

45.8:asString("6.2")     ; " 45.80"
45.8:asString("08.2")    ; "00045.80"
#-45:asString("06")      ; "-00045"
"ab":asString(">6")      ; "    ab"

row := { n, v | "{}{}":fill([n:asString("<8"), v:asString("8.2")]) }.
row:value("apples", 3.5).     ; apples      3.50
row:value("pears", 12.25).    ; pears      12.25
```

Deliberately smaller than printf:

- **No conversion letter.** The receiver knows its own type, so there is nothing
  that could contradict it.
- **No sign mode.** A leading space for a positive number falls out of the width,
  numbers aligning right — which removed a whole mode from the design.
- Numbers align right and text aligns left; `<` `>` `^` override.
- Decimals belong to floats. Asking an integer, string, boolean, or array for
  them is an error rather than a no-op.
- Zero fill must align right — padding a number on the left with zeros would
  change what it says — and goes after any sign.
- A value wider than the width is never cut. Losing digits would be worse than a
  ragged column.

Put on `asString` rather than a separate `format` message, so one message answers
"the text of this value" and there is no second one to drift from it. **No
argument means what it always meant**, so `display`, `fill`, and array rendering
are untouched.

### `format` is now `fill` — `4a70ef0`, 2026-08-19

**Breaking: `"...":format([...])` is now `"...":fill([...])`.**

```
"you have {} apples":fill([#3]):display.    ; you have 3 apples
```

The behaviour is unchanged. The name was wrong: the placeholders are blanks and
the message fills them, whereas `format` belongs to formatting a *single value*
against a spec — where the value is the receiver, not the template.

`"...":fill(...)` is a template acting on values; `45.8:asString("5.2")` is a
value being formatted. Two jobs, and `format` was the wrong word for the first.

Not `replace`, which `string:replace(old, new)` will want.

Formatting a single value is recorded as an open decision (roadmap 2.12). The
shape is settled — a spec argument to the existing `asString`, so one message
answers "the text of this value" and there is no second one to drift from it —
but the spec language itself is not.

### The virtual machine is `bin/solvm` — `efbdf2c`, 2026-08-19

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
