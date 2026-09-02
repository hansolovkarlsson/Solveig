# Solveig -- design notes

## Original notes

The whole project started from this sketch (`notes.txt`, kept verbatim):

```text
new virtual machine

parts:
	Solas: compiler, compile to bytecode
	Solum: virtual machine, executing bytecode
	Solis: interactive version, compile line by line and executes the line

Object oriented, simple syntax
Everything is an object

Example of creating an integer variable and assigning it, then printing it.

	integer:new(a) 	; sends message "integer" to top Object to create an integer object
	a:set(#45)	; assigns integer value #45 to integer object, by sending set message
	a:print.	; sends print message to object a to print out
```

## The four parts

| Part      | Binary      | Job                                          |
| --------- | ----------- | -------------------------------------------- |
| **Solas** | `bin/solas` | Compiler: `.sol` source -> bytecode          |
| **SolVM** | `bin/solvm` | Virtual machine: loads and executes bytecode; sources in `solum/` |
| **Solis** | `bin/solis` | REPL: reads until the input could compile, then runs it |
| **Solid** | `bin/solid` | Debugger: runs a program a step at a time; sources in `solid/` |

Solid came last and is the one that changed the machine to exist: the VM offers
a stop before each instruction that begins a new line or enters a new frame, and
Solid decides whether that stop is interesting. The machine knows nothing about
breakpoints or stepping.

Solas and SolVM meet at exactly one place: `solum/include/solum/bytecode.h`.
That header defines the opcodes, so a change to the instruction set is a change
to one file that both halves already include. Solis links both libraries and
skips serialisation entirely -- it compiles straight into a `SolChunk` and hands
it to the VM.

## The name

**Solveig** names the project. The language is **Solum**, and the four programs
are **Solas**, **SolVM**, **Solis** and **Solid** -- the last being
*sol-interactive-debugger*, which is also a word. See the README for where the
names come from.

## What the language is for

**Solum is meant to be a general-purpose language.** Not a scripting language,
not a shell language, not a teaching language -- those are shapes it can take,
and one of them is the shape it happens to have taken first.

That first shape was a *discovery* rather than a decision. The twenty<!--count programs-->
programs in
[programs/](../programs/) are a webserver, three parsers, a disassembler, a log
analyser, a documentation checker, a benchmark harness, a mirror and a page
generator, and they lean towards text and processes for a reason that has
nothing to do with the language: they are the tools this project needed while
building the thing that runs them. Written against a different need they would
have leaned somewhere else.

**The eighteenth was written to lean somewhere else on purpose**, on 2026-08-31.
[sha256sum](../programs/sha256sum.sol) does sixty-four rounds of shifts, masks
and additions per sixty-four bytes and touches a syscall twice a file, which
makes it the first program here whose inner loop is arithmetic — and it was
chosen for that rather than for being a Unix tool. Each of the others made the
sentence above truer and more misleading at once; this one is the beginning of
the correction rather than another instance of it.

The languages worth comparing against all did the same thing and none of them
stopped there. Python, Java and the rest write shell tools, servers, games,
music and instruments, and none of that was settled in advance -- it followed
from the language being practical enough that somebody reached for it.

**The consequence, and it is a rule for reading the roadmap:** *no program here
has wanted X* is a statement about what has been built. It is never a statement
about what the language is for. It is a good reason to **wait for a program
before choosing a shape**, because the program is what tells you which shape is
right -- and it is not a reason to rule a direction out.

The distinction is easy to lose, and it was lost once already: trigonometry was
very nearly argued away on the grounds that *there is no geometry anywhere near
this language*, which is a true sentence about twenty<!--count programs--> programs
and an empty one
about a language. The entry it belongs to,
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done), now says so.

The admission rule for [ROADMAP.md](ROADMAP.md) is unchanged and is not what
this is about: an entry still means a program wanted something and could not
have it. What changes is the reading of an entry's *absence*. There are further
directions intended for the language, and each will be written down here as it
is decided rather than inferred from what has been built so far.

### The directions intended, stated 2026-08-31

**These are intentions rather than decisions**, and the difference matters: none
of them has been scoped, none is queued, and each will be argued on its own when
it is reached. They are here because the paragraph above promised they would be,
and because *no program here has wanted X* reads differently when the list of
things somebody means to try is written down beside it.

In the words they were given in: **mathematics libraries, graphics, stateful
work, databases, networking, predicate logic, neural networks, and perhaps a
language model.**

**With one condition attached, and it is the load-bearing part**: that the
foundations are covered and solid from the ground up before any of them is
reached. That is a constraint on the order, not a doubt about the list.

**What each currently runs into**, so far as is known on the day it was written.
Some of this is measured and some is inference from how the machine is built, and
which is which is said:

| direction | what stands in front of it |
| --- | --- |
| **Mathematics** | Nothing known. The arithmetic landed with [3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done) and `lib/math.sol` is beside it. |
| **Graphics** | Nothing structural: [GTK4 and SDL2](extensions.md) both draw, and a canvas re-tested the mechanism on 2026-08-30 without needing anything new. At scale it meets the value representation, below. |
| **Stateful work** | Reflection cannot write — no `slotAtPut`, no `clone`, no re-parenting, and no reading a global by computed name ([2.14](ROADMAP.md#214-loose-ends-from-the-decided-items)). |
| **Databases** | Was blocked outright until [3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) closed on 2026-08-31; a ranged read exists now. Still absent: a **positioned write**, a file identity ([6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done)), and anything about locking or flushing. |
| **Networking** | [net](NET.md) is IPv4 UDP only — no TCP, no IPv6, no name resolution — and there is no concurrency: [3.11](ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads) is about threads, and `system:run` blocks with no spawn beside it. |
| **Predicate logic** | Already argued in [ideas.md](ideas.md#programs-that-would-press-on-something): it wants coroutines, continuations and a non-local return, all three refused, so it needs an explicit trail and choice-point stack — and [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) bites on deep resolution. |
| **Neural networks** | The value representation. A `SolValue` is a type tag and a union, so an array of floats is an array of tagged values rather than a `double[]`, and every element access is a send. **Inference, not measurement** — the number is what [`gzip -d`](ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31) is on that survey to produce. The likely answer is an [extension](extensions.md) owning the buffer rather than a new core type, since a small core is a goal in itself. |
| **A language model** | Everything under networking, plus TLS, plus everything under neural networks. The furthest out, and the one whose foundations are least examined. |

**And the thing that gets harder rather than easier out there**: the
[oracle](method.md#hold-it-against-something-somebody-else-wrote) that made sed
and tail worth writing has no equivalent for a neural network — there is no
byte-for-byte answer to be held to. That is the argument for spending the cheap
oracles on the questions the far directions depend on while they are still
cheap, and it is why two of the three tools recommended on 2026-08-31 are
numeric experiments wearing a Unix tool's name.

## Design principles

Not laid down in advance -- these are what the decisions so far have in common,
written down because they keep settling the next question.

**Two spellings of the same thing mean the same thing.** `[#1, #2]` and
`array:of(#1, #2)` produce identical bytecode, and so do `@expr( a + b )` and
`a:add(b)`. Where a shorthand exists it is notation, never a second semantics.
The syntax is already a lot to take on, so a reader should never have to ask
which of two forms they are looking at in order to know what it does.

**There are two of those shorthands and they are the only two**, which is worth
saying because the second one has operators in it. `@expr(...)` began as a
notation for a formula being transcribed — a send chain reads left to right and
precedence does not, so `a^2 + 3*(sin(a/2) + sqrt(b))` written as sends puts its
outermost operation in the middle of the line and cannot be checked against the
page it came from — and it covers comparison and logic too, which is why it is
named for an expression rather than for arithmetic.

What it does not do is add anything to the language. Every operator is a send,
a term inside a region is an ordinary expression, and the bytes are the same
bytes: `a & b` compiles to what `a:and({ b })` compiles to, short-circuiting
included, because that is where the block's body would have gone.

**One operator, one meaning.** `:=` binds a name to an evaluated value, whether
the name is a global, a temporary, or a slot on a class. An earlier design had it
mean something different on the left of a method definition, and removing that
special case took a hundred lines of compiler with it.

**Strict rather than convenient.** Integers and floats never coerce, integer
overflow traps instead of wrapping, an undeclared name inside a method is an
error rather than a new variable, and an out-of-range index is an error rather
than nil. A wrong program should stop, not continue quietly.

Conversion is always asked for, never assumed. `#7:div(#2)` answers an integer,
and a fractional answer needs `#7:asFloat:div(#2:asFloat)`. Narrowing a float
says which way it goes -- `floor`, `ceiling`, `rounded`, `truncated` -- rather
than having a default to remember. Parsing text is strict at both ends: the whole
string must be a number and nothing else, so `" 45"` and `"45 "` are errors.

`asString` answers plain text where `print` shows the literal form: `#45:asString`
is `"45"`, while `#45:print` shows `#45`. Two different jobs, kept apart, and
`display` is the third: it sends `asString` and writes those characters raw.

`print` is for reading a value back -- inside an array, or at a prompt. `display`
is for output. Without the pair, a formatted string could only be shown wearing
quotes, and a string holding newlines could not be written as lines at all.

An object is rendered by asking it: the renderer sends `asString`, so a type that
defines one is shown that way everywhere -- `print`, `display`, `fill`, and
inside an array. `object`'s own `asString` writes the address directly rather
than calling the renderer back, which is what keeps that from recurring.

A string renders with its escapes put back, so `"a\"b"` prints as `"a\"b"` and
reads as one string again. `\"`, `\\`, `\n`, `\t`, `\r` are the escapes;
an unknown one is an error rather than a literal backslash.

`fill` fills `{}` from an array, asking each value for its `asString` by
sending it, so an override is honoured. Placeholders and values must match
exactly in both directions.

A float renders as the shortest decimal that reads back as the same bits, so
printing never shows a different number than it holds, and the text compiles.
Where a number has few enough whole digits the renderer keeps fixed notation --
`1000` rather than `1e+03` -- since extra digits cannot stop it round-tripping.
Infinity and not-a-number are written by name; `infinity` and `nan` are globals,
so those read back.

The line falls where representability does. Integer division by zero traps
because there is no integer infinity; float division by zero answers one, because
float multiplication already overflows to infinity where integer multiplication
traps. Integer division also floors rather than truncating, so `#-7:div(#2)` is
`#-4` and `mod` takes the divisor's sign -- which keeps a remainder inside
`[0, n)` where indexing and cyclic arithmetic want it.

## Object model

Smalltalk lineage, prototype flavour:

- An object is a set of named slots plus a `proto` pointer it delegates to.
- A class is not a separate kind of thing -- it is an object like any other.
  `integer` is the integer class object, found by a lookup and sent to like
  anything else. It does not construct, though: an integer is a value, written
  rather than made, and `integer:new` says so.
- The same holds for objects you define. `object:new` answers a fresh object
  delegating to the receiver, so `point := object:new` then `p := point:new`
  makes `point` a class by use rather than by kind. A slot assigned on an
  instance is always the instance's own, shadowing the prototype rather than
  writing through to it.
- An override reaches what it overrides through `self:via(ancestor)`, which
  begins the lookup at the ancestor but keeps `self` as the receiver. The
  ancestor is named rather than inferred, so no frame has to record where a
  running method was defined, and a method cannot find itself again. `parent`
  reads the delegation link, read-only.
- A method fetched with `slotAt` is the plain block, and `self` comes from a
  send rather than being carried, so a fetched one has no receiver until
  `boundTo(receiver)` gives it one -- which answers a second block over the same
  code rather than calling it, the same shape as `via`. A send still supplies
  its own receiver, which is what makes an installed block a method, so binding
  chooses a receiver for `value` and never overrides a send.
- Message send is the only way to make anything happen. `:` is the send
  operator: `receiver:message(args)`.
- Slot lookup walks the proto chain and terminates at the root Object, which
  doubles as the globals namespace where class objects like `integer` live. Each
  object's own slots are a list; an object with more than a dozen keeps a table
  beside it, which is what makes the walk a step per object rather than a step
  per slot ([3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done)).
- Every built-in class delegates to `object`, so there is one hierarchy:
  `#45:isKindOf(object)` is true, and "everything is an object" holds of the
  type graph as well as the slogan. The four classes whose instances are not
  objects — `string`, `symbol`, `block`, `boolean` — shadow `new` and refuse it,
  since `new` means *make an object delegating to me* and theirs are not.

**A name is compared by pointer, not by spelling.** Every slot name and every
selector goes through one table on the VM, which answers the same address for
the same characters -- so a lookup walking a proto chain compares pointers, and
never looks at a byte of either name. A chunk's name table is resolved through
that table once, before the chunk first runs, which is what keeps the hash off
the path a send takes: the send reads a pointer already resolved. It is also
what lets an object index its own slots by that pointer, since the address is
the identity and is stable for the life of the VM.

This is the VM's own table and not the symbol table behind `'foo`. The two do
the same job and hold it differently: a symbol is a value a program can drop, so
that table is weak and a symbol nothing mentions can die. A name is pointed at
by slots and by chunks, neither of which can say when they are finished with
one, so these live as long as the VM. `sol_object_lookup` still compares
spelling, for C callers holding an ordinary literal; the dispatch loop uses
`sol_object_lookup_interned`, and building with `-DSOLUM_CHECK_INTERNED` makes
it assert that what it was handed really did come from the table.

Values and references divide on mutability. Numbers and strings are immutable,
so they are values: two of them are equal when they say the same thing, and
sharing is always safe. Objects, blocks, and arrays can change, so they are
references: two of them are equal only when they are the same one, and `a := b`
makes two names for one thing.

**What "sharing is always safe" is worth, concretely.**
[programs/edit.sol](../programs/edit.sol)'s undo keeps the *whole buffer* for
every change — a copy of the array of lines — and the text is never copied at
all, because every line is a string that cannot be changed. Measured: ten
thousand lines of ten characters and ten thousand lines of a *thousand*
characters snapshot in 0.095ms and 0.078ms, which is one measurement twice. The
design an editor in a mutable-string language is pushed towards — recording how
to undo each command — is a second implementation of every command, exercised
only when something has already gone wrong. It did not have to be written here,
and this paragraph of the language is the reason.

Numbers are immutable values. `a := #45` binds the name `a` to the integer 45;
nothing can mutate 45 itself, and rebinding `a` affects only `a`. Mutable state
lives in object *slots* instead, so `p:x_set(#3)` is visible to every name
holding that same object. This split is what lets numbers ride unboxed in
`SolValue` without allocating.

## Syntax

```text
a := #45         ; ':=' binds a name; '#' tags an integer literal
b := 45          ; a bare number is a float
s := "hello"     ; double quotes are strings
p := point:new(#3, #4)
a:print.         ; ':' sends a message; '.' terminates a statement
                 ; ';' starts a comment, running to end of line
@include "lib.sol".   ; '@' marks a directive: compile time, never a message
@expr(a + b / 2)      ; the other one, and the only directive that is a value
```

`:` is the send operator throughout: `object:message`. Parentheses group a
message's parameters, which is why `a := #45` and `a := (#45)` read
consistently.

A method is a name bound on a class, exactly as a variable is a name bound in
the globals -- so it uses the same `:=`, with the same meaning. The right-hand
side is evaluated, and a slot holding a *block* is what makes a method:

```
integer:double := { self:mul(#2) }.           ; `self` is the receiver
integer:poly := { a, b | self:mul(a):add(b) }. ; parameters come before '|'

integer:quadruple := { | d |                  ; a leading '|' declares
    d := self:double.                         ; temporaries instead
    d:double
}.
```

A slot holding anything else is data, evaluated once when bound and simply
answered thereafter:

```
integer:limit := #45:add(#32).
#1:limit:print.        ; #77 -- computed when it was bound
```

Because `:=` evaluates, a method can be computed rather than written out:

```
maker := { { self:mul(#2) } }.
integer:double := maker:value().
```

Only parameters and names declared with `| ... |` are locals. Everything else
is a global, whether it is being read or written:

```
counter := #0.
integer:bump() := (
    counter := counter:add(#1).   ; updates the global everyone can see
    counter
).

integer:quadruple() := (
    | d |                          ; a temporary of this frame
    d := self:double().
    d:double()
).
```

Assignment never declares anything, which is what keeps a method able to update
a global rather than shadowing it with a fresh local. The other half of the
rule lives in the VM: only the script's top level may bring a global into
being, so an undeclared name inside a method or block must already exist. A
typo is then an error rather than a new variable that merely looks like a
local.

Braces make a block -- code as a value:

```
b := { #21:add(#21) }.     ; nothing runs here
b:value():print.           ; #42

true:ifTrue({ #1:print }).                              ; -- control flow is
#5:lessThan(#10):ifElse({ #100:print }, { #200:print }). ; -- ordinary sending

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

A block resolves names the same way: its own declarations, then the enclosing
method's, then the globals. So `{ i := i:add(#1) }` updates the `i` everyone
else can see rather than a private copy that vanishes when the block returns.

### Why binding is syntax and not a message

**The question everyone arrives at**, and it is a fair one. Everything else in
this language is a message, and every message can be overridden — `integer:add
:= { n | #999 }` really does replace addition. `:=` stands outside that. If a
method is *a name bound on a class*, why is the binding itself not
`thing:bind('name, value)`, sent like everything else?

**Because `:=` is not one operation. It is four, and only one of them could be
a message.** What it compiles to depends entirely on what the name turns out to
be:

| What the name is | What it compiles to | Could a method do it? |
| --- | --- | --- |
| a parameter, or a `\| a \|` temporary | `OP_SET_LOCAL slot` | **No** |
| a local of an enclosing frame | `OP_SET_OUTER depth, slot` | **No** |
| anything else — a global | `OP_SET_GLOBAL name` | **Almost** |
| `a:b := c`, a slot on an object | `OP_SET_SLOT name` | **Yes** |

**The locals are structural.** That `slot` is a byte decided while compiling; a
frame is a fixed-size array whose size is written into the chunk header and
which the verifier bounds-checks before the code runs. By the time the program
exists the name is gone — [bytecode.md](BYTECODE.md)'s slot-name table keeps it
only so a debugger can print `average` rather than `slot 3`. There is no
receiver to send to and no name to send. This is not a preference about how
assignment should read; there is nothing there to say it about.

**The global case fails for a subtler reason.** A global *is* an ordinary slot
on an ordinary object, so `a := b` genuinely is `root:bind('a, b)` in every
respect but one: **that object has no name in Solum.** The global `object` is
the root *class*, which is a different object entirely, and the one holding the
globals is not reachable from a program at all:

```
zzz := #42.
object:respondsTo('zzz):print.       ; false
```

So the alternative spelling is not one the language declines to offer. There is
no receiver for it to be sent to.

**And `a:b := c` — the one that could be a message — is compiled as one.** The
parser reads `a:b` as an ordinary send, emits `OP_SEND b`, then sees `:=` and
rewinds its own write cursor over the instruction it just wrote:

```c
if (target_at >= 0 && sol_parser_match(p, TOK_ASSIGN)) {
    c->scope->chunk->count = target_at;      /* unemit the send */
```

That is as close to sugar as anything here gets, and it is the form that makes
`integer:double := { ... }` and `p:x := #3` the same sentence.

#### Why not make that last one a message anyway

Three reasons, and none of them is that `:=` reads better.

**The compiler can see bindings, and that is load-bearing.** Compiling
`lib/text.sol` beside a program that binds the same name produces *'x' was
already bound by lib/text.sol -- this one wins, and nothing else will say so*.
That warning exists only because a binding is a thing the compiler can
recognise. So does deciding at compile time whether a name is a frame slot,
which is what makes locals possible at all; so does knowing whether a block
reaches out of its frame, which decides whether it may outlive it. A binding
that arrived as a send would be invisible to every one of those.

**Overridability is the one property you would not want here.** Overriding `add`
affects programs that add. Overriding `bind` would affect every assignment in
every program, the shipped library included, and it would be reentrant — the
override's own body assigns.

**And it could not be defined.** You would need a binding to bind the name of
the binding method.

**What this costs, stated plainly:** there is no way to bind a computed name.
Reflection reads and never writes (2.10 in [ROADMAP.md](ROADMAP.md)), and the
globals are further out of reach than that entry says — they cannot be read by
computed name either, since the object holding them cannot be named. A program
that wanted either would be an ordinary roadmap entry; none has.

### Literals

| Form      | Type    | Note                                          |
| --------- | ------- | --------------------------------------------- |
| `#45`     | integer | `#` is a type tag, not a literal marker       |
| `45`      | float   | bare numbers are real                         |
| `45.5`    | float   |                                               |
| `1.5e-3`  | float   | exponent optional, sign optional              |
| `"hello"` | string  | scanned; no runtime type yet                  |
| `'foo`    | symbol  | quote prefix, no closing quote, as in Lisp    |

`@include` is not in that table because it is not a literal and not a value.
`@` opens the compiler's own space: what follows it happens while compiling, and
by the time the program runs there is nothing of it left. It is the one thing in
the syntax that is not a message or a value, and the sigil is there so that it
never has to be mistaken for either.

### Grammar

```
program    -> statement* EOF
statement  -> directive | expression '.'?
directive  -> DIRECTIVE STRING '.'?
expression -> IDENT ':=' expression
           |  send ( ':=' expression )?
send       -> primary ( ':' IDENT arguments? )*
arguments  -> '(' ( expression ( ',' expression )* )? ')'
primary    -> IDENT | INT | FLOAT | STRING | group | block | array
group      -> '(' declarations? expression ( '.' expression )* '.'? ')'
block      -> '{' params? declarations?
              ( expression ( '.' expression )* '.'? )? '}'
array      -> '[' ( expression ( ',' expression )* )? ']'
params     -> IDENT ( ',' IDENT )* '|'
declarations -> '|' IDENT ( ',' IDENT )* '|'
```

A send is an assignment target when `:=` follows it. Single pass, so the send
has already been emitted by then -- but a zero-argument send is exactly three
bytes and its receiver is still on the stack beneath it, so rewinding the chunk
to where the send started undoes it precisely. No extra lookahead, and still no
AST.

Block parameters need one small lookahead: `{ a, b | ... }` is a parameter list
while `{ a }` is a body. A `SolLexer` is three pointers, so the compiler copies
it, scans for the closing `|`, and throws the copy away; nothing in the real
token stream moves. That leading `|` is also why parameters could not reuse the
parenthesised form -- `{ (a) }` would be both a one-parameter block and a block
answering `a`.

`.` separates statements rather than terminating them: required between two,
optional after the last, in a script and inside a group or block alike.

Two scanning rules keep this unambiguous:

- `:` followed by `=` is one `:=` token, never a send. This is why message
  selectors must be plain identifiers -- if `=` were a legal selector,
  `a:=(b)` would be both an assignment and a send of `=`. Equality is
  therefore `a:equals(b)`, not `a:=(b)`.
- A `.` only continues a float when a digit follows it, so `45.` is the float
  45 followed by a statement terminator rather than a malformed number.

## Instruction set

A stack machine where nearly everything is `OP_SEND`. The complete reference —
every opcode, its operands, its length and its effect on the stack — is
[BYTECODE.md](BYTECODE.md), which is checked against
`solum/include/solum/bytecode.h` by the test suite rather than kept in step by
hand. A table lived here once and fell six opcodes behind, which is why it does
not any more.

Operand widths follow one rule, and it is about what bounds the number rather
than about the instruction. An index into a side table -- a constant, a name, a
nested method -- is a little-endian u16, because those tables grow with the
program and a long file fills one. A frame slot, a nesting depth, an argument
count is a u8, because those are bounded by the machine instead: a frame of
more than 255 slots is refused before it runs. Jump offsets were u16 from the
start, so sixteen bits is the only width the format has, and `sol_read_u16` is
where it is decoded.

Both side tables intern, so a chunk spends one slot on `print` however often it
is sent, and one on `#1` however often it is written. The loader appends to
both instead, because a file refers to them by position and folding a duplicate
on load would shift every index after it.

`a := #45. a:print.` compiles to roughly:

```
CONST      #45
SET_GLOBAL 'a'       ; assignment is an expression -- value stays on the stack
POP                  ; the statement discards it
GLOBAL     'a'       ; resolve the name -- a lookup, not a send
SEND       'print', 0
POP
HALT
```

Assignment leaving its value on the stack costs nothing and makes
`c := b := #45` fall out for free.

## The .sob file format

The file's tables are little-endian, independent of the host, so a `.sob` file
is portable. `solum/include/solum/serialize.h` carries the byte-level layout.

**The header, written once for the file:**

```
magic     4  "SOLB"
version   2  u16
slots     2  u16, the script frame's slot count (was reserved before v11)
```

**Then a chunk body, which is what recurses:**

```
names     4  u32 count, then each: u16 length + bytes
constants 4  u32 count, then each: u8 tag + payload
             (0 nil, no payload; 1 i64; 2 f64; 3 bool, one byte)
code      4  u32 length, then that many bytes
lines     4  u32 run count, then each: u32 run length + u32 line
files     4  u32 count, then each: u16 length + bytes
fileruns  4  u32 run count, then each: u32 run length + u32 file index
slotnames 2  u16 count, then each: u16 length + bytes
methods   4  u32 count, then each: u16 name length + bytes, u16 arity,
             u16 slot count, u16 flags, then that method's *body*
```

**The header does not recur.** A method carries its own slot count in the four
fields above, so a nested chunk begins at `names` — the magic, the version and
the script's slot count belong to the file and are written once. Reading a
method's chunk as though it were a whole file is the mistake a second
implementation makes first, and
[programs/disasm.sol](../programs/disasm.sol) made it.

`slotnames` is counted by a **u16** where every other table here uses a u32,
which is not a pattern, only what it is.

Flags are `1` for a block and `2` for a block that captures its home frame.
Blocks are compiled exactly like methods, so they share the method table.

A method owns a chunk, so the format nests. Reading is recursive with a depth
cap, and a method's declared frame size is checked against its arity before any
of its code is verified.

**Little-endian means little-endian, as of format 14**, and it did not before.
Until then the tables in this section were little-endian and the two-byte
operands *inside* the code section were big-endian — two conventions arrived at
separately, each internally consistent, and never compared. This page said both
things, a hundred lines apart, and the section a reader of the file format lands
on was the wrong one.

Getting it backwards does not look like a misreading; it looks like data
corruption, every index landing 256 times too large. It cost
[disasm.sol](../programs/disasm.sol) a debugging session, which is what turned
this up.

**The order is written down in one place**, and used to be written down in
thirteen. `SOL_U16_FIRST_SHIFT` and `SOL_U16_SECOND_SHIFT` in `bytecode.h` are
the whole of it; `sol_u16_first`, `sol_u16_second`, `sol_write_u16` and
`sol_read_u16` are derived from them, and every emitter, patcher and reader goes
through those four. Reading had been single-sourced since the beginning and
writing never had — twelve copies of `(v >> 8) & 0xff` across the compiler and
the tests, which is the shape of thing that drifts and the reason the
instruction *lengths* once did. Collapsing them is what made the flip a
two-character edit; `tests/test_bytecode.c` holds the pair to each other, so
changing one and not the other fails the build.

**What the flip cost** was a format version, the code section being stored
verbatim, and a hand edit to the two decoders in
[disasm.sol](../programs/disasm.sol) — a reader written in Solum that nothing
checks against the C. That last one is the interesting one: `make test` would
have stayed green with it reading backwards. What caught it is the thing that
program exists for, disassembling a fresh file and comparing against
`solvm --dump`, which agrees over 5,737 instructions at format 14.

Line numbers are run-length encoded: neighbouring instructions almost always
share a line, so the runs are much smaller than one number per byte. They
expand back into the chunk's parallel array on load.

Floats are stored as IEEE-754 binary64 and come back bit-identical, so a
literal never drifts by being written and read.

### A .sob file is untrusted input

Anything loaded from disk is verified before it can run. The loader reads the
whole file into memory and parses it through a cursor that bounds-checks every
read, rejects a count that could not fit in the bytes remaining (so a corrupt
length cannot become an allocation bomb), and then runs `sol_chunk_verify` over
the code:

- every instruction fits inside the code array,
- every operand indexes a name, constant, or method that exists -- both bytes
  of it, so an index of 256 into a table of one entry is caught rather than
  read as slot 0,
- the opcode is one the VM knows,
- every jump target is the start of an instruction in this chunk,
- the final instruction is `HALT` or `RETURN`,
- and every instruction runs at a height the code agrees on.

The last two are memory-safety requirements, not tidiness. Without the final
`HALT` the dispatch loop would read past the end of the buffer, since that is
the only place the ip can leave the code. And a target landing one byte into a
send would have that send's operands executed as opcodes, which is why the
verifier walks the chunk once to record where each instruction begins before
checking any target against it.

Jumps have since arrived in both directions, forward for the conditionals and
backward to close a loop. The backward one is its own opcode, so the instruction
that can move the ip towards zero stays easy to find, and the check is the same
one: in range, on a boundary.

The last item is the newest, and it is what makes `OP_SEND` checkable at all.
The machine is a stack machine, so every instruction runs at a definite height:
`SEND 'add' (1 args)` always has exactly two values beneath it, whatever the
program computed to get there. `argc` is a byte the *file* supplies, though, and
whether that many arguments are really present depends on that height -- so
nothing structural could tell a real count from a corrupted one. Fuzzing found
the shape it takes: a send claiming 227 arguments on a stack one deep, reading
its receiver from below the frame.

So the verifier computes the height at every instruction, by walking control
flow from the entry and following each branch. The rule that makes it possible
is the JVM's: **the paths into a point must agree.** An instruction reached from
two places at two different heights has no height, and that is what corruption
looks like. The two prerequisites were already in hand, which is why this came
last rather than first -- every opcode's length is known, and every branch
target is already established to be an instruction boundary, so the walk can
only land where an instruction begins.

Code that no path reaches is never given a height, and is not required to have
one: it cannot run. Its operands are still checked by the pass above, and a jump
into it would make it reachable, at which point it is checked like anything
else.

`sol_chunk_save` runs the same verifier before writing, so Solas cannot emit a
file that Solum would refuse.

Compile errors carry a column as well as a line, and print the source line with
the offending token underlined. A token records where it began rather than where
the scanner stopped, which is what places a string that spans lines at its
opening quote. Runtime errors stay at line granularity: a chunk records a line
per byte of bytecode, and a column would be a second table in every `.sob` for a
message printed only when something has already gone wrong.

The height check does not replace the one the send makes at run time. The two
cover different populations: the verifier runs when a `.sob` is loaded, while
Solis runs what it has just compiled without verifying -- deliberately, since
verifying every REPL line to catch the compiler's own bugs is the wrong shape --
and the C API will run any chunk it is handed. One comparison per send is a
cheap floor to keep under all of that.

What verification does *not* promise is termination. A corrupted file can pass
every check and still be a valid program that loops forever -- flipping the `#1`
in `i := i:add(#1)` to `#0` leaves a well-formed chunk whose loop never
advances. That is the VM behaving correctly: a bad program is not a broken VM,
and Solum has no business cutting short a loop a user asked for. Fuzzing bears
this out -- every hang observed came from a corrupted constant or code byte,
none from a name, count, or length the loader parses.

Inlining `whileTrue` made that promise load-bearing rather than incidental: a
crafted file can now spin on a backward jump without so much as a send. It could
already spin through a loop built from sends, and `{ true }:whileTrue({})` is a
legal program, so nothing became reachable that was not reachable before.

## Resolved questions

**What does `integer:new(a)` actually do?** Nothing, in the end -- it refuses,
and the section below on `:=` says why. What the question was really about is
still worth the answer: `integer` is the integer class object, and the comment in
the original notes -- "sends message integer to top Object" -- is loose wording.
Nothing sends `integer` anywhere.

Resolving the *name* `integer` is a separate step, and it is a lookup rather
than a send: the compiler emits `OP_GLOBAL 'integer'`, which finds the class
object in the root Object's slots. This is the Smalltalk arrangement, where
`Integer` is a global you look up and `Integer new` is the message send. Keeping
the two distinct means `OP_SEND` never has to special-case a receiver that does
not exist yet.

**How do variables work?** A name is a binding, not an object. `:=` binds:

```
a := #45.                 ; bind a to the integer 45
p := point:new(#3, #4).   ; bind p to a fresh point
q := p.                   ; q and p name the same object
q:x_set(#7).              ; mutation is visible through p too
```

This replaces the original `integer:new(a)` form, which had to pass the *name*
`a` into `new` before `a` existed -- that would have needed symbol literals or
an evaluation-order special case in the compiler. With `:=`, `new` is an
ordinary message returning an ordinary object, and binding is a separate
bytecode instruction.

`integer:new(#45)` survived for a while as an explicit long form of `a := #45`,
and it is gone: it constructed nothing, being the identity function with a type
check, and a number is written rather than made. `new` is now the construction
protocol and nothing else -- `object` and `array`, the two classes whose
instances are references, so that there is a fresh distinct one to hand back.
The other six refuse and say what to write. See
[class-and-instance.md](class-and-instance.md#new-used-to-mean-three-things).

Numbers being immutable is what makes this coherent: with mutable integers,
`b := a` would have to choose between copying the box and sharing it, and both
answers surprise someone.

**Is arithmetic strict, and what happens on overflow?** Strict, both ways.
`#45` and `45` are different types and never coerce, so `#45:add(1.5)` is an
error rather than a quiet promotion. Integers are signed 64-bit and *trap* on
overflow rather than wrapping -- `__builtin_add_overflow` is one instruction
plus a predictable branch, so strictness costs close to nothing and a silent
wrong answer becomes a reportable error. Wrapping stays available later as an
explicit `a:wrapAdd(b)` if it is ever wanted.

**Does the `.` terminator survive the float ambiguity?** Yes. `.` has exactly
one competing use -- the decimal point -- because sends use `:` rather than dot
chaining. One character of lookahead settles it: a `.` continues a number only
when a digit follows. That is a single `if` in the scanner, and it is what
every C-family lexer already does.

**How is a method defined?** With `:=`, and it is genuinely the same operator
as everywhere else -- the right-hand side is evaluated and bound:

```
integer:double := { self:mul(#2) }.
```

There is no method-definition form in the grammar. A slot holds a value; a slot
holding a block is a method, and sending its name runs the block with the
receiver as `self`. Sending the name of a slot holding anything else answers
that value. Methods and data slots stop being different kinds of thing.

An earlier design did have a definition form, `integer:double() := self:mul(#2)`,
where the right-hand side was compiled rather than evaluated. It read well but
made `:=` mean two different things depending on what stood to its left, and it
put a shape the compiler had to pattern-match into the grammar. Evaluating the
right-hand side removes the special case and buys metaprogramming: a method can
be *computed*, because by the time it is bound it is only a value.

A call pushes a frame whose `slots` point into the value stack at the receiver,
so `slots[0]` is `self` and `slots[1..arity]` are the arguments -- the caller
has already laid them out that way, and nothing is copied to make the call. The
compiler decides the frame size and records it as `slot_count`; the VM reserves
that much and fills the extra with nil.

**The script's frame is one of them.** It used to be the exception -- no method,
so nothing reserved it any slots -- which is why a temporary declared at the top
level had to be refused: there was nowhere to put it. `SolChunk` carries a slot
count of its own now and `sol_vm_run` reserves it the same way, so the top level
is a frame like every other. Slot 0 is unnameable in both: the receiver in a
block, and nothing at all in a script, which has none.

**How does control flow work?** By sending messages, with no control-flow
syntax at all. `{ ... }` makes a block -- unevaluated code packaged as a value
-- and `ifTrue`, `ifElse`, and `whileTrue` are ordinary primitives that decide
whether and how often to run one. A user can add control structures the same
way, and they cost exactly what the built-in ones cost.

This needs the interpreter to be re-entrant: a primitive invokes a block
through `sol_vm_call_block`, which pushes a frame and runs until it returns.
`whileTrue` is then just a C loop calling two blocks.

The compiler has since learned six of those selectors after all -- `ifTrue`,
`ifFalse`, `ifElse`, `whileTrue`, `and`, and `or` -- and emits jumps when it
sees one written literally with plain blocks (4.1). That is an
optimisation layered on top rather than a change of model: the primitives are
still there, still what a `perform` or a block held in a variable reaches, and
the compiler falls back to the send whenever inlining would alter what the
program means. A user's own control structure is a send, as it was.

**What does a block capture?** The frame it was written in, lexically. Each
frame records the frame it was written inside, by index and by id, and
`OP_OUTER` carries a depth saying how many steps out along that chain to walk.
Blocks nested in blocks therefore chain one frame at a time rather than all
sharing one, which is what lets a name several blocks out stay reachable.

`self` is handled differently, and deliberately. It is not resolved lexically at
compile time, because which block ends up invoked as a method is not knowable
there -- one block can build another and a third can bind it to a slot. Instead
`self` compiles to slot 0 of the frame being entered, the VM captures the
current receiver into a block when the block is created, and a send to a slot
holding that block overrides slot 0 with its own receiver. Lexical either way,
but decided where the answer is actually known.

A block may outlive the frame it captured. Rather than promote captured
variables to the heap, Solum takes two cheaper measures:

- The compiler works out whether a block actually reads or writes its home
  frame (`touches_home`, which also accounts for blocks nested inside it). One
  that does not is independent of the frame and may escape freely -- which
  covers `{ #42 }` and most conditional branches.
- A capturing block records its home frame's index *and* a frame id unique for
  the life of the VM. Calling it checks the frame is still the one it captured,
  so an escaped block is reported rather than reading slots that now belong to
  someone else.

Real closures would need the captured slots moved to the heap when a frame
dies. That is the upgrade path; the id check is what makes the current
restriction safe rather than silently wrong.

## Strings

Immutable, and therefore values rather than references: `equals` compares
characters, the way it does for numbers, where an array compares identity.
Nothing can mutate a string, so sharing one is always safe.

A literal needs no constant tag in `.sob`. Its bytes live in the chunk's interned
text table beside selectors and global names, and `OP_STRING` builds a string
from them at run time -- which is also why the compiler can emit one without
having a VM to allocate in. A literal whose bytes match a selector shares one
entry with it, harmlessly.

Building the string at run time rather than caching it means a literal in a loop
allocates once per pass. Immutability makes that purely a cost; interning would
remove it, but wants a weak table so interned strings can still die. Selector
dispatch no longer waits on this -- it has a table of its own, below.

There are no escape sequences yet, so a string cannot contain a `"`. A literal
newline between the quotes does work, since the scanner counts lines as it goes.

## Garbage collection

Mark-sweep, non-moving, stop-the-world. The heap holds three types: a
`SolObject`, which owns its slot chain; a `SolBlock`; and a `SolCode`, a compiled
chunk tree.

Code ownership is dual, because Solas has no VM to own a chunk on its behalf. A
chunk created by `sol_chunk_init` is caller-owned and freed by hand, as Solas and
the tests do. One created by `sol_code_new` belongs to a `SolCode` cell that the
collector sweeps once nothing refers to it, which is how Solis compiles a chunk
per input line without accumulating them. `sol_chunk_add_method` propagates
ownership as each subtree is added, so a caller cannot forget to.

Both heap types begin with a `SolGCHeader`, so one list threads the whole heap
and one sweep loop walks it. A new heap type joins by embedding the header and
adding a case to the tracer and the freer, rather than by adding another list.

The object graph is these edges:

```
SolObject.proto          -> SolObject
SolObject.slots[].value  -> SolValue
SolBlock.self            -> SolValue
SolBlock.owner           -> SolCode      (the tree its code lives in)
SolCode  constants       -> SolValue     (once strings can be constants)
```

A block caches its owning cell rather than reading it back through
`block->code->chunk`. A caller-owned chunk can be freed while blocks pointing
into it are still on the heap -- calling such a block was always wrong, but the
tracer must not fault merely for walking past one.

Roots are cheap here because of two properties of the interpreter. Frame locals
live *inside* the value stack -- `push_frame` sets `slots = stack_top - argc - 1`
and fills the rest by pushing -- so scanning the stack covers every local of
every frame with no separate frame walk. And a primitive's arguments are still on
the stack while it runs, since the dispatch loop drops them only after it
returns. That leaves the value stack, the chunk each active frame is executing,
`vm->root`, the built-in classes, and the temporary-root stack.

Marking uses an explicit worklist rather than recursion, so a graph deeper than
the C stack traces without overflowing it -- a 200,000-link proto chain is a
test, not a hypothetical.

Collection happens *before* an allocation, never after, so the new cell -- which
nothing points at yet -- cannot be swept. Two consequences worth knowing:

- `sol_vm_init` must null `vm->root` and the class fields before the first
  allocation, or a collection during setup would trace uninitialised pointers.
- Today the only allocation reachable from running code is `sol_block_new` at
  `OP_BLOCK`, where everything live is already on the stack or in globals, so no
  temporary-root machinery is needed. That changes with strings.

Setting `SOLUM_GC_STRESS=1` collects on every allocation. Running the test suite
under it is what actually finds a missing root.

## Limits

A host may say what a program is allowed to spend before it starts it:

```c
SolVM vm;
sol_vm_init(&vm);
sol_vm_set_step_limit(&vm, 10000000);      /* instructions */
sol_vm_set_memory_limit(&vm, 64 * 1024 * 1024);   /* live bytes */

if (sol_vm_run(&vm, &chunk) == SOL_STOPPED) {
    /* it neither finished nor asked to stop */
}
```

[embedding.md](embedding.md) is the contract a host works to,
[solum/embed.h](../solum/include/solum/embed.h) is the whole supported surface,
and [embed/host.c](../embed/host.c) is one that works.

Zero is no limit and is the default, which is right for a person at a terminal:
they have a ctrl-c, and a budget chosen in advance by somebody who did not know
what the program would do is worse than no budget at all. It is the *embedded*
case that wants them -- a program running scripts on behalf of somebody else,
where starting one must not mean lending it the thread and the heap for as long
as it cares to keep them.

Neither limit is reachable from inside the language. There is no message that
sets, clears or reads one, which is the whole of what makes them limits.

**Steps are counted in the dispatch loop**, and it has to be there. The obvious
cheaper place is the debug hook, which already exists and can already stop a
running program -- Solid quits out of one that way. But the hook is offered when
the line or the frame changes, and a loop written literally compiles to jumps:
it enters no frame and returns to no caller, so neither moves. Measured, with a
breakpoint on the loop:

| loop | iterations | times the hook was offered a stop |
| --- | --- | --- |
| `{ ... }:whileTrue({ ... })`, one line | 3,000,000 | 1 |
| `[#1,#5]:loop(step)` | 5 | 5 |

The inlined loop is offered once and then runs to completion. It is the same
inlining that makes `--trace` quiet on a long loop, seen from the other side:
what makes the trace bearable makes the program unstoppable. A loop cannot hide
from an instruction count the way it hides from a line number.

**What a step does not measure is work**, and the distinction is worth having
straight before relying on either limit. An instruction is a unit of dispatch.
A primitive that reads a file or scans a string does all of it between one step
and the next, so `system:readFile` of 256MB and an `indexOf` over the whole of
it is eight instructions -- the same eight as for 64MB, since the count does not
follow the size. What the limits bound is a program that loops, which is what
they were built for, and not the cost of one message. See
[3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work).

The counter is a post-decrement and a compare, and there is no branch asking
whether a limit was set: with none, `steps_remaining` starts at `UINT64_MAX`, so
the unlimited case runs the same two instructions and reaches zero five hundred
years from now.

Measured on a five-million-turn inlined loop, which is around twenty million
instructions: 0.74-0.75s with the counter and 0.76-1.04s without it. That is not
a speed-up, it is the measurement saying the cost is below its own noise -- but
it does put a ceiling on it, which is what the number was wanted for.

A step is a unit of work rather than of time, deliberately. It does not vary
with the machine, its load, or what else is running, so a limit chosen once
means the same thing everywhere -- which a wall-clock timeout does not.

**Memory is measured after a collection**, in `sol_gc_maybe_collect`, and this is
the whole difficulty of a memory limit. `bytes_allocated` before a sweep counts
everything the program has ever asked for and not yet had taken back, most of
which may be unreachable; a ceiling read off that figure stops a program for
litter rather than for what it is holding, and a loop building one small string
at a time would trip it however small the strings were. After a sweep the figure
is what is live. So going over is a reason to collect, and being over once that
has happened is a reason to stop.

The allocation that crossed the line still completes -- its caller needs
somewhere to put a half-built object -- and the program unwinds at the next
instruction boundary.

So the overshoot is bounded in *time* and not in *size*. One instruction is one
allocation, and one allocation is however large the thing being allocated is:
under a 1MB ceiling, reading a 256MB file succeeds and the program is stopped at
the next instruction holding 268,450,673 live bytes. The ceiling is a ceiling on
carrying on, not on going over.

**A stop is not catchable, and that is not an oversight.** `sol_vm_stop` sets
`stopped` alongside `had_error`, so it unwinds through every loop that already
tests that flag, and both `onError` and `ensure` let it past untouched. A
handler is code; running a handler is spending the allowance that just ran out;
and a handler wrapped around everything -- which is the shape people write --
would turn the limit into a suggestion. `ensure` is the sharper case, because it
works by setting the failure aside precisely so that more code may run, and a
program could otherwise put its work in a cleanup and carry on.

What that costs is small in this language, because nothing has to be released: a
file is read or written whole, and no message hands back anything a program is
obliged to close. It would cost more in a language where there were.

**An extension is where there are, and the design answers it rather than
falsifying it.** A socket or a window handed back by
[an extension](extensions.md) is a resource with a release, which is the first
thing here that has one. But it is still not something a *program* is obliged to
close: there is no `close` message, and the collector gives it back when the
program lets go — or `sol_vm_free` does, for whatever is still held when the
machine goes down. So a stopped program's sockets are closed **because** the
cleanup was never the program's to run, which is the same reason the paragraph
above gives for the cost being small. Had an explicit `close` been the mechanism,
an uncatchable stop would have leaked one every time.

The allowance is reset by `sol_vm_run`, so it is per run and not per VM: a
server handing one machine a request and then another means each of them to have
the whole of it.

**What this is not.** It bounds a program's work and its footprint. It does not
bound what it reaches for -- a stopped program may already have deleted the
files it was going to delete -- and it is not a sandbox. That half is
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine),
which is still a decision rather than a mechanism.

## Open questions

[REFERENCE.md](REFERENCE.md) describes the language as it is; this document is
about why. Everything unresolved lives in [ROADMAP.md](ROADMAP.md) -- the open design
questions, the known limitations, and the work that has not been done. It is kept
as one list rather than split across documents so it cannot drift.

## Status

**0.35.0.** The language is Turing-complete, does not leak, and is what a
program gets written in rather than a slice being demonstrated.

```
$ solas report.sol && solvm report.sob
```

Implemented: the scanner, the single-pass compiler, the re-entrant dispatch loop
with call frames, methods and locals, blocks with lexical capture and
parameters, message-based control flow with the common forms inlined to jumps,
the `.sob` format with its verifier, and every built-in type the language
has -- `integer`, `float`, `boolean`, `nil`, `block`, `string`, `symbol`,
`array`, `dict`, `time`, `error` and `object`, each delegating to a single root.

The heap is collected by mark-sweep over objects, blocks and compiled code, so a
block literal in a loop does not accumulate and Solis retains nothing between
lines. A program reaches the world outside it: arguments, standard input, files,
directories, the clock, another program, and a status to stop with. It can be
traced (`solvm --trace`), stepped (`bin/solid`), and bounded (`--steps`,
`--memory`).

What is deliberately not there is in
[ROADMAP.md](ROADMAP.md#3-known-limitations), and it is short: a capturing block
cannot outlive its frame, there is no non-local return, recursion reaches 254
levels, text is bytes, and a `.sob` from an older format is refused rather than
read hopefully. One decision is open -- whether a script can be run with less
than the whole machine -- and it is a decision rather than work waiting.
