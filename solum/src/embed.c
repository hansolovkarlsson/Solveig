/* embed.c -- the host-facing helpers declared in embed.h.
 *
 * None of this is new capability. Every one of these is two or three calls a
 * host could already have made, and the reason they are here is that a host
 * assembling them by hand has to know things nothing wrote down: that a global
 * is a slot on `vm->root`, that rendering is a send and can therefore fail and
 * can therefore collect, and that everything dies with `sol_vm_free`. Naming
 * the pattern is the point -- an interface is a list of things somebody may
 * rely on, and three internal calls in the right order is not one. */

#include <stdlib.h>
#include <string.h>

#include "solum/embed.h"
#include "solum/gc.h"
#include "solum/object.h"

bool sol_vm_global(SolVM *vm, const char *name, SolValue *out)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    if (slot == NULL) return false;
    if (out != NULL) *out = slot->value;
    return true;
}

char *sol_vm_global_text(SolVM *vm, const char *name)
{
    SolValue value;
    if (!sol_vm_global(vm, name, &value)) return NULL;

    /* Rendering a composite sends `asString` to what it holds, so this can
       allocate and can fail. Failing leaves the VM's error set, and answering
       NULL rather than a half-built string is the honest report. */
    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, value, &text);
    if (vm->had_error) {
        sol_text_free(&text);
        return NULL;
    }

    char *copy = malloc((size_t)text.length + 1);
    if (copy != NULL) {
        memcpy(copy, text.chars, (size_t)text.length);
        copy[text.length] = '\0';
    }
    sol_text_free(&text);
    return copy;
}

void sol_vm_set_global(SolVM *vm, const char *name, SolValue value)
{
    sol_object_define(vm, vm->root, name, value);
}

void sol_vm_set_global_text(SolVM *vm, const char *name, const char *chars)
{
    int length = chars != NULL ? (int)strlen(chars) : 0;
    SolString *string = sol_string_new(vm, chars != NULL ? chars : "", length);

    /* Rooted across the define, which allocates a slot and can therefore
       collect. The string is reachable from nothing until the slot holds it,
       which is the whole of why this is not two lines in a caller. */
    sol_gc_push_temp(vm, (SolGCHeader *)string);
    sol_object_define(vm, vm->root, name, SOL_STRING_VAL(string));
    sol_gc_pop_temp(vm);
}

const char *sol_vm_error_message(const SolVM *vm)
{
    return vm->error_message.length > 0 ? vm->error_message.chars : NULL;
}

const char *sol_vm_error_trace(const SolVM *vm)
{
    return vm->error_trace.length > 0 ? vm->error_trace.chars : NULL;
}
