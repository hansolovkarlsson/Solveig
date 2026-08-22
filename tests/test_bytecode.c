/* Covers the chunk plumbing that both Solas and Solum depend on. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
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

/* Writing a two-byte operand and reading it back is the same number, whichever
   order the two are in.
 *
 * The order lives in SOL_U16_FIRST_SHIFT and SOL_U16_SECOND_SHIFT and nowhere
 * else now -- it used to live in twelve copies of `(v >> 8) & 0xff` across the
 * compiler and this suite. This is what holds the writing pair and the reading
 * function to each other, so changing one of the two and not the other fails
 * here rather than in whatever runs next.
 *
 * The values are the edges: zero, both single bytes, the two-byte boundary, two
 * asymmetric patterns that a swap could not leave looking right, and the
 * largest an operand can be. */
static void test_a_two_byte_operand_round_trips(void)
{
    static const uint16_t values[] = { 0, 1, 0x00ff, 0x0100, 0x1234, 0xabcd, 0xffff };

    for (size_t i = 0; i < sizeof values / sizeof values[0]; i++) {
        uint8_t bytes[2];

        /* As the compiler emits it: one byte, then the other. */
        bytes[0] = sol_u16_first(values[i]);
        bytes[1] = sol_u16_second(values[i]);
        assert(sol_read_u16(bytes) == values[i]);

        /* And as a patch writes it, which must agree with the pair. */
        uint8_t patched[2] = { 0, 0 };
        sol_write_u16(patched, values[i]);
        assert(patched[0] == bytes[0] && patched[1] == bytes[1]);
    }

    /* And the two shifts are a permutation of the halves rather than, say, both
       8 -- which would round-trip nothing, and would still pass every case above
       if the reader happened to be wrong the same way. */
    assert(sol_u16_first(0xff00) != sol_u16_second(0xff00));
    assert(SOL_U16_FIRST_SHIFT + SOL_U16_SECOND_SHIFT == 8);

    printf("  a two-byte operand round-trips, whichever order it is in\n");
}

/* A side-table index, exactly as the compiler emits it -- through the same pair,
   so a test cannot go on passing after the order changes under it. */
static void write_index(SolChunk *chunk, int index, int line)
{
    sol_chunk_write(chunk, sol_u16_first((uint16_t)index), line);
    sol_chunk_write(chunk, sol_u16_second((uint16_t)index), line);
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

/* ---- the instruction set reference ------------------------------------- *
 *
 * docs/BYTECODE.md describes every opcode. It fell six behind once -- every
 * jump, plus the two newest -- because nothing tied the document to the header,
 * so nothing said when it stopped being true.
 *
 * These read both files. The opcode names come out of the enum in the order
 * they are written, which is also their value: a C enum with no initialisers
 * numbers from zero upwards, so the header alone gives name and value both, and
 * there is no list here to fall behind in its turn.
 */
#define HEADER_PATH "solum/include/solum/bytecode.h"
#define DOC_PATH    "docs/BYTECODE.md"

#define MAX_OPCODES 64

static char *read_whole_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    /* Run from the repository root, which is where `make test` runs. */
    assert(f != NULL);

    assert(fseek(f, 0L, SEEK_END) == 0);
    long size = ftell(f);
    assert(size > 0);
    rewind(f);

    char *text = malloc((size_t)size + 1);
    assert(text != NULL);
    assert(fread(text, 1, (size_t)size, f) == (size_t)size);
    text[size] = '\0';
    fclose(f);
    return text;
}

/* The identifiers in the SolOpCode enum, in order. Answers how many. */
static int opcode_names(const char *header, char names[][32])
{
    const char *at = strstr(header, "typedef enum {");
    assert(at != NULL);
    const char *end = strstr(at, "} SolOpCode;");
    assert(end != NULL);

    int count = 0;
    while ((at = strstr(at, "OP_")) != NULL && at < end) {
        /* Only a name being *defined*. Starting its line is not enough: the
           comments wrap, so `OP_JUMP_IF_FALSE only in the complaint it makes`
           begins one too. What separates them is what comes after -- a member
           is followed by its comma, or by its comment if it is the last one. */
        const char *line = at;
        while (line > header && line[-1] != '\n') line--;

        bool at_line_start = true;
        for (const char *c = line; c < at; c++) {
            if (*c != ' ' && *c != '\t') { at_line_start = false; break; }
        }

        int length = 0;
        while (at[length] == '_' || (at[length] >= 'A' && at[length] <= 'Z') ||
               (at[length] >= '0' && at[length] <= '9')) {
            length++;
        }

        const char *after = at + length;
        while (*after == ' ' || *after == '\t') after++;
        bool is_a_member = *after == ',' || (after[0] == '/' && after[1] == '*');

        if (at_line_start && is_a_member) {
            assert(count < MAX_OPCODES);
            assert(length < 32);
            memcpy(names[count], at, (size_t)length);
            names[count][length] = '\0';
            count++;
        }
        at += length;
    }

    assert(count > 0);
    return count;
}

/* Every opcode the header defines is described in the document. This is the
   check that would have caught the six that went missing. */
static void test_every_opcode_is_documented(void)
{
    char *header = read_whole_file(HEADER_PATH);
    char *doc    = read_whole_file(DOC_PATH);

    char names[MAX_OPCODES][32];
    int count = opcode_names(header, names);

    for (int i = 0; i < count; i++) {
        if (strstr(doc, names[i]) == NULL) {
            printf("\n%s defines %s and %s does not describe it\n",
                   HEADER_PATH, names[i], DOC_PATH);
            assert(false);
        }
    }

    free(header);
    free(doc);
    printf("  every opcode in the header is in %s (%d of them)\n", DOC_PATH, count);
}

/* And with the right number beside it.
 *
 * The document described every instruction and never said what byte any of them
 * was, so a reader with only this page in front of them could not decode one
 * instruction of a .sob file -- which programs/disasm.sol found by trying. The
 * numbers are the enum's order, so inserting an opcode in the middle renumbers
 * everything after it, and this is what makes that fail the suite instead of
 * silently making the page wrong. */
static void test_every_opcode_has_its_number(void)
{
    char *header = read_whole_file(HEADER_PATH);
    char *doc    = read_whole_file(DOC_PATH);

    char names[MAX_OPCODES][32];
    int count = opcode_names(header, names);

    for (int i = 0; i < count; i++) {
        /* The row is "| **N** | `OP_NAME` |", so the number is what stands
           immediately before the opcode in the table. */
        char wanted[64];
        snprintf(wanted, sizeof wanted, "| **%d** | `%s` |", i, names[i]);
        if (strstr(doc, wanted) == NULL) {
            printf("\n%s should give %s the byte %d, as \"%s\"\n",
                   DOC_PATH, names[i], i, wanted);
            assert(false);
        }
    }

    free(header);
    free(doc);
    printf("  and every one carries its byte (0 to %d)\n", count - 1);
}

/* And the other way: nothing described that no longer exists. */
static void test_nothing_documented_has_been_removed(void)
{
    char *header = read_whole_file(HEADER_PATH);
    char *doc    = read_whole_file(DOC_PATH);

    char names[MAX_OPCODES][32];
    int count = opcode_names(header, names);

    for (const char *at = strstr(doc, "OP_"); at != NULL; at = strstr(at + 1, "OP_")) {
        int length = 0;
        while (at[length] == '_' || (at[length] >= 'A' && at[length] <= 'Z') ||
               (at[length] >= '0' && at[length] <= '9')) {
            length++;
        }

        bool known = false;
        for (int i = 0; i < count; i++) {
            if ((int)strlen(names[i]) == length &&
                memcmp(names[i], at, (size_t)length) == 0) {
                known = true;
                break;
            }
        }
        if (!known) {
            printf("\n%s describes %.*s, which the header does not define\n",
                   DOC_PATH, length, at);
            assert(false);
        }
    }

    free(header);
    free(doc);
    printf("  nothing in %s has been removed from the header\n", DOC_PATH);
}

/* The document gives each instruction's length in bytes. `sol_op_length` is the
   one place lengths are really written down, so that is what it is measured
   against -- a table saying three where the executor reads five would send a
   reader off by two on every following offset. */
static void test_documented_lengths_are_the_real_ones(void)
{
    char *header = read_whole_file(HEADER_PATH);
    char *doc    = read_whole_file(DOC_PATH);

    char names[MAX_OPCODES][32];
    int count = opcode_names(header, names);

    int checked = 0;
    for (int op = 0; op < count; op++) {
        /* The row for this opcode: "| `OP_NAME` | operands | bytes | ... " */
        char needle[64];
        snprintf(needle, sizeof needle, "| `%s` |", names[op]);

        const char *row = strstr(doc, needle);
        if (row == NULL) continue;          /* the check above owns that case */

        /* Past the operand column to the one after it. */
        const char *at = row + strlen(needle);
        at = strchr(at, '|');
        assert(at != NULL);
        at++;
        while (*at == ' ') at++;

        assert(*at >= '0' && *at <= '9');
        int documented = atoi(at);
        int actual = sol_op_length((uint8_t)op);

        if (documented != actual) {
            printf("\n%s says %s is %d bytes; sol_op_length says %d\n",
                   DOC_PATH, names[op], documented, actual);
            assert(false);
        }
        checked++;
    }

    assert(checked == count);       /* every one of them had a row */

    free(header);
    free(doc);
    printf("  every documented instruction length matches sol_op_length\n");
}

int main(void)
{
    test_a_two_byte_operand_round_trips();
    test_chunk_grows();
    test_constants_are_indexed_in_order();
    test_constants_are_interned();
    test_names_are_interned();
    test_disassembler_walks_every_instruction();
    test_every_opcode_is_documented();
    test_every_opcode_has_its_number();
    test_nothing_documented_has_been_removed();
    test_documented_lengths_are_the_real_ones();
    printf("test_bytecode: ok\n");
    return 0;
}
