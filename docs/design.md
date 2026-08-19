# Solveig -- design notes

## Original notes

The whole project started from this sketch (`notes.txt`, kept verbatim):

```
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

## The three parts

| Part      | Binary      | Job                                          |
| --------- | ----------- | -------------------------------------------- |
| **Solas** | `bin/solas` | Compiler: `.sol` source -> bytecode          |
| **Solum** | `bin/solum` | Virtual machine: loads and executes bytecode |
| **Solis** | `bin/solis` | REPL: compiles and runs a line at a time     |

Solas and Solum meet at exactly one place: `solum/include/solum/bytecode.h`.
That header defines the opcodes, so a change to the instruction set is a change
to one file that both halves already include. Solis links both libraries and
skips serialisation entirely -- it compiles straight into a `SolChunk` and hands
it to the VM.

## The name

**Solveig** is the language; **Solas**, **Solum**, and **Solis** are the programs
that compile, run, and explore it. Old Norse *Sólveig*, from *sól* "sun" and
*veig*, usually read as "strength". See the README for the longer note.

Where these documents say "Solveig" they mean the language; "Solum" always means
the virtual machine.

## Design principles

Not laid down in advance -- these are what the decisions so far have in common,
written down because they keep settling the next question.

**Two spellings of the same thing mean the same thing.** `[#1, #2]` and
`array:of(#1, #2)` produce identical bytecode; `a := #45` and
`a := integer:new(#45)` produce the same integer. Where a shorthand exists it is
notation, never a second semantics. The syntax is already a lot to take on, so a
reader should never have to ask which of two forms they are looking at in order
to know what it does.

**One operator, one meaning.** `:=` binds a name to an evaluated value, whether
the name is a global, a temporary, or a slot on a class. An earlier design had it
mean something different on the left of a method definition, and removing that
special case took a hundred lines of compiler with it.

**Strict rather than convenient.** Integers and floats never coerce, integer
overflow traps instead of wrapping, an undeclared name inside a method is an
error rather than a new variable, and an out-of-range index will be an error
rather than nil. A wrong program should stop, not continue quietly.

## Object model

Smalltalk lineage, prototype flavour:

- An object is a set of named slots plus a `proto` pointer it delegates to.
- A class is not a separate kind of thing -- it is an object like any other.
  `integer` is the integer class object; `integer:new(a)` sends `new` to it and
  gets back an instance that delegates to it.
- Message send is the only way to make anything happen. `:` is the send
  operator: `receiver:message(args)`.
- Slot lookup walks the proto chain and terminates at the root Object, which
  doubles as the globals namespace where class objects like `integer` live.

Numbers are immutable values. `a := #45` binds the name `a` to the integer 45;
nothing can mutate 45 itself, and rebinding `a` affects only `a`. Mutable state
lives in object *slots* instead, so `p:x_set(#3)` is visible to every name
holding that same object. This split is what lets numbers ride unboxed in
`SolValue` without allocating.

## Syntax

```
a := #45         ; ':=' binds a name; '#' tags an integer literal
b := 45          ; a bare number is a float
s := "hello"     ; double quotes are strings
p := point:new(#3, #4)
a:print.         ; ':' sends a message; '.' terminates a statement
                 ; ';' starts a comment, running to end of line
```

`:` is the send operator throughout: `object:message`. Parentheses group a
message's parameters, which is why `a := #45`, `a := (#45)` and
`a := integer:new(#45)` all read consistently.

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
#1:limit:print.        ; #77, computed when it was bound
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

true:ifTrue({ #1:print }).                              ; control flow is
#5:lessThan(#10):ifElse({ #100:print }, { #200:print }). ; ordinary sending

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

A block resolves names the same way: its own declarations, then the enclosing
method's, then the globals. So `{ i := i:add(#1) }` updates the `i` everyone
else can see rather than a private copy that vanishes when the block returns.

### Literals

| Form      | Type    | Note                                          |
| --------- | ------- | --------------------------------------------- |
| `#45`     | integer | `#` is a type tag, not a literal marker       |
| `45`      | float   | bare numbers are real                         |
| `45.5`    | float   |                                               |
| `"hello"` | string  | scanned; no runtime type yet                  |
| `'foo`    | symbol  | quote prefix, no closing quote, as in Lisp    |

### Grammar

```
program    -> statement* EOF
statement  -> expression '.'?
expression -> IDENT ':=' expression
           |  send ( ':=' expression )?
send       -> primary ( ':' IDENT arguments? )*
arguments  -> '(' ( expression ( ',' expression )* )? ')'
primary    -> IDENT | INT | FLOAT | STRING | group | block
group      -> '(' declarations? expression ( '.' expression )* '.'? ')'
block      -> '{' params? declarations?
              ( expression ( '.' expression )* '.'? )? '}'
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

Two scanning rules keep this unambiguous:

- `:` followed by `=` is one `:=` token, never a send. This is why message
  selectors must be plain identifiers -- if `=` were a legal selector,
  `a:=(b)` would be both an assignment and a send of `=`. Equality is
  therefore `a:equals(b)`, not `a:=(b)`.
- A `.` only continues a float when a digit follows it, so `45.` is the float
  45 followed by a statement terminator rather than a malformed number.

## Instruction set

A stack machine where nearly everything is `OP_SEND`.

| Opcode      | Operands               | Effect                                      |
| ----------- | ---------------------- | ------------------------------------------- |
| `OP_CONST`  | u8 const index         | push `constants[idx]`                       |
| `OP_NIL`    | --                     | push nil                                    |
| `OP_GLOBAL` | u8 name index          | push the named global                       |
| `OP_SET_GLOBAL` | u8 name index      | bind the name, leave the value on the stack |
| `OP_LOCAL`  | u8 slot                | push a frame slot (slot 0 is `self`)        |
| `OP_SET_LOCAL` | u8 slot             | store into a slot, leaving the value        |
| `OP_OUTER`  | u8 depth, u8 slot      | read a slot `depth` frames out              |
| `OP_SET_OUTER` | u8 depth, u8 slot   | write one, leaving the value                |
| `OP_BLOCK`  | u8 method index        | make a block capturing the current frame    |
| `OP_SET_SLOT` | u8 name index        | pop a value and an object, bind, answer it  |
| `OP_SEND`   | u8 name index, u8 argc | pop argc args + receiver, push the reply    |
| `OP_POP`    | --                     | discard top of stack (statement boundary)   |
| `OP_RETURN` | --                     | return top of stack from the current method |
| `OP_HALT`   | --                     | stop the VM                                 |

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

Little-endian throughout, independent of the host, so a `.sob` file is
portable. `solum/include/solum/serialize.h` carries the byte-level layout.

```
magic     4  "SOLB"
version   2  u16
reserved  2  u16, must be zero
names     4  u32 count, then each: u16 length + bytes
constants 4  u32 count, then each: u8 tag + payload (0 nil, 1 i64, 2 f64)
code      4  u32 length, then that many bytes
lines     4  u32 run count, then each: u32 run length + u32 line
methods   4  u32 count, then each: u16 name length + bytes, u16 arity,
             u16 slot count, u16 flags, then that method's chunk, recursively
```

Flags are `1` for a block and `2` for a block that captures its home frame.
Blocks are compiled exactly like methods, so they share the method table.

A method owns a chunk, so the format nests. Reading is recursive with a depth
cap, and a method's declared frame size is checked against its arity before any
of its code is verified.

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
- every operand indexes a name or constant that exists,
- the opcode is one the VM knows,
- the final instruction is `HALT` or `RETURN`.

That last rule is a memory-safety requirement, not tidiness: execution is
linear, so without it the dispatch loop would read past the end of the buffer.
When jumps arrive it has to become a check that every target lands on an
instruction boundary.

`sol_chunk_save` runs the same verifier before writing, so Solas cannot emit a
file that Solum would refuse.

What verification does *not* promise is termination. A corrupted file can pass
every check and still be a valid program that loops forever -- flipping the `#1`
in `i := i:add(#1)` to `#0` leaves a well-formed chunk whose loop never
advances. That is the VM behaving correctly: a bad program is not a broken VM,
and Solum has no business cutting short a loop a user asked for. Fuzzing bears
this out -- every hang observed came from a corrupted constant or code byte,
none from a name, count, or length the loader parses.

## Resolved questions

**What does `integer:new(a)` actually do?** `integer` is the integer class
object, and `new` is sent to it to create an instance. The comment in the
original notes -- "sends message integer to top Object" -- is loose wording;
nothing sends `integer` anywhere.

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
bytecode instruction. `a := integer:new(#45)` still works as the explicit long
form of `a := #45`; the literal is sugar for the built-in case, and `new` stays
the general construction protocol for user-defined classes.

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

**How does control flow work?** By sending messages, with no control-flow
syntax at all. `{ ... }` makes a block -- unevaluated code packaged as a value
-- and `ifTrue`, `ifElse`, and `whileTrue` are ordinary primitives that decide
whether and how often to run one. Nothing in the compiler knows those
selectors, so a user can add control structures the same way.

This needs the interpreter to be re-entrant: a primitive invokes a block
through `sol_vm_call_block`, which pushes a frame and runs until it returns.
`whileTrue` is then just a C loop calling two blocks.

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
variables to the heap, Solveig takes two cheaper measures:

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

## Open questions

Everything unresolved lives in [ROADMAP.md](ROADMAP.md) -- the open design
questions, the known limitations, and the work that has not been done. It is kept
as one list rather than split across documents so it cannot drift.

## Status

The vertical slice runs. `bin/solis` compiles and executes a line at a time:

```
> a := #45.
> a:add(#5):print.
#50
> a:print.
#45
```

The full pipeline also runs, compiling to a file and executing it separately:

```
$ ./bin/solas examples/hello.sol     # writes examples/hello.sob
$ ./bin/solum examples/hello.sob
#45
```

Methods defined in Solveig source work too, in the REPL and through a file:

```
> integer:double := { self:mul(#2) }.
> #21:double:print.
#42
```

Blocks make the language Turing-complete:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul( self:sub(#1):factorial ) })
}.
#20:factorial:print.      ; #2432902008176640000
```

Implemented: the scanner, the single-pass compiler, the re-entrant dispatch
loop with call frames, methods and locals, blocks with lexical capture, the
`.sob` format with its verifier, and built-in `integer`, `float`, `boolean`,
`nil`, and `block` classes. Not implemented: user-defined classes, strings,
symbols, and user-defined classes. The heap is collected: a mark-sweep collector
reclaims objects and blocks, so a block literal in a loop no longer accumulates.
Compiled code is collected too, so Solis retains nothing between lines.
