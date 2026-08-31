/* dialect.c -- the operator table a module declared for itself.
 *
 * A flat array, searched linearly. A dialect with enough operators for that to
 * matter is a dialect that has gone wrong in a way a hash table would only
 * hide -- and the arrays are walked backwards so that if a redefinition is ever
 * allowed, the later one is what a use finds. */
#include <stdlib.h>
#include <string.h>

#include "phoenix/dialect.h"

void phx_dialect_init(PhxDialect *dialect)
{
    dialect->name = NULL;
    dialect->declared_at = PHX_SPAN_NONE;
    dialect->infix = NULL;
    dialect->infix_count = dialect->infix_capacity = 0;
    dialect->prefix = NULL;
    dialect->prefix_count = dialect->prefix_capacity = 0;
    dialect->macro = NULL;
    dialect->macro_count = dialect->macro_capacity = 0;
}

void phx_dialect_free(PhxDialect *dialect)
{
    for (int i = 0; i < dialect->infix_count; i++) {
        free(dialect->infix[i].spelling);
        free(dialect->infix[i].selector);
    }
    for (int i = 0; i < dialect->prefix_count; i++) {
        free(dialect->prefix[i].spelling);
        free(dialect->prefix[i].selector);
    }
    for (int i = 0; i < dialect->macro_count; i++) {
        for (int j = 0; j < dialect->macro[i].param_count; j++)
            free(dialect->macro[i].params[j]);
        free(dialect->macro[i].params);
        free(dialect->macro[i].name);
        phx_node_free(dialect->macro[i].template);
    }
    free(dialect->macro);
    free(dialect->infix);
    free(dialect->prefix);
    free(dialect->name);
    phx_dialect_init(dialect);
}

static bool same(const char *spelling, const char *chars, int length)
{
    return (int)strlen(spelling) == length &&
           memcmp(spelling, chars, (size_t)length) == 0;
}

const PhxInfix *phx_dialect_infix(const PhxDialect *dialect,
                                  const char *spelling, int length)
{
    for (int i = dialect->infix_count - 1; i >= 0; i--)
        if (same(dialect->infix[i].spelling, spelling, length))
            return &dialect->infix[i];
    return NULL;
}

const PhxPrefix *phx_dialect_prefix(const PhxDialect *dialect,
                                    const char *spelling, int length)
{
    for (int i = dialect->prefix_count - 1; i >= 0; i--)
        if (same(dialect->prefix[i].spelling, spelling, length))
            return &dialect->prefix[i];
    return NULL;
}

const PhxInfix *phx_dialect_add_infix(PhxDialect *dialect,
                                      const char *spelling, int length,
                                      const char *selector, int selector_length,
                                      int precedence, PhxAssoc assoc,
                                      PhxSpan declared_at)
{
    /* Always added, never refused. Lookup walks backwards, so the last
       declaration is the one a use finds -- and what to say about the one it
       displaced is a policy the reader applies, not a rule the table has. */
    const PhxInfix *existing = phx_dialect_infix(dialect, spelling, length);

    if (dialect->infix_count == dialect->infix_capacity) {
        dialect->infix_capacity = dialect->infix_capacity < 8
                                ? 8 : dialect->infix_capacity * 2;
        dialect->infix = phx_realloc(dialect->infix,
                                     (size_t)dialect->infix_capacity * sizeof *dialect->infix);
    }

    PhxInfix *entry = &dialect->infix[dialect->infix_count++];
    entry->spelling = phx_strndup(spelling, (size_t)length);
    entry->selector = phx_strndup(selector, (size_t)selector_length);
    entry->precedence = precedence;
    entry->assoc = assoc;
    entry->declared_at = declared_at;
    return existing;
}

const PhxPrefix *phx_dialect_add_prefix(PhxDialect *dialect,
                                        const char *spelling, int length,
                                        const char *selector, int selector_length,
                                        PhxSpan declared_at)
{
    const PhxPrefix *existing = phx_dialect_prefix(dialect, spelling, length);

    if (dialect->prefix_count == dialect->prefix_capacity) {
        dialect->prefix_capacity = dialect->prefix_capacity < 8
                                 ? 8 : dialect->prefix_capacity * 2;
        dialect->prefix = phx_realloc(dialect->prefix,
                                      (size_t)dialect->prefix_capacity * sizeof *dialect->prefix);
    }

    PhxPrefix *entry = &dialect->prefix[dialect->prefix_count++];
    entry->spelling = phx_strndup(spelling, (size_t)length);
    entry->selector = phx_strndup(selector, (size_t)selector_length);
    entry->declared_at = declared_at;
    return existing;
}

const PhxMacro *phx_dialect_macro(const PhxDialect *dialect,
                                  const char *name, int length)
{
    for (int i = dialect->macro_count - 1; i >= 0; i--)
        if (same(dialect->macro[i].name, name, length))
            return &dialect->macro[i];
    return NULL;
}

const PhxMacro *phx_dialect_add_macro(PhxDialect *dialect,
                                      const char *name, int length,
                                      char **params, int param_count,
                                      PhxNode *template, PhxSpan declared_at)
{
    const PhxMacro *existing = phx_dialect_macro(dialect, name, length);

    if (dialect->macro_count == dialect->macro_capacity) {
        dialect->macro_capacity = dialect->macro_capacity < 8
                                ? 8 : dialect->macro_capacity * 2;
        dialect->macro = phx_realloc(dialect->macro,
                                     (size_t)dialect->macro_capacity * sizeof *dialect->macro);
    }

    PhxMacro *entry = &dialect->macro[dialect->macro_count++];
    entry->name = phx_strndup(name, (size_t)length);
    entry->params = params;
    entry->param_count = param_count;
    entry->template = template;
    entry->declared_at = declared_at;
    return existing;
}
