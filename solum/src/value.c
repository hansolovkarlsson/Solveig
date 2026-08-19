#include <stdio.h>
#include <stdlib.h>

#include "solum/object.h"
#include "solum/value.h"

/* An array can hold itself -- `a:add(a)` -- so printing is depth-limited rather
   than trusting the structure to be finite. */
#define SOL_PRINT_MAX_DEPTH 4

static void print_value(SolValue value, int depth)
{
    switch (value.type) {
    case SOL_NIL:   printf("nil"); break;
    case SOL_BOOL:  printf(SOL_AS_BOOL(value) ? "true" : "false"); break;
    case SOL_BLOCK: printf("<block>"); break;
    case SOL_INT:   printf("#%lld", (long long)SOL_AS_INT(value)); break;
    case SOL_FLOAT: printf("%g", SOL_AS_FLOAT(value)); break;
    case SOL_STRING: {
        /* Printed as it would be written, the way #45 prints as #45 rather
           than 45. That also keeps a string legible inside an array. */
        const SolString *string = SOL_AS_STRING(value);
        printf("\"%.*s\"", string->length, string->chars);
        break;
    }
    case SOL_ARRAY: {
        const SolArray *array = SOL_AS_ARRAY(value);
        if (depth >= SOL_PRINT_MAX_DEPTH) { printf("[...]"); break; }
        printf("[");
        for (int i = 0; i < array->count; i++) {
            if (i > 0) printf(", ");
            print_value(array->items[i], depth + 1);
        }
        printf("]");
        break;
    }
    case SOL_OBJ:
        /* TODO: send `print` to the object instead of dumping its address,
           once dispatch exists. */
        printf("<object %p>", (void *)SOL_AS_OBJ(value));
        break;
    }
}

void sol_value_print(SolValue value)
{
    print_value(value, 0);
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
