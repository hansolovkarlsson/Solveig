/* ext_fastmath.c -- stands in for "a library I wrote myself, in C, because it
   has to be fast". Nothing about it knows that SDL or the sockets exist. */
#include <math.h>

#include "solum/embed.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

static SolValue prim_dot(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 2 || args[0].type != SOL_ARRAY || args[1].type != SOL_ARRAY) {
        sol_vm_runtime_error(vm, "dot expects two arrays");
        return SOL_NIL_VAL;
    }
    SolArray *a = args[0].as.array, *b = args[1].as.array;
    if (a->count != b->count) {
        sol_vm_runtime_error(vm, "dot expects arrays of one length");
        return SOL_NIL_VAL;
    }
    double sum = 0.0;
    for (int i = 0; i < a->count; i++) {
        if (a->items[i].type != SOL_FLOAT || b->items[i].type != SOL_FLOAT) {
            sol_vm_runtime_error(vm, "dot expects floats");
            return SOL_NIL_VAL;
        }
        sum += a->items[i].as.real * b->items[i].as.real;
    }
    return SOL_FLOAT_VAL(sum);
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;
    SolObject *m = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, m, "dot", prim_dot);
    sol_vm_set_global(vm, "fastmath", SOL_OBJ_VAL(m));
    return 0;
}
