/* expand.c -- a form, and what it stands for. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "phoenix/expand.h"
#include "phoenix/lex.h"

/* ------------------------------------------------------------- fresh names */

/* Every identifier that appears anywhere in the module, templates included.
 *
 * Collected by lexing the source text rather than by walking the tree, because
 * the tree is about to change and the text is not. A name generated for hygiene
 * has to avoid this set, and after expansion no identifier exists that was not
 * either in it or generated against it -- which is what makes "fresh" mean
 * fresh rather than probably fresh. */
typedef struct {
    char **names;
    int count, capacity;
} NameSet;

static bool name_set_has(const NameSet *set, const char *name)
{
    for (int i = 0; i < set->count; i++)
        if (strcmp(set->names[i], name) == 0) return true;
    return false;
}

static void name_set_add(NameSet *set, const char *name, size_t length)
{
    if (set->count == set->capacity) {
        set->capacity = set->capacity < 64 ? 64 : set->capacity * 2;
        set->names = phx_realloc(set->names,
                                 (size_t)set->capacity * sizeof *set->names);
    }
    set->names[set->count++] = phx_strndup(name, length);
}

static void name_set_collect(NameSet *set, const char *text)
{
    PhxLexer lexer;
    phx_lexer_init(&lexer, text);
    for (;;) {
        PhxToken token = phx_lexer_next(&lexer);
        if (token.type == PHX_TOK_EOF) break;
        if (token.type != PHX_TOK_NAME) continue;
        char *name = phx_strndup(token.start, (size_t)token.length);
        if (!name_set_has(set, name)) name_set_add(set, name, strlen(name));
        free(name);
    }
}

static void name_set_free(NameSet *set)
{
    for (int i = 0; i < set->count; i++) free(set->names[i]);
    free(set->names);
    set->names = NULL;
    set->count = set->capacity = 0;
}

/* ------------------------------------------------------------- the expander */

/* A user local that a template identifier would be caught by, and the frame it
   belongs to. Collected first and renamed afterwards, because renaming while
   walking would move the ground under the walk. */
typedef struct Capture {
    PhxNode *block;
    const char *name;           /* borrowed from the block */
} Capture;

typedef struct {
    const PhxSource *source;
    const PhxDialect *dialect;
    PhxDiagnostics *diag;
    PhxProvenance *provenance;
    NameSet used;
    uint32_t scope;         /* one per expansion; 0 is what a person wrote */
    Capture *captures;
    int capture_count, capture_capacity;
    bool failed;
} Expander;

void phx_provenance_init(PhxProvenance *provenance)
{
    provenance->nodes = NULL;
    provenance->count = provenance->capacity = 0;
}

void phx_provenance_free(PhxProvenance *provenance)
{
    for (int i = 0; i < provenance->count; i++)
        phx_node_free(provenance->nodes[i]);
    free(provenance->nodes);
    phx_provenance_init(provenance);
}

static void retain(PhxProvenance *provenance, PhxNode *node)
{
    if (provenance->count == provenance->capacity) {
        provenance->capacity = provenance->capacity < 16
                             ? 16 : provenance->capacity * 2;
        provenance->nodes = phx_realloc(provenance->nodes,
                                        (size_t)provenance->capacity
                                            * sizeof *provenance->nodes);
    }
    provenance->nodes[provenance->count++] = node;
}

/* `t` -> `t__1`, or `t__2` if the module already had a `t__1`. The generated
   name joins the set, so two expansions never agree by accident. */
static char *fresh_name(Expander *expander, const char *base)
{
    char buffer[256];
    for (int n = 1; ; n++) {
        snprintf(buffer, sizeof buffer, "%s__%d", base, n);
        if (name_set_has(&expander->used, buffer)) continue;
        name_set_add(&expander->used, buffer, strlen(buffer));
        return phx_strndup(buffer, strlen(buffer));
    }
}

/* ---------------------------------------------------------- instantiation */

typedef struct {
    const PhxMacro *macro;
    const PhxNode *use;         /* the arguments live here */
    char **from;                /* what the template binds */
    char **to;                  /* what this expansion calls it instead */
    int rename_count;
    uint32_t scope;
} Instance;

/* Every name the template binds, once each. A template that binds `t` twice in
   two nested blocks gets one rename for both, which keeps the shadowing it
   wrote rather than flattening it. */
static void collect_binders(const PhxNode *node, NameSet *binders)
{
    for (int i = 0; i < node->param_count; i++)
        if (!name_set_has(binders, node->params[i]))
            name_set_add(binders, node->params[i], strlen(node->params[i]));
    for (int i = 0; i < node->temp_count; i++)
        if (!name_set_has(binders, node->temps[i]))
            name_set_add(binders, node->temps[i], strlen(node->temps[i]));
    for (int i = 0; i < node->count; i++)
        collect_binders(node->children[i], binders);
}

static const char *renamed(const Instance *instance, const char *name)
{
    for (int i = 0; i < instance->rename_count; i++)
        if (strcmp(instance->from[i], name) == 0) return instance->to[i];
    return name;
}

static int parameter_index(const PhxMacro *macro, const char *name)
{
    for (int i = 0; i < macro->param_count; i++)
        if (strcmp(macro->params[i], name) == 0) return i;
    return -1;
}

/* The template, copied, with parameters replaced and binders renamed.
 *
 * An argument goes in as a copy of itself and is not stamped: it is the
 * caller's code, its spans are the caller's spans, and an error in it must
 * point where the caller is looking. Everything else is the template's, and
 * carries the scope and the use it came from. */
static PhxNode *instantiate(const Instance *instance, const PhxNode *template)
{
    if (template->kind == PHX_NODE_NAME) {
        int index = parameter_index(instance->macro, template->text);
        if (index >= 0) return phx_node_copy(instance->use->children[index]);
    }

    PhxNode *copy = phx_node_new(template->kind, template->span);
    copy->scope = instance->scope;
    copy->introduced_by = instance->use;

    if (template->text != NULL) {
        const char *text = template->kind == PHX_NODE_NAME
                         ? renamed(instance, template->text)
                         : template->text;
        copy->text = phx_strndup(text, strlen(text));
    }

    for (int i = 0; i < template->param_count; i++) {
        const char *name = renamed(instance, template->params[i]);
        phx_node_add_param(copy, name, (int)strlen(name));
    }
    for (int i = 0; i < template->temp_count; i++) {
        const char *name = renamed(instance, template->temps[i]);
        phx_node_add_temp(copy, name, (int)strlen(name));
    }
    for (int i = 0; i < template->count; i++)
        phx_node_add(copy, instantiate(instance, template->children[i]));

    return copy;
}

static PhxNode *expand_node(Expander *expander, PhxNode *node, int depth);

/* How deep expansion may go before something is wrong with this file rather
   than with the program in it.
 *
 * A template may mention only the forms declared above it, so expanding form N
 * yields uses of forms below N and the highest index strictly falls: the depth
 * is bounded by the number of declarations, and this is unreachable. It is here
 * because "unreachable" is a claim about the reader and the dialect agreeing,
 * and a silent infinite loop is the worst way to find out that they do not. */
#define PHX_EXPANSION_LIMIT 256

static PhxNode *expand_macro(Expander *expander, PhxNode *use, int depth)
{
    const PhxMacro *macro = phx_dialect_macro(expander->dialect,
                                              use->text, (int)strlen(use->text));
    if (macro == NULL) {
        /* The reader only builds one of these for a name it found, so this is
           the two of them disagreeing rather than anything a program did. */
        phx_error(expander->diag, use->span,
                  "internal: '%s' was read as a form and is not one", use->text);
        expander->failed = true;
        return use;
    }

    NameSet binders = { NULL, 0, 0 };
    collect_binders(macro->template, &binders);

    Instance instance;
    instance.macro = macro;
    instance.use = use;
    instance.rename_count = binders.count;
    instance.scope = ++expander->scope;
    instance.from = binders.names;
    instance.to = binders.count > 0
                ? phx_alloc((size_t)binders.count * sizeof *instance.to) : NULL;
    for (int i = 0; i < binders.count; i++)
        instance.to[i] = fresh_name(expander, binders.names[i]);

    PhxNode *result = instantiate(&instance, macro->template);

    for (int i = 0; i < binders.count; i++) free(instance.to[i]);
    free(instance.to);
    name_set_free(&binders);

    /* The use is kept rather than freed: everything just built points at it,
       and a diagnostic will want to say so. */
    retain(expander->provenance, use);

    return expand_node(expander, result, depth + 1);
}

static PhxNode *expand_node(Expander *expander, PhxNode *node, int depth)
{
    if (depth > PHX_EXPANSION_LIMIT) {
        phx_error(expander->diag, node->span,
                  "expansion went %d deep, which should not be possible",
                  depth);
        phx_note_expansion(expander->diag, node);
        expander->failed = true;
        return node;
    }

    /* Arguments first, so a form is handed code that is already expanded and a
       parameter used twice does not expand twice. */
    for (int i = 0; i < node->count; i++)
        node->children[i] = expand_node(expander, node->children[i], depth);

    if (node->kind == PHX_NODE_MACRO)
        return expand_macro(expander, node, depth);

    return node;
}

/* --------------------------------------------------- the other half of it */

/* Renaming a template's binders stops it capturing a name its caller passed.
 * It does nothing about the other direction: a template's *free* reference,
 * landing inside a frame that happens to bind that name.
 *
 *     @syntax bump(n) => total := total:add(n).
 *
 *     total := #0.
 *     run := { | total | total := #100. bump(#5). total }.
 *
 * The template means the global `total`. Written out literally it lands inside
 * a block whose temporary is also called `total`, and Solveig resolves a bare
 * name to a local before a global -- so the form updates the caller's variable
 * and the global stays #0. The program runs and answers wrongly.
 *
 * Solveig's rule is what makes this fixable in one pass rather than needing a
 * resolver: **only parameters and `| ... |` temporaries are locals, and
 * everything else is a global in one flat namespace** (REFERENCE.md, "Names and
 * binding"). So the frames are exactly the blocks, a frame's locals are exactly
 * its parameters and temporaries, and a name that is not one of those needs no
 * protecting -- there is no second global called `total` for a template to have
 * meant instead.
 *
 * Which leaves one case, and it is the caller's local that gives way: the
 * template cannot be renamed, because reaching the global is the whole of what
 * it meant. Renaming a local throughout its own frame is invisible to everybody
 * else, a local being a thing no other frame can see. */

typedef struct Frame {
    struct Frame *parent;
    PhxNode *block;             /* NULL at the module's own level */
} Frame;

static bool binds(const PhxNode *block, const char *name)
{
    for (int i = 0; i < block->param_count; i++)
        if (strcmp(block->params[i], name) == 0) return true;
    for (int i = 0; i < block->temp_count; i++)
        if (strcmp(block->temps[i], name) == 0) return true;
    return false;
}

/* Deduplicated: one frame's one local is renamed once, however many template
   identifiers would have been caught by it. */
static void add_capture(Expander *expander, PhxNode *block, const char *name)
{
    for (int i = 0; i < expander->capture_count; i++)
        if (expander->captures[i].block == block &&
            strcmp(expander->captures[i].name, name) == 0) return;

    if (expander->capture_count == expander->capture_capacity) {
        expander->capture_capacity = expander->capture_capacity < 8
                                   ? 8 : expander->capture_capacity * 2;
        expander->captures = phx_realloc(expander->captures,
                                         (size_t)expander->capture_capacity
                                             * sizeof *expander->captures);
    }
    expander->captures[expander->capture_count].block = block;
    expander->captures[expander->capture_count].name = name;
    expander->capture_count++;
}

/* Every user local that a template identifier would be caught by.
 *
 * Walked outward and not stopped at the first, because renaming the innermost
 * only hands the capture to the next one out. Stopped at a frame of the
 * template's own, which is a local the template meant and got. */
static void find_captures(Expander *expander, PhxNode *node, Frame *frame)
{
    if (node->kind == PHX_NODE_NAME && node->scope != 0) {
        for (Frame *f = frame; f != NULL && f->block != NULL; f = f->parent) {
            if (!binds(f->block, node->text)) continue;
            if (f->block->scope == node->scope) break;
            if (f->block->scope == 0) add_capture(expander, f->block, node->text);
        }
    }

    /* A group borrows the frame it sits in rather than making one, so only a
       block is a frame here. Group temporaries would belong to the enclosing
       frame if Phoenix read them, and it does not yet. */
    Frame inner = { frame, node };
    Frame *next = node->kind == PHX_NODE_BLOCK ? &inner : frame;
    for (int i = 0; i < node->count; i++)
        find_captures(expander, node->children[i], next);
}

/* Every reference the renamed binding owns, and no others.
 *
 * `scope` is the binding's own origin: a reference belongs to a binding only if
 * it came from the same place, which is what keeps the template's identifier --
 * the one being protected -- untouched while it sits in the middle of the
 * renamed frame. */
static void rename_in(PhxNode *node, const char *from, const char *to,
                      uint32_t scope)
{
    if (node->kind == PHX_NODE_BLOCK && node->scope == scope &&
        binds(node, from))
        return;                                     /* shadowed from here down */

    if (node->kind == PHX_NODE_NAME && node->scope == scope &&
        strcmp(node->text, from) == 0) {
        free(node->text);
        node->text = phx_strndup(to, strlen(to));
    }

    for (int i = 0; i < node->count; i++)
        rename_in(node->children[i], from, to, scope);
}

static void rename_binder(PhxNode *block, const char *from, const char *to)
{
    for (int i = 0; i < block->param_count; i++)
        if (strcmp(block->params[i], from) == 0) {
            free(block->params[i]);
            block->params[i] = phx_strndup(to, strlen(to));
        }
    for (int i = 0; i < block->temp_count; i++)
        if (strcmp(block->temps[i], from) == 0) {
            free(block->temps[i]);
            block->temps[i] = phx_strndup(to, strlen(to));
        }
}

static void protect_free_references(Expander *expander, PhxNode *module)
{
    find_captures(expander, module, NULL);

    for (int i = 0; i < expander->capture_count; i++) {
        Capture *capture = &expander->captures[i];
        char *fresh = fresh_name(expander, capture->name);
        char *from = phx_strndup(capture->name, strlen(capture->name));

        rename_binder(capture->block, from, fresh);
        for (int j = 0; j < capture->block->count; j++)
            rename_in(capture->block->children[j], from, fresh,
                      capture->block->scope);

        free(from);
        free(fresh);
    }
}

/* ---------------------------------------------------------- after the fact */

static bool assignable(const PhxNode *node)
{
    return node->kind == PHX_NODE_NAME ||
           (node->kind == PHX_NODE_SEND && node->count == 1);
}

/* What the reader checked before expansion and cannot check after it.
 *
 *     @syntax setTo(place, v) => place := v.
 *     setTo(#1, #2).
 *
 * The template is a well-formed assignment and the use is a well-formed call.
 * Only the two together are wrong, and the only useful way to say so names both
 * -- which is what the trail is for. */
static void validate(Expander *expander, const PhxNode *node)
{
    if (node->kind == PHX_NODE_ASSIGN && !assignable(node->children[0])) {
        /* The caret goes on the target, which is where the reader is looking.
           The trail comes off the assignment, because the target is the
           caller's own code and knows nothing about how it got here -- it is
           the *template* that put it in a place a place has to be. */
        phx_error(expander->diag, phx_node_extent(node->children[0]),
                  "this cannot be assigned to");
        phx_note_expansion(expander->diag, node);
        expander->failed = true;
    }
    for (int i = 0; i < node->count; i++)
        validate(expander, node->children[i]);
}

bool phx_expand(PhxNode *module, const PhxSource *source,
                const PhxDialect *dialect, PhxDiagnostics *diag,
                PhxProvenance *provenance)
{
    Expander expander;
    expander.source = source;
    expander.dialect = dialect;
    expander.diag = diag;
    expander.provenance = provenance;
    expander.used.names = NULL;
    expander.used.count = expander.used.capacity = 0;
    expander.scope = 0;
    expander.captures = NULL;
    expander.capture_count = expander.capture_capacity = 0;
    expander.failed = false;

    name_set_collect(&expander.used, source->text);

    for (int i = 0; i < module->count; i++)
        module->children[i] = expand_node(&expander, module->children[i], 0);

    if (!expander.failed) protect_free_references(&expander, module);
    if (!expander.failed) validate(&expander, module);

    free(expander.captures);
    name_set_free(&expander.used);
    return !expander.failed;
}
