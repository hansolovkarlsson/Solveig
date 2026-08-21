/* A class object holds the messages its instances understand, and answers them
   itself. Sending one used to hand the class object to a primitive that read it
   as an instance -- `array:add(#1)` aborted, `array:print` smashed the C stack.
   These are the checks that it refuses instead, and that nothing else moved. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"
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

static SolResult once(const char *source)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    SolResult result = run(&vm, &chunk, source);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    return result;
}

/* One per built-in class, each a message only an instance can answer. Every one
   of these either aborted, segfaulted, or answered nonsense read from the class
   object before the receiver check. */
static void test_a_class_refuses_its_instances_messages(void)
{
    static const char *refused[] = {
        "array:add(#1).",        "array:size.",     "array:at(#1).",
        "array:print.",          "array:asString.", "array:sorted.",
        "block:value.",          "block:print.",    "block:whileTrue({ false }).",
        "string:size.",          "string:concat(\"x\").",
        "string:asUppercase.",   "string:print.",
        "integer:add(#1).",      "integer:abs.",    "integer:print.",
        "symbol:size.",          "symbol:asString.",
        "float:floor.",          "float:print.",
        "boolean:not.",          "boolean:asString.",
        /* `ifTrue` written literally is inlined, so this one is refused by the
           jump rather than by the receiver check -- a different message, the
           same refusal. Held in a variable it takes the ordinary path. */
        "boolean:ifTrue({ #1 }).",
        "b := { #1 }. boolean:ifTrue(b).",
    };
    /* `nil` names the value, not the class -- nil_class has no global, so
       there is nothing to send these to. */

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        assert(once(refused[i]) == SOL_RUNTIME_ERROR);
    }
    printf("  %zu class-object sends refused, none of them fatal\n",
           sizeof(refused) / sizeof(refused[0]));
}

/* The same messages, sent to something that really is one. */
static void test_instances_still_answer(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    vm.gc_stress = true;

    assert(run(&vm, &chunk,
        "a := [#3, #1, #2]. a:add(#4)."
        "size := a:size. first := a:at(#1). sorted := a:sorted:at(#1)."
        "text := \"ab\":concat(\"c\"). upper := \"ab\":asUppercase."
        "n := #7:abs. f := 1.5:floor. neg := #45:negated."
        "s := 'ab:size. t := 'ab:asString."
        "yes := false:not. b := { #9 }:value.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "size")) == 4);
    assert(SOL_AS_INT(global(&vm, "first")) == 3);
    assert(SOL_AS_INT(global(&vm, "sorted")) == 1);
    assert(strcmp(SOL_AS_STRING(global(&vm, "text"))->chars, "abc") == 0);
    assert(strcmp(SOL_AS_STRING(global(&vm, "upper"))->chars, "AB") == 0);
    assert(SOL_AS_INT(global(&vm, "n")) == 7);
    assert(SOL_AS_INT(global(&vm, "f")) == 1);      /* floor answers an integer */
    assert(SOL_AS_INT(global(&vm, "neg")) == -45);
    assert(SOL_AS_INT(global(&vm, "s")) == 2);
    assert(SOL_AS_BOOL(global(&vm, "yes")) == true);
    assert(SOL_AS_INT(global(&vm, "b")) == 9);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  instances answer everything they used to\n");
}

/* The messages a class object is genuinely the receiver of are untouched --
   which is the whole reason the requirement is per message and not per class. */
static void test_class_side_messages_still_work(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := array:of(#1, #2). b := array:new."
        "sizes := a:size:add(b:size)."
        "i := #5. f := 1.5."                   /* written, not constructed */
        "p := object:new. p:x := #3. q := p:new. inherited := q:x.") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "sizes")) == 2);
    assert(SOL_AS_INT(global(&vm, "i")) == 5);
    assert(SOL_AS_FLOAT(global(&vm, "f")) == 1.5);
    assert(SOL_AS_INT(global(&vm, "inherited")) == 3);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  class-side messages are untouched\n");
}

/* `respondsTo` has to agree with sending, or it is worse than useless. */
static void test_reflection_agrees_with_sending(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        /* the class does not respond to what only its instances answer */
        "a := array:respondsTo('add). b := array:respondsTo('of)."
        "c := [#1]:respondsTo('add). d := #45:respondsTo('concat)."
        /* perform goes through the same dispatch, so it refuses the same */
        "e := array:perform('of, #1):size. f := [#1, #2]:perform('size).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "a")) == false);
    assert(SOL_AS_BOOL(global(&vm, "b")) == true);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);
    assert(SOL_AS_BOOL(global(&vm, "d")) == false);
    assert(SOL_AS_INT(global(&vm, "e")) == 1);
    assert(SOL_AS_INT(global(&vm, "f")) == 2);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  respondsTo answers what sending would do\n");

    /* And performing one it refuses is an error, not a crash. */
    assert(once("array:perform('add, #1).") == SOL_RUNTIME_ERROR);
    printf("  perform refuses it too\n");
}

/* A class object nested inside something being rendered must not take the
   renderer down with it. Rendering asks an object for `asString`; a class
   object carries the one meant for its instances, and the renderer falls back
   to the address rather than raising 1.6 from inside a print. */
static void test_a_class_object_renders_as_an_address(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "text := [array, #1]:asString."
        "nested := [[block]]:asString.") == SOL_OK);

    const SolString *text = SOL_AS_STRING(global(&vm, "text"));
    assert(strstr(text->chars, "<object ") != NULL);
    assert(strstr(text->chars, "#1") != NULL);
    assert(strstr(SOL_AS_STRING(global(&vm, "nested"))->chars, "<object ") != NULL);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a class object inside an array renders as its address\n");
}

/* Overriding a built-in with a block replaces the requirement along with the
   primitive: a block is a method, and a method checks its own arity. */
static void test_an_override_lifts_the_requirement(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "array:describe := { \"the array class\" }."
        "x := array:describe."
        /* and overriding one that was refused makes it answer */
        "array:size := { #0 }."
        "y := array:size.") == SOL_OK);

    assert(strcmp(SOL_AS_STRING(global(&vm, "x"))->chars, "the array class") == 0);
    assert(SOL_AS_INT(global(&vm, "y")) == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a block bound over a primitive answers for the class\n");
}

/* `via` rewrites the receiver before dispatch, so the check has to see the
   object the message will actually run with, not the delegate. */
static void test_via_is_checked_against_the_real_receiver(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "base := object:new. base:name := { \"base\" }."
        "derived := base:new."
        "derived:name := { self:via(base):name:concat(\"+\") }."
        "x := derived:name.") == SOL_OK);

    assert(strcmp(SOL_AS_STRING(global(&vm, "x"))->chars, "base+") == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  via still reaches the ancestor with the right receiver\n");
}

int main(void)
{
    printf("class side versus instance side\n");
    test_a_class_refuses_its_instances_messages();
    test_instances_still_answer();
    test_class_side_messages_still_work();
    test_reflection_agrees_with_sending();
    test_a_class_object_renders_as_an_address();
    test_an_override_lifts_the_requirement();
    test_via_is_checked_against_the_real_receiver();
    printf("ok\n");
    return 0;
}
