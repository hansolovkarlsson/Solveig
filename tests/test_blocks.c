/* Blocks: deferred code, the frame they capture, and the control flow that
 * falls out of sending them messages. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
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

/* The whole point: a block is a value, and writing one runs nothing. */
static void test_a_block_defers_its_body(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "ran := false. b := { ran := true }.") == SOL_OK);
    assert(SOL_IS_BLOCK(global(&vm, "b")));
    assert(SOL_AS_BOOL(global(&vm, "ran")) == false);   /* not yet */

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

static void test_value_runs_it(void)
{
    SolVM vm; sol_vm_init(&vm);
    /* One chunk per `run`: a chunk has to outlive anything defined in it, so it
       cannot be freed between the two, and reusing the variable would leak the
       first one. */
    SolChunk first, second;

    assert(run(&vm, &first, "r := { #1:add(#2) }:value().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 3);

    /* An empty block answers nil. */
    assert(run(&vm, &second, "e := { }:value().") == SOL_OK);
    assert(SOL_IS_NIL(global(&vm, "e")));

    sol_chunk_free(&first);
    sol_chunk_free(&second);
    sol_vm_free(&vm);
}

/* Conditionals are ordinary sends -- nothing in the compiler knows them. */
static void test_conditionals_choose_a_branch(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk first, second, third;

    assert(run(&vm, &first,
        "taken := false. skipped := false."
        "true:ifTrue({ taken := true })."
        "true:ifFalse({ skipped := true }).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "taken")) == true);
    assert(SOL_AS_BOOL(global(&vm, "skipped")) == false);

    assert(run(&vm, &second,
        "r := #5:lessThan(#10):ifElse({ #100 }, { #200 }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 100);

    assert(run(&vm, &third,
        "r := #50:lessThan(#10):ifElse({ #100 }, { #200 }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 200);

    sol_chunk_free(&first);
    sol_chunk_free(&second);
    sol_chunk_free(&third);
    sol_vm_free(&vm);
}

/* Comparisons keep the same strictness as arithmetic, except `equals`, which
   answers false across types rather than erroring. */
static void test_comparison_strictness(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "r := #1:lessThan(2.0).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "a := #1:equals(1.0). b := #1:equals(#1).") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "a")) == false);
    assert(SOL_AS_BOOL(global(&vm, "b")) == true);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* The loop the whole design was for: the condition must be re-evaluated, which
   is exactly why it has to be a block rather than a value. */
static void test_while_true_loops(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk first, second;

    assert(run(&vm, &first,
        "i := #0."
        "{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "i")) == 5);

    /* A condition that is false from the start runs the body zero times. */
    assert(run(&vm, &second,
        "n := #0. { false }:whileTrue({ n := n:add(#1) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 0);

    sol_chunk_free(&first);
    sol_chunk_free(&second);
    sol_vm_free(&vm);
}

/* A block written inside a method reads and writes that method's locals, even
   though whileTrue is what actually runs it. */
static void test_blocks_capture_enclosing_locals(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:sumTo := {"
        "    | total, i |"
        "    total := #0."
        "    i := #1."
        "    { i:greaterThan(self):not() }:whileTrue({"
        "        total := total:add(i)."
        "        i := i:add(#1)"
        "    })."
        "    total"
        "}."
        "r := #100:sumTo().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 5050);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* `self` inside a block is the enclosing method's receiver, not the block. */
static void test_self_inside_a_block(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:viaBlock := { { self:mul(#2) }:value() }."
        "r := #21:viaBlock().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 42);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Conditionals plus recursion finally give a recursion that terminates. */
static void test_recursion_with_a_base_case(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:factorial := {"
        "    self:lessThan(#2):ifElse({ #1 },"
        "        { self:mul( self:sub(#1):factorial() ) })"
        "}."
        "a := #1:factorial(). b := #5:factorial(). c := #20:factorial().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "a")) == 1);
    assert(SOL_AS_INT(global(&vm, "b")) == 120);
    assert(SOL_AS_INT(global(&vm, "c")) == 2432902008176640000LL);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* A block that does not touch its home frame is independent of it, and may be
   stored and run long after that frame is gone. */
static void test_non_capturing_blocks_may_escape(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk first, second;

    assert(run(&vm, &first, "saved := { #42 }.") == SOL_OK);
    assert(run(&vm, &second, "r := saved:value().") == SOL_OK);   /* new frame */
    assert(SOL_AS_INT(global(&vm, "r")) == 42);

    sol_chunk_free(&second);
    sol_chunk_free(&first);
    sol_vm_free(&vm);
}

/* A capturing block that outlives its frame is caught, not left reading slots
   that now belong to someone else. */
static void test_escaping_capture_is_caught(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk first, second;

    assert(run(&vm, &first,
        "escaped := nil."                       /* globals are made at top level */
        "integer:leak := { | t | t := self. escaped := { t }. #0 }."
        "#7:leak().") == SOL_OK);
    /* `escaped` is a block over a frame that has since returned. */
    assert(run(&vm, &second, "r := escaped:value().") == SOL_RUNTIME_ERROR);

    sol_chunk_free(&second);
    sol_chunk_free(&first);
    sol_vm_free(&vm);
}

static void test_errors_are_reported(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk, "true:ifTrue(#1).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "{ #1 }:whileTrue({ #2 }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "#1:ifTrue({ #2 }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk);

    assert(run(&vm, &chunk, "b := { #1.") == SOL_COMPILE_ERROR);
    sol_chunk_free(&chunk);

    /* The VM stays usable after each failure. */
    assert(run(&vm, &chunk, "fine := { #1 }:value().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "fine")) == 1);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

/* Blocks nested in blocks share the same home frame -- capture is lexical, so
   it skips past intermediate block frames. */
static void test_nested_blocks_share_the_home_frame(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:nested := {"
        "    | n |"
        "    n := self."
        "    { { n := n:add(#1) }:value() }:value()."
        "    n"
        "}."
        "r := #10:nested().") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "r")) == 11);

    sol_chunk_free(&chunk);
    sol_vm_free(&vm);
}

int main(void)
{
    test_a_block_defers_its_body();
    test_value_runs_it();
    test_conditionals_choose_a_branch();
    test_comparison_strictness();
    test_while_true_loops();
    test_blocks_capture_enclosing_locals();
    test_self_inside_a_block();
    test_recursion_with_a_base_case();
    test_non_capturing_blocks_may_escape();
    test_escaping_capture_is_caught();
    test_errors_are_reported();
    test_nested_blocks_share_the_home_frame();
    printf("test_blocks: ok\n");
    return 0;
}
