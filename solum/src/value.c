#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/object.h"
#include "solum/value.h"

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
            fprintf(stderr, "solum: out of memory\n");
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

static void render(SolValue value, SolText *out, int depth)
{
    switch (value.type) {
    case SOL_NIL:   sol_text_append(out, "nil", 3); break;
    case SOL_BOOL:
        if (SOL_AS_BOOL(value)) sol_text_append(out, "true", 4);
        else                    sol_text_append(out, "false", 5);
        break;
    case SOL_INT:   append_format(out, "#%lld", (long long)SOL_AS_INT(value)); break;
    case SOL_FLOAT: append_format(out, "%g", SOL_AS_FLOAT(value)); break;
    case SOL_BLOCK: sol_text_append(out, "<block>", 7); break;
    case SOL_DELEGATE: sol_text_append(out, "<delegate>", 10); break;
    case SOL_STRING: {
        /* Rendered as it would be written, the way #45 renders as #45. That also
           keeps a string legible inside an array. */
        const SolString *string = SOL_AS_STRING(value);
        sol_text_append(out, "\"", 1);
        sol_text_append(out, string->chars, string->length);
        sol_text_append(out, "\"", 1);
        break;
    }
    case SOL_ARRAY: {
        const SolArray *array = SOL_AS_ARRAY(value);
        if (depth >= SOL_RENDER_MAX_DEPTH) { sol_text_append(out, "[...]", 5); break; }
        sol_text_append(out, "[", 1);
        for (int i = 0; i < array->count; i++) {
            if (i > 0) sol_text_append(out, ", ", 2);
            render(array->items[i], out, depth + 1);
        }
        sol_text_append(out, "]", 1);
        break;
    }
    case SOL_OBJ:
        /* TODO: send `print` to the object instead of dumping its address.
           Roadmap 5.2 -- much more visible now that user objects exist. */
        append_format(out, "<object %p>", (void *)SOL_AS_OBJ(value));
        break;
    }
}

void sol_value_render(SolValue value, SolText *out)
{
    render(value, out, 0);
}

void sol_value_print(SolValue value)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(value, &text);
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
            fprintf(stderr, "solum: out of memory\n");
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
