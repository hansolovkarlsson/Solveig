#include <stdio.h>
#include <stdlib.h>

#include "solum/value.h"
#include "solum/object.h"

void sol_value_print(SolValue value)
{
    switch (value.type) {
    case SOL_NIL:   printf("nil"); break;
    case SOL_INT:   printf("#%lld", (long long)SOL_AS_INT(value)); break;
    case SOL_FLOAT: printf("%g", SOL_AS_FLOAT(value)); break;
    case SOL_OBJ:
        /* TODO: send `print` to the object instead of dumping its address,
           once dispatch exists. */
        printf("<object %p>", (void *)SOL_AS_OBJ(value));
        break;
    }
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
