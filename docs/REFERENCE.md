# Solum — language reference

Solum is the language; **Solas** compiles it, **SolVM** runs the bytecode, and
**Solis** is the REPL. This document describes the language as it is, message by
message, for looking things up.

If you are meeting the language for the first time, read [GUIDE.md](GUIDE.md)
instead — the same ground in an order that builds, with a runnable example behind
each concept. For why the language is this way see [design.md](design.md); for
what is still missing see [ROADMAP.md](ROADMAP.md).

Everything is an object and all work happens by sending messages.

```
a := #45.
a:print.
```

## Contents

- [Running a program](#running-a-program)
- [Splitting a program across files](#splitting-a-program-across-files)
- [The program and its process](#the-program-and-its-process)
- [Lexical structure](#lexical-structure)
- [Values](#values)
- [Names and binding](#names-and-binding)
- [Messages](#messages)
- [Blocks](#blocks)
- [Control flow](#control-flow)
- [Objects](#objects)
- [Message reference](#message-reference)
- [Errors](#errors)
- [Limits](#limits)

---

## Running a program

```sh
./bin/solas program.sol             # compiles to program.sob
./bin/solvm program.sob             # runs it
./bin/solvm program.sob a b c       # ...with arguments, which system:arguments answers
./bin/solis                         # a prompt; input may span lines
```

Everything after the `.sob` belongs to the program and solvm does not look at
it, so its own flags have to come first.

The program is `solvm`; its sources live under `solum/`. The two are the same
word -- `SOLVM` is how *solum* was written before the alphabet split V into two
letters -- so the directory keeps the modern spelling and the program the older
one.

`solas --dump` also prints the disassembly. `solvm --dump` prints it for a
compiled file before running.

A `.sob` file is verified before it runs: every instruction must fit, every
operand must index something that exists, every jump must land on the start of
an instruction inside the chunk, and the last instruction must stop the machine.
A corrupt file is refused rather than executed.

The file also carries a format version, and a build reads only its own: a `.sob`
left over from an earlier one is refused with `unsupported bytecode version`
rather than misread. Recompile the `.sol`.

---

## Splitting a program across files

```
@include "library.sol".
```

compiles that file into this one at that point, as though its text had been
written there. Globals are one flat namespace and stay one: two files binding
the same name collide exactly as two `:=` in one file do, and the later wins.

**`@` marks a directive**, and a directive is not a message. What follows the
`@` happens while compiling; by the time the program runs there is nothing left
of it to run. That is the whole of what the sigil is for, and it is why nothing
in the `@` space is written as a send.

The file name has to be a literal string, because the file is found while
compiling and a name holding one has no value yet.

**It stands alone.** A file compiled in at that point has nowhere to go inside
an expression, so anywhere other than on its own as a statement a directive is a
compile error:

```
[prog.sol:1:7] solas: a directive must stand alone as a statement at '@include'
  x := (@include "library.sol").
        ^^^^^^^^
```

`@include` is the only directive there is. An unknown one is refused rather than
passed through, since `@` is the compiler's own space and a name in it that the
compiler does not know is a mistake:

```
[prog.sol:1:1] solas: unknown directive at '@compile'
  @compile "library.sol".
  ^^^^^^^^
```

A directive is one token, `@` and all, so the bare word stays free: `include` is
an ordinary name that any object may use for a slot.

**The file is found beside the file including it**, not beside the directory you
happened to be standing in, so a program can be moved without its includes
breaking. An absolute path is taken as it stands. Source that is not a file at
all — the prompt, or a string handed to the compiler — has nothing to be
relative to, and the working directory is used.

**Failing that, the search path.** A name not found beside the includer is
looked for in each directory of the search path, in order, and the first that
has it wins:

- `-I dir` arguments to `solas` or `solis`, in the order given;
- then the entries of `SOLUM_PATH`, colon-separated;
- then the library shipped beside the binary — `bin/solas` looks in `bin/../lib`.

That is C's rule for a quoted include, and for C's reason: your own files are
found without saying where they are, and a name you do not have locally comes
from the library. It carries C's cost too — a local file **shadows** a library
one of the same name — which is usually what you want and occasionally a trap.
A file that includes a library file of its own name finds *itself* beside it
first, and, a file being compiled once, that include quietly does nothing.

An absolute name searches nothing. A file found nowhere says so:

```
[prog.sol:1:10] solas: cannot read the included file 'prog/missing.sol', and it is not on the search path either
```

### The library

`lib/control.sol` ships with the language and is on the search path, so a
program asks for it by name:

```
@include "control.sol".

#3:repeat({ "tick":display }).
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
#1:toByDo(#10, #3, { n | n:display }).       ; 1 4 7 10
#4:timesCollect({ n | n:mul(n) }).           ; [#1, #4, #9, #16]
```

| Message | Answers |
| --- | --- |
| `#n:timesCollect(block)` | an array of `n` answers, the block given the pass number |

**None of it is language.** These are methods bound on `integer` and `block` by
an ordinary Solum file, because control flow is message sending and a loop is
therefore something a library can add.

**Four things were here once and are not any more.** `doUntil`, `repeat`, `toDo`
and `toByDo` all started as Solum in this file, all four were measured, and all
four turned out to be worth building into the VM — see
[integer](#integer) and [block](#block). Defining any of them here again would be
a trap rather than an override: a slot bound on `integer` shadows the primitive,
so the slow version would quietly win, and `doUntil` is spliced in by the
compiler anyway.

That leaves one function in the library, which is a fair record of what
measuring does. The machinery around it — the search path, `@include` finding a
name it was not told the location of — is unchanged and is the part that
matters.

A step of `#0` would never finish, so `toByDo` says so rather than hanging.

Written in Solum, they cost a block call per iteration — about 1.30× a literal
`whileTrue`, which compiles to jumps. See
[ROADMAP 6.6](ROADMAP.md#66-the-loop-constructs-are-library-code-and-pay-for-it).

**A file is compiled once** per compilation, however many ways it is reached,
keyed by where it turns out to be on disk so that two spellings of one file are
one file. C compiles it every time and leaves each file to guard itself, which
needs conditional compilation that Solum has not got; and a second copy could
only rebind names already bound and repeat whatever the file did on the way. So
two files may each include what they need without arranging between themselves
who includes what — and a cycle ends instead of recurring.

**Errors name the file**, and the chain that reached it:

```
[lib/broken.sol:2:6] solas: expected an expression at ':'
  y := :.
       ^
  ... included from lib/middle.sol, line 1
  ... included from prog.sol, line 3
```

Includes may nest 64 deep.

Two things this is not. There is no module system: an included file gets no
namespace of its own. If you want one, bind an object and hang the rest off it,
which claims one global instead of a dozen —
[examples/library.sol](../examples/library.sol) does that. And a `.sob` file is
one chunk with no record of which file a line came from, so a run-time stack
trace gives a line number without saying which file counted it.

---

## The program and its process

`system` is a global holding one object. It is not a class and has no
instances — there is one process, and this is where what belongs to it lives
rather than to any value. Its messages are in
[the reference below](#system).

```
system:arguments:do({ a | a:display }).
system:exit(#0).
```

### Stopping

`system:exit(status)` stops the program and hands `status` back to whatever ran
it. It **unwinds** rather than leaving from under the machine: every frame is
discarded the way an error discards them, and control returns through `main`, so
everything already written is flushed on the way out. Nothing after the `exit`
runs, including the rest of a loop it was called inside:

```
[#1, #2, #3]:do({ n | n:print. n:equals(#2):ifTrue({ system:exit(#3) }) }).
```
```
#1
#2
```

A status is an integer from **#0 to #255**, and anything else is an error rather
than a value quietly adjusted to fit — POSIX keeps only the low eight bits, so
`system:exit(#256)` would otherwise leave with 0 and look like success.

At the prompt it does the same thing: Solis runs the same machine, so
`system:exit(#4)` leaves Solis with status 4.

### Arguments

`system:arguments` answers an array of strings: everything on the command line
after the `.sob` file, in order, and neither solvm's name nor the file's is among
them. With none given it is the **empty array** rather than nil, so it can be
walked without first asking whether it is there.

It is a data slot rather than a method, because it is data — the same array every
time, not a fresh one:

```
system:arguments:equals(system:arguments):print.     ; true
```

Being an ordinary array, a program can add to it or sort it. That changes the
program's copy and nothing else.

### Reading input

`system:readLine` answers one line from standard input **without its
terminator**, or **nil** when there is no more.

```
line := system:readLine.
{ line:notNil }:whileTrue({
    line:display.
    line := system:readLine
}).
```

Nil is the end and `""` is an empty line, so the two are never confused. A last
line carrying no newline of its own still counts as a line, and `\r\n` is one
terminator, so a file written on another system reads the same as one written
here.

Nil rather than an error is the one place absence is not treated as a mistake:
running out of input is how a loop that reads to the end finishes, not something
that went wrong.

At the prompt it reads the next line you type, which Solis then does not see —
the program and the prompt are reading the same input.

Waiting for a single keypress is a different job. It needs raw terminal mode,
which is the first thing in the runtime that would differ by platform, and it is
not here.

### Files

Whole files, as strings.

```
system:writeFile("notes.txt", "apples 3\npears 12\n").
system:readFile("notes.txt"):size:print.         ; #18
```

`readFile` answers the whole file as one string. `writeFile` replaces what is
there, creates the file if it is not, and answers nil — there is nothing useful
to chain from a write.

**A missing file is an error, not nil**, which is the same answer an
out-of-range index gets and for the same reason: a program asking for a file it
has not got is wrong about something. `readLine` answering nil at the end of
input is not the precedent, since running out of input is how a loop *finishes*.

`system:fileExists(path)` is how to ask first, and it is about a **file**: a
directory answers false, because that is what `readFile` would say about one
too.

A string is bytes, so a file of them survives the round trip — a NUL is a byte
like any other, `size` counts it, and reading a file and writing it back copies
it exactly. `split`, `indexOf` and `copyFrom` work on it too, all three going by
the length rather than stopping at the first NUL. What is still missing is a
*number* for a byte: `at` answers a one-character string, so there is nothing to
do arithmetic on.

These are on `system` rather than on the string naming the file, though
`"notes.txt":readFile` reads well. A string knows nothing about files, and
`system` is already where what belongs to the world outside the program lives.

There was a third reason once: include was spelled `"lib.sol":include` then, and
`"lib.sol":readFile` beside it would have been two identical-looking sends that
were nothing alike. That collision is gone — an include is `@include "lib.sol"`
now and looks like nothing else — but the first two reasons were the load-bearing
ones and they still hold.

### The clock

`system:clock` answers **monotonic seconds as a float**. The epoch is
deliberately unspecified: the only useful thing to do with two readings is
subtract them, and a wall clock can go backwards in between.

```
start := system:clock.
i := #0. { i:lessThan(#100000) }:whileTrue({ i := i:add(#1) }).
system:clock:sub(start):asString("0.4"):display.     ; 0.0147 -- whatever it took
```

`{ ... }:timeToRun` does the same without the bookkeeping, answering the seconds
the block took. The block's own answer is dropped — what was asked for was the
time, and `{ ... }:value` is there when the answer is wanted too.

**The clock has a floor**, and it decides how this message is used. On the
machine this was written on it is a microsecond, by `clock_getres` and by
watching the smallest step between two readings. One send and one add costs
well under a tenth of that, so a single run answers the floor rather than the
block — `0` most times, one whole microsecond when the two readings happen to
fall either side of a tick:

```
{ #1:add(#1) }:timeToRun:print.        ; 0, or 0.000001 -- the floor, either way
```

`timeToRun(#n)` runs the block `n` times and answers the **total**, which is how
anything smaller than a microsecond gets measured:

```
total := { #1:add(#1) }:timeToRun(#200000).
total:div(200000.0):asString(".9"):display.      ; 0.000000088 -- or thereabouts
```

The total rather than the average, because the total is the measurement and the
average is a division you can do — and keeping the count in view is what tells
you whether the floor was cleared. A count below `#1` is an error.

What is measured includes the cost of calling the block, a frame pushed and
popped. That is not overhead to subtract; it is what running the block costs.

---

## Lexical structure

### Comments

`;` begins a comment, which runs to the end of the line.

```
a := #45.        ; this is a comment
```

### Statements

`.` separates statements. It is required between two and optional after the
last, in a script and inside a group or block alike.

```
a := #1. b := #2      ; the last needs no '.'
```

A line beginning with `:` continues the expression above it, so

```
total := #10
:add(#5).
```

is one statement, not two.

### Literals

| Form | Type | Notes |
| --- | --- | --- |
| `#45`, `#-45` | integer | `#` is a type tag, not a marker |
| `45`, `45.5` | float | a bare number is a float |
| `1e3`, `1.5e-3`, `1E+3` | float | exponent optional, sign optional |
| `"hello"` | string | see escapes below |
| `[#1, #2]` | array | sugar for `array:of(#1, #2)` |
| `{ #1 }` | block | code as a value |
| `'foo` | symbol | an interned name; no closing quote |

`#` marks an integer and its absence marks a float, so `#45` and `45` are
different values of different types. There is no exponent on an integer, `#`
meaning exact.

A `.` only continues a number when a digit follows it, so `45.` is the float
`45` followed by a statement separator.

### String escapes

`\"`, `\\`, `\n`, `\t`, `\r`. Any other escape is an error rather than a literal
backslash. There is no `\0`.

```
"she said \"hi\"".
"one\ntwo".
```

A literal newline inside the quotes also works.

### Identifiers

`[A-Za-z_][A-Za-z0-9_]*`. Message selectors are identifiers, which is why `=`
cannot be one: `a:=(b)` would otherwise be both an assignment and a send.

### Reserved names

None are keywords, but these are bound as globals at startup and shadowing them
will surprise you: `integer`, `float`, `string`, `array`, `dictionary`, `symbol`,
`block`, `boolean`, `object`, `error`, `system`, `nil`, `true`, `false`,
`infinity`, `nan`.

The first ten are the class objects, `system` is
[the process](#the-program-and-its-process), and the rest are values.

`self` is not a global; it is recognised by the compiler inside a block.

`include` is not reserved at all. The directive is `@include`, one token, and no
identifier can begin with `@` — so the language has no keywords in the ordinary
sense and the `@` space cannot collide with a name you might want.

---

## Values

| Type | Literal | Semantics |
| --- | --- | --- |
| nil | `nil` | the absent value |
| boolean | `true`, `false` | |
| integer | `#45` | signed 64-bit, **immutable** |
| float | `45.5` | IEEE-754 binary64, **immutable** |
| string | `"hi"` | **immutable** |
| array | `[#1]` | growable, **mutable** |
| dictionary | *none* — `dictionary:new` | values under keys, **mutable** |
| symbol | `'foo` | an interned name, **immutable** |
| block | `{ #1 }` | code as a value |
| object | `object:new` | slots plus a prototype, **mutable** |

**Values and references divide on mutability.** Numbers and strings are
immutable, so they are values: two are equal when they say the same thing, and
sharing is always safe. Arrays, blocks, and objects are references: two are equal
only when they are the same one, and `a := b` makes two names for one thing.

```
a := "hi". b := "hi". a:equals(b):print.      ; true  -- same characters
a := [#1]. b := [#1]. a:equals(b):print.      ; false -- two arrays
```

### Strictness

Types never coerce. An integer does not combine with a float, and a string does
not join to a number.

```
#45:add(1.5).        ; solvm: 'add' expects integer, got float (no implicit coercion)
"a":concat(#1).      ; solvm: 'concat' expects a string, got integer
#45:asFloat:add(1.5) ; the conversion is written out
```

Integer arithmetic traps rather than wrapping: overflow, division by zero, and
`INT64_MIN div #-1` are all errors. Floats follow IEEE, so they overflow to
`infinity` and divide by zero to it, infinity being a representable float where
there is no such integer.

---

## Names and binding

`:=` binds a name to an evaluated value. It means the same thing everywhere.

```
a := #45.                            ; a global
integer:double := { self:mul(#2) }.  ; a slot on a class
p:x := #3.                           ; a slot on an object
```

Only **parameters** and names declared with `| ... |` are locals. Everything else
is a global, read or written.

```
counter := #0.
integer:bump := {
    counter := counter:add(#1).      ; updates the global
    counter
}.

integer:quadruple := { | d |         ; a temporary of this frame
    d := self:double.
    d:double
}.
```

Only the top level of a script may **create** a global. An undeclared name
assigned inside a block must already exist, so a typo is reported rather than
quietly becoming a variable that looks local.

Declarations may open a block or a method body, and a duplicate name in one
frame is a compile error.

A group may open with them too, **anywhere**, the top level of a script
included:

```
( | t | t := #5. t ):print.      ; #5
```

A group borrows the frame it sits in rather than making one, so its temporaries
belong to that frame — and the whole script is one frame. Two groups in a file
therefore share a namespace and cannot both declare `t`, exactly as two groups
inside one block cannot.

This was refused until the script's frame had slots to declare into. See
[ROADMAP 6.6](ROADMAP.md#66-the-loop-constructs-are-library-code-and-pay-for-it)
for the other thing that was waiting on the same field.

---

## Messages

`:` is the send operator. Parentheses group a message's arguments.

```
receiver:selector.
receiver:selector(a).
receiver:selector(a, b).
```

Sends chain left to right:

```
#2:add(#3):mul(#4):print.     ; #20, being (2+3)*4
```

There are no operators and no precedence to remember; `a:add(b:mul(c))` is
written out.

A bare identifier resolves to a local, then to an enclosing frame's local, then
to a global. It is a lookup, not a send.

### Grouping

`( ... )` groups an expression, which is how a chain is redirected:

```
#1:add(#2):mul(#3):print.       ; #9, being (1+2)*3
#1:add((#2:mul(#3))):print.     ; #7, being 1+(2*3)
```

A group may hold several statements separated by `.`. The earlier ones are
discarded and the last is the group's value.

```
( #1. #2 ):print.               ; #2
```

It may also open with `| a, b |`, declaring temporaries of the frame it sits in
-- the script's own frame included. Two groups sharing a frame share one
namespace; see [Names and binding](#names-and-binding).

**A group is not a block.** Both are code in brackets, both hold statements
separated by `.`, both answer their last one, and both may declare temporaries.
Everything else differs: a group runs where it is written, exactly once, and a
block runs only when something sends it `value`, then as many times as it is
sent.

```
(#1:add(#2)):print.             ; #3      -- the group ran
{ #1:add(#2) }:print.           ; <block> -- nothing ran
```

A group also borrows the frame it sits in, where a block makes one -- which is
why a group can only declare temporaries somewhere that already has a frame.

That the argument to `ifTrue` is a block and not a group is the whole of how
control flow works here: an argument is evaluated before the send, so a group
would have run before `ifTrue` could decide anything. See
[Control flow](#control-flow).

---

## Blocks

`{ ... }` makes a block: code as a value. Writing one runs nothing.

```
b := { #21:add(#21) }.
b:value():print.              ; #42
```

Parameters come before `|`. A leading `|` declares temporaries, and a block may
have both -- the parameters, then a temporaries list of its own:

```
{ k | | t | t := k:add(#1). t }
```

```
add := { a, b | a:add(b) }.
add:value(#3, #4):print.      ; #7

{ | t | t := #5. t:add(#1) }:value():print.   ; #6
```

A block's body may hold several statements separated by `.`; the last is its
value.

### Capture

A block reads the frame it was written in, lexically, however many blocks deep.

```
integer:sumTo := { | total, i |
    total := #0.
    i := #1.
    { i:greaterThan(self):not }:whileTrue({
        total := total:add(i).
        i := i:add(#1)
    }).
    total
}.
```

`self` is the receiver the block was written under, captured when the block is
created — so a block inside a method still answers the right object.

A block that reads or writes its enclosing frame cannot outlive it. Calling one
after that frame has returned is reported, not left to read whatever now sits
there. A block that touches nothing outside itself may escape freely.

---

## Control flow

There is no control-flow syntax. `ifTrue`, `ifElse`, and `whileTrue` are ordinary
messages that take unevaluated blocks, so a user can add control structures the
same way.

```
#5:lessThan(#10):ifTrue({ "small":display }).
#5:lessThan(#10):ifElse({ "small" }, { "large" }):display.

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

`and` and `or` take a block for the same reason — so the answer can be settled
without running it.

```
x:greaterThan(#0):and({ x:lessThan(#10) }).
```

`whileTrue` and `and`/`or` are strict about the block answering a boolean.

### What the compiler does with them

Written literally, `ifTrue`, `ifFalse`, `ifElse`, `whileTrue`, `doUntil`, `and`,
and `or` compile to jumps: no block is allocated and no frame is entered.

`repeat`, `toDo` and `toByDo` are **not** in that list and deliberately so. They
are primitives, which is faster here than inlining would have been: inlining
removes the block call an iteration and keeps two bytecode sends for the
counter, where a primitive removes the two sends and keeps the block call. The
sends cost more — measured, the primitive is 2.5× what inlined jumps produced. This is an optimisation
only — the meaning is exactly that of the message, and the message is still
there, reachable through `perform` or with a block held in a variable.

It applies when every block involved is written on the spot with no parameters
and no temporaries. For `whileTrue` that includes the receiver, since the
condition is the receiver. Anything else is compiled as an ordinary send, so
these still mean what they say rather than being quietly rewritten:

```
true:ifElse({ a | a }, { #2 }).      ; still an arity error, as a send would be
true:ifElse({ | t | t := #1. t }, { #0 }).   ; t stays in a frame of its own
{ a | a }:whileTrue({ #1 }).         ; the condition is a block like any other
```

A non-boolean receiver reports the same error either way:

```
#45:ifElse({ #1 }, { #2 }).
solvm: integer does not understand 'ifElse'
```

A condition that answers something other than a boolean is `whileTrue`
complaining about the answer, not a receiver failing to understand a message,
and it reads the same either way:

```
{ #1 }:whileTrue({ #2 }).
solvm: whileTrue expects the condition block to answer a boolean, got integer
```

`doUntil` names itself too, its condition being a block like `and`'s:

```
{ #1 }:doUntil({ #5 }).
solvm: 'doUntil' expects the block to answer a boolean, got integer
```

**`doUntil` is the loop `whileTrue` cannot write.** `whileTrue` tests before the
body runs, so a loop that must run at least once needs a flag declared outside
it. Inlined, `doUntil` needs no flag — which makes it **faster than the loop it
replaces**, not a convenience paid for: 1.28× the hand-written flag version,
because that flag costs two sends an iteration the jumps do not need.

`and` and `or` say the same thing about their block, naming themselves, since
what the block answered is what they answer:

```
true:and({ #5 }).
solvm: 'and' expects the block to answer a boolean, got integer
```

A loop compiles to a jump backwards, which is the only way the machine can run
the same instruction twice. It therefore need not terminate — but neither need
the loop it was compiled from, so nothing is reachable that was not before.

Recursion works, and with conditionals it terminates:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul(self:sub(#1):factorial) })
}.
```

---

## Objects

There is no separate notion of a class. `object:new` answers a fresh object
delegating to the receiver; whether something is a class or an instance is how
you use it.

```
point := object:new.
point:x := #0.                       ; a default every instance sees
point:y := #0.
point:sum := { self:x:add(self:y) }. ; a method: a slot holding a block

point:make := { a, b | | p |
    p := self:new.                   ; self, so it survives inheritance
    p:x := a.
    p:y := b.
    p
}.

p := point:make(#3, #4).
p:sum:print.                         ; #7
```

- A slot holding a **block** is a method; sending its name runs it with the
  receiver as `self`. A slot holding anything else answers that value.
- Assigning on an instance always makes the **instance's own** slot, so it
  shadows the prototype rather than writing through.
- Delegation chains, and the nearest slot wins.

### The built-in classes are objects too

`integer`, `array`, `string` and the rest are ordinary objects holding the
messages their *instances* understand. Sending one of those to the class itself
is an error, not a shortcut:

```
[#1, #2]:add(#3).    ; the array grows
array:add(#3).       ; solvm: 'add' expects an array, got object
```

The messages a class answers for itself are the ones that make instances —
`array:of(...)`, `array:new`, `object:new` — plus reflection, which reads either
side. `respondsTo` agrees with sending, so `array:respondsTo('add)` is false and
`array:respondsTo('of)` is true.

**Only three classes construct** — `object`, `array` and `dictionary` — and the
rule is mutability: `new` belongs where something is *made*, which is where the
instances are references, so there is a fresh, distinct one to hand back.

```
array:new:equals(array:new):print.    ; false -- two arrays
"":equals(""):print.                  ; true  -- one value
```

A value class has no fresh distinct thing to answer with, so the six that are
left refuse and say what to write instead:

```
integer:new(#45).
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one
```

They refuse rather than going missing because every built-in delegates to
`object`, whose `new` would otherwise answer an object delegating to `integer` —
a thing that fails every message an integer understands.

`integer:new` and `float:new` used to answer their own argument, which was the
literal spelled longer. See
[class-and-instance.md](class-and-instance.md#new-means-three-things).

Every built-in class delegates to `object`, so there is one hierarchy and
everything is an object in the type graph as well as in the slogan:

```
#45:isKindOf(object):print.      ; true
"s":isKindOf(object):print.      ; true
integer:parent:equals(object):print.   ; true
object:parent:print.             ; nil  -- the chain ends here
```

Four classes cannot make their instances, because those instances are not
objects, and they say so rather than inheriting a `new` that would answer
something useless:

```
string:new.
solvm: a string is written as a literal, not made with 'new' -- "" is the empty one
```

`symbol`, `block` and `boolean` refuse in the same way, each naming what to
write instead.

Binding a block over one of these replaces the requirement along with the
primitive, so a class can be given messages of its own:

```
array:describe := { "arrays, in a list" }.
array:describe:display.
```

### Adding methods to a built-in class

A built-in class is an object and a slot holding a block is a method, so
extending one needs no new rule — it is the same `:=` used everywhere:

```
integer:double := { self:mul(#2) }.
#21:double:print.                    ; #42
```

Every built-in takes them, arguments and recursion included:

```
integer:between := { lo, hi | self:greaterOrEqual(lo):and({ self:lessOrEqual(hi) }) }.
#5:between(#1, #10):print.           ; true

string:shout   := { self:asUppercase:concat("!") }.   ; "hey":shout   -> "HEY!"
array:second   := { self:at(#2) }.                    ; [#1,#2,#3]:second -> #2
boolean:toggle := { self:not }.                       ; true:toggle  -> false
block:twice    := { self:value. self:value }.
```

The addition is global: every integer gains `double`, because there is one
`integer` and that is where the method now lives. To give a *distinct* type its
own behaviour, build an object that holds a value rather than extending the
class — a value type cannot be subclassed, since an unboxed number's class is
chosen by its type tag and there is nowhere to record a different one.

Two things to know before overriding a message that already exists.

**The primitive is gone.** A slot wins over a primitive of the same name, and
nothing keeps the displaced one. `via` cannot reach it either: a built-in class
has no ancestor holding the version you replaced.

**Do not build the text with `fill` inside an `asString` override.** `fill`
renders each of its values by *sending* `asString`, so it re-enters the override
and recurses until the call-depth cap:

```
integer:asString := { "<{}>":fill([self:abs]) }.
#42:asString.
solvm: call depth exceeded
```

Use `concat` there instead. The recursion is bounded rather than fatal, but it
is an easy loop to write.

### Calling what you override

`self:via(ancestor)` begins the lookup at the ancestor but keeps the receiver, so
`self` inside the ancestor's method is still the instance.

```
animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro:display.            ; I am rex!
```

The ancestor is named rather than inferred, so a method extends the object it was
written against however deep the receiver is.

`parent` reads the delegation link and is read-only.

**Assigning it does not re-parent.** `o:parent := other` binds an ordinary slot
named `parent`, which shadows the message — the delegation link is an internal
pointer rather than a slot, so nothing a program writes can corrupt dispatch.
The assignment succeeds, `o:parent` then answers `other`, and what `o` actually
delegates to is unchanged:

```
a := object:new. a:tag := #1.
b := object:new. b:tag := #2.
kid := a:new.

kid:parent := b.
kid:parent:equals(b):print.      ; true   -- the slot answers
kid:tag:print.                   ; #1     -- but the chain still runs to a
```

This is the ordinary shadowing rule rather than a special case: a slot always
wins over a primitive of the same name, which is what lets an object define its
own `asString`. It is worth knowing because it is the one assignment that looks
like it did something and did not.

There is no way to re-parent at run time. It would need the link to become a
real slot, which is a separate question — see [ROADMAP.md](ROADMAP.md) 2.14.

### Showing an object

Define `asString` and it serves `print`, `display`, `fill`, and an enclosing
array alike.

```
point:asString := { "point({}, {})":fill([self:x, self:y]) }.
p:print.                      ; point(3, 4)
[p]:print.                    ; [point(3, 4)]
```

Without one, an object shows its address.

---

## Asking whether a value is there

`isNil` and `notNil` are on **every type**, and they have to be: the point of
asking is that you do not know what the receiver is, so a message only nil
understood could not be sent to find out.

```
system:readLine:isNil:print.     ; true at the end of input
"":isNil:print.                  ; false -- empty is not absent
```

`notNil` exists rather than leaving `isNil:not` to say it, because the negative
is the form that gets written: running out of input is how a loop finishes.

```
line := system:readLine.
{ line:notNil }:whileTrue({ ... }).
```

`x:equals(nil)` says the same thing and is what the language had before these.
It reads as a comparison against a value rather than a question about absence,
and its negative is three concepts deep to ask one thing.

Absence is not emptiness: `""`, `#0`, `[]` and `false` all answer `notNil`. See
[absence.md](absence.md).

---

## Errors

Every failure stops the program unless something catches it.

```
{ nil:frobnicate }:onError({ e | e:message:display }).
        ; nil does not understand 'frobnicate'
```

`onError` runs the receiver, and if it fails runs the handler with the error
instead. It answers **the receiver's answer when nothing went wrong, and the
handler's when something did** — so it is an expression:

```
text := { system:readFile(path) }:onError({ e | "" }).
```

A caught error says nothing: the message never reaches stderr, and the program
carries on.

### Raising one

```
error:raise("bad input on line 3").
```

`error:raise` is the only way to raise, so **re-raising is
`error:raise(e:message)`**. Two spellings — one on the class taking a string,
another on an instance taking none — would be one name meaning two things, which
is a mistake this language has made once already with `new`. The price of having
one is that a re-raised error's stack points at where it was re-raised rather
than where it first failed. That is honest: it *is* a new raise.

### The error

An ordinary object delegating to `error`, with its message in a slot.

| Message | Answers |
| --- | --- |
| `message` | the text, as a string; nil on an error made some other way |

It is a value rather than a string on purpose. This project rewords its errors
freely, so handing a handler the text and nothing else would make matching on it
the only way to tell failures apart — an idiom these very habits would keep
breaking. An object leaves room to say more about a failure later without
breaking every handler that already exists.

There is no taxonomy of failures. Inventing one to go with a catch mechanism
would be inventing it in the wrong order.

### What it catches

**Everything** — including a message misspelled into one the receiver does not
understand. That is the deliberate choice and the familiar hazard: a handler
wrapped around too much hides mistakes. What makes it bearable is that passing
one on is a single message:

```
{ risky:value }:onError({ e |
    e:message:equals("empty"):ifElse(
        { "(nothing given)" },
        { error:raise(e:message) })       ; not ours -- pass it on
}).
```

Two things it does not catch. **`system:exit`** travels the same way, being a
stop rather than a failure, and a program asking to stop should not be argued
with by something that was only watching for errors. And an error raised **inside
the handler** is not caught by that handler — it propagates, like any other
failure.

The handler is checked when it is run, not when `onError` is sent, so
`{ #1 }:onError(#2)` is quiet when nothing fails. That is how every block
argument here behaves: `false:ifTrue(#5)` says nothing either.

---

## Reflection

Five messages let a program ask about itself. Names are given as symbols,
because a symbol is what a name is and comparing one is a pointer comparison.

| Message | Answers |
| --- | --- |
| `slots` | an array of symbols naming the receiver's **own** slots |
| `slotAt(name)` | the value in that slot, searching the chain like a send |
| `respondsTo(name)` | whether a send of that name would find anything |
| `isKindOf(class)` | whether the receiver delegates to `class`, at any depth |
| `perform(name, ...)` | the answer to a send whose name is decided at run time |

Continuing the `point` above:

```
point:slots:print.               ; ['x, 'y, 'sum, 'make]
p:isKindOf(point):print.         ; true
p:respondsTo('sum):print.        ; true
p:perform('sum):print.           ; #7
```

`slots` answers own slots in the order they were defined; inherited names are
not yours, and `parent:slots` is how you ask about those. `respondsTo` and
`slotAt` search the whole chain, as a send does.

A value answers for the class it dispatches to, so `#45:isKindOf(integer)` is
true and `#45:respondsTo('add)` is true. `slots` and `slotAt` want an object to
look inside and say so on anything else.

The built-in classes are objects whose slots hold primitives, so
`integer:slots` lists what an integer understands. `slotAt` on one of those is
an error: a primitive is C, and has no value to answer.

### Fetching a method

A slot holding a block **is** a method, so `slotAt` is the only way to get at
one as a value. What comes back is the plain block, and `self` is supplied by a
send rather than carried by the block:

```
m := point:slotAt('sum).
m:value.                 ; solvm: nil does not understand 'x'
p:perform('sum):print.   ; #7 -- the receiver comes from the send
```

`boundTo` chooses one. It answers a **second block** over the same code with
`self` set, which you then call like any other block. The longer explanation,
including what it is for, is in [fetched-methods.md](fetched-methods.md):

```
bound := m:boundTo(p).
bound:value:print.       ; #7
```

Binding and calling stay two things, as `via` keeps them two things. So `value`
means exactly what it always meant -- the arguments are the block's own, and the
receiver is not one of them:

```
n := integer:slotAt('poly):boundTo(#10).
n:value(#3, #7):print.   ; #37
```

The receiver may be any value, since `self` may be. The original block is
untouched: binding answers a new one, and binding that one binds again.

Two things it does **not** do. It does not lift the frame restriction — a block
that reads its home frame is no freer for being bound, so binding chooses a
receiver, not a lifetime. And it does not survive a send: installing a bound
block in a slot still makes an ordinary method, and a send supplies its own
receiver, which is what makes an installed block a method at all.

```
b:show := m:boundTo(a).
b:show.                  ; the send wins -- self is b, not a
```

---

## Message reference

Every built-in message. `print` shows the **literal** form (`#45`, `"a\"b"`);
`display` writes the **text** (`45`, `a"b`); `asString` answers that text as a
string.

Elements inside an array are always shown in literal form, so that a printed
array reads back as one: `["a"]:display` writes `["a"]`, quotes and all, where
`"a":display` writes `a`.

### Every type

`print`, `display`, `asString`, `equals`, `notEquals`, `isNil`, `notNil` (see
[Asking whether a value is there](#asking-whether-a-value-is-there)), and the
reflection messages `perform`, `respondsTo`, `isKindOf`, `slots`, `slotAt` (see
[Reflection](#reflection)).

`asString` takes an optional format spec:

```
[align] [','] ['0'] [width] ['.' decimals]

45.8:asString("6.2")         ; " 45.80"
45.8:asString("08.2")        ; "00045.80"
#1234567:asString(",")       ; "1,234,567"
1234.5:asString(",10.2")     ; "  1,234.50"
#45:asString("<6")           ; "45    "
"ab":asString(">6")          ; "    ab"
```

`<` `>` `^` align left, right, centre. Numbers align right by default and
everything else left. A value wider than the width is never cut.

`,` groups whole-number digits in threes, and only those -- a sign, a fraction,
and an exponent pass through. Decimals and grouping belong to numbers; asking a
string, a boolean, or an array for either is an error.

Zero fill must align right and goes after any sign, so `#-45:asString("06")` is
`-00045`. It cannot be combined with `,`. The flags have one order, so there is
one way to write a given spec.

With no argument it answers the plain text, which is what `display`, `fill`, and
array rendering ask for.

`equals` compares characters for strings and identity for arrays, blocks, and
objects.

### integer

| Message | Answers |
| --- | --- |
| `add(n)` `sub(n)` `mul(n)` | an integer; traps on overflow |
| `div(n)` `mod(n)` | **floored**; traps on zero and on `INT64_MIN div #-1` |
| `negated` `abs` | an integer; traps on the most negative |
| `lessThan(n)` `greaterThan(n)` | a boolean |
| `lessOrEqual(n)` `greaterOrEqual(n)` | a boolean |
| `asFloat` | a float; loses precision above 2^53 |
| `asString` | the digits, without the `#` |
| `asBase(#n)` | the digits in base `n`, 2 to 36, as a string |
| `repeat(block)` | nil, having run the block that many times |
| `toDo(#b, block)` | nil; the block is given each of the receiver to `#b`, **inclusive** |
| `toByDo(#b, #step, block)` | the same, by `#step`; negative counts down |

`#-7:div(#2)` is `#-4` and `#-7:mod(#2)` is `#1`: division floors, so the
remainder takes the divisor's sign and stays in `[0, n)` for positive `n`.

### float

Everything integer has, minus `asFloat`, `asBase`, and the overflow traps, plus:

| Message | Answers |
| --- | --- |
| `floor` `ceiling` `rounded` `truncated` | an **integer**; errors on infinity, not-a-number, or out of range |

There is no `asInteger`: narrowing names its direction so there is no default to
remember. `rounded` is half away from zero. Bases are an integer's business, so
`asBase` is not here.

Dividing by zero answers a float rather than erring: `1:div(0)` is `infinity`,
`-1:div(0)` is `-infinity`, and `0:div(0)` is `nan`, which is IEEE rather than a
choice made here. `nan:equals(nan)` is false for the same reason.

A float is written as the shortest text that reads back as the same value, so
`0.1` prints as `0.1` and not as the seventeen digits it really is. A whole
float prints without a point, which is how the two number types are told apart
on the page: the `#` marks the integer.

```
45:print.            ; 45
#45:print.           ; #45
1:div(3):print.      ; 0.3333333333333333
1e21:print.          ; 1e+21
0.000001:print.      ; 1e-06
```

`infinity` and `nan` are written by name, and both read back — `infinity` and
`nan` are globals, and `asFloat` parses either. `-infinity` has no literal;
`"-infinity":asFloat` gives it.

### string

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `at(#i)` | a one-character string; **one-based** |
| `concat(s)` | a new string; strict about its argument |
| `split(s)` | an array of the pieces between occurrences of `s` |
| `indexOf(s)` | where `s` first appears, **one-based**, or nil |
| `copyFrom(#a, #b)` | the characters `#a` to `#b`, both ends included |
| `fill([...])` | a new string with the blanks filled; see below |
| `lessThan(s)` `greaterThan(s)` | a boolean, comparing characters |
| `lessOrEqual(s)` `greaterOrEqual(s)` | a boolean |
| `asInteger` `asFloat` | strict: the whole string must be a number |
| `asInteger(#n)` | reads base `n`, 2 to 36; the digits alone, no `0x` |
| `asUppercase` `asLowercase` | a new string; ASCII letters only |
| `asSymbol` | the interned symbol for these characters |
| `asString` | itself |
| `asString(spec)` | padded text; see the spec below |

#### Taking a string apart

`split` answers **occurrences + 1 pieces**, always, and never drops one. A
separator at either end, or two together, gives an empty string where the
missing piece would be:

```
"a,b,c":split(",").      ; ["a", "b", "c"]
"a,,b":split(",").       ; ["a", "", "b"]
",a":split(",").         ; ["", "a"]
"abc":split(",").        ; ["abc"]   -- no occurrence, so one piece
"":split(",").           ; [""]
```

That is what makes the answer predictable: the pieces put back together with the
separator between them are the string you started with, whatever it was.
Dropping empties would read more kindly on `" a  b "` and would lose the
difference between `"a,,b"` and `"a,b"` — usually the one thing a program
parsing a file needs to keep.

Occurrences are taken left to right and not reconsidered, so `"aaaa":split("aa")`
is three empty pieces rather than two.

`indexOf` answers **nil when there is no match**, not `#0`. Indices start at
`#1`, so `#0` would be an out-of-band value and a second way of saying "nothing"
beside the one the language already has; `text:indexOf(","):isNil` is the
same question asked of an unset slot or the end of input.

`copyFrom` includes both ends and both are one-based, so `copyFrom(#i, #i)` is
exactly `at(#i)`. An empty result is spelled with `to` **one** before `from`, and
that is the only spelling — anything further apart is a mistake rather than a
wider empty. `from` may be one past the end for the same reason: that is where
the empty tail is.

```
"hello":copyFrom(#2, #4).    ; "ell"
"hello":copyFrom(#3, #2).    ; ""
"hello":copyFrom(#6, #5).    ; ""
"hello":copyFrom(#4, #2).    ; error: ends at #2, more than one before its start #4
"hello":copyFrom(#2, #6).    ; error: ends at #6, past a string of size 5
```

Neither `split` nor `indexOf` will look for the empty string: every position in
every string contains it, so the answer would be arbitrary rather than useful.
Both refuse it.

All three respect the length rather than stopping at the first NUL, so they work
on a file read with `readFile` whatever is in it.

[`join`](#array) puts the pieces back: `s:split(sep):join(sep)` is `s`, for
every string and every separator.

#### Filling in blanks

`fill` puts the array's values into the `{}` blanks, rendering each by sending
it `asString`. `{{`
writes a literal brace; `}` is never special. Placeholders and values must match
exactly — too few and too many are both errors.

```
"you have {} apples":fill([#3]):display.    ; you have 3 apples
```

Parsing is strict at both ends: `" 45"` and `"45 "` are errors, not `45`.

Bases go through `asBase` and `asInteger(#n)` rather than a letter in the format
spec, so one message covers every base from 2 to 36 and nothing in the spec
starts looking like a conversion character. Digits above nine are lowercase, and
padding comes from the spec by chaining:

```
#255:asBase(#16)                    ; "ff"
#255:asBase(#16):asString("08")     ; "000000ff"
"ff":asInteger(#16)                 ; #255
```

### array

| Message | Answers |
| --- | --- |
| `new` | an empty array |
| `of(...)` | an array of the arguments — what `[...]` compiles to |
| `size` | an integer |
| `at(#i)` | the element; **one-based**, out of range is an error |
| `at_put(#i, v)` | the value stored |
| `add(v)` | **the array**, so it chains |
| `do(block)` | the array, having run the block per element |
| `collect(block)` | a new array of the block's answers |
| `select(block)` | a new array of the elements the block accepted |
| `inject(start, block)` | one value, folded left to right |
| `copyFrom(#a, #b)` | a new array, `#a` to `#b`, both ends included |
| `first(#n)` `last(#n)` | a new array of up to `n`; **clamps** |
| `join(s)` | the strings with `s` between them; strict |
| `sorted` | a new array in ascending order |
| `sorted(block)` | a new array ordered by the block |

`collect`, `select`, `inject`, `join` and `sorted` all leave the receiver
untouched. `select` and the comparison block are both strict about answering a
boolean.

**Folding.** `inject` gives the block what has accumulated so far and one
element, and takes its answer as the next accumulation:

```
[#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) }).   ; #10
[#1, #2, #3]:inject("", { s, n | s:concat(n:asString) }).   ; "123"
```

An empty array answers `start` without calling the block, so a fold is safe to
write without asking first whether there is anything to fold. What accumulates
need not be the elements' type, and the order is left to right.

It completes the four iteration messages: `do` throws its answers away,
`collect` and `select` each answer an array, and `inject` answers one value.
Unlike `do` it is an expression, so it can stand in the middle of one rather
than only at the top of a frame where an accumulator could be declared.

**Slicing.** `copyFrom` is the string's rule exactly: both ends included, both
one-based, an empty slice spelled with `to` one before `from`, and out of range
an **error** — following `at`. Two collections disagreeing about what a slice
means would be worse than either rule is good.

```
[#1, #2, #3, #4, #5]:copyFrom(#2, #4).   ; [#2, #3, #4]
[#1, #2, #3, #4, #5]:copyFrom(#3, #2).   ; []
[#1, #2, #3]:copyFrom(#1, #4).           ; error: ends at #4, past an array of size 3
```

`first` and `last` **clamp** where `copyFrom` refuses, and that is two rules on
purpose, because they are two questions. `copyFrom` names *positions*, and a
position outside the array is a program wrong about something. `first` names a
*quantity* — give me the top five — which a list of three has answered correctly
by handing over three. Refusing there would make every ranked report check the
size first, which is the whole of what these exist to avoid.

```
[#1, #2, #3]:first(#2).      ; [#1, #2]
[#1, #2, #3]:last(#2).       ; [#2, #3]
[#1, #2, #3]:first(#99).     ; [#1, #2, #3]  -- everything there is
[#1, #2, #3]:first(#0).      ; []
```

A negative count is refused by both: clamping is for asking for more than there
is, not for asking for nonsense.

All three answer a new array and share its elements, an array holding references
— so a slice of an array of arrays sees the same inner arrays.

**Joining.** `join` is `split` backwards, and the round trip holds for every
string and every separator — which is what `split` keeping its empty pieces buys:

```
"a,,b":split(","):join(",").     ; "a,,b"
[]:join(",").                    ; ""
["only"]:join(",").              ; "only"
```

It is strict about what it joins: an array holding anything but a string is an
error rather than a silent `asString` on each element, rendering being what
`asString` and `fill` are for.

The separator **may** be empty, where `split`'s may not. The two are not the
same question: nothing cannot be looked for, since every position contains it,
but putting nothing between the pieces is exactly concatenation.

**Sorting.** With no argument the order comes from *sending* `lessThan`, so a
type that defines one sorts itself:

```
[#3, #1, #2]:sorted:print.                            ; [#1, #2, #3]
["pear", "apple"]:sorted:print.                       ; ["apple", "pear"]
[#1, #3, #2]:sorted({ a, b | b:lessThan(a) }):print.  ; [#3, #2, #1]
```

The comparison answers whether `a` comes strictly before `b`. Mixed types are an
error rather than an arbitrary order, for the same reason arithmetic on them is:
`lessThan` has no coercion to fall back on.

The sort is **stable** -- equal elements keep the order they were in -- which is
what makes sorting twice a way to order by two keys: sort by the minor key
first, then by the major one.

### symbol

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `asString` | the name, as a string |

`'foo` is an interned name: two symbols spelling the same thing are the same
symbol, so `equals` is a pointer comparison. `"foo":asSymbol` finds the existing
one. A symbol never equals a string.

Useful as a tag where a string would be compared character by character:

```
state := 'running.
state:equals('running):ifTrue({ "go":display }).
```

### boolean

| Message | Answers |
| --- | --- |
| `not` | a boolean |
| `and(block)` `or(block)` | short-circuit; the block runs only if needed |
| `ifTrue(block)` `ifFalse(block)` | the block's answer, or nil |
| `ifElse(t, f)` | the chosen block's answer |

### dictionary

Values kept under keys, found by hashing. There is no literal — `dictionary:new`
makes an empty one.

| Message | Answers |
| --- | --- |
| `new` | an empty dictionary |
| `size` | an integer |
| `at(key)` | the value; **an error** when the key is not there |
| `at(key, default)` | the value, or `default` when the key is not there |
| `atPut(key, value)` | **the value stored**, so it chains |
| `includes(key)` | a boolean |
| `remove(key)` | the value removed; an error when the key is not there |
| `keys` `values` | an array, in **no order worth relying on** |
| `do(block)` | the dictionary, having run the block once per **value** |
| `keysAndValuesDo(block)` | the same, the block taking a key and a value |

**Keys are values.** Integers, floats, strings, symbols, booleans and nil are
compared by content, so two keys that look alike are one key. Arrays, blocks,
objects and other dictionaries are compared by identity, where two that look
alike would be two keys — the right answer for `equals` and a useless one here,
so they are refused rather than quietly behaving that way:

```
d:atPut([#1], "nope").
solvm: 'atPut' wants a value for a key, got array -- those are compared by identity, so two that look alike would be two keys
```

It is the same line the language draws between
[values and references](#values) everywhere else.

`at(key, default)` is the form a counter wants, since it needs no separate
question first:

```
counts:atPut(word, counts:at(word, #0):add(#1)).
```

`do` takes a one-argument block over the values, exactly as an array's does: the
same selector should not want a different shape of block depending on what it is
sent to. `keysAndValuesDo` is the two-argument form, and it beats `keys:do` with
an `at` inside because it does not look each key up a second time.

Both walk a **snapshot of the keys**, so a block that adds to the dictionary it
is walking does not rehash the table underneath itself; one that removes a key
it has not reached yet will not see it.

`keys` and `values` are snapshots too, and their order is the table's, which is
to say arbitrary. Sort before showing anything.

A dictionary is a reference, like an array: `equals` is identity, so two with
equal contents are two dictionaries. It cannot be a constant in a `.sob` for the
same reason an array cannot — it is built at run time.

`nan` is accepted as a key and can never be found again, since `nan:equals(nan)`
is false. That is IEEE showing through rather than a decision made here.

---

### block

| Message | Answers |
| --- | --- |
| `value(...)` | the block's answer; the count must match its parameters |
| `boundTo(receiver)` | a new block over the same code, with `self` set |
| `whileTrue(body)` | nil, having run `body` while the receiver answers true |
| `doUntil(condition)` | nil, having run the receiver **until** the condition is true — the body first, so always at least once |
| `repeat(#n)` | nil, having run the receiver `n` times |
| `onError(handler)` | the block's answer, or the handler's if it failed |
| `timeToRun` | seconds the block took, as a float |
| `timeToRun(#n)` | seconds `n` runs took, as a float |

### object

| Message | Answers |
| --- | --- |
| `new` | a fresh object delegating to the receiver |
| `via(ancestor)` | a delegating view: lookup starts there, `self` stays |
| `parent` | the prototype, or nil at the root; read-only — assigning it shadows the message rather than re-parenting |

`slots` and `slotAt` are listed under [Reflection](#reflection); they are on
every type but answer only for objects.

### system

One object, bound to the global `system`. Not a class: it has no instances, and
it delegates to `object` like everything else. See
[The program and its process](#the-program-and-its-process).

| Message | Answers |
| --- | --- |
| `exit(status)` | nothing — the program stops, with `status` from #0 to #255 |
| `arguments` | an array of strings; the empty array when there were none |
| `readLine` | one line of standard input without its terminator, or nil at the end |
| `readFile(path)` | the whole file as a string; an error if it is not there |
| `writeFile(path, text)` | nil, having replaced the file's contents |
| `fileExists(path)` | true if a file — not a directory — is at that path |
| `clock` | monotonic seconds as a float; only differences are meaningful |

### nil

`print`, `display`, `asString`, `equals`, `notEquals`, `isNil`, `notNil`, and the
five reflection messages every type carries. Nothing else — asking nil for
anything more is an error rather than nil again, so a missing value is reported
where it is used rather than propagating.

`nil:isNil` is the only receiver that answers true, which is what makes the pair
worth having on every type rather than on nil alone.

`nil` names the value, not a class: there is no global for the class it
dispatches to. `nil:isKindOf(object)` is true, like every other value, but
`nil:slots` says an object is what has slots.

There is one nil and it carries no type, so `string:nil` and `integer:nil` are
not messages anything understands. A name holds a value and never a type, so
what a value is gets asked of the value: `isKindOf(string)` is false for nil and
true for a string. Absence and emptiness are different — `""`, `#0` and `[]` are
values that answer their type's messages, and nil answers almost nothing.

A declared temporary holds nil before it is assigned. A slot that was never
bound is a *miss* rather than a nil, reported like any unknown message, so a
prototype with an optional field binds `nil` as the default. The whole of it,
with the reasoning, is in [absence.md](absence.md).

---

## Errors

**A compile error** names the line and column, then shows the line with the
offending text underlined:

```
[line 2:9] solas: expected '.' between statements at ','
  b := #2 , .
          ^
```

A long line is windowed around the token rather than shown whole. Only the
first error in a statement is reported; the parser then resynchronises at the
next `.` and carries on, so one mistake gives one message.

**A runtime error** stops the program and reports the line of each frame,
innermost first. There is no way to catch one.

```
solvm: integer does not understand 'frobnicate'
  [line 1] in script
```

A running frame knows its line but not its column: the chunk records a line per
byte of bytecode, and a column would be a second table in every `.sob` for a
message only printed when something has already gone wrong.

Errors, rather than silent answers, are the rule: unknown messages, wrong
argument counts, type mismatches, out-of-range indices, integer overflow,
division by zero, undeclared names, and a block outliving its frame.

---

## Limits

| | |
| --- | --- |
| Recursion | about **62 levels** — the frame cap is 64 and a level costs one frame, now that an `ifElse` branch, a `whileTrue` body, and an `and`/`or` block are inlined rather than called |
| Constants, names, blocks per chunk | **65536** — a two-byte index, and both tables intern, so repeats cost nothing |
| Arguments, parameters, array literal elements | 255 — an argument count is one byte |
| Locals per frame | 255 |
| Solis input | no limit — the buffer grows, and reading continues while a bracket or a string is open |
| Strings | bytes, not characters: `size` counts bytes, `at` answers a byte, and `"café":size` is 5 |
| Case | ASCII only, and by explicit range rather than the C locale |
| Strings | no `\0`, no unicode escapes |
| Symbols | read-only: `perform`, `respondsTo`, and `slotAt` take one to *name* something, but nothing takes one to *create* a slot — there is no `slotAtPut` |

Collection is mark-and-sweep and stop-the-world. `SOLUM_GC_STRESS=1` collects on
every allocation, which is how the collector is tested.
