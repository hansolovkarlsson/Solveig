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
 * A chunk carries two side tables. Constants are values (#45, 45.5); names are
 * the identifiers used by lookups and sends. They are separate because a name
 * is not a value -- there is no string object to hold one in.
 */
#ifndef SOLUM_BYTECODE_H
#define SOLUM_BYTECODE_H

#include "solum/common.h"
#include "solum/value.h"

typedef enum {
    OP_CONST,       /* operand: u8 const index -- push constants[idx]           */
    OP_NIL,         /* push nil                                                 */
    OP_GLOBAL,      /* operand: u8 name index -- push the named global          */
    OP_SET_GLOBAL,  /* operand: u8 name index -- bind name, leave value on stack*/
    OP_SEND,        /* operands: u8 name index, u8 argc -- send a message       */
    OP_POP,         /* discard top of stack (statement boundary)                */
    OP_RETURN,      /* return top of stack from the current method              */
    OP_HALT         /* stop the VM                                              */
} SolOpCode;

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
} SolChunk;

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
