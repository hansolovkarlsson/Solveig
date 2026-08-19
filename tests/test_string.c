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

/* Escapes, so a string can hold a quote at last. */
static void test_escapes(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "q := \"a\\\"b\". qn := q:size."
        "b := \"back\\\\slash\". bn := b:size."
        "n := \"one\\ntwo\". nn := n:size."
        "t := \"a\\tb\". tn := t:size."
        "r := \"a\\rb\". rn := r:size.") == SOL_OK);
    assert(is_text(global(&vm, "q"), "a\"b"));
    assert(SOL_AS_INT(global(&vm, "qn")) == 3);
    assert(is_text(global(&vm, "b"), "back\\slash"));
    assert(SOL_AS_INT(global(&vm, "bn")) == 10);
    assert(is_text(global(&vm, "n"), "one\ntwo"));
    assert(SOL_AS_INT(global(&vm, "nn")) == 7);
    assert(is_text(global(&vm, "t"), "a\tb"));
    assert(SOL_AS_INT(global(&vm, "tn")) == 3);
    assert(is_text(global(&vm, "r"), "a\rb"));
    assert(SOL_AS_INT(global(&vm, "rn")) == 3);
    sol_chunk_free(&chunk);

    /* An unknown escape is a mistake, not a literal backslash. */
    assert(run(&vm, &chunk, "x := \"a\\qb\".") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);
    /* And a string still has to end. */
    assert(run(&vm, &chunk, "x := \"unterminated") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Rendering puts the escapes back, or a string holding a quote would render as
   text that no longer reads as one string. */
static void test_rendering_escapes(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "q := \"a\\\"b\":asString."          /* asString gives the characters */
        "arr := [\"a\\\"b\", \"one\\ntwo\"]:asString.") == SOL_OK);
    assert(is_text(global(&vm, "q"), "a\"b"));
    /* Inside a composite, the literal form is used -- escapes and all. */
    assert(is_text(global(&vm, "arr"), "[\"a\\\"b\", \"one\\ntwo\"]"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A string's rendered form must compile back to the same string, escapes and
   all -- the same round-trip that floats now hold to. */
static void test_escaped_text_compiles_back(void)
{
    const char *sources[] = {
        "\"plain\"",
        "\"a\\\"b\"",
        "\"back\\\\slash\"",
        "\"one\\ntwo\"",
        "\"tab\\there\"",
        "\"\"",
        "\"quote at end\\\"\"",
    };

    for (size_t i = 0; i < sizeof sources / sizeof sources[0]; i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        char first[128];
        snprintf(first, sizeof first, "v := %s.", sources[i]);
        assert(run(&vm, &chunk, first) == SOL_OK);

        SolValue original = global(&vm, "v");
        assert(SOL_IS_STRING(original));

        SolText text;
        sol_text_init(&text);
        sol_value_render(original, &text);

        SolVM again; sol_vm_init(&again);
        SolChunk second;
        char round[256];
        snprintf(round, sizeof round, "v := %s.", text.chars);
        assert(run(&again, &second, round) == SOL_OK);

        SolValue back = global(&again, "v");
        assert(SOL_IS_STRING(back));
        assert(SOL_AS_STRING(back)->length == SOL_AS_STRING(original)->length);
        assert(memcmp(SOL_AS_STRING(back)->chars, SOL_AS_STRING(original)->chars,
                      (size_t)SOL_AS_STRING(original)->length) == 0);

        sol_text_free(&text);
        sol_chunk_free(&second);
        sol_vm_free(&again);
        sol_chunk_free(&chunk);
        sol_vm_free(&vm);
    }
}

int main(void)
{
    test_escapes();
    test_rendering_escapes();
    test_escaped_text_compiles_back();
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
