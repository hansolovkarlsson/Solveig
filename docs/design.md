# Solum -- design notes

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

Methods are defined with the same `:=`, because a method is a name bound on a
class exactly as a variable is a name bound in the globals:

```
integer:double() := self:mul(#2).      ; `self` is the receiver
integer:poly(a, b) := self:mul(a):add(b).   ; parameters become locals

integer:quadruple() := (               ; parens may hold several statements;
    d := self:double().                ; the last one is the result
    d:double()
).
```

Inside a method, assigning to a new name declares a local; reading a name that
is not a local falls back to the globals, so a method can still see `integer`.
At the top level there are no locals and every name is a global.

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
           |  send
send       -> primary ( ':' IDENT arguments? )*
arguments  -> '(' ( expression ( ',' expression )* )? ')'
primary    -> IDENT | INT | FLOAT | STRING | group
group      -> '(' expression ( '.' expression )* '.'? ')'

definition -> IDENT ':' IDENT '(' params? ')' ':=' expression
params     -> IDENT ( ',' IDENT )*
```

A definition and a send start identically, and telling them apart needs more
lookahead than the parser carries. A `SolLexer` is three pointers, so the
compiler copies it and scans ahead for the `IDENT ':' IDENT '(' ... ')' ':='`
shape, then throws the copy away; nothing in the real token stream moves.

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
| `OP_DEF_METHOD` | u8 method, u8 name | bind a method on the object on top of stack |
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
             u16 slot count, then that method's chunk, recursively
```

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

**How is a method defined?** With `:=`, the same operator that binds a name:

```
integer:double() := self:mul(#2).
```

A method is a name bound on a class, exactly as a variable is a name bound in
the globals, so this needed no new keyword and no new operator. The target is
an ordinary expression, evaluated and left on the stack for `OP_DEF_METHOD`.

The body compiles into a chunk of its own, which the enclosing chunk owns. A
call pushes a frame whose `slots` point into the value stack at the receiver,
so `slots[0]` is `self` and `slots[1..arity]` are the arguments -- the caller
has already laid them out that way, and nothing is copied to make the call. The
compiler decides the frame size and records it as the method's `slot_count`;
the VM reserves that much and fills the extra with nil.

## Open questions

- **Statement terminator.** Only the last line of the example ends in `.`. Is
  `.` a terminator that the earlier lines informally omit, or a separator in the
  Smalltalk sense? The parser currently treats it as optional, which accepts
  both, but that means it cannot catch a missing one.
- **Strings and symbols have no runtime type.** Both scan to tokens, and the
  compiler rejects them with a clear message. Strings need a heap object, which
  is the first thing that will make the collector matter.
- **Class side vs instance side share one object.** `integer` holds both `new`
  and `print`, so `#45:new(#1)` resolves as readily as `integer:new(#1)`.
  Separating them needs a metaclass level.
- **Nothing creates a new class.** Methods can now be defined on the built-in
  classes, but there is no way to make a class of your own, so user-defined
  objects with their own slots are still out of reach.
- **No conditionals, so no recursion that terminates.** A method can call
  itself, but nothing can stop it -- `integer:loop() := self:loop()` runs to the
  frame cap. This is the most pressing gap, and it is the one blocks were
  invented for: in Smalltalk `ifTrue:` is an ordinary message taking a block.
  Built-in keywords are the alternative, at the cost of "everything is a
  message".
- **Methods are owned by the chunk that compiled them.** A class holds only a
  pointer, so freeing a chunk would leave its methods dangling. Solis therefore
  keeps every line's chunk alive for the whole session. The real fix is for the
  collector to own methods.
- **Solis is line-at-a-time**, so a method body spanning several lines has to
  go in a file. Fixing this means the REPL buffering until the parens balance.
- **Division.** Deliberately absent so far: integer division has to choose
  between truncating, flooring, and returning a float, and that choice is
  awkward under strict typing.
- **Blocks and methods in the language itself.** `OP_RETURN` and call frames are
  reserved for this, but nothing defines a method in Solum source yet -- every
  method is currently a C primitive.
- **Garbage collection.** Objects are threaded onto `vm->objects` at allocation
  and freed en masse at shutdown. That list is there so a mark-sweep collector
  can be dropped in without changing the allocator.
- **256-constant limit.** `OP_SEND` and `OP_CONST` carry a one-byte index. A
  `CONST_LONG`-style variant is the fix when a real program hits it.

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

Methods defined in Solum source work too, in the REPL and through a file:

```
> integer:double() := self:mul(#2).
> #21:double():print.
#42
```

Implemented: the scanner, the single-pass compiler, the dispatch loop with call
frames, methods and locals, the `.sob` format with its verifier, and built-in
`integer` and `float` classes with `new`, `print`, `add`, `sub`, `mul`. Not
implemented: conditionals and blocks, user-defined classes, strings, symbols,
and the collector.
