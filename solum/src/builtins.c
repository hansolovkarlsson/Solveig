/* builtins.c -- the classes that exist before any Solum code runs.
 *
 * Every method here is a C primitive. Arithmetic is strict: an integer only
 * combines with an integer, a float only with a float. There is no implicit
 * coercion, so `#45:add(1.5)` is an error rather than a quiet promotion.
 */
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/* `print` shows the literal form -- `#45`, `"a\"b"` -- which is what you want
 * when reading a value back or reading it inside an array.
 *
 * `display` writes the text instead: it sends `asString` and writes those
 * characters raw. That is what output wants, and without it a formatted string
 * could only be shown wearing quotes, and a string holding newlines could not be
 * written as lines at all.
 */
static SolValue prim_display(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "display", argc, 0)) return SOL_NIL_VAL;

    SolValue text = sol_vm_send(vm, self, "asString", NULL, 0);
    if (vm->had_error) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(text)) {
        sol_vm_runtime_error(vm, "'asString' answered %s rather than a string",
                             sol_type_name(text));
        return SOL_NIL_VAL;
    }

    const SolString *string = SOL_AS_STRING(text);
    fwrite(string->chars, 1, (size_t)string->length, stdout);
    printf("\n");
    return self;
}

static SolValue prim_print(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "print", argc, 0)) return SOL_NIL_VAL;

    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, self, &text);
    if (text.chars != NULL) fwrite(text.chars, 1, (size_t)text.length, stdout);
    printf("\n");
    sol_text_free(&text);
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

/* Integer division floors rather than truncating, so the two differ only on
 * negatives: -7 div 2 is -4, not -3.
 *
 * Floor is chosen for what it does to `mod`. A floored remainder always lands in
 * [0, n) for positive n, which is what indexing, hashing, and cyclic arithmetic
 * actually want; a truncated one takes the sign of the dividend, so -7 rem 2 is
 * -1 and every use site needs a correction. It is also Smalltalk's choice, and
 * the object model came from there.
 *
 * The truncating pair keeps the names `quo` and `rem` free, should it ever be
 * wanted alongside.
 *
 * The result is an integer, which is not really a free choice: answering a float
 * would let two integers leave their type silently, which is exactly the
 * implicit coercion the language refuses everywhere else.
 */
static bool integer_divisor(SolVM *vm, const char *name, SolValue self, SolValue arg)
{
    if (!check_same_type(vm, name, self, arg)) return false;

    if (SOL_AS_INT(arg) == 0) {
        sol_vm_runtime_error(vm, "division by zero in '%s'", name);
        return false;
    }
    /* The one division that overflows: the most negative integer has no positive
       counterpart. In C this is undefined and raises SIGFPE on x86 rather than
       answering anything, so it is guarded rather than trapped after the fact. */
    if (SOL_AS_INT(self) == INT64_MIN && SOL_AS_INT(arg) == -1) {
        sol_vm_runtime_error(vm, "integer overflow in '%s'", name);
        return false;
    }
    return true;
}

static SolValue prim_integer_div(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "div", argc, 1)) return SOL_NIL_VAL;
    if (!integer_divisor(vm, "div", self, args[0])) return SOL_NIL_VAL;

    int64_t a = SOL_AS_INT(self), b = SOL_AS_INT(args[0]);
    int64_t q = a / b, r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) q--;      /* C truncates; step down */
    return SOL_INT_VAL(q);
}

static SolValue prim_integer_mod(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "mod", argc, 1)) return SOL_NIL_VAL;
    if (!integer_divisor(vm, "mod", self, args[0])) return SOL_NIL_VAL;

    int64_t b = SOL_AS_INT(args[0]);
    int64_t r = SOL_AS_INT(self) % b;
    if (r != 0 && ((r < 0) != (b < 0))) r += b;   /* take the divisor's sign */
    return SOL_INT_VAL(r);
}

/* Negating the most negative integer overflows, since it has no positive
   counterpart -- the same edge that guards INT64_MIN div #-1. */
static SolValue prim_integer_negated(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "negated", argc, 0)) return SOL_NIL_VAL;
    if (SOL_AS_INT(self) == INT64_MIN) {
        sol_vm_runtime_error(vm, "integer overflow in 'negated'");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(-SOL_AS_INT(self));
}

static SolValue prim_integer_abs(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "abs", argc, 0)) return SOL_NIL_VAL;
    if (SOL_AS_INT(self) == INT64_MIN) {
        sol_vm_runtime_error(vm, "integer overflow in 'abs'");
        return SOL_NIL_VAL;
    }
    int64_t v = SOL_AS_INT(self);
    return SOL_INT_VAL(v < 0 ? -v : v);
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

static SolValue prim_float_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "new", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_FLOAT(args[0])) {
        sol_vm_runtime_error(vm, "float:new expects a float, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }
    return args[0];
}

static SolValue prim_float_negated(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "negated", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(-SOL_AS_FLOAT(self));
}

static SolValue prim_float_abs(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "abs", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(fabs(SOL_AS_FLOAT(self)));
}

/* Floats divide by zero to infinity rather than erroring. That is not a new
   rule: float multiplication already overflows silently to infinity where
   integer multiplication traps, because infinity is a representable float and
   there is no such integer. Division by zero falls on the same line. */
static SolValue prim_float_div(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "div", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "div", self, args[0])) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(SOL_AS_FLOAT(self) / SOL_AS_FLOAT(args[0]));
}

/* Floored, to match the integers: the remainder takes the divisor's sign. */
static SolValue prim_float_mod(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "mod", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "mod", self, args[0])) return SOL_NIL_VAL;

    double b = SOL_AS_FLOAT(args[0]);
    double r = fmod(SOL_AS_FLOAT(self), b);
    if (r != 0.0 && ((r < 0.0) != (b < 0.0))) r += b;
    return SOL_FLOAT_VAL(r);
}

/* ---- conversions -------------------------------------------------------- */

/* `asString` answers the plain text of a value, where `print` shows the literal
 * form. `#45:asString` is "45", not "#45", because the point of it is to build
 * text -- "you have ":concat(n:asString) should not read "you have #45". The two
 * are deliberately different jobs, the way Smalltalk separates displayString
 * from printString.
 */
static SolValue string_from(SolVM *vm, const char *text, int length)
{
    return SOL_STRING_VAL(sol_string_new(vm, text, length));
}

static SolValue prim_integer_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;
    char buffer[32];
    int n = snprintf(buffer, sizeof buffer, "%lld", (long long)SOL_AS_INT(self));
    return string_from(vm, buffer, n);
}

/* A float's plain form and its literal form are the same -- there is no `#` to
   drop -- so this goes through the renderer rather than formatting again. Its
   own snprintf("%g") had drifted: print showed 1234567 while asString said
   1.23457e+06, which is a different number. */
static SolValue prim_float_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;

    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, self, &text);
    SolValue result = string_from(vm, text.chars == NULL ? "" : text.chars, text.length);
    sol_text_free(&text);
    return result;
}

static SolValue prim_bool_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;
    return SOL_AS_BOOL(self) ? string_from(vm, "true", 4) : string_from(vm, "false", 5);
}

static SolValue prim_nil_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;
    return string_from(vm, "nil", 3);
}

/* A string is already text, and is immutable, so it can answer itself. */
static SolValue prim_string_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;
    return self;
}

/* Widening an integer can lose precision above 2^53, silently, because that is
   what binary64 is. Erroring would be surprising and unlike every other
   language; the loss is documented instead. */
static SolValue prim_integer_as_float(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asFloat", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL((double)SOL_AS_INT(self));
}

/* Narrowing needs the caller to say which way to go, so there is no `asInteger`
 * on a float: `floor`, `ceiling`, `rounded`, and `truncated` each answer an
 * integer and each says what it does. Naming the intent is cheaper than
 * remembering a default.
 *
 * Every one of them can fail, since most floats have no integer counterpart. */
static bool float_to_integer(SolVM *vm, const char *name, double d, int64_t *out)
{
    if (isnan(d)) {
        sol_vm_runtime_error(vm, "'%s' cannot convert a value that is not a number", name);
        return false;
    }
    /* 2^63 is exactly representable, so this is the true range test: anything
       below the lower bound or at or above the upper has no int64. */
    if (!(d >= -9223372036854775808.0 && d < 9223372036854775808.0)) {
        sol_vm_runtime_error(vm, "'%s' is out of integer range", name);
        return false;
    }
    *out = (int64_t)d;
    return true;
}

static SolValue float_rounding(SolVM *vm, const char *name, SolValue self,
                               int argc, double (*how)(double))
{
    if (!check_argc(vm, name, argc, 0)) return SOL_NIL_VAL;
    int64_t result;
    if (!float_to_integer(vm, name, how(SOL_AS_FLOAT(self)), &result)) return SOL_NIL_VAL;
    return SOL_INT_VAL(result);
}

static SolValue prim_float_floor(SolVM *vm, SolValue self, SolValue *args, int argc)
{ (void)args; return float_rounding(vm, "floor", self, argc, floor); }

static SolValue prim_float_ceiling(SolVM *vm, SolValue self, SolValue *args, int argc)
{ (void)args; return float_rounding(vm, "ceiling", self, argc, ceil); }

/* Half away from zero, which is what C's round does and what most people mean. */
static SolValue prim_float_rounded(SolVM *vm, SolValue self, SolValue *args, int argc)
{ (void)args; return float_rounding(vm, "rounded", self, argc, round); }

static SolValue prim_float_truncated(SolVM *vm, SolValue self, SolValue *args, int argc)
{ (void)args; return float_rounding(vm, "truncated", self, argc, trunc); }

/* Parsing the other way. Strict: the whole string has to be a number and nothing
   else, so "12abc", "", " 45" and "45 " are all errors rather than 12, 0, 45 and
   45. strtoll and strtod skip leading whitespace of their own accord, which
   would have made the two ends behave differently, so it is rejected here. */
static bool parsed_cleanly(const SolString *string, const char *end)
{
    if (string->length == 0) return false;
    if (isspace((unsigned char)string->chars[0])) return false;
    return end == string->chars + string->length;
}
static SolValue prim_string_as_integer(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asInteger", argc, 0)) return SOL_NIL_VAL;

    const SolString *string = SOL_AS_STRING(self);
    char *end;
    errno = 0;
    long long value = strtoll(string->chars, &end, 10);

    if (!parsed_cleanly(string, end)) {
        sol_vm_runtime_error(vm, "'%s' is not an integer", string->chars);
        return SOL_NIL_VAL;
    }
    if (errno == ERANGE) {
        sol_vm_runtime_error(vm, "'%s' is out of integer range", string->chars);
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL((int64_t)value);
}

static SolValue prim_string_as_float(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asFloat", argc, 0)) return SOL_NIL_VAL;

    const SolString *string = SOL_AS_STRING(self);
    char *end;
    double value = strtod(string->chars, &end);

    if (!parsed_cleanly(string, end)) {
        sol_vm_runtime_error(vm, "'%s' is not a float", string->chars);
        return SOL_NIL_VAL;
    }
    return SOL_FLOAT_VAL(value);
}

/* A composite has no unambiguous flat text, so its `asString` answers the same
   literal form `print` shows -- rendered once, in value.c, so the two cannot
   drift. */
static SolValue prim_rendered_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;

    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, self, &text);
    SolValue result = string_from(vm, text.chars == NULL ? "" : text.chars, text.length);
    sol_text_free(&text);
    return result;
}

/* An object's default rendering, written directly rather than by calling the
   renderer back -- which is what stops the renderer's "ask the object" from
   recurring forever. A type that defines its own `asString` never reaches this. */
static SolValue prim_object_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;
    char buffer[40];
    int n = snprintf(buffer, sizeof buffer, "<object %p>", (void *)SOL_AS_OBJ(self));
    return string_from(vm, buffer, n);
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
    /* Identity, like objects and blocks. Two arrays with equal elements are two
       arrays; comparing contents is a different question and deserves its own
       name rather than quietly changing what `equals` means. */
    case SOL_ARRAY: return SOL_BOOL_VAL(SOL_AS_ARRAY(self) == SOL_AS_ARRAY(other));
    case SOL_DELEGATE: return SOL_BOOL_VAL(SOL_AS_DELEGATE(self) == SOL_AS_DELEGATE(other));
    /* A string is immutable, so it is a value like a number rather than a
       reference like an array: equality compares contents. */
    case SOL_STRING: {
        const SolString *a = SOL_AS_STRING(self);
        const SolString *b = SOL_AS_STRING(other);
        return SOL_BOOL_VAL(a->length == b->length &&
                            memcmp(a->chars, b->chars, (size_t)a->length) == 0);
    }
    case SOL_OBJ:   return SOL_BOOL_VAL(SOL_AS_OBJ(self) == SOL_AS_OBJ(other));
    }
    return SOL_BOOL_VAL(false);
}

/* The negation of `equals`, defined in terms of it so the two can never
   disagree about what equality means for a given type. */
static SolValue prim_not_equals(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "notEquals", argc, 1)) return SOL_NIL_VAL;
    SolValue equal = prim_equals(vm, self, args, argc);
    if (vm->had_error) return SOL_NIL_VAL;
    return SOL_BOOL_VAL(!SOL_AS_BOOL(equal));
}

/* Ordering, for numbers and for strings. Strings compare by their characters,
   shorter first when one is a prefix of the other, which is what sorting wants.
   Numbers stay strict: an integer does not order against a float. */
static int compare_values(SolValue a, SolValue b)
{
    if (SOL_IS_INT(a)) {
        int64_t x = SOL_AS_INT(a), y = SOL_AS_INT(b);
        return x < y ? -1 : (x > y ? 1 : 0);
    }
    if (SOL_IS_FLOAT(a)) {
        double x = SOL_AS_FLOAT(a), y = SOL_AS_FLOAT(b);
        return x < y ? -1 : (x > y ? 1 : 0);
    }

    const SolString *x = SOL_AS_STRING(a);
    const SolString *y = SOL_AS_STRING(b);
    int shorter = x->length < y->length ? x->length : y->length;
    int order = memcmp(x->chars, y->chars, (size_t)shorter);
    if (order != 0) return order < 0 ? -1 : 1;
    return x->length < y->length ? -1 : (x->length > y->length ? 1 : 0);
}

static SolValue ordering(SolVM *vm, const char *name, SolValue self, SolValue *args,
                         int argc, bool want_less, bool want_equal)
{
    if (!check_argc(vm, name, argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, name, self, args[0])) return SOL_NIL_VAL;

    int order = compare_values(self, args[0]);
    if (order == 0) return SOL_BOOL_VAL(want_equal);
    return SOL_BOOL_VAL(want_less ? order < 0 : order > 0);
}

static SolValue prim_less_or_equal(SolVM *vm, SolValue self, SolValue *args, int argc)
{ return ordering(vm, "lessOrEqual", self, args, argc, true, true); }

static SolValue prim_greater_or_equal(SolVM *vm, SolValue self, SolValue *args, int argc)
{ return ordering(vm, "greaterOrEqual", self, args, argc, false, true); }

static SolValue prim_string_less(SolVM *vm, SolValue self, SolValue *args, int argc)
{ return ordering(vm, "lessThan", self, args, argc, true, false); }

static SolValue prim_string_greater(SolVM *vm, SolValue self, SolValue *args, int argc)
{ return ordering(vm, "greaterThan", self, args, argc, false, false); }

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

/* Short-circuit, so they take a block rather than a value: the argument is only
   run when the answer is not already settled. That is the same shape as
   `ifTrue`, and the reason `and`/`or` cannot simply take booleans. */
static SolValue boolean_block(SolVM *vm, const char *name, SolValue block)
{
    SolValue answer = sol_vm_call_block(vm, block, NULL, 0);
    if (vm->had_error) return SOL_NIL_VAL;
    if (!SOL_IS_BOOL(answer)) {
        sol_vm_runtime_error(vm, "'%s' expects the block to answer a boolean, got %s",
                             name, sol_type_name(answer));
        return SOL_NIL_VAL;
    }
    return answer;
}

static SolValue prim_and(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "and", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_AS_BOOL(self)) return SOL_BOOL_VAL(false);   /* the block never runs */
    return boolean_block(vm, "and", args[0]);
}

static SolValue prim_or(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "or", argc, 1)) return SOL_NIL_VAL;
    if (SOL_AS_BOOL(self)) return SOL_BOOL_VAL(true);
    return boolean_block(vm, "or", args[0]);
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

/* ---- array ------------------------------------------------------------- */

/* Indices are one-based: an index is an ordinal, not an offset. The translation
   to the backing store happens here and nowhere else. */
static bool array_index(SolVM *vm, const char *name, const SolArray *array,
                        SolValue index, int *out)
{
    if (!SOL_IS_INT(index)) {
        sol_vm_runtime_error(vm, "'%s' expects an integer index, got %s",
                             name, sol_type_name(index));
        return false;
    }

    int64_t i = SOL_AS_INT(index);
    if (i < 1 || i > array->count) {
        sol_vm_runtime_error(vm, "index #%lld is out of bounds for an array of size %d",
                             (long long)i, array->count);
        return false;
    }
    *out = (int)(i - 1);
    return true;
}

static SolValue prim_array_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args;
    if (!check_argc(vm, "new", argc, 0)) return SOL_NIL_VAL;
    return SOL_ARRAY_VAL(sol_array_new(vm, 0));
}

/* `array:of(#1, #2, #3)` -- what `[#1, #2, #3]` will be sugar for. Variadic, so
   there is no arity to check. */
static SolValue prim_array_of(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    SolArray *array = sol_array_new(vm, argc);
    /* The arguments are still on the value stack while this runs, so they are
       rooted; nothing allocates between here and the last copy. */
    for (int i = 0; i < argc; i++) sol_array_add(vm, array, args[i]);
    return SOL_ARRAY_VAL(array);
}

static SolValue prim_array_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "size", argc, 0)) return SOL_NIL_VAL;
    return SOL_INT_VAL(SOL_AS_ARRAY(self)->count);
}

static SolValue prim_array_at(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "at", argc, 1)) return SOL_NIL_VAL;

    SolArray *array = SOL_AS_ARRAY(self);
    int index;
    if (!array_index(vm, "at", array, args[0], &index)) return SOL_NIL_VAL;
    return array->items[index];
}

static SolValue prim_array_at_put(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "at_put", argc, 2)) return SOL_NIL_VAL;

    SolArray *array = SOL_AS_ARRAY(self);
    int index;
    if (!array_index(vm, "at_put", array, args[0], &index)) return SOL_NIL_VAL;
    array->items[index] = args[1];
    return args[1];                 /* answers the value stored, as `:=` does */
}

/* Answers the array, so `a:add(#1):add(#2)` chains. Smalltalk answers the added
   element instead, but it has cascades for this and Solum does not -- `;` is a
   comment here. */
static SolValue prim_array_add(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "add", argc, 1)) return SOL_NIL_VAL;
    sol_array_add(vm, SOL_AS_ARRAY(self), args[0]);
    return self;
}

static SolValue prim_array_do(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "do", argc, 1)) return SOL_NIL_VAL;

    SolArray *array = SOL_AS_ARRAY(self);

    /* The block may grow the array, which reallocates the backing store, so the
       count is bounded once at the start and `items` is re-read every pass. The
       receiver is on the stack throughout, so the array itself stays rooted. */
    int limit = array->count;
    for (int i = 0; i < limit; i++) {
        if (i >= array->count) break;          /* it shrank underneath us */
        sol_vm_call_block(vm, args[0], &array->items[i], 1);
        if (vm->had_error) return SOL_NIL_VAL;
    }
    return self;
}

/* `collect` and `select` are the first primitives to need a temporary root.
 *
 * `do` does not: its array is the receiver, so it sits on the value stack and is
 * rooted for the whole call. These two allocate a *result* array and then call a
 * block per element -- and a block can allocate. Between those calls the result
 * is reachable only from a C local, which the collector cannot see, so without
 * the root a collection mid-loop would sweep the very array being built.
 */
static SolValue prim_array_collect(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "collect", argc, 1)) return SOL_NIL_VAL;

    SolArray *source = SOL_AS_ARRAY(self);
    SolArray *result = sol_array_new(vm, source->count);
    sol_gc_push_temp(vm, &result->gc);

    /* Bounded once and re-read each pass, as `do` is: the block may grow the
       source and move its backing store. */
    int limit = source->count;
    for (int i = 0; i < limit; i++) {
        if (i >= source->count) break;

        SolValue mapped = sol_vm_call_block(vm, args[0], &source->items[i], 1);
        if (vm->had_error) {
            sol_gc_pop_temp(vm);
            return SOL_NIL_VAL;
        }
        /* Nothing allocates between the block returning and this, so `mapped`
           does not need rooting of its own. */
        sol_array_add(vm, result, mapped);
    }

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(result);
}

static SolValue prim_array_select(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "select", argc, 1)) return SOL_NIL_VAL;

    SolArray *source = SOL_AS_ARRAY(self);
    SolArray *result = sol_array_new(vm, 0);
    sol_gc_push_temp(vm, &result->gc);

    int limit = source->count;
    for (int i = 0; i < limit; i++) {
        if (i >= source->count) break;

        SolValue element = source->items[i];

        /* Appended before the test rather than after it. The element would
           otherwise live only in a C local while the block runs, and a block
           that replaced it in the source would leave nothing else pointing at
           it. Held in the result, it is rooted; a rejected one is dropped by
           winding the count back. */
        sol_array_add(vm, result, element);

        SolValue keep = sol_vm_call_block(vm, args[0], &element, 1);
        if (vm->had_error) {
            sol_gc_pop_temp(vm);
            return SOL_NIL_VAL;
        }
        if (!SOL_IS_BOOL(keep)) {
            sol_vm_runtime_error(vm, "select expects the block to answer a boolean, "
                                     "got %s", sol_type_name(keep));
            sol_gc_pop_temp(vm);
            return SOL_NIL_VAL;
        }
        if (!SOL_AS_BOOL(keep)) result->count--;
    }

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(result);
}

/* ---- string ------------------------------------------------------------ */

static SolValue prim_string_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "size", argc, 0)) return SOL_NIL_VAL;
    return SOL_INT_VAL(SOL_AS_STRING(self)->length);
}

/* Answers a new string; nothing mutates one. Strict, like arithmetic: joining a
   string to a number is an error rather than a silent conversion. */
static SolValue prim_string_concat(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "concat", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'concat' expects a string, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    const SolString *a = SOL_AS_STRING(self);
    const SolString *b = SOL_AS_STRING(args[0]);

    /* Both operands are on the value stack for the duration of this call, so
       they stay rooted while the result is allocated. */
    int length = a->length + b->length;
    char *joined = malloc((size_t)length + 1);
    if (joined == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }
    memcpy(joined, a->chars, (size_t)a->length);
    memcpy(joined + a->length, b->chars, (size_t)b->length);
    joined[length] = '\0';

    SolValue result = SOL_STRING_VAL(sol_string_new(vm, joined, length));
    free(joined);
    return result;
}

/* `"you have {} apples":fill([n])`
 *
 * Named for what it does: the placeholders are blanks and this fills them. It is
 * not `format`, which belongs to formatting a single value against a spec --
 * `"..."`:fill is the template doing something to the values, where
 * `45.8:asString("5.2")` is the value being formatted.
 *
 * `{}` takes the next value, rendered by sending it `asString` -- a send rather
 * than a direct call, so a type that overrides `asString` is honoured here too.
 * `{{` writes a literal brace; a `{` that is neither is an error rather than a
 * guess.
 *
 * `}` is never special and needs no escape, so `}}` is simply two of them. That
 * differs from Python, where `}` closes a placeholder that may carry content;
 * here a placeholder is exactly `{}`, so a lone `}` cannot be ambiguous and one
 * escape rule is enough.
 *
 * Placeholders and values must match exactly. Too few values and too many are
 * both errors: filling the gap with blanks, or dropping the extras, would turn a
 * mistake into output that looks deliberate.
 */
static SolValue prim_string_fill(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "fill", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_ARRAY(args[0])) {
        sol_vm_runtime_error(vm, "'fill' expects an array of values, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    const SolString *template = SOL_AS_STRING(self);
    SolArray *values = SOL_AS_ARRAY(args[0]);

    /* The receiver and the array are on the value stack for this call, so both
       stay rooted while `asString` runs and possibly allocates. The buffer is
       plain C memory, invisible to the collector and needing nothing from it. */
    SolText out;
    sol_text_init(&out);
    int used = 0;

    for (int i = 0; i < template->length; ) {
        char c = template->chars[i];
        if (c != '{') {
            sol_text_append(&out, &template->chars[i], 1);
            i++;
            continue;
        }

        if (i + 1 < template->length && template->chars[i + 1] == '{') {
            sol_text_append(&out, "{", 1);
            i += 2;
            continue;
        }

        if (i + 1 < template->length && template->chars[i + 1] == '}') {
            if (used == values->count) {
                sol_vm_runtime_error(vm, "'fill' has more placeholders than the "
                                         "%d value%s given", values->count,
                                     values->count == 1 ? "" : "s");
                sol_text_free(&out);
                return SOL_NIL_VAL;
            }
            SolValue text = sol_vm_send(vm, values->items[used], "asString", NULL, 0);
            if (vm->had_error) { sol_text_free(&out); return SOL_NIL_VAL; }
            if (!SOL_IS_STRING(text)) {
                sol_vm_runtime_error(vm, "'asString' answered %s rather than a string",
                                     sol_type_name(text));
                sol_text_free(&out);
                return SOL_NIL_VAL;
            }
            sol_text_append(&out, SOL_AS_STRING(text)->chars, SOL_AS_STRING(text)->length);
            used++;
            i += 2;
            continue;
        }

        sol_vm_runtime_error(vm, "'fill' expects '{}' or '{{' after a brace");
        sol_text_free(&out);
        return SOL_NIL_VAL;
    }

    if (used != values->count) {
        sol_vm_runtime_error(vm, "'fill' has %d placeholder%s but %d value%s given",
                             used, used == 1 ? "" : "s",
                             values->count, values->count == 1 ? "" : "s");
        sol_text_free(&out);
        return SOL_NIL_VAL;
    }

    SolValue result = string_from(vm, out.chars == NULL ? "" : out.chars, out.length);
    sol_text_free(&out);
    return result;
}

/* One-based, like an array: an index is an ordinal. Answers a one-character
   string, there being no character type of its own. */
static SolValue prim_string_at(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "at", argc, 1)) return SOL_NIL_VAL;

    const SolString *string = SOL_AS_STRING(self);
    if (!SOL_IS_INT(args[0])) {
        sol_vm_runtime_error(vm, "'at' expects an integer index, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    int64_t i = SOL_AS_INT(args[0]);
    if (i < 1 || i > string->length) {
        sol_vm_runtime_error(vm, "index #%lld is out of bounds for a string of size %d",
                             (long long)i, string->length);
        return SOL_NIL_VAL;
    }
    return SOL_STRING_VAL(sol_string_new(vm, string->chars + (i - 1), 1));
}

/* ---- object ------------------------------------------------------------ */

/* `new` answers a fresh object delegating to the receiver.
 *
 * There is no separate notion of a class: an object created from `object` can be
 * given slots, and an object created from *that* delegates to it and finds them.
 * Whether a given object is a class or an instance is a matter of how it is
 * used, not of what it is.
 *
 *     point := object:new.
 *     point:x := #0.                       ; a default every instance sees
 *     point:show := { self:x:print }.      ; a method, being a slot holding a block
 *
 *     p := point:new.
 *     p:x := #3.                           ; p's own slot, shadowing point's
 *
 * A slot assigned on an instance is always the instance's own, so setting one
 * shadows the prototype rather than writing through to it. */
static SolValue prim_object_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "new", argc, 0)) return SOL_NIL_VAL;
    if (!SOL_IS_OBJ(self)) {
        sol_vm_runtime_error(vm, "'new' expects an object, got %s",
                             sol_type_name(self));
        return SOL_NIL_VAL;
    }
    /* `self` is on the value stack for the duration of this call, so it stays
       rooted while the child is allocated. */
    return SOL_OBJ_VAL(sol_object_new(vm, SOL_AS_OBJ(self)));
}

/* `self:via(ancestor)` answers a delegating view: a send to it looks the message
   up starting at `ancestor`, but runs it with `self` still the receiver. */
static SolValue prim_object_via(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "via", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_OBJ(args[0])) {
        sol_vm_runtime_error(vm, "'via' expects an object to start from, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }
    /* Both the receiver and the ancestor are on the value stack for this call,
       so they stay rooted while the delegate is allocated. */
    return SOL_DELEGATE_VAL(sol_delegate_new(vm, self, SOL_AS_OBJ(args[0])));
}

/* The prototype this object delegates to, or nil at the root. Read-only: the
   link stays an internal pointer, so nothing a program writes can corrupt
   dispatch. */
static SolValue prim_object_parent(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "parent", argc, 0)) return SOL_NIL_VAL;
    if (!SOL_IS_OBJ(self)) {
        sol_vm_runtime_error(vm, "'parent' expects an object, got %s",
                             sol_type_name(self));
        return SOL_NIL_VAL;
    }
    SolObject *proto = SOL_AS_OBJ(self)->proto;
    return proto == NULL ? SOL_NIL_VAL : SOL_OBJ_VAL(proto);
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
    sol_object_define_primitive(vm->integer_class, "display", prim_display);
    sol_object_define_primitive(vm->integer_class, "add",   prim_integer_add);
    sol_object_define_primitive(vm->integer_class, "sub",   prim_integer_sub);
    sol_object_define_primitive(vm->integer_class, "mul",   prim_integer_mul);
    sol_object_define_primitive(vm->integer_class, "div",   prim_integer_div);
    sol_object_define_primitive(vm->integer_class, "mod",   prim_integer_mod);
    sol_object_define_primitive(vm->integer_class, "asFloat",  prim_integer_as_float);
    sol_object_define_primitive(vm->integer_class, "asString", prim_integer_as_string);
    sol_object_define_primitive(vm->integer_class, "negated", prim_integer_negated);
    sol_object_define_primitive(vm->integer_class, "abs",     prim_integer_abs);
    sol_object_define_primitive(vm->integer_class, "notEquals",      prim_not_equals);
    sol_object_define_primitive(vm->integer_class, "lessOrEqual",    prim_less_or_equal);
    sol_object_define_primitive(vm->integer_class, "greaterOrEqual", prim_greater_or_equal);
    sol_object_define_primitive(vm->integer_class, "equals",      prim_equals);
    sol_object_define_primitive(vm->integer_class, "lessThan",    prim_less);
    sol_object_define_primitive(vm->integer_class, "greaterThan", prim_greater);

    vm->float_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->float_class, "print", prim_print);
    sol_object_define_primitive(vm->float_class, "display", prim_display);
    sol_object_define_primitive(vm->float_class, "add",   prim_float_add);
    sol_object_define_primitive(vm->float_class, "sub",   prim_float_sub);
    sol_object_define_primitive(vm->float_class, "mul",   prim_float_mul);
    sol_object_define_primitive(vm->float_class, "div",   prim_float_div);
    sol_object_define_primitive(vm->float_class, "mod",   prim_float_mod);
    sol_object_define_primitive(vm->float_class, "asString",  prim_float_as_string);
    sol_object_define_primitive(vm->float_class, "floor",     prim_float_floor);
    sol_object_define_primitive(vm->float_class, "ceiling",   prim_float_ceiling);
    sol_object_define_primitive(vm->float_class, "rounded",   prim_float_rounded);
    sol_object_define_primitive(vm->float_class, "truncated", prim_float_truncated);
    sol_object_define_primitive(vm->float_class, "new",     prim_float_new);
    sol_object_define_primitive(vm->float_class, "negated", prim_float_negated);
    sol_object_define_primitive(vm->float_class, "abs",     prim_float_abs);
    sol_object_define_primitive(vm->float_class, "notEquals",      prim_not_equals);
    sol_object_define_primitive(vm->float_class, "lessOrEqual",    prim_less_or_equal);
    sol_object_define_primitive(vm->float_class, "greaterOrEqual", prim_greater_or_equal);
    sol_object_define_primitive(vm->float_class, "equals",      prim_equals);
    sol_object_define_primitive(vm->float_class, "lessThan",    prim_less);
    sol_object_define_primitive(vm->float_class, "greaterThan", prim_greater);

    vm->nil_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->nil_class, "print",  prim_print);
    sol_object_define_primitive(vm->nil_class, "display", prim_display);
    sol_object_define_primitive(vm->nil_class, "equals", prim_equals);
    sol_object_define_primitive(vm->nil_class, "asString",  prim_nil_as_string);
    sol_object_define_primitive(vm->nil_class, "notEquals", prim_not_equals);

    vm->bool_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->bool_class, "print",   prim_print);
    sol_object_define_primitive(vm->bool_class, "display", prim_display);
    sol_object_define_primitive(vm->bool_class, "equals",  prim_equals);
    sol_object_define_primitive(vm->bool_class, "not",     prim_not);
    sol_object_define_primitive(vm->bool_class, "ifTrue",  prim_if_true);
    sol_object_define_primitive(vm->bool_class, "ifFalse", prim_if_false);
    sol_object_define_primitive(vm->bool_class, "ifElse",  prim_if_else);
    sol_object_define_primitive(vm->bool_class, "asString", prim_bool_as_string);
    sol_object_define_primitive(vm->bool_class, "and",       prim_and);
    sol_object_define_primitive(vm->bool_class, "or",        prim_or);
    sol_object_define_primitive(vm->bool_class, "notEquals", prim_not_equals);

    vm->block_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->block_class, "print",     prim_print);
    sol_object_define_primitive(vm->block_class, "display", prim_display);
    sol_object_define_primitive(vm->block_class, "equals",    prim_equals);
    sol_object_define_primitive(vm->block_class, "notEquals", prim_not_equals);
    sol_object_define_primitive(vm->block_class, "asString",  prim_rendered_as_string);
    sol_object_define_primitive(vm->block_class, "value",     prim_value);
    sol_object_define_primitive(vm->block_class, "whileTrue", prim_while_true);

    vm->array_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->array_class, "new",    prim_array_new);
    sol_object_define_primitive(vm->array_class, "of",     prim_array_of);
    sol_object_define_primitive(vm->array_class, "size",   prim_array_size);
    sol_object_define_primitive(vm->array_class, "at",     prim_array_at);
    sol_object_define_primitive(vm->array_class, "at_put", prim_array_at_put);
    sol_object_define_primitive(vm->array_class, "add",    prim_array_add);
    sol_object_define_primitive(vm->array_class, "do",      prim_array_do);
    sol_object_define_primitive(vm->array_class, "collect", prim_array_collect);
    sol_object_define_primitive(vm->array_class, "select",  prim_array_select);
    sol_object_define_primitive(vm->array_class, "print",  prim_print);
    sol_object_define_primitive(vm->array_class, "display", prim_display);
    sol_object_define_primitive(vm->array_class, "equals",    prim_equals);
    sol_object_define_primitive(vm->array_class, "notEquals", prim_not_equals);
    sol_object_define_primitive(vm->array_class, "asString",  prim_rendered_as_string);

    /* The root of the user-defined side. The built-in classes deliberately do
       not delegate to it: `float` inheriting object's `new` would answer a plain
       object rather than a float. Untangling that is the class-side/instance-side
       question in the roadmap. */
    vm->object_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->object_class, "new",    prim_object_new);
    sol_object_define_primitive(vm->object_class, "via",    prim_object_via);
    sol_object_define_primitive(vm->object_class, "parent", prim_object_parent);
    sol_object_define_primitive(vm->object_class, "print",  prim_print);
    sol_object_define_primitive(vm->object_class, "display", prim_display);
    sol_object_define_primitive(vm->object_class, "equals",    prim_equals);
    sol_object_define_primitive(vm->object_class, "notEquals", prim_not_equals);
    sol_object_define_primitive(vm->object_class, "asString",  prim_object_as_string);

    vm->string_class = sol_object_new(vm, NULL);
    sol_object_define_primitive(vm->string_class, "print",  prim_print);
    sol_object_define_primitive(vm->string_class, "display", prim_display);
    sol_object_define_primitive(vm->string_class, "equals", prim_equals);
    sol_object_define_primitive(vm->string_class, "size",   prim_string_size);
    sol_object_define_primitive(vm->string_class, "concat", prim_string_concat);
    sol_object_define_primitive(vm->string_class, "at",     prim_string_at);
    sol_object_define_primitive(vm->string_class, "fill",   prim_string_fill);
    sol_object_define_primitive(vm->string_class, "asString",  prim_string_as_string);
    sol_object_define_primitive(vm->string_class, "asInteger", prim_string_as_integer);
    sol_object_define_primitive(vm->string_class, "asFloat",   prim_string_as_float);
    sol_object_define_primitive(vm->string_class, "notEquals",      prim_not_equals);
    sol_object_define_primitive(vm->string_class, "lessThan",       prim_string_less);
    sol_object_define_primitive(vm->string_class, "greaterThan",    prim_string_greater);
    sol_object_define_primitive(vm->string_class, "lessOrEqual",    prim_less_or_equal);
    sol_object_define_primitive(vm->string_class, "greaterOrEqual", prim_greater_or_equal);

    /* Bind the class objects into the globals namespace so `integer` resolves. */
    sol_object_define(vm->root, "integer", SOL_OBJ_VAL(vm->integer_class));
    sol_object_define(vm->root, "float",   SOL_OBJ_VAL(vm->float_class));
    sol_object_define(vm->root, "array",   SOL_OBJ_VAL(vm->array_class));
    sol_object_define(vm->root, "string",  SOL_OBJ_VAL(vm->string_class));
    sol_object_define(vm->root, "object",  SOL_OBJ_VAL(vm->object_class));
    sol_object_define(vm->root, "nil",     SOL_NIL_VAL);
    sol_object_define(vm->root, "true",    SOL_BOOL_VAL(true));
    /* The two floats with no literal form. Naming them makes `infinity` and
       `nan` readable back, which is how a printed float round-trips. */
    sol_object_define(vm->root, "infinity", SOL_FLOAT_VAL(INFINITY));
    sol_object_define(vm->root, "nan",      SOL_FLOAT_VAL(NAN));
    sol_object_define(vm->root, "false",   SOL_BOOL_VAL(false));
}
