/* test_reader.c -- what the header declares, and what the body then means.
 *
 * The assertions are on the *emitted Solveig*, not on the tree, and that is
 * deliberate. A tree assertion says the parser built what this file expected;
 * the emitted text says what Solveig will be told, which is the only thing a
 * program's behaviour depends on. The Makefile then runs the examples through
 * the real `solas` and `solvm`, which is the half no unit test can do. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "proto/emit.h"
#include "proto/reader.h"
#include "proto/unit.h"

static int failures = 0;
static int checks = 0;

/* Compiles `text` and answers the generated Solveig, or NULL if it did not
   compile. The caller frees. */
static char *compile(const char *text, int *errors)
{
    ProtoUnit unit;
    proto_unit_init(&unit);

    const ProtoSource *source = proto_unit_adopt(&unit, "<test>", text);

    FILE *sink = tmpfile();
    ProtoDiagnostics diag;
    proto_diag_init(&diag, sink);

    ProtoDialect dialect;
    proto_dialect_init(&dialect);

    ProtoNode *module = proto_read(source, &unit, &dialect, &diag);
    *errors = diag.errors;

    char *out = NULL;
    if (module != NULL) {
        ProtoEmitter emitter;
        proto_emitter_init(&emitter);
        proto_emit(&emitter, module);
        /* Past the generated banner, which is not what any of this is about. */
        const char *body = strstr(emitter.text, "\n\n");
        out = proto_strndup(body + 2, strlen(body + 2));
        proto_emitter_free(&emitter);
        proto_node_free(module);
    }

    proto_dialect_free(&dialect);
    proto_unit_free(&unit);
    fclose(sink);
    return out;
}

static void expect(const char *label, const char *text, const char *want)
{
    checks++;
    int errors = 0;
    char *got = compile(text, &errors);

    if (got == NULL) {
        printf("  FAIL %s: did not compile (%d error%s)\n",
               label, errors, errors == 1 ? "" : "s");
        failures++;
        return;
    }
    if (strcmp(got, want) != 0) {
        printf("  FAIL %s\n    want: %s    got:  %s", label, want, got);
        failures++;
    }
    free(got);
}

static void expect_rejected(const char *label, const char *text)
{
    checks++;
    int errors = 0;
    char *got = compile(text, &errors);
    if (got != NULL) {
        printf("  FAIL %s: compiled, and should not have\n    got:  %s",
               label, got);
        failures++;
        free(got);
        return;
    }
    if (errors < 1) {
        printf("  FAIL %s: rejected without saying why\n", label);
        failures++;
    }
}

#define HEADER \
    "@language solveig.\n" \
    "@infix + 60 add.\n" \
    "@infix - 60 sub.\n" \
    "@infix * 70 mul.\n" \
    "@infixr ^ 80 raise.\n" \
    "@prefix ~ not.\n"

int main(void)
{
    /* The ladder is the module's, and nothing is built in: `*` binds tighter
       than `+` only because the header said 70 against 60. */
    expect("precedence",       HEADER "a := #2 + #3 * #4.\n",
           "a := #2:add(#3:mul(#4)).\n");
    expect("precedence, other way", HEADER "a := #2 * #3 + #4.\n",
           "a := #2:mul(#3):add(#4).\n");
    expect("left associativity", HEADER "a := #1 - #2 - #3.\n",
           "a := #1:sub(#2):sub(#3).\n");
    expect("right associativity", HEADER "a := #1 ^ #2 ^ #3.\n",
           "a := #1:raise(#2:raise(#3)).\n");
    expect("parentheses beat precedence", HEADER "a := (#2 + #3) * #4.\n",
           "a := (#2:add(#3)):mul(#4).\n");
    expect("prefix",           HEADER "a := ~b.\n", "a := b:not.\n");
    expect("prefix reaches past an operator", HEADER "a := ~b + c.\n",
           "a := b:not:add(c).\n");

    /* A send binds tighter than any operator there could be, because it is not
       one: `:` is core syntax and a dialect never sees it. */
    expect("sends bind tightest", HEADER "a := #1 + #2:negated.\n",
           "a := #1:add(#2:negated).\n");

    /* The three literal forms Solveig distinguishes, carried through. */
    expect("literals", HEADER "a := [#1, 2.5, \"s\", 'sym].\n",
           "a := [#1, 2.5, \"s\", 'sym].\n");

    /* Blocks: parameters, temporaries, and the leading bar that tells them
       apart. Solveig's rule, and Proto reads it the same way. */
    expect("one parameter",  HEADER "a := { x | x }.\n", "a := { x | x }.\n");
    expect("one temporary",  HEADER "a := { | t | t }.\n", "a := { | t | t }.\n");
    expect("both",           HEADER "a := { x | | t | t }.\n",
           "a := { x | | t | t }.\n");
    expect("neither",        HEADER "a := { b:print }.\n", "a := { b:print }.\n");

    expect("operators reach inside a block", HEADER "a := { x | x + #1 }.\n",
           "a := { x | x:add(#1) }.\n");

    /* `||` is one operator token and a lone `|` is still the block's own bar,
       which is the whole of what makes both declarable at once. The four cases
       are the four positions a bar can stand in: as an operator, after a
       parameter list, around temporaries, and after a parameter list *and*
       around temporaries. */
    expect("|| is an operator", HEADER "@infix || 25 or.\na := b || c.\n",
           "a := b:or(c).\n");
    expect("|| and a block's bar in one line",
           HEADER "@infix || 25 or.\na := { x | x || y }.\n",
           "a := { x | x:or(y) }.\n");
    expect("|| does not disturb temporaries",
           HEADER "@infix || 25 or.\na := { p | | t | t || p }.\n",
           "a := { p | | t | t:or(p) }.\n");

    /* What the token cost. `{ || … }` used to be an empty list of temporaries
       and emit nothing; it is two bars now, and the way to say the same thing
       is to space them. Written down as a test because it is the only thing
       this feature took away. */
    expect("an empty temporary list is spaced now",
           HEADER "a := { | | b:print }.\n", "a := { b:print }.\n");
    expect_rejected("'{ || … }' is no longer an empty temporary list",
                    HEADER "a := { || b:print }.\n");

    /* Slot assignment, and Solveig's prefix application. */
    expect("slot assignment", HEADER "r:name := #1.\n", "r:name := #1.\n");
    expect("prefix application is a send", HEADER "a := sin(x).\n",
           "a := x:sin.\n");

    /* @include is Solveig's directive and is carried through unread. */
    expect("include", HEADER "@include \"text.sol\".\n",
           "@include \"text.sol\".\n");

    /* What a module did not declare has no meaning in it. An undeclared
       operator quietly meaning something is the one convenience that would make
       every dialect secretly the same dialect. */
    expect_rejected("undeclared infix",  HEADER "a := #1 % #2.\n");
    expect_rejected("undeclared prefix", HEADER "a := !b.\n");
    expect_rejected("operator declared twice",
                    HEADER "@infix + 70 mul.\na := #1.\n");
    expect_rejected("directive after code",
                    HEADER "a := #1.\n@infix % 60 mod.\n");
    expect_rejected("language declared twice",
                    "@language a.\n@language b.\na := #1.\n");
    expect_rejected("assigning to something that is not a place",
                    HEADER "#1 + #2 := #3.\n");
    expect_rejected("unclosed block",    HEADER "a := { x | x.\n");
    expect_rejected("missing statement end", HEADER "a := #1 b := #2.\n");
    expect_rejected("'#' with no digits", HEADER "a := #.\n");
    expect_rejected("unclosed string",   HEADER "a := \"open.\n");

    /* A closing bracket that belongs to nobody. `synchronize` stops *at* one
       without consuming it, which is right when something above is waiting for
       it and wrong at the top level, where nothing is -- so the statement loop
       read it, failed, synchronised to it, and read it again. A regression here
       hangs `make test` rather than failing it, which is loud in its own way. */
    expect_rejected("an unmatched closing bracket terminates",
                    HEADER "a := #1.\n)\nb := #2.\n");
    expect_rejected("an unmatched closing brace terminates",
                    HEADER "a := #1.\n}\n");

    printf("%d checks, %d failed\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
