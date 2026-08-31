/* builtins.c -- the classes that exist before any Solum code runs.
 *
 * Every method here is a C primitive. Arithmetic is strict: an integer only
 * combines with an integer, a float only with a float. There is no implicit
 * coercion, so `#45:add(1.5)` is an error rather than a quiet promotion.
 */
#define _POSIX_C_SOURCE 200809L    /* clock_gettime, for system:clock */
/* `struct stat`'s sub-second fields are hidden by _POSIX_C_SOURCE alone here,
   and they are spelled differently. See prim_system_modified_at. The Makefile
   passes this for every file on Darwin; the guard is so that saying it twice
   is not a warning, and it stays here because this is the file that needs it. */
#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#define _DARWIN_C_SOURCE
#endif

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <time.h>
#if defined(__unix__) || defined(__APPLE__)
#include <unistd.h>
#endif

#include "solum/serialize.h"
#include "solum/stdin.h"
#include "solum/vm.h"

/* Checks arity and reports a usable message if it is wrong. */
static bool check_argc(SolVM *vm, const char *name, int argc, int expected)
{
    if (argc == expected) return true;
    sol_vm_runtime_error(vm, "'%s' takes %d argument%s, got %d",
                         name, expected, expected == 1 ? "" : "s", argc);
    return false;
}

/* A block argument, checked when the message is *received* rather than when the
   block is called.

   Those are the same moment for a block that always runs and different moments
   for one that might not, and the difference was a hole: `false:and(#45)` never
   reaches the argument, so nothing looked at it, so it answered `false` and said
   nothing. The same held for the branch `ifElse` does not take, a `whileTrue`
   whose condition is false the first time, `do` over an empty array, `onError`
   over a block that did not fail -- fourteen messages where a wrong program was
   accepted **because of the data it happened to meet**. Checking here makes the
   complaint the same on every run of the same text, which is the only kind of
   complaint a program can be written against. */
static bool wants_block(SolVM *vm, const char *name, SolValue value)
{
    if (SOL_IS_BLOCK(value)) return true;
    sol_vm_runtime_error(vm, "'%s' expects a block, got %s", name,
                         sol_type_name(value));
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

/* Here because two attempts at writing it in Solum were both wrong and both
   silent about it -- see ROADMAP 3.14. Newton's method converges quadratically
   only once the guess is near, and from `x` itself the approach is one halving
   per octave, so a fixed iteration count is wrong for large `x` and a capped
   loop is wrong by orders of magnitude. Getting it right means scaling by the
   exponent first, which is asking a script to know how a double is laid out.
   The C library already knows, and is correctly rounded.

   Float only. `#2:sqrt` would have to answer a float, and no arithmetic message
   here crosses the two types; `#2:asFloat:sqrt` is how an integer asks.

   A negative answers nan rather than raising, which is the rule float division
   already follows below: this arithmetic reaches infinity and nan instead of
   trapping, because both are representable floats. */
static SolValue prim_float_sqrt(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "sqrt", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(sqrt(SOL_AS_FLOAT(self)));
}

/* The rest of the mathematics, landed as one set rather than a message at a
 * time -- ROADMAP 3.14, which spent its whole life waiting for a program that
 * wanted an angle and got programs/basic.sol: an interpreter for a language
 * whose own definition contains SIN, COS, TAN, ATN, EXP, LOG and an exponent
 * operator, and which cannot decide to want fewer of them.
 *
 * The case is the one that made sqrt a primitive above, and it is stronger.
 * The series for a sine is the easy half; the difficulty is argument
 * reduction, and reducing x modulo 2*pi needs pi to far more bits than a
 * double holds -- so the obvious `x - 2pi*round(x/2pi)` loses a digit of the
 * answer per octave of the argument and is returning noise well before 1e16.
 * Plausible output, catastrophically wrong in a range nobody thinks to test,
 * silent throughout. The C library already knows how to do it.
 *
 * asin, acos and atan2 are here although no program has asked for one, for the
 * same reason as the rest: written by hand, asin(x) is atan(x/sqrt(1-x*x)),
 * which divides by zero at the ends of its own domain, and atan2 is atan(y/x)
 * with quadrant fixups everybody gets wrong on the axes. Shipping the half a
 * program asked for is how the other half arrives one convenience at a time,
 * which is what that entry's rule exists to prevent.
 *
 * Radians, following C and following the standard basic.sol is written to.
 * Degrees are a multiplication and belong in lib/math.sol, which is the same
 * line this entry already drew between sqrt and min.
 *
 * None of them raise. sqrt answers nan for a negative and division reaches
 * infinity, so log(0) is -infinity and log of a negative is nan. A language
 * with stricter rules imposes them itself -- basic.sol raises for SQR(-1)
 * because ECMA-55 says so, on top of a sqrt that quietly answers nan, and that
 * is the right place for it. */
static SolValue prim_float_pow(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "pow", argc, 1)) return SOL_NIL_VAL;
    if (!check_same_type(vm, "pow", self, args[0])) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(pow(SOL_AS_FLOAT(self), SOL_AS_FLOAT(args[0])));
}

static SolValue prim_float_exp(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "exp", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(exp(SOL_AS_FLOAT(self)));
}

/* The natural logarithm, which is what every language calling it `log` means
   and what BASIC's LOG is. A base-ten one is log(x)/log(10) and needs nothing
   the machine has to supply. */
static SolValue prim_float_log(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "log", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(log(SOL_AS_FLOAT(self)));
}

static SolValue prim_float_sin(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "sin", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(sin(SOL_AS_FLOAT(self)));
}

static SolValue prim_float_cos(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "cos", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(cos(SOL_AS_FLOAT(self)));
}

static SolValue prim_float_tan(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "tan", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(tan(SOL_AS_FLOAT(self)));
}

/* Outside -1 to 1 these answer nan, which is the domain error IEEE gives and
   the same answer sqrt gives for a negative. */
static SolValue prim_float_asin(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asin", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(asin(SOL_AS_FLOAT(self)));
}

static SolValue prim_float_acos(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "acos", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(acos(SOL_AS_FLOAT(self)));
}

static SolValue prim_float_atan(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "atan", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(atan(SOL_AS_FLOAT(self)));
}

/* Class-side, and that is the answer to the question this message raises: it
   takes two coordinates and neither is the subject of the sentence, so
   `y:atan2(x)` reads as though the y were what the angle is about. `float` is
   the receiver instead, the way `time:fromSeconds` and `array:of` are written,
   and then the arguments are in the order the name has always had them. */
static SolValue prim_float_atan2(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "atan2", argc, 2)) return SOL_NIL_VAL;
    for (int i = 0; i < 2; i++) {
        if (!SOL_IS_FLOAT(args[i])) {
            sol_vm_runtime_error(vm, "'atan2' expects a float, got %s",
                                 sol_type_name(args[i]));
            return SOL_NIL_VAL;
        }
    }
    return SOL_FLOAT_VAL(atan2(SOL_AS_FLOAT(args[0]), SOL_AS_FLOAT(args[1])));
}

/* Class-side too, and not a global. `infinity` and `nan` are globals because
   they are values this type produces and has no other way to name; pi is a
   constant, and `pi` is a name a program is entitled to want -- which is the
   argument lib/math.sol already makes for binding no global of its own.

   It is the one member of this set that a script could have got right on its
   own: 3.141592653589793 is the nearest double and anybody can type it. It is
   here so that a language with sin and cos is not a language where the first
   thing every program does is write out a constant. */
static SolValue prim_float_pi(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    (void)args;
    if (!check_argc(vm, "pi", argc, 0)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(3.14159265358979311599796346854418516159057617187500);
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
#define SOL_SPEC_MAX_DECIMALS 40

/* 309 digits for DBL_MAX, a sign, a point, the decimals, and the NUL. */
#define SOL_FLOAT_DECIMALS_MAX (309 + 2 + SOL_SPEC_MAX_DECIMALS + 1)

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
        if (digits == 0 || out->decimals > SOL_SPEC_MAX_DECIMALS) {
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
        /* Big enough for the worst case there is: DBL_MAX has 309 digits before
           the point, the spec allows 40 after it, and a sign and a point sit
           between -- 351 characters.

           This was 64, and the bug that hid there is worth naming because it is
           not the one a short buffer is usually blamed for. `snprintf` does not
           overflow; it truncates. What it *answers* is the length it would have
           written had there been room, and that length went straight to
           `spec_finish` as the length of the text. So `1e150:asString("0.6")`
           produced a 157-character string of which 93 characters were whatever
           lay behind the buffer on the stack -- an over-read, and stack bytes
           handed to a script as a string it can print. Found by bench.sol, which
           wanted a square root and tested it at 1e300.

           The clamp below makes the length agree with the buffer whatever the
           buffer is, so this cannot come back if the sizing is ever wrong
           again. */
        char buffer[SOL_FLOAT_DECIMALS_MAX];
        int n = snprintf(buffer, sizeof buffer, "%.*f", spec.decimals, d);
        if (n < 0) n = 0;
        if (n >= (int)sizeof buffer) n = (int)sizeof buffer - 1;
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
/* `#5:inc` and `#5:dec` -- one more, one less.
 *
 * `add(#1)` with a shorter name, which is a thing this language usually refuses
 * to add. What earns it is how often it is written: **76 of the 256 arithmetic
 * sends** in the examples and libraries are `add(#1)` or `sub(#1)`, which is
 * three in every ten. That is a consequence of having no binary operators --
 * `i := i + 1` is short in a language with them and `i := i:add(#1)` is not --
 * so the commonest arithmetic there is pays the most for the design.
 *
 * They answer a new integer rather than changing the receiver, because an
 * integer is a value: `a := a:inc` is the whole idiom and `a:inc` on its own
 * does nothing. The saving is the `(#1)`, and that is all it is.
 *
 * Integers only. A float counter is a different thing -- counting by ones in a
 * type where a one is not exact is a mistake to make deliberately rather than
 * conveniently.
 */
static SolValue prim_integer_inc(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "inc", argc, 0)) return SOL_NIL_VAL;

    int64_t result;
    if (__builtin_add_overflow(SOL_AS_INT(self), (int64_t)1, &result)) {
        sol_vm_runtime_error(vm, "integer overflow in 'inc'");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(result);
}

static SolValue prim_integer_dec(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "dec", argc, 0)) return SOL_NIL_VAL;

    int64_t result;
    if (__builtin_sub_overflow(SOL_AS_INT(self), (int64_t)1, &result)) {
        sol_vm_runtime_error(vm, "integer overflow in 'dec'");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(result);
}

/* ---- bits ---------------------------------------------------------------- *
 *
 * An integer is a signed 64-bit two's-complement number and there is no
 * unsigned type, which decides most of what follows.
 *
 * The case for these was written before they existed: `lib/text.sol` encodes
 * UTF-8 with `div(#64)` and `mod(#64)` and puts the tag bits on with `add`,
 * carrying a comment saying it does so for the want of shifts and masks. A
 * workaround in shipped library code is the same signal that got `removeLast`
 * and `indexOf` built. File modes are the second use: `modeOf(path)` answers an
 * integer, and "make this executable" is an or with #73.
 */
static bool bit_argument(SolVM *vm, const char *name, SolValue self, SolValue other)
{
    if (!SOL_IS_INT(self)) return false;       /* the receiver check has run */
    if (!SOL_IS_INT(other)) {
        sol_vm_runtime_error(vm, "'%s' expects an integer, got %s", name,
                             sol_type_name(other));
        return false;
    }
    return true;
}

static SolValue prim_integer_bit_and(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "bitAnd", argc, 1)) return SOL_NIL_VAL;
    if (!bit_argument(vm, "bitAnd", self, args[0])) return SOL_NIL_VAL;
    return SOL_INT_VAL((int64_t)((uint64_t)SOL_AS_INT(self) &
                                 (uint64_t)SOL_AS_INT(args[0])));
}

static SolValue prim_integer_bit_or(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "bitOr", argc, 1)) return SOL_NIL_VAL;
    if (!bit_argument(vm, "bitOr", self, args[0])) return SOL_NIL_VAL;
    return SOL_INT_VAL((int64_t)((uint64_t)SOL_AS_INT(self) |
                                 (uint64_t)SOL_AS_INT(args[0])));
}

static SolValue prim_integer_bit_xor(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "bitXor", argc, 1)) return SOL_NIL_VAL;
    if (!bit_argument(vm, "bitXor", self, args[0])) return SOL_NIL_VAL;
    return SOL_INT_VAL((int64_t)((uint64_t)SOL_AS_INT(self) ^
                                 (uint64_t)SOL_AS_INT(args[0])));
}

/* Every bit flipped, so `#0:bitNot` is `#-1` and `n:bitNot` is `#0:sub(n):dec`.
   Done in unsigned, where the result is defined rather than left to the
   compiler. */
static SolValue prim_integer_bit_not(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "bitNot", argc, 0)) return SOL_NIL_VAL;
    return SOL_INT_VAL((int64_t)~(uint64_t)SOL_AS_INT(self));
}

/* How far a shift may go. 64 bits, so #0 to #63 -- and a count outside that is
   refused rather than answering whatever the hardware does with it, which is
   the same choice `div` makes about zero. */
static bool shift_count(SolVM *vm, const char *name, SolValue value, int64_t *out)
{
    if (!SOL_IS_INT(value)) {
        sol_vm_runtime_error(vm, "'%s' expects an integer, got %s", name,
                             sol_type_name(value));
        return false;
    }
    int64_t n = SOL_AS_INT(value);
    if (n < 0 || n > 63) {
        sol_vm_runtime_error(vm, "'%s' wants #0 to #63, got #%lld", name,
                             (long long)n);
        return false;
    }
    *out = n;
    return true;
}

/* Left, and it **traps on overflow** like `mul` rather than dropping the bits
   that go off the end. A shift that loses the number is a mistake in the same
   way a product that does not fit is one. */
static SolValue prim_integer_shift_left(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "shiftLeft", argc, 1)) return SOL_NIL_VAL;
    int64_t n;
    if (!shift_count(vm, "shiftLeft", args[0], &n)) return SOL_NIL_VAL;

    int64_t x = SOL_AS_INT(self);
    if (n > 0 && x != 0) {
        /* Everything from -2^(63-n) up to 2^(63-n) survives the shift, and
           nothing else does. The bound fits because 63 - n is at most 62. */
        int64_t bound = (int64_t)1 << (63 - n);
        if (x >= bound || x < -bound) {
            sol_vm_runtime_error(vm, "integer overflow in 'shiftLeft'");
            return SOL_NIL_VAL;
        }
    }
    return SOL_INT_VAL((int64_t)((uint64_t)x << n));
}

/* Right, and **arithmetic**: the sign is kept, so `#-8:shiftRight(#1)` is `#-4`.
 *
 * That is not a free choice. There is no unsigned integer here, so a logical
 * shift would turn every negative number into a huge positive one, which is not
 * an answer anybody wants from a language whose integers are signed. Keeping
 * the sign also makes a shift agree exactly with `div` by a power of two, which
 * is **floored** -- and the agreement is worth having, since the two are the
 * same operation written twice.
 *
 * Written as that division rather than with C's `>>`, whose behaviour on a
 * negative left operand is left to the implementation.
 */
static SolValue prim_integer_shift_right(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "shiftRight", argc, 1)) return SOL_NIL_VAL;
    int64_t n;
    if (!shift_count(vm, "shiftRight", args[0], &n)) return SOL_NIL_VAL;

    int64_t x = SOL_AS_INT(self);
    if (n == 0) return SOL_INT_VAL(x);
    if (n >= 63) return SOL_INT_VAL(x < 0 ? -1 : 0);   /* the sign, spread out */

    int64_t divisor = (int64_t)1 << n;
    int64_t quotient = x / divisor;
    if (x < 0 && quotient * divisor != x) quotient -= 1;   /* floor, not trunc */
    return SOL_INT_VAL(quotient);
}

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

/* `#65:asCharacter` -- the one-byte string that byte spells. The inverse of
 * `asByte`, and the only way to write a byte the lexer has no escape for: there
 * is no `\0` in a literal, so `#0:asCharacter` is where a NUL comes from.
 * Strings are length-counted and carry one through `readFile` and `writeFile`
 * already, so this adds a spelling rather than a hazard.
 *
 * A code point is not a byte above 127. `#233:asCharacter` is one byte, which
 * is Latin-1 rather than the two bytes UTF-8 spells é with -- encoding a code
 * point is arithmetic on top of this and belongs where the format is known.
 */
static SolValue prim_integer_as_character(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asCharacter", argc, 0)) return SOL_NIL_VAL;

    int64_t value = SOL_AS_INT(self);
    if (value < 0 || value > 255) {
        sol_vm_runtime_error(vm,
            "#%lld is not a byte -- 'asCharacter' wants #0 to #255",
            (long long)value);
        return SOL_NIL_VAL;
    }
    char byte = (char)(unsigned char)value;
    return SOL_STRING_VAL(sol_string_new(vm, &byte, 1));
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

/* `"  42 ":trim` -- the same text without the space around it.
 *
 * Wanted by the first program that read another program's output. `wc -l`
 * answers `"     100\n"`, and `asInteger` is strict about the whole string
 * being a number -- rightly, since `"12abc"` is a mistake rather than twelve --
 * so text arriving from outside needs the padding taken off before it can be
 * anything else. Every tool that prints a number pads it, and every script that
 * reads one trims it.
 *
 * Space, tab, newline and carriage return: the four a terminal produces.
 * Nothing else is whitespace here, because a string is bytes and deciding what
 * is blank in a text this language cannot otherwise read would be a promise it
 * could not keep.
 *
 * A string with nothing to remove answers itself; strings are immutable, so
 * nothing can tell, and it saves an allocation.
 */
static bool is_blank(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static SolValue prim_string_trim(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "trim", argc, 0)) return SOL_NIL_VAL;

    const SolString *string = SOL_AS_STRING(self);
    int from = 0, to = string->length;
    while (from < to && is_blank(string->chars[from])) from++;
    while (to > from && is_blank(string->chars[to - 1])) to--;

    if (from == 0 && to == string->length) return self;
    return SOL_STRING_VAL(sol_string_new(vm, string->chars + from, to - from));
}

/* `"A":asByte` -- the number of the one byte in the receiver.
 *
 * Named for what it answers rather than for what a caller might wish it
 * answered. A string is bytes (ROADMAP 2.13), so this is a byte and not a
 * character: `"é"` is two bytes and is refused, which is the honest answer and
 * the one that keeps `asByte` and `asCharacter` exact inverses.
 *
 * Strict about the size for the same reason `asInteger` is strict about its
 * digits: a message that quietly took the first byte of a longer string would
 * answer something plausible for input that is a mistake.
 */
static SolValue prim_string_as_byte(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asByte", argc, 0)) return SOL_NIL_VAL;

    const SolString *string = SOL_AS_STRING(self);
    if (string->length == 0) {
        sol_vm_runtime_error(vm, "'asByte' wants one byte, and this string is empty");
        return SOL_NIL_VAL;
    }
    if (string->length != 1) {
        sol_vm_runtime_error(vm,
            "'asByte' wants one byte, and this string has %d -- a character "
            "outside ASCII is more than one of them",
            string->length);
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL((int64_t)(unsigned char)string->chars[0]);
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

    /* `sol_value_equals` is the one definition, in object.c, because a
       dictionary asks the same question of its keys and the two must not come
       to disagree about what one key being another means. What it says, per
       type: nil and booleans and numbers by their value; strings by their
       contents, being immutable and so values themselves; symbols by pointer,
       being interned, which is the same thing; and blocks, arrays, objects,
       delegates and dictionaries by identity, two arrays with equal elements
       being two arrays. Comparing contents is a different question and deserves
       its own name rather than quietly changing what `equals` means. */
    return SOL_BOOL_VAL(sol_value_equals(self, args[0]));
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

    /* A symbol orders by its text, like the string it is written as.
     *
       Interning is what makes `equals` on two symbols a pointer comparison, and
       it is exactly what makes their *addresses* say nothing about their order
       -- so this is the one symbol operation that has to look at the
       characters. Worth it: an array of symbols is what a tally is keyed by,
       and a report wants a stable order to print in. */
    const char *xc; int xn;
    const char *yc; int yn;
    if (SOL_IS_SYMBOL(a)) {
        xc = SOL_AS_SYMBOL(a)->chars; xn = SOL_AS_SYMBOL(a)->length;
        yc = SOL_AS_SYMBOL(b)->chars; yn = SOL_AS_SYMBOL(b)->length;
    } else {
        xc = SOL_AS_STRING(a)->chars; xn = SOL_AS_STRING(a)->length;
        yc = SOL_AS_STRING(b)->chars; yn = SOL_AS_STRING(b)->length;
    }

    int shorter = xn < yn ? xn : yn;
    int order = memcmp(xc, yc, (size_t)shorter);
    if (order != 0) return order < 0 ? -1 : 1;
    return xn < yn ? -1 : (xn > yn ? 1 : 0);
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
    if (!wants_block(vm, "ifTrue", args[0])) return SOL_NIL_VAL;
    if (!SOL_AS_BOOL(self)) return SOL_NIL_VAL;
    return sol_vm_call_block(vm, args[0], NULL, 0);
}

static SolValue prim_if_false(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "ifFalse", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "ifFalse", args[0])) return SOL_NIL_VAL;
    if (SOL_AS_BOOL(self)) return SOL_NIL_VAL;
    return sol_vm_call_block(vm, args[0], NULL, 0);
}

static SolValue prim_if_else(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "ifElse", argc, 2)) return SOL_NIL_VAL;
    /* Both, not the one about to run: a branch is not checked by being taken. */
    if (!wants_block(vm, "ifElse", args[0])) return SOL_NIL_VAL;
    if (!wants_block(vm, "ifElse", args[1])) return SOL_NIL_VAL;
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
    if (!wants_block(vm, "and", args[0])) return SOL_NIL_VAL;
    if (!SOL_AS_BOOL(self)) return SOL_BOOL_VAL(false);   /* the block never runs */
    return boolean_block(vm, "and", args[0]);
}

static SolValue prim_or(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "or", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "or", args[0])) return SOL_NIL_VAL;
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

/* `m:boundTo(receiver)` -- the same code, run with a receiver you choose.
 *
 * A block carries the `self` it was written under, and a send to a slot holding
 * one supplies its own receiver instead. That is what makes an installed block
 * a method, and it is why a *fetched* method is unbound: `slotAt` answers the
 * plain block, so `m:value` runs with whatever `self` was where it was written
 * -- nil, for a method written at the top level.
 *
 * This answers a second block over the same code with `self` set. Answering a
 * block rather than calling it follows `via`, which answers a delegating view
 * rather than doing the send: binding and calling are two things, so `value`
 * goes on meaning exactly what it meant, arity included -- there is no
 * argument list with a receiver hidden at the front of it.
 *
 * The home frame comes across unchanged, so a capturing block is no freer than
 * it was: binding chooses a receiver, not a lifetime (3.1).
 *
 * No temp root. The receiver of this send and its argument are both still on
 * the value stack -- the dispatch loop drops them after the primitive returns,
 * not before -- and the stack is a root, so the collection sol_block_new may
 * trigger can see both. */
static SolValue prim_bound_to(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "boundTo", argc, 1)) return SOL_NIL_VAL;

    SolBlock *block = SOL_AS_BLOCK(self);
    return SOL_BLOCK_VAL(sol_block_new(vm, block->code, args[0],
                                       block->home_frame, block->home_id));
}

/* `{ condition }:whileTrue({ body })` -- the receiver is re-run every pass,
   which is the whole reason it has to be a block rather than a value. */
/* ---- counted loops ----------------------------------------------------- *
 *
 * `repeat` and the counted loop lived in lib/control.sol, written in Solum.
 * Roadmap 6.6 was about inlining them the way `whileTrue` and `doUntil` are
 * inlined, and that turned out to be both harder and worse than making them
 * primitives.
 *
 * Harder, because a counted loop needs a counter that survives the iteration
 * and the receiver's type is not known while compiling. `whileTrue` inlines
 * because its receiver must be a literal block; `#n:repeat` takes whatever
 * expression you wrote, and `1.5:repeat({...})` has to go on saying *float does
 * not understand 'repeat'* rather than complaining about the counter. Getting
 * that right through inlined jumps needs a type-guard instruction that does not
 * exist.
 *
 * Worse, because dispatch already answers it for free -- a message installed
 * for SOL_INT receivers is simply not found on `float` -- and because the
 * counter arithmetic moves from bytecode into C. The Solum version pays a
 * `lessThan` send and an `add` send per iteration on top of the block call;
 * inlining removes the block call and keeps the two sends, where a primitive
 * removes the two sends and keeps the block call. The sends cost more.
 */
static SolValue prim_integer_repeat(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "repeat", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "repeat", args[0])) return SOL_NIL_VAL;

    int64_t times = SOL_AS_INT(self);
    for (int64_t i = 0; i < times; i++) {
        sol_vm_call_block(vm, args[0], NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;
    }
    /* A count of zero or less runs the body no times rather than complaining,
       which is what an empty range does everywhere else here. */
    return SOL_NIL_VAL;
}

/* `{ body }:repeat(#n)` -- the same loop, said the other way round, because
   which reads better depends on which of the two the sentence is about. */
static SolValue prim_block_repeat(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "repeat", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_INT(args[0])) {
        sol_vm_runtime_error(vm, "'repeat' expects an integer count, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    int64_t times = SOL_AS_INT(args[0]);
    for (int64_t i = 0; i < times; i++) {
        sol_vm_call_block(vm, self, NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

/* `[#from, #to, #step]:loop({ n | ... })` -- inclusive at both ends,
 * following `at` and `copyFrom`: an index here is an ordinal, and half-open
 * ranges are what make *zero*-based indexing tidy. The step is optional, and a
 * two-element array means a step of #1.
 *
 * The range arrives as an array so that the three numbers are written together
 * and in order. It cost the send-time arity check the two-message spelling had:
 * an array of the wrong size can only be caught here, at run time, which is why
 * the complaint below names what it wanted rather than only what it got.
 *
 * A negative step counts down and stops when it passes the limit. A step of #0
 * would never finish, so it is refused -- the Solum version could only print a
 * complaint and carry on, which is the sort of thing a primitive can do
 * properly. */
static SolValue prim_array_loop(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "loop", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "loop", args[0])) return SOL_NIL_VAL;

    SolArray *range = SOL_AS_ARRAY(self);
    if (range->count != 2 && range->count != 3) {
        sol_vm_runtime_error(vm,
            "'loop' wants [from, to] or [from, to, step], got %d element%s",
            range->count, range->count == 1 ? "" : "s");
        return SOL_NIL_VAL;
    }

    /* Named rather than indexed from here down, because `values[2]` meaning the
       step is exactly the thing this spelling was chosen to stop a reader
       having to remember. */
    for (int i = 0; i < range->count; i++) {
        if (!SOL_IS_INT(range->items[i])) {
            static const char *part[3] = { "from", "to", "step" };
            sol_vm_runtime_error(vm, "'loop' expects an integer for '%s', got %s",
                                 part[i], sol_type_name(range->items[i]));
            return SOL_NIL_VAL;
        }
    }

    int64_t from  = SOL_AS_INT(range->items[0]);
    int64_t limit = SOL_AS_INT(range->items[1]);
    int64_t step  = range->count == 3 ? SOL_AS_INT(range->items[2]) : 1;

    if (step == 0) {
        sol_vm_runtime_error(vm, "'loop' needs a step other than #0");
        return SOL_NIL_VAL;
    }

    /* The index is handed to the block, so it has to be a value each pass. The
       overflow check is what stops a step near INT64_MAX wrapping past the
       limit and running forever. */
    for (int64_t i = from; step > 0 ? i <= limit : i >= limit; ) {
        SolValue index = SOL_INT_VAL(i);
        sol_vm_call_block(vm, args[0], &index, 1);
        if (vm->had_error) return SOL_NIL_VAL;

        int64_t next;
        if (__builtin_add_overflow(i, step, &next)) break;
        i = next;
    }
    return SOL_NIL_VAL;
}

/* `{ body }:doUntil({ condition })` -- the body first, then the test, so it
 * always runs at least once.
 *
 * The one loop shape `whileTrue` cannot express without a flag declared outside
 * it, which is why this is built in rather than left in the library where it
 * started: written literally it compiles to jumps, and the two block calls an
 * iteration -- one for the body, one for the condition -- go away. Measured at
 * 1.70x before that, which is the largest of the loop constructs because it is
 * the only one paying for two.
 *
 * The complaint names `doUntil` rather than `whileTrue`, and the inlined form
 * says the same thing by way of OP_CHECK_BOOL, which carries the name. */
static SolValue prim_do_until(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "doUntil", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "doUntil", args[0])) return SOL_NIL_VAL;

    for (;;) {
        sol_vm_call_block(vm, self, NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;

        SolValue answer = sol_vm_call_block(vm, args[0], NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;

        if (!SOL_IS_BOOL(answer)) {
            sol_vm_block_answer_error(vm, "doUntil", answer);
            return SOL_NIL_VAL;
        }
        if (SOL_AS_BOOL(answer)) return SOL_NIL_VAL;
    }
}

static SolValue prim_while_true(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "whileTrue", argc, 1)) return SOL_NIL_VAL;
    /* Before the first test, so a loop whose condition is false to begin with
       still complains about a body that is not one. */
    if (!wants_block(vm, "whileTrue", args[0])) return SOL_NIL_VAL;

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
    if (!check_argc(vm, "atPut", argc, 2)) return SOL_NIL_VAL;

    SolArray *array = SOL_AS_ARRAY(self);
    int index;
    if (!array_index(vm, "atPut", array, args[0], &index)) return SOL_NIL_VAL;
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
    if (!wants_block(vm, "do", args[0])) return SOL_NIL_VAL;

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
    if (!wants_block(vm, "collect", args[0])) return SOL_NIL_VAL;

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

/* `xs:removeLast` -- takes the last element off and answers it.
 *
 * Refuses an empty array rather than answering nil, which is the same choice
 * `at` makes about an index out of range: nil would be a second way of saying
 * "nothing here" beside the one the language already has, and it would turn a
 * mistake into a value that fails somewhere else. A caller with an array that
 * might be empty asks `size` first, which is the shape a stack's loop condition
 * already has.
 *
 * The slot beyond the new count is left as it was. The tracer walks `count`
 * rather than `capacity`, so it is not reachable, and the value being answered
 * is on the stack and rooted by the caller. */
static SolValue prim_array_remove_last(SolVM *vm, SolValue self, SolValue *args,
                                       int argc)
{
    (void)args;
    if (!check_argc(vm, "removeLast", argc, 0)) return SOL_NIL_VAL;

    SolArray *array = SOL_AS_ARRAY(self);
    if (array->count == 0) {
        sol_vm_runtime_error(vm, "'removeLast' wants an element, and this array is empty");
        return SOL_NIL_VAL;
    }
    return array->items[--array->count];
}

/* `xs:indexOf(v)` -- where `v` first is, one-based, or nil.
 *
 * Answers nil rather than #0 for the same reason `string:indexOf` does: indices
 * start at #1, so #0 would be an out-of-band value and a second way of saying
 * "nothing". It is also why there is no `includes` -- `indexOf(v):notNil` is
 * that question, and one message answering *where* is worth more than two, one
 * of which only answers *whether*.
 *
 * Equality is `sol_value_equals`, the same one `equals` sends: by content for
 * values, by identity for arrays, blocks, objects and dictionaries. So an array
 * finds a string equal to one it holds, and finds another array only if it is
 * the same array. That is the line the language draws everywhere else. */
static SolValue prim_array_index_of(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "indexOf", argc, 1)) return SOL_NIL_VAL;

    const SolArray *array = SOL_AS_ARRAY(self);
    for (int i = 0; i < array->count; i++) {
        if (sol_value_equals(array->items[i], args[0])) return SOL_INT_VAL(i + 1);
    }
    return SOL_NIL_VAL;
}

static SolValue prim_array_select(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "select", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "select", args[0])) return SOL_NIL_VAL;

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

/* A fresh array holding `count` of `source`'s elements from `at` (zero-based
   here, one-based at the boundary). Shared by the three slicing messages so
   they cannot come to disagree about what copying means. */
static SolValue slice_of(SolVM *vm, const SolArray *source, int at, int count)
{
    SolArray *out = sol_array_new(vm, count);
    sol_gc_push_temp(vm, &out->gc);
    for (int i = 0; i < count; i++) sol_array_add(vm, out, SOL_NIL_VAL);

    /* The receiver is on the value stack for the duration, so `source` and
       everything in it stay rooted while the copy is made. Nothing allocates
       after the array is grown, so the elements need no rooting of their own. */
    for (int i = 0; i < count; i++) out->items[i] = source->items[at + i];

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(out);
}

/* `copyFrom(#a, #b)` -- both ends included, both one-based, exactly as a
 * string's is. `#1:copyFrom(#1, #1)` is a one-element array where `at(#1)` is
 * the element itself, which is the only difference between them.
 *
 * Out of range is an **error**, following `at`. The empty slice is spelled with
 * `to` one before `from` and only that far, and `from` may be one past the end,
 * which is where the empty tail is. All of that is the string's rule, and
 * having two collections disagree about what a slice means would be worse than
 * either rule is good. */
static SolValue prim_array_copy_from(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "copyFrom", argc, 2)) return SOL_NIL_VAL;
    if (!SOL_IS_INT(args[0]) || !SOL_IS_INT(args[1])) {
        sol_vm_runtime_error(vm, "'copyFrom' expects integer bounds, got %s and %s",
                             sol_type_name(args[0]), sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }

    const SolArray *source = SOL_AS_ARRAY(self);
    int64_t from = SOL_AS_INT(args[0]);
    int64_t to   = SOL_AS_INT(args[1]);

    if (from < 1 || from > (int64_t)source->count + 1) {
        sol_vm_runtime_error(vm, "'copyFrom' starts at #%lld, outside an array of size %d",
                             (long long)from, source->count);
        return SOL_NIL_VAL;
    }
    if (to > (int64_t)source->count) {
        sol_vm_runtime_error(vm, "'copyFrom' ends at #%lld, past an array of size %d",
                             (long long)to, source->count);
        return SOL_NIL_VAL;
    }
    if (to < from - 1) {
        sol_vm_runtime_error(vm,
            "'copyFrom' ends at #%lld, more than one before its start #%lld",
            (long long)to, (long long)from);
        return SOL_NIL_VAL;
    }

    return slice_of(vm, source, (int)(from - 1), (int)(to - from + 1));
}

/* `first(#n)` and `last(#n)` -- and these **clamp** where `copyFrom` refuses.
 *
 * Deliberately two rules, because they are two questions. `copyFrom` names
 * positions, and a position outside the array is a program wrong about
 * something. `first` names a quantity -- give me the top five -- and a list
 * with only three in it has answered that question correctly by handing over
 * three. Refusing there would make every ranked report check the size first,
 * which is the whole of what these exist to avoid.
 *
 * A negative count is refused by both, since clamping is for asking for more
 * than there is, not for asking for nonsense. `#0` is the empty array. */
static bool slice_count(SolVM *vm, const char *name, SolValue value,
                        int size, int *out)
{
    if (!SOL_IS_INT(value)) {
        sol_vm_runtime_error(vm, "'%s' expects an integer count, got %s",
                             name, sol_type_name(value));
        return false;
    }

    int64_t wanted = SOL_AS_INT(value);
    if (wanted < 0) {
        sol_vm_runtime_error(vm, "'%s' needs a count of #0 or more, got #%lld",
                             name, (long long)wanted);
        return false;
    }

    *out = wanted > (int64_t)size ? size : (int)wanted;
    return true;
}

static SolValue prim_array_first(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "first", argc, 1)) return SOL_NIL_VAL;

    const SolArray *source = SOL_AS_ARRAY(self);
    int count;
    if (!slice_count(vm, "first", args[0], source->count, &count)) return SOL_NIL_VAL;

    return slice_of(vm, source, 0, count);
}

static SolValue prim_array_last(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "last", argc, 1)) return SOL_NIL_VAL;

    const SolArray *source = SOL_AS_ARRAY(self);
    int count;
    if (!slice_count(vm, "last", args[0], source->count, &count)) return SOL_NIL_VAL;

    return slice_of(vm, source, source->count - count, count);
}

/* `inject(start, block)` -- the fold. The block is given what has accumulated
 * so far and one element, and answers the next accumulation:
 *
 *     [#1, #2, #3]:inject(#0, { total, n | total:add(n) }).   ; #6
 *
 * An empty array answers `start` without calling the block, which is what makes
 * a fold safe to write without asking first whether there is anything to fold.
 *
 * This is the fourth of the iteration messages and the one that was missing.
 * `do` throws its answers away, `collect` and `select` each answer an array, and
 * every reduction to a single value had to be a `do` with an accumulator
 * declared outside it -- which works, but only at the top of a frame, and never
 * in the middle of an expression. */
static SolValue prim_array_inject(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "inject", argc, 2)) return SOL_NIL_VAL;
    if (!wants_block(vm, "inject", args[1])) return SOL_NIL_VAL;

    SolArray *source = SOL_AS_ARRAY(self);

    /* The accumulated value lives on the value stack for the length of the
       fold. It is a fresh value at almost every step and nothing else refers to
       it, and `sol_gc_push_temp` cannot hold it -- an integer or a nil has no
       header to push, where the stack roots any value whatever its type.

       Defensive rather than load-bearing, and worth being honest about which:
       `sol_vm_call_block` pushes the receiver and arguments before it can
       allocate, so today the accumulated value is already rooted at every point
       a collection can happen, and taking this out passes under
       `SOLUM_GC_STRESS=1`. What it costs is one stack slot; what it buys is
       that `inject` holds its own value across an unbounded number of calls
       into the language instead of relying on what another function does with
       its arguments. `collect` can rely on that, having nothing live between
       one call and the next. */
    SolValue *accumulated = vm->stack_top;
    sol_vm_push(vm, args[0]);
    if (vm->had_error) return SOL_NIL_VAL;      /* the stack was full */

    /* Bounded once and re-read each pass, as `do` and `collect` are. */
    int limit = source->count;
    for (int i = 0; i < limit; i++) {
        if (i >= source->count) break;

        /* Copied out rather than passed by pointer, since the two do not sit
           together anywhere. Nothing allocates between here and the pushes
           inside the call, so the copy needs no rooting of its own. */
        SolValue pair[2] = { *accumulated, source->items[i] };

        SolValue next = sol_vm_call_block(vm, args[1], pair, 2);
        if (vm->had_error) {
            sol_vm_pop(vm);
            return SOL_NIL_VAL;
        }
        *accumulated = next;
    }

    return sol_vm_pop(vm);
}

/* `join(separator)` -- the pieces with the separator between them, and the
 * inverse of `split`:
 *
 *     "a,,b":split(","):join(",").          ; "a,,b"
 *
 * That round trip holds for every string and every separator, which is the
 * point of `split` keeping its empty pieces.
 *
 * Strict about what it joins: an array holding anything but a string is an
 * error rather than a silent `asString` on each element. Rendering a value as
 * text is what `fill` and `asString` are for, and a `join` that did it too
 * would be a second way to reach the same place, quietly.
 *
 * The separator may be empty, where `split`'s may not. The two are not the same
 * question: nothing can be *looked for*, since every position contains it, but
 * putting nothing between the pieces is exactly concatenation. */
static SolValue prim_array_join(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "join", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'join' expects a string separator, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    const SolString *separator = SOL_AS_STRING(args[0]);
    const SolArray  *pieces    = SOL_AS_ARRAY(self);

    /* Measured before anything is written, so the whole answer is one
       allocation and a bad element is found before any work is done. */
    int64_t total = 0;
    for (int i = 0; i < pieces->count; i++) {
        if (!SOL_IS_STRING(pieces->items[i])) {
            sol_vm_runtime_error(vm, "'join' expects an array of strings; #%d is %s",
                                 i + 1, sol_type_name(pieces->items[i]));
            return SOL_NIL_VAL;
        }
        total += SOL_AS_STRING(pieces->items[i])->length;
    }
    if (pieces->count > 1) {
        total += (int64_t)separator->length * (pieces->count - 1);
    }
    if (total > INT_MAX) {
        sol_vm_runtime_error(vm, "'join' would make a string of %lld bytes",
                             (long long)total);
        return SOL_NIL_VAL;
    }

    char *joined = malloc((size_t)total + 1);
    if (joined == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }

    /* The array is the receiver and on the value stack throughout, so every
       piece stays rooted while it is copied out. */
    size_t at = 0;
    for (int i = 0; i < pieces->count; i++) {
        if (i > 0 && separator->length > 0) {
            memcpy(joined + at, separator->chars, (size_t)separator->length);
            at += (size_t)separator->length;
        }
        const SolString *piece = SOL_AS_STRING(pieces->items[i]);
        memcpy(joined + at, piece->chars, (size_t)piece->length);
        at += (size_t)piece->length;
    }
    joined[total] = '\0';

    SolValue result = SOL_STRING_VAL(sol_string_new(vm, joined, (int)total));
    free(joined);
    return result;
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

/* Where `needle` first appears in `haystack` at or after `from`, zero-based, or
   -1. Not strstr: a string is bytes and may hold a NUL, so the length is what
   says where it ends and a search has to respect that. */
static int find_substring(const SolString *haystack, const SolString *needle, int from)
{
    if (needle->length == 0 || needle->length > haystack->length) return -1;

    for (int i = from; i + needle->length <= haystack->length; i++) {
        if (memcmp(haystack->chars + i, needle->chars,
                   (size_t)needle->length) == 0) {
            return i;
        }
    }
    return -1;
}

/* Both `split` and `indexOf` look for something, and neither can look for
   nothing: every position in every string contains the empty string, so the
   answer would be arbitrary rather than useful. An error says so at the point
   the mistake was made. */
static bool needle_from(SolVM *vm, const char *name, SolValue value,
                        const SolString **out)
{
    if (!SOL_IS_STRING(value)) {
        sol_vm_runtime_error(vm, "'%s' expects a string, got %s",
                             name, sol_type_name(value));
        return false;
    }
    const SolString *needle = SOL_AS_STRING(value);
    if (needle->length == 0) {
        sol_vm_runtime_error(vm, "'%s' needs at least one character to look for", name);
        return false;
    }
    *out = needle;
    return true;
}

/* Answers an array of the pieces between occurrences of `separator`.
 *
 * There are always occurrences + 1 pieces, and no piece is ever dropped: a
 * separator at either end, or two together, gives an empty string where the
 * missing piece would be. That is what makes the answer predictable -- the
 * pieces put back together with the separator between them are the original
 * string, whatever the string was. Dropping empties would read more kindly on
 * `" a  b "` and would lose the difference between `"a,,b"` and `"a,b"`, which
 * a program parsing a file is usually the one thing it needs to keep. */
/* "a-b-c":replace("-", "+") -- every occurrence, left to right.
 *
 * **Every rather than the first**, and the reason is that this message replaces
 * an idiom rather than inventing a capability: `split` then `join` was how it
 * was written before, and that pair replaces all of them. A `replace` that did
 * one would not be shorter than the thing it replaced, it would be different
 * from it -- and a program that had been using the idiom would change meaning
 * on being tidied up.
 *
 * So there is one message and it does the obvious thing. A first-only replace is
 * `indexOf` and two `copyFrom`s, which is what wanting it looks like and is rare
 * enough not to name.
 *
 * Non-overlapping, scanning forward: each match resumes after the one before,
 * so `"aaa":replace("aa", "b")` is `"ba"` and not `"bb"` or anything cleverer.
 *
 * An empty needle is refused by `needle_from`, the way `split` and `indexOf`
 * refuse it -- replacing nothing everywhere has no answer worth guessing at. An
 * empty *replacement* is allowed and is how a program deletes.
 */
static SolValue prim_string_replace(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "replace", argc, 2)) return SOL_NIL_VAL;

    const SolString *from;
    if (!needle_from(vm, "replace", args[0], &from)) return SOL_NIL_VAL;

    if (!SOL_IS_STRING(args[1])) {
        sol_vm_runtime_error(vm, "'replace' expects a string to put in its place, got %s",
                             sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }
    const SolString *to = SOL_AS_STRING(args[1]);
    const SolString *text = SOL_AS_STRING(self);

    /* Counted before anything is allocated, so the buffer is made once at the
       size it will end up -- the same shape `split` uses, for the same reason. */
    int found = 0;
    for (int at = find_substring(text, from, 0); at >= 0;
         at = find_substring(text, from, at + from->length)) {
        found++;
    }

    /* A string is immutable, so a receiver with nothing to replace *is* the
       answer. No allocation, and `equals` compares contents in any case. */
    if (found == 0) return self;

    /* In a width that cannot wrap: a long replacement over many matches can
       exceed what a length can hold, and a program that asked for that should
       be told rather than handed a truncated string. */
    long long size = (long long)text->length
                   + (long long)found * ((long long)to->length - from->length);
    if (size > INT_MAX) {
        sol_vm_runtime_error(vm, "'replace' would make a string longer than a string can be");
        return SOL_NIL_VAL;
    }

    char *out = malloc((size_t)size + 1);
    if (out == NULL) {
        fprintf(stderr, "solvm: out of memory\n");
        exit(1);
    }

    int written = 0;
    int start = 0;
    for (int i = 0; i < found; i++) {
        int at = find_substring(text, from, start);
        memcpy(out + written, text->chars + start, (size_t)(at - start));
        written += at - start;
        memcpy(out + written, to->chars, (size_t)to->length);
        written += to->length;
        start = at + from->length;
    }
    memcpy(out + written, text->chars + start, (size_t)(text->length - start));
    written += text->length - start;
    out[written] = '\0';

    /* Copies, so the buffer is this function's to free. */
    SolValue answer = SOL_STRING_VAL(sol_string_new(vm, out, written));
    free(out);
    return answer;
}

static SolValue prim_string_split(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "split", argc, 1)) return SOL_NIL_VAL;
    const SolString *separator;
    if (!needle_from(vm, "split", args[0], &separator)) return SOL_NIL_VAL;

    const SolString *text = SOL_AS_STRING(self);

    /* Counted before anything is allocated, so the array is made once at the
       size it will end up. */
    int pieces = 1;
    for (int at = find_substring(text, separator, 0); at >= 0;
         at = find_substring(text, separator, at + separator->length)) {
        pieces++;
    }

    SolArray *out = sol_array_new(vm, pieces);
    /* Every piece is a fresh string, and allocating one may collect. The array
       is reachable from nothing but this local until it is answered, and the
       pieces already in it are reachable only through the array. Filling with
       nil first means the growth happens while nothing new is live. */
    sol_gc_push_temp(vm, &out->gc);
    for (int i = 0; i < pieces; i++) sol_array_add(vm, out, SOL_NIL_VAL);

    /* `self` is on the value stack for the duration of the call, so `text`
       stays rooted while the pieces are cut out of it. */
    int start = 0;
    for (int i = 0; i < pieces; i++) {
        int at  = find_substring(text, separator, start);
        int end = at < 0 ? text->length : at;

        out->items[i] = SOL_STRING_VAL(
            sol_string_new(vm, text->chars + start, end - start));
        start = end + separator->length;
    }

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(out);
}

/* The one-based index where `s` first appears, or nil when it does not.
 *
 * Nil rather than #0. An index of #0 would be an out-of-band value in a
 * language whose indices start at #1, and a second way of saying "nothing"
 * beside the one the language already has. `text:indexOf(","):equals(nil)` is
 * the same question asked of an unset slot or the end of input. */
/* `indexOf(what)` -- where it first appears, one-based, or nil.
 *
 * `indexOf(what, #from)` is the same question asked from a position, and it is
 * here because a *second* search in the same string could not be written
 * without copying what was left of it. lib/pattern.sol's matcher jumps from one
 * candidate to the next and paid a `copyFrom` of the tail at every jump --
 * quadratic in the length of the line, which on an eighty-thousand-character
 * line is 0.14 seconds of copying for one search. programs/expect.sol wrote the
 * same workaround for a different reason, which is two, and two is the number
 * this repository has taken to mean *build it* (see 6.19, 6.23).
 *
 * A second arity rather than a second message, because it is the same question:
 * `at(key)` and `at(key, default)` on a dictionary set the shape, and `run`,
 * `sorted`, `asString` and `random:new` all follow it. The message count does
 * not move.
 *
 * `#from` may be one past the end, where the answer is nil rather than an
 * error -- the same rule `copyFrom` has, and for the same reason: a loop that
 * walks off the end should get an answer rather than a fault. Further out is a
 * mistake and says so.
 */
static SolValue prim_string_index_of(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc != 1 && argc != 2) {
        sol_vm_runtime_error(vm,
            "'indexOf' takes what to look for, or that and where to start, got %d",
            argc);
        return SOL_NIL_VAL;
    }

    const SolString *needle;
    if (!needle_from(vm, "indexOf", args[0], &needle)) return SOL_NIL_VAL;

    const SolString *text = SOL_AS_STRING(self);
    int64_t from = 1;

    if (argc == 2) {
        if (!SOL_IS_INT(args[1])) {
            sol_vm_runtime_error(vm, "'indexOf' expects an integer position, got %s",
                                 sol_type_name(args[1]));
            return SOL_NIL_VAL;
        }
        from = SOL_AS_INT(args[1]);
        if (from < 1 || from > (int64_t)text->length + 1) {
            sol_vm_runtime_error(vm,
                "'indexOf' starts at #%lld, outside a string of size %d",
                (long long)from, text->length);
            return SOL_NIL_VAL;
        }
    }

    int at = find_substring(text, needle, (int)(from - 1));
    return at < 0 ? SOL_NIL_VAL : SOL_INT_VAL(at + 1);
}

/* `copyFrom(#a, #b)` -- the characters from #a to #b, both ends included and
 * both one-based, so `copyFrom(#i, #i)` is exactly `at(#i)`.
 *
 * An empty result has to be sayable, or cutting a string at an index that turns
 * out to be its first character has no answer. It is spelled with `to` one
 * before `from`, and that is the only spelling: anything further apart is a
 * mistake rather than a wider empty. `from` may be one past the end for the
 * same reason -- that is where the empty tail is. */
static SolValue prim_string_copy_from(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "copyFrom", argc, 2)) return SOL_NIL_VAL;
    if (!SOL_IS_INT(args[0]) || !SOL_IS_INT(args[1])) {
        sol_vm_runtime_error(vm, "'copyFrom' expects integer bounds, got %s and %s",
                             sol_type_name(args[0]), sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }

    const SolString *text = SOL_AS_STRING(self);
    int64_t from = SOL_AS_INT(args[0]);
    int64_t to   = SOL_AS_INT(args[1]);

    if (from < 1 || from > (int64_t)text->length + 1) {
        sol_vm_runtime_error(vm, "'copyFrom' starts at #%lld, outside a string of size %d",
                             (long long)from, text->length);
        return SOL_NIL_VAL;
    }
    if (to > (int64_t)text->length) {
        sol_vm_runtime_error(vm, "'copyFrom' ends at #%lld, past a string of size %d",
                             (long long)to, text->length);
        return SOL_NIL_VAL;
    }
    if (to < from - 1) {
        sol_vm_runtime_error(vm,
            "'copyFrom' ends at #%lld, more than one before its start #%lld",
            (long long)to, (long long)from);
        return SOL_NIL_VAL;
    }

    return SOL_STRING_VAL(
        sol_string_new(vm, text->chars + (from - 1), (int)(to - from + 1)));
}

/* ---- dictionary -------------------------------------------------------- *
 *
 * Values kept under keys. `programs/log.sol` is why: counting by key is most of
 * what a log analyser does, and before this the only way to write it was an
 * array of pairs walked from the top, O(n) a lookup.
 *
 * An object could not serve, and it is worth saying why rather than leaving it
 * looking like an oversight. A slot name goes into the VM's *permanent* name
 * table, which outlives every slot and is freed only with the VM -- so a
 * dictionary of keys read from a file would leak a name per key. And slots are
 * a linked list walked linearly, so an object-as-dictionary would not have been
 * faster than the array it replaced. See object.h.
 */

/* Keys are values -- the types `equals` compares by content. A reference is
   compared by identity, so two arrays that look alike are two keys, which is
   the right answer for `equals` and a useless one here. */
static bool key_from(SolVM *vm, const char *name, SolValue key)
{
    if (sol_dict_key_ok(key)) return true;

    sol_vm_runtime_error(vm,
        "'%s' wants a value for a key, got %s -- those are compared by identity, "
        "so two that look alike would be two keys",
        name, sol_type_name(key));
    return false;
}

/* Names the key the way it would be written, so that `"1"` and `#1` and `'1`
   are told apart in the complaint as they are in the table. */
static void missing_key(SolVM *vm, const char *what, SolValue key)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, key, &text);
    sol_vm_runtime_error(vm, "no key %s %s", text.chars, what);
    sol_text_free(&text);
}

static SolValue prim_dict_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args;
    if (!check_argc(vm, "new", argc, 0)) return SOL_NIL_VAL;
    return SOL_DICT_VAL(sol_dict_new(vm));
}

/* `dictionary:of("a", #1, "b", #2)` -- the inline form, and the thing a
 * dictionary literal would be sugar for if one is ever wanted. `array:of` is
 * the same shape and `[...]` compiles to it.
 *
 * Variadic like `array:of`, but not arity-free the way that one is: arguments
 * pair up, so an odd count is a missing value rather than a shorter answer.
 * That is the one mistake this can make and it is caught rather than rounded
 * off -- an entry with no value is a typo every time.
 *
 * Repeating a key takes the last value, which is what repeating `atPut` does.
 * No arguments is an empty dictionary, as no arguments to `array:of` is an
 * empty array. */
static SolValue prim_dict_of(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;

    if (argc % 2 != 0) {
        sol_vm_runtime_error(vm,
            "'of' takes a key and a value for each entry, and got %d argument%s "
            "-- the odd one has no value to go with it",
            argc, argc == 1 ? "" : "s");
        return SOL_NIL_VAL;
    }

    /* No temporary root, and that is checked rather than assumed. The
       arguments are still on the value stack, so they are rooted; the new
       dictionary is not, but nothing between here and the return can collect.
       `sol_dict_put` grows with calloc and free rather than a heap allocation
       -- object.c says so where it does it, "nothing can be collected in the
       middle of the rebuild" -- and `key_from` only formats a message. A root
       here would be two instructions guarding against nothing. */
    SolDict *dict = sol_dict_new(vm);

    for (int i = 0; i < argc; i += 2) {
        if (!key_from(vm, "of", args[i])) return SOL_NIL_VAL;
        sol_dict_put(vm, dict, args[i], args[i + 1]);
    }

    return SOL_DICT_VAL(dict);
}

static SolValue prim_dict_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "size", argc, 0)) return SOL_NIL_VAL;
    return SOL_INT_VAL(SOL_AS_DICT(self)->count);
}

/* `at(key)` is an error when the key is not there, the same answer an
   out-of-range index gets. `at(key, default)` is the form for a lookup that may
   legitimately miss -- and it is the one a counter wants:

       counts:atPut(word, counts:at(word, #0):add(#1)).
 */
static SolValue prim_dict_at(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc != 1 && argc != 2) {
        sol_vm_runtime_error(vm, "'at' takes a key, or a key and a default, got %d",
                             argc);
        return SOL_NIL_VAL;
    }
    if (!key_from(vm, "at", args[0])) return SOL_NIL_VAL;

    SolValue found;
    if (sol_dict_get(SOL_AS_DICT(self), args[0], &found)) return found;
    if (argc == 2) return args[1];

    missing_key(vm, "in the dictionary", args[0]);
    return SOL_NIL_VAL;
}

static SolValue prim_dict_at_put(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "atPut", argc, 2)) return SOL_NIL_VAL;
    if (!key_from(vm, "atPut", args[0])) return SOL_NIL_VAL;

    /* Receiver and both arguments are on the value stack for the duration of
       this call, so they stay rooted while the table grows. */
    sol_dict_put(vm, SOL_AS_DICT(self), args[0], args[1]);
    return args[1];         /* the value stored, as `atPut` on an array does */
}

static SolValue prim_dict_includes(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "includes", argc, 1)) return SOL_NIL_VAL;
    if (!key_from(vm, "includes", args[0])) return SOL_NIL_VAL;

    SolValue found;
    return SOL_BOOL_VAL(sol_dict_get(SOL_AS_DICT(self), args[0], &found));
}

static SolValue prim_dict_remove(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "remove", argc, 1)) return SOL_NIL_VAL;
    if (!key_from(vm, "remove", args[0])) return SOL_NIL_VAL;

    SolValue held;
    if (sol_dict_remove(SOL_AS_DICT(self), args[0], &held)) return held;

    missing_key(vm, "to remove", args[0]);
    return SOL_NIL_VAL;
}

/* `keys` and `values` answer arrays, in the table's order -- which is to say in
   no order worth relying on. Sort them if you want a stable one; log.sol does.
   They are snapshots, so changing the dictionary afterwards does not change
   them. */
static SolValue dict_contents(SolVM *vm, SolValue self, bool want_keys)
{
    const SolDict *dict = SOL_AS_DICT(self);

    SolArray *out = sol_array_new(vm, dict->count);
    sol_gc_push_temp(vm, &out->gc);
    for (int i = 0; i < dict->count; i++) sol_array_add(vm, out, SOL_NIL_VAL);

    int at = 0;
    for (int i = 0; i < dict->capacity && at < dict->count; i++) {
        if (dict->entries[i].state != SOL_DICT_LIVE) continue;
        out->items[at++] = want_keys ? dict->entries[i].key : dict->entries[i].value;
    }

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(out);
}

static SolValue prim_dict_keys(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "keys", argc, 0)) return SOL_NIL_VAL;
    return dict_contents(vm, self, true);
}

static SolValue prim_dict_values(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "values", argc, 0)) return SOL_NIL_VAL;
    return dict_contents(vm, self, false);
}

/* `do` runs the block once per *value*, one argument a call, exactly as an
   array's does -- the same selector should not want a different shape of block
   depending on the receiver. `keysAndValuesDo` is the two-argument form, and it
   is worth having rather than leaving `keys:do` plus `at` to say it, since that
   looks each key up a second time. */
static SolValue dict_iterate(SolVM *vm, SolValue self, SolValue block, bool with_keys)
{
    /* A snapshot, so a block that adds to the dictionary it is walking does not
       rehash the table underneath the walk. An array's `do` re-reads its
       backing store each pass instead; that works because growth there does not
       move an element to a different index, and here it would. */
    SolValue keys = dict_contents(vm, self, true);
    sol_gc_push_temp(vm, &SOL_AS_ARRAY(keys)->gc);

    const SolArray *list = SOL_AS_ARRAY(keys);
    for (int i = 0; i < list->count; i++) {
        SolValue found;
        if (!sol_dict_get(SOL_AS_DICT(self), list->items[i], &found)) {
            continue;                     /* the block removed it on the way */
        }

        SolValue args[2] = { with_keys ? list->items[i] : found, found };
        sol_vm_call_block(vm, block, args, with_keys ? 2 : 1);
        if (vm->had_error) {
            sol_gc_pop_temp(vm);
            return SOL_NIL_VAL;
        }
    }

    sol_gc_pop_temp(vm);
    return self;
}

static SolValue prim_dict_do(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "do", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "do", args[0])) return SOL_NIL_VAL;
    return dict_iterate(vm, self, args[0], false);
}

static SolValue prim_dict_keys_and_values_do(SolVM *vm, SolValue self,
                                             SolValue *args, int argc)
{
    if (!check_argc(vm, "keysAndValuesDo", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "keysAndValuesDo", args[0])) return SOL_NIL_VAL;
    return dict_iterate(vm, self, args[0], true);
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
/* `new` on a class that constructs nothing, which is seven of the ten.
 *
 * The rule is mutability. `new` belongs where something is *made* -- where the
 * instances are references, so there is a fresh, distinct one to hand back.
 * `array:new:equals(array:new)` is false: two arrays. `"":equals("")` is true:
 * one value. A value class has no fresh distinct thing to answer with, so its
 * `new` could only ever hand back the literal spelled longer.
 *
 * `integer` and `float` had exactly that until this commit. `integer:new(#45)`
 * was `return args[0]`, type-checked -- a vestige of the sketch in the original
 * notes, where you built a mutable integer and then `set` it. Numbers became
 * immutable unboxed values, `set` never existed, and `new` outlived the thing it
 * constructed. It is also what let `#45:new(#1)` answer, since a value resolves
 * against its class and the class had a `new` to find.
 *
 * They cannot simply lose it. Every built-in class delegates to `object`, whose
 * `new` answers a fresh object delegating to the receiver -- right for a
 * user-defined class, whose instances *are* objects delegating to it, and wrong
 * for these six. Deleting integer's registration was tried: `integer:new` then
 * answered an object delegating to `integer`, which fails `print`. Worse than
 * the identity function it replaced. So each of the six shadows `new` and says
 * what to write instead: the error is the only thing these classes have to offer
 * here, so it may as well teach.
 *
 * That leaves `new` meaning one thing -- make me a new one -- on the three
 * classes where something is made: `object`, `array` and `dictionary`, all of
 * them mutable, which is the rule. */
static SolValue refuse_new(SolVM *vm, const char *how)
{
    sol_vm_runtime_error(vm, "%s", how);
    return SOL_NIL_VAL;
}

static SolValue prim_integer_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "an integer is written #45, and there is nothing for "
                          "'new' to make -- #0 is the empty one");
}

static SolValue prim_float_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "a float is written 45.0, and there is nothing for "
                          "'new' to make -- 0.0 is the empty one");
}

static SolValue prim_time_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "a time comes from system:time or system:modifiedAt "
                          "-- there is nothing for 'new' to make");
}

static SolValue prim_string_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "a string is written as a literal, not made with 'new' "
                          "-- \"\" is the empty one");
}

/* A foreign handle is made by a primitive and by nothing else: the machine has
   no way to invent a socket, and neither has a program. */
static SolValue prim_foreign_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "a foreign handle comes from an extension and cannot "
                          "be made with 'new' -- see docs/extensions.md");
}

/* `<socket>`, the same text `print` shows, because there is nothing else
   truthful to say about a pointer the machine does not understand. Deliberately
   the rendered form rather than bare characters: a foreign handle has no
   contents to hand over the way a string does. */
static SolValue prim_foreign_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asString", argc, 0)) return SOL_NIL_VAL;

    SolText text;
    sol_text_init(&text);
    sol_value_render(vm, self, &text);
    SolValue answer = SOL_STRING_VAL(sol_string_new(vm, text.chars, text.length));
    sol_text_free(&text);
    return answer;
}

static SolValue prim_symbol_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "a symbol is written 'name, or made from a string with "
                          "asSymbol -- not with 'new'");
}

static SolValue prim_block_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "a block is written { ... } and compiled -- there is "
                          "nothing for 'new' to make");
}

static SolValue prim_boolean_no_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    return refuse_new(vm, "there are only two booleans, true and false -- 'new' "
                          "makes neither");
}

/* ---- time --------------------------------------------------------------- *
 *
 * A point in time, held as nanoseconds since 1970-01-01T00:00:00Z, and a
 * **value** like a number: two of the same instant are the same time, nothing
 * mutates one, and there is no literal for one because there is nothing to
 * write down that a clock or a file does not tell you.
 *
 * **Everything is UTC.** There is no local time and no zone, and that is the
 * decision rather than an omission. A zone is a political fact that changes by
 * legislation, twice a year in most places, and retroactively in some. An
 * instant is unambiguous; a wall-clock reading is not, and a library that
 * blurred the two would be wrong somewhere for reasons no program could see.
 *
 * `system:clock` is still there and is still not this. That one is a stopwatch
 * -- monotonic, unspecified epoch, only differences meaningful -- and this is a
 * calendar. A program that wants to know how long something took wants the
 * first; one that wants to know when it happened wants the second.
 */
#define SOL_NANOS_PER_SECOND 1000000000LL

static bool time_argument(SolVM *vm, const char *name, SolValue value)
{
    if (SOL_IS_TIME(value)) return true;
    sol_vm_runtime_error(vm, "'%s' expects a time, got %s",
                         name, sol_type_name(value));
    return false;
}

/* Splits an instant into calendar parts, in UTC. False when the instant is
   outside what the platform's calendar can express, which int64 nanoseconds
   cannot reach on any system that has a 64-bit `time_t`. */
static bool time_parts(SolVM *vm, const char *name, SolValue value, struct tm *out)
{
    int64_t nanos = SOL_AS_TIME(value);
    /* Floor division, so an instant before the epoch lands on the right second
       rather than one too late -- C division truncates towards zero. */
    int64_t seconds = nanos / SOL_NANOS_PER_SECOND;
    if (nanos % SOL_NANOS_PER_SECOND < 0) seconds--;

    time_t when = (time_t)seconds;
    if (gmtime_r(&when, out) == NULL) {
        sol_vm_runtime_error(vm, "'%s' cannot read a calendar at that instant", name);
        return false;
    }
    return true;
}

static SolValue prim_system_time(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args;
    if (!check_argc(vm, "time", argc, 0)) return SOL_NIL_VAL;

    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) {
        sol_vm_runtime_error(vm, "the calendar clock is unavailable");
        return SOL_NIL_VAL;
    }
    return SOL_TIME_VAL((int64_t)now.tv_sec * SOL_NANOS_PER_SECOND + now.tv_nsec);
}

/* `a:secondsSince(b)` -- a float, as `system:clock` differences are, and named
 * rather than spelled `sub`.
 *
 * `sub` would have answered a different kind of thing from every other `sub` in
 * the language -- a time minus a time is not a time -- and would have invited
 * `t:sub(#5)`, which is a question with two plausible answers. The name says
 * the direction and the unit, which are the two things a bare subtraction
 * leaves you guessing. */
/* Days since 1970-01-01 from a civil date, by Howard Hinnant's algorithm.
 *
 * Written out rather than reached for: `timegm` is the obvious call and is a
 * BSD extension rather than standard C, and `mktime` is the standard one and
 * reads the *local* zone, which is exactly the thing this type does not have.
 * Ten lines of arithmetic is a smaller price than either. Exact for any year
 * the rest of this can express. */
static int64_t days_from_civil(int64_t y, int m, int d)
{
    y -= m <= 2;
    int64_t era = (y >= 0 ? y : y - 399) / 400;
    int64_t yoe = y - era * 400;                        /* 0 to 399 */
    int64_t doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    int64_t doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + doe - 719468;
}

/* Turns calendar parts into an instant, and refuses a date that does not exist.
 *
 * The check is a round trip: convert, split back, and see whether the day came
 * out the way it went in. February the 30th converts to March the 2nd without
 * complaining, and a silently wrong date is worse than a refused one. */
static bool instant_from_parts(SolVM *vm, const char *name, int year, int month,
                               int day, int hour, int minute, int second,
                               int64_t nanos, int64_t offset, int64_t *out)
{
    if (month < 1 || month > 12 || day < 1 || day > 31 ||
        hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
        second < 0 || second > 60) {                    /* 60 for a leap second */
        sol_vm_runtime_error(vm, "'%s' cannot read that as a date", name);
        return false;
    }

    int64_t days = days_from_civil(year, month, day);
    if (days_from_civil(year, month, 1) + (day - 1) != days) {
        sol_vm_runtime_error(vm, "'%s' cannot read that as a date", name);
        return false;
    }
    /* The real check: a day past the end of its month lands in the next one. */
    {
        int64_t back = days;
        int64_t z = back + 719468;
        int64_t era = (z >= 0 ? z : z - 146096) / 146097;
        int64_t doe = z - era * 146097;
        int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        int64_t mp = (5 * doy + 2) / 153;
        int64_t gotDay = doy - (153 * mp + 2) / 5 + 1;
        int64_t gotMonth = mp + (mp < 10 ? 3 : -9);
        if (gotDay != day || gotMonth != month) {
            sol_vm_runtime_error(vm, "'%s' cannot read that as a date", name);
            return false;
        }
    }

    int64_t seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset;
    *out = seconds * SOL_NANOS_PER_SECOND + nanos;
    return true;
}

/* `time:fromSeconds(s)` -- an instant from seconds since the epoch, which is
 * the one way to name a particular moment rather than the current one.
 *
 * Without it `system:time` and `system:modifiedAt` are the only instants a
 * program can have, which is enough to stamp a log and not enough to say when
 * something is due, or to test any of this against a date somebody knows.
 *
 * A float, for the same unit `secondsSince` and `plusSeconds` speak in. An
 * integer is refused as it is everywhere else here -- `#n:asFloat` is the
 * conversion, and being asked for it is the point of being strict. */
/* `"2026-08-20T09:14:02Z":asTime` -- the other direction from `asString`, and
 * on `string` beside `asInteger`, `asFloat` and `asSymbol`, which is where a
 * conversion *from* text has always lived here.
 *
 * A string message living in the time section rather than with the other string
 * primitives, beside the calendar arithmetic it needs -- which is where
 * `timeToRun` sits with respect to the clock, for the same reason.
 *
 * ISO-8601, and a deliberately narrow slice of it:
 *
 *     2026-08-20                     midnight
 *     2026-08-20T09:14:02            T or a space between them
 *     2026-08-20 09:14:02.5          a fraction of a second
 *     2026-08-20T09:14:02Z           explicitly UTC
 *     2026-08-20T09:14:02+01:00      an offset, which is subtracted
 *
 * **No zone means UTC**, because there is no other kind of time here. An
 * *offset* is accepted because an offset is arithmetic -- `+01:00` is an exact
 * number of minutes and says nothing about legislation. A zone *name* is not,
 * and never will be.
 *
 * Strict, as `asInteger` is: the whole string is the timestamp or it is not one.
 * A date that does not exist -- February the 30th -- is refused rather than
 * rolled into March, which is what almost every date parser does quietly.
 */
static bool read_digits(const char **at, int count, int *out)
{
    int value = 0;
    for (int i = 0; i < count; i++) {
        char c = (*at)[i];
        if (c < '0' || c > '9') return false;
        value = value * 10 + (c - '0');
    }
    *at += count;
    *out = value;
    return true;
}

static SolValue prim_string_as_time(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    const SolString *text = SOL_AS_STRING(self);

    /* With a format, the C library reads it -- the same alphabet `asString`
       writes in, so the two are counterparts. */
    if (argc == 1) {
        if (!SOL_IS_STRING(args[0])) {
            sol_vm_runtime_error(vm, "'asTime' expects a format as a string, got %s",
                                 sol_type_name(args[0]));
            return SOL_NIL_VAL;
        }

        struct tm parts;
        memset(&parts, 0, sizeof parts);
        parts.tm_mday = 1;                  /* a format naming no day means the 1st */

        const char *rest = strptime(text->chars, SOL_AS_STRING(args[0])->chars, &parts);
        if (rest == NULL || *rest != '\0') {
            sol_vm_runtime_error(vm, "'%s' does not match that time format",
                                 text->chars);
            return SOL_NIL_VAL;
        }

        int64_t instant;
        if (!instant_from_parts(vm, "asTime", parts.tm_year + 1900, parts.tm_mon + 1,
                                parts.tm_mday, parts.tm_hour, parts.tm_min,
                                parts.tm_sec, 0, 0, &instant)) {
            return SOL_NIL_VAL;
        }
        return SOL_TIME_VAL(instant);
    }
    if (!check_argc(vm, "asTime", argc, 0)) return SOL_NIL_VAL;

    const char *at = text->chars;
    int year, month, day, hour = 0, minute = 0, second = 0;
    int64_t nanos = 0, offset = 0;

    if (!read_digits(&at, 4, &year) || *at++ != '-' ||
        !read_digits(&at, 2, &month) || *at++ != '-' ||
        !read_digits(&at, 2, &day)) {
        sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
        return SOL_NIL_VAL;
    }

    if (*at == 'T' || *at == ' ') {
        at++;
        if (!read_digits(&at, 2, &hour) || *at++ != ':' ||
            !read_digits(&at, 2, &minute) || *at++ != ':' ||
            !read_digits(&at, 2, &second)) {
            sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
            return SOL_NIL_VAL;
        }

        /* A fraction of a second, to as many places as are written. */
        if (*at == '.') {
            at++;
            if (*at < '0' || *at > '9') {
                sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
                return SOL_NIL_VAL;
            }
            int64_t scale = SOL_NANOS_PER_SECOND / 10;
            while (*at >= '0' && *at <= '9') {
                if (scale > 0) { nanos += (*at - '0') * scale; scale /= 10; }
                at++;                       /* past nanoseconds, digits are dropped */
            }
        }
    }

    if (*at == 'Z') {
        at++;
    } else if (*at == '+' || *at == '-') {
        int sign = *at++ == '-' ? -1 : 1;
        int oh, om;
        if (!read_digits(&at, 2, &oh)) {
            sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
            return SOL_NIL_VAL;
        }
        if (*at == ':') at++;
        if (!read_digits(&at, 2, &om)) {
            sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
            return SOL_NIL_VAL;
        }
        if (oh > 23 || om > 59) {
            sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
            return SOL_NIL_VAL;
        }
        offset = sign * (oh * 3600 + om * 60);
    }

    if (*at != '\0') {
        sol_vm_runtime_error(vm, "'%s' is not an ISO-8601 time", text->chars);
        return SOL_NIL_VAL;
    }

    int64_t instant;
    if (!instant_from_parts(vm, "asTime", year, month, day, hour, minute,
                            second, nanos, offset, &instant)) {
        return SOL_NIL_VAL;
    }
    return SOL_TIME_VAL(instant);
}

static SolValue prim_time_from_seconds(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "fromSeconds", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_FLOAT(args[0])) {
        sol_vm_runtime_error(vm, "'fromSeconds' expects a float, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    double seconds = SOL_AS_FLOAT(args[0]);
    if (seconds != seconds || seconds > 9.0e9 || seconds < -9.0e9) {
        sol_vm_runtime_error(vm, "'fromSeconds' cannot reach that instant");
        return SOL_NIL_VAL;
    }

    /* The whole seconds and the fraction separately. Multiplying the whole
       thing by a billion first would push it past 1e18, where a double has
       stopped counting in ones -- an instant in 2026 came back a hundred
       nanoseconds out. Splitting keeps the seconds exact and asks the double
       only for the part it can still hold. */
    double whole = floor(seconds);
    return SOL_TIME_VAL((int64_t)whole * SOL_NANOS_PER_SECOND +
                        (int64_t)llround((seconds - whole) *
                                         (double)SOL_NANOS_PER_SECOND));
}

/* The other direction, so an instant can be written to a file and read back. */
static SolValue prim_time_as_seconds(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "asSeconds", argc, 0)) return SOL_NIL_VAL;

    /* Split for the same reason `fromSeconds` splits: the nanoseconds of a
       present-day instant are past 1e18, and turning that into a double before
       dividing throws away the precision the answer was meant to carry. */
    int64_t nanos = SOL_AS_TIME(self);
    return SOL_FLOAT_VAL((double)(nanos / SOL_NANOS_PER_SECOND) +
                         (double)(nanos % SOL_NANOS_PER_SECOND) /
                         (double)SOL_NANOS_PER_SECOND);
}

static SolValue prim_time_seconds_since(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "secondsSince", argc, 1)) return SOL_NIL_VAL;
    if (!time_argument(vm, "secondsSince", args[0])) return SOL_NIL_VAL;

    /* In floating point, because the answer is a duration and durations are
       what `system:clock` already answers. The difference of two int64
       nanosecond counts cannot overflow a double's precision at any range a
       program will meet. */
    double difference = (double)(SOL_AS_TIME(self) - SOL_AS_TIME(args[0]));
    return SOL_FLOAT_VAL(difference / (double)SOL_NANOS_PER_SECOND);
}

/* `t:plusSeconds(n)` -- another instant, `n` seconds along. A float, so a
   fraction works and so it pairs with `secondsSince`. */
static SolValue prim_time_plus_seconds(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "plusSeconds", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_FLOAT(args[0])) {
        sol_vm_runtime_error(vm, "'plusSeconds' expects a float, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    double seconds = SOL_AS_FLOAT(args[0]);
    if (seconds != seconds || seconds > 9.0e9 || seconds < -9.0e9) {
        sol_vm_runtime_error(vm, "'plusSeconds' cannot move a time that far");
        return SOL_NIL_VAL;
    }
    return SOL_TIME_VAL(SOL_AS_TIME(self) +
                        (int64_t)(seconds * (double)SOL_NANOS_PER_SECOND));
}

static SolValue prim_time_compare(SolVM *vm, SolValue self, SolValue *args,
                                  int argc, const char *name, int wanted, bool orEqual)
{
    if (!check_argc(vm, name, argc, 1)) return SOL_NIL_VAL;
    if (!time_argument(vm, name, args[0])) return SOL_NIL_VAL;

    int64_t a = SOL_AS_TIME(self), b = SOL_AS_TIME(args[0]);
    int order = a < b ? -1 : (a > b ? 1 : 0);
    return SOL_BOOL_VAL(order == wanted || (orEqual && order == 0));
}

static SolValue prim_time_before(SolVM *vm, SolValue self, SolValue *a, int n)
{ return prim_time_compare(vm, self, a, n, "lessThan", -1, false); }
static SolValue prim_time_after(SolVM *vm, SolValue self, SolValue *a, int n)
{ return prim_time_compare(vm, self, a, n, "greaterThan", 1, false); }
static SolValue prim_time_not_after(SolVM *vm, SolValue self, SolValue *a, int n)
{ return prim_time_compare(vm, self, a, n, "lessOrEqual", -1, true); }
static SolValue prim_time_not_before(SolVM *vm, SolValue self, SolValue *a, int n)
{ return prim_time_compare(vm, self, a, n, "greaterOrEqual", 1, true); }

static SolValue time_field(SolVM *vm, SolValue self, int argc,
                           const char *name, int which)
{
    if (!check_argc(vm, name, argc, 0)) return SOL_NIL_VAL;

    struct tm parts;
    if (!time_parts(vm, name, self, &parts)) return SOL_NIL_VAL;

    switch (which) {
    case 0: return SOL_INT_VAL(parts.tm_year + 1900);
    case 1: return SOL_INT_VAL(parts.tm_mon + 1);      /* #1 to #12, not #0 */
    case 2: return SOL_INT_VAL(parts.tm_mday);
    case 3: return SOL_INT_VAL(parts.tm_hour);
    case 4: return SOL_INT_VAL(parts.tm_min);
    case 5: return SOL_INT_VAL(parts.tm_sec);
    /* Monday is #1, following the day names rather than C's Sunday-is-zero. */
    default: return SOL_INT_VAL(parts.tm_wday == 0 ? 7 : parts.tm_wday);
    }
}

static SolValue prim_time_year(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "year", 0); }
static SolValue prim_time_month(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "month", 1); }
static SolValue prim_time_day(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "day", 2); }
static SolValue prim_time_hour(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "hour", 3); }
static SolValue prim_time_minute(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "minute", 4); }
static SolValue prim_time_second(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "second", 5); }
static SolValue prim_time_weekday(SolVM *vm, SolValue s, SolValue *a, int n)
{ (void)a; return time_field(vm, s, n, "weekday", 6); }

/* `t:asString` is the ISO-8601 the renderer gives; `t:asString(spec)` hands the
 * spec to `strftime`, whose alphabet is the one everybody already knows.
 *
 * Not the number-formatting spec language, which is about width and digits and
 * has nothing to say about a Tuesday. Two spec languages is a cost, and the
 * alternative was inventing a third that nobody knows. */
static SolValue prim_time_as_string(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc == 0) {
        SolText text;
        sol_text_init(&text);
        sol_value_render(vm, self, &text);
        SolValue answer = SOL_STRING_VAL(sol_string_new(vm, text.chars, text.length));
        sol_text_free(&text);
        return answer;
    }
    if (!check_argc(vm, "asString", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'asString' expects a format as a string, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    struct tm parts;
    if (!time_parts(vm, "asString", self, &parts)) return SOL_NIL_VAL;

    char buffer[512];
    size_t written = strftime(buffer, sizeof buffer,
                              SOL_AS_STRING(args[0])->chars, &parts);
    if (written == 0 && SOL_AS_STRING(args[0])->length > 0) {
        sol_vm_runtime_error(vm, "that time format is empty or too long");
        return SOL_NIL_VAL;
    }
    return SOL_STRING_VAL(sol_string_new(vm, buffer, (int)written));
}

/* ---- errors ------------------------------------------------------------ *
 *
 * An error is an ordinary object delegating to `error`, with its `message` in a
 * slot. Nothing more: there is no taxonomy of failures here, and inventing one
 * to go with a catch mechanism would be inventing it in the wrong order.
 *
 * A *value* rather than a string, though, and deliberately. This project rewords
 * its errors freely, so if a handler were handed the text and nothing else,
 * matching on it would become the only way to tell failures apart -- an idiom
 * the project's own habits would keep breaking. An object leaves room for a
 * `kind` later without breaking every handler that already exists.
 */
static SolValue error_from(SolVM *vm, const char *message, int length)
{
    SolObject *e = sol_object_new(vm, vm->error_class);
    sol_gc_push_temp(vm, &e->gc);

    SolString *text = sol_string_new(vm, message, length);
    sol_object_define(vm, e, "message", SOL_STRING_VAL(text));

    sol_gc_pop_temp(vm);
    return SOL_OBJ_VAL(e);
}

/* `error:raise("...")` -- the only way to raise one, so re-raising is
 * `error:raise(e:message)`.
 *
 * Two spellings of raising would have been a `new`-shaped mistake: a `raise` on
 * the class taking a string and another on an instance taking nothing is one
 * name meaning two things, which is the trouble this language has already been
 * through once. The cost of having one is that a re-raised error's stack points
 * at where it was re-raised rather than where it first failed, which is honest
 * -- it is a new raise -- and is written down. */
static SolValue prim_error_raise(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "raise", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'raise' expects a string, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    /* Raised errors read exactly like the machine's own: the message is what
       was given, and the stack is where it was given. */
    sol_vm_runtime_error(vm, "%s", SOL_AS_STRING(args[0])->chars);
    return SOL_NIL_VAL;
}

/* `{ ... }:onError({ e | ... })` -- run the receiver, and if it fails, run the
 * handler with the error instead.
 *
 * It catches **everything**, including a message the receiver did not
 * understand because of a typo. That is the deliberate choice and the familiar
 * hazard: a handler wrapped around too much hides mistakes. What makes it
 * bearable is that re-raising is one message -- `error:raise(e:message)` -- so a
 * handler that only means to deal with some failures can pass the rest on.
 *
 * `system:exit` is not caught. It travels by the same flag, being a stop rather
 * than a failure, and a program asking to stop should not be argued with by
 * something that was only watching for errors.
 *
 * Answers what the receiver answered when it did not fail, and what the handler
 * answered when it did -- so it is an expression:
 *
 *     text := { system:readFile(path) }:onError({ e | "" }).
 */
static SolValue prim_block_on_error(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "onError", argc, 1)) return SOL_NIL_VAL;
    /* Before the body runs, not after it fails: a handler that is not a block
       is wrong whether or not anything goes wrong. */
    if (!wants_block(vm, "onError", args[0])) return SOL_NIL_VAL;

    SolValue answer = sol_vm_call_block(vm, self, NULL, 0);
    if (!vm->had_error) return answer;
    if (vm->exiting) return SOL_NIL_VAL;      /* a stop, not a failure */

    /* Nor is a limit, and this one is not the program's to decline. Running the
       handler would be running code after the budget that pays for code ran
       out, and a handler wrapped around everything -- which is the shape people
       write -- would turn the limit into a suggestion. */
    if (vm->stopped) return SOL_NIL_VAL;

    /* Built before the flag is cleared, so nothing can allocate its way into
       another error while the message is still only in the VM's buffer. */
    SolValue caught = error_from(vm, vm->error_message.chars,
                                 vm->error_message.length);

    vm->had_error = false;
    vm->error_message.length = 0;
    vm->error_trace.length = 0;

    return sol_vm_call_block(vm, args[0], &caught, 1);
}

/* `{ body }:ensure({ cleanUp })` -- run the cleanup whether the body finished
 * or not, then go on doing whatever the body was going to do.
 *
 * Answers the body's answer. The cleanup's answer is discarded, because the
 * cleanup is not what the expression is about.
 *
 * The whole difficulty is that a failure has to be **set aside** for the
 * cleanup to run at all. `had_error` is what stops the machine, and the
 * dispatch loop tests it after every instruction -- so a cleanup started with
 * the flag still up would run one instruction and stop. It is lifted out,
 * complete with its message, and put back afterwards.
 *
 * `system:exit` is set aside the same way and for the same reason. It travels
 * by the same flag, and releasing a thing you borrowed is exactly as necessary
 * when a program is stopping as when it is failing -- more so.
 *
 * When both go wrong -- the body failed and the cleanup failed too -- the
 * body's failure is the one that survives. That is the rule everywhere here:
 * the first error wins, and the second is usually a consequence of the first.
 */
static SolValue prim_block_ensure(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (!check_argc(vm, "ensure", argc, 1)) return SOL_NIL_VAL;
    if (!wants_block(vm, "ensure", args[0])) return SOL_NIL_VAL;

    SolValue answer = sol_vm_call_block(vm, self, NULL, 0);

    /* A limit is the one thing the cleanup does not get to run for. Everything
       below works by setting the failure aside so that the cleanup may run --
       and a cleanup is code, which is what there is no longer any budget for.
       A program could otherwise put its work in a cleanup and carry on.
     *
       What that costs is small here, because there is nothing in this language
       that has to be released: a file is read or written whole, and no message
       hands back anything a program is obliged to close. It would cost more in
       a language where there were. */
    if (vm->stopped) return SOL_NIL_VAL;

    if (!vm->had_error) {
        /* Nothing to set aside. A cleanup that fails here fails on its own
           account, with nothing to compete with. */
        sol_vm_call_block(vm, args[0], NULL, 0);
        return vm->had_error ? SOL_NIL_VAL : answer;
    }

    /* Lift the failure out. The texts are moved rather than copied: the VM gets
       fresh empty ones for the duration, so anything the cleanup reports lands
       somewhere else and can be thrown away. */
    SolText  message  = vm->error_message;
    SolText  trace    = vm->error_trace;
    bool     exiting  = vm->exiting;
    int      code     = vm->exit_code;

    sol_text_init(&vm->error_message);
    sol_text_init(&vm->error_trace);
    vm->had_error = false;
    vm->exiting   = false;

    sol_vm_call_block(vm, args[0], NULL, 0);

    /* Whatever the cleanup made of it, the body's failure is what carries on. */
    sol_text_free(&vm->error_message);
    sol_text_free(&vm->error_trace);
    vm->error_message = message;
    vm->error_trace   = trace;
    vm->had_error     = true;
    vm->exiting       = exiting;
    vm->exit_code     = code;

    return SOL_NIL_VAL;
}

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
    return SOL_BOOL_VAL(slot != NULL && sol_slot_accepts(slot, self) &&
                        sol_vm_may_reach(vm, slot, self));
}

/* Whether the receiver delegates to `other`, directly or further up. A value
   answers for the class it dispatches to, so #45:isKindOf(integer) is true. */
/* `isNil` and `notNil`, on every type.
 *
 * `x:equals(nil)` already said this, and said it awkwardly: a test for absence
 * read as a comparison against a value, and the negative form -- which is the
 * common one, since running out of input is how a loop finishes -- read as
 * `x:notEquals(nil)`, three concepts deep to ask one question.
 *
 * Both, rather than `isNil` alone with `not` for the other. The message that
 * actually gets written is the negative one, and `line:isNil:not` is worse than
 * the `notEquals(nil)` it would be replacing -- so a version with only `isNil`
 * would leave the one real use of it no better off than before.
 *
 * They are on every class rather than on nil, because the receiver is exactly
 * what is not known: the point of asking is that the answer might be nil, and a
 * message that only nil understood could not be sent to find out. */
static SolValue prim_is_nil(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "isNil", argc, 0)) return SOL_NIL_VAL;
    return SOL_BOOL_VAL(SOL_IS_NIL(self));
}

static SolValue prim_not_nil(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "notNil", argc, 0)) return SOL_NIL_VAL;
    return SOL_BOOL_VAL(!SOL_IS_NIL(self));
}

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

/* `obj:exports` -- the object's external surface, or nil where it has drawn no
 * boundary. `obj:exports([\'read, \'write])` draws one.
 *
 * The export boundary is the half of a module system that namespacing does not
 * give you. `json` is already a namespace -- one name in the flat space, with
 * `json:read(...)` reaching through it -- but every one of its two dozen working
 * parts is as reachable as its two published ones, and `json:digits := "abc"`
 * from outside breaks the parser.
 *
 * So: from outside, an object that has drawn a boundary *is* its export list.
 * A name off the list can be neither sent nor bound. From inside -- from a frame
 * running with this object as its self -- nothing changes at all, which is what
 * lets `read` go on calling `self:parseValue`.
 *
 * Declared as a list rather than name by name because that is the direction the
 * ratio runs: two published names against two dozen private ones. And the list
 * is kept, not merely stamped onto the slots that exist when it arrives, so
 * that `exports` may be written at the top of a file where a reader will look
 * for it rather than being forced to the bottom.
 *
 * Nothing takes a boundary back down. `exports(nil)` would be a way to do it
 * and is deliberately not offered: a boundary that any caller could lift is a
 * comment about intent rather than a boundary. */
static SolValue prim_exports(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    SolObject *obj;
    if (!reflected_object(vm, "exports", self, &obj)) return SOL_NIL_VAL;

    if (argc == 0) return obj->exports;

    if (argc != 1) {
        sol_vm_runtime_error(vm, "'exports' takes 0 or 1 arguments, got %d", argc);
        return SOL_NIL_VAL;
    }
    if (!SOL_IS_ARRAY(args[0])) {
        sol_vm_runtime_error(vm, "'exports' expects an array of symbols, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    SolArray *list = SOL_AS_ARRAY(args[0]);
    for (int i = 0; i < list->count; i++) {
        if (!SOL_IS_SYMBOL(list->items[i])) {
            sol_vm_runtime_error(vm,
                "'exports' expects an array of symbols, and element #%d is %s",
                i + 1, sol_type_name(list->items[i]));
            return SOL_NIL_VAL;
        }
    }

    /* Drawn from inside only. Otherwise anybody could redraw somebody else's
       boundary, and the first thing they would draw is a wider one. */
    if (!SOL_IS_NIL(obj->exports)) {
        SolValue here = sol_vm_self(vm);
        if (!(SOL_IS_OBJ(here) && SOL_AS_OBJ(here) == obj)) {
            sol_vm_runtime_error(vm,
                "'exports' has already been declared and cannot be redrawn "
                "from outside");
            return SOL_NIL_VAL;
        }
    }

    sol_object_set_exports(obj, args[0]);
    return args[0];
}

/* The names of the object's own slots, in the order they were defined. The list
   is kept newest first, so it is filled backwards.

   From outside an object that has drawn a boundary this answers what it
   exports, and nothing else -- a boundary a reflection walks straight through
   is decorative. */
static SolValue prim_slots(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)args;
    if (!check_argc(vm, "slots", argc, 0)) return SOL_NIL_VAL;
    SolObject *obj;
    if (!reflected_object(vm, "slots", self, &obj)) return SOL_NIL_VAL;

    SolValue here = sol_vm_self(vm);
    bool inside = SOL_IS_OBJ(here) && SOL_AS_OBJ(here) == obj;

    int count = 0;
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        if (inside || slot->exported) count++;
    }

    SolArray *out = sol_array_new(vm, count);
    /* Interning a name allocates, and the array is reachable from nothing but
       this local until it is answered. */
    sol_gc_push_temp(vm, &out->gc);

    for (int i = 0; i < count; i++) sol_array_add(vm, out, SOL_NIL_VAL);

    int i = count - 1;
    for (SolSlot *slot = obj->slots; slot != NULL; slot = slot->next) {
        if (!inside && !slot->exported) continue;
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
    /* Reading a slot without sending to it is still reaching it. */
    if (!sol_vm_may_reach(vm, slot, self)) {
        sol_vm_runtime_error(vm, "'%s' is not exported by %s", selector->chars,
                             sol_type_name(self));
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
/* ---- random: a generator you make, rather than one everybody shares ------ *
 *
 * A random number is **state**, and where that state lives was the whole of
 * 3.14. It lives in an object you make:
 *
 *     r := random:new.              ; seeded by the machine
 *     r := random:new(#20260824).   ; seeded by you, and it repeats
 *     r:upTo(#6):print.
 *
 * Not on `system`, and that is the decision. A generator there would give a VM
 * a history, and two runs of one chunk would stop being identical -- which
 * [embedding.md] promises and this project's own suite relies on. Made this
 * way, a program that never says `random:new` is as deterministic as it ever
 * was, and one that does can say which seed it used and have the run back.
 *
 * The generator is PCG XSH RR 32/64 (O'Neill): 64 bits of state, which is
 * exactly the room an object's payload has, so an instance allocates nothing
 * and the collector has nothing extra to free. Two draws make 64 bits where a
 * bound needs them.
 *
 * **Why this is in the machine at all**, when Lehmer's is eight lines of Solum:
 * because the eight lines are the easy part and every part around them is a
 * trap this language makes worse. Wrapping multiplication is what the textbook
 * generator needs and integer arithmetic here traps on overflow instead. A
 * seed can only come from `system:clock`, and a clock's low bits are not
 * entropy: measured on the generator [bench.sol](../programs/bench.sol)
 * carries, two runs a microsecond apart get consecutive seeds, and the first
 * coin flip is then exactly the parity of the start time, while the first
 * index into 21 takes three values out of 21. And `mod n` on the way out is
 * biased. Each is invisible in the output, which is the same argument that put
 * `sqrt` in the machine and not in a library.
 */
#define SOL_PCG_MULT 6364136223846793005ULL
#define SOL_PCG_INC  1442695040888963407ULL

static uint32_t pcg_step(uint64_t *state)
{
    uint64_t previous = *state;
    *state = previous * SOL_PCG_MULT + SOL_PCG_INC;

    uint32_t xorshifted = (uint32_t)(((previous >> 18u) ^ previous) >> 27u);
    uint32_t rotation   = (uint32_t)(previous >> 59u);
    return (xorshifted >> rotation) | (xorshifted << ((32u - rotation) & 31u));
}

static uint64_t pcg_draw(uint64_t *state)
{
    uint64_t high = pcg_step(state);
    return (high << 32) | pcg_step(state);
}

/* The seeding PCG specifies: a step, the seed added, another step. Handing the
   seed straight to the state would make near seeds start near each other, which
   is the defect measured above rather than a theoretical one. */
static uint64_t pcg_seeded(uint64_t seed)
{
    uint64_t state = 0;
    (void)pcg_step(&state);
    state += seed;
    (void)pcg_step(&state);
    return state;
}

/* An integer in [0, span), with no modulo bias: the low `2^64 mod span` draws
   would be one more likely than the rest, so they are drawn again. */
static uint64_t pcg_below(uint64_t *state, uint64_t span)
{
    uint64_t reject = (0u - span) % span;      /* 2^64 mod span, in one step */
    for (;;) {
        uint64_t drawn = pcg_draw(state);
        if (drawn >= reject) return drawn % span;
    }
}

/* Somewhere to start that is not the clock. `/dev/urandom` rather than
   `getentropy`, which lives in a different header on each system this builds
   on; if it cannot be read the fallback says so by being obviously worse. */
static uint64_t entropy(void)
{
    uint64_t seed = 0;
    FILE *f = fopen("/dev/urandom", "rb");
    if (f != NULL) {
        size_t got = fread(&seed, 1, sizeof seed, f);
        fclose(f);
        if (got == sizeof seed) return seed;
    }

    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) { now.tv_sec = 0; now.tv_nsec = 0; }
    uint64_t here = (uint64_t)(uintptr_t)&now;    /* wherever this frame landed */
    return ((uint64_t)now.tv_sec * 1000000000u + (uint64_t)now.tv_nsec) ^ (here << 16);
}

/* The receiver has to be something `random:new` made. The prototype answering
   these would be one generator shared by everything that reached for it, which
   is the thing this design is arranged to prevent. */
static bool made_random(SolVM *vm, const char *name, SolValue self, uint64_t *state)
{
    if (!SOL_IS_OBJ(self) || SOL_AS_OBJ(self) == vm->random_class) {
        sol_vm_runtime_error(vm,
            "'%s' wants a random of its own -- random:new, or random:new(#seed)",
            name);
        return false;
    }
    *state = (uint64_t)SOL_AS_OBJ(self)->payload;
    return true;
}

static void keep_state(SolValue self, uint64_t state)
{
    SOL_AS_OBJ(self)->payload = (int64_t)state;
}

static SolValue prim_random_new(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc != 0 && argc != 1) {
        sol_vm_runtime_error(vm, "'new' takes a seed, or nothing at all, got %d",
                             argc);
        return SOL_NIL_VAL;
    }
    if (!SOL_IS_OBJ(self)) {
        sol_vm_runtime_error(vm, "'new' expects an object, got %s",
                             sol_type_name(self));
        return SOL_NIL_VAL;
    }
    if (argc == 1 && !SOL_IS_INT(args[0])) {
        sol_vm_runtime_error(vm, "'new' wants the seed as an integer, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    /* Non-negative, so a seed the machine chose reads and types like one a
       person would, and so it survives being printed and handed back. */
    int64_t seed = argc == 1 ? SOL_AS_INT(args[0])
                             : (int64_t)(entropy() >> 1);

    /* `self` is on the value stack for this call; the child is pushed because
       defining its slot allocates. */
    SolObject *made = sol_object_new(vm, SOL_AS_OBJ(self));
    sol_gc_push_temp(vm, &made->gc);
    made->payload = (int64_t)pcg_seeded((uint64_t)seed);

    /* The seed is an ordinary slot, because it is ordinary data: it records
       what this generator was made with so a run can be had again. Assigning to
       it records something untrue rather than reseeding -- there is no message
       that reseeds, since a generator you can restart from the middle is one
       nobody can reason about. */
    sol_object_define(vm, made, "seed", SOL_INT_VAL(seed));
    sol_gc_pop_temp(vm);

    return SOL_OBJ_VAL(made);
}

/* `r:upTo(#n)` -- an integer from 1 to n, which is the range an array is
   indexed by, since that is what asking for a random one of something means
   here. */
static SolValue prim_random_up_to(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    uint64_t state;
    if (!check_argc(vm, "upTo", argc, 1)) return SOL_NIL_VAL;
    if (!made_random(vm, "upTo", self, &state)) return SOL_NIL_VAL;

    if (!SOL_IS_INT(args[0])) {
        sol_vm_runtime_error(vm, "'upTo' wants an integer, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }
    int64_t top = SOL_AS_INT(args[0]);
    if (top < 1) {
        sol_vm_runtime_error(vm, "'upTo' wants at least #1 to choose from, got #%lld",
                             (long long)top);
        return SOL_NIL_VAL;
    }

    uint64_t drawn = pcg_below(&state, (uint64_t)top);
    keep_state(self, state);
    return SOL_INT_VAL((int64_t)drawn + 1);
}

/* `r:between(#a, #b)` -- both ends included, which is the reading that needs no
   footnote and the one `first`/`last` and `copyFrom` already take. */
static SolValue prim_random_between(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    uint64_t state;
    if (!check_argc(vm, "between", argc, 2)) return SOL_NIL_VAL;
    if (!made_random(vm, "between", self, &state)) return SOL_NIL_VAL;

    if (!SOL_IS_INT(args[0]) || !SOL_IS_INT(args[1])) {
        sol_vm_runtime_error(vm, "'between' wants two integers, got %s and %s",
                             sol_type_name(args[0]), sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }
    int64_t low = SOL_AS_INT(args[0]), high = SOL_AS_INT(args[1]);
    if (low > high) {
        sol_vm_runtime_error(vm, "'between' wants the low end first, got #%lld and #%lld",
                             (long long)low, (long long)high);
        return SOL_NIL_VAL;
    }

    /* The whole of int64 is one more than a uint64 can count, and that is the
       one case where every draw is already in range. */
    uint64_t span = (uint64_t)high - (uint64_t)low + 1u;
    uint64_t drawn = span == 0u ? pcg_draw(&state) : pcg_below(&state, span);
    keep_state(self, state);
    return SOL_INT_VAL((int64_t)((uint64_t)low + drawn));
}

/* `r:fraction` -- at least 0.0 and always less than 1.0.
 *
 * Named for what it answers rather than for its type: a message called `float`
 * on something that is not one reads as a conversion of the receiver, which is
 * what `asFloat` means everywhere else here.
 *
 * 53 bits, which is every bit a double can tell apart in [0, 1). The version
 * everyone writes instead -- an integer over its bound -- is coarser than the
 * type and biased on top of it. */
static SolValue prim_random_fraction(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    uint64_t state;
    (void)args;
    if (!check_argc(vm, "fraction", argc, 0)) return SOL_NIL_VAL;
    if (!made_random(vm, "fraction", self, &state)) return SOL_NIL_VAL;

    double answer = (double)(pcg_draw(&state) >> 11) * (1.0 / 9007199254740992.0);
    keep_state(self, state);
    return SOL_FLOAT_VAL(answer);
}

/* ---- system: the process, rather than any value --------------------- */

/* Stopping is a message, and it unwinds rather than leaving from under the
 * machine. Every frame is discarded the way an error discards them, `main`
 * returns normally, and whatever the C library was holding is flushed on the way
 * out. `exit(3)` here would skip all of that, and would make a program's last
 * line of output depend on whether stdout happened to be a terminal.
 *
 * A status is #0 to #255 and anything else is refused rather than masked: POSIX
 * keeps the low eight bits, so `system:exit(#256)` would leave with 0 and look
 * like success -- exactly the quiet mistake the language refuses elsewhere.
 */
static SolValue prim_system_exit(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "exit", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_INT(args[0])) {
        sol_vm_runtime_error(vm, "'exit' expects an integer status, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    int64_t code = SOL_AS_INT(args[0]);
    if (code < 0 || code > 255) {
        sol_vm_runtime_error(vm, "an exit status is #0 to #255, got #%lld",
                             (long long)code);
        return SOL_NIL_VAL;
    }

    vm->exit_code = (int)code;
    vm->exiting = true;
    vm->had_error = true;      /* the flag every loop already tests to unwind */
    return SOL_NIL_VAL;
}

/* Reads one line from standard input, without its terminator, as a fresh
 * string -- or nil at end of input.
 *
 * Nil rather than an error, which is the one place absence is not treated as a
 * mistake here: a loop reading to the end has to be able to tell that it has got
 * there, and running out of input is the normal way for that loop to finish. An
 * empty line is `""` and is not the end, so the two stay distinguishable.
 *
 * `\r\n` is one terminator, so a file written on another system reads the same
 * as one written here. A NUL byte is a byte like any other: the line is taken
 * by length, so this and `readFile` agree about what a string may hold, where
 * the `fgets` this used to be stopped at the first NUL and dropped the rest of
 * the line with it.
 *
 * **It takes from the same window `readKey` does** -- solum/src/stdin.c, and
 * ROADMAP 6.36 for what it was before. Solis' reader takes from it too when it
 * is not editing a line at a terminal, which is what makes *the program and the
 * prompt are reading the same input* true rather than nearly true.
 */
/* `system:readKey` -- one byte from standard input, without waiting for a line.
 *
 * **One byte, not a whole escape sequence.** An arrow key is three bytes and a
 * function key can be more, and which is which is the terminal's business
 * rather than this one's. Answering the byte is the smaller promise and lets a
 * program assemble whatever it wants from them. A one-character string, so
 * `asByte` gives the number and the value is a value like any other.
 *
 * **nil at the end of input**, which is `readLine`'s answer and for the same
 * reason: running out of input is how a loop that reads finishes.
 *
 * **No echo.** Raw mode does not, and a program that wants the key shown can
 * print it. Showing it would be a second thing happening.
 *
 * The terminal handling is in solum/src/stdin.c, along with the window this
 * takes its byte from -- the same one `readLine` takes its line from, which is
 * ROADMAP 6.36 and is why this is four lines now. Raw mode only when standard
 * input is a terminal, and only around a read that has to happen: a byte
 * already held needs no mode at all.
 */
static SolValue prim_system_read_key(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    (void)args;
    if (!check_argc(vm, "readKey", argc, 0)) return SOL_NIL_VAL;

    int byte = sol_stdin_byte_raw();
    if (byte < 0) return SOL_NIL_VAL;          /* the end of input */

    char one = (char)byte;
    return SOL_STRING_VAL(sol_string_new(vm, &one, 1));
}

/* `system:keyWaiting(seconds)` -- whether a byte is there to be read, waiting
 * up to that long for one to arrive.
 *
 * The escape key is why this exists. An arrow arrives as three bytes and the
 * escape key as one, and `readKey` answers a byte and blocks until there is
 * one -- so a program that has just read an escape cannot tell a sequence from
 * a keypress without reading on, and reading on is exactly what it must not do
 * if nothing more is coming. Nothing follows an escape within a few
 * milliseconds except a machine. examples/keys.sol said this was missing on the
 * day `readKey` landed; programs/edit.sol is what made it worth having.
 *
 * **A question, not a second reader.** `readKey(seconds)` answering the byte or
 * nil was the other shape, and nil already means *the end of input* -- which is
 * how every read loop here finishes. Overloading it with *nothing yet* would
 * leave a program unable to tell "there is nobody there" from "they have not
 * typed yet", where the first is final and the second is normal.
 *
 * **True at the end of input**, where the `readKey` after it answers nil: there
 * is something to read, and what is there is the end. True as well when the
 * shared window already holds a byte, which costs nothing to know. The waiting
 * itself, and the terminal mode it needs, are in solum/src/stdin.c.
 *
 * Seconds as a float, like every other duration in this language, and `0.0` is
 * a question about right now.
 */
static SolValue prim_system_key_waiting(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "keyWaiting", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_FLOAT(args[0])) {
        sol_vm_runtime_error(vm, "'keyWaiting' expects a float, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    double seconds = SOL_AS_FLOAT(args[0]);
    /* A negative wait is a mistake rather than a way of asking to wait for
       ever, which `poll` would take it for. nan is refused for the same reason:
       there is no length of time it could mean. */
    if (seconds != seconds || seconds < 0.0) {
        sol_vm_runtime_error(vm, "'keyWaiting' cannot wait for %s seconds",
                             seconds != seconds ? "nan" : "a negative number of");
        return SOL_NIL_VAL;
    }

    double milliseconds = seconds * 1000.0;
    if (milliseconds > 2.0e9) milliseconds = 2.0e9;

    return SOL_BOOL_VAL(sol_stdin_waiting((int)(milliseconds + 0.5)));
}

/* `system:terminalSize` -- how many rows and columns the screen has, or nil
 * when there is not one.
 *
 * programs/edit.sol asked for this, and it is the third thing a full-screen
 * program needs after `readKey` and `write`: an editor cannot draw a screen it
 * cannot measure. Until this existed the only answer was to fork a shell and
 * read `stty size` -- 7ms an ask, measured, against about a microsecond here,
 * which is the difference between measuring once at startup and measuring on
 * every redraw. That difference is the whole of what this buys, and it is why
 * there is no way to be *told* the size changed: at this price a program can
 * ask again every time it draws, and then a resize needs no notification.
 *
 * **One message answering both numbers**, rather than `rows` and `columns`.
 * Two asks straddle a resize, and a program that catches one can compute a
 * screen that never existed -- an old width with a new height. One ask cannot.
 *
 * **A dictionary**, the way `capture` answers `"output"` and `"status"`: an
 * array would be two numbers in an order the reader has to remember, and rows
 * and columns are exactly the pair everybody remembers backwards.
 *
 * **Nil rather than 24 by 80** when the output is not a terminal. A default is
 * a lie a program cannot see through, and what to do instead is the program's
 * decision and not this one's: an editor picks a size, a pager gives up, a
 * report ignores the question. `tput lines` is the counter-example -- it
 * answers the terminfo default down a pipe, confidently and wrongly.
 *
 * **Standard output**, because that is where the drawing goes. A program whose
 * input is a script and whose output is the screen still gets an answer, which
 * is what makes an editor testable; one whose output is a file gets nil, which
 * is the truth about the file.
 */
#if defined(__unix__) || defined(__APPLE__)
#include <sys/ioctl.h>

static SolValue prim_system_terminal_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    (void)args;
    if (!check_argc(vm, "terminalSize", argc, 0)) return SOL_NIL_VAL;

    struct winsize size;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) != 0) return SOL_NIL_VAL;

    /* A terminal that reports nothing is not a terminal to draw on. Some
       pseudo-terminals answer the ioctl with zeroes before anything has been
       attached to them, and a program dividing a screen into zero rows would
       be worse off than one told there is no screen. */
    if (size.ws_row == 0 || size.ws_col == 0) return SOL_NIL_VAL;

    SolDict *answer = sol_dict_new(vm);
    /* Rooted because the two keys are allocated after it and either may
       collect. `sol_dict_put` itself cannot -- it rebuilds with calloc. */
    sol_gc_push_temp(vm, &answer->gc);
    sol_dict_put(vm, answer, SOL_STRING_VAL(sol_string_new(vm, "rows", 4)),
                 SOL_INT_VAL(size.ws_row));
    sol_dict_put(vm, answer, SOL_STRING_VAL(sol_string_new(vm, "columns", 7)),
                 SOL_INT_VAL(size.ws_col));
    sol_gc_pop_temp(vm);
    return SOL_DICT_VAL(answer);
}

#else   /* no ioctl: there is no size to answer, which nil already says */

static SolValue prim_system_terminal_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    (void)args;
    if (!check_argc(vm, "terminalSize", argc, 0)) return SOL_NIL_VAL;
    return SOL_NIL_VAL;
}

#endif

/* `system:write(text)` -- the half of the terminal `readLine` did not have.
 *
 * ROADMAP 3.18. `display` and `print` were the only ways a program had to put
 * text on its own output and both end the line, so a prompt could not sit beside
 * the answer to it, a counter could not be overwritten in place, and a line
 * could not be built from pieces decided as it went. programs/basic.sol met all
 * three at once in one statement: BASIC's INPUT prompts with `?` and reads what
 * is typed after it.
 *
 * On `system` rather than on `string`, which was the one question the entry
 * left. `print`, `display` and `asString` are a trio about *rendering a value* --
 * the literal form, the text, and the text as a value -- and this is not a
 * fourth member of that: it is about a destination. The destination is where
 * `readLine` already lives, and the two are the two halves of one terminal.
 *
 * A string and not any value, so there is no second rendering rule to remember:
 * `system:write(#45:asString)` says which of the two forms it wants. That
 * follows `writeFile`, which is the neighbour it most resembles.
 *
 * Crucially it writes to the same `stdout` the rest of this file writes to.
 * `system:writeFile("/dev/stdout", text)` was the workaround, and it opens a
 * second stream on the same file: when the output is not a terminal the two
 * buffer differently and the prompt overtakes everything printed before it. That
 * failed only when redirected, which is the worst way for it to fail. */
static SolValue prim_system_write(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "write", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'write' expects a string, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    const SolString *text = SOL_AS_STRING(args[0]);
    fwrite(text->chars, 1, (size_t)text->length, stdout);

    /* Flushed, because the whole point is text that is not followed by a
       newline -- and a line-buffered stdout would hold it until one arrived,
       which for a prompt means until after the answer had been read. */
    fflush(stdout);
    return SOL_NIL_VAL;
}

/* `system:writeError(text)` -- the other stream a process has.
 *
 * ROADMAP 3.19. Until this, `display`, `print` and `system:write` all went to
 * standard output and nothing went to standard error, so a program had no way
 * to separate what it produced from what went wrong producing it. The machine
 * had the stream the language did not: `solvm` writes its own diagnostics to
 * stderr and a test holds it to that.
 *
 * programs/basic.sol asked. Run over a `.bas` file it reports a bad listing,
 * and that report was going to standard output -- so redirecting the output
 * captured the error into the file and `2>/dev/null` did not suppress it.
 *
 * Its own message rather than a destination argument on `write`, which was the
 * question the entry left. A destination would make the common case carry an
 * argument it never wants; two names read as the two streams a process has.
 * What is deliberately *not* here is a second `display`: that message and
 * `print` are about rendering a value and serve every type, and a variant of
 * each pointing somewhere else is the second mechanism behind the first that
 * this language exists to refuse.
 *
 * Flushed like its sibling. C leaves stderr unbuffered, so this is belt and
 * braces rather than necessary -- but the whole point of both messages is text
 * that arrives when it is written, and that is worth not depending on. */
static SolValue prim_system_write_error(SolVM *vm, SolValue self, SolValue *args,
                                        int argc)
{
    (void)self;
    if (!check_argc(vm, "writeError", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'writeError' expects a string, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    const SolString *text = SOL_AS_STRING(args[0]);
    fwrite(text->chars, 1, (size_t)text->length, stderr);
    fflush(stderr);
    return SOL_NIL_VAL;
}

static SolValue prim_system_read_line(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    (void)args;
    if (!check_argc(vm, "readLine", argc, 0)) return SOL_NIL_VAL;

    char  *line = NULL;
    size_t length = 0;
    size_t capacity = 0;
    bool   read_anything = false;

    for (;;) {
        if (!sol_stdin_fill()) break;
        read_anything = true;

        size_t available;
        const char *bytes = sol_stdin_window(&available);
        const char *newline = memchr(bytes, '\n', available);
        size_t take = newline != NULL ? (size_t)(newline - bytes) + 1 : available;

        if (length + take + 1 > capacity) {
            size_t want = capacity < 128 ? 128 : capacity;
            while (want < length + take + 1) want *= 2;

            char *grown = realloc(line, want);
            if (grown == NULL) {
                free(line);
                sol_vm_runtime_error(vm, "out of memory reading a line");
                return SOL_NIL_VAL;
            }
            line = grown;
            capacity = want;
        }
        memcpy(line + length, bytes, take);
        length += take;
        line[length] = '\0';

        sol_stdin_take(take);
        if (newline != NULL) break;
    }

    if (!read_anything) {
        free(line);
        return SOL_NIL_VAL;
    }

    if (length > 0 && line[length - 1] == '\n') length--;
    if (length > 0 && line[length - 1] == '\r') length--;

    SolString *text = sol_string_new(vm, line, (int)length);
    free(line);
    return SOL_STRING_VAL(text);
}

/* ---- files ----------------------------------------------------------- */

/* Reading and writing are on `system` rather than on a string, though
 * `"notes.txt":readFile` reads well and was what the roadmap sketched. Two
 * things decided against it. A string does not know anything about files, and
 * putting them there gives every string in the program a message about the
 * filesystem. And `system` is already defined as what belongs to the process
 * rather than to any value, where a file is the world outside.
 *
 * There was a third at the time: an include was spelled `"lib.sol":include`,
 * and `"lib.sol":readFile` beside it would have been two identical-looking
 * sends that were not the same kind of thing at all. An include is
 * `@include "lib.sol"` now and looks like nothing else, so that collision is
 * gone -- but it was never the load-bearing reason.
 *
 * A missing file is an error rather than nil, which is the same answer the rest
 * of the language gives: an out-of-range index is an error, an unset slot is a
 * miss. `readLine` answering nil at the end is not the precedent it looks like
 * -- running out of input is how a loop finishes, where a file that is not there
 * is a program expecting something that is not so. `system:fileExists` is how to
 * ask first.
 */
static bool path_argument(SolVM *vm, const char *name, SolValue value)
{
    if (SOL_IS_STRING(value)) return true;
    sol_vm_runtime_error(vm, "'%s' expects a path as a string, got %s",
                         name, sol_type_name(value));
    return false;
}

/* system:load("lib.sob") -- runs an already-compiled chunk in this machine,
 * sharing the globals with whatever is running now.
 *
 * The run-time twin of `@include`, and it shares its namespace rule: there is
 * one flat globals namespace, the loaded file binds into it, and the caller
 * sees everything it bound. That is the whole of the connection between the two
 * files -- names, resolved at run time, which is why the caller compiles alone
 * and only fails when a name it wanted was never bound.
 *
 * And it is once-only, as `@include` is, keyed the same way: the realpath, so
 * two names for one file are one file. Loading again is not an error and not a
 * second run -- it answers **false** and does nothing, the way `makeDirectory`
 * answers false for a directory already there. That is what lets two files each
 * load what they need without arranging between themselves who loads what, and
 * it is why a cycle ends: the file is written down before it runs, so a file
 * that reaches itself finds itself already there.
 *
 * It shares `@include`'s hazard too, undiluted: nothing is namespaced, so a
 * name bound twice is silently the second one. See ROADMAP 3.10.
 *
 * Loading into a code cell is what makes this safe to return from. The chunk
 * belongs to the collector, and the collector keeps it for exactly as long as a
 * frame is executing it or a block defined in it is still reachable -- so a
 * block this file bound into a global outlives the load, and a file that bound
 * nothing is reclaimed. Freeing the chunk here instead would be ROADMAP 3.6:
 * the globals would hold blocks whose code had gone.
 *
 * There is deliberately no temporary root over the window before that frame
 * exists, and it took removing one to be sure: with the root taken out, the
 * tests pass under ASan and `gc_stress` alike. Nothing in that window can
 * collect. A collection happens where something allocates, `serialize.c` is
 * handed no VM at all and so can allocate nothing the collector knows about --
 * a string constant is chunk-owned bytes until OP_STRING makes a string of it
 * at run time -- and `sol_code_new` collects before it allocates rather than
 * after. Solis roots its submission because *compiling* allocates; loading does
 * not, and a root whose window is empty is a comment that claims a danger. */
static SolValue prim_system_load(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "load", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "load", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;

    /* The identity, before anything is opened: the realpath, so that `lib.sob`,
       `./lib.sob` and the absolute name are one file rather than three. When
       there is no realpath to be had the name stands in for one -- that is a
       file which is about to fail to load, and the load says so better than
       this could. */
    char *identity = realpath(path, NULL);
    if (identity == NULL) {
        identity = malloc(strlen(path) + 1);
        if (identity == NULL) {
            sol_vm_runtime_error(vm, "out of memory loading '%s'", path);
            return SOL_NIL_VAL;
        }
        strcpy(identity, path);
    }

    if (sol_vm_already_loaded(vm, identity)) {
        free(identity);
        return SOL_BOOL_VAL(false);
    }

    SolCode *code = sol_code_new(vm);

    SolSerResult loaded = sol_chunk_load(&code->chunk, path);
    if (loaded != SOL_SER_OK) {
        free(identity);
        sol_vm_runtime_error(vm, "cannot load '%s': %s", path,
                             sol_ser_message(loaded));
        return SOL_NIL_VAL;
    }

    /* A .sob is untrusted input, as serialize.h says: it may have been written
       by something other than solas, and the dispatch loop trusts its operands.
       Verifying is what stands between a malformed file and the machine. */
    SolSerResult sound = sol_chunk_verify(&code->chunk);
    if (sound != SOL_SER_OK) {
        free(identity);
        sol_vm_runtime_error(vm, "'%s' is not usable: %s", path,
                             sol_ser_message(sound));
        return SOL_NIL_VAL;
    }

    /* The loader initialises the chunk it is handed -- serialize.h says so, and
       `solvm` relies on it by passing a raw one -- and initialising clears the
       owner `sol_code_new` had just set. So ownership is established here,
       after the load rather than before it, or every block this file defines
       would carry no owner and the collector would sweep the code out from
       under it. That failure is invisible until a collection happens to land
       between the load and the call: SOLUM_GC_STRESS makes it happen every
       time, which is how it was found. */
    sol_chunk_set_owner(&code->chunk, code);

    /* From here the chunk is rooted by the frame executing it, which is what
       the collector looks at. An earlier draft held a temporary root across
       this call instead: the temporary roots are eight deep and overflowing
       them is a hard exit rather than a failure a program can see, so the ninth
       nested load killed the process outright. */
    /* Written down before it runs, not after, and that is what ends a cycle: a
       file reaching itself -- directly, or round through others -- finds itself
       already listed and does nothing. Recorded only now that it is known to
       load and to verify, so a file that was never usable is not remembered as
       though it had been. */
    sol_vm_remember_loaded(vm, identity);      /* takes ownership */

    SolResult result = sol_vm_call_chunk(vm, &code->chunk);

    /* A failure inside the loaded file has already set the error and its trace,
       and `had_error` is the flag every loop tests -- so saying nothing more is
       what lets it keep unwinding through the caller. `system:exit` arrives
       here the same way and must also be left alone. */
    (void)result;
    return SOL_BOOL_VAL(true);
}

static SolValue prim_system_read_file(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "readFile", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "readFile", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;

    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        sol_vm_runtime_error(vm, "cannot read '%s': %s", path, strerror(errno));
        return SOL_NIL_VAL;
    }

    long size = 0;
    if (fseek(file, 0L, SEEK_END) == 0) size = ftell(file);
    rewind(file);

    if (size < 0 || size > INT_MAX) {
        fclose(file);
        sol_vm_runtime_error(vm, "'%s' is too large to read into a string", path);
        return SOL_NIL_VAL;
    }

    char *buffer = malloc((size_t)size + 1);
    if (buffer == NULL) {
        fclose(file);
        sol_vm_runtime_error(vm, "out of memory reading '%s'", path);
        return SOL_NIL_VAL;
    }

    /* A short read is a failure rather than a shorter string: `fopen` on a
       directory succeeds on some systems, and reading one does not. */
    size_t got = fread(buffer, 1, (size_t)size, file);
    int failed = ferror(file);
    fclose(file);

    if (failed || got != (size_t)size) {
        free(buffer);
        sol_vm_runtime_error(vm, "cannot read '%s': %s", path,
                             failed ? strerror(errno) : "it is not a file");
        return SOL_NIL_VAL;
    }

    SolString *text = sol_string_new(vm, buffer, (int)got);
    free(buffer);
    return SOL_STRING_VAL(text);
}

/* Replaces what is there, and creates the file if it is not. Answers nil: there
   is nothing useful to chain from a write, and the count of bytes written is the
   size of what you already had. */
static SolValue prim_system_write_file(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "writeFile", argc, 2)) return SOL_NIL_VAL;
    if (!path_argument(vm, "writeFile", args[0])) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[1])) {
        sol_vm_runtime_error(vm, "'writeFile' expects a string to write, got %s",
                             sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }

    const char     *path = SOL_AS_STRING(args[0])->chars;
    const SolString *text = SOL_AS_STRING(args[1]);

    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        sol_vm_runtime_error(vm, "cannot write '%s': %s", path, strerror(errno));
        return SOL_NIL_VAL;
    }

    size_t wrote = fwrite(text->chars, 1, (size_t)text->length, file);

    /* Closing is where a buffered write finally fails -- a full disk reports
       itself here and not at the fwrite that filled the buffer. */
    bool ok = (wrote == (size_t)text->length) && (fclose(file) == 0);
    if (!ok) {
        sol_vm_runtime_error(vm, "cannot write '%s': %s", path, strerror(errno));
        return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

/* True for a *file* that is there, which is the question `readFile` asks. A
   directory exists and is not one, and answering true for it would make this a
   trap rather than a way to look before you leap. */
/* `system:isDirectory(path)` -- the other half of `fileExists`, which answers
   false for a directory so that it agrees with what `readFile` would say. Once
   a program can list a directory it needs to tell what it found, so the pair is
   wanted together. */
static SolValue prim_system_is_directory(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "isDirectory", argc, 1)) return SOL_BOOL_VAL(false);
    if (!path_argument(vm, "isDirectory", args[0])) return SOL_BOOL_VAL(false);

    struct stat info;
    if (stat(SOL_AS_STRING(args[0])->chars, &info) != 0) return SOL_BOOL_VAL(false);
    return SOL_BOOL_VAL(S_ISDIR(info.st_mode) ? true : false);
}

/* `system:filesIn(path)` -- what is in a directory, as an array of names.
 *
 * **Names, not paths.** A path would have to choose a separator and would make
 * the answer awkward to show; joining is the caller's, and one `concat` wide.
 *
 * **Everything but `.` and `..`**, directories included. Leaving subdirectories
 * out would make a recursive walk impossible, and `isDirectory` is there to
 * tell them apart.
 *
 * **In whatever order the directory gives them**, which is to say none worth
 * relying on -- the same rule `dictionary:keys` follows, and `sorted` is one
 * message away.
 *
 * A path that is not a directory is an error, as a missing file is to
 * `readFile`: a program asking to walk something that is not a directory is
 * wrong about something. */
static SolValue prim_system_files_in(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "filesIn", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "filesIn", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;
    DIR *dir = opendir(path);
    if (dir == NULL) {
        sol_vm_runtime_error(vm, "cannot list '%s'", path);
        return SOL_NIL_VAL;
    }

    SolArray *out = sol_array_new(vm, 0);
    sol_gc_push_temp(vm, &out->gc);

    /* Each name is a fresh string and the array grows, so both allocate. The
       array is rooted above, and a name is put into it before the next one is
       made. */
    for (struct dirent *entry = readdir(dir); entry != NULL; entry = readdir(dir)) {
        const char *name = entry->d_name;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;

        SolString *text = sol_string_new(vm, name, (int)strlen(name));
        sol_array_add(vm, out, SOL_STRING_VAL(text));
    }
    closedir(dir);

    sol_gc_pop_temp(vm);
    return SOL_ARRAY_VAL(out);
}

/* `system:appendFile(path, text)` -- `writeFile` replaces, and a log wants the
   other one. Creates the file when it is not there, as `writeFile` does. */
static SolValue prim_system_append_file(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "appendFile", argc, 2)) return SOL_NIL_VAL;
    if (!path_argument(vm, "appendFile", args[0])) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[1])) {
        sol_vm_runtime_error(vm, "'appendFile' expects text as a string, got %s",
                             sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }

    const char *path = SOL_AS_STRING(args[0])->chars;
    FILE *f = fopen(path, "ab");
    if (f == NULL) {
        sol_vm_runtime_error(vm, "cannot append to '%s'", path);
        return SOL_NIL_VAL;
    }

    const SolString *text = SOL_AS_STRING(args[1]);
    size_t written = fwrite(text->chars, 1, (size_t)text->length, f);

    /* A buffered write fails when the buffer is flushed, so a full disk
       announces itself at the close rather than at the write that filled it. */
    if (fclose(f) != 0 || written != (size_t)text->length) {
        sol_vm_runtime_error(vm, "cannot append to '%s'", path);
        return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

/* `system:environment(name)` -- the variable, or **nil** when it is not set.
 *
 * Nil rather than an error: a variable that is not set is a legitimate answer
 * to a legitimate question, the way the end of input is. `isNil` asks, and
 * `{ system:environment("HOME") }:onError` would be the wrong shape for
 * something that is not a failure. */
/* ---- running another program -------------------------------------------- *
 *
 * `system:run(["ls", "-l", path])` and `system:capture([...])`, and the shape
 * of those is the decision in them: **an array of arguments, not a string for a
 * shell.**
 *
 * A string handed to `/bin/sh` is the convenient form and the one every
 * scripting language regrets. `"rm " ++ name` is a command until `name` holds a
 * space, and then it is two; a file called `; rm -rf ~` is a sentence the shell
 * reads rather than a name the program passed. Building the argument list means
 * a path with a space in it is one argument because it is one string, and
 * nothing in it is ever read as syntax.
 *
 * The shell is still there and is spelled out when it is wanted:
 *
 *     system:run(["/bin/sh", "-c", "ls | wc -l"]).
 *
 * which says what it is doing. `lib/shell.sol` wraps that for programs that
 * want pipes and globs, so the convenience is a line away and the hazard is
 * named where it is taken rather than hidden in a primitive.
 *
 * A command that cannot be run answers **127**, which is what a shell answers
 * for the same thing, rather than raising: a script asking whether a tool is
 * installed is asking a question, not making a mistake.
 */
#if defined(__unix__) || defined(__APPLE__)
#include <sys/wait.h>
#include <unistd.h>

/* The array, as execvp wants it: NULL-terminated, and every element a string.
   The caller frees the vector; the strings belong to the array's values. */
static char **argv_from(SolVM *vm, const char *name, SolValue value)
{
    if (!SOL_IS_ARRAY(value)) {
        sol_vm_runtime_error(vm, "'%s' expects an array of strings, got %s"
                                 " -- the program and then its arguments",
                             name, sol_type_name(value));
        return NULL;
    }
    const SolArray *array = SOL_AS_ARRAY(value);
    if (array->count == 0) {
        sol_vm_runtime_error(vm, "'%s' wants something to run", name);
        return NULL;
    }

    char **argv = malloc(sizeof(char *) * (size_t)(array->count + 1));
    if (argv == NULL) {
        sol_vm_runtime_error(vm, "out of memory building a command");
        return NULL;
    }

    for (int i = 0; i < array->count; i++) {
        if (!SOL_IS_STRING(array->items[i])) {
            sol_vm_runtime_error(vm,
                "'%s' wants every argument as a string, and #%d is %s", name,
                i + 1, sol_type_name(array->items[i]));
            free(argv);
            return NULL;
        }
        argv[i] = SOL_AS_STRING(array->items[i])->chars;
    }
    argv[array->count] = NULL;
    return argv;
}

/* What waitpid's status means to a script: the exit code, or 128 + the signal
   for a program killed by one, which is the shell's convention and the only
   one anybody recognises. */
static int status_of(int status)
{
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
}

/* ---- where a child's streams go ------------------------------------------ *
 *
 * Both take an optional second argument saying what the child's stdin, stdout
 * and stderr should be: **an array of alternating name and value**, which is
 * the options bag this language can spell. There is an array literal and no
 * dictionary literal, so a dictionary here would cost three statements at every
 * call site to say one thing.
 *
 *     system:run(["make"], ["stderr", 'discard]).
 *     system:capture(argv, ["stderr", 'merge]).
 *     system:run(argv, ["stdout", "build.log", "stderr", 'merge]).
 *
 * The names are the strings `capture` answers with, so a stream is spelled the
 * same going in as coming out. A value is either a **manner, as a symbol** --
 * `'share`, `'discard`, and `'merge` for stderr alone -- or a **path, as a
 * string**. The type is what tells them apart, which is what keeps a file
 * called `discard` a file.
 *
 * Files are opened **before** the fork, so a path that cannot be opened is this
 * program's error to report rather than a child that silently did nothing. They
 * are opened close-on-exec, so the copy `dup2` makes is the only one the child
 * carries -- `dup2` does not pass the flag on, which is the property this rests
 * on.
 */
typedef struct {
    int  fd;        /* what the child gets, or -1 to inherit ours */
    bool merge;     /* stderr only: wherever stdout ends up */
    bool opened;    /* we opened it, so we close it again */
    bool named;     /* the caller mentioned this stream */
} SolStream;

static void close_streams(SolStream *in, SolStream *out, SolStream *err)
{
    SolStream *all[3] = { in, out, err };
    for (int i = 0; i < 3; i++) {
        if (all[i]->opened) close(all[i]->fd);
        all[i]->opened = false;
    }
}

/* In the child, between fork and exec. Nothing here may allocate or fail in a
   way worth reporting: there is nobody left to report to. */
static void child_streams(const SolStream *in, const SolStream *out,
                          const SolStream *err)
{
    if (in->fd  >= 0) dup2(in->fd,  STDIN_FILENO);
    if (out->fd >= 0) dup2(out->fd, STDOUT_FILENO);

    /* After stdout, and that order is the whole of it: `2>&1 >file` sends
       stderr where stdout *was*, `>file 2>&1` where it now is, and the second
       is what `'merge` means. */
    if (err->merge)        dup2(STDOUT_FILENO, STDERR_FILENO);
    else if (err->fd >= 0) dup2(err->fd, STDERR_FILENO);
}

/* One value: a manner as a symbol, or a path as a string. */
static bool stream_value(SolVM *vm, const char *name, const char *which,
                         SolValue value, SolStream *stream)
{
    bool input = strcmp(which, "stdin") == 0;
    bool error_stream = strcmp(which, "stderr") == 0;

    if (SOL_IS_SYMBOL(value)) {
        const char *manner = SOL_AS_SYMBOL(value)->chars;

        if (strcmp(manner, "share") == 0) return true;   /* the default, said */

        if (strcmp(manner, "merge") == 0) {
            if (!error_stream) {
                sol_vm_runtime_error(vm,
                    "'%s' takes 'merge for \"stderr\", which is the stream that"
                    " can follow another", name);
                return false;
            }
            stream->merge = true;
            return true;
        }

        if (strcmp(manner, "discard") == 0) {
            stream->fd = open("/dev/null", (input ? O_RDONLY : O_WRONLY) | O_CLOEXEC);
            if (stream->fd < 0) {
                sol_vm_runtime_error(vm, "cannot discard the child's %s: %s",
                                     which, strerror(errno));
                return false;
            }
            stream->opened = true;
            return true;
        }

        sol_vm_runtime_error(vm,
            "'%s' does not know '%s' for \"%s\" -- a stream takes 'share,"
            " 'discard%s, or a path as a string",
            name, manner, which, error_stream ? ", 'merge" : "");
        return false;
    }

    if (SOL_IS_STRING(value)) {
        const char *path = SOL_AS_STRING(value)->chars;
        stream->fd = input
            ? open(path, O_RDONLY | O_CLOEXEC)
            : open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0666);
        if (stream->fd < 0) {
            sol_vm_runtime_error(vm, "cannot open '%s' for the child's %s: %s",
                                 path, which, strerror(errno));
            return false;
        }
        stream->opened = true;
        return true;
    }

    sol_vm_runtime_error(vm,
        "'%s' wants a manner as a symbol or a path as a string for \"%s\","
        " got %s", name, which, sol_type_name(value));
    return false;
}

/* The whole array. Opens what it has to; closes it again if a later pair is
   wrong, so a refused call leaves no descriptor behind. */
static bool streams_from(SolVM *vm, const char *name, SolValue value,
                         bool capturing,
                         SolStream *in, SolStream *out, SolStream *err)
{
    if (!SOL_IS_ARRAY(value)) {
        sol_vm_runtime_error(vm,
            "'%s' expects the streams as an array of names and values, got %s"
            " -- [\"stderr\", 'discard]", name, sol_type_name(value));
        return false;
    }

    const SolArray *given = SOL_AS_ARRAY(value);
    if (given->count % 2 != 0) {
        sol_vm_runtime_error(vm,
            "'%s' wants a value for every stream named, and got %d of them",
            name, given->count);
        return false;
    }

    for (int i = 0; i < given->count; i += 2) {
        if (!SOL_IS_STRING(given->items[i])) {
            sol_vm_runtime_error(vm,
                "'%s' wants a stream's name as a string, and #%d is %s",
                name, i + 1, sol_type_name(given->items[i]));
            close_streams(in, out, err);
            return false;
        }

        const char *which = SOL_AS_STRING(given->items[i])->chars;
        SolStream  *stream = NULL;
        if      (strcmp(which, "stdin")  == 0) stream = in;
        else if (strcmp(which, "stdout") == 0) stream = out;
        else if (strcmp(which, "stderr") == 0) stream = err;
        else {
            sol_vm_runtime_error(vm,
                "'%s' does not know the stream \"%s\" -- there is \"stdin\","
                " \"stdout\" and \"stderr\"", name, which);
            close_streams(in, out, err);
            return false;
        }

        if (stream->named) {
            sol_vm_runtime_error(vm, "'%s' is given \"%s\" twice", name, which);
            close_streams(in, out, err);
            return false;
        }
        stream->named = true;

        /* `capture` is the message that keeps stdout. Redirecting it would
           leave the answer's "output" with nothing in it and no way to say so,
           which is a worse thing to allow than to refuse. */
        if (capturing && stream == out) {
            sol_vm_runtime_error(vm,
                "'capture' keeps the child's stdout, which is what it is for"
                " -- 'run' is the one that can send it elsewhere");
            close_streams(in, out, err);
            return false;
        }

        if (!stream_value(vm, name, which, given->items[i + 1], stream)) {
            close_streams(in, out, err);
            return false;
        }
    }
    return true;
}

static SolValue prim_system_run(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 && argc != 2) {
        sol_vm_runtime_error(vm,
            "'run' takes a command, or a command and its streams, got %d", argc);
        return SOL_NIL_VAL;
    }

    char **argv = argv_from(vm, "run", args[0]);
    if (argv == NULL) return SOL_NIL_VAL;

    SolStream in = { -1, false, false, false };
    SolStream out = in, err = in;
    if (argc == 2 && !streams_from(vm, "run", args[1], false, &in, &out, &err)) {
        free(argv);
        return SOL_NIL_VAL;
    }

    fflush(stdout);          /* the child shares the terminal; ours goes first */
    fflush(stderr);

    pid_t pid = fork();
    if (pid < 0) {
        const char *what = argv[0];
        free(argv);
        close_streams(&in, &out, &err);
        sol_vm_runtime_error(vm, "cannot run '%s': %s", what, strerror(errno));
        return SOL_NIL_VAL;
    }
    if (pid == 0) {
        child_streams(&in, &out, &err);
        execvp(argv[0], argv);
        _exit(127);          /* not found, or not runnable: the shell's answer */
    }

    close_streams(&in, &out, &err);      /* the child has its own copies now */

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { /* again */ }
    free(argv);
    return SOL_INT_VAL(status_of(status));
}

/* The same, keeping what it wrote. Answers a dictionary rather than the text
   alone, because a script that reads a command's output almost always has to
   know whether it worked -- `grep` finding nothing is not `grep` failing, and
   only the status tells them apart. */
static SolValue prim_system_capture(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 && argc != 2) {
        sol_vm_runtime_error(vm,
            "'capture' takes a command, or a command and its streams, got %d",
            argc);
        return SOL_NIL_VAL;
    }

    char **argv = argv_from(vm, "capture", args[0]);
    if (argv == NULL) return SOL_NIL_VAL;

    SolStream in = { -1, false, false, false };
    SolStream out = in, err = in;
    if (argc == 2 && !streams_from(vm, "capture", args[1], true, &in, &out, &err)) {
        free(argv);
        return SOL_NIL_VAL;
    }

    int fds[2];
    if (pipe(fds) != 0) {
        free(argv);
        close_streams(&in, &out, &err);
        sol_vm_runtime_error(vm, "cannot make a pipe: %s", strerror(errno));
        return SOL_NIL_VAL;
    }

    fflush(stdout);
    fflush(stderr);

    pid_t pid = fork();
    if (pid < 0) {
        close(fds[0]); close(fds[1]); free(argv);
        close_streams(&in, &out, &err);
        sol_vm_runtime_error(vm, "cannot run a command: %s", strerror(errno));
        return SOL_NIL_VAL;
    }
    if (pid == 0) {
        close(fds[0]);
        /* The pipe is this message's stdout, so `'merge` on stderr lands in
           the answer rather than on the terminal -- one rule, and it falls out
           of stdout being where it already is. */
        SolStream piped = { fds[1], false, false, false };
        child_streams(&in, &piped, &err);
        if (fds[1] > STDERR_FILENO) close(fds[1]);
        execvp(argv[0], argv);
        _exit(127);
    }
    close(fds[1]);
    close_streams(&in, &out, &err);

    /* Read to the end before waiting: a child writing more than a pipe holds
       would block forever against a parent waiting for it to finish. */
    char  *text = NULL;
    size_t length = 0, capacity = 0;
    for (;;) {
        if (capacity - length < 4096) {
            size_t want = capacity < 8192 ? 8192 : capacity * 2;
            char *grown = realloc(text, want);
            if (grown == NULL) break;
            text = grown;
            capacity = want;
        }
        ssize_t got = read(fds[0], text + length, capacity - length);
        if (got <= 0) break;
        length += (size_t)got;
    }
    close(fds[0]);

    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) { /* again */ }
    free(argv);

    SolDict *out_dict = sol_dict_new(vm);
    sol_gc_push_temp(vm, &out_dict->gc);

    SolValue output = SOL_STRING_VAL(sol_string_new(vm, text ? text : "", (int)length));
    sol_gc_push_temp(vm, &SOL_AS_STRING(output)->gc);

    sol_dict_put(vm, out_dict, SOL_STRING_VAL(sol_string_new(vm, "output", 6)), output);
    sol_dict_put(vm, out_dict, SOL_STRING_VAL(sol_string_new(vm, "status", 6)),
                 SOL_INT_VAL(status_of(status)));

    sol_gc_pop_temp(vm);
    sol_gc_pop_temp(vm);
    free(text);
    return SOL_DICT_VAL(out_dict);
}

#else   /* no fork here: say so rather than pretending */

static SolValue prim_system_run(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    sol_vm_runtime_error(vm, "'run' needs a system with fork and exec");
    return SOL_NIL_VAL;
}

static SolValue prim_system_capture(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self; (void)args; (void)argc;
    sol_vm_runtime_error(vm, "'capture' needs a system with fork and exec");
    return SOL_NIL_VAL;
}

#endif

static SolValue prim_system_environment(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "environment", argc, 1)) return SOL_NIL_VAL;
    if (!SOL_IS_STRING(args[0])) {
        sol_vm_runtime_error(vm, "'environment' expects a name as a string, got %s",
                             sol_type_name(args[0]));
        return SOL_NIL_VAL;
    }

    const char *value = getenv(SOL_AS_STRING(args[0])->chars);
    if (value == NULL) return SOL_NIL_VAL;
    return SOL_STRING_VAL(sol_string_new(vm, value, (int)strlen(value)));
}

/* `system:fileSize(path)` -- how big, without reading it.
 *
 * `system:readFile(path):size` says the same thing and reads the whole file to
 * do it, which is a poor way to ask about a large one.
 *
 * Size and not the modification time, which is the other thing `stat` knows and
 * the obvious companion. A timestamp wants to be a date rather than a number of
 * seconds, and there is no date here yet -- answering an integer now would be
 * an interface a date type would have to change. */
static SolValue prim_system_file_size(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "fileSize", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "fileSize", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;
    struct stat info;
    if (stat(path, &info) != 0) {
        sol_vm_runtime_error(vm, "cannot measure '%s'", path);
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL((int64_t)info.st_size);
}

/* `system:modifiedAt(path)` -- the companion `fileSize` was waiting for. It
   could not be written until there was a time to answer with. */
static SolValue prim_system_modified_at(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "modifiedAt", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "modifiedAt", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;
    struct stat info;
    if (stat(path, &info) != 0) {
        sol_vm_runtime_error(vm, "cannot read the time of '%s'", path);
        return SOL_NIL_VAL;
    }

    /* The sub-second part, which `st_mtime` does not carry.
     *
     * Throwing it away made this message useless for the job it exists for. A
     * mirroring script asks "is the source newer than the copy?", and with
     * whole seconds the answer is no for anything changed in the same second as
     * the last run -- which is exactly when a script gets run twice. The
     * filesystem records nanoseconds and `time` holds nanoseconds; only this
     * was rounding, in the middle.
     *
     * Two spellings for one thing: POSIX.1-2008 says `st_mtim`, and Apple has
     * `st_mtimespec` and no `st_mtim`. This is the second piece of the runtime
     * that differs by platform, after the prompt's raw mode. */
#if defined(__APPLE__)
    int64_t nanos = (int64_t)info.st_mtimespec.tv_nsec;
#elif defined(st_mtime)     /* POSIX.1-2008 defines this macro beside st_mtim */
    int64_t nanos = (int64_t)info.st_mtim.tv_nsec;
#else
    int64_t nanos = 0;      /* an older Unix: whole seconds, as before */
#endif

    return SOL_TIME_VAL((int64_t)info.st_mtime * SOL_NANOS_PER_SECOND + nanos);
}

/* ---- changing what is there -------------------------------------------- *
 *
 * These three do something that cannot be undone, which is a different sort of
 * message from the ones above and is worth saying out loud. Nothing here asks
 * twice or keeps a copy.
 */

/* `system:remove(path)` -- a file, or an **empty** directory.
 *
 * Both, because C's `remove` does both and the distinction is not one a script
 * wants to make: it knows what it is taking away. A directory with anything in
 * it is refused, and there is deliberately no recursive form -- deleting a tree
 * is not something to make one message wide. A program that means it can walk
 * with `filesIn` and remove what it finds, which at least reads like what it
 * does. */
static SolValue prim_system_remove(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "remove", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "remove", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;
    if (remove(path) != 0) {
        sol_vm_runtime_error(vm, "cannot remove '%s': %s", path, strerror(errno));
        return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

/* `system:makeDirectory(path)` -- one directory, whose parent must be there.
 *
 * One, not the whole path. `mkdir -p` is what a script usually wants and it
 * does more than its name says: asked for `a/b/c` it may leave `a` and `a/b`
 * behind having failed at `c`, which is a poor thing to have happened quietly.
 * Making each level in turn is a loop the program can write and read.
 *
 * A directory that is already there is an error rather than a shrug, which
 * makes `system:isDirectory(p):ifFalse({ system:makeDirectory(p) })` the way to
 * say "make sure of it" -- longer, and it says which of the two you meant. */
/* `system:makeDirectory(path)` -- answers whether it made one.
 *
 * **true** if it did, **false** if a directory was already there, and an error
 * for anything else. It used to refuse the second case, which made "make sure
 * this exists" -- the thing a script wants nine times in ten -- a test and a
 * make, and every script that wrote anywhere carried the same little block.
 *
 * Answering rather than refusing is what puts the fact where a caller can use
 * it *or* ignore it. Refusing did neither well: a caller who wanted to know had
 * to catch the error and read its text, because `mkdir` reports EEXIST for a
 * directory that is already there and for a **file** in the way, and those are
 * not the same news at all. The first is fine and the second never will be.
 *
 * So the file case is separated out and says what it is. One level still, as
 * before: `mkdir -p` is a different message and nothing has asked for it.
 */
static SolValue prim_system_make_directory(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "makeDirectory", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "makeDirectory", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;
    if (mkdir(path, 0777) == 0) return SOL_BOOL_VAL(true);

    if (errno == EEXIST) {
        struct stat info;
        if (stat(path, &info) == 0 && S_ISDIR(info.st_mode)) {
            return SOL_BOOL_VAL(false);        /* already there, which is fine */
        }
        sol_vm_runtime_error(vm,
            "cannot make directory '%s': something that is not a directory is "
            "already there", path);
        return SOL_NIL_VAL;
    }

    sol_vm_runtime_error(vm, "cannot make directory '%s': %s",
                         path, strerror(errno));
    return SOL_NIL_VAL;
}

/* `system:modeOf(path)` -- the permission bits, as an integer.
 *
 * An integer rather than a string, because that is what the mode *is* and the
 * conversions to read it are already here. Solum has no octal literal, so #493
 * is what 0755 looks like written down -- which reads badly enough that the
 * pair to know is `asBase` and `asInteger`:
 *
 *     system:modeOf(path):asBase(#8)      ; "755"
 *     "755":asInteger(#8)                 ; #493
 *
 * A string of nine letters -- "rwxr-xr-x" -- was the alternative, and it is
 * what a person recognises. It was turned down because it would be a second
 * representation of a number, needing its own parser and its own refusals,
 * where `asBase` already crosses that gap for every base.
 *
 * The file-type bits are masked off: what a script wants to copy is the
 * permissions, and handing back the type as well would make `setMode(to,
 * modeOf(from))` a thing that could try to change a file into a directory.
 */
static SolValue prim_system_mode_of(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "modeOf", argc, 1)) return SOL_NIL_VAL;
    if (!path_argument(vm, "modeOf", args[0])) return SOL_NIL_VAL;

    const char *path = SOL_AS_STRING(args[0])->chars;
    struct stat info;
    if (stat(path, &info) != 0) {
        sol_vm_runtime_error(vm, "cannot read the mode of '%s': %s",
                             path, strerror(errno));
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL((int64_t)(info.st_mode & 07777));
}

/* `system:setMode(path, mode)` -- the other direction.
 *
 * The range is checked here rather than left to `chmod`, which on most systems
 * quietly ignores bits it does not know: a mode out of range is a program that
 * has computed one wrongly, and saying so is better than applying most of it.
 */
static SolValue prim_system_set_mode(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "setMode", argc, 2)) return SOL_NIL_VAL;
    if (!path_argument(vm, "setMode", args[0])) return SOL_NIL_VAL;
    if (!SOL_IS_INT(args[1])) {
        sol_vm_runtime_error(vm, "'setMode' expects an integer mode, got %s"
                                 " -- \"755\":asInteger(#8) is one way to write it",
                             sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }

    int64_t mode = SOL_AS_INT(args[1]);
    if (mode < 0 || mode > 07777) {
        sol_vm_runtime_error(vm, "#%lld is not a mode -- 'setMode' wants #0 to #4095",
                             (long long)mode);
        return SOL_NIL_VAL;
    }

    const char *path = SOL_AS_STRING(args[0])->chars;
    if (chmod(path, (mode_t)mode) != 0) {
        sol_vm_runtime_error(vm, "cannot set the mode of '%s': %s",
                             path, strerror(errno));
        return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

/* `system:setModifiedAt(path, time)` -- so that a copy can keep the original's.
 *
 * The pair to `modifiedAt`, and the reason it exists: a copy made by reading
 * and writing is stamped *now*, so a mirroring script comparing times has to
 * ask "newer than" rather than "the same as" -- and then a file replaced with
 * an older copy of itself goes unnoticed. With this, a copy can carry the time
 * across and the comparison can be exact.
 *
 * Only the modification time. The access time is left alone with UTIME_OMIT,
 * because nothing here has wanted it and setting it silently would be a second
 * thing happening.
 */
static SolValue prim_system_set_modified_at(SolVM *vm, SolValue self, SolValue *args,
                                            int argc)
{
    (void)self;
    if (!check_argc(vm, "setModifiedAt", argc, 2)) return SOL_NIL_VAL;
    if (!path_argument(vm, "setModifiedAt", args[0])) return SOL_NIL_VAL;
    if (!SOL_IS_TIME(args[1])) {
        sol_vm_runtime_error(vm, "'setModifiedAt' expects a time, got %s",
                             sol_type_name(args[1]));
        return SOL_NIL_VAL;
    }

    int64_t nanos = SOL_AS_TIME(args[1]);
    struct timespec when;
    when.tv_sec = (time_t)(nanos / SOL_NANOS_PER_SECOND);
    when.tv_nsec = (long)(nanos % SOL_NANOS_PER_SECOND);
    if (when.tv_nsec < 0) {            /* before 1970: floor rather than truncate */
        when.tv_sec -= 1;
        when.tv_nsec += SOL_NANOS_PER_SECOND;
    }

    struct timespec times[2];
    times[0].tv_sec = 0;
    times[0].tv_nsec = UTIME_OMIT;     /* leave the access time alone */
    times[1] = when;

    const char *path = SOL_AS_STRING(args[0])->chars;
    if (utimensat(AT_FDCWD, path, times, 0) != 0) {
        sol_vm_runtime_error(vm, "cannot set the time of '%s': %s",
                             path, strerror(errno));
        return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

/* `system:rename(from, to)` -- moving and renaming being the same operation.
 *
 * Works on a directory as readily as a file. It **replaces** an existing `to`
 * without asking, which is what the system call does and what every `mv`
 * does -- `system:fileExists` is how to look first.
 *
 * It cannot cross a filesystem: there the answer is to read, write, and remove,
 * which is three operations because it is three operations, and the error says
 * so rather than pretending otherwise. */
static SolValue prim_system_rename(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "rename", argc, 2)) return SOL_NIL_VAL;
    if (!path_argument(vm, "rename", args[0])) return SOL_NIL_VAL;
    if (!path_argument(vm, "rename", args[1])) return SOL_NIL_VAL;

    const char *from = SOL_AS_STRING(args[0])->chars;
    const char *to   = SOL_AS_STRING(args[1])->chars;
    if (rename(from, to) != 0) {
        sol_vm_runtime_error(vm, "cannot rename '%s' to '%s': %s",
                             from, to, strerror(errno));
        return SOL_NIL_VAL;
    }
    return SOL_NIL_VAL;
}

static SolValue prim_system_file_exists(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (!check_argc(vm, "fileExists", argc, 1)) return SOL_BOOL_VAL(false);
    if (!path_argument(vm, "fileExists", args[0])) return SOL_BOOL_VAL(false);

    struct stat info;
    if (stat(SOL_AS_STRING(args[0])->chars, &info) != 0) return SOL_BOOL_VAL(false);
    return SOL_BOOL_VAL(S_ISREG(info.st_mode) ? true : false);
}

/* Monotonic seconds as a float. Monotonic because the only thing worth doing
 * with two readings is subtracting them, and a wall clock can go backwards
 * between them -- so the epoch is deliberately unspecified and a single reading
 * means nothing on its own. */
/* Monotonic seconds, or false if the clock is unavailable. The epoch is
   deliberately unspecified: only differences mean anything. */
static bool monotonic_seconds(SolVM *vm, double *out)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        sol_vm_runtime_error(vm, "the monotonic clock is unavailable");
        return false;
    }
    *out = (double)now.tv_sec + (double)now.tv_nsec / 1e9;
    return true;
}

static SolValue prim_system_clock(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    (void)args;
    if (!check_argc(vm, "clock", argc, 0)) return SOL_NIL_VAL;

    double now;
    if (!monotonic_seconds(vm, &now)) return SOL_NIL_VAL;
    return SOL_FLOAT_VAL(now);
}

/* `{ ... }:timeToRun` -- seconds the block took, as a float.
 *
 * A block message living beside the clock it reads rather than with the other
 * block primitives, which is where the thing it does actually is.
 *
 * Seconds as a float, which the roadmap called the obvious choice and is: it is
 * the only answer that needs no duration type, it subtracts and compares like
 * any other number, and `asString(".3")` already formats it.
 *
 * The block's own answer is dropped. What is wanted is the time, and a message
 * that answered both would have to answer an array or an object, which is a
 * worse thing to have to take apart than to write `{ ... }:value` when the
 * answer is wanted too.
 *
 * What is measured is `sol_vm_call_block`, so it includes the cost of the call
 * itself -- a frame pushed and popped. That is honest: it is what running the
 * block costs.
 *
 * `timeToRun(#n)` runs the block n times and answers the total. It is there
 * because the clock has a floor -- a microsecond on the machine this was
 * written on, by `clock_getres` and by watching the smallest step between two
 * readings -- and one run of anything small measures as exactly 0.0. The whole
 * point of the entry that asked for this was to measure what `/usr/bin/time`
 * around a process could not, and every one of those is far under a
 * microsecond, so without a count the message cannot do the job it is for.
 *
 * The total rather than the average, because the total is the measurement and
 * the average is a division the caller can do -- and seeing the total keeps the
 * count in view, which is the number that says whether the floor was cleared. */
static SolValue prim_block_time_to_run(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    int64_t times = 1;
    if (argc == 1) {
        if (!SOL_IS_INT(args[0])) {
            sol_vm_runtime_error(vm, "'timeToRun' expects an integer count, got %s",
                                 sol_type_name(args[0]));
            return SOL_NIL_VAL;
        }
        times = SOL_AS_INT(args[0]);
        if (times < 1) {
            sol_vm_runtime_error(vm, "'timeToRun' needs a count of #1 or more, got #%lld",
                                 (long long)times);
            return SOL_NIL_VAL;
        }
    } else if (argc != 0) {
        sol_vm_runtime_error(vm, "'timeToRun' takes no argument or a count, got %d", argc);
        return SOL_NIL_VAL;
    }

    double start;
    if (!monotonic_seconds(vm, &start)) return SOL_NIL_VAL;

    for (int64_t i = 0; i < times; i++) {
        sol_vm_call_block(vm, self, NULL, 0);
        if (vm->had_error) return SOL_NIL_VAL;    /* including an exit */
    }

    double end;
    if (!monotonic_seconds(vm, &end)) return SOL_NIL_VAL;

    return SOL_FLOAT_VAL(end - start);
}

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
    /* NOTE: class-side and instance-side messages share one object, and the
       line between them is drawn by the receiver each slot requires rather than
       by which object holds it. Every class-side message -- `new`, `of`,
       `fromSeconds`, and the reflection that needs an object to look inside --
       requires SOL_OBJ, so a class answers it and an instance does not.

       That is what keeps `respondsTo` honest -- it answers whether a send would
       find a slot that accepts this receiver, so a slot that accepts everybody
       and then refuses from inside would make it disagree with sending. It is
       also the whole of what splitting the two objects would have bought, which
       is why roadmap 2.5 was closed rather than built. See
       docs/class-and-instance.md.

       Which side each message is on is the half that had to be settled first,
       so that `array:add(#1)` is refused rather than run against an object that
       is not an array. */
    vm->integer_class = sol_object_new(vm, NULL);
    instance(vm, vm->integer_class, SOL_OBJ, "new", prim_integer_no_new);
    instance(vm, vm->integer_class, SOL_INT, "print", prim_print);
    instance(vm, vm->integer_class, SOL_INT, "display", prim_display);
    instance(vm, vm->integer_class, SOL_INT, "add", prim_integer_add);
    instance(vm, vm->integer_class, SOL_INT, "sub", prim_integer_sub);
    instance(vm, vm->integer_class, SOL_INT, "mul", prim_integer_mul);
    instance(vm, vm->integer_class, SOL_INT, "div", prim_integer_div);
    instance(vm, vm->integer_class, SOL_INT, "mod", prim_integer_mod);
    instance(vm, vm->integer_class, SOL_INT, "asFloat", prim_integer_as_float);
    instance(vm, vm->integer_class, SOL_INT, "asBase", prim_integer_as_base);
    instance(vm, vm->integer_class, SOL_INT, "asCharacter", prim_integer_as_character);
    instance(vm, vm->integer_class, SOL_INT, "inc", prim_integer_inc);
    instance(vm, vm->integer_class, SOL_INT, "dec", prim_integer_dec);
    instance(vm, vm->integer_class, SOL_INT, "bitAnd", prim_integer_bit_and);
    instance(vm, vm->integer_class, SOL_INT, "bitOr", prim_integer_bit_or);
    instance(vm, vm->integer_class, SOL_INT, "bitXor", prim_integer_bit_xor);
    instance(vm, vm->integer_class, SOL_INT, "bitNot", prim_integer_bit_not);
    instance(vm, vm->integer_class, SOL_INT, "shiftLeft", prim_integer_shift_left);
    instance(vm, vm->integer_class, SOL_INT, "shiftRight", prim_integer_shift_right);
    instance(vm, vm->integer_class, SOL_INT, "repeat", prim_integer_repeat);
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
    instance(vm, vm->float_class, SOL_OBJ, "new", prim_float_no_new);
    instance(vm, vm->float_class, SOL_FLOAT, "negated", prim_float_negated);
    instance(vm, vm->float_class, SOL_FLOAT, "abs", prim_float_abs);
    instance(vm, vm->float_class, SOL_FLOAT, "sqrt", prim_float_sqrt);
    instance(vm, vm->float_class, SOL_FLOAT, "pow", prim_float_pow);
    instance(vm, vm->float_class, SOL_FLOAT, "exp", prim_float_exp);
    instance(vm, vm->float_class, SOL_FLOAT, "log", prim_float_log);
    instance(vm, vm->float_class, SOL_FLOAT, "sin", prim_float_sin);
    instance(vm, vm->float_class, SOL_FLOAT, "cos", prim_float_cos);
    instance(vm, vm->float_class, SOL_FLOAT, "tan", prim_float_tan);
    instance(vm, vm->float_class, SOL_FLOAT, "asin", prim_float_asin);
    instance(vm, vm->float_class, SOL_FLOAT, "acos", prim_float_acos);
    instance(vm, vm->float_class, SOL_FLOAT, "atan", prim_float_atan);
    instance(vm, vm->float_class, SOL_OBJ, "atan2", prim_float_atan2);
    instance(vm, vm->float_class, SOL_OBJ, "pi", prim_float_pi);
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
    instance(vm, vm->bool_class, SOL_OBJ, "new", prim_boolean_no_new);
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
    instance(vm, vm->block_class, SOL_OBJ, "new", prim_block_no_new);
    instance(vm, vm->block_class, SOL_BLOCK, "print", prim_print);
    instance(vm, vm->block_class, SOL_BLOCK, "display", prim_display);
    instance(vm, vm->block_class, SOL_BLOCK, "equals", prim_equals);
    instance(vm, vm->block_class, SOL_BLOCK, "notEquals", prim_not_equals);
    instance(vm, vm->block_class, SOL_BLOCK, "asString", prim_rendered_as_string);
    instance(vm, vm->block_class, SOL_BLOCK, "value", prim_value);
    instance(vm, vm->block_class, SOL_BLOCK, "timeToRun", prim_block_time_to_run);
    instance(vm, vm->block_class, SOL_BLOCK, "boundTo", prim_bound_to);
    instance(vm, vm->block_class, SOL_BLOCK, "whileTrue", prim_while_true);
    instance(vm, vm->block_class, SOL_BLOCK, "doUntil", prim_do_until);
    instance(vm, vm->block_class, SOL_BLOCK, "repeat", prim_block_repeat);
    instance(vm, vm->block_class, SOL_BLOCK, "onError", prim_block_on_error);
    instance(vm, vm->block_class, SOL_BLOCK, "ensure", prim_block_ensure);

    vm->array_class = sol_object_new(vm, NULL);
    instance(vm, vm->array_class, SOL_OBJ, "new", prim_array_new);
    instance(vm, vm->array_class, SOL_OBJ, "of", prim_array_of);
    instance(vm, vm->array_class, SOL_ARRAY, "size", prim_array_size);
    instance(vm, vm->array_class, SOL_ARRAY, "at", prim_array_at);
    instance(vm, vm->array_class, SOL_ARRAY, "atPut", prim_array_at_put);
    instance(vm, vm->array_class, SOL_ARRAY, "loop", prim_array_loop);
    instance(vm, vm->array_class, SOL_ARRAY, "add", prim_array_add);
    instance(vm, vm->array_class, SOL_ARRAY, "do", prim_array_do);
    instance(vm, vm->array_class, SOL_ARRAY, "collect", prim_array_collect);
    instance(vm, vm->array_class, SOL_ARRAY, "select", prim_array_select);
    instance(vm, vm->array_class, SOL_ARRAY, "inject", prim_array_inject);
    instance(vm, vm->array_class, SOL_ARRAY, "copyFrom", prim_array_copy_from);
    instance(vm, vm->array_class, SOL_ARRAY, "first", prim_array_first);
    instance(vm, vm->array_class, SOL_ARRAY, "last", prim_array_last);
    instance(vm, vm->array_class, SOL_ARRAY, "join", prim_array_join);
    instance(vm, vm->array_class, SOL_ARRAY, "print", prim_print);
    instance(vm, vm->array_class, SOL_ARRAY, "sorted", prim_array_sorted);
    instance(vm, vm->array_class, SOL_ARRAY, "removeLast", prim_array_remove_last);
    instance(vm, vm->array_class, SOL_ARRAY, "indexOf", prim_array_index_of);
    instance(vm, vm->array_class, SOL_ARRAY, "display", prim_display);
    instance(vm, vm->array_class, SOL_ARRAY, "equals", prim_equals);
    instance(vm, vm->array_class, SOL_ARRAY, "notEquals", prim_not_equals);
    instance(vm, vm->array_class, SOL_ARRAY, "asString", prim_rendered_as_string);

    vm->dict_class = sol_object_new(vm, NULL);
    instance(vm, vm->dict_class, SOL_OBJ, "new", prim_dict_new);
    instance(vm, vm->dict_class, SOL_OBJ, "of", prim_dict_of);
    instance(vm, vm->dict_class, SOL_DICT, "size", prim_dict_size);
    instance(vm, vm->dict_class, SOL_DICT, "at", prim_dict_at);
    instance(vm, vm->dict_class, SOL_DICT, "atPut", prim_dict_at_put);
    instance(vm, vm->dict_class, SOL_DICT, "includes", prim_dict_includes);
    instance(vm, vm->dict_class, SOL_DICT, "remove", prim_dict_remove);
    instance(vm, vm->dict_class, SOL_DICT, "keys", prim_dict_keys);
    instance(vm, vm->dict_class, SOL_DICT, "values", prim_dict_values);
    instance(vm, vm->dict_class, SOL_DICT, "do", prim_dict_do);
    instance(vm, vm->dict_class, SOL_DICT, "keysAndValuesDo",
             prim_dict_keys_and_values_do);
    instance(vm, vm->dict_class, SOL_DICT, "print", prim_print);
    instance(vm, vm->dict_class, SOL_DICT, "display", prim_display);
    instance(vm, vm->dict_class, SOL_DICT, "equals", prim_equals);
    instance(vm, vm->dict_class, SOL_DICT, "notEquals", prim_not_equals);
    instance(vm, vm->dict_class, SOL_DICT, "asString", prim_rendered_as_string);

    /* The root of the user-defined side. The built-in classes deliberately do
       not delegate to it: `float` inheriting object's `new` would answer a plain
       object rather than a float. Untangling that is the class-side/instance-side
       question in the roadmap. */
    vm->object_class = sol_object_new(vm, NULL);
    instance(vm, vm->object_class, SOL_OBJ, "new", prim_object_new);

    /* `error` is an ordinary object that errors delegate to, so `e:message` is
       a slot lookup and `e:isKindOf(error)` is true without any new machinery.
       The default is nil rather than absent: a prototype with an optional field
       binds one, and an error made any other way still answers `message`. */
    /* `time` is a class object like `integer`: a value dispatches against it,
       and nothing constructs one, so it has no `new` -- `system:time` and
       `system:modifiedAt` are where an instant comes from. */
    vm->time_class = sol_object_new(vm, NULL);
    instance(vm, vm->time_class, SOL_OBJ, "new", prim_time_no_new);
    instance(vm, vm->time_class, SOL_OBJ, "fromSeconds", prim_time_from_seconds);
    instance(vm, vm->time_class, SOL_TIME, "asSeconds", prim_time_as_seconds);
    instance(vm, vm->time_class, SOL_TIME, "secondsSince", prim_time_seconds_since);
    instance(vm, vm->time_class, SOL_TIME, "plusSeconds", prim_time_plus_seconds);
    instance(vm, vm->time_class, SOL_TIME, "lessThan", prim_time_before);
    instance(vm, vm->time_class, SOL_TIME, "greaterThan", prim_time_after);
    instance(vm, vm->time_class, SOL_TIME, "lessOrEqual", prim_time_not_after);
    instance(vm, vm->time_class, SOL_TIME, "greaterOrEqual", prim_time_not_before);
    instance(vm, vm->time_class, SOL_TIME, "year", prim_time_year);
    instance(vm, vm->time_class, SOL_TIME, "month", prim_time_month);
    instance(vm, vm->time_class, SOL_TIME, "day", prim_time_day);
    instance(vm, vm->time_class, SOL_TIME, "hour", prim_time_hour);
    instance(vm, vm->time_class, SOL_TIME, "minute", prim_time_minute);
    instance(vm, vm->time_class, SOL_TIME, "second", prim_time_second);
    instance(vm, vm->time_class, SOL_TIME, "weekday", prim_time_weekday);
    instance(vm, vm->time_class, SOL_TIME, "asString", prim_time_as_string);
    instance(vm, vm->time_class, SOL_TIME, "print", prim_print);
    instance(vm, vm->time_class, SOL_TIME, "display", prim_display);
    instance(vm, vm->time_class, SOL_TIME, "equals", prim_equals);
    instance(vm, vm->time_class, SOL_TIME, "notEquals", prim_not_equals);

    vm->error_class = sol_object_new(vm, vm->object_class);
    any_receiver(vm, vm->error_class, "raise", prim_error_raise);
    sol_object_define(vm, vm->error_class, "message", SOL_NIL_VAL);
    instance(vm, vm->object_class, SOL_OBJ, "via", prim_object_via);
    instance(vm, vm->object_class, SOL_OBJ, "parent", prim_object_parent);
    instance(vm, vm->object_class, SOL_OBJ, "print", prim_print);
    instance(vm, vm->object_class, SOL_OBJ, "display", prim_display);
    instance(vm, vm->object_class, SOL_OBJ, "equals", prim_equals);
    instance(vm, vm->object_class, SOL_OBJ, "notEquals", prim_not_equals);
    instance(vm, vm->object_class, SOL_OBJ, "asString", prim_object_as_string);

    vm->string_class = sol_object_new(vm, NULL);
    instance(vm, vm->string_class, SOL_OBJ, "new", prim_string_no_new);
    instance(vm, vm->string_class, SOL_STRING, "print", prim_print);
    instance(vm, vm->string_class, SOL_STRING, "display", prim_display);
    instance(vm, vm->string_class, SOL_STRING, "equals", prim_equals);
    instance(vm, vm->string_class, SOL_STRING, "size", prim_string_size);
    instance(vm, vm->string_class, SOL_STRING, "concat", prim_string_concat);
    instance(vm, vm->string_class, SOL_STRING, "at", prim_string_at);
    instance(vm, vm->string_class, SOL_STRING, "split", prim_string_split);
    instance(vm, vm->string_class, SOL_STRING, "indexOf", prim_string_index_of);
    instance(vm, vm->string_class, SOL_STRING, "copyFrom", prim_string_copy_from);
    instance(vm, vm->string_class, SOL_STRING, "fill", prim_string_fill);
    instance(vm, vm->string_class, SOL_STRING, "asString", prim_string_as_string);
    instance(vm, vm->string_class, SOL_STRING, "asInteger", prim_string_as_integer);
    instance(vm, vm->string_class, SOL_STRING, "asFloat", prim_string_as_float);
    instance(vm, vm->string_class, SOL_STRING, "asUppercase", prim_string_upper);
    instance(vm, vm->string_class, SOL_STRING, "asLowercase", prim_string_lower);
    instance(vm, vm->string_class, SOL_STRING, "asSymbol", prim_string_as_symbol);
    instance(vm, vm->string_class, SOL_STRING, "asByte", prim_string_as_byte);
    instance(vm, vm->string_class, SOL_STRING, "trim", prim_string_trim);
    instance(vm, vm->string_class, SOL_STRING, "replace", prim_string_replace);
    instance(vm, vm->string_class, SOL_STRING, "asTime", prim_string_as_time);
    instance(vm, vm->string_class, SOL_STRING, "notEquals", prim_not_equals);
    instance(vm, vm->string_class, SOL_STRING, "lessThan", prim_string_less);
    instance(vm, vm->string_class, SOL_STRING, "greaterThan", prim_string_greater);
    instance(vm, vm->string_class, SOL_STRING, "lessOrEqual", prim_less_or_equal);
    instance(vm, vm->string_class, SOL_STRING, "greaterOrEqual", prim_greater_or_equal);

    /* A resource an extension owns. Five messages and every one of them already
       existed, so the language answers exactly what it did before: a value type
       is not a message. There is no `close` -- the collector releases it when
       the program lets go, and `sol_gc_free_all` releases it at shutdown even
       for a program a limit took away, which is a guarantee an explicit close
       could not make. See docs/extensions.md. */
    vm->foreign_class = sol_object_new(vm, NULL);
    instance(vm, vm->foreign_class, SOL_OBJ, "new", prim_foreign_no_new);
    instance(vm, vm->foreign_class, SOL_FOREIGN, "print", prim_print);
    instance(vm, vm->foreign_class, SOL_FOREIGN, "display", prim_display);
    instance(vm, vm->foreign_class, SOL_FOREIGN, "asString", prim_foreign_as_string);
    instance(vm, vm->foreign_class, SOL_FOREIGN, "equals", prim_equals);
    instance(vm, vm->foreign_class, SOL_FOREIGN, "notEquals", prim_not_equals);

    vm->symbol_class = sol_object_new(vm, NULL);
    instance(vm, vm->symbol_class, SOL_OBJ, "new", prim_symbol_no_new);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "print", prim_print);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "display", prim_display);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "asString", prim_symbol_as_string);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "equals", prim_equals);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "notEquals", prim_not_equals);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "size", prim_symbol_size);
    /* Ordered by text, so an array of symbols sorts -- `sorted` with no block
       sends `lessThan`, so these are what make that work. */
    instance(vm, vm->symbol_class, SOL_SYMBOL, "lessThan", prim_string_less);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "greaterThan", prim_string_greater);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "lessOrEqual", prim_less_or_equal);
    instance(vm, vm->symbol_class, SOL_SYMBOL, "greaterOrEqual", prim_greater_or_equal);

    /* Reflection is the same on every class, and installing it in a loop is not
       just brevity: a message that answers what an object understands is wrong
       the moment one class quietly lacks it. */
    SolObject *classes[] = {
        vm->integer_class, vm->float_class, vm->nil_class,    vm->bool_class,
        vm->block_class,   vm->array_class, vm->object_class, vm->string_class,
        vm->symbol_class,  vm->dict_class,  vm->time_class,
    };
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        any_receiver(vm, classes[i], "perform",    prim_perform);
        any_receiver(vm, classes[i], "respondsTo", prim_responds_to);
        any_receiver(vm, classes[i], "isKindOf",   prim_is_kind_of);
        any_receiver(vm, classes[i], "isNil",      prim_is_nil);
        any_receiver(vm, classes[i], "notNil",     prim_not_nil);
        /* These two want an object to look inside, and say so through the
           receiver requirement rather than from inside the primitive. That is
           what keeps `respondsTo` honest: it answers whether a send would find
           a slot that accepts this receiver, so a slot that accepts everybody
           and then refuses would make it disagree with sending. */
        instance(vm, classes[i], SOL_OBJ, "slots",  prim_slots);
        instance(vm, classes[i], SOL_OBJ, "exports", prim_exports);
        instance(vm, classes[i], SOL_OBJ, "slotAt", prim_slot_at);
    }

    /* One hierarchy. Every built-in class delegates to `object`, so
       `#45:isKindOf(object)` holds and "everything is an object" is true of the
       type graph and not only of the slogan.
     *
       This was thought to need the class-side/instance-side split first, on the
       grounds that a built-in inheriting object's `new` would answer a plain
       object. Two things had already removed that: integer, float and array
       define their own `new` and shadow it, and 1.6's receiver requirements
       refuse `via` and `parent` -- the only two messages a built-in does not
       already define -- to any receiver that is not an object. What was left was
       the four classes with no `new` of their own, and they have one now.

       object itself has no prototype: the chain has to end somewhere, and this
       is where. */
    vm->integer_class->proto = vm->object_class;
    vm->float_class->proto   = vm->object_class;
    vm->nil_class->proto     = vm->object_class;
    vm->bool_class->proto    = vm->object_class;
    vm->block_class->proto   = vm->object_class;
    vm->array_class->proto   = vm->object_class;
    vm->dict_class->proto    = vm->object_class;
    vm->time_class->proto    = vm->object_class;
    vm->string_class->proto  = vm->object_class;
    vm->symbol_class->proto  = vm->object_class;
    vm->foreign_class->proto = vm->object_class;

    /* Bind the class objects into the globals namespace so `integer` resolves. */
    sol_object_define(vm, vm->root, "integer", SOL_OBJ_VAL(vm->integer_class));
    sol_object_define(vm, vm->root, "float",   SOL_OBJ_VAL(vm->float_class));
    sol_object_define(vm, vm->root, "array",   SOL_OBJ_VAL(vm->array_class));
    sol_object_define(vm, vm->root, "dictionary", SOL_OBJ_VAL(vm->dict_class));
    sol_object_define(vm, vm->root, "error",      SOL_OBJ_VAL(vm->error_class));
    sol_object_define(vm, vm->root, "time",       SOL_OBJ_VAL(vm->time_class));
    sol_object_define(vm, vm->root, "string",  SOL_OBJ_VAL(vm->string_class));
    sol_object_define(vm, vm->root, "object",  SOL_OBJ_VAL(vm->object_class));
    /* Now that isKindOf takes a class, the remaining ones need names to be
       asked about. */
    sol_object_define(vm, vm->root, "symbol",  SOL_OBJ_VAL(vm->symbol_class));
    sol_object_define(vm, vm->root, "block",   SOL_OBJ_VAL(vm->block_class));
    /* Named for the same reason: a program handed one by an extension has to
       be able to ask `isKindOf(foreign)`. Nothing else here is useful --
       `foreign:new` exists only to refuse, since a resource comes from an
       extension and cannot be invented. */
    sol_object_define(vm, vm->root, "foreign", SOL_OBJ_VAL(vm->foreign_class));
    sol_object_define(vm, vm->root, "boolean", SOL_OBJ_VAL(vm->bool_class));
    sol_object_define(vm, vm->root, "nil",     SOL_NIL_VAL);
    sol_object_define(vm, vm->root, "true",    SOL_BOOL_VAL(true));
    /* The two floats with no literal form. Naming them makes `infinity` and
       `nan` readable back, which is how a printed float round-trips. */
    sol_object_define(vm, vm->root, "infinity", SOL_FLOAT_VAL(INFINITY));
    sol_object_define(vm, vm->root, "nan",      SOL_FLOAT_VAL(NAN));
    sol_object_define(vm, vm->root, "false",   SOL_BOOL_VAL(false));

    /* `system` is about the process rather than about any value, so it is not a
       class and has no instances -- it is one object with slots, bound to a
       global like everything else. `exit` and `clock` are primitives because
       they do something; `arguments` is a data slot because it is data, and
       sol_vm_set_arguments replaces it when the host has any to give.

       Bound into the globals first and filled in after, so that it is reachable
       while the slots that follow allocate. */
    /* `random` is a prototype rather than a class of a value type: what it
       makes are ordinary objects whose payload is a generator's state. Bound
       into the globals before its slots are defined, so it is reachable while
       they allocate. */
    vm->random_class = sol_object_new(vm, vm->object_class);
    sol_object_define(vm, vm->root, "random", SOL_OBJ_VAL(vm->random_class));
    any_receiver(vm, vm->random_class, "new",      prim_random_new);
    any_receiver(vm, vm->random_class, "upTo",     prim_random_up_to);
    any_receiver(vm, vm->random_class, "between",  prim_random_between);
    any_receiver(vm, vm->random_class, "fraction", prim_random_fraction);

    SolObject *system = sol_object_new(vm, vm->object_class);
    sol_object_define(vm, vm->root, "system", SOL_OBJ_VAL(system));
    any_receiver(vm, system, "exit", prim_system_exit);
    any_receiver(vm, system, "clock", prim_system_clock);
    any_receiver(vm, system, "write", prim_system_write);
    any_receiver(vm, system, "writeError", prim_system_write_error);
    any_receiver(vm, system, "readLine", prim_system_read_line);
    any_receiver(vm, system, "readKey", prim_system_read_key);
    any_receiver(vm, system, "terminalSize", prim_system_terminal_size);
    any_receiver(vm, system, "keyWaiting", prim_system_key_waiting);
    any_receiver(vm, system, "load", prim_system_load);
    any_receiver(vm, system, "readFile", prim_system_read_file);
    any_receiver(vm, system, "writeFile", prim_system_write_file);
    any_receiver(vm, system, "fileExists", prim_system_file_exists);
    any_receiver(vm, system, "isDirectory", prim_system_is_directory);
    any_receiver(vm, system, "filesIn", prim_system_files_in);
    any_receiver(vm, system, "appendFile", prim_system_append_file);
    any_receiver(vm, system, "environment", prim_system_environment);
    any_receiver(vm, system, "run", prim_system_run);
    any_receiver(vm, system, "capture", prim_system_capture);
    any_receiver(vm, system, "fileSize", prim_system_file_size);
    any_receiver(vm, system, "remove", prim_system_remove);
    any_receiver(vm, system, "makeDirectory", prim_system_make_directory);
    any_receiver(vm, system, "rename", prim_system_rename);
    any_receiver(vm, system, "time", prim_system_time);
    any_receiver(vm, system, "modifiedAt", prim_system_modified_at);
    any_receiver(vm, system, "setModifiedAt", prim_system_set_modified_at);
    any_receiver(vm, system, "modeOf", prim_system_mode_of);
    any_receiver(vm, system, "setMode", prim_system_set_mode);

    SolArray *no_arguments = sol_array_new(vm, 0);
    sol_gc_push_temp(vm, &no_arguments->gc);
    sol_object_define(vm, system, "arguments", SOL_ARRAY_VAL(no_arguments));
    sol_gc_pop_temp(vm);
}
