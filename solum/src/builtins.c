/* builtins.c -- the classes that exist before any Solum code runs.
 *
 * Every method here is a C primitive. Arithmetic is strict: an integer only
 * combines with an integer, a float only with a float. There is no implicit
 * coercion, so `#45:add(1.5)` is an error rather than a quiet promotion.
 */
#include <stdio.h>

#include "solum/vm.h"

/* Checks arity and reports a usable message if it is wrong. */
static bool check_argc(SolVM *vm, const char *name, int argc, int expected)
{
    if (argc == expected) return true;
    sol_vm_runtime_error(vm, "'%s' takes %d argument%s, got %d",
                         name, expected, expected == 1 ? "" : "s", argc);
    return false;
}

/* Strict type check on an argument -- the rule that makes #45 and 45 distinct. */
static bool check_same_type(SolVM *vm, const char *name, SolValue self, SolValue arg)
{
    if (self.type == arg.type) return true;
    sol_vm_runtime_error(vm, "'%s' expects %s, got %s (no implicit coercion)",
                         name, sol_type_name(self), sol_type_name(arg));
    return false;
}

/* ---- shared ---------------------------------------------------------- */

static SolValue prim_print(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "print", argc, 0)) return SOL_NIL_VAL;
    sol_value_print(self);
    printf("\n");
    return self;
}

/* ---- integer --------------------------------------------------------- */

static SolValue prim_integer_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "new", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_INT(args[0])) {
        sol_vm_runtime_error(vm, "integer:new expects an integer, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }
    /* Integers are immutable values, so there is nothing to allocate --
       `integer:new(#45)` is the long form of the literal `#45`. */
    return args[0];
}

/* Arithmetic traps on overflow rather than wrapping. __builtin_*_overflow is a
   single instruction plus a predictable branch, so strictness is close to free. */
static SolValue prim_integer_add(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "add", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "add", self, args[0])) return SOL_NIL_VAL;

    int64_t result;
    if (__builtin_add_overflow(SOL_AS_INT(self), SOL_AS_INT(args[0]), &result)) {
        sol_vm_runtime_error(vm, "integer overflow in 'add'");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(result);
}

static SolValue prim_integer_sub(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "sub", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "sub", self, args[0])) return SOL_NIL_VAL;

    int64_t result;
    if (__builtin_sub_overflow(SOL_AS_INT(self), SOL_AS_INT(args[0]), &result)) {
        sol_vm_runtime_error(vm, "integer overflow in 'sub'");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(result);
}

static SolValue prim_integer_mul(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "mul", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "mul", self, args[0])) return SOL_NIL_VAL;

    int64_t result;
    if (__builtin_mul_overflow(SOL_AS_INT(self), SOL_AS_INT(args[0]), &result)) {
        sol_vm_runtime_error(vm, "integer overflow in 'mul'");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(result);
}

/* ---- float ----------------------------------------------------------- */

static SolValue prim_float_add(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "add", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "add", self, args[0])) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(SOL_AS_FLOAT(self) + SOL_AS_FLOAT(args[0]));
}

static SolValue prim_float_sub(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "sub", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "sub", self, args[0])) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(SOL_AS_FLOAT(self) - SOL_AS_FLOAT(args[0]));
}

static SolValue prim_float_mul(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "mul", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "mul", self, args[0])) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(SOL_AS_FLOAT(self) * SOL_AS_FLOAT(args[0]));
}

/* ---- installation ---------------------------------------------------- */

void sol_builtins_install(SolVM *vm)
{
    /* NOTE: class-side and instance-side messages currently share one object,
       so `#45:new(#1)` resolves as readily as `integer:new(#1)`. Splitting them
       needs a metaclass level -- see docs/design.md. */
    vm->integer_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->integer_class, "new",   prim_integer_new);
    sol_object_define_primitive(vm->integer_class, "print", prim_print);
    sol_object_define_primitive(vm->integer_class, "add",   prim_integer_add);
    sol_object_define_primitive(vm->integer_class, "sub",   prim_integer_sub);
    sol_object_define_primitive(vm->integer_class, "mul",   prim_integer_mul);

    vm->float_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->float_class, "print", prim_print);
    sol_object_define_primitive(vm->float_class, "add",   prim_float_add);
    sol_object_define_primitive(vm->float_class, "sub",   prim_float_sub);
    sol_object_define_primitive(vm->float_class, "mul",   prim_float_mul);

    vm->nil_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->nil_class, "print", prim_print);

    /* Bind the class objects into the globals namespace so `integer` resolves. */
    sol_object_define(vm->root, "integer", SOL_OBJ_VAL(vm->integer_class));
    sol_object_define(vm->root, "float",   SOL_OBJ_VAL(vm->float_class));
    sol_object_define(vm->root, "nil",     SOL_NIL_VAL);
}
