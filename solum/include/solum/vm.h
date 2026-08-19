/* vm.h -- the Solum virtual machine. */
#ifndef SOLUM_VM_H
#define SOLUM_VM_H

#include "solum/common.h"
#include "solum/bytecode.h"
#include "solum/object.h"

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
    SOL_RUNTIME_ERROR
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
    SolObject *string_class;
    SolObject *object_class;

    bool had_error;
};

void sol_vm_init(SolVM *vm);
void sol_vm_free(SolVM *vm);

/* Executes `chunk` to completion. */
SolResult sol_vm_run(SolVM *vm, const SolChunk *chunk);

void     sol_vm_push(SolVM *vm, SolValue value);
SolValue sol_vm_pop(SolVM *vm);

/* The object a message sent to `value` is resolved against. */
SolObject *sol_vm_class_of(SolVM *vm, SolValue value);

/* Sends `name` to `receiver` and answers the reply.
 *
 * For primitives that need to call back into the language -- `format` asking a
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

/* Installs the built-in classes and their primitives. Called by sol_vm_init. */
void sol_builtins_install(SolVM *vm);

/* Name of a value's type, for error messages: "integer", "float", ... */
const char *sol_type_name(SolValue value);

#endif /* SOLUM_VM_H */
