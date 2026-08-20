/* Inlined conditionals: the same meaning, and jumps a crafted file cannot abuse. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/bytecode.h"
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

/* Written literally it inlines; held in a variable it cannot, and takes the
   ordinary send. The two must agree on every combination. */
static void test_inlined_matches_the_send(void)
{
    static const struct { const char *inlined; const char *sent; } pairs[] = {
        { "true:ifElse({ #1 }, { #2 })",  "true:ifElse(a, b)"  },
        { "false:ifElse({ #1 }, { #2 })", "false:ifElse(a, b)" },
        { "true:ifTrue({ #1 })",          "true:ifTrue(a)"     },
        { "false:ifTrue({ #1 })",         "false:ifTrue(a)"    },
        { "true:ifFalse({ #1 })",         "true:ifFalse(a)"    },
        { "false:ifFalse({ #1 })",        "false:ifFalse(a)"   },
    };

    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++) {
        char source[256];
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;

        snprintf(source, sizeof(source),
                 "a := { #1 }. b := { #2 }. x := %s. y := %s.",
                 pairs[i].inlined, pairs[i].sent);
        assert(run(&vm, &chunk, source) == SOL_OK);

        SolValue x = global(&vm, "x"), y = global(&vm, "y");
        assert(SOL_IS_NIL(x) == SOL_IS_NIL(y));
        if (!SOL_IS_NIL(x)) assert(SOL_AS_INT(x) == SOL_AS_INT(y));

        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }
    printf("  inlined and sent forms agree\n");
}

/* No OP_BLOCK and no send of the selector -- otherwise this tests nothing. */
static void test_actually_inlines(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("x := true:ifElse({ #1 }, { #2 }).", &chunk));

    bool saw_jump = false, saw_block = false;
    for (int offset = 0; offset < chunk.count; ) {
        uint8_t op = chunk.code[offset];
        if (op == OP_JUMP || op == OP_JUMP_IF_FALSE) saw_jump = true;
        if (op == OP_BLOCK) saw_block = true;
        switch (op) {
        case OP_CONST: case OP_GLOBAL: case OP_SET_GLOBAL: case OP_LOCAL:
        case OP_SET_LOCAL: case OP_BLOCK: case OP_SET_SLOT: case OP_STRING:
        case OP_SYMBOL:            offset += 2; break;
        case OP_SEND: case OP_OUTER: case OP_SET_OUTER: case OP_JUMP:
                                   offset += 3; break;
        case OP_JUMP_IF_FALSE:     offset += 4; break;
        default:                   offset += 1; break;
        }
    }
    assert(saw_jump);
    assert(!saw_block);

    sol_chunk_free(&chunk);
    printf("  emits jumps, allocates no block\n");
}

/* The restrictions exist so the optimisation cannot change meaning. */
static void test_falls_back(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* A block with temporaries keeps its own frame, so it is sent, not inlined
       -- and a name inside it may still shadow one outside. */
    assert(run(&vm, &chunk,
        "b := { | t | t := #1. true:ifElse({ | t | t := #2. t }, { #0 }):add(t) }."
        "x := b:value.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "x")) == 3);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* A block with parameters is an arity error when called with none, and
       inlining it would have quietly made it work. */
    SolVM vm2; sol_vm_init(&vm2);
    SolChunk chunk2;
    assert(run(&vm2, &chunk2, "true:ifElse({ a | a }, { #2 }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk2); sol_vm_free(&vm2);

    printf("  falls back to a send where inlining would change meaning\n");
}

static void test_semantics_hold(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    vm.gc_stress = true;

    assert(run(&vm, &chunk,
        /* self resolves through an inlined branch */
        "p := object:new. p:n := #7."
        "p:pick := { self:n:greaterThan(#5):ifElse({ self:n:mul(#10) }, { #0 }) }."
        "a := p:pick."
        /* an enclosing frame's local, read and written from inside a branch */
        "b := { | acc | acc := #0."
        "       true:ifElse({ acc := acc:add(#5) }, { acc := acc:sub(#5) })."
        "       acc }:value."
        /* nested, and chained onto */
        "c := #7:greaterThan(#5):ifElse({ #7:greaterThan(#10)"
        "                                 :ifElse({ #1 }, { #2 }) }, { #3 })."
        /* only the taken branch runs */
        "log := array:of()."
        "true:ifElse({ log:add(#1) }, { log:add(#2) })."
        "false:ifElse({ log:add(#3) }, { log:add(#4) })."
        "d := log:size. e := log:at(#1). f := log:at(#2).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "a")) == 70);
    assert(SOL_AS_INT(global(&vm, "b")) == 5);
    assert(SOL_AS_INT(global(&vm, "c")) == 2);
    assert(SOL_AS_INT(global(&vm, "d")) == 2);
    assert(SOL_AS_INT(global(&vm, "e")) == 1);
    assert(SOL_AS_INT(global(&vm, "f")) == 4);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  self, capture, nesting, and one-branch-only all hold\n");
}

/* Thousands of conditionals in a loop: a branch that left the stack one deep
   would drift into either underflow or overflow. */
static void test_stack_stays_balanced(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0. acc := #0."
        "{ i:lessThan(#20000) }:whileTrue({"
        "    acc := i:mod(#2):equals(#0):ifElse({ acc:add(#1) }, { acc })."
        "    i:lessThan(#0):ifTrue({ #1 })."
        "    i:lessThan(#0):ifFalse({ #2 })."
        "    i := i:add(#1)."
        "}).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "acc")) == 10000);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  20,000 conditionals leave the stack where they found it\n");
}

/* A conditional branch no longer costs a frame, which is the whole of 3.5. */
static void test_recursion_reaches_further(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "integer:countdown := "
        "    { self:lessThan(#1):ifElse({ #0 }, { self:sub(#1):countdown }) }."
        /* 30 was the whole budget before inlining. */
        "x := #55:countdown.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "x")) == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  recursion reaches past the old 30-level ceiling\n");
}

/* Execution is no longer linear, so the verifier has to know where every
   instruction starts. These are the files a fuzzer or an attacker writes. */
static void test_verifier_rejects_bad_jumps(void)
{
    struct { int target_delta; const char *why; } cases[] = {
        { +1,   "a target one byte into the next instruction" },
        { +200, "a target past the end of the chunk" },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        SolChunk chunk;
        sol_chunk_init(&chunk);
        assert(sol_compile("x := true:ifElse({ #1 }, { #2 }).", &chunk));
        assert(sol_chunk_verify(&chunk) == SOL_SER_OK);

        /* Find the JUMP_IF_FALSE the compiler just emitted and skew it. */
        bool patched = false;
        for (int offset = 0; offset + 3 < chunk.count; offset++) {
            if (chunk.code[offset] != OP_JUMP_IF_FALSE) continue;
            int jump = (chunk.code[offset + 1] << 8) | chunk.code[offset + 2];
            jump += cases[i].target_delta;
            chunk.code[offset + 1] = (uint8_t)((jump >> 8) & 0xff);
            chunk.code[offset + 2] = (uint8_t)(jump & 0xff);
            patched = true;
            break;
        }
        assert(patched);
        assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

        sol_chunk_free(&chunk);
        printf("  rejected: %s\n", cases[i].why);
    }
}

/* The selector rides in the third operand byte; a bad index there would be read
   as a name that does not exist. */
static void test_verifier_checks_the_selector(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("x := true:ifElse({ #1 }, { #2 }).", &chunk));

    for (int offset = 0; offset + 3 < chunk.count; offset++) {
        if (chunk.code[offset] != OP_JUMP_IF_FALSE) continue;
        chunk.code[offset + 3] = (uint8_t)chunk.names.count;   /* one past the end */
        break;
    }
    assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

    sol_chunk_free(&chunk);
    printf("  rejected: a selector index past the name table\n");
}

int main(void)
{
    printf("inlined conditionals\n");
    test_inlined_matches_the_send();
    test_actually_inlines();
    test_falls_back();
    test_semantics_hold();
    test_stack_stays_balanced();
    test_recursion_reaches_further();
    test_verifier_rejects_bad_jumps();
    test_verifier_checks_the_selector();
    printf("ok\n");
    return 0;
}
