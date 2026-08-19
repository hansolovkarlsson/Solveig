/* Strings: immutable, compared by value, and holding no references. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/serialize.h"
#include "solum/vm.h"

static SolResult run(SolVM *vm, SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    if (!sol_compile(source, chunk)) return SOL_COMPILE_ERROR;
    return sol_vm_run(vm, chunk);
}

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

static void test_literals_and_size(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "s := \"hello\". n := s:size."
        "e := \"\". m := e:size.") == SOL_OK);
    assert(is_text(global(&vm, "s"), "hello"));
    assert(SOL_AS_INT(global(&vm, "n")) == 5);
    assert(is_text(global(&vm, "e"), ""));
    assert(SOL_AS_INT(global(&vm, "m")) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A string is immutable, so it is a value: equality compares contents. That is
   the opposite of an array, where two equal-looking arrays are two arrays. */
static void test_equality_is_by_value(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "same := \"hi\":equals(\"hi\")."
        "diff := \"hi\":equals(\"ho\")."
        "len := \"hi\":equals(\"hix\")."
        "cross := \"hi\":equals(#1)."
        /* built at run time rather than written as a literal */
        "built := \"h\":concat(\"i\"):equals(\"hi\")."
        /* and the contrast: arrays compare by identity */
        "arrays := [#1]:equals([#1]).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    assert(SOL_AS_BOOL(global(&vm, "diff")) == false);
    assert(SOL_AS_BOOL(global(&vm, "len")) == false);
    assert(SOL_AS_BOOL(global(&vm, "cross")) == false);
    assert(SOL_AS_BOOL(global(&vm, "built")) == true);
    assert(SOL_AS_BOOL(global(&vm, "arrays")) == false);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_concat(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"hello\"."
        "b := a:concat(\", world\")."
        "n := b:size.") == SOL_OK);
    assert(is_text(global(&vm, "b"), "hello, world"));
    assert(SOL_AS_INT(global(&vm, "n")) == 12);
    assert(is_text(global(&vm, "a"), "hello"));   /* the receiver is untouched */
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "e := \"\":concat(\"\").") == SOL_OK);
    assert(is_text(global(&vm, "e"), ""));
    sol_chunk_free(&chunk);

    /* Strict, like arithmetic: no silent conversion. */
    assert(run(&vm, &chunk, "\"a\":concat(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* One-based, like arrays, and answering a one-character string since there is
   no character type. */
static void test_at(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "s := \"abc\". first := s:at(#1). last := s:at(#3).") == SOL_OK);
    assert(is_text(global(&vm, "first"), "a"));
    assert(is_text(global(&vm, "last"), "c"));
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "\"ab\":at(#0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"ab\":at(#3).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"\":at(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"ab\":at(1.0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Strings go in arrays and through the iteration protocol like anything else. */
static void test_strings_in_collections(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "xs := [\"a\", \"b\", \"c\"]."
        "loud := xs:collect({ s | s:concat(\"!\") })."
        "one := loud:at(#1). three := loud:at(#3)."
        "kept := xs:select({ s | s:equals(\"b\") })."
        "n := kept:size. only := kept:at(#1).") == SOL_OK);
    assert(is_text(global(&vm, "one"), "a!"));
    assert(is_text(global(&vm, "three"), "c!"));
    assert(SOL_AS_INT(global(&vm, "n")) == 1);
    assert(is_text(global(&vm, "only"), "b"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A string holds bytes, not values, so it has no outgoing edges -- but it is
   still a cell that must be reached and must be reclaimed. */
static void test_collection(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* Reachable only through an array. */
    assert(run(&vm, &chunk, "held := [\"alpha\":concat(\"!\")].") == SOL_OK);
    sol_gc_collect(&vm);
    sol_gc_collect(&vm);
    SolValue held = global(&vm, "held");
    assert(SOL_IS_ARRAY(held));
    assert(is_text(SOL_AS_ARRAY(held)->items[0], "alpha!"));
    sol_chunk_free(&chunk);

    /* And discarded strings go away. */
    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);
    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#300) }:whileTrue({ i := i:add(#1). \"x\":concat(\"y\"). }).")
        == SOL_OK);
    sol_gc_collect(&vm);
    assert(sol_gc_live_count(&vm) <= baseline + 8);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Literals live in the chunk's interned text, shared with selectors and global
   names -- so a string whose bytes match a selector must still be a string. */
static void test_literal_text_is_shared_safely(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "s := \"print\". n := s:size. same := s:equals(\"print\").") == SOL_OK);
    assert(is_text(global(&vm, "s"), "print"));
    assert(SOL_AS_INT(global(&vm, "n")) == 5);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Literals survive the .sob round trip, since their bytes ride in the text
   table that was already serialised. */
static void test_round_trip(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("s := \"hello, world\". s:print.", &chunk));

    const char *path = "build/tests/test_string.tmp.sob";
    assert(sol_chunk_save(&chunk, path) == SOL_SER_OK);

    SolChunk loaded;
    assert(sol_chunk_load(&loaded, path) == SOL_SER_OK);
    assert(loaded.count == chunk.count);
    assert(memcmp(loaded.code, chunk.code, (size_t)chunk.count) == 0);

    SolVM vm; sol_vm_init(&vm);
    assert(sol_vm_run(&vm, &loaded) == SOL_OK);
    assert(is_text(global(&vm, "s"), "hello, world"));

    sol_vm_free(&vm);
    sol_chunk_free(&loaded);
    sol_chunk_free(&chunk);
    remove(path);
}

int main(void)
{
    test_literals_and_size();
    test_equality_is_by_value();
    test_concat();
    test_at();
    test_strings_in_collections();
    test_collection();
    test_literal_text_is_shared_safely();
    test_round_trip();
    printf("test_string: ok\n");
    return 0;
}
