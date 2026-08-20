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

static SolValue string_from(SolVM *vm, const char *text, int length)
{
    return SOL_STRING_VAL(sol_string_new(vm, text, length));
}


/* A format spec, the optional argument to `asString`.
 *
 *     [align] [','] ['0'] [width] ['.' decimals]
 *
 *     "8"      width 8, aligned the way the type prefers
 *     "<8"     width 8, left
 *     "^11"    width 11, centred
 *     "08.2"   width 8, two decimals, zero-filled
 *     ".2"     two decimals, no padding
 *     ",10.2"  width 10, two decimals, digits grouped in threes
 *
 * Deliberately smaller than printf. There is no conversion letter, the receiver
 * being the thing that knows its own type, and no sign mode: a leading space for
 * positive numbers falls out of the width, since numbers align right. Fewer
 * modes to learn, and none that can contradict the value it is applied to.
 *
 * Decimals belong to floats. Width, alignment, and fill are applied to whatever
 * text the value produces, so they work the same everywhere.
 */
#define SOL_SPEC_MAX_WIDTH 1024

typedef struct {
    char align;        /* '<', '>', '^', or 0 for the type's own preference */
    bool group;        /* ',' -- digits in threes */
    bool zero_fill;
    int  width;
    int  decimals;     /* -1 when the spec did not ask */
} SolSpec;

static bool spec_parse(SolVM *vm, const SolString *text, SolSpec *out)
{
    out->align = 0;
    out->group = false;
    out->zero_fill = false;
    out->width = 0;
    out->decimals = -1;

    int i = 0;
    const char *s = text->chars;
    int n = text->length;

    if (i < n && (s[i] == '<' || s[i] == '>' || s[i] == '^')) out->align = s[i++];

    if (i < n && s[i] == ',') { out->group = true; i++; }

    if (i < n && s[i] == '0') {
        /* Zero fill and grouping together produce leading zeros that are not
           themselves grouped -- 001,234.50 -- which reads as a mistake. Refused
           rather than rendered. */
        if (out->group) {
            sol_vm_runtime_error(vm, "a grouped format cannot also be zero-filled");
            return false;
        }
        /* Zero fill only makes sense pushing digits right; padding a number on
           the left with zeros would change what it says. */
        if (out->align != 0 && out->align != '>') {
            sol_vm_runtime_error(vm, "a zero-filled format must align right");
            return false;
        }
        out->zero_fill = true;
        out->align = '>';
        i++;
    }

    while (i < n && s[i] >= '0' && s[i] <= '9') {
        out->width = out->width * 10 + (s[i++] - '0');
        if (out->width > SOL_SPEC_MAX_WIDTH) {
            sol_vm_runtime_error(vm, "a format width may not exceed %d",
                                 SOL_SPEC_MAX_WIDTH);
            return false;
        }
    }

    if (i < n && s[i] == '.') {
        i++;
        out->decimals = 0;
        int digits = 0;
        while (i < n && s[i] >= '0' && s[i] <= '9') {
            out->decimals = out->decimals * 10 + (s[i++] - '0');
            digits++;
        }
        if (digits == 0 || out->decimals > 40) {
            sol_vm_runtime_error(vm, "'%s' is not a usable number of decimals",
                                 text->chars);
            return false;
        }
    }

    if (i != n) {
        sol_vm_runtime_error(vm, "'%s' is not a format spec; expected "
                                 "[align][,][0][width][.decimals]", text->chars);
        return false;
    }
    return true;
}

/* Reads the optional spec argument. No argument means the plain text, which is
   what `display`, `fill`, and array rendering all ask for. */
static bool spec_from_args(SolVM *vm, SolValue *args, int argc, SolSpec *out)
{
    out->align = 0;
    out->group = false;
    out->zero_fill = false;
    out->width = 0;
    out->decimals = -1;

    if (argc == 0) return true;
    if (argc != 1) {
        sol_vm_runtime_error(vm, "'asString' takes no argument or one, got %d", argc);
        return false;
    }
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'asString' expects a format spec string, got %s",
                             sol_type_name(args[0]));
        return false;
    }
    return spec_parse(vm, SOL_AS_STRING(args[0]), out);
}

/* Pads `text` to the spec's width. A value wider than the width is never cut --
   losing digits would be worse than a ragged column. Zero fill goes after any
   sign, so -45 in width 6 is -00045 rather than 000-45. */
static SolValue spec_apply(SolVM *vm, const char *text, int length,
                           const SolSpec *spec, char preferred)
{
    if (length >= spec->width) return string_from(vm, text, length);

    char align = spec->align != 0 ? spec->align : preferred;
    int pad = spec->width - length;
    char fill = spec->zero_fill ? '0' : ' ';

    SolText out;
    sol_text_init(&out);

    if (align == '<') {
        sol_text_append(&out, text, length);
        for (int i = 0; i < pad; i++) sol_text_append(&out, &fill, 1);
    } else if (align == '^') {
        int left = pad / 2;
        for (int i = 0; i < left; i++) sol_text_append(&out, &fill, 1);
        sol_text_append(&out, text, length);
        for (int i = 0; i < pad - left; i++) sol_text_append(&out, &fill, 1);
    } else if (spec->zero_fill && length > 0 && (text[0] == '-' || text[0] == '+')) {
        sol_text_append(&out, text, 1);
        for (int i = 0; i < pad; i++) sol_text_append(&out, &fill, 1);
        sol_text_append(&out, text + 1, length - 1);
    } else {
        for (int i = 0; i < pad; i++) sol_text_append(&out, &fill, 1);
        sol_text_append(&out, text, length);
    }

    SolValue result = string_from(vm, out.chars, out.length);
    sol_text_free(&out);
    return result;
}

/* Writes `text` with its whole-number digits in threes. Anything that is not a
   leading run of digits -- a sign, a fraction, an exponent, the word infinity --
   is passed through untouched, so only the part that wants separating gets
   them. */
static void append_grouped(SolText *out, const char *text, int length)
{
    int start = 0;
    if (length > 0 && (text[0] == '-' || text[0] == '+')) {
        sol_text_append(out, text, 1);
        start = 1;
    }

    int end = start;
    while (end < length && text[end] >= '0' && text[end] <= '9') end++;

    int digits = end - start;
    for (int i = 0; i < digits; i++) {
        if (i > 0 && (digits - i) % 3 == 0) sol_text_append(out, ",", 1);
        sol_text_append(out, &text[start + i], 1);
    }
    if (end < length) sol_text_append(out, text + end, length - end);
}

/* Grouping happens before padding, since it changes the width. */
static SolValue spec_finish(SolVM *vm, const char *text, int length,
                            const SolSpec *spec, char preferred)
{
    if (!spec->group) return spec_apply(vm, text, length, spec, preferred);

    SolText grouped;
    sol_text_init(&grouped);
    append_grouped(&grouped, text, length);
    SolValue result = spec_apply(vm, grouped.chars, grouped.length, spec, preferred);
    sol_text_free(&grouped);
    return result;
}

/* Decimals are a float's business; asking an integer or a string for them is a
   mistake rather than a no-op. */
static bool spec_rejects_decimals(SolVM *vm, const SolSpec *spec, const char *what)
{
    if (spec->decimals < 0) return false;
    sol_vm_runtime_error(vm, "decimals mean nothing for %s", what);
    return true;
}

/* Grouping is a number's business for the same reason. */
static bool spec_rejects_grouping(SolVM *vm, const SolSpec *spec, const char *what)
{
    if (!spec->group) return false;
    sol_vm_runtime_error(vm, "digit grouping means nothing for %s", what);
    return true;
}

/* `asString` answers the plain text of a value, where `print` shows the literal
 * form. `#45:asString` is "45", not "#45", because the point of it is to build
 * text -- "you have ":concat(n:asString) should not read "you have #45". The two
 * are deliberately different jobs, the way Smalltalk separates displayString
 * from printString.
 */
static SolValue prim_integer_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "an integer")) return SOL_NIL_VAL;

    char buffer[32];
    int n = snprintf(buffer, sizeof buffer, "%lld", (long long)SOL_AS_INT(self));
    return spec_finish(vm, buffer, n, &spec, '>');   /* numbers align right */
}

/* A float's plain form and its literal form are the same -- there is no `#` to
   drop -- so this goes through the renderer rather than formatting again. Its
   own snprintf("%g") had drifted: print showed 1234567 while asString said
   1.23457e+06, which is a different number. */
static SolValue prim_float_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;

    /* Asked for decimals, a float is written to that many. Otherwise it gets the
       shortest text that reads back as the same bits, which is the renderer's
       job and not something to duplicate here. Infinity and not-a-number keep
       their names either way; rounding them to two places means nothing. */
    double d = SOL_AS_FLOAT(self);
    if (spec.decimals >= 0 && !isnan(d) && !isinf(d)) {
        char buffer[64];
        int n = snprintf(buffer, sizeof buffer, "%.*f", spec.decimals, d);
        return spec_finish(vm, buffer, n, &spec, '>');
    }

    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, self, &text);
    SolValue result = spec_finish(vm, text.chars == NULL ? "" : text.chars,
                                  text.length, &spec, '>');
    sol_text_free(&text);
    return result;
}

static SolValue prim_bool_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "a boolean")) return SOL_NIL_VAL;
    if (spec_rejects_grouping(vm, &spec, "a boolean")) return SOL_NIL_VAL;
    return SOL_AS_BOOL(self) ? spec_apply(vm, "true", 4, &spec, '<')
                             : spec_apply(vm, "false", 5, &spec, '<');
}

static SolValue prim_nil_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "nil")) return SOL_NIL_VAL;
    if (spec_rejects_grouping(vm, &spec, "nil")) return SOL_NIL_VAL;
    return spec_apply(vm, "nil", 3, &spec, '<');
}

/* A string is already text, so with no spec it answers itself. Text aligns left,
   being read rather than counted. */
static SolValue prim_string_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "a string")) return SOL_NIL_VAL;
    if (spec_rejects_grouping(vm, &spec, "a string")) return SOL_NIL_VAL;
    if (argc == 0) return self;

    const SolString *string = SOL_AS_STRING(self);
    return spec_apply(vm, string->chars, string->length, &spec, '<');
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

/* `#255:asBase(#16)` -- the digits of an integer in another base, as a string.
 *
 * A message rather than a letter in the format spec. A letter would look like
 * printf's conversion character, which the spec was designed without, and would
 * invite a reader to try `f` and `d`; and one letter buys one base, where a
 * number buys all of them. Padding still comes from the spec, by chaining:
 *
 *     #255:asBase(#16):asString("08")   ->  "000000ff"
 *
 * Digits above nine are lowercase. Uppercase would want a case message on
 * strings, which is a more general thing to have than a second base message.
 */
#define SOL_BASE_MIN 2
#define SOL_BASE_MAX 36

static bool base_from(SolVM *vm, const char *name, SolValue value, int *out)
{
    if (!SOL_IS_INT(value)) {
        sol_vm_runtime_error(vm, "'%s' expects an integer base, got %s",
                             name, sol_type_name(value));
        return false;
    }
    int64_t base = SOL_AS_INT(value);
    if (base < SOL_BASE_MIN || base > SOL_BASE_MAX) {
        sol_vm_runtime_error(vm, "'%s' expects a base between %d and %d, got #%lld",
                             name, SOL_BASE_MIN, SOL_BASE_MAX, (long long)base);
        return false;
    }
    *out = (int)base;
    return true;
}

static SolValue prim_integer_as_base(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "asBase", argc, 1)) return SOL_NIL_VAL;
    int base;
    if (!base_from(vm, "asBase", args[0], &base)) return SOL_NIL_VAL;

    /* The magnitude is taken unsigned, so the most negative integer -- which has
       no positive counterpart -- converts like any other rather than trapping. */
    int64_t value = SOL_AS_INT(self);
    bool negative = value < 0;
    uint64_t magnitude = negative ? (uint64_t)(-(value + 1)) + 1u : (uint64_t)value;

    char digits[70];                    /* 64 binary digits, a sign, a NUL */
    int n = 0;
    do {
        int digit = (int)(magnitude % (uint64_t)base);
        digits[n++] = (char)(digit < 10 ? '0' + digit : 'a' + digit - 10);
        magnitude /= (uint64_t)base;
    } while (magnitude != 0);
    if (negative) digits[n++] = '-';

    char text[70];
    for (int i = 0; i < n; i++) text[i] = digits[n - 1 - i];
    return string_from(vm, text, n);
}

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
    int base = 10;
    if (argc == 1) {
        if (!base_from(vm, "asInteger", args[0], &base)) return SOL_NIL_VAL;
    } else if (argc != 0) {
        sol_vm_runtime_error(vm, "'asInteger' takes no argument or a base, got %d", argc);
        return SOL_NIL_VAL;
    }

    const SolString *string = SOL_AS_STRING(self);

    /* strtoll would accept a 0x prefix in base 16 and a leading 0 in base 8.
       Neither is written here, so neither is accepted -- the string is the
       digits and nothing else. */
    if (base == 16 && string->length > 1 && string->chars[0] == '0' &&
        (string->chars[1] == 'x' || string->chars[1] == 'X')) {
        sol_vm_runtime_error(vm, "'%s' is not a base 16 integer; write the digits alone",
                             string->chars);
        return SOL_NIL_VAL;
    }

    char *end;
    errno = 0;
    long long value = strtoll(string->chars, &end, base);

    if (!parsed_cleanly(string, end)) {
        if (base == 10) {
            sol_vm_runtime_error(vm, "'%s' is not an integer", string->chars);
        } else {
            sol_vm_runtime_error(vm, "'%s' is not an integer in base %d",
                                 string->chars, base);
        }
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
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "this value")) return SOL_NIL_VAL;
    if (spec_rejects_grouping(vm, &spec, "this value")) return SOL_NIL_VAL;

    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, self, &text);
    SolValue result = spec_apply(vm, text.chars == NULL ? "" : text.chars,
                                 text.length, &spec, '<');
    sol_text_free(&text);
    return result;
}

/* An object's default rendering, written directly rather than by calling the
   renderer back -- which is what stops the renderer's "ask the object" from
   recurring forever. A type that defines its own `asString` never reaches this. */
static SolValue prim_object_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "an object")) return SOL_NIL_VAL;
    if (spec_rejects_grouping(vm, &spec, "an object")) return SOL_NIL_VAL;
    char buffer[40];
    int n = snprintf(buffer, sizeof buffer, "<object %p>", (void *)SOL_AS_OBJ(self));
    return spec_apply(vm, buffer, n, &spec, '<');
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
    /* Interned, so two symbols spelling the same thing are the same symbol and
       a pointer comparison is a comparison of the names. */
    case SOL_SYMBOL: return SOL_BOOL_VAL(SOL_AS_SYMBOL(self) == SOL_AS_SYMBOL(other));
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
        /* Worded in vm.c, because the inlined form raises the same complaint
           from OP_CHECK_BOOL and the two must not drift apart. */
        sol_vm_block_answer_error(vm, name, answer);
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
            sol_vm_condition_error(vm, condition);
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

/* Does `a` sort strictly before `b`?
 *
 * With no block the default is to *send* `lessThan`, so a user-defined type
 * that defines one orders itself, the way `fill` honours an overridden
 * `asString` rather than going around it. Either way this calls back into the
 * VM, so it can allocate, collect, and fail. */
static bool sorts_before(SolVM *vm, SolValue comparison, SolValue a, SolValue b,
                         bool *before)
{
    SolValue answer;
    if (SOL_IS_NIL(comparison)) {
        SolValue other = b;
        answer = sol_vm_send(vm, a, "lessThan", &other, 1);
    } else {
        SolValue pair[2] = { a, b };
        answer = sol_vm_call_block(vm, comparison, pair, 2);
    }
    if (vm->had_error) return false;

    if (!SOL_IS_BOOL(answer)) {
        sol_vm_runtime_error(vm, "sort expects the comparison to answer a "
                                 "boolean, got %s", sol_type_name(answer));
        return false;
    }
    *before = SOL_AS_BOOL(answer);
    return true;
}

/* Merge sort, for two reasons beyond the O(n log n).
 *
 * It is stable, which is what makes sorting twice a way to sort by two keys.
 * And it cannot be walked off the end of the array by a comparison that
 * contradicts itself -- a program is free to hand us `{ a, b | true }`, and the
 * indices here are bounded by the halves rather than by what the comparison
 * claims. A quicksort partition trusting the comparison would not be.
 *
 * `items` and `scratch` are the backing stores of two arrays the caller holds
 * rooted. The comparison can collect at any point, and what keeps every value
 * alive across that is `items`: a value is *copied* into scratch, never moved,
 * so until the copy back at the end of a merge it is still in `items` too.
 * Rooting the result array is therefore what makes this safe -- drop it and a
 * comparison that allocates will free values out from under the merge. */
static bool merge_sort(SolVM *vm, SolValue comparison, SolValue *items,
                       SolValue *scratch, int lo, int hi)
{
    if (hi - lo < 2) return true;

    int mid = lo + (hi - lo) / 2;
    if (!merge_sort(vm, comparison, items, scratch, lo, mid)) return false;
    if (!merge_sort(vm, comparison, items, scratch, mid, hi)) return false;

    int i = lo, j = mid, k = lo;
    while (i < mid && j < hi) {
        bool before;
        /* Asked the other way round on purpose: take from the right only when
           it sorts *strictly* before the left, so equals keep their order. */
        if (!sorts_before(vm, comparison, items[j], items[i], &before)) return false;
        scratch[k++] = before ? items[j++] : items[i++];
    }
    while (i < mid) scratch[k++] = items[i++];
    while (j < hi)  scratch[k++] = items[j++];

    for (int x = lo; x < hi; x++) items[x] = scratch[x];
    return true;
}

/* `xs:sorted` or `xs:sorted({ a, b | ... })` -- a new array, like collect and
   select. Nothing here sorts in place. */
static SolValue prim_array_sorted(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc > 1) {
        sol_vm_runtime_error(vm, "'sorted' takes 0 or 1 arguments, got %d", argc);
        return SOL_NIL_VAL;
    }
    SolValue comparison = SOL_NIL_VAL;
    if (argc == 1) {
        if (!SOL_IS_BLOCK(args[0])) {
            sol_vm_runtime_error(vm, "'sorted' expects a block, got %s",
                                 sol_type_name(args[0]));
            return SOL_NIL_VAL;
        }
        comparison = args[0];
    }

    SolArray *source = SOL_AS_ARRAY(self);
    int count = source->count;

    SolArray *result = sol_array_new(vm, count);
    sol_gc_push_temp(vm, &result->gc);
    for (int i = 0; i < count; i++) sol_array_add(vm, result, source->items[i]);

    SolArray *scratch = sol_array_new(vm, count);
    sol_gc_push_temp(vm, &scratch->gc);
    /* Filled, not merely reserved. The tracer walks `count` rather than
       `capacity`, so this is what makes the scratch array describe its own
       contents -- today every value in it is also still in `result`, which is
       what actually keeps it alive, but that is an invariant of how merging
       copies and not something the array itself states. */
    for (int i = 0; i < count; i++) sol_array_add(vm, scratch, SOL_NIL_VAL);

    bool ok = merge_sort(vm, comparison, result->items, scratch->items, 0, count);

    sol_gc_pop_temp(vm);                       /* scratch */
    sol_gc_pop_temp(vm);                       /* result */
    return ok ? SOL_ARRAY_VAL(result) : SOL_NIL_VAL;
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

/* A symbol answers its name, and a string answers the symbol for it. Those two
   are the whole conversion: a symbol is a name, and its text is what it says. */
static SolValue prim_symbol_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolSpec spec;
    if (!spec_from_args(vm, args, argc, &spec)) return SOL_NIL_VAL;
    if (spec_rejects_decimals(vm, &spec, "a symbol")) return SOL_NIL_VAL;
    if (spec_rejects_grouping(vm, &spec, "a symbol")) return SOL_NIL_VAL;

    const SolSymbol *symbol = SOL_AS_SYMBOL(self);
    return spec_apply(vm, symbol->chars, symbol->length, &spec, '<');
}

static SolValue prim_symbol_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "size", argc, 0)) return SOL_NIL_VAL;
    return SOL_INT_VAL(SOL_AS_SYMBOL(self)->length);
}

static SolValue prim_string_as_symbol(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asSymbol", argc, 0)) return SOL_NIL_VAL;
    const SolString *string = SOL_AS_STRING(self);
    /* The receiver is on the value stack, so it stays rooted while interning
       allocates. */
    return SOL_SYMBOL_VAL(sol_symbol_intern(vm, string->chars, string->length));
}

/* `"ff":asUppercase` -- a new string with the letters changed.
 *
 * ASCII only, and by explicit range rather than `toupper`, which follows the C
 * locale: under a Turkish locale `toupper('i')` is a dotted capital I, so the
 * same program would answer differently on two machines. Predictability is worth
 * more here than the locales this cannot serve, and a real Unicode case mapping
 * is a different piece of work rather than a bigger version of this one.
 *
 * A string with nothing to change answers itself. Strings are immutable, so
 * nothing can tell the difference, and it saves an allocation.
 */
static SolValue string_recased(SolVM *vm, SolValue self, int argc,
                               const char *name, bool upper)
{
    if (!check_argc(vm, name, argc, 0)) return SOL_NIL_VAL;

    const SolString *string = SOL_AS_STRING(self);
    int i = 0;
    while (i < string->length) {
        char c = string->chars[i];
        if (upper ? (c >= 'a' && c <= 'z') : (c >= 'A' && c <= 'Z')) break;
        i++;
    }
    if (i == string->length) return self;          /* nothing to change */

    SolText out;
    sol_text_init(&out);
    for (int j = 0; j < string->length; j++) {
        char c = string->chars[j];
        if (upper && c >= 'a' && c <= 'z')        c = (char)(c - 'a' + 'A');
        else if (!upper && c >= 'A' && c <= 'Z')  c = (char)(c - 'A' + 'a');
        sol_text_append(&out, &c, 1);
    }
    SolValue result = string_from(vm, out.chars, out.length);
    sol_text_free(&out);
    return result;
}

static SolValue prim_string_upper(SolVM *vm, SolValue self, SolValue *args, int argc)
{ (void)args; return string_recased(vm, self, argc, "asUppercase", true); }

static SolValue prim_string_lower(SolVM *vm, SolValue self, SolValue *args, int argc)
{ (void)args; return string_recased(vm, self, argc, "asLowercase", false); }

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

/* ---- reflection --------------------------------------------------------- */

/* Names are given as symbols rather than strings. A symbol is what a name is,
   and comparing one is a pointer comparison, which matters for `respondsTo` in
   a loop. */
static bool selector_from(SolVM *vm, const char *name, SolValue value,
                          const SolSymbol **out)
{
    if (!SOL_IS_SYMBOL(value)) {
        sol_vm_runtime_error(vm, "'%s' expects a symbol, got %s",
                             name, sol_type_name(value));
        return false;
    }
    *out = SOL_AS_SYMBOL(value);
    return true;
}

/* `p:perform('add, #1)` -- a send whose name is decided at run time. */
static SolValue prim_perform(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc < 1) {
        sol_vm_runtime_error(vm, "'perform' expects a symbol and its arguments");
        return SOL_NIL_VAL;
    }
    const SolSymbol *selector;
    if (!selector_from(vm, "perform", args[0], &selector)) return SOL_NIL_VAL;

    return sol_vm_send(vm, self, selector->chars, args + 1, argc - 1);
}

/* Whether a send of that name would find anything -- including the built-in
   messages, which are slots too. */
static SolValue prim_responds_to(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "respondsTo", argc, 1)) return SOL_NIL_VAL;
    const SolSymbol *selector;
    if (!selector_from(vm, "respondsTo", args[0], &selector)) return SOL_NIL_VAL;

    SolObject *target = sol_vm_class_of(vm, self);
    if (target == NULL) return SOL_BOOL_VAL(false);

    /* Finding the slot is not enough, and answering true for one that would
       refuse this receiver would make `respondsTo` disagree with sending. A
       class object holds its instances' messages: `array:respondsTo('add)` is
       false, because `array:add(#1)` is an error. */
    SolSlot *slot = sol_object_lookup_interned(
        vm, target, sol_vm_intern_name(vm, selector->chars, selector->length));
    return SOL_BOOL_VAL(slot != NULL && sol_slot_accepts(slot, self));
}

/* Whether the receiver delegates to `other`, directly or further up. A value
   answers for the class it dispatches to, so #45:isKindOf(integer) is true. */
static SolValue prim_is_kind_of(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "isKindOf", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_OBJ(args[0])) {
        sol_vm_runtime_error(vm, "'isKindOf' expects an object, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    SolObject *wanted = SOL_AS_OBJ(args[0]);
    for (SolObject *o = sol_vm_class_of(vm, self); o != NULL; o = o->proto) {
        if (o == wanted) return SOL_BOOL_VAL(true);
    }
    return SOL_BOOL_VAL(false);
}

static bool reflected_object(SolVM *vm, const char *name, SolValue self,
                             SolObject **out)
{
    if (!SOL_IS_OBJ(self)) {
        sol_vm_runtime_error(vm, "'%s' expects an object, got %s -- only an object "
                                 "has slots of its own", name, sol_type_name(self));
        return false;
    }
    *out = SOL_AS_OBJ(self);
    return true;
}

/* The names of the object's own slots, in the order they were defined. The list
   is kept newest first, so it is filled backwards. */
static SolValue prim_slots(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "slots", argc, 0)) return SOL_NIL_VAL;
    SolObject *obj;
    if (!reflected_object(vm, "slots", self, &obj)) return SOL_NIL_VAL;

    int count = 0;
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) count++;

    SolArray *out = sol_array_new(vm, count);
    /* Interning a name allocates, and the array is reachable from nothing but
       this local until it is answered. */
    sol_gc_push_temp(vm, &out->gc);

    for (int i = 0; i < count; i++) sol_array_add(vm, out, SOL_NIL_VAL);

    int i = count - 1;
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        out->items[i--] = SOL_SYMBOL_VAL(
            sol_symbol_intern(vm, slot->name, (int)strlen(slot->name)));
    }

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(out);
}

/* The value in a slot, without sending to it -- which is the only way to get at
   a method as a value, a slot holding a block being a method. */
static SolValue prim_slot_at(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "slotAt", argc, 1)) return SOL_NIL_VAL;
    const SolSymbol *selector;
    if (!selector_from(vm, "slotAt", args[0], &selector)) return SOL_NIL_VAL;
    SolObject *obj;
    if (!reflected_object(vm, "slotAt", self, &obj)) return SOL_NIL_VAL;

    SolSlot *slot = sol_object_lookup_interned(
        vm, obj, sol_vm_intern_name(vm, selector->chars, selector->length));
    if (slot == NULL) {
        sol_vm_runtime_error(vm, "no slot named '%s'", selector->chars);
        return SOL_NIL_VAL;
    }
    if (slot->primitive != NULL) {
        sol_vm_runtime_error(vm, "'%s' is built in and has no value to answer",
                             selector->chars);
        return SOL_NIL_VAL;
    }
    return slot->value;
}

/* ---- installation ---------------------------------------------------- */

/* Which side of the class each message lives on.
 *
 * `array` is an object whose slots are the messages an *array* understands, and
 * it answers them itself -- so `array:add(#1)` finds `add` and hands the class
 * object to a primitive that reads it as an array. `instance` records the
 * receiver each one actually needs, and the dispatcher refuses anything else.
 *
 * `any_receiver` is the rest: the class-side messages, which the class object
 * is the receiver of, and reflection, which is meaningful on either side. The
 * two names are the class-side/instance-side distinction 2.5 is about, written
 * down one message at a time rather than decided all at once.
 */
static void instance(SolVM *vm, SolObject *cls, SolValueType type, const char *name,
                     SolPrimitive fn)
{
    sol_object_define_primitive_for(vm, cls, name, fn, (int)type);
}

static void any_receiver(SolVM *vm, SolObject *obj, const char *name, SolPrimitive fn)
{
    sol_object_define_primitive(vm, obj, name, fn);
}

void sol_builtins_install(SolVM *vm)
{
    /* NOTE: class-side and instance-side messages still share one object, so
       `#45:new(#1)` resolves as readily as `integer:new(#1)`. Splitting them
       properly needs a metaclass level -- see docs/design.md. What is written
       down here is the half that had to be settled first: which side each
       message is on, so that `array:add(#1)` is refused rather than run against
       an object that is not an array. */
    vm->integer_class = sol_object_new(vm, NULL);
    any_receiver(vm, vm->integer_class, "new", prim_integer_new);
    instance(vm, vm->integer_class, SOL_INT, "print", prim_print);
    instance(vm, vm->integer_class, SOL_INT, "display", prim_display);
    instance(vm, vm->integer_class, SOL_INT, "add", prim_integer_add);
    instance(vm, vm->integer_class, SOL_INT, "sub", prim_integer_sub);
    instance(vm, vm->integer_class, SOL_INT, "mul", prim_integer_mul);
    instance(vm, vm->integer_class, SOL_INT, "div", prim_integer_div);
    instance(vm, vm->integer_class, SOL_INT, "mod", prim_integer_mod);
    instance(vm, vm->integer_class, SOL_INT, "asFloat", prim_integer_as_float);
    instance(vm, vm->integer_class, SOL_INT, "asBase", prim_integer_as_base);
    instance(vm, vm->integer_class, SOL_INT, "asString", prim_integer_as_string);
    instance(vm, vm->integer_class, SOL_INT, "negated", prim_integer_negated);
    instance(vm, vm->integer_class, SOL_INT, "abs", prim_integer_abs);
    instance(vm, vm->integer_class, SOL_INT, "notEquals", prim_not_equals);
    instance(vm, vm->integer_class, SOL_INT, "lessOrEqual", prim_less_or_equal);
    instance(vm, vm->integer_class, SOL_INT, "greaterOrEqual", prim_greater_or_equal);
    instance(vm, vm->integer_class, SOL_INT, "equals", prim_equals);
    instance(vm, vm->integer_class, SOL_INT, "lessThan", prim_less);
    instance(vm, vm->integer_class, SOL_INT, "greaterThan", prim_greater);

    vm->float_class = sol_object_new(vm, NULL);
    instance(vm, vm->float_class, SOL_FLOAT, "print", prim_print);
    instance(vm, vm->float_class, SOL_FLOAT, "display", prim_display);
    instance(vm, vm->float_class, SOL_FLOAT, "add", prim_float_add);
    instance(vm, vm->float_class, SOL_FLOAT, "sub", prim_float_sub);
    instance(vm, vm->float_class, SOL_FLOAT, "mul", prim_float_mul);
    instance(vm, vm->float_class, SOL_FLOAT, "div", prim_float_div);
    instance(vm, vm->float_class, SOL_FLOAT, "mod", prim_float_mod);
    instance(vm, vm->float_class, SOL_FLOAT, "asString", prim_float_as_string);
    instance(vm, vm->float_class, SOL_FLOAT, "floor", prim_float_floor);
    instance(vm, vm->float_class, SOL_FLOAT, "ceiling", prim_float_ceiling);
    instance(vm, vm->float_class, SOL_FLOAT, "rounded", prim_float_rounded);
    instance(vm, vm->float_class, SOL_FLOAT, "truncated", prim_float_truncated);
    any_receiver(vm, vm->float_class, "new", prim_float_new);
    instance(vm, vm->float_class, SOL_FLOAT, "negated", prim_float_negated);
    instance(vm, vm->float_class, SOL_FLOAT, "abs", prim_float_abs);
    instance(vm, vm->float_class, SOL_FLOAT, "notEquals", prim_not_equals);
    instance(vm, vm->float_class, SOL_FLOAT, "lessOrEqual", prim_less_or_equal);
    instance(vm, vm->float_class, SOL_FLOAT, "greaterOrEqual", prim_greater_or_equal);
    instance(vm, vm->float_class, SOL_FLOAT, "equals", prim_equals);
    instance(vm, vm->float_class, SOL_FLOAT, "lessThan", prim_less);
    instance(vm, vm->float_class, SOL_FLOAT, "greaterThan", prim_greater);

    vm->nil_class = sol_object_new(vm, NULL);
    instance(vm, vm->nil_class, SOL_NIL, "print", prim_print);
    instance(vm, vm->nil_class, SOL_NIL, "display", prim_display);
    instance(vm, vm->nil_class, SOL_NIL, "equals", prim_equals);
    instance(vm, vm->nil_class, SOL_NIL, "asString", prim_nil_as_string);
    instance(vm, vm->nil_class, SOL_NIL, "notEquals", prim_not_equals);

    vm->bool_class = sol_object_new(vm, NULL);
    instance(vm, vm->bool_class, SOL_BOOL, "print", prim_print);
    instance(vm, vm->bool_class, SOL_BOOL, "display", prim_display);
    instance(vm, vm->bool_class, SOL_BOOL, "equals", prim_equals);
    instance(vm, vm->bool_class, SOL_BOOL, "not", prim_not);
    instance(vm, vm->bool_class, SOL_BOOL, "ifTrue", prim_if_true);
    instance(vm, vm->bool_class, SOL_BOOL, "ifFalse", prim_if_false);
    instance(vm, vm->bool_class, SOL_BOOL, "ifElse", prim_if_else);
    instance(vm, vm->bool_class, SOL_BOOL, "asString", prim_bool_as_string);
    instance(vm, vm->bool_class, SOL_BOOL, "and", prim_and);
    instance(vm, vm->bool_class, SOL_BOOL, "or", prim_or);
    instance(vm, vm->bool_class, SOL_BOOL, "notEquals", prim_not_equals);

    vm->block_class = sol_object_new(vm, NULL);
    instance(vm, vm->block_class, SOL_BLOCK, "print", prim_print);
    instance(vm, vm->block_class, SOL_BLOCK, "display", prim_display);
    instance(vm, vm->block_class, SOL_BLOCK, "equals", prim_equals);
    instance(vm, vm->block_class, SOL_BLOCK, "notEquals", prim_not_equals);
    instance(vm, vm->block_class, SOL_BLOCK, "asString", prim_rendered_as_string);
    instance(vm, vm->block_class, SOL_BLOCK, "value", prim_value);
    instance(vm, vm->block_class, SOL_BLOCK, "whileTrue", prim_while_true);

    vm->array_class = sol_object_new(vm, NULL);
    any_receiver(vm, vm->array_class, "new", prim_array_new);
    any_receiver(vm, vm->array_class, "of", prim_array_of);
    instance(vm, vm->array_class, SOL_ARRAY, "size", prim_array_size);
    instance(vm, vm->array_class, SOL_ARRAY, "at", prim_array_at);
    instance(vm, vm->array_class, SOL_ARRAY, "at_put", prim_array_at_put);
    instance(vm, vm->array_class, SOL_ARRAY, "add", prim_array_add);
    instance(vm, vm->array_class, SOL_ARRAY, "do", prim_array_do);
    instance(vm, vm->array_class, SOL_ARRAY, "collect", prim_array_collect);
    instance(vm, vm->array_class, SOL_ARRAY, "select", prim_array_select);
    instance(vm, vm->array_class, SOL_ARRAY, "print", prim_print);
    instance(vm, vm->array_class, SOL_ARRAY, "sorted", prim_array_sorted);
    instance(vm, vm->array_class, SOL_ARRAY, "display", prim_display);
    instance(vm, vm->array_class, SOL_ARRAY, "equals", prim_equals);
    instance(vm, vm->array_class, SOL_ARRAY, "notEquals", prim_not_equals);
    instance(vm, vm->array_class, SOL_ARRAY, "asString", prim_rendered_as_string);

    /* The root of the user-defined side. The built-in classes deliberately do
       not delegate to it: `float` inheriting object's `new` would answer a plain
       object rather than a float. Untangling that is the class-side/instance-side
       question in the roadmap. */
    vm->object_class = sol_object_new(vm, NULL);
    instance(vm, vm->object_class, SOL_OBJ, "new", prim_object_new);
    instance(vm, vm->object_class, SOL_OBJ, "via", prim_object_via);
    instance(vm, vm->object_class, SOL_OBJ, "parent", prim_object_parent);
    instance(vm, vm->object_class, SOL_OBJ, "print", prim_print);
    instance(vm, vm->object_class, SOL_OBJ, "display", prim_display);
    instance(vm, vm->object_class, SOL_OBJ, "equals", prim_equals);
    instance(vm, vm->object_class, SOL_OBJ, "notEquals", prim_not_equals);
    instance(vm, vm->object_class, SOL_OBJ, "asString", prim_object_as_string);

    vm->string_class = sol_object_new(vm, NULL);
    instance(vm, vm->string_class, SOL_STRING, "print", prim_print);
    instance(vm, vm->string_class, SOL_STRING, "display", prim_display);
    instance(vm, vm->string_class, SOL_STRING, "equals", prim_equals);
    instance(vm, vm->string_class, SOL_STRING, "size", prim_string_size);
    instance(vm, vm->string_class, SOL_STRING, "concat", prim_string_concat);
    instance(vm, vm->string_class, SOL_STRING, "at", prim_string_at);
    instance(vm, vm->string_class, SOL_STRING, "fill", prim_string_fill);
    instance(vm, vm->string_class, SOL_STRING, "asString", prim_string_as_string);
    instance(vm, vm->string_class, SOL_STRING, "asInteger", prim_string_as_integer);
    instance(vm, vm->string_class, SOL_STRING, "asFloat", prim_string_as_float);
    instance(vm, vm->string_class, SOL_STRING, "asUppercase", prim_string_upper);
    instance(vm, vm->string_class, SOL_STRING, "asLowercase", prim_string_lower);
    instance(vm, vm->string_class, SOL_STRING, "asSymbol", prim_string_as_symbol);
    instance(vm, vm->string_class, SOL_STRING, "notEquals", prim_not_equals);
    instance(vm, vm->string_class, SOL_STRING, "lessThan", prim_string_less);
    instance(vm, vm->string_class, SOL_STRING, "greaterThan", prim_string_greater);
    instance(vm, vm->string_class, SOL_STRING, "lessOrEqual", prim_less_or_equal);
    instance(vm, vm->string_class, SOL_STRING, "greaterOrEqual", prim_greater_or_equal);

    vm->symbol_class = sol_object_new(vm, NULL);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "print", prim_print);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "display", prim_display);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "asString", prim_symbol_as_string);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "equals", prim_equals);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "notEquals", prim_not_equals);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "size", prim_symbol_size);

    /* Reflection is the same on every class, and installing it in a loop is not
       just brevity: a message that answers what an object understands is wrong
       the moment one class quietly lacks it. */
    SolObject *classes[] = {
        vm->integer_class, vm->float_class, vm->nil_class,    vm->bool_class,
        vm->block_class,   vm->array_class, vm->object_class, vm->string_class,
        vm->symbol_class,
    };
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        any_receiver(vm, classes[i], "perform",    prim_perform);
        any_receiver(vm, classes[i], "respondsTo", prim_responds_to);
        any_receiver(vm, classes[i], "isKindOf",   prim_is_kind_of);
        /* These two want an object to look inside. On anything else they say so
           rather than going missing, which is a better error than "no slot". */
        any_receiver(vm, classes[i], "slots",      prim_slots);
        any_receiver(vm, classes[i], "slotAt",     prim_slot_at);
    }

    /* Bind the class objects into the globals namespace so `integer` resolves. */
    sol_object_define(vm, vm->root, "integer", SOL_OBJ_VAL(vm->integer_class));
    sol_object_define(vm, vm->root, "float",   SOL_OBJ_VAL(vm->float_class));
    sol_object_define(vm, vm->root, "array",   SOL_OBJ_VAL(vm->array_class));
    sol_object_define(vm, vm->root, "string",  SOL_OBJ_VAL(vm->string_class));
    sol_object_define(vm, vm->root, "object",  SOL_OBJ_VAL(vm->object_class));
    /* Now that isKindOf takes a class, the remaining ones need names to be
       asked about. */
    sol_object_define(vm, vm->root, "symbol",  SOL_OBJ_VAL(vm->symbol_class));
    sol_object_define(vm, vm->root, "block",   SOL_OBJ_VAL(vm->block_class));
    sol_object_define(vm, vm->root, "boolean", SOL_OBJ_VAL(vm->bool_class));
    sol_object_define(vm, vm->root, "nil",     SOL_NIL_VAL);
    sol_object_define(vm, vm->root, "true",    SOL_BOOL_VAL(true));
    /* The two floats with no literal form. Naming them makes `infinity` and
       `nan` readable back, which is how a printed float round-trips. */
    sol_object_define(vm, vm->root, "infinity", SOL_FLOAT_VAL(INFINITY));
    sol_object_define(vm, vm->root, "nan",      SOL_FLOAT_VAL(NAN));
    sol_object_define(vm, vm->root, "false",   SOL_BOOL_VAL(false));
}
