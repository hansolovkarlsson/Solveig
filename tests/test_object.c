/* User-defined objects: creation, delegation, and what a "class" turns out to be. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
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

static void test_new_makes_a_distinct_object(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. b := object:new."
        "same := a:equals(a). other := a:equals(b).") == SOL_OK);
    assert(SOL_IS_OBJ(global(&vm, "a")));
    assert(SOL_IS_OBJ(global(&vm, "b")));
    assert(SOL_AS_OBJ(global(&vm, "a")) != SOL_AS_OBJ(global(&vm, "b")));
    assert(SOL_AS_BOOL(global(&vm, "same")) == true);
    assert(SOL_AS_BOOL(global(&vm, "other")) == false);   /* identity, not shape */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A slot on the prototype is a default every instance sees. */
static void test_slots_are_inherited(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:x := #0. point:y := #0."
        "p := point:new."
        "px := p:x. py := p:y.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "px")) == 0);
    assert(SOL_AS_INT(global(&vm, "py")) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Assigning on an instance makes the instance's own slot rather than writing
   through to the prototype -- otherwise one instance would change all of them. */
static void test_assignment_shadows_rather_than_writes_through(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. base:v := #1."
        "a := base:new. b := base:new."
        "a:v := #99."
        "av := a:v. bv := b:v. basev := base:v.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "av")) == 99);
    assert(SOL_AS_INT(global(&vm, "bv")) == 1);
    assert(SOL_AS_INT(global(&vm, "basev")) == 1);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A method is a slot holding a block, and `self` is whoever was sent to. */
static void test_methods_receive_the_instance_as_self(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:x := #0. point:y := #0."
        "point:sum := { self:x:add(self:y) }."
        "point:make := { a, b | | p | p := self:new. p:x := a. p:y := b. p }."
        "p := point:make(#3, #4)."
        "s := p:sum."
        "d := point:new:sum.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "s")) == 7);
    assert(SOL_AS_INT(global(&vm, "d")) == 0);   /* the defaults still apply */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Delegation chains, and a nearer slot wins. */
static void test_inheritance_and_override(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "animal := object:new."
        "animal:name := \"animal\". animal:speak := { \"...\" }."
        "animal:describe := { self:name:concat(\" says \"):concat(self:speak) }."
        "dog := animal:new."
        "dog:name := \"dog\". dog:speak := { \"woof\" }."
        "rex := dog:new. rex:name := \"rex\"."
        "a := animal:describe. d := dog:describe. r := rex:describe.") == SOL_OK);

    const SolString *a = SOL_AS_STRING(global(&vm, "a"));
    const SolString *d = SOL_AS_STRING(global(&vm, "d"));
    const SolString *r = SOL_AS_STRING(global(&vm, "r"));
    assert(memcmp(a->chars, "animal says ...", 15) == 0);
    assert(memcmp(d->chars, "dog says woof", 13) == 0);
    /* `describe` comes from animal, `speak` from dog, `name` from rex. */
    assert(memcmp(r->chars, "rex says woof", 13) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The default `print` is a fallback, not a fixture. */
static void test_print_can_be_overridden(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "thing := object:new."
        "thing:print := { \"a thing\" }."
        "r := thing:new:print.") == SOL_OK);
    assert(SOL_IS_STRING(global(&vm, "r")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_errors(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* A value is not an object and has no slots of its own. */
    assert(run(&vm, &chunk, "#1:new.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "x := #1. x:field := #2.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    /* An object understands only what it or its prototypes hold. */
    assert(run(&vm, &chunk, "object:new:nosuch.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

/* An object's slots and its prototype are both tracing edges. */
static void test_objects_are_collected(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "point := object:new."
        "point:label := \"origin\"."
        "kept := point:new."
        "kept:tag := [\"a\", \"b\"].") == SOL_OK);

    sol_gc_collect(&vm);
    sol_gc_collect(&vm);

    /* Reached through the instance's own slot, and through its prototype. */
    SolChunk second;
    assert(run(&vm, &second,
        "n := kept:tag:size. l := kept:label.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_IS_STRING(global(&vm, "l")));
    sol_chunk_free(&second);

    /* Objects nobody keeps go away. */
    sol_gc_collect(&vm);
    int baseline = sol_gc_live_count(&vm);
    SolChunk third;
    assert(run(&vm, &third,
        "i := #0."
        "{ i:lessThan(#300) }:whileTrue({ i := i:add(#1). object:new. }).") == SOL_OK);
    sol_gc_collect(&vm);
    assert(sol_gc_live_count(&vm) <= baseline + 8);

    sol_chunk_free(&third);
    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* An override reaching the version it overrides. Naming the ancestor directly
   would send to *it*, so `self` inside would become the ancestor; `via` starts
   the lookup there while leaving the receiver alone. */
static void test_via_keeps_the_receiver(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "animal := object:new."
        "animal:name := \"animal\"."
        "animal:intro := { \"I am \":concat(self:name) }."
        "dog := animal:new."
        "dog:name := \"dog\"."
        "dog:intro := { self:via(animal):intro:concat(\"!\") }."
        "rex := dog:new. rex:name := \"rex\"."
        "a := animal:intro. d := dog:intro. r := rex:intro.") == SOL_OK);

    assert(memcmp(SOL_AS_STRING(global(&vm, "a"))->chars, "I am animal", 11) == 0);
    assert(memcmp(SOL_AS_STRING(global(&vm, "d"))->chars, "I am dog!", 9) == 0);
    /* The whole point: the ancestor's method sees rex, not animal. */
    assert(memcmp(SOL_AS_STRING(global(&vm, "r"))->chars, "I am rex!", 9) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Each level extends the one above, however deep the receiver. */
static void test_via_chains(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. a:tag := { \"a\" }."
        "b := a:new. b:tag := { self:via(a):tag:concat(\"b\") }."
        "c := b:new. c:tag := { self:via(b):tag:concat(\"c\") }."
        "ra := a:new:tag. rb := b:new:tag. rc := c:new:tag.") == SOL_OK);
    assert(memcmp(SOL_AS_STRING(global(&vm, "ra"))->chars, "a", 1) == 0);
    assert(memcmp(SOL_AS_STRING(global(&vm, "rb"))->chars, "ab", 2) == 0);
    assert(memcmp(SOL_AS_STRING(global(&vm, "rc"))->chars, "abc", 3) == 0);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A delegate carries arguments through like any other send, and answers data
   slots as readily as methods. */
static void test_via_passes_arguments_and_reads_slots(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new."
        "base:v := #7."
        "base:plus := { n | self:v:add(n) }."
        "kid := base:new."
        "kid:v := #100."
        "kid:plus := { n | self:via(base):plus(n):add(#1) }."
        "r := kid:new:plus(#5)."
        "slot := kid:new:via(base):v.") == SOL_OK);
    /* self:v is the instance's, inherited from kid, so 100 + 5 + 1. */
    assert(SOL_AS_INT(global(&vm, "r")) == 106);
    /* Reading through a delegate finds base's slot, not kid's. */
    assert(SOL_AS_INT(global(&vm, "slot")) == 7);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_parent(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. b := a:new. c := b:new."
        "one := c:parent:equals(b)."
        "two := c:parent:parent:equals(a)."
        "three := a:parent:equals(object)."
        "root := object:parent.") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "one")) == true);
    assert(SOL_AS_BOOL(global(&vm, "two")) == true);
    assert(SOL_AS_BOOL(global(&vm, "three")) == true);
    assert(SOL_IS_NIL(global(&vm, "root")));      /* the chain ends */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Assigning `parent` binds an ordinary slot that shadows the message. It does
   *not* re-parent, because the delegation link is an internal pointer rather
   than a slot -- which is what stops a program corrupting dispatch, and is also
   what makes this the one assignment that looks like it did something and did
   not. Pinned so it stays a known shape. */
static void test_assigning_parent_shadows_rather_than_reparents(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := object:new. a:tag := #1."
        "b := object:new. b:tag := #2."
        "kid := a:new."
        "before := kid:tag."
        "kid:parent := b."                 /* looks like re-parenting */
        "after := kid:tag."                /* but the chain is unchanged */
        "shadowed := kid:parent:equals(b)."
        "real := kid:tag:equals(#1).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "before")) == 1);
    assert(SOL_AS_INT(global(&vm, "after")) == 1);   /* still a's tag */
    assert(SOL_AS_BOOL(global(&vm, "shadowed")));    /* the slot answers */
    assert(SOL_AS_BOOL(global(&vm, "real")));

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* And the reason it matters: it is how someone tries to subclass a built-in,
   which cannot work -- an unboxed value's class is chosen by its type tag, so
   there is nowhere to record a different one. */
static void test_a_built_in_cannot_be_subclassed_this_way(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "o := object:new. o:parent := integer. o:add(#1).") == SOL_RUNTIME_ERROR);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* One hierarchy: every built-in class delegates to `object`, so "everything is
   an object" holds of the type graph and not only of the slogan. */
static void test_every_value_is_an_object(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #45:isKindOf(object).      b := 1.5:isKindOf(object)."
        "c := \"s\":isKindOf(object).      d := [#1]:isKindOf(object)."
        "e := true:isKindOf(object).     f := 'sym:isKindOf(object)."
        "g := { #1 }:isKindOf(object).   h := nil:isKindOf(object)."
        "i := object:new:isKindOf(object)."
        /* the classes themselves, and where the chain ends */
        "j := integer:isKindOf(object).  k := integer:parent:equals(object)."
        "root := object:parent."
        /* and a value still knows its own class */
        "l := #45:isKindOf(integer).     m := #45:add(#1).") == SOL_OK);

    static const char *all[] = { "a","b","c","d","e","f","g","h","i","j","k","l" };
    for (size_t n = 0; n < sizeof(all) / sizeof(all[0]); n++) {
        assert(SOL_AS_BOOL(global(&vm, all[n])));
    }
    assert(SOL_IS_NIL(global(&vm, "root")));      /* object has no prototype */
    assert(SOL_AS_INT(global(&vm, "m")) == 46);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
}

/* Joining the hierarchies must not put object's messages onto the values. The
   two a built-in does not already define are refused by their receiver
   requirement, which 1.6 installed for a different reason entirely. */
static void test_the_root_leaks_nothing_onto_values(void)
{
    static const char *refused[] = {
        "#45:parent.",
        "#45:via(integer).",
        "\"s\":parent.",
        "true:via(boolean).",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }

    /* And what a value does understand is untouched. */
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk,
        "a := #45:respondsTo('add).      b := #45:respondsTo('parent)."
        "c := \"s\":respondsTo('size).     d := #45:respondsTo('via).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "a")));
    assert(!SOL_AS_BOOL(global(&vm, "b")));
    assert(SOL_AS_BOOL(global(&vm, "c")));
    assert(!SOL_AS_BOOL(global(&vm, "d")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
}

/* A class whose instances are not objects cannot make one. Left inherited,
   object's `new` would answer an object delegating to `string`, which refuses
   every message a string understands -- inert, and no use to anybody. Each of
   the four says what to write instead. */
static void test_a_class_that_cannot_construct_says_so(void)
{
    static const char *refused[] = {
        "string:new.", "symbol:new.", "block:new.", "boolean:new.",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }

    /* The ones that can, still do -- object's `new` included, which is what the
       four are shadowing. */
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk,
        "a := integer:new(#1).  b := float:new(1.5).  c := array:new:size."
        "p := object:new. p:tag := #7."
        "d := p:new:tag."                     /* delegates, as it always did */
        "e := array:of(#1, #2):size.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_FLOAT(global(&vm, "b")) == 1.5);
    assert(SOL_AS_INT(global(&vm, "c")) == 0);
    assert(SOL_AS_INT(global(&vm, "d")) == 7);
    assert(SOL_AS_INT(global(&vm, "e")) == 2);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
}

static void test_via_errors(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "object:new:via(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    assert(run(&vm, &chunk, "object:new:via(object):nosuch.") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);
    /* `via` lives on object, so a value does not have it. */
    assert(run(&vm, &chunk, "#1:via(object).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    sol_vm_free(&vm);
}

int main(void)
{
    test_via_keeps_the_receiver();
    test_via_chains();
    test_via_passes_arguments_and_reads_slots();
    test_parent();
    test_assigning_parent_shadows_rather_than_reparents();
    test_a_built_in_cannot_be_subclassed_this_way();
    test_every_value_is_an_object();
    test_the_root_leaks_nothing_onto_values();
    test_a_class_that_cannot_construct_says_so();
    test_via_errors();
    test_new_makes_a_distinct_object();
    test_slots_are_inherited();
    test_assignment_shadows_rather_than_writes_through();
    test_methods_receive_the_instance_as_self();
    test_inheritance_and_override();
    test_print_can_be_overridden();
    test_errors();
    test_objects_are_collected();
    printf("test_object: ok\n");
    return 0;
}
