/* value.h -- the tagged value representation.
 *
 * Everything in Solum is an object, but numbers are carried unboxed in
 * SolValue so arithmetic does not have to allocate. They are immutable values:
 * `a := #45` binds a name to the integer 45, and nothing can mutate 45 itself.
 *
 * `#45` is an integer; a bare `45` is a float. The `#` is a type tag on the
 * literal, which is why the two need separate tags here.
 */
#ifndef SOLUM_VALUE_H
#define SOLUM_VALUE_H

#include "solum/common.h"

typedef struct SolObject SolObject;
typedef struct SolBlock  SolBlock;
typedef struct SolArray  SolArray;
typedef struct SolString SolString;
typedef struct SolDelegate SolDelegate;

typedef enum {
    SOL_NIL,
    SOL_BOOL,     /* true, false     */
    SOL_INT,      /* #45             */
    SOL_FLOAT,    /* 45              */
    SOL_BLOCK,    /* { ... }         */
    SOL_ARRAY,    /* [#1, #2]        */
    SOL_STRING,   /* "hello"         */
    SOL_DELEGATE, /* self:via(proto) */
    SOL_OBJ
} SolValueType;

typedef struct {
    SolValueType type;
    union {
        bool      boolean;
        int64_t   integer;
        double    real;
        SolBlock  *block;
        SolArray  *array;
        SolString *string;
        SolDelegate *delegate;
        SolObject *obj;
    } as;
} SolValue;

#define SOL_NIL_VAL       ((SolValue){ SOL_NIL,   { .integer = 0 } })
#define SOL_BOOL_VAL(b)   ((SolValue){ SOL_BOOL,  { .boolean = (b) } })
#define SOL_BLOCK_VAL(b)  ((SolValue){ SOL_BLOCK, { .block = (b) } })
#define SOL_ARRAY_VAL(a)  ((SolValue){ SOL_ARRAY, { .array = (a) } })
#define SOL_STRING_VAL(s) ((SolValue){ SOL_STRING, { .string = (s) } })
#define SOL_DELEGATE_VAL(d) ((SolValue){ SOL_DELEGATE, { .delegate = (d) } })
#define SOL_INT_VAL(i)    ((SolValue){ SOL_INT,   { .integer = (i) } })
#define SOL_FLOAT_VAL(f)  ((SolValue){ SOL_FLOAT, { .real = (f) } })
#define SOL_OBJ_VAL(o)    ((SolValue){ SOL_OBJ,   { .obj = (o) } })

#define SOL_IS_NIL(v)     ((v).type == SOL_NIL)
#define SOL_IS_BOOL(v)    ((v).type == SOL_BOOL)
#define SOL_IS_BLOCK(v)   ((v).type == SOL_BLOCK)
#define SOL_IS_ARRAY(v)   ((v).type == SOL_ARRAY)
#define SOL_IS_STRING(v)  ((v).type == SOL_STRING)
#define SOL_IS_DELEGATE(v) ((v).type == SOL_DELEGATE)
#define SOL_IS_INT(v)     ((v).type == SOL_INT)
#define SOL_IS_FLOAT(v)   ((v).type == SOL_FLOAT)
#define SOL_IS_OBJ(v)     ((v).type == SOL_OBJ)

#define SOL_AS_BOOL(v)    ((v).as.boolean)
#define SOL_AS_BLOCK(v)   ((v).as.block)
#define SOL_AS_ARRAY(v)   ((v).as.array)
#define SOL_AS_STRING(v)  ((v).as.string)
#define SOL_AS_DELEGATE(v) ((v).as.delegate)
#define SOL_AS_INT(v)     ((v).as.integer)
#define SOL_AS_FLOAT(v)   ((v).as.real)
#define SOL_AS_OBJ(v)     ((v).as.obj)

/* Writes a human-readable form of `value` to stdout. Used by the `print`
   message and by the disassembler. */
void sol_value_print(SolValue value);

/* Value array -- backing store for a chunk's constant pool. */
typedef struct {
    int      count;
    int      capacity;
    SolValue *values;
} SolValueArray;

void sol_value_array_init(SolValueArray *array);
int  sol_value_array_write(SolValueArray *array, SolValue value); /* returns index */
void sol_value_array_free(SolValueArray *array);

#endif /* SOLUM_VALUE_H */
