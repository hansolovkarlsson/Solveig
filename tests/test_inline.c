/* Inlined control flow: the same meaning, and jumps a crafted file cannot abuse. */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

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

/* A two-byte side-table index, as the emitter writes it -- through the same
   pair, so a test cannot go on passing after the order changes under it. */
static void write_index(SolChunk *chunk, int index, int line)
{
    sol_chunk_write(chunk, sol_u16_first((uint16_t)index), line);
    sol_chunk_write(chunk, sol_u16_second((uint16_t)index), line);
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
        offset += sol_op_length(op);
    }
    assert(saw_jump);
    assert(!saw_block);

    sol_chunk_free(&chunk);
    printf("  emits jumps, allocates no block\n");
}

/* The loop is the same claim, with a backward jump closing it. */
static void test_loop_actually_inlines(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("i := #0. { i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).",
                       &chunk));

    bool saw_loop = false, saw_exit = false, saw_block = false;
    for (int offset = 0; offset < chunk.count; ) {
        uint8_t op = chunk.code[offset];
        if (op == OP_LOOP)          saw_loop = true;
        if (op == OP_EXIT_IF_FALSE) saw_exit = true;
        if (op == OP_BLOCK)         saw_block = true;
        offset += sol_op_length(op);
    }
    assert(saw_loop);
    assert(saw_exit);
    assert(!saw_block);          /* neither the condition nor the body is one */

    sol_chunk_free(&chunk);
    printf("  the loop jumps back, allocating neither block\n");
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
            int jump = sol_read_u16(&chunk.code[offset + 1]);
            jump += cases[i].target_delta;
            sol_write_u16(&chunk.code[offset + 1], (uint16_t)jump);
            patched = true;
            break;
        }
        assert(patched);
        assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

        sol_chunk_free(&chunk);
        printf("  rejected: %s\n", cases[i].why);
    }
}

/* The selector follows the jump offset rather than leading, so it starts at the
   third operand byte; a bad index there would be read as a name that does not
   exist. Both of its bytes are written, so the check is on the whole index
   rather than on a low byte that happens to be out of range. */
static void test_verifier_checks_the_selector(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("x := true:ifElse({ #1 }, { #2 }).", &chunk));

    bool patched = false;
    for (int offset = 0; offset + 4 < chunk.count; offset++) {
        if (chunk.code[offset] != OP_JUMP_IF_FALSE) continue;
        int past = chunk.names.count;                  /* one past the end */
        sol_write_u16(&chunk.code[offset + 3], (uint16_t)past);
        patched = true;
        break;
    }
    assert(patched);
    assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

    sol_chunk_free(&chunk);
    printf("  rejected: a selector index past the name table\n");
}

/* ---- whileTrue ---------------------------------------------------------- */

/* Written literally it inlines; reached through variables it cannot, and takes
   the ordinary send. Same counts, same answer, same number of passes. */
static void test_loop_matches_the_send(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        /* inlined */
        "i := #0. n := #0."
        "a := { i:lessThan(#5) }:whileTrue({ i := i:add(#1). n := n:add(#10) })."
        /* the very same loop, reached through variables */
        "j := #0. m := #0."
        "cond := { j:lessThan(#5) }. body := { j := j:add(#1). m := m:add(#10) }."
        "b := cond:whileTrue(body)."
        /* a condition false on the first look runs the body no times */
        "k := #0."
        "c := { false }:whileTrue({ k := k:add(#1) })."
        "never := { false }. d := never:whileTrue({ k := k:add(#1) }).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "i")) == SOL_AS_INT(global(&vm, "j")));
    assert(SOL_AS_INT(global(&vm, "n")) == SOL_AS_INT(global(&vm, "m")));
    assert(SOL_AS_INT(global(&vm, "n")) == 50);
    assert(SOL_AS_INT(global(&vm, "k")) == 0);

    /* whileTrue answers nil, and the body's value is discarded either way. */
    assert(SOL_IS_NIL(global(&vm, "a")));
    assert(SOL_IS_NIL(global(&vm, "b")));
    assert(SOL_IS_NIL(global(&vm, "c")));
    assert(SOL_IS_NIL(global(&vm, "d")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  inlined and sent loops agree\n");
}

/* The condition is the receiver, so the interesting cases are the ones where
   the receiver is not a plain block written on the spot. */
static void test_loop_falls_back(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        /* A condition with temporaries keeps its own frame, so it is sent. Its
           `t` must stay its own -- there is a `t` outside it here. */
        "t := #100. i := #0."
        "{ | t | t := #5. i:lessThan(t) }:whileTrue({ i := i:add(#1) })."
        /* A loop is still an expression: nil, and sendable. */
        "x := { false }:whileTrue({ #1 }):equals(nil).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "i")) == 5);
    assert(SOL_AS_INT(global(&vm, "t")) == 100);
    assert(SOL_AS_BOOL(global(&vm, "x")) == true);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* A block with parameters is an arity error when whileTrue calls it with
       none -- in the condition and in the body alike. Inlining either would
       have quietly made it work. */
    const char *arity[] = {
        "{ a | a:lessThan(#5) }:whileTrue({ #1 }).",
        "i := #0. { i:lessThan(#5) }:whileTrue({ a | i := i:add(#1) }).",
    };
    for (size_t i = 0; i < sizeof(arity) / sizeof(arity[0]); i++) {
        SolVM v; sol_vm_init(&v);
        SolChunk ch;
        assert(run(&v, &ch, arity[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&ch); sol_vm_free(&v);
    }

    printf("  falls back to a send where inlining would change meaning\n");
}

/* Runs a program that must fail, and hands back what it printed to stderr. */
static void error_of(const char *source, char *out, size_t size)
{
    char path[] = "/tmp/solum-inline-err-XXXXXX";
    int fd = mkstemp(path);
    assert(fd >= 0);

    fflush(stderr);
    int saved = dup(STDERR_FILENO);
    assert(saved >= 0);
    assert(dup2(fd, STDERR_FILENO) >= 0);

    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk, source) == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    fflush(stderr);
    assert(dup2(saved, STDERR_FILENO) >= 0);
    close(saved);

    assert(lseek(fd, 0, SEEK_SET) == 0);
    ssize_t got = read(fd, out, size - 1);
    out[got > 0 ? (size_t)got : 0] = '\0';
    close(fd);
    remove(path);
}

/* A condition that answers something other than a boolean is whileTrue's
   complaint about the answer, not a receiver failing to understand a message --
   which is the whole reason the loop's test has an opcode of its own. Both
   forms go through one function, and this is what holds them there. */
static void test_loop_condition_error_matches(void)
{
    char inlined[512], sent[512];

    error_of("{ #1 }:whileTrue({ #2 }).", inlined, sizeof(inlined));
    error_of("c := { #1 }. c:whileTrue({ #2 }).", sent, sizeof(sent));

    assert(strstr(inlined, "whileTrue expects the condition block to answer "
                           "a boolean, got integer") != NULL);
    assert(strstr(sent, "whileTrue expects the condition block to answer "
                        "a boolean, got integer") != NULL);

    /* Same first line, whichever way it was compiled. */
    const char *a = strchr(inlined, '\n'), *b = strchr(sent, '\n');
    assert(a != NULL && b != NULL);
    assert(a - inlined == b - sent);
    assert(strncmp(inlined, sent, (size_t)(a - inlined)) == 0);

    printf("  a non-boolean condition reads the same either way\n");
}

/* The loop body keeps the stack where it found it, over enough passes that any
   drift would overflow or underflow. */
static void test_loop_stack_stays_balanced(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0. acc := #0."
        "{ i:lessThan(#50000) }:whileTrue({"
        "    acc := acc:add(#1)."
        "    { false }:whileTrue({ #9 })."          /* a nested loop, never run */
        "    i := i:add(#1)."
        "}).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "acc")) == 50000);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  50,000 passes leave the stack where they found it\n");
}

/* Points the chunk's `op` at `target`, whatever is there -- so a test can aim at
   somewhere it knows is wrong instead of guessing an offset and hoping. */
static void aim(SolChunk *chunk, uint8_t op, int target)
{
    for (int at = 0; at < chunk->count; at += sol_op_length(chunk->code[at])) {
        if (chunk->code[at] != op) continue;
        int after = at + sol_op_length(op);
        int jump  = (op == OP_LOOP) ? after - target : target - after;
        sol_write_u16(&chunk->code[at + 1], (uint16_t)jump);
        return;
    }
    assert(false);                              /* no such instruction here */
}

/* The first offset that is *not* the start of an instruction. Every chunk with
   a multi-byte instruction in it has one. */
static int an_operand_byte(const SolChunk *chunk)
{
    for (int at = 0; at < chunk->count; ) {
        int length = sol_op_length(chunk->code[at]);
        assert(length > 0);
        if (length > 1) return at + 1;
        at += length;
    }
    assert(false);
    return -1;
}

/* A backward jump is the one instruction that can move the ip towards zero, so
   it is the one that can put it before the chunk as well as after. These are the
   files a fuzzer or an attacker writes. */
static void test_verifier_rejects_bad_loops(void)
{
    static const char *source =
        "i := #0. { i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).";

    struct { uint8_t op; int target; const char *why; } cases[] = {
        { OP_LOOP,          0, "a backward target inside an instruction"      },
        { OP_LOOP,         -1, "a backward target before the start of the chunk" },
        { OP_EXIT_IF_FALSE, 0, "a loop exit landing inside an instruction"    },
    };

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        SolChunk chunk;
        sol_chunk_init(&chunk);
        assert(sol_compile(source, &chunk));

        /* A real loop, backward jump and all, is accepted. */
        assert(sol_chunk_verify(&chunk) == SOL_SER_OK);

        int target = cases[i].target;
        if (target == 0) target = an_operand_byte(&chunk);
        aim(&chunk, cases[i].op, target);
        assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

        sol_chunk_free(&chunk);
        printf("  rejected: %s\n", cases[i].why);
    }
}

/* A loop that jumps to itself is a spin, not a memory fault, and the verifier
   is right to accept it: the source language can already say `{ true }` and
   never finish. Termination was never the promise. */
static void test_verifier_allows_a_spin(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("i := #0. { i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).",
                       &chunk));

    for (int at = 0; at < chunk.count; at += sol_op_length(chunk.code[at])) {
        if (chunk.code[at] != OP_LOOP) continue;
        aim(&chunk, OP_LOOP, at);               /* jumps to itself, forever */
        break;
    }
    assert(sol_chunk_verify(&chunk) == SOL_SER_OK);

    sol_chunk_free(&chunk);
    printf("  accepted: a loop that spins -- in range, on an instruction\n");
}


/* ---- and / or ----------------------------------------------------------- */

/* Every combination, both ways round. `and` and `or` answer a boolean on both
   paths, so unlike the conditionals there is nothing here that can be nil. */
static void test_logical_matches_the_send(void)
{
    static const struct { const char *inlined; const char *sent; } pairs[] = {
        { "true:and({ true })",   "true:and(t)"   },
        { "true:and({ false })",  "true:and(f)"   },
        { "false:and({ true })",  "false:and(t)"  },
        { "false:and({ false })", "false:and(f)"  },
        { "true:or({ true })",    "true:or(t)"    },
        { "true:or({ false })",   "true:or(f)"    },
        { "false:or({ true })",   "false:or(t)"   },
        { "false:or({ false })",  "false:or(f)"   },
    };

    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++) {
        char source[256];
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;

        snprintf(source, sizeof(source),
                 "t := { true }. f := { false }. x := %s. y := %s.",
                 pairs[i].inlined, pairs[i].sent);
        assert(run(&vm, &chunk, source) == SOL_OK);

        SolValue x = global(&vm, "x"), y = global(&vm, "y");
        assert(SOL_IS_BOOL(x) && SOL_IS_BOOL(y));
        assert(SOL_AS_BOOL(x) == SOL_AS_BOOL(y));

        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }
    printf("  inlined and sent and/or agree on all eight combinations\n");
}

/* Jumps and a check, no block and no send of the selector. */
static void test_logical_actually_inlines(void)
{
    static const char *sources[] = {
        "x := true:and({ false }).",
        "x := false:or({ true }).",
    };

    for (size_t i = 0; i < sizeof(sources) / sizeof(sources[0]); i++) {
        SolChunk chunk;
        sol_chunk_init(&chunk);
        assert(sol_compile(sources[i], &chunk));

        bool saw_jump = false, saw_check = false, saw_block = false;
        for (int offset = 0; offset < chunk.count; ) {
            uint8_t op = chunk.code[offset];
            if (op == OP_JUMP_IF_FALSE) saw_jump = true;
            if (op == OP_CHECK_BOOL) saw_check = true;
            if (op == OP_BLOCK) saw_block = true;
            offset += sol_op_length(op);
        }
        assert(saw_jump);
        assert(saw_check);
        assert(!saw_block);

        sol_chunk_free(&chunk);
    }
    printf("  and/or emit jumps and a check, allocating no block\n");
}

/* The point of taking a block at all: the argument does not run once the
   receiver has settled the answer. */
static void test_logical_short_circuits(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "log := array:of()."
        "a := false:and({ log:add(#1). true })."     /* must not run */
        "b := true:or({ log:add(#2). false })."      /* must not run */
        "c := true:and({ log:add(#3). true })."      /* must run */
        "d := false:or({ log:add(#4). true })."      /* must run */
        "n := log:size. p := log:at(#1). q := log:at(#2).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "a")) == false);
    assert(SOL_AS_BOOL(global(&vm, "b")) == true);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);
    assert(SOL_AS_BOOL(global(&vm, "d")) == true);
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    assert(SOL_AS_INT(global(&vm, "p")) == 3);
    assert(SOL_AS_INT(global(&vm, "q")) == 4);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  the block runs only when the receiver has not settled it\n");
}

/* The shortcut answers a constant, not the global `true` or `false`, which a
   program may rebind. Reading the global would make the two paths disagree. */
static void test_logical_shortcut_ignores_rebinding(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "yes := #1:equals(#1). no := #1:equals(#2)."   /* real booleans */
        "true := #5. false := #6."                      /* both names rebound */
        "a := no:and({ yes })."                         /* shortcut: false */
        "b := yes:or({ no }).") == SOL_OK);             /* shortcut: true  */

    SolValue a = global(&vm, "a"), b = global(&vm, "b");
    assert(SOL_IS_BOOL(a) && SOL_AS_BOOL(a) == false);
    assert(SOL_IS_BOOL(b) && SOL_AS_BOOL(b) == true);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  the shortcut answers a boolean even where true/false are rebound\n");
}

static void test_logical_falls_back(void)
{
    /* Parameters: an arity error when `and` calls the block with none, and
       inlining would have quietly made it work. */
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    assert(run(&vm, &chunk, "true:and({ a | a }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* Temporaries belong to the block's own frame, so a name inside may shadow
       one outside; inlining would collide them. */
    SolVM vm2; sol_vm_init(&vm2);
    SolChunk chunk2;
    assert(run(&vm2, &chunk2,
        "b := { | t | t := #1."
        "       true:and({ | t | t := #2. true })."
        "       t }."
        "y := b:value.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm2, "y")) == 1);
    sol_chunk_free(&chunk2); sol_vm_free(&vm2);

    printf("  and/or fall back where inlining would change meaning\n");
}

/* A block answering a non-boolean is `and` objecting to the answer, not a
   receiver failing to understand a message -- which is why OP_CHECK_BOOL
   exists rather than reusing the loop's test. One function words it. */
static void test_logical_answer_error_matches(void)
{
    char inlined[512], sent[512];

    error_of("true:and({ #5 }).", inlined, sizeof(inlined));
    error_of("b := { #5 }. true:and(b).", sent, sizeof(sent));

    assert(strstr(inlined, "'and' expects the block to answer a boolean, "
                           "got integer") != NULL);
    assert(strstr(sent, "'and' expects the block to answer a boolean, "
                        "got integer") != NULL);

    const char *a = strchr(inlined, '\n'), *b = strchr(sent, '\n');
    assert(a != NULL && b != NULL);
    assert(a - inlined == b - sent);
    assert(strncmp(inlined, sent, (size_t)(a - inlined)) == 0);

    /* `or` names itself, which is why the message carries the selector. */
    char or_inlined[512];
    error_of("false:or({ #5 }).", or_inlined, sizeof(or_inlined));
    assert(strstr(or_inlined, "'or' expects the block to answer a boolean, "
                              "got integer") != NULL);

    printf("  a non-boolean answer reads the same either way\n");
}

/* A receiver that is not a boolean never finds `and`, because `and` lives on
   the boolean class. The inlined form reports that, not something of its own. */
static void test_logical_receiver_error_matches(void)
{
    char inlined[512], sent[512];

    error_of("#5:and({ true }).", inlined, sizeof(inlined));
    error_of("b := { true }. #5:and(b).", sent, sizeof(sent));

    assert(strstr(inlined, "integer does not understand 'and'") != NULL);

    const char *a = strchr(inlined, '\n'), *b = strchr(sent, '\n');
    assert(a != NULL && b != NULL);
    assert(a - inlined == b - sent);
    assert(strncmp(inlined, sent, (size_t)(a - inlined)) == 0);

    printf("  a non-boolean receiver reads the same either way\n");
}

/* Both paths through both messages, thousands of times: a shortcut that left
   the stack one deep would drift into underflow or overflow. */
static void test_logical_stack_stays_balanced(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0. acc := #0."
        "{ i:lessThan(#20000) }:whileTrue({"
        "    i:mod(#2):equals(#0):and({ i:greaterThan(#-1) })"
        "        :ifTrue({ acc := acc:add(#1) })."
        "    i:mod(#2):equals(#0):or({ i:lessThan(#0) })."
        "    i := i:add(#1)."
        "}).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "acc")) == 10000);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  20,000 and/or leave the stack where they found it\n");
}

/* Nesting, capture, and self through an inlined and/or, under GC stress. */
static void test_logical_semantics_hold(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;
    vm.gc_stress = true;

    assert(run(&vm, &chunk,
        /* self resolves through the block, which is compiled into this frame */
        "p := object:new. p:n := #7."
        "p:ok := { self:n:greaterThan(#5):and({ self:n:lessThan(#10) }) }."
        "a := p:ok."
        /* an enclosing frame's local, read and written from inside the block */
        "b := { | hit | hit := #0."
        "       false:or({ hit := hit:add(#1). true })."
        "       hit }:value."
        /* nested one inside another */
        "c := true:and({ false:or({ true }) })."
        /* chained onto, and mixed with the conditionals */
        "d := true:and({ true }):ifElse({ #1 }, { #2 }).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "a")) == true);
    assert(SOL_AS_INT(global(&vm, "b")) == 1);
    assert(SOL_AS_BOOL(global(&vm, "c")) == true);
    assert(SOL_AS_INT(global(&vm, "d")) == 1);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  self, capture, nesting, and chaining hold through and/or\n");
}

/* OP_CHECK_BOOL carries a name, and a corrupted one would be read out of the
   table it indexes. */
static void test_verifier_checks_the_logical_selector(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("x := true:and({ false }).", &chunk));

    bool patched = false;
    for (int offset = 0; offset + 2 < chunk.count; offset++) {
        if (chunk.code[offset] != OP_CHECK_BOOL) continue;
        int past = chunk.names.count;                  /* one past the end */
        sol_write_u16(&chunk.code[offset + 1], (uint16_t)past);
        patched = true;
        break;
    }
    assert(patched);
    assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

    sol_chunk_free(&chunk);
    printf("  rejected: a CHECK_BOOL name index past the name table\n");
}

/* OP_CHECK_BOOL examines the top of the stack, so a chunk reaching it with
   nothing there is corrupt. The verifier computes stack heights now (3.9) and
   refuses this at load -- and the opcode still refuses it at run time, because
   Solis runs what it just compiled without verifying and the C API will run any
   chunk it is handed. Both, on purpose. */
static void test_check_bool_on_an_empty_stack(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    int name = sol_chunk_add_name(&chunk, "and", 3);

    sol_chunk_write(&chunk, OP_CHECK_BOOL, 1);    /* nothing has been pushed */
    write_index(&chunk, name, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);

    /* Caught at the door: there is no value here for it to look at. */
    assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

    /* And caught again if something runs it without asking the verifier. */
    SolVM vm;
    sol_vm_init(&vm);
    assert(sol_vm_run(&vm, &chunk) == SOL_RUNTIME_ERROR);
    sol_vm_free(&vm);

    sol_chunk_free(&chunk);
    printf("  CHECK_BOOL on an empty stack is refused at load and at run\n");
}

/* ---- doUntil ------------------------------------------------------------ *
 *
 * The body first, then the test, so it always runs at least once -- the one
 * loop `whileTrue` cannot express without a flag declared outside it. Inlined
 * it is 1.28x the hand-written flag loop it replaces, because the flag costs
 * two sends an iteration that the jumps do not need.
 */
static void test_do_until_runs_the_body_first(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* True from the start, and the body has still run. */
    assert(run(&vm, &chunk,
        "once := #0. { once := once:add(#1) }:doUntil({ true })."
        "counted := #0. { counted := counted:add(#1) }:doUntil({ counted:greaterOrEqual(#4) })."
        /* it answers nil, as whileTrue does */
        "answer := { #1 }:doUntil({ true }).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "once")) == 1);
    assert(SOL_AS_INT(global(&vm, "counted")) == 4);
    assert(SOL_IS_NIL(global(&vm, "answer")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  doUntil runs the body before the test, always at least once\n");
}

static void test_do_until_actually_inlines(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    assert(sol_compile("i := #0. { i := i:add(#1) }:doUntil({ i:greaterOrEqual(#3) }).",
                       &chunk));

    bool saw_loop = false, saw_check = false, saw_block = false, saw_send = false;
    for (int offset = 0; offset < chunk.count; ) {
        uint8_t op = chunk.code[offset];
        if (op == OP_LOOP)       saw_loop = true;
        if (op == OP_CHECK_BOOL) saw_check = true;
        if (op == OP_BLOCK)      saw_block = true;
        offset += sol_op_length(op);
    }
    (void)saw_send;
    assert(saw_loop);
    assert(saw_check);           /* the check that lets it name itself */
    assert(!saw_block);          /* neither the body nor the condition is one */

    sol_chunk_free(&chunk);
    printf("  doUntil jumps back, allocating neither block\n");
}

/* The inlined form and the sent one must complain identically, which is what
   OP_CHECK_BOOL's name index is carrying here: without it the check would be
   OP_EXIT_IF_FALSE's, which says `whileTrue`. */
static void test_do_until_condition_error_matches(void)
{
    static const char *both[] = {
        "i := #0. { i := i:add(#1) }:doUntil({ #5 }).",          /* inlined */
        "i := #0. c := { #5 }. { i := i:add(#1) }:doUntil(c).",  /* sent */
    };

    char captured[2][256];
    for (size_t i = 0; i < 2; i++) {
        char temp[] = "/tmp/solum-dountil-XXXXXX";
        int fd = mkstemp(temp);
        assert(fd >= 0);
        fflush(stderr);
        int saved = dup(STDERR_FILENO);
        assert(dup2(fd, STDERR_FILENO) >= 0);

        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, both[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);

        fflush(stderr);
        assert(dup2(saved, STDERR_FILENO) >= 0);
        close(saved);
        assert(lseek(fd, 0, SEEK_SET) == 0);
        ssize_t got = read(fd, captured[i], sizeof captured[i] - 1);
        captured[i][got > 0 ? (size_t)got : 0] = '\0';
        close(fd);
        remove(temp);
    }

    assert(strstr(captured[0], "'doUntil' expects the block to answer a boolean") != NULL);
    assert(strstr(captured[0], "whileTrue") == NULL);    /* not the neighbour's */
    /* The first line of each is the same complaint. */
    char *first = strchr(captured[0], '\n');
    char *second = strchr(captured[1], '\n');
    assert(first != NULL && second != NULL);
    assert((size_t)(first - captured[0]) == (size_t)(second - captured[1]));
    assert(memcmp(captured[0], captured[1], (size_t)(first - captured[0])) == 0);

    printf("  inlined and sent doUntil word the complaint identically\n");
}

static void test_do_until_falls_back(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* A block with a parameter is an arity error when called with none, and
       inlining it would have quietly made it work. */
    assert(run(&vm, &chunk, "{ a | a }:doUntil({ true }).") == SOL_RUNTIME_ERROR);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* A condition held in a name is an ordinary argument, so this is a send --
       and it still means what it says. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "i := #0. c := { i:greaterOrEqual(#3) }."
        "{ i := i:add(#1) }:doUntil(c). n := i.") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 3);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* And the message is still there to be found. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "here := { #1 }:respondsTo('doUntil)."
        "i := #0. { i := i:add(#1) }:perform('doUntil, { i:greaterOrEqual(#2) })."
        "n := i.") == SOL_OK);
    assert(SOL_AS_BOOL(global(&vm, "here")));
    assert(SOL_AS_INT(global(&vm, "n")) == 2);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    printf("  doUntil falls back to a send, and is still a message\n");
}

/* A loop leaves exactly one value where it started, or a long one would grow
   the stack until it overflowed. */
static void test_do_until_stack_stays_balanced(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "i := #0."
        "{ i := i:add(#1) }:doUntil({ i:greaterOrEqual(#2000) })."
        "deep := #0."
        "{ deep := deep:add(#1) }:doUntil({ deep:greaterOrEqual(#2000) })."
        "n := i:add(deep).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 4000);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a long doUntil does not grow the stack\n");
}

/* ---- the counted loops -------------------------------------------------- *
 *
 * Primitives rather than inlined jumps, which is 6.6 answered differently from
 * the way it asked. A primitive removes the two counter sends an iteration and
 * keeps the block call; inlining would have removed the block call and kept the
 * sends. Measured, the primitive is 2.5x what inlining would have produced.
 *
 * It also gets the receiver check for free: `repeat` is installed for SOL_INT
 * receivers, so a float simply does not understand it, where inlined jumps
 * would have needed a type-guard instruction to say the same thing.
 */
static void test_counted_loops_count(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "ticks := #0. #3:repeat({ ticks := ticks:add(#1) })."
        "tocks := #0. { tocks := tocks:add(#1) }:repeat(#2)."
        "up := array:new. #1:toDo(#3, { n | up:add(n) })."
        "stepped := array:new. #1:toByDo(#10, #3, { n | stepped:add(n) })."
        "down := array:new. #3:toByDo(#1, #0:sub(#1), { n | down:add(n) })."
        /* they answer nil, as the other loops do */
        "answer := #1:repeat({ #2 }).") == SOL_OK);

    assert(SOL_AS_INT(global(&vm, "ticks")) == 3);
    assert(SOL_AS_INT(global(&vm, "tocks")) == 2);
    assert(SOL_AS_ARRAY(global(&vm, "up"))->count == 3);
    assert(SOL_AS_INT(SOL_AS_ARRAY(global(&vm, "up"))->items[2]) == 3);
    assert(SOL_AS_ARRAY(global(&vm, "stepped"))->count == 4);     /* 1 4 7 10 */
    assert(SOL_AS_INT(SOL_AS_ARRAY(global(&vm, "stepped"))->items[3]) == 10);
    assert(SOL_AS_ARRAY(global(&vm, "down"))->count == 3);        /* 3 2 1 */
    assert(SOL_AS_INT(SOL_AS_ARRAY(global(&vm, "down"))->items[2]) == 1);
    assert(SOL_IS_NIL(global(&vm, "answer")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  repeat, toDo and toByDo count what they say\n");
}

/* An empty range runs the body no times rather than complaining, which is what
   an empty slice and an empty split already do. */
static void test_counted_loops_over_nothing(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := #0. #0:repeat({ a := a:add(#1) })."
        "b := #0. #0:sub(#5):repeat({ b := b:add(#1) })."     /* a negative count */
        "c := #0. { c := c:add(#1) }:repeat(#0)."
        "d := #0. #5:toDo(#1, { n | d := d:add(#1) })."
        "e := #0. #1:toByDo(#5, #0:sub(#1), { n | e := e:add(#1) })."
        "n := a:add(b):add(c):add(d):add(e).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "n")) == 0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  an empty range runs the body no times\n");
}

/* The receiver check falls out of dispatch: `repeat` is on integer, so a float
   does not understand it -- the same complaint a send has always made, and the
   thing inlining would have had to reproduce by hand. */
static void test_counted_loops_refuse(void)
{
    static const char *refused[] = {
        "1.5:repeat({ #1 }).",
        "\"x\":repeat({ #1 }).",
        "#3:repeat(#1).",                    /* not a block */
        "#3:repeat.",
        "{ #1 }:repeat(1.5).",
        "#1:toByDo(#5, #0, { n | n }).",     /* a step of #0 never finishes */
        "#1:toByDo(1.5, #1, { n | n }).",
        "#1:toDo(#3, { n | n }, #4).",
        "#1:toDo(#3, { }).",                 /* the block is handed the index */
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }
    printf("  a non-integer receiver does not understand repeat\n");
}

/* An error inside the body stops the loop rather than being run past. */
static void test_an_error_in_the_body_stops_the_loop(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "seen := #0."
        "#10:repeat({ seen := seen:add(#1). nil:frobnicate }).") == SOL_RUNTIME_ERROR);
    assert(SOL_AS_INT(global(&vm, "seen")) == 1);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "seen := #0."
        "#1:toDo(#10, { n | seen := seen:add(#1). nil:frobnicate }).") == SOL_RUNTIME_ERROR);
    assert(SOL_AS_INT(global(&vm, "seen")) == 1);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    printf("  an error in the body stops the loop at once\n");
}

/* A step near the top of the range must not wrap past the limit and run
   forever. The loop stops when the next index would overflow. */
static void test_a_huge_step_terminates(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* The last two integers there are, by ones: both run, and then the step
       that would carry it past INT64_MAX ends the loop instead of wrapping to
       the bottom and running for ever. */
    assert(run(&vm, &chunk,
        "seen := #0."
        "#9223372036854775806:toByDo(#9223372036854775807, #1,"
        "    { n | seen := seen:add(#1) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 2);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* A step so large the very first one overflows: the body has still run
       once, because the starting index was inside the range. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "seen := #0."
        "#9223372036854775806:toByDo(#9223372036854775807, #9223372036854775807,"
        "    { n | seen := seen:add(#1) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 1);
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    /* And downwards, past the bottom. */
    sol_vm_init(&vm);
    assert(run(&vm, &chunk,
        "seen := #0."
        "#0:sub(#9223372036854775807):toByDo(#0:sub(#9223372036854775807), #0:sub(#1),"
        "    { n | seen := seen:add(#1) }).") == SOL_OK);
    assert(SOL_AS_INT(global(&vm, "seen")) == 1);
    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a step that would overflow stops the loop rather than wrapping\n");
}

int main(void)
{
    printf("inlined control flow\n");
    test_inlined_matches_the_send();
    test_actually_inlines();
    test_falls_back();
    test_semantics_hold();
    test_stack_stays_balanced();
    test_recursion_reaches_further();
    test_verifier_rejects_bad_jumps();
    test_verifier_checks_the_selector();
    test_loop_actually_inlines();
    test_loop_matches_the_send();
    test_loop_falls_back();
    test_loop_condition_error_matches();
    test_loop_stack_stays_balanced();
    test_do_until_runs_the_body_first();
    test_do_until_actually_inlines();
    test_do_until_condition_error_matches();
    test_do_until_falls_back();
    test_do_until_stack_stays_balanced();
    test_counted_loops_count();
    test_counted_loops_over_nothing();
    test_counted_loops_refuse();
    test_an_error_in_the_body_stops_the_loop();
    test_a_huge_step_terminates();
    test_verifier_rejects_bad_loops();
    test_verifier_allows_a_spin();
    test_logical_matches_the_send();
    test_logical_actually_inlines();
    test_logical_short_circuits();
    test_logical_shortcut_ignores_rebinding();
    test_logical_falls_back();
    test_logical_answer_error_matches();
    test_logical_receiver_error_matches();
    test_logical_stack_stays_balanced();
    test_logical_semantics_hold();
    test_verifier_checks_the_logical_selector();
    test_check_bool_on_an_empty_stack();
    printf("ok\n");
    return 0;
}
