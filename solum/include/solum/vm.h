/* vm.h -- the Solum virtual machine. */
#ifndef SOLUM_VM_H
#define SOLUM_VM_H

#include "solum/common.h"
#include "solum/bytecode.h"
#include "solum/object.h"
#include "solum/value.h"

#define SOL_FRAMES_MAX 64
#define SOL_STACK_MAX  (SOL_FRAMES_MAX * 256)

/* One activation. `slots` points into the value stack at the receiver, so
   slots[0] is self and slots[1..arity] are the arguments -- the caller has
   already laid them out that way, and no copying is needed to make the call. */
typedef struct {
    const SolMethod *method;   /* NULL for the top-level chunk */
    const SolChunk  *chunk;
    const uint8_t   *ip;
    SolValue        *slots;
    uint64_t         id;       /* unique for the life of the VM */

    /* The frame this one was lexically written inside, by index and by id.
       Reaching a name further out is a walk along this chain -- lexical, not
       dynamic. The id is what detects a frame that has since returned. */
    int              home_frame;
    uint64_t         home_id;
} SolFrame;

typedef enum {
    SOL_OK,
    SOL_COMPILE_ERROR,
    SOL_RUNTIME_ERROR,
    SOL_EXIT              /* the program asked to stop; `exit_code` says with what */
} SolResult;

struct SolVM {
    SolFrame frames[SOL_FRAMES_MAX];
    int      frame_count;

    SolValue  stack[SOL_STACK_MAX];
    SolValue *stack_top;

    SolObject *root;      /* globals namespace; also ends every proto chain */
    uint64_t   next_frame_id;

    /* Heap. One list threads every collectable cell; `gray` is the mark
       worklist, kept explicit so a deep object graph cannot overflow the C
       stack the way recursive marking would. */
    SolGCHeader  *heap;
    size_t        bytes_allocated;
    size_t        next_gc;
    SolGCHeader **gray;
    int           gray_count;
    int           gray_capacity;
    SolGCHeader  *temps[SOL_GC_MAX_TEMPS];
    int           temp_count;
    bool          gc_stress;

    /* Class objects for the unboxed value types. A message sent to #45 is
       resolved against integer_class, which is what keeps "everything is an
       object" true without boxing every number. */
    SolObject *integer_class;
    SolObject *float_class;
    SolObject *nil_class;
    SolObject *bool_class;
    SolObject *block_class;
    SolObject *array_class;
    SolObject *dict_class;
    SolObject *error_class;
    SolObject *time_class;
    SolObject *string_class;
    SolObject *object_class;
    SolObject *symbol_class;

    /* The intern table: buckets of symbols chained by `chain`. Weak, so being
       here does not keep a symbol alive. */
    SolSymbol **symbols;
    int         symbol_capacity;
    int         symbol_count;

    /* The name table: one copy of every selector and slot name this VM has
       seen, so that comparing two names is comparing two pointers. Open
       addressing, capacity a power of two, no deletions.
     *
     * Deliberately *not* the symbol table above, which is weak so that a name
     * mentioned once can die. These are not values a program can hold; they are
     * the VM's own atoms, they must outlive every slot and every chunk that
     * points at one, and there is no moment at which one is known to be
     * unreachable. So they live as long as the VM and are freed with it. */
    char      **names;
    int         name_capacity;
    int         name_count;

    bool had_error;

    /* What went wrong, formatted -- the message and the stack beneath it --
     * rather than written straight to stderr.
     *
     * Deferring the write is what will let an error be caught: a handler has to
     * be able to see it and decide, and a message already on stderr cannot be
     * taken back. Nothing catches anything yet, so `sol_vm_run` prints this
     * before it returns and the visible behaviour is unchanged.
     *
     * The first error wins. Formatting a message can itself fail -- rendering a
     * value calls `asString`, which is a send like any other -- and the failure
     * that started it is the one worth reporting.
     *
     * Kept apart because they are wanted apart: a handler is given the message
     * and nothing else, where an uncaught error is printed with the stack
     * beneath it. Composing the report at the point it is printed means the two
     * cannot drift. */
    SolText error_message;    /* "nil does not understand 'boom'"  */
    SolText error_trace;      /* "  [line 3] in block\n..."         */

    /* `system:exit(code)` unwinds rather than leaving from under the machine.
       It sets `had_error` too, since every loop that has to stop already checks
       that one -- the flag means "stop running", and `exiting` says which of
       the two reasons it was. */
    bool exiting;
    int  exit_code;

    /* `solvm --trace`: write a call and a return for every frame entered, to
       stderr, indented by depth. Off unless a front end turns it on.
     *
       `trace_depth` is how far down to follow: 0 for all of it, or a limit,
       since a program's outermost calls are usually the ones being looked for
       and its innermost are usually a loop body. */
    bool trace;
    int  trace_depth;

    /* A debugger, if one is driving. `debug_hook` is called before each
       instruction that begins a new line or changes frame -- a statement
       boundary, near enough -- and whatever it does happens on this VM, with
       every frame still live. The VM decides *when* to offer a stop and the
       hook decides whether to take it, which keeps the machine ignorant of
       stepping, breakpoints, and what a debugger is for.
     *
       NULL when nothing is driving, which is the cost: one predictable branch
       per instruction. See solid/. */
    void (*debug_hook)(struct SolVM *vm, void *context);
    void  *debug_context;

    /* Set while the hook is being called because the program is *failing*
       rather than because it reached a line. The frames are still standing at
       that point -- the trace has just walked them -- so it is the one moment a
       debugger can look at the wreck from inside. */
    bool   debug_failed;
    int      debug_last_line;
    uint64_t debug_last_frame_id;
};

void sol_vm_init(SolVM *vm);

/* Hands the program its own arguments, which `system:arguments` answers. Copies
   them, so the caller's array need not outlive the call. Without this the slot
   holds the empty array, which is what a program run with no arguments sees. */
void sol_vm_set_arguments(SolVM *vm, int count, char **args);

/* Frees the interned names. Called by sol_vm_free once nothing can look one up
   again -- every slot and every chunk that pointed at one is already gone. */
void sol_vm_free_names(SolVM *vm);

/* Resolves `chunk`'s name table, and every nested method's, to this VM's
   interned names. Idempotent, and re-does the work if the chunk was last
   resolved against a different VM -- which the tests do, running one chunk and
   then another VM's. Called before a chunk runs, so the dispatch loop can
   assume `chunk->interned` is there. */
void sol_vm_intern_chunk(SolVM *vm, SolChunk *chunk);
void sol_vm_free(SolVM *vm);

/* Executes `chunk` to completion. */
SolResult sol_vm_run(SolVM *vm, const SolChunk *chunk);

void     sol_vm_push(SolVM *vm, SolValue value);
SolValue sol_vm_pop(SolVM *vm);

/* The object a message sent to `value` is resolved against. */
SolObject *sol_vm_class_of(SolVM *vm, SolValue value);

/* Sends `name` to `receiver` and answers the reply.
 *
 * For primitives that need to call back into the language -- `fill` asking a
 * value for its `asString`, so that an override is honoured rather than
 * bypassed. Receiver and arguments are pushed onto the value stack for the
 * duration, so everything stays rooted even if the send allocates. Sets the
 * VM's error flag on failure. */
SolValue sol_vm_send(SolVM *vm, SolValue receiver, const char *name,
                     SolValue *args, int argc);

/* Runs `block` to completion and returns its value. Primitives use this to
   invoke a block, which is how `ifTrue` and `whileTrue` work without the
   compiler knowing anything about them. Sets the VM's error flag on failure. */
SolValue sol_vm_call_block(SolVM *vm, SolValue block, SolValue *args, int argc);

/* Reports a runtime error against the current instruction and unwinds. */
void sol_vm_runtime_error(SolVM *vm, const char *format, ...);

/* The complaint `whileTrue` makes when its condition answers something other
   than a boolean. Both forms of the loop -- the primitive and the inlined
   jumps -- go through here, so the two cannot come to word it differently. */
void sol_vm_condition_error(SolVM *vm, SolValue answer);

/* The same complaint for `and` and `or`, which name the message because there
   are two of them. Shared by the primitives and by OP_CHECK_BOOL for the same
   reason as above: an inlined form that worded this differently would be a
   difference the optimisation was not allowed to make. */
void sol_vm_block_answer_error(SolVM *vm, const char *name, SolValue answer);

/* Installs the built-in classes and their primitives. Called by sol_vm_init. */
void sol_builtins_install(SolVM *vm);

/* Name of a value's type, for error messages: "integer", "float", ... */
const char *sol_type_name(SolValue value);

#endif /* SOLUM_VM_H */
