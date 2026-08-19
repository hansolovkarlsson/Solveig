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
    vm->frame_count = 0;
    vm->objects = NULL;
    vm->blocks = NULL;
    vm->next_frame_id = 1;
    vm->had_error = false;
    reset_stack(vm);

    /* The root Object is the globals namespace -- built-in class objects
       (`integer`, ...) live in its slots, and OP_GLOBAL resolves names against
       it. It also terminates every proto chain. */
    vm->root = sol_object_new(vm, NULL);
    vm->integer_class = NULL;
    vm->float_class = NULL;
    vm->nil_class = NULL;
    vm->bool_class = NULL;
    vm->block_class = NULL;

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

    SolBlock *block = vm->blocks;
    while (block != NULL) {
        SolBlock *next = block->next;
        free(block);
        block = next;
    }
    vm->blocks = NULL;

    vm->root = NULL;
    vm->integer_class = NULL;
    vm->float_class = NULL;
    vm->nil_class = NULL;
    vm->bool_class = NULL;
    vm->block_class = NULL;
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
    case SOL_BOOL:  return vm->bool_class;
    case SOL_BLOCK: return vm->block_class;
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
    case SOL_BOOL:  return "boolean";
    case SOL_BLOCK: return "block";
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

    /* Innermost frame first, so the line that actually failed leads. A runaway
       recursion would otherwise bury the message under a full stack, so the
       middle is elided. */
    const int head = 8, tail = 3;
    for (int i = vm->frame_count - 1; i >= 0; i--) {
        int from_top = vm->frame_count - 1 - i;
        if (vm->frame_count > head + tail + 1 && from_top == head) {
            fprintf(stderr, "  ... %d more frames ...\n",
                    vm->frame_count - head - tail);
            i = tail;                    /* skip to the outermost few */
            continue;
        }
        SolFrame *frame = &vm->frames[i];
        size_t offset = (size_t)(frame->ip - frame->chunk->code) - 1;
        fprintf(stderr, "  [line %d] in %s\n", frame->chunk->lines[offset],
                frame->method ? frame->method->name : "script");
    }
    vm->had_error = true;
}

/* Pushes a frame. The receiver and arguments are already on the stack in slot
   order; any remaining locals are filled with nil. */
static bool push_frame(SolVM *vm, const SolMethod *code, int argc,
                       SolValue *home_slots, int home_frame, uint64_t home_id)
{
    if (argc != code->arity) {
        sol_vm_runtime_error(vm, "'%s' takes %d argument%s, got %d",
                             code->is_block ? "block" : code->name, code->arity,
                             code->arity == 1 ? "" : "s", argc);
        return false;
    }
    if (vm->frame_count == SOL_FRAMES_MAX) {
        sol_vm_runtime_error(vm, "call depth exceeded");
        return false;
    }

    SolValue *slots = vm->stack_top - argc - 1;   /* slots[0] is the receiver */
    int extra = code->slot_count - (argc + 1);
    if (vm->stack_top + extra > vm->stack + SOL_STACK_MAX) {
        sol_vm_runtime_error(vm, "stack overflow");
        return false;
    }
    for (int i = 0; i < extra; i++) *vm->stack_top++ = SOL_NIL_VAL;

    SolFrame *frame = &vm->frames[vm->frame_count++];
    frame->method = code;
    frame->chunk = &code->chunk;
    frame->ip = code->chunk.code;
    frame->slots = slots;
    frame->id = vm->next_frame_id++;
    frame->home_slots = home_slots;
    frame->home_frame = home_frame;
    frame->home_id = home_id;
    return true;
}

/* A block's home frame must still be the one it captured. Frame ids are unique
   for the life of the VM, so a block that outlived its method is caught here
   rather than reading slots that now belong to someone else. */
static SolValue *resolve_home(SolVM *vm, const SolBlock *block)
{
    if (block->home_frame >= vm->frame_count ||
        vm->frames[block->home_frame].id != block->home_id) {
        sol_vm_runtime_error(vm, "block outlived the method that created it");
        return NULL;
    }
    return vm->frames[block->home_frame].slots;
}

static SolResult run_frames(SolVM *vm, int base);

SolValue sol_vm_call_block(SolVM *vm, SolValue block, SolValue *args, int argc)
{
    if (!SOL_IS_BLOCK(block)) {
        sol_vm_runtime_error(vm, "expected a block, got %s", sol_type_name(block));
        return SOL_NIL_VAL;
    }
    SolBlock *b = SOL_AS_BLOCK(block);
    SolValue *home = NULL;
    if (b->code->captures) {
        home = resolve_home(vm, b);
        if (home == NULL) return SOL_NIL_VAL;
    }

    if (vm->stack_top + argc + 1 > vm->stack + SOL_STACK_MAX) {
        sol_vm_runtime_error(vm, "stack overflow");
        return SOL_NIL_VAL;
    }

    int base = vm->frame_count;
    *vm->stack_top++ = block;                       /* the block is its own receiver */
    for (int i = 0; i < argc; i++) *vm->stack_top++ = args[i];

    if (!push_frame(vm, b->code, argc, home, b->home_frame, b->home_id)) {
        vm->stack_top -= argc + 1;
        return SOL_NIL_VAL;
    }

    SolResult result = run_frames(vm, base);
    vm->frame_count = base;                         /* defensive: never leave frames behind */
    if (result != SOL_OK) return SOL_NIL_VAL;
    return sol_vm_pop(vm);
}

static SolResult run_frames(SolVM *vm, int base)
{
    SolFrame *frame = &vm->frames[vm->frame_count - 1];

#define READ_BYTE() (*frame->ip++)
#define READ_NAME() (sol_chunk_name(frame->chunk, READ_BYTE()))

    for (;;) {
        uint8_t instruction = READ_BYTE();
        switch (instruction) {

        case OP_CONST:
            sol_vm_push(vm, frame->chunk->constants.values[READ_BYTE()]);
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

        case OP_LOCAL:
            sol_vm_push(vm, frame->slots[READ_BYTE()]);
            break;

        case OP_SET_LOCAL:
            frame->slots[READ_BYTE()] = vm->stack_top[-1];
            break;

        case OP_OUTER:
            sol_vm_push(vm, frame->home_slots[READ_BYTE()]);
            break;

        case OP_SET_OUTER:
            frame->home_slots[READ_BYTE()] = vm->stack_top[-1];
            break;

        case OP_BLOCK: {
            const SolMethod *code = frame->chunk->methods.methods[READ_BYTE()];

            /* A block written inside a block shares the enclosing method's
               frame -- capture is lexical, so it skips past intermediate
               block frames rather than stopping at the nearest one. */
            int home_frame;
            uint64_t home_id;
            if (frame->method != NULL && frame->method->is_block) {
                home_frame = frame->home_frame;
                home_id = frame->home_id;
            } else {
                home_frame = vm->frame_count - 1;
                home_id = frame->id;
            }
            sol_vm_push(vm, SOL_BLOCK_VAL(sol_block_new(vm, code, home_frame, home_id)));
            break;
        }

        case OP_DEF_METHOD: {
            const SolMethod *method = frame->chunk->methods.methods[READ_BYTE()];
            const char *name = READ_NAME();

            /* The target stays on the stack, the way an assignment leaves its
               value, so the enclosing statement's POP cleans up. */
            SolValue target = vm->stack_top[-1];
            if (!SOL_IS_OBJ(target)) {
                sol_vm_runtime_error(vm, "cannot define '%s' on %s", name,
                                     sol_type_name(target));
                break;
            }
            sol_object_define_method(SOL_AS_OBJ(target), name, method);
            break;
        }

        case OP_SEND: {
            const char *name = READ_NAME();
            uint8_t argc = READ_BYTE();

            SolValue receiver = vm->stack_top[-1 - argc];
            SolObject *target = sol_vm_class_of(vm, receiver);
            SolSlot *slot = target ? sol_object_lookup(target, name) : NULL;

            if (slot == NULL) {
                sol_vm_runtime_error(vm, "%s does not understand '%s'",
                                     sol_type_name(receiver), name);
                break;
            }

            if (slot->method != NULL) {
                if (push_frame(vm, slot->method, argc, NULL, 0, 0)) {
                    frame = &vm->frames[vm->frame_count - 1];
                }
                break;
            }

            if (slot->primitive == NULL) {
                sol_vm_runtime_error(vm, "'%s' is a slot, not a message", name);
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

        case OP_RETURN: {
            SolValue result = sol_vm_pop(vm);
            vm->frame_count--;

            /* Discard the whole activation -- self, arguments, and locals --
               then leave the reply where the receiver was. */
            vm->stack_top = frame->slots;
            sol_vm_push(vm, result);

            if (vm->frame_count == base) return SOL_OK;
            frame = &vm->frames[vm->frame_count - 1];
            break;
        }

        case OP_HALT:
            return SOL_OK;

        default:
            sol_vm_runtime_error(vm, "unknown opcode %d", instruction);
            break;
        }

        if (vm->had_error) return SOL_RUNTIME_ERROR;
    }

#undef READ_NAME
#undef READ_BYTE
}

SolResult sol_vm_run(SolVM *vm, const SolChunk *chunk)
{
    vm->had_error = false;
    vm->frame_count = 0;
    reset_stack(vm);

    /* The top-level chunk runs in a frame like anything else, so one code path
       handles both. It has no method, no locals, and no home. */
    SolFrame *frame = &vm->frames[vm->frame_count++];
    frame->method = NULL;
    frame->chunk = chunk;
    frame->ip = chunk->code;
    frame->slots = vm->stack;
    frame->id = vm->next_frame_id++;
    frame->home_slots = NULL;
    frame->home_frame = 0;
    frame->home_id = 0;

    SolResult result = run_frames(vm, 0);
    if (result != SOL_OK) {
        vm->frame_count = 0;
        reset_stack(vm);
    }
    return result;
}
