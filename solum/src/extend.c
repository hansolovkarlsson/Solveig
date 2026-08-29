/* extend.c -- loading an extension into a machine.
 *
 * Two entry points and one of them is four lines, because registering is the
 * whole mechanism and `dlopen` is only a way of finding the function to
 * register. The header says why they are separate; this file is why it costs
 * nothing to keep them so.
 */
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/extend.h"

/* The entry point a bundle exports, spelled once. */
#define ENTRY "sol_extension_init"

/* A message on the heap for the caller to free, or nothing if it did not ask.
 *
 * Always answers false, so every failure below is one line: the caller says
 * `return fail(error, "...")` and cannot forget which way round the result
 * goes. Out of memory answers false with `*error` left NULL, which the callers
 * report as an unexplained refusal rather than crashing over a message. */
static bool fail(char **error, const char *format, ...)
{
    if (error == NULL) return false;

    va_list args;
    va_start(args, format);
    int length = vsnprintf(NULL, 0, format, args);
    va_end(args);
    if (length < 0) return false;

    char *text = malloc((size_t)length + 1);
    if (text == NULL) return false;

    va_start(args, format);
    vsnprintf(text, (size_t)length + 1, format, args);
    va_end(args);

    *error = text;
    return false;
}

bool sol_extension_register(SolVM *vm, SolExtensionInit init, const char *name,
                            char **error)
{
    if (init == NULL) return fail(error, "%s: no entry point", name);

    /* The ABI is handed *to* the extension rather than read back from it, so
       that a bundle too old to know the question still gets asked it. It
       compares and refuses; this side only learns which way it went. */
    int answer = init(vm, SOL_EXTENSION_ABI);
    if (answer != 0) {
        return fail(error,
                    "%s: refused ABI %d -- built against a different SolVM, "
                    "rebuild it against this one",
                    name, SOL_EXTENSION_ABI);
    }
    return true;
}

bool sol_extension_load(SolVM *vm, const char *path, char **error)
{
    /* RTLD_LOCAL so that two bundles cannot resolve each other's symbols by
       accident: an extension may depend on a library, and two of them that
       happen to share a name should not silently become one. RTLD_NOW so that a
       missing symbol is a refusal here rather than a crash on the first send --
       which is the whole reason the link change in the Makefile exists. */
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        const char *why = dlerror();
        return fail(error, "%s: %s", path, why != NULL ? why : "cannot load");
    }

    /* Casting an object pointer to a function pointer is not something ISO C
       promises, and POSIX requires it to work for exactly this. The union is
       how it is spelled without the compiler being right to complain. */
    union { void *object; SolExtensionInit function; } entry;
    dlerror();                                     /* clear any stale message */
    entry.object = dlsym(handle, ENTRY);
    if (entry.object == NULL) {
        const char *why = dlerror();
        return fail(error, "%s: no " ENTRY "%s%s", path,
                    why != NULL ? " -- " : "", why != NULL ? why : "");
    }

    /* The handle is deliberately not closed, here or ever. See extend.h. */
    return sol_extension_register(vm, entry.function, path, error);
}

/* ---- keeping a value alive between calls --------------------------------- *
 *
 * A slot map. The token carries the index and the generation of the slot it was
 * handed out for, so a token outliving its slot is detected rather than
 * resolving to whatever was retained next -- which would be the collector's
 * silent misdispatch reproduced one layer up, and this registry exists to end
 * that class of failure rather than to move it.
 *
 * Indices are stable for the life of the VM: nothing shifts, nothing shrinks,
 * and a released slot goes on a free list to be handed out again with a higher
 * generation. */

#define RETAINED_INDEX(token)  ((int)((token) & 0xffffffffu))
#define RETAINED_GEN(token)    ((uint32_t)((token) >> 32))

/* Generations start at 1, so index 0's first token is not zero and
   SOL_RETAINED_NONE cannot collide with a real one. */
static SolRetained retained_token(int index, uint32_t generation)
{
    return ((SolRetained)generation << 32) | (uint32_t)index;
}

/* The slot a token names, or NULL if it names none. Checks the generation, which
   is the whole point: an index alone would answer confidently and wrongly. */
static SolRetainedSlot *retained_slot(SolVM *vm, SolRetained token)
{
    if (token == SOL_RETAINED_NONE) return NULL;

    int index = RETAINED_INDEX(token);
    if (index < 0 || index >= vm->retained_count) return NULL;

    SolRetainedSlot *slot = &vm->retained[index];
    if (!slot->in_use) return NULL;                          /* released */
    if (slot->generation != RETAINED_GEN(token)) return NULL; /* since reused */
    return slot;
}

SolRetained sol_extension_retain(SolVM *vm, SolValue value)
{
    int index;

    if (vm->retained_free != -1) {
        index = vm->retained_free;
        vm->retained_free = vm->retained[index].next_free;
    } else {
        if (vm->retained_count + 1 > vm->retained_capacity) {
            int capacity = vm->retained_capacity < 8 ? 8 : vm->retained_capacity * 2;
            SolRetainedSlot *grown = realloc(vm->retained,
                                             sizeof(SolRetainedSlot) * (size_t)capacity);
            if (grown == NULL) {
                /* The same answer `mark_cell` gives when the worklist will not
                   grow: losing track of a value the collector was told to keep
                   is not something there is a safe way to continue from. */
                fprintf(stderr, "solvm: out of memory retaining a value\n");
                exit(1);
            }
            vm->retained = grown;
            vm->retained_capacity = capacity;
        }
        index = vm->retained_count++;
        vm->retained[index].generation = 0;      /* bumped to 1 just below */
    }

    SolRetainedSlot *slot = &vm->retained[index];
    slot->value = value;
    slot->in_use = true;
    slot->generation++;
    return retained_token(index, slot->generation);
}

bool sol_extension_retained(SolVM *vm, SolRetained token, SolValue *out)
{
    const SolRetainedSlot *slot = retained_slot(vm, token);
    if (slot == NULL) return false;
    if (out != NULL) *out = slot->value;
    return true;
}

bool sol_extension_release(SolVM *vm, SolRetained token)
{
    SolRetainedSlot *slot = retained_slot(vm, token);
    if (slot == NULL) return false;

    /* Cleared as well as unlinked. The slot is not traced once `next_free` is
       set, but leaving a value here would keep a cell reachable from the
       allocator's point of view for as long as the slot went unreused, which is
       a leak that would only show up under memory pressure. */
    slot->value = SOL_NIL_VAL;
    slot->in_use = false;
    slot->next_free = vm->retained_free;
    vm->retained_free = RETAINED_INDEX(token);
    return true;
}
