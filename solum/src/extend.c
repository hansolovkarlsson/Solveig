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
