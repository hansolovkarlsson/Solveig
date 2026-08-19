#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/gc.h"
#include "solum/vm.h"

static void reset_stack(SolVM *vm)
{
    vm->stack_top = vm->stack;
}

void sol_vm_init(SolVM *vm)
{
    vm->frame_count = 0;
    vm->had_error = false;
    vm->next_frame_id = 1;
    reset_stack(vm);

    /* Every root must be readable before the first allocation, because that
       allocation may collect -- and does on every one under stress. Leaving
       these until after the root object exists would have the collector trace
       uninitialised pointers. */
    vm->root = NULL;
    vm->integer_class = NULL;
    vm->float_class = NULL;
    vm->nil_class = NULL;
    vm->bool_class = NULL;
    vm->block_class = NULL;
    vm->array_class = NULL;
    vm->string_class = NULL;
    vm->object_class = NULL;

    vm->heap = NULL;
    vm->bytes_allocated = 0;
    vm->next_gc = SOL_GC_INITIAL_THRESHOLD;
    vm->gray = NULL;
    vm->gray_count = 0;
    vm->gray_capacity = 0;
    vm->temp_count = 0;
    vm->gc_stress = getenv("SOLUM_GC_STRESS") != NULL;

    /* The root Object is the globals namespace -- built-in class objects
       (`integer`, ...) live in its slots, and OP_GLOBAL resolves names against
       it. It also terminates every proto chain. */
    vm->root = sol_object_new(vm, NULL);

    sol_builtins_install(vm);
}

void sol_vm_free(SolVM *vm)
{
    sol_gc_free_all(vm);

    vm->root = NULL;
    vm->integer_class = NULL;
    vm->float_class = NULL;
    vm->nil_class = NULL;
    vm->bool_class = NULL;
    vm->block_class = NULL;
    vm->array_class = NULL;
    vm->string_class = NULL;
    vm->object_class = NULL;
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
    case SOL_ARRAY: return vm->array_class;
    case SOL_STRING: return vm->string_class;
    case SOL_DELEGATE: return NULL;   /* handled before dispatch reaches here */
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
    case SOL_ARRAY: return "array";
    case SOL_STRING: return "string";
    case SOL_DELEGATE: return "delegate";
    case SOL_OBJ:   return "object";
    }
    return "?";
}

void sol_vm_runtime_error(SolVM *vm, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    fputs("solvm: ", stderr);
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
                       int home_frame, uint64_t home_id)
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
    frame->home_frame = home_frame;
    frame->home_id = home_id;
    return true;
}

/* Walks `depth` steps out along the lexical chain from `frame` and answers that
   frame's slots.
 *
 * Every hop is checked: a frame's home is recorded by index *and* by an id
 * unique for the life of the VM, so a block whose enclosing frame has since
 * returned is reported rather than reading slots that now belong to someone
 * else. Depth is bounded by the verifier, but each step is validated anyway
 * because liveness is a runtime property. */
static SolValue *outer_slots(SolVM *vm, const SolFrame *frame, int depth)
{
    for (int i = 0; i < depth; i++) {
        int index = frame->home_frame;
        if (index < 0 || index >= vm->frame_count ||
            vm->frames[index].id != frame->home_id) {
            sol_vm_runtime_error(vm, "block outlived the frame it was written in");
            return NULL;
        }
        frame = &vm->frames[index];
    }
    return frame->slots;
}

static SolResult run_frames(SolVM *vm, int base);

SolValue sol_vm_call_block(SolVM *vm, SolValue block, SolValue *args, int argc)
{
    if (!SOL_IS_BLOCK(block)) {
        sol_vm_runtime_error(vm, "expected a block, got %s", sol_type_name(block));
        return SOL_NIL_VAL;
    }
    SolBlock *b = SOL_AS_BLOCK(block);

    if (vm->stack_top + argc + 1 > vm->stack + SOL_STACK_MAX) {
        sol_vm_runtime_error(vm, "stack overflow");
        return SOL_NIL_VAL;
    }

    int base = vm->frame_count;
    /* Slot 0 is the receiver the block was written under. A send to a slot
       holding this block supplies its own receiver instead, which is what makes
       an installed block behave as a method. */
    *vm->stack_top++ = b->self;
    for (int i = 0; i < argc; i++) *vm->stack_top++ = args[i];

    if (!push_frame(vm, b->code, argc, b->home_frame, b->home_id)) {
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

            /* Only the script's top level creates globals. Inside a method or
               block an undeclared name must already exist, so a typo cannot
               quietly bring a new global into being where it would look like a
               local. */
            if (frame->method != NULL && sol_object_lookup(vm->root, name) == NULL) {
                sol_vm_runtime_error(vm, "undefined name '%s' -- declare it with "
                                         "'| %s |' or assign it at the top level",
                                     name, name);
                break;
            }

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

        case OP_OUTER: {
            uint8_t depth = READ_BYTE();
            uint8_t slot = READ_BYTE();
            SolValue *slots = outer_slots(vm, frame, depth);
            if (slots == NULL) break;
            sol_vm_push(vm, slots[slot]);
            break;
        }

        case OP_SET_OUTER: {
            uint8_t depth = READ_BYTE();
            uint8_t slot = READ_BYTE();
            SolValue *slots = outer_slots(vm, frame, depth);
            if (slots == NULL) break;
            slots[slot] = vm->stack_top[-1];
            break;
        }

        case OP_STRING: {
            /* The literal's bytes live in the chunk's interned text, so the
               string is built fresh here. Immutability makes that only a cost,
               never a semantic difference -- see the roadmap on interning. */
            const char *text = READ_NAME();
            sol_vm_push(vm, SOL_STRING_VAL(
                sol_string_new(vm, text, (int)strlen(text))));
            break;
        }

        case OP_BLOCK: {
            const SolMethod *code = frame->chunk->methods.methods[READ_BYTE()];

            /* The block's home is the frame creating it. Blocks nested inside
               will home to this block's frame in turn, so reaching further out
               is a matter of depth along that chain.
       
               `self` is captured here rather than resolved lexically at compile
               time, because whether a given block ends up invoked as a method
               is not knowable until it is bound to a slot. */
            SolValue captured = frame->method != NULL ? frame->slots[0] : SOL_NIL_VAL;
            sol_vm_push(vm, SOL_BLOCK_VAL(
                sol_block_new(vm, code, captured, vm->frame_count - 1, frame->id)));
            break;
        }

        case OP_SET_SLOT: {
            const char *name = READ_NAME();

            /* `obj:name := value` -- the same operator as `a := value`, so the
               value is already evaluated and simply gets bound. A block bound
               this way is what makes a method. */
            SolValue value = sol_vm_pop(vm);
            SolValue target = sol_vm_pop(vm);
            if (!SOL_IS_OBJ(target)) {
                sol_vm_runtime_error(vm, "cannot bind '%s' on %s", name,
                                     sol_type_name(target));
                break;
            }
            sol_object_define(SOL_AS_OBJ(target), name, value);
            sol_vm_push(vm, value);          /* assignment answers its value */
            break;
        }

        case OP_SEND: {
            const char *name = READ_NAME();
            uint8_t argc = READ_BYTE();

            SolValue receiver = vm->stack_top[-1 - argc];
            SolObject *target;

            if (SOL_IS_DELEGATE(receiver)) {
                /* `self:via(ancestor):message` -- begin the search at the
                   ancestor, but run whatever is found with the original
                   receiver as self. Rewriting the stack slot is all that takes,
                   since everything below already reads self from there. */
                SolDelegate *delegate = SOL_AS_DELEGATE(receiver);
                target = delegate->start;
                receiver = delegate->receiver;
                vm->stack_top[-1 - argc] = receiver;
            } else {
                target = sol_vm_class_of(vm, receiver);
            }

            SolSlot *slot = target ? sol_object_lookup(target, name) : NULL;

            if (slot == NULL) {
                sol_vm_runtime_error(vm, "%s does not understand '%s'",
                                     sol_type_name(receiver), name);
                break;
            }

            /* A slot holding a block is a method: run it with the receiver as
               self, which the caller has already placed in slot position. A
               capturing block would need its home frame, and one bound as a
               method has outlived it, so this is where that is caught. */
            if (SOL_IS_BLOCK(slot->value)) {
                SolBlock *block = SOL_AS_BLOCK(slot->value);
                if (push_frame(vm, block->code, argc,
                               block->home_frame, block->home_id)) {
                    frame = &vm->frames[vm->frame_count - 1];
                }
                break;
            }

            /* Any other slot simply answers its value. */
            if (slot->primitive == NULL) {
                vm->stack_top -= argc + 1;
                sol_vm_push(vm, slot->value);
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

SolValue sol_vm_send(SolVM *vm, SolValue receiver, const char *name,
                     SolValue *args, int argc)
{
    SolObject *target = sol_vm_class_of(vm, receiver);
    SolSlot *slot = target ? sol_object_lookup(target, name) : NULL;
    if (slot == NULL) {
        sol_vm_runtime_error(vm, "%s does not understand '%s'",
                             sol_type_name(receiver), name);
        return SOL_NIL_VAL;
    }
    if (vm->stack_top + argc + 1 > vm->stack + SOL_STACK_MAX) {
        sol_vm_runtime_error(vm, "stack overflow");
        return SOL_NIL_VAL;
    }

    /* Laid out exactly as OP_SEND would, so everything below behaves the same
       and the arguments are rooted for the duration. */
    SolValue *base = vm->stack_top;
    *vm->stack_top++ = receiver;
    for (int i = 0; i < argc; i++) *vm->stack_top++ = args[i];

    SolValue result = SOL_NIL_VAL;

    if (SOL_IS_BLOCK(slot->value)) {
        SolBlock *block = SOL_AS_BLOCK(slot->value);
        int frame_base = vm->frame_count;
        if (push_frame(vm, block->code, argc, block->home_frame, block->home_id)) {
            if (run_frames(vm, frame_base) == SOL_OK) result = sol_vm_pop(vm);
            vm->frame_count = frame_base;
        }
    } else if (slot->primitive != NULL) {
        result = slot->primitive(vm, receiver, base + 1, argc);
    } else {
        result = slot->value;
    }

    vm->stack_top = base;
    return result;
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
    frame->home_frame = -1;          /* nothing encloses the script */
    frame->home_id = 0;

    SolResult result = run_frames(vm, 0);
    if (result != SOL_OK) {
        vm->frame_count = 0;
        reset_stack(vm);
    }
    return result;
}
