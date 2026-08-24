#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/gc.h"
#include "solum/vm.h"

static void reset_stack(SolVM *vm)
{
    vm->stack_top = vm->stack;
}

/* Serials handed to VMs, so a chunk can say whose interned names it holds
   without relying on an address that a later VM may be given again. Never
   reused, never zero -- zero is what a chunk from Solas carries, meaning no VM
   has resolved it yet.
 *
 * **Atomic, and it had to be measured to be believed.** This began as a plain
 * `uint64_t` and `next_vm_id++`, which is a read-modify-write: two threads
 * building a machine at the same time can be handed the same serial, and a
 * chunk shared between them then believes it is already resolved for the second
 * and dispatches against the first one's name table. That is the very defect
 * the serial was introduced to fix, reappearing in the fix.
 *
 * The window looked negligible -- three instructions inside a `sol_vm_init`
 * that takes about 52us -- and it is not: 16 threads building 480,000 machines
 * produced **10,319 duplicate serials**, a rate of 2.1%. A contended increment
 * is nothing like as brief as its instruction count suggests. Relaxed ordering
 * is enough, since nothing is being published alongside it; what is needed is
 * only that no two machines are handed one number. */
static _Atomic uint64_t next_vm_id = 1;

void sol_vm_init(SolVM *vm)
{
    vm->id = atomic_fetch_add_explicit(&next_vm_id, 1, memory_order_relaxed);
    vm->report_errors = true;
    vm->frame_count = 0;
    vm->had_error = false;
    vm->exiting = false;
    vm->trace = false;
    vm->trace_depth = 0;
    vm->debug_hook = NULL;
    vm->debug_failed = false;
    vm->debug_context = NULL;
    vm->debug_last_line = -1;
    vm->debug_last_frame_id = 0;
    vm->exit_code = 0;
    vm->stopped = false;
    vm->step_limit = 0;
    vm->steps_remaining = UINT64_MAX;   /* no limit, spelled as one that never runs out */
    vm->memory_limit = 0;
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
    vm->dict_class = NULL;
    vm->error_class = NULL;
    vm->time_class = NULL;
    vm->string_class = NULL;
    vm->object_class = NULL;
    vm->symbol_class = NULL;
    vm->symbols = NULL;
    vm->symbol_capacity = 0;
    vm->symbol_count = 0;

    vm->names = NULL;
    vm->name_capacity = 0;
    vm->name_count = 0;

    vm->heap = NULL;
    vm->bytes_allocated = 0;
    vm->next_gc = SOL_GC_INITIAL_THRESHOLD;
    vm->gray = NULL;
    vm->gray_count = 0;
    vm->gray_capacity = 0;
    vm->temp_count = 0;
    sol_text_init(&vm->error_message);
    sol_text_init(&vm->error_trace);
    vm->gc_stress = getenv("SOLUM_GC_STRESS") != NULL;

    /* The root Object is the globals namespace -- built-in class objects
       (`integer`, ...) live in its slots, and OP_GLOBAL resolves names against
       it. It also terminates every proto chain. */
    vm->root = sol_object_new(vm, NULL);

    sol_builtins_install(vm);
}

/* The array `system:arguments` answers. Built the way every array of fresh
 * values is: the elements go in as nil first, so that growing the backing store
 * happens while nothing new is live, and each string is then stored before the
 * next allocation can collect it.
 *
 * `arguments` is an ordinary data slot rather than a primitive, because it is
 * ordinary data: it does not change while the program runs, and a slot holding
 * an array is exactly what it is.
 */
void sol_vm_set_arguments(SolVM *vm, int count, char **args)
{
    SolSlot *slot = sol_object_lookup(vm->root, "system");
    if (slot == NULL || !SOL_IS_OBJ(slot->value)) return;

    SolArray *out = sol_array_new(vm, count);
    sol_gc_push_temp(vm, &out->gc);

    for (int i = 0; i < count; i++) sol_array_add(vm, out, SOL_NIL_VAL);
    for (int i = 0; i < count; i++) {
        out->items[i] = SOL_STRING_VAL(
            sol_string_new(vm, args[i], (int)strlen(args[i])));
    }

    sol_object_define(vm, SOL_AS_OBJ(slot->value), "arguments", SOL_ARRAY_VAL(out));
    sol_gc_pop_temp(vm);
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
    vm->dict_class = NULL;
    vm->error_class = NULL;
    vm->time_class = NULL;
    vm->string_class = NULL;
    vm->object_class = NULL;
    vm->symbol_class = NULL;

    sol_text_free(&vm->error_message);
    sol_text_free(&vm->error_trace);

    /* Last: the heap is gone, so nothing is left holding an interned name. */
    sol_vm_free_names(vm);
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
    case SOL_SYMBOL: return vm->symbol_class;
    case SOL_DELEGATE: return NULL;   /* handled before dispatch reaches here */
    case SOL_DICT:  return vm->dict_class;
    case SOL_TIME:  return vm->time_class;
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
    case SOL_SYMBOL: return "symbol";
    case SOL_DELEGATE: return "delegate";
    case SOL_DICT:  return "dictionary";
    case SOL_TIME:  return "time";
    case SOL_OBJ:   return "object";
    }
    return "?";
}

/* Appends a printf-style line to `out`. The buffer is generous rather than
   exact: a message can embed a rendered value, and truncating the one thing
   that says what went wrong would be a poor trade for a few bytes. */
static void append_formatted(SolText *out, const char *format, va_list args)
{
    char line[1024];
    int length = vsnprintf(line, sizeof line, format, args);
    if (length < 0) return;

    if (length >= (int)sizeof line) length = (int)sizeof line - 1;
    sol_text_append(out, line, length);
}

static void append_line(SolText *out, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    append_formatted(out, format, args);
    va_end(args);
}

/* Records what went wrong instead of printing it. `sol_vm_run` writes it out
   before returning, so nothing about the visible behaviour has changed -- but
   the message now exists as text the machine holds, which is what a handler
   will need in order to be given it. */
/* The stack beneath a message, innermost frame first, so the line that actually
   failed leads.
 *
 * Shared by a failure and by a stop, which want the same picture for opposite
 * reasons: one to say where the program went wrong, the other to say where it
 * had got to when it was taken away. */
static void append_stack_trace(SolVM *vm)
{
    /* A runaway recursion would bury the message under a full stack, so the
       middle is elided. */
    const int head = 8, tail = 3;
    for (int i = vm->frame_count - 1; i >= 0; i--) {
        int from_top = vm->frame_count - 1 - i;
        if (vm->frame_count > head + tail + 1 && from_top == head) {
            append_line(&vm->error_trace, "  ... %d more frames ...\n",
                        vm->frame_count - head - tail);
            i = tail;                    /* skip to the outermost few */
            continue;
        }
        SolFrame *frame = &vm->frames[i];
        /* The instruction just read, so back one from where `ip` now points.
           A frame stopped before its first instruction has nothing behind it
           and reports its first line, which is where it was about to be. */
        size_t offset = (size_t)(frame->ip - frame->chunk->code);
        if (offset > 0) offset--;

        /* The file as well as the line, when the chunk knows it. A chunk is one
           compiled unit and `@include` puts a library's code into the same one,
           so a bare line number named a line in a file nobody had said -- which
           read as a line of the file being looked at. A chunk compiled from
           text rather than a file has no name to give, and says just the line
           as it always did. */
        const char *file = sol_chunk_file_of(frame->chunk, (int)offset);
        const char *what = frame->method ? frame->method->name : "script";

        if (file[0] != '\0') {
            append_line(&vm->error_trace, "  [%s:%d] in %s\n",
                        file, frame->chunk->lines[offset], what);
        } else {
            append_line(&vm->error_trace, "  [line %d] in %s\n",
                        frame->chunk->lines[offset], what);
        }
    }
}

void sol_vm_runtime_error(SolVM *vm, const char *format, ...)
{
    /* The first error wins. Building a message can itself fail: a complaint
       that names a value renders it, and rendering sends `asString`. The
       failure that started it is the one worth reporting, and the one that
       followed is a consequence of trying to report it. */
    if (vm->had_error) return;

    va_list args;
    va_start(args, format);
    append_formatted(&vm->error_message, format, args);
    va_end(args);

    append_stack_trace(vm);

    vm->had_error = true;

    /* One last offer, with everything still standing. A debugger cannot resume
       from here -- the unwind is already decided -- but it can be looked at,
       which is the difference between a debugger and a prompt beside the wreck.
       Guarded against re-entry: reporting an error from inside the hook must
       not call the hook again. */
    if (vm->debug_hook != NULL && !vm->debug_failed) {
        vm->debug_failed = true;
        vm->debug_hook(vm, vm->debug_context);
        vm->debug_failed = false;
    }
}

/* A limit was reached. Unwinds like a failure and is not one.
 *
 * Not routed through `sol_vm_runtime_error` for two reasons that both matter.
 * A runtime error is the program's fault and this is not: nothing it did was
 * wrong, it was simply given less than it wanted. And a runtime error is
 * catchable, where this must not be -- `onError` and `ensure` both let it
 * through untouched, because a handler is code, running a handler is spending
 * the budget that just ran out, and a program that can run code after the limit
 * is a program the limit does not bind.
 *
 * A stop outranks an error already pending, and clears its message. The
 * program may well have been in the middle of failing -- a memory limit is
 * reached by allocating, and so is formatting the report of a failure -- but it
 * is being stopped, and that is the outcome its host has to hear about.
 */
void sol_vm_stop(SolVM *vm, const char *format, ...)
{
    if (vm->stopped) return;         /* the first stop wins, as the first error does */

    vm->error_message.length = 0;
    vm->error_trace.length = 0;

    va_list args;
    va_start(args, format);
    append_formatted(&vm->error_message, format, args);
    va_end(args);

    append_stack_trace(vm);

    vm->stopped   = true;
    vm->had_error = true;            /* the flag every loop already unwinds on */
    vm->exiting   = false;           /* and not the one that means it asked to go */
}

/* The receiver a primitive requires, spelled the way an error message wants it.
   Ten cases rather than a rule, because of the article. */
static const char *receiver_name(int type)
{
    switch (type) {
    case SOL_NIL:      return "nil";
    case SOL_BOOL:     return "a boolean";
    case SOL_INT:      return "an integer";
    case SOL_FLOAT:    return "a float";
    case SOL_BLOCK:    return "a block";
    case SOL_ARRAY:    return "an array";
    case SOL_STRING:   return "a string";
    case SOL_SYMBOL:   return "a symbol";
    case SOL_DELEGATE: return "a delegate";
    case SOL_OBJ:      return "an object";
    default:           return "something else";
    }
}

/* Finding a slot is not enough to run it.
 *
 * A built-in class holds the messages its *instances* understand, and answers
 * them itself: `array` is an object, `add` is one of its slots, so `array:add`
 * finds it -- and `prim_array_add` would then read the class object as an
 * array. Every primitive that reads its receiver's payload has always been
 * entitled to assume the type, because lookup went through the class that
 * describes it. That holds for every instance and fails for the one object
 * that is not one. See roadmap 1.6.
 *
 * Reports and answers false when the receiver does not suit.
 */
static bool receiver_suits(SolVM *vm, const SolSlot *slot, SolValue receiver)
{
    if (sol_slot_accepts(slot, receiver)) return true;

    sol_vm_runtime_error(vm, "'%s' expects %s, got %s", slot->name,
                         receiver_name(slot->receiver_type),
                         sol_type_name(receiver));
    return false;
}

void sol_vm_condition_error(SolVM *vm, SolValue answer)
{
    sol_vm_runtime_error(vm, "whileTrue expects the condition block to answer "
                             "a boolean, got %s", sol_type_name(answer));
}

void sol_vm_block_answer_error(SolVM *vm, const char *name, SolValue answer)
{
    sol_vm_runtime_error(vm, "'%s' expects the block to answer a boolean, got %s",
                         name, sol_type_name(answer));
}

/* ---- tracing ------------------------------------------------------------ *
 *
 * `solvm --trace` writes the call tree: one line entering a frame, one leaving
 * it, indented by depth. Frames rather than sends, which is what makes it
 * readable at all -- a send is arithmetic as often as it is a call, and there
 * are hundreds of thousands of those.
 *
 * This language is unusually well suited to it. Conditionals and loops written
 * literally compile to jumps, so a `whileTrue` running three hundred thousand
 * times produces **no trace lines**: what shows up is the calls, which is what
 * was wanted.
 *
 * To stderr, so a program's own output can still be piped somewhere.
 *
 * Values are rendered with a NULL VM, which is what the disassembler does and
 * for the same reason: rendering with one would *send* `asString`, and a trace
 * that runs the program it is tracing is not a trace. An object shows as its
 * address rather than however it likes to describe itself, which is the price.
 */
/* Whether this frame is within the depth being followed. */
static bool tracing_here(const SolVM *vm)
{
    if (!vm->trace) return false;
    return vm->trace_depth == 0 || vm->frame_count <= vm->trace_depth;
}

static void trace_indent(const SolVM *vm)
{
    for (int i = 0; i < vm->frame_count; i++) fputs("  ", stderr);
}

/* Cut long, because a trace is read by eye. A dictionary of a hundred keys
   rendered in full is one line nobody finishes, and what a trace is for is
   seeing the shape of what happened rather than the contents of everything it
   touched -- the value can be printed from inside the program when it matters. */
#define TRACE_VALUE_MAX 48

static void trace_value(SolValue value)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(NULL, value, &text);

    if (text.length > TRACE_VALUE_MAX) {
        fwrite(text.chars, 1, TRACE_VALUE_MAX - 3, stderr);
        fputs("...", stderr);
    } else {
        fwrite(text.chars, 1, (size_t)text.length, stderr);
    }
    sol_text_free(&text);
}

/* Where the call is written: the caller's line, and the file it is in. */
static void trace_caller_place(const SolVM *vm)
{
    if (vm->frame_count == 0) { fputs("[line 0] ", stderr); return; }

    const SolFrame *frame = &vm->frames[vm->frame_count - 1];
    int offset = (int)(frame->ip - frame->chunk->code) - 1;
    if (offset < 0) offset = 0;
    if (offset >= frame->chunk->count) offset = frame->chunk->count - 1;
    if (offset < 0) { fputs("[line 0] ", stderr); return; }

    const char *file = sol_chunk_file_of(frame->chunk, offset);
    if (file[0] != '\0') {
        fprintf(stderr, "[%s:%d] ", file, frame->chunk->lines[offset]);
    } else {
        fprintf(stderr, "[line %d] ", frame->chunk->lines[offset]);
    }
}

static void trace_call(const SolVM *vm, const SolMethod *code, int argc,
                       const SolValue *slots, const char *sent_as)
{
    trace_indent(vm);
    trace_caller_place(vm);

    /* Slot 0 is the receiver for a method, and for a block it is the `self` the
       block was *written under* -- nil for one written at the top level. Naming
       that would be accurate and useless, so a plain block is written as the
       call it is, and one carrying a self is written with it because that is a
       block installed as a method and the receiver is the interesting part. */
    if (sent_as != NULL) {
        /* The selector it was sent as, which for a block installed in a slot is
           the method name and is the thing worth reading. A block called
           directly has none, and says so by being written as the call it is. */
        trace_value(slots[0]);
        fprintf(stderr, ":%s", sent_as);
    } else if (!code->is_block) {
        trace_value(slots[0]);
        fprintf(stderr, ":%s", code->name);
    } else if (SOL_IS_NIL(slots[0])) {
        fputs("value", stderr);
    } else {
        trace_value(slots[0]);
        fputs(":value", stderr);
    }

    if (argc > 0) {
        fputc('(', stderr);
        for (int i = 0; i < argc; i++) {
            if (i > 0) fputs(", ", stderr);
            /* Named, when the chunk remembers what the parameter was called.
               Arguments land in slots 1..arity, so the name is the slot's. */
            const char *param = sol_chunk_slot_name(&code->chunk, i + 1);
            if (param[0] != '\0') fprintf(stderr, "%s: ", param);
            trace_value(slots[i + 1]);
        }
        fputc(')', stderr);
    }
    fputc('\n', stderr);
}

static void trace_return(const SolVM *vm, SolValue result)
{
    trace_indent(vm);
    fputs("-> ", stderr);
    trace_value(result);
    fputc('\n', stderr);
}

/* Pushes a frame. The receiver and arguments are already on the stack in slot
   order; any remaining locals are filled with nil. */
static bool push_frame(SolVM *vm, const SolMethod *code, int argc,
                       int home_frame, uint64_t home_id, const char *sent_as)
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

    if (tracing_here(vm)) trace_call(vm, code, argc, slots, sent_as);

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
    SolValue *mark = vm->stack_top;
    *vm->stack_top++ = b->self;
    for (int i = 0; i < argc; i++) *vm->stack_top++ = args[i];

    if (!push_frame(vm, b->code, argc, b->home_frame, b->home_id, NULL)) {
        vm->stack_top = mark;
        return SOL_NIL_VAL;
    }

    SolResult result = run_frames(vm, base);
    vm->frame_count = base;                         /* defensive: never leave frames behind */

    /* And the stack with it, which `sol_vm_send` has always done. A failure
       leaves the receiver, the arguments and whatever the frame was part-way
       through still on the stack, and that was invisible for as long as every
       error unwound to `sol_vm_run`, which resets the stack on its way out.
       `onError` stops the unwind, so execution carries on from here -- on
       whatever this left behind, unless it leaves nothing. */
    if (result != SOL_OK) {
        vm->stack_top = mark;
        return SOL_NIL_VAL;
    }
    return sol_vm_pop(vm);
}

static SolResult run_frames(SolVM *vm, int base)
{
    SolFrame *frame = &vm->frames[vm->frame_count - 1];

#define READ_BYTE() (*frame->ip++)
#define READ_SHORT() (frame->ip += 2, sol_read_u16(frame->ip - 2))
#define READ_INDEX() ((int)READ_SHORT())
#define READ_NAME() (sol_chunk_name(frame->chunk, READ_INDEX()))
/* The same name, as this VM's interned copy: what a lookup wants. Every chunk
   the VM runs went through sol_vm_intern_chunk, so the table is there. */
#define READ_INTERNED() (frame->chunk->interned[READ_INDEX()])

    for (;;) {
        /* The budget. One instruction is one step, counted here because this is
           the only place every instruction goes through -- a limit checked
           anywhere else is a limit with a way around it.
         *
           Post-decrement, so a limit of N runs N instructions and stops before
           the (N+1)th. With no limit the counter starts at UINT64_MAX and the
           test is the same test, which is why there is no branch here asking
           whether a limit was set: the unlimited case pays one decrement and
           one predictable compare, and reaches zero five hundred years from
           now.
         *
           An inlined loop is what makes this necessary. `whileTrue` written
           literally compiles to jumps, so it enters no frames and returns to no
           caller, and anything counting calls or watching the frame depth never
           sees it go round. Instructions it cannot hide from. */
        if (vm->steps_remaining-- == 0) {
            sol_vm_stop(vm, "stopped: the step limit of %llu was reached",
                        (unsigned long long)vm->step_limit);
            return SOL_STOPPED;
        }

        /* A stop point, when something is driving. Offered before the
           instruction runs, at each line the program moves to and each frame it
           enters or leaves -- which is what a person means by a step. The hook
           decides whether to take it; the machine only says where it is. */
        if (vm->debug_hook != NULL) {
            int offset = (int)(frame->ip - frame->chunk->code);
            int line = offset < frame->chunk->count ? frame->chunk->lines[offset] : 0;

            /* By frame *id* rather than by depth. A block whose whole body is
               one line, called over and over from a primitive, never changes
               either line or depth -- the frame goes and another is pushed at
               the same depth -- so a depth test offered one stop for a loop of
               a thousand. An id is unique for the life of the VM, so a new
               frame is always a new place to be. */
            if (line != vm->debug_last_line || frame->id != vm->debug_last_frame_id) {
                vm->debug_last_line = line;
                vm->debug_last_frame_id = frame->id;
                vm->debug_hook(vm, vm->debug_context);
                if (vm->had_error || vm->exiting) {
                    return vm->stopped ? SOL_STOPPED : SOL_RUNTIME_ERROR;
                }
            }
        }

        uint8_t instruction = READ_BYTE();
        switch (instruction) {

        case OP_CONST:
            sol_vm_push(vm, frame->chunk->constants.values[READ_INDEX()]);
            break;

        case OP_NIL:
            sol_vm_push(vm, SOL_NIL_VAL);
            break;

        case OP_GLOBAL: {
            const char *name = READ_INTERNED();
            SolSlot *slot = sol_object_lookup_interned(vm, vm->root, name);
            if (slot == NULL) {
                sol_vm_runtime_error(vm, "undefined name '%s'", name);
                break;
            }
            sol_vm_push(vm, slot->value);
            break;
        }

        case OP_SET_GLOBAL: {
            const char *name = READ_INTERNED();

            /* Only the script's top level creates globals. Inside a method or
               block an undeclared name must already exist, so a typo cannot
               quietly bring a new global into being where it would look like a
               local. */
            if (frame->method != NULL &&
                sol_object_lookup_interned(vm, vm->root, name) == NULL) {
                sol_vm_runtime_error(vm, "undefined name '%s' -- declare it with "
                                         "'| %s |' or assign it at the top level",
                                     name, name);
                break;
            }

            /* Assignment is an expression: the value stays on the stack so
               `c := b := #45` works and the statement's POP discards it. */
            sol_object_define_interned(vm, vm->root, name, vm->stack_top[-1]);
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

        case OP_SYMBOL: {
            const char *text = READ_NAME();
            sol_vm_push(vm, SOL_SYMBOL_VAL(
                sol_symbol_intern(vm, text, (int)strlen(text))));
            break;
        }

        case OP_BLOCK: {
            const SolMethod *code = frame->chunk->methods.methods[READ_INDEX()];

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
            const char *name = READ_INTERNED();

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
            sol_object_define_interned(vm, SOL_AS_OBJ(target), name, value);
            sol_vm_push(vm, value);          /* assignment answers its value */
            break;
        }

        case OP_SEND: {
            const char *name = READ_INTERNED();
            uint8_t argc = READ_BYTE();

            /* A `.sob` is untrusted and `argc` is a byte the verifier cannot
               bound on its own: whether 227 arguments are really on the stack
               depends on the stack height at this instruction, which needs an
               analysis the verifier does not do yet (3.9). Without this check a
               corrupted count reads the receiver from below the frame -- found
               by fuzzing, and older than the jumps that exposed it. */
            if (vm->stack_top - (argc + 1) < frame->slots) {
                sol_vm_runtime_error(vm, "stack underflow");
                break;
            }

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

            SolSlot *slot = target ? sol_object_lookup_interned(vm, target, name)
                                   : NULL;

            if (slot == NULL) {
                sol_vm_runtime_error(vm, "%s does not understand '%s'",
                                     sol_type_name(receiver), name);
                break;
            }

            if (!receiver_suits(vm, slot, receiver)) break;

            /* A slot holding a block is a method: run it with the receiver as
               self, which the caller has already placed in slot position. A
               capturing block would need its home frame, and one bound as a
               method has outlived it, so this is where that is caught. */
            if (SOL_IS_BLOCK(slot->value)) {
                SolBlock *block = SOL_AS_BLOCK(slot->value);
                if (push_frame(vm, block->code, argc,
                               block->home_frame, block->home_id, name)) {
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

        case OP_JUMP:
            frame->ip += READ_SHORT();
            break;

        /* An inlined `whileTrue`, closing the loop. The only instruction that
           moves the ip backwards; the verifier has established that it lands
           on the start of an instruction in this chunk. It can spin, but so can
           the loop it was compiled from -- non-termination is something the
           source language already allows, not something bytecode can reach that
           source cannot. */
        case OP_LOOP:
            frame->ip -= READ_SHORT();
            break;

        /* An inlined `whileTrue`, testing its condition. */
        case OP_EXIT_IF_FALSE: {
            uint16_t offset = READ_SHORT();
            SolValue condition = sol_vm_pop(vm);

            if (!SOL_IS_BOOL(condition)) {
                sol_vm_condition_error(vm, condition);
                break;
            }
            if (!SOL_AS_BOOL(condition)) frame->ip += offset;
            break;
        }

        /* An inlined `and` or `or`, checking what its block answered. The
           value goes back: it is the reply, where the two tests below consume
           the boolean they branch on. Popping and pushing rather than reading
           the top in place borrows pop's underflow guard, which a corrupted
           chunk reaching here with an empty stack still needs. */
        case OP_CHECK_BOOL: {
            const char *name = READ_NAME();
            SolValue answer = sol_vm_pop(vm);

            if (!SOL_IS_BOOL(answer)) {
                sol_vm_block_answer_error(vm, name, answer);
                break;
            }
            sol_vm_push(vm, answer);
            break;
        }

        /* The compiler emits this for an inlined `ifTrue`/`ifFalse`/`ifElse`.
           Offsets are forward only, so no bytecode the compiler writes can loop
           here -- and the verifier has already established that the target is
           the start of an instruction in this chunk. */
        case OP_JUMP_IF_FALSE: {
            uint16_t offset = READ_SHORT();
            const char *name = READ_NAME();
            SolValue condition = sol_vm_pop(vm);

            /* Inlining must not change what the program means, and only a
               boolean understands these. Reported exactly as the send it
               replaced would have. */
            if (!SOL_IS_BOOL(condition)) {
                sol_vm_runtime_error(vm, "%s does not understand '%s'",
                                     sol_type_name(condition), name);
                break;
            }
            if (!SOL_AS_BOOL(condition)) frame->ip += offset;
            break;
        }

        case OP_POP:
            sol_vm_pop(vm);
            break;

        case OP_RETURN: {
            SolValue result = sol_vm_pop(vm);
            vm->frame_count--;
            /* After the decrement, so the depth this is tested at is the one
               the matching call was written at. */
            if (tracing_here(vm)) trace_return(vm, result);

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

        /* One flag stops the machine and the other says why. Every loop that
           has to unwind already tests `had_error`, and an exit unwinds through
           exactly those, so it sets that one too rather than adding a second
           test to each of them. */
        if (vm->had_error) {
            if (vm->exiting) return SOL_EXIT;
            return vm->stopped ? SOL_STOPPED : SOL_RUNTIME_ERROR;
        }
    }

#undef READ_INTERNED
#undef READ_NAME
#undef READ_INDEX
#undef READ_SHORT
#undef READ_BYTE
}

SolValue sol_vm_send(SolVM *vm, SolValue receiver, const char *name,
                     SolValue *args, int argc)
{
    /* Called from C with an ordinary literal, so the name is interned here
       rather than by the caller. One hash, then the same pointer comparison
       the dispatch loop does. */
    name = sol_vm_intern_name(vm, name, (int)strlen(name));

    SolObject *target = sol_vm_class_of(vm, receiver);
    SolSlot *slot = target ? sol_object_lookup_interned(vm, target, name) : NULL;
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
        if (push_frame(vm, block->code, argc, block->home_frame, block->home_id,
                       name)) {
            if (run_frames(vm, frame_base) == SOL_OK) result = sol_vm_pop(vm);
            vm->frame_count = frame_base;
        }
    } else if (slot->primitive != NULL) {
        if (receiver_suits(vm, slot, receiver)) {
            result = slot->primitive(vm, receiver, base + 1, argc);
        }
    } else {
        result = slot->value;
    }

    vm->stack_top = base;
    return result;
}

/* Resolves one chunk's names, then every method nested inside it. Recursion
   depth here is nesting depth in the source, which the compiler already bounds.
 *
 * Doing this per chunk rather than per send is the whole point: the hash is
 * paid once for each name a chunk mentions, and every send of it afterwards is
 * a pointer comparison. */
void sol_vm_intern_chunk(SolVM *vm, SolChunk *chunk)
{
    if (chunk->interned_for != vm->id) {
        free(chunk->interned);
        chunk->interned = NULL;
    }
    if (chunk->interned == NULL && chunk->names.count > 0) {
        chunk->interned = malloc((size_t)chunk->names.count * sizeof *chunk->interned);
        if (chunk->interned == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        for (int i = 0; i < chunk->names.count; i++) {
            const char *name = chunk->names.names[i];
            chunk->interned[i] = sol_vm_intern_name(vm, name, (int)strlen(name));
        }
    }
    chunk->interned_for = vm->id;

    for (int i = 0; i < chunk->methods.count; i++) {
        sol_vm_intern_chunk(vm, &chunk->methods.methods[i]->chunk);
    }
}

void sol_vm_set_step_limit(SolVM *vm, uint64_t steps)
{
    vm->step_limit = steps;
    vm->steps_remaining = steps > 0 ? steps : UINT64_MAX;
}

void sol_vm_set_memory_limit(SolVM *vm, size_t bytes)
{
    vm->memory_limit = bytes;
}

void sol_vm_set_error_reporting(SolVM *vm, bool on)
{
    vm->report_errors = on;
}

SolResult sol_vm_run(SolVM *vm, const SolChunk *chunk)
{
    vm->had_error = false;
    vm->exiting = false;
    vm->stopped = false;

    /* The allowance is per run, not per VM. A server that hands one machine a
       request and then another means each request to have the whole of it,
       rather than the second inheriting what the first left. */
    vm->steps_remaining = vm->step_limit > 0 ? vm->step_limit : UINT64_MAX;

    vm->error_message.length = 0;   /* keeps the buffers, drops last run's text */
    vm->error_trace.length = 0;
    vm->frame_count = 0;
    reset_stack(vm);

    /* Resolve the names once, here, so every send below is a pointer compare.
       The chunk is const to callers because running must not rewrite the code;
       the resolved table is an accelerator beside it, not part of it. */
    sol_vm_intern_chunk(vm, (SolChunk *)chunk);

    /* The top-level chunk runs in a frame like anything else, so one code path
       handles both. It has no method, no locals, and no home. */
    SolFrame *frame = &vm->frames[vm->frame_count++];
    frame->method = NULL;
    frame->chunk = chunk;
    frame->ip = chunk->code;
    frame->slots = vm->stack;

    /* Reserve the script's slots before the first instruction, exactly as
       `push_frame` reserves a method's. Slot 0 is the unnameable one every
       frame has; the rest are temporaries the top level declared. A script that
       declares none reserves one slot and never reads it. */
    for (int i = 0; i < chunk->slot_count; i++) *vm->stack_top++ = SOL_NIL_VAL;
    frame->id = vm->next_frame_id++;
    frame->home_frame = -1;          /* nothing encloses the script */
    frame->home_id = 0;

    SolResult result = run_frames(vm, 0);
    if (result != SOL_OK) {
        vm->frame_count = 0;
        reset_stack(vm);
    }

    /* Nothing caught it, so it is written out here -- the one place that knows
       the program is over and no handler is coming. `system:exit` unwinds
       through the same flag and is not a failure, so it says nothing.

       This is why deferring the write changed no behaviour: the message still
       reaches stderr before `sol_vm_run` answers, exactly as it did when the
       write happened where the failure was.

       Unless a host asked for the failure to be its own. The text is kept
       either way -- what `report_errors` decides is whether this function also
       puts it somewhere the host did not choose. */
    if (vm->report_errors && vm->had_error && !vm->exiting &&
        vm->error_message.length > 0) {
        fprintf(stderr, "solvm: %s\n", vm->error_message.chars);
        if (vm->error_trace.length > 0) fputs(vm->error_trace.chars, stderr);
    }
    return result;
}
