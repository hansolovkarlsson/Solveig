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

/* ---- comparison ------------------------------------------------------- */

/* Comparisons are as strict as arithmetic: comparing an integer to a float is
   an error, not a silent promotion. `equals` is the exception -- asking whether
   two values are equal is reasonable across types, and the answer is false. */
static SolValue prim_equals(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "equals", argc, 1)) return SOL_NIL_VAL;

    SolValue other = args[0];
    if (self.type != other.type) return SOL_BOOL_VAL(false);

    switch (self.type) {
    case SOL_NIL:   return SOL_BOOL_VAL(true);
    case SOL_BOOL:  return SOL_BOOL_VAL(SOL_AS_BOOL(self) == SOL_AS_BOOL(other));
    case SOL_INT:   return SOL_BOOL_VAL(SOL_AS_INT(self) == SOL_AS_INT(other));
    case SOL_FLOAT: return SOL_BOOL_VAL(SOL_AS_FLOAT(self) == SOL_AS_FLOAT(other));
    case SOL_BLOCK: return SOL_BOOL_VAL(SOL_AS_BLOCK(self) == SOL_AS_BLOCK(other));
    case SOL_OBJ:   return SOL_BOOL_VAL(SOL_AS_OBJ(self) == SOL_AS_OBJ(other));
    }
    return SOL_BOOL_VAL(false);
}

static SolValue prim_less(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "lessThan", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "lessThan", self, args[0])) return SOL_NIL_VAL;

    if (SOL_IS_INT(self)) return SOL_BOOL_VAL(SOL_AS_INT(self) < SOL_AS_INT(args[0]));
    return SOL_BOOL_VAL(SOL_AS_FLOAT(self) < SOL_AS_FLOAT(args[0]));
}

static SolValue prim_greater(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "greaterThan", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "greaterThan", self, args[0])) return SOL_NIL_VAL;

    if (SOL_IS_INT(self)) return SOL_BOOL_VAL(SOL_AS_INT(self) > SOL_AS_INT(args[0]));
    return SOL_BOOL_VAL(SOL_AS_FLOAT(self) > SOL_AS_FLOAT(args[0]));
}

/* ---- boolean ----------------------------------------------------------- */

/* Control flow is ordinary message sending: `ifTrue` receives an unevaluated
   block and decides whether to run it. Nothing in the compiler knows these
   selectors, so a user can add their own control structures the same way. */
static SolValue prim_if_true(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "ifTrue", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_AS_BOOL(self)) return SOL_NIL_VAL;
    return sol_vm_call_block(vm, args[0], NULL, 0);
}

static SolValue prim_if_false(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "ifFalse", argc, 1)) return SOL_NIL_VAL;
    if (SOL_AS_BOOL(self)) return SOL_NIL_VAL;
    return sol_vm_call_block(vm, args[0], NULL, 0);
}

static SolValue prim_if_else(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "ifElse", argc, 2)) return SOL_NIL_VAL;
    return sol_vm_call_block(vm, SOL_AS_BOOL(self) ? args[0] : args[1], NULL, 0);
}

static SolValue prim_not(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "not", argc, 0)) return SOL_NIL_VAL;
    return SOL_BOOL_VAL(!SOL_AS_BOOL(self));
}

/* ---- block ------------------------------------------------------------- */

/* `value` takes whatever the block declares -- `{ a, b | ... }:value(#1, #2)`.
   push_frame checks the count against the block's arity, so a mismatch is
   reported there rather than needing a separate check here. */
static SolValue prim_value(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    return sol_vm_call_block(vm, self, args, argc);
}

/* `{ condition }:whileTrue({ body })` -- the receiver is re-run every pass,
   which is the whole reason it has to be a block rather than a value. */
static SolValue prim_while_true(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "whileTrue", argc, 1)) return SOL_NIL_VAL;

    for (;;) {
        SolValue condition = sol_vm_call_block(vm, self, NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;

        if (!SOL_IS_BOOL(condition)) {
            sol_vm_runtime_error(vm, "whileTrue expects the condition block to "
                                     "answer a boolean, got %s",
                                 sol_type_name(condition));
            return SOL_NIL_VAL;
        }
        if (!SOL_AS_BOOL(condition)) return SOL_NIL_VAL;

        sol_vm_call_block(vm, args[0], NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;
    }
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
    sol_object_define_primitive(vm->integer_class, "equals",      prim_equals);
    sol_object_define_primitive(vm->integer_class, "lessThan",    prim_less);
    sol_object_define_primitive(vm->integer_class, "greaterThan", prim_greater);

    vm->float_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->float_class, "print", prim_print);
    sol_object_define_primitive(vm->float_class, "add",   prim_float_add);
    sol_object_define_primitive(vm->float_class, "sub",   prim_float_sub);
    sol_object_define_primitive(vm->float_class, "mul",   prim_float_mul);
    sol_object_define_primitive(vm->float_class, "equals",      prim_equals);
    sol_object_define_primitive(vm->float_class, "lessThan",    prim_less);
    sol_object_define_primitive(vm->float_class, "greaterThan", prim_greater);

    vm->nil_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->nil_class, "print",  prim_print);
    sol_object_define_primitive(vm->nil_class, "equals", prim_equals);

    vm->bool_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->bool_class, "print",   prim_print);
    sol_object_define_primitive(vm->bool_class, "equals",  prim_equals);
    sol_object_define_primitive(vm->bool_class, "not",     prim_not);
    sol_object_define_primitive(vm->bool_class, "ifTrue",  prim_if_true);
    sol_object_define_primitive(vm->bool_class, "ifFalse", prim_if_false);
    sol_object_define_primitive(vm->bool_class, "ifElse",  prim_if_else);

    vm->block_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->block_class, "print",     prim_print);
    sol_object_define_primitive(vm->block_class, "equals",    prim_equals);
    sol_object_define_primitive(vm->block_class, "value",     prim_value);
    sol_object_define_primitive(vm->block_class, "whileTrue", prim_while_true);

    /* Bind the class objects into the globals namespace so `integer` resolves. */
    sol_object_define(vm->root, "integer", SOL_OBJ_VAL(vm->integer_class));
    sol_object_define(vm->root, "float",   SOL_OBJ_VAL(vm->float_class));
    sol_object_define(vm->root, "nil",     SOL_NIL_VAL);
    sol_object_define(vm->root, "true",    SOL_BOOL_VAL(true));
    sol_object_define(vm->root, "false",   SOL_BOOL_VAL(false));
}
