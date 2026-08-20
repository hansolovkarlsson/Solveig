/* Covers the chunk plumbing that both Solas and Solum depend on. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solum/bytecode.h"

static void test_chunk_grows(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(chunk.count == 0);

    /* Push past the initial capacity of 8 to exercise the realloc path. */
    for (int i = 0; i < 100; i++) {
        sol_chunk_write(&chunk, OP_NIL, i / 10 + 1);
    }
    assert(chunk.count == 100);
    assert(chunk.capacity >= 100);
    assert(chunk.lines[0] == 1);
    assert(chunk.lines[99] == 10);

    sol_chunk_free(&chunk);
    assert(chunk.count == 0);
    assert(chunk.code == NULL);
}

static void test_constants_are_indexed_in_order(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    int first  = sol_chunk_add_constant(&chunk, SOL_INT_VAL(45));
    int second = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(2.5));

    assert(first == 0 && second == 1);
    assert(SOL_IS_INT(chunk.constants.values[first]));
    assert(SOL_AS_INT(chunk.constants.values[first]) == 45);
    assert(SOL_IS_FLOAT(chunk.constants.values[second]));

    sol_chunk_free(&chunk);
}

/* Constants intern the way names do. `#45` is immutable, so one slot can serve
   every mention of it -- but only where the bits agree: #45 and 45 are
   different types, and -0.0 prints differently from 0.0. */
static void test_constants_are_interned(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    int a = sol_chunk_add_constant(&chunk, SOL_INT_VAL(45));
    int b = sol_chunk_add_constant(&chunk, SOL_INT_VAL(45));
    assert(a == b);
    assert(chunk.constants.count == 1);

    assert(sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(45.0)) != a);
    assert(sol_chunk_add_constant(&chunk, SOL_NIL_VAL) !=
           sol_chunk_add_constant(&chunk, SOL_BOOL_VAL(false)));

    int zero  = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(0.0));
    int minus = sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(-0.0));
    assert(zero != minus);

    /* The loader appends instead, because a file's code indexes this table by
       position and folding an entry would shift everything after it. */
    int kept = sol_chunk_append_constant(&chunk, SOL_INT_VAL(45));
    assert(kept != a);

    sol_chunk_free(&chunk);
}

/* Repeated selectors must collapse onto one slot -- with a bounded operand this
   is the difference between fitting in a chunk and not. */
static void test_names_are_interned(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    int a      = sol_chunk_add_name(&chunk, "a", 1);
    int print1 = sol_chunk_add_name(&chunk, "print", 5);
    int print2 = sol_chunk_add_name(&chunk, "print", 5);

    assert(a == 0);
    assert(print1 == 1);
    assert(print2 == print1);
    assert(chunk.names.count == 2);
    assert(strcmp(sol_chunk_name(&chunk, print1), "print") == 0);

    /* A name that is a prefix of another must not collide. */
    int pr = sol_chunk_add_name(&chunk, "pr", 2);
    assert(pr != print1);
    assert(strcmp(sol_chunk_name(&chunk, pr), "pr") == 0);

    sol_chunk_free(&chunk);
}

/* A side-table index, big-endian, exactly as the compiler emits it. */
static void write_index(SolChunk *chunk, int index, int line)
{
    sol_chunk_write(chunk, (uint8_t)((index >> 8) & 0xff), line);
    sol_chunk_write(chunk, (uint8_t)(index & 0xff), line);
}

static void test_disassembler_walks_every_instruction(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    /* Hand-assembled `a:print.` */
    int a     = sol_chunk_add_name(&chunk, "a", 1);
    int print = sol_chunk_add_name(&chunk, "print", 5);

    sol_chunk_write(&chunk, OP_GLOBAL, 1);
    write_index(&chunk, a, 1);
    sol_chunk_write(&chunk, OP_SEND, 1);
    write_index(&chunk, print, 1);
    sol_chunk_write(&chunk, 0, 1);
    sol_chunk_write(&chunk, OP_POP, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);

    /* Each instruction must advance the offset, and operands of multi-byte
       instructions must not be decoded as opcodes. */
    int instructions = 0;
    for (int offset = 0; offset < chunk.count; instructions++) {
        int next = sol_chunk_disassemble_instruction(&chunk, offset);
        assert(next > offset);
        offset = next;
    }
    assert(instructions == 4);

    sol_chunk_free(&chunk);
}

int main(void)
{
    test_chunk_grows();
    test_constants_are_indexed_in_order();
    test_constants_are_interned();
    test_names_are_interned();
    test_disassembler_walks_every_instruction();
    printf("test_bytecode: ok\n");
    return 0;
}
