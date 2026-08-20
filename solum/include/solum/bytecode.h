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
    OP_CONST,       /* operand: u8 const index -- push constants[idx]           */
    OP_NIL,         /* push nil                                                 */
    OP_GLOBAL,      /* operand: u8 name index -- push the named global          */
    OP_SET_GLOBAL,  /* operand: u8 name index -- bind name, leave value on stack*/
    OP_LOCAL,       /* operand: u8 slot -- push a local (slot 0 is self)        */
    OP_SET_LOCAL,   /* operand: u8 slot -- store into a local, leave it on stack*/
    OP_OUTER,       /* operands: u8 depth, u8 slot -- read a slot of an enclosing
                       frame, `depth` steps out along the lexical chain         */
    OP_SET_OUTER,   /* operands: u8 depth, u8 slot -- write one, leaving the value*/
    OP_BLOCK,       /* operand: u8 method index -- make a block capturing the
                       current frame as its home                               */
    OP_STRING,      /* operand: u8 name index -- make a string from that text  */
    OP_SYMBOL,      /* operand: u8 name index -- intern that text as a symbol  */
    OP_SEND,        /* operands: u8 name index, u8 argc -- send a message       */
    OP_SET_SLOT,    /* operand: u8 name index -- pop a value and an object, bind
                       the name on it, and leave the value                      */
    OP_JUMP,        /* operands: u16 offset -- skip forward that many bytes     */
    OP_JUMP_IF_FALSE,/* operands: u16 offset, u8 name index -- pop a boolean and
                       skip when it is false. The name is the selector this was
                       inlined from, so a non-boolean reports the same "does not
                       understand" it would have as a real send.               */
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

/* A chunk is one compiled unit: a method body, or a whole file. */
typedef struct {
    int           count;
    int           capacity;
    uint8_t      *code;
    int          *lines;      /* source line per byte, for error reporting */
    SolValueArray constants;
    SolNameArray  names;
    SolMethodArray methods;

    /* The collectable cell owning this chunk's tree, or NULL when the chunk is
       owned by whoever created it. Solas and the tests use standalone chunks and
       free them by hand; Solis hands its chunks to the collector, because a
       block defined on one line outlives the line. */
    SolCode      *owner;
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
int  sol_chunk_add_constant(SolChunk *chunk, SolValue value); /* returns index */

/* Interns `length` bytes of `name`, returning its index. Repeat names collapse
   onto one entry, so `print` used ten times costs one slot. */
int  sol_chunk_add_name(SolChunk *chunk, const char *name, int length);

/* Appends without interning, so indices stay exactly as given. The loader uses
   this: a file's code refers to names by position, and collapsing a duplicate
   would silently shift every index after it. */
int  sol_chunk_append_name(SolChunk *chunk, const char *name, int length);
const char *sol_chunk_name(const SolChunk *chunk, int index);

void sol_chunk_free(SolChunk *chunk);

/* Disassembly -- the main debugging tool while the compiler is being written. */
void sol_chunk_disassemble(const SolChunk *chunk, const char *name);
int  sol_chunk_disassemble_instruction(const SolChunk *chunk, int offset);

#endif /* SOLUM_BYTECODE_H */
