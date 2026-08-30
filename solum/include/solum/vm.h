/* vm.h -- the Solum virtual machine. */
#ifndef SOLUM_VM_H
#define SOLUM_VM_H

#include "solum/common.h"
#include "solum/bytecode.h"
#include "solum/object.h"
#include "solum/value.h"

/* How deep calls may nest, and how many values may be live at once.
 *
 * The two used to be one number -- the stack was FRAMES * 256, on the reasoning
 * that a frame may hold 256 slots because a slot index is a u8. That made the
 * cap expensive to raise: a SolVM holds both arrays inline and lives on the C
 * stack, including on threads, where the default is often 512KB. At the old 64
 * frames the machine was already 260KB, nearly all of it stack, so raising the
 * cap eightfold would have made a VM too big to put on a thread at all.
 *
 * They are separate now. Frames are cheap -- 56 bytes each -- and the stack is
 * sized on its own, generously, for how many values a program actually holds
 * live rather than for a worst case no program reaches. Both are checked: going
 * past the frames is `call depth exceeded` and going past the stack is `stack
 * overflow`, and each is an ordinary catchable failure rather than a crash. */
#define SOL_FRAMES_MAX 256
#define SOL_STACK_MAX  16384

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
    SOL_EXIT,             /* the program asked to stop; `exit_code` says with what */
    SOL_STOPPED           /* a limit stopped it: it neither finished nor asked to */
} SolResult;

/* One value an extension has asked the collector to keep.
 *
 * A slot rather than a bare SolValue because of `generation`, which is what
 * makes a stale token *detectable*. Without it, releasing slot 5 and later
 * retaining into slot 5 would leave an old token resolving to a different
 * value -- which is the exact failure this registry exists to prevent, moved
 * from the collector into the registry. Bumped on every release, so a token
 * from before it answers nothing.
 *
 * `in_use` and `next_free` are two fields because they were one and that was a
 * bug: -1 meant both "in use" and "end of the free list", so releasing into an
 * empty free list wrote -1 and marked the slot live again. A second release
 * then answered true and the slot was on the free list twice. Caught by
 * test_retain.c's `test_releasing_twice_is_not_an_error`, which is exactly the
 * kind of case worth writing even when it looks like it cannot fail.
 *
 * Releasing and retaining are both constant time, and the array never shrinks
 * or shifts. Nothing may shift: a token is an index. */
typedef struct {
    SolValue value;
    uint32_t generation;
    bool     in_use;
    int      next_free;      /* meaningful only when `in_use` is false */
} SolRetainedSlot;

struct SolVM {
    SolFrame frames[SOL_FRAMES_MAX];
    int      frame_count;

    SolValue  stack[SOL_STACK_MAX];
    SolValue *stack_top;

    SolObject *root;      /* globals namespace; also ends every proto chain */
    uint64_t   next_frame_id;

    /* This machine's serial, unique for the life of the process. A chunk
       records it to say whose interned names it is holding -- by serial and not
       by pointer, because a freed VM's address can be handed straight back to
       the next one, and a host that runs a script per request makes that the
       normal case rather than a corner. See `interned_for` in bytecode.h. */
    uint64_t   id;

    /* Heap. One list threads every collectable cell; `gray` is the mark
       worklist, kept explicit so a deep object graph cannot overflow the C
       stack the way recursive marking would. */
    SolGCHeader  *heap;
    size_t        bytes_allocated;
    size_t        next_gc;
    SolGCHeader **gray;
    int           gray_count;
    int           gray_capacity;
    /* Foreign cells made since the last collection.
     *
     * The heap threshold is measured in bytes, and a foreign cell is forty of
     * them however scarce the thing it holds. A file descriptor is one of a few
     * hundred; a window is one of a few dozen. So a program opening sockets in
     * a loop would exhaust the process long before it allocated its way to a
     * collection -- measured, and it ran out at 256 with the heap barely
     * touched.
     *
     * So foreign cells get a count of their own, and enough of them forces a
     * collection whatever the byte figure says. This is not a second heap: it
     * is the collector being told that these are expensive in a currency it
     * cannot see. See SOL_GC_FOREIGN_PRESSURE. */
    int           foreign_since_gc;

    /* What an extension has asked the collector to keep, and the other half of
       what `temps` does.
     *
     * `temps` covers a window inside one primitive and is eight deep. This
     * covers a value foreign code will hold *between* calls -- a block handed
     * to a toolkit as a callback -- which is unbounded in both count and time,
     * and which nothing else here can see: the tracer walks the stack, the
     * frames, the temps and the class objects, and a block in a C struct is
     * none of them. See sol_extension_retain in extend.h. */
    SolRetainedSlot *retained;
    int              retained_count;
    int              retained_capacity;
    int              retained_free;      /* head of the free list, or -1 */

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
    /* What a resource an extension owns answers to. There is no way to make
       one from Solum -- only a primitive can -- so this class has no `new`. */
    SolObject *foreign_class;

    /* How many globals the built-ins bound, counted the moment they were
       installed. A new name goes on the front of the root's slot list, so
       everything a program binds sits ahead of that many slots -- which is what
       lets a debugger show what this program bound rather than the whole root.
       Nothing removes a slot, so the number stays true. */
    int builtin_globals;

    /* Not a value type: `random` is an object whose children hold a generator's
       state in their payload. Kept here so a primitive can tell the prototype
       from something made with `random:new`, which is the difference between a
       generator and a shared global one. */
    SolObject *random_class;

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

    /* This machine's one string for each of the 256 byte values.
     *
     * `string:at` answers a one-character string, there being no character
     * type, so walking a string a byte at a time used to allocate a cell per
     * character -- and so did `"o"` in the loop's condition, because OP_STRING
     * builds a literal fresh on every evaluation. Nine million characters
     * scanned meant eighteen million strings made and collected to look at
     * bytes the machine already had.
     *
     * A string is immutable and compared by value, so which copy a program
     * holds is not something it can ask. Sharing one is therefore invisible,
     * which is what makes this a cost removed rather than a decision.
     *
     * **Strong, where the symbol table is weak, and the reason is the count.**
     * Symbols are unbounded -- a program can intern a million names -- so a
     * table that kept them would be a leak with a table around it. There are
     * 256 byte values and there will never be more, so the whole of this one is
     * about six kilobytes held for the life of the machine, and holding it is
     * what makes the second read free. That is also why the general case in
     * 1.3 is still open: interning *every* literal needs a weak table so the
     * long ones can die, and this needs no table machinery at all.
     *
     * **Filled on first use, not at startup.** ROADMAP 3.10 measures a third of
     * a request going on building a machine, so 512 allocations added to
     * `sol_vm_init` would be paid by every request to buy bytes most programs
     * never read. An entry costs nothing until something asks for that byte.
     *
     * Indexed by the byte itself, all 256 of them: a string is bytes and may
     * hold a NUL, so `\0` is an entry like any other. */
    SolString *bytes[256];

    /* Files `system:load` has already run, by identity -- the realpath, so that
       two names for one file are one file. `@include` keeps the same list for
       the same reason, and keys it the same way; the difference is only that
       its list belongs to one compilation and this one belongs to the machine.

       Never shortened. Nothing unloads a file, in the same way and for the same
       reason that nothing unbinds a global -- see ROADMAP 3.10, which this is
       one more face of. */
    char **loaded;
    int    loaded_count;
    int    loaded_capacity;

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

    /* What a host is willing to lend the program, set before it runs. Zero is
       no limit, which is the default and is right for a person at a terminal
       with a ctrl-c to hand.
     *
       `steps_remaining` counts down in both cases: with no limit it starts at
       UINT64_MAX, so the dispatch loop tests one counter rather than first
       testing whether there is one to test. At a billion instructions a second
       that runs out after five hundred years, which is near enough to never.
     *
       Reset by `sol_vm_run`, so a budget is per run and not per VM -- a server
       handing one VM a request and then another wants each of them to get the
       whole allowance rather than the remains of the last one's. */
    uint64_t step_limit;
    uint64_t steps_remaining;
    size_t   memory_limit;        /* live bytes, measured after a collection */

    /* Set when a limit stopped the program. It travels by `had_error`, as an
       exit does, because that is the flag every loop already unwinds on -- and
       is kept apart from `exiting` because the two say opposite things about
       whose decision it was. Neither `onError` nor `ensure` may intercept it: a
       limit a program can catch is a limit it can decline. */
    bool stopped;

    /* Whether an uncaught failure is written to stderr as the run ends. True
       unless a host says otherwise, which is what every front end here relies
       on -- a person at a terminal wants to be told.
     *
       A host does not. It is holding `error_message` and `error_trace` already
       and has its own log to put them in, so the default gives it the failure
       twice and in a format it did not choose. Turning this off does not make
       the failure quieter, it makes it the host's: `sol_vm_run` still answers
       SOL_RUNTIME_ERROR or SOL_STOPPED and the text is still there to read. */
    bool report_errors;

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

/* Whether a send from where the machine now stands may reach `slot` on
   `receiver` -- true unless the receiver has drawn an export boundary that
   leaves the slot outside it. See `exports`. */
bool sol_vm_may_reach(const SolVM *vm, const SolSlot *slot, SolValue receiver);

/* The self of the frame now running -- nil at a program's top level, which is
   what puts it outside every object's export boundary. */
SolValue sol_vm_self(const SolVM *vm);

/* Whether this machine has already run the file with this identity, and the
   note that it has. `sol_vm_remember_loaded` takes ownership of `identity`.
   Together they are `system:load`'s once-only memory; nothing else uses them. */
bool sol_vm_already_loaded(const SolVM *vm, const char *identity);
void sol_vm_remember_loaded(SolVM *vm, char *identity);

/* Executes `chunk` *inside* the run already in progress, sharing the globals
   with it, and answers how it went.
 *
 * This is `sol_vm_run`'s nested twin, and the difference is everything it does
 * not do. It does not reset the error state, the step budget, the frames or the
 * stack: those belong to the run underway, and a chunk loaded part-way through
 * is a guest in it rather than a fresh start. What it does do is what
 * `sol_vm_call_block` does -- remember the frame count and the stack top, run
 * until the guest is done, and put both back, because a top-level chunk ends in
 * OP_HALT and HALT unwinds nothing.
 *
 * The chunk must stay alive for as long as anything it defined can still be
 * reached. Load into a `sol_code_new` cell and the collector settles that; a
 * caller-owned chunk makes it the caller's problem -- see ROADMAP 3.6. */
SolResult sol_vm_call_chunk(SolVM *vm, const SolChunk *chunk);

/* What the program may spend, set by whoever is embedding the machine and not
 * reachable from inside it. There is no message that sets, clears or reads
 * either of these, which is the whole of what makes them limits rather than
 * suggestions. Zero lifts one; both are lifted to begin with.
 *
 * A step is one instruction, which is a unit of work rather than of time --
 * deliberately, because it does not vary with the machine or with what else it
 * is running, so a limit chosen on a laptop means the same thing on a server.
 *
 * The memory figure is live bytes after a collection, so a program is stopped
 * for holding too much and not for having allocated too much.
 *
 * Reaching either answers `SOL_STOPPED`, which is neither `SOL_OK` nor
 * `SOL_EXIT`: the program did not finish and did not ask to stop. */
void sol_vm_set_step_limit(SolVM *vm, uint64_t steps);
void sol_vm_set_memory_limit(SolVM *vm, size_t bytes);

/* Whether `sol_vm_run` writes an uncaught failure to stderr before it answers.
 * On unless a host turns it off; see `report_errors` above. Off does not lose
 * the failure -- the result still says what happened and
 * `sol_vm_error_message` still holds the text. */
void sol_vm_set_error_reporting(SolVM *vm, bool on);

/* Stops the program because a limit was reached, with `format` saying which.
 *
 * Not `sol_vm_runtime_error`, though it unwinds the same way, because a stop is
 * not the program's fault and must not be catchable. The first stop wins, and a
 * stop outranks an error already pending: whatever the program was in the
 * middle of failing at, it is being stopped, and that is the outcome its host
 * needs to hear about. */
void sol_vm_stop(SolVM *vm, const char *format, ...);

void     sol_vm_push(SolVM *vm, SolValue value);
SolValue sol_vm_pop(SolVM *vm);

/* The object a message sent to `value` is resolved against. */
SOL_API SolObject *sol_vm_class_of(SolVM *vm, SolValue value);

/* Sends `name` to `receiver` and answers the reply.
 *
 * For primitives that need to call back into the language -- `fill` asking a
 * value for its `asString`, so that an override is honoured rather than
 * bypassed. Receiver and arguments are pushed onto the value stack for the
 * duration, so everything stays rooted even if the send allocates. Sets the
 * VM's error flag on failure. */
SOL_API SolValue sol_vm_send(SolVM *vm, SolValue receiver, const char *name,
                     SolValue *args, int argc);

/* Runs `block` to completion and returns its value. Primitives use this to
   invoke a block, which is how `ifTrue` and `whileTrue` work without the
   compiler knowing anything about them. Sets the VM's error flag on failure. */
SOL_API SolValue sol_vm_call_block(SolVM *vm, SolValue block, SolValue *args, int argc);

/* Reports a runtime error against the current instruction and unwinds. */
SOL_API void sol_vm_runtime_error(SolVM *vm, const char *format, ...);

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
SOL_API const char *sol_type_name(SolValue value);

#endif /* SOLUM_VM_H */
