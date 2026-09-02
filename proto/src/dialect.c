/* dialect.c -- the operator table a module declared for itself.
 *
 * A flat array, searched linearly. A dialect with enough operators for that to
 * matter is a dialect that has gone wrong in a way a hash table would only
 * hide -- and the arrays are walked backwards so that if a redefinition is ever
 * allowed, the later one is what a use finds. */
#include <stdlib.h>
#include <string.h>

#include "proto/dialect.h"

static const char *const hole_kind_names[] = {
    "expression", "name", "literal", "block", "place"
};

const char *proto_hole_kind_name(ProtoHoleKind kind)
{
    return hole_kind_names[kind];
}

bool proto_hole_kind_from(const char *text, int length, ProtoHoleKind *out)
{
    for (size_t i = 0; i < sizeof hole_kind_names / sizeof *hole_kind_names; i++)
        if ((int)strlen(hole_kind_names[i]) == length &&
            memcmp(hole_kind_names[i], text, (size_t)length) == 0) {
            *out = (ProtoHoleKind)i;
            return true;
        }
    return false;
}

void proto_dialect_init(ProtoDialect *dialect)
{
    dialect->infix = NULL;
    dialect->infix_count = dialect->infix_capacity = 0;
    dialect->prefix = NULL;
    dialect->prefix_count = dialect->prefix_capacity = 0;
    dialect->macro = NULL;
    dialect->macro_count = dialect->macro_capacity = 0;
}

void proto_dialect_free(ProtoDialect *dialect)
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
        free(dialect->macro[i].kinds);
        for (int j = 0; j < dialect->macro[i].part_count; j++)
            free(dialect->macro[i].parts[j].text);
        free(dialect->macro[i].parts);
        free(dialect->macro[i].name);
        proto_node_free(dialect->macro[i].template);
    }
    free(dialect->macro);
    free(dialect->infix);
    free(dialect->prefix);
    proto_dialect_init(dialect);
}

static bool same(const char *spelling, const char *chars, int length)
{
    return (int)strlen(spelling) == length &&
           memcmp(spelling, chars, (size_t)length) == 0;
}

const ProtoInfix *proto_dialect_infix(const ProtoDialect *dialect,
                                  const char *spelling, int length)
{
    for (int i = dialect->infix_count - 1; i >= 0; i--)
        if (same(dialect->infix[i].spelling, spelling, length))
            return &dialect->infix[i];
    return NULL;
}

const ProtoPrefix *proto_dialect_prefix(const ProtoDialect *dialect,
                                    const char *spelling, int length)
{
    for (int i = dialect->prefix_count - 1; i >= 0; i--)
        if (same(dialect->prefix[i].spelling, spelling, length))
            return &dialect->prefix[i];
    return NULL;
}

const ProtoInfix *proto_dialect_add_infix(ProtoDialect *dialect,
                                      const char *spelling, int length,
                                      const char *selector, int selector_length,
                                      int form, int precedence, ProtoAssoc assoc,
                                      ProtoSpan declared_at)
{
    /* Always added, never refused. Lookup walks backwards, so the last
       declaration is the one a use finds -- and what to say about the one it
       displaced is a policy the reader applies, not a rule the table has.

       **The lookup comes after the growth, and must.** It answers a pointer
       *into* this array, and the caller dereferences it to report the
       collision; a realloc between the two moves the block and leaves that
       pointer in freed memory. Growing first costs nothing -- realloc does not
       change what the existing entries say, only where they are. */
    if (dialect->infix_count == dialect->infix_capacity) {
        dialect->infix_capacity = dialect->infix_capacity < 8
                                ? 8 : dialect->infix_capacity * 2;
        dialect->infix = proto_realloc(dialect->infix,
                                     (size_t)dialect->infix_capacity * sizeof *dialect->infix);
    }

    const ProtoInfix *existing = proto_dialect_infix(dialect, spelling, length);

    ProtoInfix *entry = &dialect->infix[dialect->infix_count++];
    entry->spelling = proto_strndup(spelling, (size_t)length);
    entry->selector = selector != NULL
                    ? proto_strndup(selector, (size_t)selector_length) : NULL;
    entry->form = form;
    entry->precedence = precedence;
    entry->assoc = assoc;
    entry->declared_at = declared_at;
    return existing;
}

const ProtoPrefix *proto_dialect_add_prefix(ProtoDialect *dialect,
                                        const char *spelling, int length,
                                        const char *selector, int selector_length,
                                        int form, ProtoSpan declared_at)
{
    /* After the growth, for the reason proto_dialect_add_infix gives. */
    if (dialect->prefix_count == dialect->prefix_capacity) {
        dialect->prefix_capacity = dialect->prefix_capacity < 8
                                 ? 8 : dialect->prefix_capacity * 2;
        dialect->prefix = proto_realloc(dialect->prefix,
                                      (size_t)dialect->prefix_capacity * sizeof *dialect->prefix);
    }

    const ProtoPrefix *existing = proto_dialect_prefix(dialect, spelling, length);

    ProtoPrefix *entry = &dialect->prefix[dialect->prefix_count++];
    entry->spelling = proto_strndup(spelling, (size_t)length);
    entry->selector = selector != NULL
                    ? proto_strndup(selector, (size_t)selector_length) : NULL;
    entry->form = form;
    entry->declared_at = declared_at;
    return existing;
}

const ProtoMacro *proto_dialect_macro(const ProtoDialect *dialect,
                                  const char *name, int length)
{
    for (int i = dialect->macro_count - 1; i >= 0; i--)
        if (same(dialect->macro[i].name, name, length))
            return &dialect->macro[i];
    return NULL;
}

const ProtoMacro *proto_dialect_form_at(const ProtoDialect *dialect, int index)
{
    if (index < 0 || index >= dialect->macro_count) return NULL;
    return &dialect->macro[index];
}

int proto_dialect_index_of(const ProtoDialect *dialect, const ProtoMacro *macro)
{
    return (int)(macro - dialect->macro);
}

int proto_dialect_forms(const ProtoDialect *dialect, const char *name, int length,
                      const ProtoMacro **out, int max)
{
    int found = 0;
    for (int i = 0; i < dialect->macro_count; i++)
        if (same(dialect->macro[i].name, name, length)) {
            if (found < max) out[found] = &dialect->macro[i];
            found++;
        }
    return found;
}

/* Two forms are the same form when they are spelled the same way. Two patterns
   under one word that differ somewhere are two forms, which is the whole point
   of them sharing a word. */
static bool same_shape(const ProtoMacro *macro,
                       const ProtoPatternPart *parts, int part_count)
{
    if (macro->part_count != part_count) return false;
    if (parts == NULL) return macro->param_count >= 0;   /* both call-shaped */
    for (int i = 0; i < part_count; i++) {
        if (macro->parts[i].is_hole != parts[i].is_hole) return false;
        if (!parts[i].is_hole &&
            strcmp(macro->parts[i].text, parts[i].text) != 0) return false;
    }
    return true;
}

const ProtoMacro *proto_dialect_add_macro(ProtoDialect *dialect,
                                      const char *name, int length,
                                      char **params, ProtoHoleKind *kinds,
                                      int param_count,
                                      ProtoPatternPart *parts, int part_count,
                                      ProtoNode *template, ProtoSpan declared_at)
{
    /* After the growth, for the reason proto_dialect_add_infix gives. */
    if (dialect->macro_count == dialect->macro_capacity) {
        dialect->macro_capacity = dialect->macro_capacity < 8
                                ? 8 : dialect->macro_capacity * 2;
        dialect->macro = proto_realloc(dialect->macro,
                                     (size_t)dialect->macro_capacity * sizeof *dialect->macro);
    }

    const ProtoMacro *existing = NULL;
    for (int i = dialect->macro_count - 1; i >= 0; i--)
        if (same(dialect->macro[i].name, name, length) &&
            same_shape(&dialect->macro[i], parts, part_count)) {
            existing = &dialect->macro[i];
            break;
        }

    ProtoMacro *entry = &dialect->macro[dialect->macro_count++];
    entry->name = proto_strndup(name, (size_t)length);
    entry->params = params;
    entry->kinds = kinds;
    entry->param_count = param_count;
    entry->parts = parts;
    entry->part_count = part_count;
    entry->template = template;
    entry->declared_at = declared_at;
    return existing;
}

int proto_dialect_add_template(ProtoDialect *dialect, const char *name, int length,
                             char **params, ProtoHoleKind *kinds, int param_count,
                             ProtoNode *template, ProtoSpan declared_at)
{
    if (dialect->macro_count == dialect->macro_capacity) {
        dialect->macro_capacity = dialect->macro_capacity < 8
                                ? 8 : dialect->macro_capacity * 2;
        dialect->macro = proto_realloc(dialect->macro,
                                     (size_t)dialect->macro_capacity * sizeof *dialect->macro);
    }

    ProtoMacro *entry = &dialect->macro[dialect->macro_count];
    entry->name = proto_strndup(name, (size_t)length);
    entry->params = params;
    entry->kinds = kinds;
    entry->param_count = param_count;
    entry->parts = NULL;
    entry->part_count = 0;
    entry->template = template;
    entry->declared_at = declared_at;
    return dialect->macro_count++;
}
