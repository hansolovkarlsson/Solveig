/* Symbols: interned names, and the weak table that lets them die. */
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

static void test_literals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 'foo. n := a:size. t := a:asString.") == SOL_OK);
    assert(SOL_IS_SYMBOL(global(&vm, "a")));
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(is_text(global(&vm, "t"), "foo"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Interning is the point: two symbols spelling the same thing are one symbol,
   which is why equality can be a pointer comparison. A symbol made from a string
   at run time must find the one the compiler already made. */
static void test_interning(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 'foo. b := 'foo. c := 'bar."
        "same := a:equals(b)."
        "diff := a:equals(c)."
        "built := \"foo\":asSymbol."
        "found := built:equals(a).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    assert(SOL_AS_BOOL(global(&vm, "diff")) == false);
    assert(SOL_AS_BOOL(global(&vm, "found")) == true);
    /* Identity, not merely equality: interning means one cell. */
    assert(SOL_AS_SYMBOL(global(&vm, "a")) == SOL_AS_SYMBOL(global(&vm, "b")));
    assert(SOL_AS_SYMBOL(global(&vm, "built")) == SOL_AS_SYMBOL(global(&vm, "a")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A symbol is a name, not text: the two never compare equal. */
static void test_symbol_is_not_a_string(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 'foo:equals(\"foo\")."
        "b := \"foo\":equals('foo)."
        "c := 'foo:asString:equals(\"foo\").") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "a")) == false);
    assert(SOL_AS_BOOL(global(&vm, "b")) == false);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* print shows the literal form; display writes the name. */
static void test_rendering(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 'foo:asString."
        "b := ['a, 'b]:asString."
        "c := \"tag {}\":fill(['running]).") == SOL_OK);
    assert(is_text(global(&vm, "a"), "foo"));          /* asString: the name */
    assert(is_text(global(&vm, "b"), "['a, 'b]"));     /* rendered: the literal */
    assert(is_text(global(&vm, "c"), "tag running"));  /* fill asks for asString */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The intern table holds symbols weakly. Without that, a name mentioned once
   would live as long as the VM -- and worse, every collection would have to mark
   every symbol ever interned, which turns the loop below quadratic. */
static void test_unreachable_symbols_are_reclaimed(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);

    assert(run(&vm, &chunk,
        "i := #0."
        "{ i:lessThan(#2000) }:whileTrue({ i := i:add(#1). i:asString:asSymbol. }).")
        == SOL_OK);

    sol_gc_collect(&vm);
    assert(sol_gc_live_count(&vm) <= baseline + 64);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Pruning must not drop a live symbol, nor leave an entry pointing at a swept
   one -- re-interning after a collection has to find the same symbol back. */
static void test_a_kept_symbol_survives_and_stays_the_same(void)
{
    SolVM vm; sol_vm_init(&vm);
    vm.gc_stress = true;
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "kept := 'alpha."
        "i := #0."
        "{ i:lessThan(#300) }:whileTrue({ i := i:add(#1). i:asString:asSymbol. })."
        "again := \"alpha\":asSymbol."
        "same := again:equals(kept).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    assert(SOL_AS_SYMBOL(global(&vm, "again")) == SOL_AS_SYMBOL(global(&vm, "kept")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Symbols work as tags, which is what they are useful for before reflection. */
static void test_symbols_as_tags(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "state := 'running."
        "r := state:equals('running):ifElse({ \"go\" }, { \"stop\" })."
        "state := 'halted."
        "s := state:equals('running):ifElse({ \"go\" }, { \"stop\" }).") == SOL_OK);
    assert(is_text(global(&vm, "r"), "go"));
    assert(is_text(global(&vm, "s"), "stop"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A symbol literal rides in the chunk's interned text, so it survives the file. */
static void test_round_trip(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("a := 'greeting. t := a:asString.", &chunk));

    const char *path = "build/tests/test_symbol.tmp.sob";
    assert(sol_chunk_save(&chunk, path) == SOL_SER_OK);

    SolChunk loaded;
    assert(sol_chunk_load(&loaded, path) == SOL_SER_OK);

    SolVM vm; sol_vm_init(&vm);
    assert(sol_vm_run(&vm, &loaded) == SOL_OK);
    assert(SOL_IS_SYMBOL(global(&vm, "a")));
    assert(is_text(global(&vm, "t"), "greeting"));

    sol_vm_free(&vm);
    sol_chunk_free(&loaded);
    sol_chunk_free(&chunk);
    remove(path);
}

static void test_errors(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "'foo:concat('bar).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "'foo:asUppercase.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "x := '.") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Interning is what makes `equals` a pointer comparison and exactly what makes
   the pointers say nothing about order, so `lessThan` compares the text. It is
   the one symbol operation that has to look at the characters, and it is what
   lets an array of symbols sort. */
static void test_symbols_order_by_text(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := 'apple:lessThan('banana)."
        "b := 'banana:lessThan('apple)."
        "c := 'a:lessOrEqual('a)."
        "d := 'a:greaterOrEqual('a)."
        "e := 'a:lessThan('a)."
        "f := 'ab:greaterThan('a).") == SOL_OK);   /* a prefix sorts first */
    assert(SOL_AS_BOOL(global(&vm, "a")) == true);
    assert(SOL_AS_BOOL(global(&vm, "b")) == false);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);
    assert(SOL_AS_BOOL(global(&vm, "d")) == true);
    assert(SOL_AS_BOOL(global(&vm, "e")) == false);
    assert(SOL_AS_BOOL(global(&vm, "f")) == true);
    sol_chunk_free(&chunk);

    /* Which is the point: `sorted` with no block sends `lessThan`. */
    assert(run(&vm, &chunk,
        "s := ['pear, 'apple, 'fig]:sorted."
        "one := s:at(#1). two := s:at(#2). three := s:at(#3).") == SOL_OK);
    assert(strcmp(SOL_AS_SYMBOL(global(&vm, "one"))->chars, "apple") == 0);
    assert(strcmp(SOL_AS_SYMBOL(global(&vm, "two"))->chars, "fig") == 0);
    assert(strcmp(SOL_AS_SYMBOL(global(&vm, "three"))->chars, "pear") == 0);
    sol_chunk_free(&chunk);

    /* Strict about the other side, like every other comparison. */
    assert(run(&vm, &chunk, "'a:lessThan(\"a\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_literals();
    test_interning();
    test_symbol_is_not_a_string();
    test_rendering();
    test_unreachable_symbols_are_reclaimed();
    test_a_kept_symbol_survives_and_stays_the_same();
    test_symbols_as_tags();
    test_round_trip();
    test_errors();
    test_symbols_order_by_text();
    printf("test_symbol: ok\n");
    return 0;
}
