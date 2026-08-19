/* Covers the .sob format: round-tripping, and refusing to run a bad file. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/serialize.h"

#define TMP "build/tests/test_serialize.tmp.sob"

/* `a := #45. a:print.` hand-assembled, with a float and a nil along for the
   ride so every constant tag gets exercised. */
static void build_valid(SolChunk *chunk)
{
    sol_chunk_init(chunk);

    uint8_t a     = (uint8_t)sol_chunk_add_name(chunk, "a", 1);
    uint8_t print = (uint8_t)sol_chunk_add_name(chunk, "print", 5);

    uint8_t k_int   = (uint8_t)sol_chunk_add_constant(chunk, SOL_INT_VAL(-45));
    (void)             sol_chunk_add_constant(chunk, SOL_FLOAT_VAL(2.5));
    (void)             sol_chunk_add_constant(chunk, SOL_NIL_VAL);

    sol_chunk_write(chunk, OP_CONST, 1);
    sol_chunk_write(chunk, k_int, 1);
    sol_chunk_write(chunk, OP_SET_GLOBAL, 1);
    sol_chunk_write(chunk, a, 1);
    sol_chunk_write(chunk, OP_POP, 1);
    sol_chunk_write(chunk, OP_GLOBAL, 2);
    sol_chunk_write(chunk, a, 2);
    sol_chunk_write(chunk, OP_SEND, 2);
    sol_chunk_write(chunk, print, 2);
    sol_chunk_write(chunk, 0, 2);
    sol_chunk_write(chunk, OP_POP, 2);
    sol_chunk_write(chunk, OP_HALT, 3);
}

static void test_round_trip_preserves_everything(void)
{
    SolChunk original;
    build_valid(&original);
    assert(sol_chunk_save(&original, TMP) == SOL_SER_OK);

    SolChunk loaded;
    assert(sol_chunk_load(&loaded, TMP) == SOL_SER_OK);

    assert(loaded.count == original.count);
    assert(memcmp(loaded.code, original.code, (size_t)original.count) == 0);

    /* Line numbers survive the run-length encoding. */
    for (int i = 0; i < original.count; i++) {
        assert(loaded.lines[i] == original.lines[i]);
    }
    assert(loaded.lines[0] == 1);
    assert(loaded.lines[5] == 2);
    assert(loaded.lines[11] == 3);

    assert(loaded.names.count == original.names.count);
    assert(strcmp(sol_chunk_name(&loaded, 0), "a") == 0);
    assert(strcmp(sol_chunk_name(&loaded, 1), "print") == 0);

    assert(loaded.constants.count == 3);
    assert(SOL_IS_INT(loaded.constants.values[0]));
    assert(SOL_AS_INT(loaded.constants.values[0]) == -45);   /* sign survives */
    assert(SOL_IS_FLOAT(loaded.constants.values[1]));
    assert(SOL_AS_FLOAT(loaded.constants.values[1]) == 2.5); /* bit-exact */
    assert(SOL_IS_NIL(loaded.constants.values[2]));

    sol_chunk_free(&loaded);
    sol_chunk_free(&original);
    remove(TMP);
}

/* Floats must come back bit-identical, not merely close. */
static void test_float_bits_are_exact(void)
{
    const double values[] = { 0.1, -2.5e300, 1.0 / 3.0, 1e-320 };

    for (size_t i = 0; i < sizeof values / sizeof values[0]; i++) {
        SolChunk chunk;
        sol_chunk_init(&chunk);
        sol_chunk_add_name(&chunk, "x", 1);
        uint8_t k = (uint8_t)sol_chunk_add_constant(&chunk, SOL_FLOAT_VAL(values[i]));
        sol_chunk_write(&chunk, OP_CONST, 1);
        sol_chunk_write(&chunk, k, 1);
        sol_chunk_write(&chunk, OP_POP, 1);
        sol_chunk_write(&chunk, OP_HALT, 1);

        assert(sol_chunk_save(&chunk, TMP) == SOL_SER_OK);

        SolChunk loaded;
        assert(sol_chunk_load(&loaded, TMP) == SOL_SER_OK);
        assert(memcmp(&loaded.constants.values[0].as.real, &values[i],
                      sizeof(double)) == 0);

        sol_chunk_free(&loaded);
        sol_chunk_free(&chunk);
    }
    remove(TMP);
}

/* The loader appends names rather than interning them: a file's code refers to
   names by position, so collapsing a duplicate would shift every later index. */
static void test_duplicate_names_keep_their_indices(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    sol_chunk_append_name(&chunk, "dup", 3);
    sol_chunk_append_name(&chunk, "dup", 3);
    assert(chunk.names.count == 2);

    sol_chunk_write(&chunk, OP_GLOBAL, 1);
    sol_chunk_write(&chunk, 1, 1);          /* refers to the second entry */
    sol_chunk_write(&chunk, OP_POP, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);

    assert(sol_chunk_save(&chunk, TMP) == SOL_SER_OK);

    SolChunk loaded;
    assert(sol_chunk_load(&loaded, TMP) == SOL_SER_OK);
    assert(loaded.names.count == 2);
    assert(strcmp(sol_chunk_name(&loaded, 1), "dup") == 0);

    sol_chunk_free(&loaded);
    sol_chunk_free(&chunk);
    remove(TMP);
}

/* ---- rejecting bad files --------------------------------------------- */

static void write_bytes(const char *path, const void *data, size_t size)
{
    FILE *f = fopen(path, "wb");
    assert(f != NULL);
    fwrite(data, 1, size, f);
    fclose(f);
}

/* Saves a valid file, then flips one byte at `offset`. */
static void save_and_poke(size_t offset, uint8_t value)
{
    SolChunk chunk;
    build_valid(&chunk);
    assert(sol_chunk_save(&chunk, TMP) == SOL_SER_OK);
    sol_chunk_free(&chunk);

    FILE *f = fopen(TMP, "r+b");
    assert(f != NULL);
    assert(fseek(f, (long)offset, SEEK_SET) == 0);
    fputc(value, f);
    fclose(f);
}

static void test_rejects_files_it_should_not_run(void)
{
    SolChunk chunk;

    /* Not a .sob file at all. */
    write_bytes(TMP, "this is plain text", 18);
    assert(sol_chunk_load(&chunk, TMP) == SOL_SER_BAD_MAGIC);

    /* Right magic, wrong version. */
    save_and_poke(4, 99);
    assert(sol_chunk_load(&chunk, TMP) == SOL_SER_BAD_VERSION);

    /* Reserved field must be zero -- it is where a future flag will go. */
    save_and_poke(6, 1);
    assert(sol_chunk_load(&chunk, TMP) == SOL_SER_MALFORMED);

    /* Cut short at every length, to catch a missing bounds check anywhere. */
    SolChunk valid;
    build_valid(&valid);
    assert(sol_chunk_save(&valid, TMP) == SOL_SER_OK);
    sol_chunk_free(&valid);

    FILE *f = fopen(TMP, "rb");
    assert(f != NULL);
    static uint8_t whole[4096];
    size_t size = fread(whole, 1, sizeof whole, f);
    fclose(f);
    assert(size > 16 && size < sizeof whole);

    for (size_t cut = 1; cut < size; cut++) {
        write_bytes(TMP, whole, cut);
        SolSerResult result = sol_chunk_load(&chunk, TMP);
        assert(result != SOL_SER_OK);       /* must never load, never crash */
        if (result == SOL_SER_OK) sol_chunk_free(&chunk);
    }

    /* A missing file is an I/O error, not a crash. */
    assert(sol_chunk_load(&chunk, "build/tests/definitely-not-here.sob") == SOL_SER_IO);

    remove(TMP);
}

/* ---- the verifier ----------------------------------------------------- */

static void test_verifier_rejects_unsafe_code(void)
{
    SolChunk chunk;

    /* Empty. */
    sol_chunk_init(&chunk);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* Unknown opcode. */
    sol_chunk_init(&chunk);
    sol_chunk_write(&chunk, 200, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* Operand index past the end of the constant pool. */
    sol_chunk_init(&chunk);
    sol_chunk_add_constant(&chunk, SOL_INT_VAL(1));
    sol_chunk_write(&chunk, OP_CONST, 1);
    sol_chunk_write(&chunk, 7, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* Operand index past the end of the name table. */
    sol_chunk_init(&chunk);
    sol_chunk_add_name(&chunk, "a", 1);
    sol_chunk_write(&chunk, OP_SEND, 1);
    sol_chunk_write(&chunk, 9, 1);
    sol_chunk_write(&chunk, 0, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* An instruction whose operands run off the end. */
    sol_chunk_init(&chunk);
    sol_chunk_add_name(&chunk, "a", 1);
    sol_chunk_write(&chunk, OP_SEND, 1);
    sol_chunk_write(&chunk, 0, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_TRUNCATED);
    sol_chunk_free(&chunk);

    /* Falling off the end: without a final HALT the dispatch loop would keep
       reading past the buffer. */
    sol_chunk_init(&chunk);
    sol_chunk_write(&chunk, OP_NIL, 1);
    sol_chunk_write(&chunk, OP_POP, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* And saving refuses what loading would reject. */
    sol_chunk_init(&chunk);
    sol_chunk_write(&chunk, OP_NIL, 1);
    assert(sol_chunk_save(&chunk, TMP) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);
    remove(TMP);
}

/* Methods nest a chunk inside a chunk, so they have to survive the round trip
   with their arity, frame size, and body intact. */
static void test_methods_round_trip(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);

    uint8_t integer = (uint8_t)sol_chunk_add_name(&chunk, "integer", 7);
    uint8_t dbl     = (uint8_t)sol_chunk_add_name(&chunk, "double", 6);

    SolMethod *method = sol_method_new("double", 6, 0);
    method->slot_count = 1;                       /* just self */
    uint8_t two  = (uint8_t)sol_chunk_add_constant(&method->chunk, SOL_INT_VAL(2));
    uint8_t mul  = (uint8_t)sol_chunk_add_name(&method->chunk, "mul", 3);
    sol_chunk_write(&method->chunk, OP_LOCAL, 1);
    sol_chunk_write(&method->chunk, 0, 1);
    sol_chunk_write(&method->chunk, OP_CONST, 1);
    sol_chunk_write(&method->chunk, two, 1);
    sol_chunk_write(&method->chunk, OP_SEND, 1);
    sol_chunk_write(&method->chunk, mul, 1);
    sol_chunk_write(&method->chunk, 1, 1);
    sol_chunk_write(&method->chunk, OP_RETURN, 1);
    uint8_t index = (uint8_t)sol_chunk_add_method(&chunk, method);

    sol_chunk_write(&chunk, OP_GLOBAL, 1);
    sol_chunk_write(&chunk, integer, 1);
    sol_chunk_write(&chunk, OP_DEF_METHOD, 1);
    sol_chunk_write(&chunk, index, 1);
    sol_chunk_write(&chunk, dbl, 1);
    sol_chunk_write(&chunk, OP_POP, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);

    assert(sol_chunk_save(&chunk, TMP) == SOL_SER_OK);

    SolChunk loaded;
    assert(sol_chunk_load(&loaded, TMP) == SOL_SER_OK);
    assert(loaded.methods.count == 1);

    const SolMethod *back = loaded.methods.methods[0];
    assert(strcmp(back->name, "double") == 0);
    assert(back->arity == 0);
    assert(back->slot_count == 1);
    assert(back->chunk.count == method->chunk.count);
    assert(memcmp(back->chunk.code, method->chunk.code,
                  (size_t)method->chunk.count) == 0);
    assert(strcmp(sol_chunk_name(&back->chunk, mul), "mul") == 0);

    sol_chunk_free(&loaded);
    sol_chunk_free(&chunk);
    remove(TMP);
}

/* A frame is addressed by one-byte slot operands, so a method claiming fewer
   slots than it has parameters -- or code reaching past them -- must be
   rejected before it can index outside the frame. */
static void test_verifier_checks_frame_bounds(void)
{
    SolChunk chunk;

    /* slot_count smaller than self + parameters. */
    sol_chunk_init(&chunk);
    sol_chunk_add_name(&chunk, "x", 1);
    SolMethod *bad = sol_method_new("bad", 3, 2);
    bad->slot_count = 2;                          /* needs at least 3 */
    sol_chunk_write(&bad->chunk, OP_NIL, 1);
    sol_chunk_write(&bad->chunk, OP_RETURN, 1);
    sol_chunk_add_method(&chunk, bad);
    sol_chunk_write(&chunk, OP_HALT, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* A local slot past the end of the frame. */
    sol_chunk_init(&chunk);
    SolMethod *over = sol_method_new("over", 4, 0);
    over->slot_count = 1;                         /* only self */
    sol_chunk_write(&over->chunk, OP_LOCAL, 1);
    sol_chunk_write(&over->chunk, 5, 1);          /* out of range */
    sol_chunk_write(&over->chunk, OP_RETURN, 1);
    sol_chunk_add_method(&chunk, over);
    sol_chunk_write(&chunk, OP_HALT, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);

    /* The top-level chunk has no frame slots at all. */
    sol_chunk_init(&chunk);
    sol_chunk_write(&chunk, OP_LOCAL, 1);
    sol_chunk_write(&chunk, 0, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);
    assert(sol_chunk_verify(&chunk) == SOL_SER_MALFORMED);
    sol_chunk_free(&chunk);
}

int main(void)
{
    test_round_trip_preserves_everything();
    test_methods_round_trip();
    test_verifier_checks_frame_bounds();
    test_float_bits_are_exact();
    test_duplicate_names_keep_their_indices();
    test_rejects_files_it_should_not_run();
    test_verifier_rejects_unsafe_code();
    printf("test_serialize: ok\n");
    return 0;
}
