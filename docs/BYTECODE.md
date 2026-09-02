# The instruction set

**Writing something that emits this?** [PRODUCING.md](PRODUCING.md) has the
rules a grammar cannot carry, the limits a chunk has, and what the verifier
checks — the things `solas` enforces that are not on this page or in the
grammar.

Every opcode SolVM executes, what it takes, and what it does to the stack.

The definitive copy is [`solum/include/solum/bytecode.h`](../solum/include/solum/bytecode.h),
which is the contract between the two halves of the system: Solas includes it to
emit, Solum includes it to execute. **This page is checked against that header by
`tests/test_bytecode.c`** — an opcode added there and not described here fails
the test suite, and so does the reverse. Instruction lengths are checked too,
against `sol_op_length`, which is the one place they are written down.

For the file format the instructions arrive in, see
[design.md](design.md#the-sob-file-format).

---

## The shape of the machine

A stack machine where nearly everything is a message send. `OP_SEND` pops `argc`
arguments plus a receiver and pushes the reply, and that covers arithmetic,
comparison, printing, and every method a program defines. Resolving a name is
the one exception: `OP_GLOBAL` is a lookup, not a send.

There is no instruction for arithmetic, no instruction for a conditional as
such, and no instruction that knows what a class is.

**Operand widths follow one rule**, and it is about what bounds the number
rather than about the instruction:

- An index into a side table — a constant, a name, a nested method — is a
  **little-endian u16**, because those tables grow with the program and a long file
  can fill one.
- A frame slot, a nesting depth, an argument count is a **u8**, because those are
  bounded by the machine instead: a frame of more than 255 slots is refused
  before it runs.

Jump offsets were u16 from the start, so sixteen bits is the only width the
format has, and `sol_read_u16` is where it is decoded.

---

## Every instruction

`Byte` is the value the opcode is, which is what a reader of a `.sob` file
needs and what this page did not carry until
[programs/disasm.sol](../programs/disasm.sol) tried to disassemble one from it
and could not decode a single instruction. The numbers are the order of the enum
in `bytecode.h`, and `tests/test_bytecode.c` now checks each one against it —
so an opcode inserted in the middle, which renumbers everything after it, fails
the suite rather than silently making this page wrong.

They are grouped below by what they do rather than by number, so the column is
not in order. `Bytes` is the whole instruction including its opcode. `Stack`
reads *before* → *after*, with the top of the stack on the right.

### Pushing values

| Byte | Opcode | Operands | Bytes | Stack | Effect |
| --- | --- | --- | --- | --- | --- |
| **0** | `OP_CONST` | u16 const index | 3 | → v | Push `constants[idx]`. |
| **1** | `OP_NIL` | — | 1 | → nil | Push nil. |
| **9** | `OP_STRING` | u16 name index | 3 | → s | Build a string from that interned text. A literal's bytes ride in the chunk's text table beside selectors and global names; a `SolString` needs a VM to allocate it, and the compiler has none. |
| **10** | `OP_SYMBOL` | u16 name index | 3 | → 'y | Intern that text as a symbol. |
| **8** | `OP_BLOCK` | u16 method index | 3 | → b | Make a block over `methods[idx]`, capturing the current frame as its home. |

### Names and slots

| Byte | Opcode | Operands | Bytes | Stack | Effect |
| --- | --- | --- | --- | --- | --- |
| **2** | `OP_GLOBAL` | u16 name index | 3 | → v | Push the named global. A lookup, not a send. |
| **3** | `OP_SET_GLOBAL` | u16 name index | 3 | v → v | Bind the name, **leaving the value**. |
| **4** | `OP_LOCAL` | u8 slot | 2 | → v | Push a frame slot. Slot 0 is `self` in a block and unused in a script, which has no receiver; 1..arity are the arguments. |
| **5** | `OP_SET_LOCAL` | u8 slot | 2 | v → v | Store into a slot, leaving the value. |
| **6** | `OP_OUTER` | u8 depth, u8 slot | 3 | → v | Read a slot `depth` frames out along the **lexical** chain. |
| **7** | `OP_SET_OUTER` | u8 depth, u8 slot | 3 | v → v | Write one, leaving the value. |
| **12** | `OP_SET_SLOT` | u16 name index | 3 | o v → v | Pop a value and an object, bind the name on the object, leave the value. |

Every one of the four assignments leaves its value on the stack. That costs
nothing and makes `c := b := #45` fall out for free — the statement that follows
discards it with `OP_POP`.

### Sending

| Byte | Opcode | Operands | Bytes | Stack | Effect |
| --- | --- | --- | --- | --- | --- |
| **11** | `OP_SEND` | u16 name index, u8 argc | 4 | r a₁..aₙ → v | Pop `argc` arguments and a receiver, send, push the reply. |

The receiver and its arguments are already laid out contiguously, so the callee's
frame points straight at them: slot 0 is the receiver, and no copying is needed
to make the call.

### Jumps

The compiler emits these only for control flow written literally with plain
blocks — `ifTrue`, `ifFalse`, `ifElse`, `whileTrue`, `and`, `or`. Written any
other way, those are ordinary sends and none of these instructions appears.

| Byte | Opcode | Operands | Bytes | Stack | Effect |
| --- | --- | --- | --- | --- | --- |
| **13** | `OP_JUMP` | u16 offset | 3 | — | Skip forward that many bytes. |
| **14** | `OP_JUMP_IF_FALSE` | u16 offset, u16 name index | 5 | b → | Pop a boolean and skip forward when it is false. |
| **15** | `OP_EXIT_IF_FALSE` | u16 offset | 3 | b → | Pop what a condition answered and leave an inlined loop when it is false. |
| **16** | `OP_CHECK_BOOL` | u16 name index | 3 | b → b | Require the top of the stack to be a boolean, **leaving it there**. |
| **17** | `OP_LOOP` | u16 offset | 3 | — | Jump *backward* that many bytes. |

Three of these carry a name index they never push, and it is there for one
reason: **an inlined message must complain exactly as the real send would.**

- `OP_JUMP_IF_FALSE` names the selector it was inlined from, so a non-boolean
  receiver reports the same "does not understand" a real send would have.
- `OP_EXIT_IF_FALSE` differs from it *only* in the complaint. Here the boolean
  came out of a block, so a non-boolean is `whileTrue` objecting to the answer
  rather than a receiver failing to understand a message.
- `OP_CHECK_BOOL` is what an inlined `and` or `or` does to the value its block
  answered. That value *is* the reply, which is why it is examined and left
  rather than consumed.

`OP_LOOP` is the one instruction that can move the instruction pointer towards
zero, which is why it is its own opcode rather than a signed `OP_JUMP`:
everything else stays forward by construction, and the verifier can rely on that.

### Leaving

| Byte | Opcode | Operands | Bytes | Stack | Effect |
| --- | --- | --- | --- | --- | --- |
| **18** | `OP_POP` | — | 1 | v → | Discard the top of the stack. This is what a statement boundary compiles to. |
| **19** | `OP_RETURN` | — | 1 | v → | Return the top of the stack from the current method. |
| **20** | `OP_HALT` | — | 1 | — | Stop the machine. |

Every chunk's last instruction is `OP_HALT`, and the verifier requires it.

---

## Reading a disassembly

`solas --dump` and `solvm --dump` both print one. `a := #45. a:print.` is:

```
== d1.sol ==
0000    1 CONST       0 '#45'
0003    | SETGLOB     0 'a'
0006    | POP
0007    | GLOBAL      0 'a'
0010    | SEND        1 'print' (0 args)
0014    | POP
0015    2 HALT
```

The first column is the byte offset — the gaps are the operands, so `CONST` at
0000 puts `SETGLOB` at 0003. The second is the source line, printed only when it
changes, `|` meaning "same line as above". Then the mnemonic, its operands, and
the side-table entry those operands name.

**A loop and a conditional**, which is where the jump instructions show up:

```
i := #0.
{ i:lessThan(#3) }:whileTrue({ i := i:add(#1) }).
i:greaterThan(#1):ifElse({ "big" }, { "small" }):display.
```

```
0000    1 CONST       0 '#0'
0003    | SETGLOB     0 'i'
0006    | POP
0007    2 GLOBAL      0 'i'
0010    | CONST       1 '#3'
0013    | SEND        1 'lessThan' (1 args)
0017    | EXITIFF    17 -> 37
0020    | GLOBAL      0 'i'
0023    | CONST       2 '#1'
0026    | SEND        2 'add' (1 args)
0030    | SETGLOB     0 'i'
0033    | POP
0034    | LOOP       30 -> 7
0037    | NIL
0038    | POP
0039    3 GLOBAL      0 'i'
0042    | CONST       2 '#1'
0045    | SEND        3 'greaterThan' (1 args)
0049    | JUMP_IF_FALSE    6 -> 60 (ifElse)
0054    | STRING      5 'big'
0057    | JUMP        3 -> 63
0060    | STRING      6 'small'
0063    | SEND        7 'display' (0 args)
0067    | POP
0068    4 HALT
```

Neither block was ever built. The condition's body is emitted inline at 0007,
`LOOP` at 0034 goes back to it, and `whileTrue`'s nil answer is the `NIL` at
0037. `ifElse` becomes a `JUMP_IF_FALSE` past the first arm and a `JUMP` over the
second, and the `(ifElse)` in the listing is that name index — carried so a
non-boolean complains the way the send would have.

A jump prints both its offset and where it lands, so `LOOP 30 -> 7` is thirty
bytes backward, arriving at 0007.

**Blocks are separate chunks.** A method owns its own chunk, so this nests, and
the disassembler prints each after the one that made it:

```
adder := { n | { m | n:add(m) } }.
```

```
== block ==
0000    1 BLOCK       0
0003    | RETURN

== block ==
0000    1 OUTER       1 ^1
0003    | LOCAL       1
0005    | SEND        0 'add' (1 args)
0009    | RETURN
```

The outer block's whole body is making the inner one. The inner reads `n` with
`OP_OUTER 1 ^1` — one frame out, slot 1 — and `m` with `OP_LOCAL 1`, its own
first argument. That is the lexical chain doing its work, and it is why a
capturing block is tied to the frame it was written in.

---

## What the verifier guarantees

A `.sob` file is untrusted input, so `sol_chunk_verify` runs before the first
instruction does. It checks that:

- every instruction fits inside the chunk;
- every operand indexes something that exists — a constant, a name, a method;
- every jump lands on the **start** of an instruction inside the chunk;
- every `OP_LOCAL` and `OP_SET_LOCAL` addresses a slot the frame really has,
  counted from `slot_count` — the method's for a method, and the chunk's own for
  the script;
- the last instruction stops the machine.

Instruction boundaries are found by walking from offset 0 with `sol_op_length`,
which is why that function is the one place lengths are written down: the
verifier, the disassembler, the compiler's escape analysis and the tests all ask
it, so none of them can drift apart from the executor.

A file that fails any of this is refused rather than executed. A `.sob` also
carries a format version, and a build reads only its own.
