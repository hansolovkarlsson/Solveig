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

/* A two-byte side-table index, as the emitter writes it. */
static void write_index(SolChunk *chunk, int index, int line)
{
    sol_chunk_write(chunk, (uint8_t)((index >> 8) & 0xff), line);
    sol_chunk_write(chunk, (uint8_t)(index & 0xff), line);
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
        chunk.code[offset + 3] = (uint8_t)((past >> 8) & 0xff);
        chunk.code[offset + 4] = (uint8_t)(past & 0xff);
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
        chunk->code[at + 1] = (uint8_t)((jump >> 8) & 0xff);
        chunk->code[at + 2] = (uint8_t)(jump & 0xff);
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
        chunk.code[offset + 1] = (uint8_t)((past >> 8) & 0xff);
        chunk.code[offset + 2] = (uint8_t)(past & 0xff);
        patched = true;
        break;
    }
    assert(patched);
    assert(sol_chunk_verify(&chunk) != SOL_SER_OK);

    sol_chunk_free(&chunk);
    printf("  rejected: a CHECK_BOOL name index past the name table\n");
}

/* The verifier does not compute stack heights (3.9), so a chunk reaching
   OP_CHECK_BOOL with nothing on the stack passes verification. The opcode has
   to refuse it rather than read below the frame, which is why it goes through
   sol_vm_pop's guard instead of reading the top in place. */
static void test_check_bool_on_an_empty_stack(void)
{
    SolChunk chunk;
    sol_chunk_init(&chunk);
    int name = sol_chunk_add_name(&chunk, "and", 3);

    sol_chunk_write(&chunk, OP_CHECK_BOOL, 1);    /* nothing has been pushed */
    write_index(&chunk, name, 1);
    sol_chunk_write(&chunk, OP_HALT, 1);

    assert(sol_chunk_verify(&chunk) == SOL_SER_OK);

    SolVM vm;
    sol_vm_init(&vm);
    assert(sol_vm_run(&vm, &chunk) == SOL_RUNTIME_ERROR);
    sol_vm_free(&vm);

    sol_chunk_free(&chunk);
    printf("  CHECK_BOOL on an empty stack is refused, not followed\n");
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
