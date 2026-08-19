/* vm.h -- the Solum virtual machine. */
#ifndef SOLUM_VM_H
#define SOLUM_VM_H

#include "solum/common.h"
#include "solum/bytecode.h"
#include "solum/object.h"

#define SOL_STACK_MAX 256

typedef enum {
    SOL_OK,
    SOL_COMPILE_ERROR,
    SOL_RUNTIME_ERROR
} SolResult;

struct SolVM {
    const SolChunk *chunk;
    const uint8_t  *ip;

    SolValue  stack[SOL_STACK_MAX];
    SolValue *stack_top;

    SolObject *root;      /* globals namespace; also ends every proto chain */
    SolObject *objects;   /* head of the all-objects list */

    /* Class objects for the unboxed value types. A message sent to #45 is
       resolved against integer_class, which is what keeps "everything is an
       object" true without boxing every number. */
    SolObject *integer_class;
    SolObject *float_class;
    SolObject *nil_class;

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

/* Reports a runtime error against the current instruction and unwinds. */
void sol_vm_runtime_error(SolVM *vm, const char *format, ...);

/* Installs the built-in classes and their primitives. Called by sol_vm_init. */
void sol_builtins_install(SolVM *vm);

/* Name of a value's type, for error messages: "integer", "float", ... */
const char *sol_type_name(SolValue value);

#endif /* SOLUM_VM_H */
