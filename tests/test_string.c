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
        sol_value_render(&vm, original, &text);

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

/* ASCII case, by explicit range rather than toupper -- which follows the C
   locale, so the same program could answer differently on two machines. */
static void test_case(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"ff\":asUppercase."
        "b := \"Hello, World!\":asUppercase."
        "c := \"Hello, World!\":asLowercase."
        "d := \"\":asUppercase."
        "e := \"123 @#\":asUppercase."
        "f := \"ALREADY\":asUppercase."
        "g := \"MiXeD\":asLowercase.") == SOL_OK);
    assert(is_text(global(&vm, "a"), "FF"));
    assert(is_text(global(&vm, "b"), "HELLO, WORLD!"));
    assert(is_text(global(&vm, "c"), "hello, world!"));
    assert(is_text(global(&vm, "d"), ""));
    assert(is_text(global(&vm, "e"), "123 @#"));      /* nothing to change */
    assert(is_text(global(&vm, "f"), "ALREADY"));
    assert(is_text(global(&vm, "g"), "mixed"));
    sol_chunk_free(&chunk);

    /* The receiver is untouched -- strings are immutable. */
    assert(run(&vm, &chunk,
        "s := \"abc\". t := s:asUppercase.") == SOL_OK);
    assert(is_text(global(&vm, "s"), "abc"));
    assert(is_text(global(&vm, "t"), "ABC"));
    sol_chunk_free(&chunk);

    /* What this was wanted for: uppercase hex. */
    assert(run(&vm, &chunk, "h := #255:asBase(#16):asUppercase.") == SOL_OK);
    assert(is_text(global(&vm, "h"), "FF"));
    sol_chunk_free(&chunk);

    /* Bytes outside ASCII pass through rather than being mangled. */
    assert(run(&vm, &chunk,
        "u := \"caf\xc3\xa9\":asUppercase. n := u:size.") == SOL_OK);
    assert(is_text(global(&vm, "u"), "CAF\xc3\xa9"));
    assert(SOL_AS_INT(global(&vm, "n")) == 5);        /* size counts bytes */
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "\"a\":asUppercase(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Every piece is kept, so there are always occurrences + 1 of them. A separator
   at either end or two together gives an empty string where the missing piece
   would be, which is what makes the answer predictable. */
static void test_split(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "p := \"a,b,c\":split(\",\"). n := p:size."
        "one := p:at(#1). three := p:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(is_text(global(&vm, "one"), "a"));
    assert(is_text(global(&vm, "three"), "c"));
    sol_chunk_free(&chunk);

    /* Two separators together leave an empty piece between them. */
    assert(run(&vm, &chunk,
        "p := \"a,,b\":split(\",\"). n := p:size. middle := p:at(#2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(is_text(global(&vm, "middle"), ""));
    sol_chunk_free(&chunk);

    /* And so do separators at the ends. */
    assert(run(&vm, &chunk,
        "p := \",a,\":split(\",\"). n := p:size."
        "first := p:at(#1). last := p:at(#3).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(is_text(global(&vm, "first"), ""));
    assert(is_text(global(&vm, "last"), ""));
    sol_chunk_free(&chunk);

    /* No occurrence is one piece: the whole string. Which keeps the rule -- no
       occurrences, one piece -- rather than making a special case of it. */
    assert(run(&vm, &chunk,
        "p := \"abc\":split(\",\"). n := p:size. whole := p:at(#1).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 1);
    assert(is_text(global(&vm, "whole"), "abc"));
    sol_chunk_free(&chunk);

    /* The empty string is one empty piece, by the same rule. */
    assert(run(&vm, &chunk,
        "p := \"\":split(\",\"). n := p:size. only := p:at(#1).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 1);
    assert(is_text(global(&vm, "only"), ""));
    sol_chunk_free(&chunk);

    /* A separator of more than one character. */
    assert(run(&vm, &chunk,
        "p := \"a--b--c\":split(\"--\"). n := p:size. second := p:at(#2).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    assert(is_text(global(&vm, "second"), "b"));
    sol_chunk_free(&chunk);

    /* Overlapping runs are taken left to right and not reconsidered. */
    assert(run(&vm, &chunk,
        "p := \"aaaa\":split(\"aa\"). n := p:size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);     /* "", "", "" */
    sol_chunk_free(&chunk);

    /* Nothing can be looked for: every position holds the empty string. */
    assert(run(&vm, &chunk, "\"a\":split(\"\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"a\":split(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"a\":split(\"a\", \"b\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* Nil for no match rather than #0: indices start at #1, so #0 would be a second
   way of saying "nothing" beside the one the language has. */
static void test_index_of(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"hello\":indexOf(\"h\")."
        "b := \"hello\":indexOf(\"ll\")."
        "c := \"hello\":indexOf(\"o\")."
        "d := \"hello\":indexOf(\"z\")."
        "e := \"hello\":indexOf(\"hello\").") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "b")) == 3);
    assert(SOL_AS_INT(global(&vm, "c")) == 5);
    assert(SOL_IS_NIL(global(&vm, "d")));
    assert(SOL_AS_INT(global(&vm, "e")) == 1);
    sol_chunk_free(&chunk);

    /* The first occurrence, not any later one. */
    assert(run(&vm, &chunk, "at := \"abcabc\":indexOf(\"bc\").") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "at")) == 2);
    sol_chunk_free(&chunk);

    /* Longer than the string it is looked for in. */
    assert(run(&vm, &chunk, "at := \"ab\":indexOf(\"abc\").") == SOL_OK);
    assert(SOL_IS_NIL(global(&vm, "at")));
    sol_chunk_free(&chunk);

    /* Which is the answer `at` and `copyFrom` are built to take. */
    assert(run(&vm, &chunk,
        "s := \"key=value\". i := s:indexOf(\"=\")."
        "key := s:copyFrom(#1, i:sub(#1))."
        "value := s:copyFrom(i:add(#1), s:size).") == SOL_OK);
    assert(is_text(global(&vm, "key"), "key"));
    assert(is_text(global(&vm, "value"), "value"));
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "\"a\":indexOf(\"\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"a\":indexOf(nil).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* **From a position**, which is what a second search in the same string needs
   and what it could not say before (6.37). Without it the only way on was to
   copy what was left of the string, which is quadratic in a loop -- and two
   shipped files were writing exactly that. */
static void test_index_of_from_a_position(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "first := \"banana\":indexOf(\"an\")."
        "second := \"banana\":indexOf(\"an\", #3)."
        "none := \"banana\":indexOf(\"an\", #5)."
        /* Starting where it already is finds it there. */
        "here := \"banana\":indexOf(\"an\", #2)."
        /* One past the end is a position, and the answer there is nil rather
           than an error -- the rule `copyFrom` has, so a loop that walks off
           the end gets an answer instead of a fault. */
        "past := \"banana\":indexOf(\"a\", #7).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "first")) == 2);
    assert(SOL_AS_INT(global(&vm, "second")) == 4);
    assert(SOL_IS_NIL(global(&vm, "none")));
    assert(SOL_AS_INT(global(&vm, "here")) == 2);
    assert(SOL_IS_NIL(global(&vm, "past")));
    sol_chunk_free(&chunk);

    /* The walk it exists for: every occurrence, without copying anything. */
    assert(run(&vm, &chunk,
        "text := \"a-b-c-d\"."
        "count := #0."
        "at := text:indexOf(\"-\")."
        "{ at:notNil }:whileTrue({"
        "    count := count:add(#1)."
        "    at := text:indexOf(\"-\", at:add(#1)) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "count")) == 3);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "\"banana\":indexOf(\"a\", #8).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"banana\":indexOf(\"a\", #0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"banana\":indexOf(\"a\", 2.0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"banana\":indexOf(\"a\", #1, #2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  indexOf searches from a position, and says so when it cannot\n");
}

/* Both ends included and both one-based, so `copyFrom(#i, #i)` is `at(#i)`. */
static void test_copy_from(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "s := \"hello\"."
        "mid := s:copyFrom(#2, #4)."
        "all := s:copyFrom(#1, #5)."
        "one := s:copyFrom(#3, #3)."
        "same := s:at(#3).") == SOL_OK);
    assert(is_text(global(&vm, "mid"), "ell"));
    assert(is_text(global(&vm, "all"), "hello"));
    assert(is_text(global(&vm, "one"), "l"));
    assert(is_text(global(&vm, "same"), "l"));
    sol_chunk_free(&chunk);

    /* An empty result has one spelling: `to` exactly one before `from`. */
    assert(run(&vm, &chunk,
        "s := \"hello\"."
        "front := s:copyFrom(#1, #0)."
        "back := s:copyFrom(#6, #5)."
        "middle := s:copyFrom(#3, #2).") == SOL_OK);
    assert(is_text(global(&vm, "front"), ""));
    assert(is_text(global(&vm, "back"), ""));
    assert(is_text(global(&vm, "middle"), ""));
    sol_chunk_free(&chunk);

    /* The empty string can be cut, but only into itself. */
    assert(run(&vm, &chunk, "e := \"\":copyFrom(#1, #0).") == SOL_OK);
    assert(is_text(global(&vm, "e"), ""));
    sol_chunk_free(&chunk);

    /* Anything further apart than that is a mistake, not a wider empty. */
    assert(run(&vm, &chunk, "\"hello\":copyFrom(#4, #2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"hello\":copyFrom(#0, #2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"hello\":copyFrom(#7, #7).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"hello\":copyFrom(#2, #6).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"hello\":copyFrom(1.0, #2).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"hello\":copyFrom(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* The pieces are strings like any other, and nothing about them refers back to
   the string they were cut from -- which is what lets that one be collected
   while they are still in use. */
static void test_pieces_outlive_the_string_they_came_from(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "pieces := \"alpha,beta,gamma\":split(\",\")."
        "joined := pieces:at(#1):concat(pieces:at(#3)).") == SOL_OK);
    sol_gc_collect(&vm);
    assert(is_text(global(&vm, "joined"), "alphagamma"));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* `trim`, wanted by the first program that read another program's output: `wc`
   pads its number with spaces and `asInteger` refuses anything but a number. */
/* `replace` takes **every** occurrence, and the reason is not taste: the idiom
   it replaces is `split` then `join`, which replaces all of them. A message that
   did the first would not be shorter than the idiom -- it would mean something
   different, and tidying an old program up would change what it did. */
static void test_replace(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "a := \"a-b-c\":replace(\"-\", \"+\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "a+b+c"));
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "a := \"one two one\":replace(\"one\", \"1\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "1 two 1"));
    sol_chunk_free(&chunk);

    /* Forward and non-overlapping, the way `split` scans: each match resumes
       after the one before rather than being reconsidered. */
    assert(run(&vm, &chunk, "a := \"aaa\":replace(\"aa\", \"b\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "ba"));
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "a := \"aaaa\":replace(\"aa\", \"b\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "bb"));
    sol_chunk_free(&chunk);

    /* An empty replacement is how a program deletes; a longer one grows the
       string, which is the case the length arithmetic has to get right. */
    assert(run(&vm, &chunk, "a := \"a,b,c\":replace(\",\", \"\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "abc"));
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "a := \"x\":replace(\"x\", \"much longer\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "much longer"));
    sol_chunk_free(&chunk);

    /* A needle of more than one character, and one at either end. */
    assert(run(&vm, &chunk, "a := \"--a--\":replace(\"--\", \"+\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "+a+"));
    sol_chunk_free(&chunk);

    /* Nothing found answers the receiver itself -- immutable, so that is the
       same string rather than a copy of it, and nothing is allocated. */
    assert(run(&vm, &chunk, "a := \"hello\":replace(\"z\", \"!\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "hello"));
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "a := \"\":replace(\"x\", \"y\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), ""));
    sol_chunk_free(&chunk);

    /* And the receiver is not touched, which is what makes it a value. */
    assert(run(&vm, &chunk,
        "s := \"keep me\". t := s:replace(\"keep\", \"drop\").") == SOL_OK);
    assert(is_text(global(&vm, "s"), "keep me"));
    assert(is_text(global(&vm, "t"), "drop me"));
    sol_chunk_free(&chunk);

    /* Bytes, like every other string message here: 2.13 showing through rather
       than a decision this one took. */
    assert(run(&vm, &chunk, "a := \"caf\xc3\xa9\":replace(\"caf\", \"CAF\").") == SOL_OK);
    assert(is_text(global(&vm, "a"), "CAF\xc3\xa9"));
    sol_chunk_free(&chunk);

    /* Nothing can be looked for, the way `split` and `indexOf` refuse it. */
    assert(run(&vm, &chunk, "\"a\":replace(\"\", \"b\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"a\":replace(#1, \"b\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"a\":replace(\"a\", #1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "\"a\":replace(\"a\").") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

static void test_trim(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"   spaced   \":trim."
        "b := \"  42\\n\":trim:asInteger."
        "c := \"\":trim."
        "d := \"    \":trim."
        "e := \"none\":trim."
        "f := \"a b\":trim."                 /* the middle is left alone */
        "g := \"\\n\\tmixed\\r\":trim.") == SOL_OK);
    assert(is_text(global(&vm, "a"), "spaced"));
    assert(SOL_AS_INT(global(&vm, "b")) == 42);
    assert(is_text(global(&vm, "c"), ""));
    assert(is_text(global(&vm, "d"), ""));
    assert(is_text(global(&vm, "e"), "none"));
    assert(is_text(global(&vm, "f"), "a b"));
    assert(is_text(global(&vm, "g"), "mixed"));
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
    printf("  trim takes the space off both ends and leaves the middle\n");
}

int main(void)
{
    test_case();
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
    test_split();
    test_replace();
    test_index_of();
    test_index_of_from_a_position();
    test_copy_from();
    test_pieces_outlive_the_string_they_came_from();
    test_trim();
    printf("test_string: ok\n");
    return 0;
}
