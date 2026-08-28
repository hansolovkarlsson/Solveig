/* probe_ext_hash.c -- the throwaway extension ideas.md asks for.
 *
 * Nothing to release, nothing to call back into, one message. It is here to
 * answer one question: does a bundle loaded at run time resolve sol_* back
 * into the program that loaded it, and is a primitive it hangs on the root
 * indistinguishable from a built-in?
 */
#include <stdint.h>
#include <string.h>

#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"
#include "solum/embed.h"

/* FNV-1a, because it fits in six lines and is not the point. */
static SolValue prim_fnv1a(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_STRING) {
        sol_vm_runtime_error(vm, "fnv1a expects one string");
        return SOL_NIL_VAL;
    }
    SolString *s = args[0].as.string;
    uint64_t h = 1469598103934665603ull;
    for (int i = 0; i < s->length; i++) {
        h ^= (unsigned char)s->chars[i];
        h *= 1099511628211ull;
    }
    return SOL_INT_VAL((int64_t)(h & 0x7fffffffffffffffll));
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;
    SolObject *hash = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm, hash, "fnv1a", prim_fnv1a);
    sol_vm_set_global(vm, "hash", SOL_OBJ_VAL(hash));
    return 0;
}
