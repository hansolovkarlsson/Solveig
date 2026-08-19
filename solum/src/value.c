#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

/* An array can hold itself -- `a:add(a)` -- so rendering is depth-limited rather
   than trusting the structure to be finite. */
#define SOL_RENDER_MAX_DEPTH 4

void sol_text_init(SolText *text)
{
    text->chars = NULL;
    text->length = 0;
    text->capacity = 0;
}

void sol_text_free(SolText *text)
{
    free(text->chars);
    sol_text_init(text);
}

void sol_text_append(SolText *text, const char *chars, int length)
{
    if (text->capacity < text->length + length + 1) {
        int capacity = text->capacity < 32 ? 32 : text->capacity;
        while (capacity < text->length + length + 1) capacity *= 2;
        text->chars = realloc(text->chars, (size_t)capacity);
        if (text->chars == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        text->capacity = capacity;
    }
    memcpy(text->chars + text->length, chars, (size_t)length);
    text->length += length;
    text->chars[text->length] = '\0';
}

static void append_format(SolText *text, const char *format, ...)
{
    char buffer[64];
    va_list args;
    va_start(args, format);
    int n = vsnprintf(buffer, sizeof buffer, format, args);
    va_end(args);
    if (n < 0) return;
    if (n >= (int)sizeof buffer) n = (int)sizeof buffer - 1;
    sol_text_append(text, buffer, n);
}

/* The shortest decimal that reads back as this exact double.
 *
 * `%g` alone gives six significant digits, which does not merely look rounded --
 * it is a different number. 1234567.0 came out as 1.23457e+06, and asString
 * baked that into a string. Trying increasing precision until the text parses
 * back to the same bits gives `0.1` for a tenth and all seventeen digits only
 * when they are needed.
 *
 * Infinities and not-a-number are written by name. `infinity` and `nan` are
 * globals, so those two read back; `-infinity` does not, having no literal form,
 * and asFloat is the way back for it. */
static void append_float(SolText *text, double d)
{
    if (isnan(d)) { sol_text_append(text, "nan", 3); return; }
    if (isinf(d)) {
        if (d < 0) sol_text_append(text, "-infinity", 9);
        else       sol_text_append(text, "infinity", 8);
        return;
    }

    char buffer[40];
    int precision = 17;
    for (int p = 1; p <= 17; p++) {
        snprintf(buffer, sizeof buffer, "%.*g", p, d);
        if (strtod(buffer, NULL) == d) { precision = p; break; }
    }

    /* Shortest is not always clearest: 1000.0 round-trips at one significant
       digit, which %g then writes as 1e+03. Asking for as many digits as the
       number has whole ones keeps %g in fixed notation where that is readable,
       and more digits can never stop it round-tripping. */
    if (d != 0.0) {
        int magnitude = (int)floor(log10(fabs(d)));
        if (magnitude >= 0 && magnitude < 17 && precision < magnitude + 1) {
            precision = magnitude + 1;
            snprintf(buffer, sizeof buffer, "%.*g", precision, d);
        }
    }
    sol_text_append(text, buffer, (int)strlen(buffer));
}

static void render(SolVM *vm, SolValue value, SolText *out, int depth)
{
    switch (value.type) {
    case SOL_NIL:   sol_text_append(out, "nil", 3); break;
    case SOL_BOOL:
        if (SOL_AS_BOOL(value)) sol_text_append(out, "true", 4);
        else                    sol_text_append(out, "false", 5);
        break;
    case SOL_INT:   append_format(out, "#%lld", (long long)SOL_AS_INT(value)); break;
    case SOL_FLOAT: append_float(out, SOL_AS_FLOAT(value)); break;
    case SOL_BLOCK: sol_text_append(out, "<block>", 7); break;
    case SOL_DELEGATE: sol_text_append(out, "<delegate>", 10); break;
    case SOL_STRING: {
        /* Rendered as it would be written, the way #45 renders as #45 -- which
           means putting the escapes back, or a string holding a quote would
           render as text that no longer reads as one string. `asString` gives
           the characters themselves; this gives the literal. */
        const SolString *string = SOL_AS_STRING(value);
        sol_text_append(out, "\"", 1);
        for (int i = 0; i < string->length; i++) {
            char ch = string->chars[i];
            switch (ch) {
            case '"':  sol_text_append(out, "\\\"", 2); break;
            case '\\': sol_text_append(out, "\\\\", 2); break;
            case '\n': sol_text_append(out, "\\n", 2); break;
            case '\t': sol_text_append(out, "\\t", 2); break;
            case '\r': sol_text_append(out, "\\r", 2); break;
            default:   sol_text_append(out, &ch, 1); break;
            }
        }
        sol_text_append(out, "\"", 1);
        break;
    }
    case SOL_ARRAY: {
        const SolArray *array = SOL_AS_ARRAY(value);
        if (depth >= SOL_RENDER_MAX_DEPTH) { sol_text_append(out, "[...]", 5); break; }
        sol_text_append(out, "[", 1);
        for (int i = 0; i < array->count; i++) {
            if (i > 0) sol_text_append(out, ", ", 2);
            render(vm, array->items[i], out, depth + 1);
        }
        sol_text_append(out, "]", 1);
        break;
    }
    case SOL_OBJ: {
        /* An object is rendered by asking it, so one that defines `asString` is
           shown that way even nested inside an array. The default `asString` on
           `object` writes the address directly rather than calling back here,
           which is what keeps this from recurring forever. */
        if (vm == NULL) {
            append_format(out, "<object %p>", (void *)SOL_AS_OBJ(value));
            break;
        }
        SolValue text = sol_vm_send(vm, value, "asString", NULL, 0);
        if (!SOL_IS_STRING(text)) {
            append_format(out, "<object %p>", (void *)SOL_AS_OBJ(value));
            break;
        }
        sol_text_append(out, SOL_AS_STRING(text)->chars, SOL_AS_STRING(text)->length);
        break;
    }
    }
}

void sol_value_render(SolVM *vm, SolValue value, SolText *out)
{
    render(vm, value, out, 0);
}

void sol_value_print(SolValue value)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(NULL, value, &text);
    fwrite(text.chars, 1, (size_t)text.length, stdout);
    sol_text_free(&text);
}

void sol_value_array_init(SolValueArray *array)
{
    array->count = 0;
    array->capacity = 0;
    array->values = NULL;
}

int sol_value_array_write(SolValueArray *array, SolValue value)
{
    if (array->capacity < array->count + 1) {
        int capacity = array->capacity < 8 ? 8 : array->capacity * 2;
        array->values = realloc(array->values, sizeof(SolValue) * capacity);
        if (array->values == NULL) {
            fprintf(stderr, "solvm: out of memory\n");
            exit(1);
        }
        array->capacity = capacity;
    }
    array->values[array->count] = value;
    return array->count++;
}

void sol_value_array_free(SolValueArray *array)
{
    free(array->values);
    sol_value_array_init(array);
}
