/* dialect.c -- the operator table a module declared for itself.
 *
 * A flat array, searched linearly. A dialect with enough operators for that to
 * matter is a dialect that has gone wrong in a way a hash table would only
 * hide -- and the arrays are walked backwards so that if a redefinition is ever
 * allowed, the later one is what a use finds. */
#include <stdlib.h>
#include <string.h>

#include "parasol/dialect.h"

static const char *const hole_kind_names[] = {
    "expression", "name", "literal", "block", "place"
};

const char *parasol_hole_kind_name(ParasolHoleKind kind)
{
    return hole_kind_names[kind];
}

bool parasol_hole_kind_from(const char *text, int length, ParasolHoleKind *out)
{
    for (size_t i = 0; i < sizeof hole_kind_names / sizeof *hole_kind_names; i++)
        if ((int)strlen(hole_kind_names[i]) == length &&
            memcmp(hole_kind_names[i], text, (size_t)length) == 0) {
            *out = (ParasolHoleKind)i;
            return true;
        }
    return false;
}

void parasol_dialect_init(ParasolDialect *dialect)
{
    dialect->infix = NULL;
    dialect->infix_count = dialect->infix_capacity = 0;
    dialect->prefix = NULL;
    dialect->prefix_count = dialect->prefix_capacity = 0;
    dialect->macro = NULL;
    dialect->macro_count = dialect->macro_capacity = 0;
}

void parasol_dialect_free(ParasolDialect *dialect)
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
        parasol_node_free(dialect->macro[i].template);
    }
    free(dialect->macro);
    free(dialect->infix);
    free(dialect->prefix);
    parasol_dialect_init(dialect);
}

static bool same(const char *spelling, const char *chars, int length)
{
    return (int)strlen(spelling) == length &&
           memcmp(spelling, chars, (size_t)length) == 0;
}

const ParasolInfix *parasol_dialect_infix(const ParasolDialect *dialect,
                                  const char *spelling, int length)
{
    for (int i = dialect->infix_count - 1; i >= 0; i--)
        if (same(dialect->infix[i].spelling, spelling, length))
            return &dialect->infix[i];
    return NULL;
}

const ParasolPrefix *parasol_dialect_prefix(const ParasolDialect *dialect,
                                    const char *spelling, int length)
{
    for (int i = dialect->prefix_count - 1; i >= 0; i--)
        if (same(dialect->prefix[i].spelling, spelling, length))
            return &dialect->prefix[i];
    return NULL;
}

const ParasolInfix *parasol_dialect_add_infix(ParasolDialect *dialect,
                                      const char *spelling, int length,
                                      const char *selector, int selector_length,
                                      int form, int precedence, ParasolAssoc assoc,
                                      ParasolSpan declared_at)
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
        dialect->infix = parasol_realloc(dialect->infix,
                                     (size_t)dialect->infix_capacity * sizeof *dialect->infix);
    }

    const ParasolInfix *existing = parasol_dialect_infix(dialect, spelling, length);

    ParasolInfix *entry = &dialect->infix[dialect->infix_count++];
    entry->spelling = parasol_strndup(spelling, (size_t)length);
    entry->selector = selector != NULL
                    ? parasol_strndup(selector, (size_t)selector_length) : NULL;
    entry->form = form;
    entry->precedence = precedence;
    entry->assoc = assoc;
    entry->declared_at = declared_at;
    return existing;
}

const ParasolPrefix *parasol_dialect_add_prefix(ParasolDialect *dialect,
                                        const char *spelling, int length,
                                        const char *selector, int selector_length,
                                        int form, ParasolSpan declared_at)
{
    /* After the growth, for the reason parasol_dialect_add_infix gives. */
    if (dialect->prefix_count == dialect->prefix_capacity) {
        dialect->prefix_capacity = dialect->prefix_capacity < 8
                                 ? 8 : dialect->prefix_capacity * 2;
        dialect->prefix = parasol_realloc(dialect->prefix,
                                      (size_t)dialect->prefix_capacity * sizeof *dialect->prefix);
    }

    const ParasolPrefix *existing = parasol_dialect_prefix(dialect, spelling, length);

    ParasolPrefix *entry = &dialect->prefix[dialect->prefix_count++];
    entry->spelling = parasol_strndup(spelling, (size_t)length);
    entry->selector = selector != NULL
                    ? parasol_strndup(selector, (size_t)selector_length) : NULL;
    entry->form = form;
    entry->declared_at = declared_at;
    return existing;
}

const ParasolMacro *parasol_dialect_macro(const ParasolDialect *dialect,
                                  const char *name, int length)
{
    for (int i = dialect->macro_count - 1; i >= 0; i--)
        if (same(dialect->macro[i].name, name, length))
            return &dialect->macro[i];
    return NULL;
}

const ParasolMacro *parasol_dialect_form_at(const ParasolDialect *dialect, int index)
{
    if (index < 0 || index >= dialect->macro_count) return NULL;
    return &dialect->macro[index];
}

int parasol_dialect_index_of(const ParasolDialect *dialect, const ParasolMacro *macro)
{
    return (int)(macro - dialect->macro);
}

int parasol_dialect_forms(const ParasolDialect *dialect, const char *name, int length,
                      const ParasolMacro **out, int max)
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
static bool same_shape(const ParasolMacro *macro,
                       const ParasolPatternPart *parts, int part_count)
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

const ParasolMacro *parasol_dialect_add_macro(ParasolDialect *dialect,
                                      const char *name, int length,
                                      char **params, ParasolHoleKind *kinds,
                                      int param_count,
                                      ParasolPatternPart *parts, int part_count,
                                      ParasolNode *template, ParasolSpan declared_at)
{
    /* After the growth, for the reason parasol_dialect_add_infix gives. */
    if (dialect->macro_count == dialect->macro_capacity) {
        dialect->macro_capacity = dialect->macro_capacity < 8
                                ? 8 : dialect->macro_capacity * 2;
        dialect->macro = parasol_realloc(dialect->macro,
                                     (size_t)dialect->macro_capacity * sizeof *dialect->macro);
    }

    const ParasolMacro *existing = NULL;
    for (int i = dialect->macro_count - 1; i >= 0; i--)
        if (same(dialect->macro[i].name, name, length) &&
            same_shape(&dialect->macro[i], parts, part_count)) {
            existing = &dialect->macro[i];
            break;
        }

    ParasolMacro *entry = &dialect->macro[dialect->macro_count++];
    entry->name = parasol_strndup(name, (size_t)length);
    entry->params = params;
    entry->kinds = kinds;
    entry->param_count = param_count;
    entry->parts = parts;
    entry->part_count = part_count;
    entry->template = template;
    entry->declared_at = declared_at;
    return existing;
}

int parasol_dialect_add_template(ParasolDialect *dialect, const char *name, int length,
                             char **params, ParasolHoleKind *kinds, int param_count,
                             ParasolNode *template, ParasolSpan declared_at)
{
    if (dialect->macro_count == dialect->macro_capacity) {
        dialect->macro_capacity = dialect->macro_capacity < 8
                                ? 8 : dialect->macro_capacity * 2;
        dialect->macro = parasol_realloc(dialect->macro,
                                     (size_t)dialect->macro_capacity * sizeof *dialect->macro);
    }

    ParasolMacro *entry = &dialect->macro[dialect->macro_count];
    entry->name = parasol_strndup(name, (size_t)length);
    entry->params = params;
    entry->kinds = kinds;
    entry->param_count = param_count;
    entry->parts = NULL;
    entry->part_count = 0;
    entry->template = template;
    entry->declared_at = declared_at;
    return dialect->macro_count++;
}
