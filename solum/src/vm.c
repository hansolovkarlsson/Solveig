#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "solum/vm.h"

static void reset_stack(SolVM *vm)
{
    vm->stack_top = vm->stack;
}

void sol_vm_init(SolVM *vm)
{
    vm->chunk = NULL;
    vm->ip = NULL;
    vm->objects = NULL;
    vm->had_error = false;
    reset_stack(vm);

    /* The root Object is the globals namespace -- built-in class objects
       (`integer`, ...) live in its slots, and OP_GLOBAL resolves names against
       it. It also terminates every proto chain. */
    vm->root = sol_object_new(vm, NULL);
    vm->integer_class = NULL;
    vm->float_class = NULL;
    vm->nil_class = NULL;

    sol_builtins_install(vm);
}

void sol_vm_free(SolVM *vm)
{
    /* TODO: replace with a real collector. For now every object is freed at
       shutdown by walking the all-objects list. */
    SolObject *obj = vm->objects;
    while (obj != NULL) {
        SolObject *next = obj->next;
        SolSlot *slot = obj->slots;
        while (slot != NULL) {
            SolSlot *slot_next = slot->next;
            free(slot->name);
            free(slot);
            slot = slot_next;
        }
        free(obj);
        obj = next;
    }
    vm->objects = NULL;
    vm->root = NULL;
    vm->integer_class = NULL;
    vm->float_class = NULL;
    vm->nil_class = NULL;
    reset_stack(vm);
}

void sol_vm_push(SolVM *vm, SolValue value)
{
    if (vm->stack_top - vm->stack >= SOL_STACK_MAX) {
        sol_vm_runtime_error(vm, "stack overflow");
        return;
    }
    *vm->stack_top++ = value;
}

SolValue sol_vm_pop(SolVM *vm)
{
    if (vm->stack_top == vm->stack) {
        sol_vm_runtime_error(vm, "stack underflow");
        return SOL_NIL_VAL;
    }
    return *--vm->stack_top;
}

SolObject *sol_vm_class_of(SolVM *vm, SolValue value)
{
    switch (value.type) {
    case SOL_INT:   return vm->integer_class;
    case SOL_FLOAT: return vm->float_class;
    case SOL_NIL:   return vm->nil_class;
    case SOL_OBJ:   return SOL_AS_OBJ(value);   /* the object answers for itself */
    }
    return NULL;
}

const char *sol_type_name(SolValue value)
{
    switch (value.type) {
    case SOL_INT:   return "integer";
    case SOL_FLOAT: return "float";
    case SOL_NIL:   return "nil";
    case SOL_OBJ:   return "object";
    }
    return "?";
}

void sol_vm_runtime_error(SolVM *vm, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    fputs("solum: ", stderr);
    vfprintf(stderr, format, args);
    va_end(args);
    fputs("\n", stderr);

    if (vm->chunk != NULL && vm->ip != NULL) {
        size_t offset = (size_t)(vm->ip - vm->chunk->code) - 1;
        fprintf(stderr, "  [line %d]\n", vm->chunk->lines[offset]);
    }
    vm->had_error = true;
}

SolResult sol_vm_run(SolVM *vm, const SolChunk *chunk)
{
    vm->chunk = chunk;
    vm->ip = chunk->code;
    vm->had_error = false;

#define READ_BYTE() (*vm->ip++)
#define READ_NAME() (sol_chunk_name(chunk, READ_BYTE()))

    for (;;) {
        uint8_t instruction = READ_BYTE();
        switch (instruction) {

        case OP_CONST:
            sol_vm_push(vm, chunk->constants.values[READ_BYTE()]);
            break;

        case OP_NIL:
            sol_vm_push(vm, SOL_NIL_VAL);
            break;

        case OP_GLOBAL: {
            const char *name = READ_NAME();
            SolSlot *slot = sol_object_lookup(vm->root, name);
            if (slot == NULL) {
                sol_vm_runtime_error(vm, "undefined name '%s'", name);
                break;
            }
            sol_vm_push(vm, slot->value);
            break;
        }

        case OP_SET_GLOBAL: {
            const char *name = READ_NAME();
            /* Assignment is an expression: the value stays on the stack so
               `c := b := #45` works and the statement's POP discards it. */
            sol_object_define(vm->root, name, vm->stack_top[-1]);
            break;
        }

        case OP_SEND: {
            const char *name = READ_NAME();
            uint8_t argc = READ_BYTE();

            SolValue receiver = vm->stack_top[-1 - argc];
            SolObject *target = sol_vm_class_of(vm, receiver);
            SolSlot *slot = target ? sol_object_lookup(target, name) : NULL;

            if (slot == NULL || slot->primitive == NULL) {
                sol_vm_runtime_error(vm, "%s does not understand '%s'",
                                     sol_type_name(receiver), name);
                break;
            }

            SolValue result = slot->primitive(vm, receiver,
                                              vm->stack_top - argc, argc);
            vm->stack_top -= argc + 1;          /* drop arguments and receiver */
            if (!vm->had_error) sol_vm_push(vm, result);
            break;
        }

        case OP_POP:
            sol_vm_pop(vm);
            break;

        case OP_RETURN:
            /* TODO: pop the call frame once bytecode methods exist. Every
               method is currently a C primitive, so nothing emits this yet. */
            return SOL_OK;

        case OP_HALT:
            return SOL_OK;

        default:
            sol_vm_runtime_error(vm, "unknown opcode %d", instruction);
            break;
        }

        if (vm->had_error) {
            reset_stack(vm);
            return SOL_RUNTIME_ERROR;
        }
    }

#undef READ_NAME
#undef READ_BYTE
}
