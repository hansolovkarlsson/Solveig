/* bytecode.h -- the instruction set shared by Solas (emitter) and Solum (executor).
 *
 * This header is the contract between the two halves of the system. Solas
 * includes it to emit; Solum includes it to execute. Any opcode change is a
 * change to both, so they are defined in exactly one place.
 *
 * The machine is a stack machine. Almost every operation is a message send:
 * OP_SEND pops argc arguments plus a receiver, and pushes the reply. Resolving
 * a name is the exception -- OP_GLOBAL is a lookup, not a send.
 *
 * Operands come in two widths, and which one an operand gets follows from what
 * bounds it. An index into a side table -- a constant, a name, a nested method
 * -- is a little-endian u16, because those tables grow with the program and a long
 * file can fill one. A frame slot, a nesting depth, an argument count is a u8,
 * because those are bounded by the machine rather than by the source: a frame
 * of more than 255 slots is refused before it runs. Jump offsets were u16
 * already, so sixteen bits is the one width the format has.
 *
 * A chunk carries two side tables. Constants are values (#45, 45.5); the other
 * holds interned text -- selectors, global names, and the bytes of string
 * literals, which OP_STRING builds a string from at run time. They are separate
 * because a name is not a value, and a string literal is not one either: a
 * SolString needs a VM to allocate it, and the compiler has none.
 */
#ifndef SOLUM_BYTECODE_H
#define SOLUM_BYTECODE_H

#include "solum/common.h"
#include "solum/gc.h"
#include "solum/value.h"

typedef struct SolCode SolCode;

typedef enum {
    OP_CONST,       /* operand: u16 const index -- push constants[idx]          */
    OP_NIL,         /* push nil                                                 */
    OP_GLOBAL,      /* operand: u16 name index -- push the named global         */
    OP_SET_GLOBAL,  /* operand: u16 name index -- bind name, leave value on stack*/
    OP_LOCAL,       /* operand: u8 slot -- push a local (slot 0 is self)        */
    OP_SET_LOCAL,   /* operand: u8 slot -- store into a local, leave it on stack*/
    OP_OUTER,       /* operands: u8 depth, u8 slot -- read a slot of an enclosing
                       frame, `depth` steps out along the lexical chain         */
    OP_SET_OUTER,   /* operands: u8 depth, u8 slot -- write one, leaving the value*/
    OP_BLOCK,       /* operand: u16 method index -- make a block capturing the
                       current frame as its home                               */
    OP_STRING,      /* operand: u16 name index -- make a string from that text */
    OP_SYMBOL,      /* operand: u16 name index -- intern that text as a symbol */
    OP_SEND,        /* operands: u16 name index, u8 argc -- send a message      */
    OP_SET_SLOT,    /* operand: u16 name index -- pop a value and an object, bind
                       the name on it, and leave the value                      */
    OP_JUMP,        /* operands: u16 offset -- skip forward that many bytes     */
    OP_JUMP_IF_FALSE,/* operands: u16 offset, u16 name index -- pop a boolean and
                       skip when it is false. The name is the selector this was
                       inlined from, so a non-boolean reports the same "does not
                       understand" it would have as a real send.               */
    OP_EXIT_IF_FALSE,/* operands: u16 offset -- pop what the condition answered
                       and leave an inlined loop when it is false. Distinct from
                       OP_JUMP_IF_FALSE only in the complaint it makes: here the
                       boolean came from a block, so a non-boolean is whileTrue
                       objecting to the answer, not a receiver failing to
                       understand the message.                                 */
    OP_CHECK_BOOL,  /* operand: u16 name index -- require the top of the stack to
                       be a boolean, leaving it there. What an inlined `and` or
                       `or` does to the value its block answered: that value is
                       the reply, so unlike the two above it is examined rather
                       than consumed. The name is the message, so the complaint
                       is the one the real send would have made.               */
    OP_LOOP,        /* operands: u16 offset -- jump *backward* that many bytes.
                       The one instruction that can move the ip towards zero,
                       which is why it is its own opcode rather than a signed
                       OP_JUMP: everything else stays forward by construction. */
    OP_POP,         /* discard top of stack (statement boundary)                */
    OP_RETURN,      /* return top of stack from the current method              */
    OP_HALT         /* stop the VM                                              */
} SolOpCode;

typedef struct SolMethod SolMethod;

/* Methods compiled into a chunk. A method owns its own chunk, so this nests. */
typedef struct {
    int         count;
    int         capacity;
    SolMethod **methods;
} SolMethodArray;

/* Interned identifiers: message selectors and global names. */
typedef struct {
    int    count;
    int    capacity;
    char **names;
} SolNameArray;

/* A hash index over one of the side tables, mapping an entry to its position.
 *
 * Both tables intern, and interning was a linear scan -- which cost nothing
 * while a table held 256 entries and became quadratic when 4.2 raised the
 * ceiling to 65536. This is what makes filling one linear again.
 *
 * Open addressing with linear probing, capacity a power of two, and no
 * deletions: entries only ever accumulate while a chunk is compiled. `slots`
 * holds a position in the side table, or -1 for an empty bucket. Derived
 * rather than stored, so nothing about the `.sob` format changes -- the loader
 * rebuilds it as it appends. */
typedef struct {
    int *slots;
    int  capacity;      /* power of two, or 0 before the first insert */
    int  count;
} SolIndex;

/* A chunk is one compiled unit: a method body, or a whole file. */
typedef struct {
    int           count;
    int           capacity;
    uint8_t      *code;
    int          *lines;      /* source line per byte, for error reporting */

    /* Which file that line came from: an index into `files`, per byte. A chunk
       is one compiled unit and an `@include` puts a library's code into the
       same one, so a line number on its own names a line in a file nobody said
       -- which read as a line of the file you were looking at, and was worse
       than saying nothing. Almost always one run per chunk: a method body comes
       from one file. */
    int          *file_ids;
    SolNameArray  files;      /* the paths, each stored once */
    int           writing_file;   /* which of them `sol_chunk_write` records */

    /* What each frame slot was called, in slot order. A slot is an index at run
       time and that is the right thing -- an access is not a lookup -- but the
       compiler knew the name and threw it away, so anything looking at a
       running frame could say `slot 3` and not `average`. Slot 0 is the
       receiver and has no name of its own. Empty for a chunk built by hand. */
    SolNameArray  slot_names;

    SolValueArray constants;
    SolNameArray  names;
    SolMethodArray methods;

    /* Where each side table's entries already live, so interning need not scan.
       Purely an accelerator: emptying one would slow compilation without
       changing a byte of what comes out. */
    SolIndex      name_index;
    SolIndex      constant_index;

    /* `names` resolved to this VM's interned copies, one entry per name, so a
       send reads a pointer it can compare with `==` instead of hashing or
       walking characters (4.3). Built once, before the chunk first runs.
       NULL in Solas, which has no VM to intern against. */
    const char  **interned;

    /* Where each of those names lives on the root object, once something has
     * looked. One entry per name, NULL until the first OP_GLOBAL or
     * OP_SET_GLOBAL mentioning it runs, after which reading or writing that
     * global is a pointer dereference rather than a hash and a probe.
     *
     * **A global's slot never moves and is never taken away**, which is what
     * makes caching the pointer sound rather than merely fast. Slots are
     * malloc'd one at a time and linked, so growing the object's index moves
     * pointers *to* them and not the slots themselves; and nothing in the
     * language removes a slot -- the same fact ROADMAP 3.10 records as a
     * problem, read here as a guarantee. A miss is not cached, so a name that
     * is not bound yet is looked up again rather than remembered as absent.
     *
     * It rides beside `interned` and is emptied by exactly the same rule --
     * `interned_for` below -- because a slot pointer belongs to one VM's root
     * as surely as an interned name belongs to its name table. Two caches with
     * one invalidation is the whole reason this is here and not somewhere of
     * its own.
     *
     * Worth 1.25x on a script whose loop counter is a global, measured against
     * the same loop written with block temporaries, where the access is already
     * an array index. */
    struct SolSlot **global_slots;

    /* Which VM those pointers belong to, by **serial number rather than
       address**. A VM used to be identified here by its own pointer, and that
       is wrong in the one case it most needed to be right: free a VM and make
       another, and the second can land at the address the first had -- which a
       host running a script per request does every time, the VM being a local.
       The chunk then believed it was already resolved and went on reading the
       freed VM's name table, which fails as `integer does not understand ''`
       rather than as anything a reader could act on.
     *
       A serial is unique for the life of the process, so a reused address
       cannot be mistaken for the same machine. Zero means "no VM yet", which is
       what a chunk from Solas holds. */
    uint64_t      interned_for;

    /* The collectable cell owning this chunk's tree, or NULL when the chunk is
       owned by whoever created it. Solas and the tests use standalone chunks and
       free them by hand; Solis hands its chunks to the collector, because a
       block defined on one line outlives the line. */
    SolCode      *owner;

    /* Frame slots the *script* needs: slot 0, which nothing can name, plus any
       temporary its top level declares. `sol_vm_run` reserves them before the
       first instruction, exactly as `push_frame` reserves a method's.
     *
     * Only meaningful on a chunk run directly as a script. A method's chunk is
     * entered through `push_frame`, which reads `SolMethod.slot_count`; this
     * stays 0 there rather than being a second copy of the same number.
     *
     * The script used to have no slots at all, which is why a temporary
     * declared at the top level had to be refused: there was nowhere to put it.
     * See ROADMAP 6.6 for the other thing that cost. */
    int           slot_count;
} SolChunk;

/* A chunk tree the collector owns. The root chunk owns every method nested
   inside it, so one cell covers the whole tree. */
struct SolCode {
    SolGCHeader gc;
    SolChunk    chunk;
};

/* Allocates a code cell with an empty chunk, ready to compile or load into. */
SolCode *sol_code_new(SolVM *vm);

/* Points `chunk` and everything nested inside it at `owner`. Callers rarely need
   this: sol_chunk_add_method propagates ownership as each subtree is added. */
void sol_chunk_set_owner(SolChunk *chunk, SolCode *owner);

/* A method compiled from Solum source, as opposed to a C primitive.
 *
 * `slot_count` covers self, the parameters, and any locals the body declares.
 * A call reserves that many stack slots, so the compiler decides the frame
 * size and the VM just honours it. */
struct SolMethod {
    char    *name;
    int      arity;
    int      slot_count;   /* 1 (self) + arity + body locals */
    bool     is_block;     /* a block body rather than a named method       */
    bool     captures;     /* reads or writes its home frame, so the frame
                              must still be alive when the block runs        */
    SolChunk chunk;
};

SolMethod *sol_method_new(const char *name, int length, int arity);
void       sol_method_free(SolMethod *method);

/* Adds `method` to the chunk, taking ownership of it. Returns its index. */
int sol_chunk_add_method(SolChunk *chunk, SolMethod *method);

void sol_chunk_init(SolChunk *chunk);
void sol_chunk_write(SolChunk *chunk, uint8_t byte, int line);

/* Both side tables intern: a repeated entry collapses onto the first, so
   `print` used ten times, or `#1`, costs one slot. Constants can do this
   because the only ones a chunk may hold are immutable scalars -- and it
   compares them by their bits, so -0.0 stays distinct from 0.0. */
int  sol_chunk_add_constant(SolChunk *chunk, SolValue value); /* returns index */
int  sol_chunk_add_name(SolChunk *chunk, const char *name, int length);

/* Interns `path` in the chunk's file table and answers its index; set
   `writing_file` to it and the bytes written next are recorded as coming from
   there. NULL is the same as "", which is what a chunk compiled from text
   rather than from a file has. */
int  sol_chunk_file(SolChunk *chunk, const char *path);

/* The path the byte at `offset` came from, or "" when nothing said. */
const char *sol_chunk_file_of(const SolChunk *chunk, int offset);

/* Records what slot `index` is called. Appends in slot order; a gap is filled
   with "" so the table stays parallel to the slots. */
void sol_chunk_name_slot(SolChunk *chunk, int index, const char *name, int length);

/* What slot `index` is called, or "" when nothing said. */
const char *sol_chunk_slot_name(const SolChunk *chunk, int index);

/* Append without interning, so indices stay exactly as given. The loader uses
   these: a file's code refers to both tables by position, and collapsing a
   duplicate would silently shift every index after it. */
int  sol_chunk_append_constant(SolChunk *chunk, SolValue value);
int  sol_chunk_append_name(SolChunk *chunk, const char *name, int length);
const char *sol_chunk_name(const SolChunk *chunk, int index);

void sol_chunk_free(SolChunk *chunk);

/* How many bytes an instruction occupies, its opcode included; 0 if the opcode
   is not one of ours. Single-sourced because the emitter, the verifier, the
   disassembler, and the executor have to agree to the byte: disagreeing is
   exactly how a jump comes to land in the middle of an instruction. */
int sol_op_length(uint8_t op);

/* ---- the byte order of a two-byte operand -------------------------------- *
 *
 * Little-endian: the first byte carries the low half, which is what the .sob
 * file's own tables have always used. **The two agree as of format 14** and did
 * not before -- a .sob used to be a little-endian container holding a
 * big-endian instruction stream, two conventions arrived at separately and
 * never compared. Both were internally consistent, so nothing forced the
 * comparison until programs/disasm.sol had to decode both in one program and
 * got the operands backwards. That does not read as a misreading: every index
 * comes out 256 times too large, which looks like a corrupt file.
 *
 * **The order lives in these two shifts and nowhere else**, which is what made
 * changing it a two-character edit. Reading was already single-sourced here;
 * writing was not, and had twelve copies of the expression across the compiler
 * and the tests -- the shape of thing that drifts, and the reason the
 * instruction lengths once did. A round-trip test in tests/test_bytecode.c
 * holds the pair to each other, so changing one and not the other fails the
 * build. */
#define SOL_U16_FIRST_SHIFT  0
#define SOL_U16_SECOND_SHIFT 8

/* The two bytes of `v`, in the order they are written. Named by position rather
   than by significance, because position is what a caller emitting one after
   the other actually cares about. */
static inline uint8_t sol_u16_first(uint16_t v)
{
    return (uint8_t)((v >> SOL_U16_FIRST_SHIFT) & 0xff);
}

static inline uint8_t sol_u16_second(uint16_t v)
{
    return (uint8_t)((v >> SOL_U16_SECOND_SHIFT) & 0xff);
}

/* The same, into two bytes a caller already has room for -- what patching a
   jump offset already emitted needs. */
static inline void sol_write_u16(uint8_t *at, uint16_t v)
{
    at[0] = sol_u16_first(v);
    at[1] = sol_u16_second(v);
}

/* The one place a two-byte operand is decoded. Everything that walks bytecode
   reads it through here, so the byte order cannot drift between the emitter,
   the verifier, and the executor. */
static inline uint16_t sol_read_u16(const uint8_t *at)
{
    return (uint16_t)(((uint16_t)at[0] << SOL_U16_FIRST_SHIFT) |
                      ((uint16_t)at[1] << SOL_U16_SECOND_SHIFT));
}

/* Disassembly -- the main debugging tool while the compiler is being written. */
void sol_chunk_disassemble(const SolChunk *chunk, const char *name);
int  sol_chunk_disassemble_instruction(const SolChunk *chunk, int offset);

#endif /* SOLUM_BYTECODE_H */
