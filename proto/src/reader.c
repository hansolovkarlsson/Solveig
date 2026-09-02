/* reader.c -- the header, and then the body under what the header declared.
 *
 * Two passes over one token stream, in one direction. The directives come
 * first and are the only thing that changes how the rest reads, so by the time
 * a statement is parsed the grammar is settled and cannot move again. That is
 * the property the whole design is built to keep: a file can be parsed by
 * reading it from the top, and nothing has to be run to find out how. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "proto/lex.h"
#include "proto/reader.h"

/* One file being read, and the `@use` that led to it.
 *
 * The chain is what prints under a diagnostic in a dialect file, so somebody
 * looking at an error three files away can see how they got there -- and it is
 * what a cycle is detected against, a file already on the chain being one that
 * is not finished being read. */
typedef struct Use {
    const struct Use *outer;
    const ProtoSource *source;
    ProtoSpan at;             /* the directive; NONE for the file on the command line */
} Use;

typedef struct {
    ProtoLexer lexer;
    ProtoToken current;
    ProtoToken previous;
    const ProtoSource *source;
    const ProtoSource *primary;   /* the file on the command line */
    ProtoUnit *unit;
    const Use *use;
    ProtoDialect *dialect;
    ProtoDiagnostics *diag;
    bool panicked;          /* suppresses the cascade after one error */
} Reader;

static ProtoNode *expression(Reader *reader);
static ProtoNode *statement(Reader *reader);
static const char *shadowed_parameter(const ProtoNode *node,
                                      char **params, int param_count);

/* ------------------------------------------------------------------ tokens */

static void advance(Reader *reader)
{
    reader->previous = reader->current;
    for (;;) {
        reader->current = proto_lexer_next(&reader->lexer);
        if (reader->current.type != PROTO_TOK_ERROR) return;
        if (!reader->panicked) {
            proto_error(reader->diag, reader->current.span, "%s",
                      reader->current.message);
            reader->panicked = true;
        } else {
            reader->diag->errors++;
        }
    }
}

static bool check(Reader *reader, ProtoTokenType type)
{
    return reader->current.type == type;
}

static bool match(Reader *reader, ProtoTokenType type)
{
    if (!check(reader, type)) return false;
    advance(reader);
    return true;
}

static void error_here(Reader *reader, const char *format, ...);

static bool consume(Reader *reader, ProtoTokenType type, const char *what)
{
    if (match(reader, type)) return true;
    if (!reader->panicked) {
        proto_error(reader->diag, reader->current.span, "expected %s, found %s",
                  what, proto_token_type_name(reader->current.type));
        reader->panicked = true;
    }
    return false;
}

static void error_at(Reader *reader, ProtoSpan span, const char *format, ...)
{
    if (reader->panicked) return;
    va_list args;
    va_start(args, format);
    /* proto_error is variadic itself, so the message is formatted here and
       handed over whole. One buffer rather than a second vararg entry point:
       diag.h says every error takes a span and nothing else, and keeping that
       true is worth a fixed buffer. */
    char message[512];
    vsnprintf(message, sizeof message, format, args);
    va_end(args);
    proto_error(reader->diag, span, "%s", message);
    reader->panicked = true;
}

static void error_here(Reader *reader, const char *format, ...)
{
    if (reader->panicked) return;
    va_list args;
    va_start(args, format);
    char message[512];
    vsnprintf(message, sizeof message, format, args);
    va_end(args);
    error_at(reader, reader->current.span, "%s", message);
}

/* The chain of `@use` that led to the file being read. Printed after a report,
   and nothing at all for the file on the command line. */
static void note_trail(Reader *reader)
{
    for (const Use *use = reader->use; use != NULL; use = use->outer)
        proto_note_from(reader->diag, use->at, "used from");
}

/* Solveig's answer to two files claiming one name, applied to syntax: the later
 * one wins, and the compiler says so rather than letting it pass.
 *
 * The four cases differ in who could have known, which is the same distinction
 * Solveig draws when it warns on a claim and not on an update:
 *
 *   both in this module      an error. A module contradicting itself in eight
 *                            lines of header is a mistake, not a choice.
 *
 *   this module over a use   silent. Deliberate, local, and both lines are in
 *                            the file being edited -- overriding an imported
 *                            operator is a thing a module is allowed to want.
 *
 *   a use over this module   a warning. Almost certainly the `@use` wanting to
 *                            be above the declaration rather than below it.
 *
 *   two uses                 a warning. Neither author knew about the other,
 *                            which is the case the rule exists for.
 */
static void collision(Reader *reader, const char *what, const char *spelling,
                      ProtoSpan now, ProtoSpan before)
{
    bool now_is_ours = now.source == reader->primary;
    bool before_was_ours = before.source == reader->primary;

    if (now_is_ours && before_was_ours) {
        error_at(reader, now, "%s '%s' has already been declared in this module",
                 what, spelling);
        proto_note(reader->diag, before, "declared here");
        return;
    }
    if (now_is_ours) return;

    if (before_was_ours) {
        proto_warning(reader->diag, now,
                    "%s '%s' here overrides the one this module declared",
                    what, spelling);
        note_trail(reader);
        proto_note(reader->diag, before,
                 "declared here, and put back by moving the @use above it");
        return;
    }

    proto_warning(reader->diag, now,
                "%s '%s' was already declared by %s -- this one wins, and "
                "nothing else will say so", what, spelling, before.source->path);
    note_trail(reader);
    proto_note(reader->diag, before, "declared here");
}

/* After an error, skip to just past the next statement end at the outermost
   level, so a second mistake in the same file is still reported. */
static void synchronize(Reader *reader)
{
    reader->panicked = false;
    int depth = 0;
    while (!check(reader, PROTO_TOK_EOF)) {
        switch (reader->current.type) {
            case PROTO_TOK_LPAREN: case PROTO_TOK_LBRACKET: case PROTO_TOK_LBRACE:
                depth++; break;
            case PROTO_TOK_RPAREN: case PROTO_TOK_RBRACKET: case PROTO_TOK_RBRACE:
                if (depth == 0) return;
                depth--; break;
            case PROTO_TOK_DOT:
                if (depth == 0) { advance(reader); return; }
                break;
            default: break;
        }
        advance(reader);
    }
}

static bool token_is(const ProtoToken *token, const char *word)
{
    return (int)strlen(word) == token->length &&
           memcmp(token->start, word, (size_t)token->length) == 0;
}

/* -------------------------------------------------------------- directives */

/* `@infix + 60 add.`  `@infixr ^ 80 raisedTo.`  `@prefix ~ not.` */
static void directive_operator(Reader *reader, bool infix, ProtoAssoc assoc)
{
    ProtoToken directive = reader->previous;

    if (!check(reader, PROTO_TOK_OPERATOR)) {
        error_here(reader,
                   "'%.*s' declares an operator, and an operator is written "
                   "out of + - * / < > = ! & ^ %% ~ ?",
                   directive.length, directive.start);
        return;
    }
    ProtoToken spelling = reader->current;
    advance(reader);

    int precedence = 0;
    if (infix) {
        /* Read as a plain number rather than as a Solveig literal: a directive
           is Proto talking to its own compiler, and `#60` there would be
           spelling a tag that has nowhere to go. */
        if (!check(reader, PROTO_TOK_FLOAT)) {
            error_here(reader, "'%.*s %.*s' needs a precedence, as a whole "
                               "number -- higher binds tighter",
                       directive.length, directive.start,
                       spelling.length, spelling.start);
            return;
        }
        for (int i = 0; i < reader->current.length; i++) {
            char c = reader->current.start[i];
            if (c < '0' || c > '9') {
                error_here(reader, "a precedence is a whole number");
                return;
            }
            precedence = precedence * 10 + (c - '0');
        }
        advance(reader);
    }

    /* Either the message it becomes, or `=>` and what it stands for.
     *
     * The template exists because a message cannot express a short-circuit:
     * Solveig's `and` takes a block, so `@infix && 30 and` compiles to
     * `a:and(b)` and is refused at run time. programs/ember wrote `:and` by
     * hand six times rather than declare an operator it could not declare. */
    ProtoToken selector = reader->current;
    ProtoNode *template = NULL;
    int form = -1;

    bool has_template = check(reader, PROTO_TOK_OPERATOR) &&
                        token_is(&reader->current, "=>");

    if (has_template) {
        advance(reader);
        template = expression(reader);
        if (template == NULL) return;
    } else if (!check(reader, PROTO_TOK_NAME)) {
        error_here(reader, "'%.*s %.*s' needs the message it becomes, or '=>' "
                           "and what it stands for",
                   directive.length, directive.start,
                   spelling.length, spelling.start);
        return;
    } else {
        advance(reader);
    }

    ProtoSpan where = { directive.span.source, directive.span.offset,
                      has_template
                          ? proto_node_extent(template).offset
                                + proto_node_extent(template).length
                                - directive.span.offset
                          : (selector.span.offset + selector.span.length)
                                - directive.span.offset };

    /* An operator with a template *is* a form, and is registered as one, so
       that substitution, hygiene, provenance and the trail all come from the
       expander rather than from a second implementation of each. */
    if (has_template) {
        static const char *const infix_names[] = { "left", "right" };
        static const char *const prefix_names[] = { "operand" };
        int count = infix ? 2 : 1;
        const char *const *names = infix ? infix_names : prefix_names;

        char **params = proto_alloc((size_t)count * sizeof *params);
        ProtoHoleKind *kinds = proto_alloc((size_t)count * sizeof *kinds);
        for (int i = 0; i < count; i++) {
            params[i] = proto_strndup(names[i], strlen(names[i]));
            kinds[i] = PROTO_HOLE_EXPRESSION;
        }

        const char *shadowed = shadowed_parameter(template, params, count);
        if (shadowed != NULL) {
            error_at(reader, proto_node_extent(template),
                     "this template binds '%s', which is what an operator "
                     "calls its operand", shadowed);
            for (int i = 0; i < count; i++) free(params[i]);
            free(params);
            free(kinds);
            proto_node_free(template);
            return;
        }

        form = proto_dialect_add_template(reader->dialect,
                                        spelling.start, spelling.length,
                                        params, kinds, count, template, where);
    }

    if (infix) {
        const ProtoInfix *clash = proto_dialect_add_infix(
            reader->dialect, spelling.start, spelling.length,
            has_template ? NULL : selector.start, selector.length,
            form, precedence, assoc, where);
        if (clash != NULL)
            collision(reader, "operator", clash->spelling,
                      spelling.span, clash->declared_at);
    } else {
        const ProtoPrefix *clash = proto_dialect_add_prefix(
            reader->dialect, spelling.start, spelling.length,
            has_template ? NULL : selector.start, selector.length,
            form, where);
        if (clash != NULL)
            collision(reader, "prefix operator", clash->spelling,
                      spelling.span, clash->declared_at);
    }
}

/* A template must not bind a name the form already gave a meaning to.
 *
 *     @syntax f(t) => { | t | t:add(#1) }.
 *
 * The `t` inside is two things at once -- the argument the caller passed, and
 * the block's own temporary -- and no rule about which wins is a rule anybody
 * should have to know. Refused at the declaration, where the author is, rather
 * than at the use, where they are not. */
static const char *shadowed_parameter(const ProtoNode *node,
                                      char **params, int param_count)
{
    for (int i = 0; i < node->param_count; i++)
        for (int j = 0; j < param_count; j++)
            if (strcmp(node->params[i], params[j]) == 0) return params[j];
    for (int i = 0; i < node->temp_count; i++)
        for (int j = 0; j < param_count; j++)
            if (strcmp(node->temps[i], params[j]) == 0) return params[j];

    for (int i = 0; i < node->count; i++) {
        const char *found = shadowed_parameter(node->children[i],
                                               params, param_count);
        if (found != NULL) return found;
    }
    return NULL;
}

/* `name` or `name: kind`, in a parameter list or inside a hole.
 *
 * The kind is optional and has to stay optional: a form that says nothing about
 * its holes must go on working, or every dialect written before this existed
 * breaks at once. */
static bool hole_kind(Reader *reader, ProtoToken name, ProtoHoleKind *kind)
{
    *kind = PROTO_HOLE_EXPRESSION;
    if (!match(reader, PROTO_TOK_COLON)) return true;

    if (!check(reader, PROTO_TOK_NAME)) {
        error_here(reader, "'%.*s:' needs what the hole will accept",
                   name.length, name.start);
        return false;
    }
    if (!proto_hole_kind_from(reader->current.start, reader->current.length,
                            kind)) {
        error_here(reader, "'%.*s' is not something a hole can ask for",
                   reader->current.length, reader->current.start);
        proto_note(reader->diag, reader->current.span,
                 "a hole accepts an expression, a name, a literal, a block "
                 "or a place");
        return false;
    }
    advance(reader);
    return true;
}

/* `<name>` in a pattern. Answers false having reported, or at a token that is
   not the start of a hole. */
static bool at_hole(Reader *reader)
{
    return check(reader, PROTO_TOK_OPERATOR) && token_is(&reader->current, "<");
}

/* Two forms under one word have to part company on a word, not on whether
 * there is a hole there.
 *
 *     @syntax on <what> do <body> => ... .
 *     @syntax on error do <body>  => ... .
 *
 * At position 1 one wants an expression and the other wants the word `error`,
 * and `on error do ...` is both of them. Preferring the literal would be a rule,
 * and it would be a rule nobody could see from either declaration. Refused at
 * the second one, where somebody is looking at the first. */
static void check_distinguishable(Reader *reader, ProtoToken name,
                                  const ProtoPatternPart *parts, int part_count)
{
    const ProtoMacro *others[32];
    int count = proto_dialect_forms(reader->dialect, name.start, name.length,
                                  others, 32);
    if (count > 32) count = 32;

    for (int i = 0; i < count; i++) {
        const ProtoMacro *other = others[i];
        if ((other->parts == NULL) != (parts == NULL)) {
            error_at(reader, name.span,
                     "'%s' is already a form of the other shape", other->name);
            proto_note(reader->diag, other->declared_at,
                     "declared here -- a name is either a call or patterns, "
                     "never both");
            return;
        }
        if (parts == NULL) continue;

        int limit = other->part_count < part_count ? other->part_count
                                                   : part_count;
        for (int at = 0; at < limit; at++) {
            if (other->parts[at].is_hole == parts[at].is_hole) {
                if (parts[at].is_hole) continue;
                if (strcmp(other->parts[at].text, parts[at].text) == 0) continue;
                break;                          /* two words, and they differ */
            }
            error_at(reader, name.span,
                     "this cannot be told apart from the other '%.*s'",
                     name.length, name.start);
            proto_note(reader->diag, other->declared_at,
                     "which has %s where this has %s",
                     other->parts[at].is_hole ? "a hole" : "a word",
                     parts[at].is_hole ? "a hole" : "a word");
            return;
        }
    }
}

/* `@syntax unless(test, body) => test:not:ifTrue({ body }).`
 * `@syntax unless <test> then <body> => test:not:ifTrue({ body }).`
 *
 * Two shapes, one meaning. The call is for a form that reads like an
 * application and the pattern for one that reads like a statement, and both
 * come out as the same thing: a list of holes and a template.
 *
 * The template is read here, under the header as it stands at this line, so a
 * form may use the operators and the forms declared above it and none of what
 * comes after. */
static void directive_syntax(Reader *reader)
{
    ProtoToken directive = reader->previous;

    if (!check(reader, PROTO_TOK_NAME)) {
        error_here(reader, "'@syntax' names the form it declares");
        return;
    }
    ProtoToken name = reader->current;
    advance(reader);

    char **params = NULL;
    ProtoHoleKind *kinds = NULL;
    int param_count = 0;
    ProtoPatternPart *parts = NULL;
    int part_count = 0;

    /* Anything that is not the call shape was an attempt at a pattern, whether
       or not a single part was read. `@syntax vec { <x> }` reads no parts at
       all -- `{` is neither a hole nor a word -- and the complaint it deserves
       is the one about patterns, not the one about a missing `=>`. */
    bool is_call = check(reader, PROTO_TOK_LPAREN);

    if (match(reader, PROTO_TOK_LPAREN)) {
        if (!check(reader, PROTO_TOK_RPAREN)) {
            do {
                if (!check(reader, PROTO_TOK_NAME)) {
                    error_here(reader, "a parameter of a form is a name");
                    goto give_up;
                }
                ProtoToken parameter = reader->current;
                advance(reader);

                ProtoHoleKind kind;
                if (!hole_kind(reader, parameter, &kind)) goto give_up;

                params = proto_realloc(params,
                                     (size_t)(param_count + 1) * sizeof *params);
                kinds = proto_realloc(kinds,
                                    (size_t)(param_count + 1) * sizeof *kinds);
                kinds[param_count] = kind;
                params[param_count++] = proto_strndup(parameter.start,
                                                    (size_t)parameter.length);
            } while (match(reader, PROTO_TOK_COMMA));
        }
        if (!consume(reader, PROTO_TOK_RPAREN, "')' after the parameters"))
            goto give_up;

    } else if (at_hole(reader) || check(reader, PROTO_TOK_NAME)) {
        /* A pattern. The leading word is part 0, so that matching a use is one
           walk over one array with nothing special about its first step. */
        parts = proto_alloc(sizeof *parts);
        parts[0].is_hole = false;
        parts[0].text = proto_strndup(name.start, (size_t)name.length);
        part_count = 1;

        while (at_hole(reader) || check(reader, PROTO_TOK_NAME)) {
            bool is_hole = at_hole(reader);
            ProtoToken word = reader->current;

            if (is_hole) {
                advance(reader);
                if (!check(reader, PROTO_TOK_NAME)) {
                    error_here(reader, "a hole is '<' and then the name the "
                                       "template knows it by");
                    goto give_up;
                }
                word = reader->current;
                advance(reader);

                ProtoHoleKind kind;
                if (!hole_kind(reader, word, &kind)) goto give_up;

                /* `>` and nothing else. `><` is one token, and it is what two
                   holes in a row look like to the lexer -- so the mistake is
                   named rather than left as a missing '>'. */
                if (check(reader, PROTO_TOK_OPERATOR) &&
                    reader->current.length > 1 &&
                    reader->current.start[0] == '>') {
                    error_here(reader, "'%.*s' is one operator here -- write "
                                       "'> <' with a space to end this hole "
                                       "and open the next",
                               reader->current.length, reader->current.start);
                    goto give_up;
                }
                if (!check(reader, PROTO_TOK_OPERATOR) ||
                    !token_is(&reader->current, ">")) {
                    error_here(reader, "expected '>' to close this hole");
                    goto give_up;
                }
                advance(reader);

                /* Two holes in a row, when the second one is delimited.
                 *
                 * The ban was justified as *no boundary between them*, and that
                 * was wrong: a block is a primary, consumed only where an
                 * operand may start, so an expression always stops at the `{`
                 * and the boundary is exactly findable. What the ban is really
                 * about is **greed** -- given `<a> <b>` and `f x + y`, the first
                 * hole takes the sum and the second finds nothing, and the split
                 * is not where anybody would put it.
                 *
                 * A delimited hole has no such problem: the split is at the
                 * brace, which is where a reader would put it too. So `if <c>
                 * <t: block>` is allowed and `if <c> <t>` is not, and what
                 * decides it is the kind -- which is why this could not have
                 * been relaxed before 0.6.0 gave holes kinds. */
                if (part_count > 0 && parts[part_count - 1].is_hole &&
                    kind != PROTO_HOLE_BLOCK) {
                    error_at(reader, word.span,
                             "a pattern needs a word between two holes, unless "
                             "the second is a block");
                    proto_note(reader->diag, word.span,
                             "'<%.*s: block>' would be read from its '{'; an "
                             "expression hole has no such edge and would take "
                             "everything the one before it left",
                             word.length, word.start);
                    goto give_up;
                }

                params = proto_realloc(params,
                                     (size_t)(param_count + 1) * sizeof *params);
                kinds = proto_realloc(kinds,
                                    (size_t)(param_count + 1) * sizeof *kinds);
                kinds[param_count] = kind;
                params[param_count++] = proto_strndup(word.start,
                                                    (size_t)word.length);
            } else {
                advance(reader);
            }

            parts = proto_realloc(parts,
                                (size_t)(part_count + 1) * sizeof *parts);
            parts[part_count].is_hole = is_hole;
            parts[part_count].text = proto_strndup(word.start,
                                                 (size_t)word.length);
            part_count++;
        }

        if (part_count == 1) {
            /* Only the leading word, which is the call shape's nullary form
               said a longer way. One spelling for one thing. */
            free(parts[0].text);
            free(parts);
            parts = NULL;
            part_count = 0;
        }
    }

    if (!check(reader, PROTO_TOK_OPERATOR) ||
        !token_is(&reader->current, "=>")) {
        /* Two messages, because a pattern that stopped early and a form with no
           `=>` at all are different mistakes and the first one is the common
           one. `@syntax mov <d> , <s>` is what somebody writing an assembler
           notation tries first -- programs/ember found it within a minute --
           and *needs '=>'* said nothing about why the comma was the problem. */
        if (!is_call && !check(reader, PROTO_TOK_EOF))
            error_here(reader,
                       "a pattern is made of names and <holes>, and %s is "
                       "neither", proto_token_type_name(reader->current.type));
        else
            error_here(reader,
                       "'@syntax %.*s' needs '=>' and then what it stands for",
                       name.length, name.start);
        if (!is_call && !check(reader, PROTO_TOK_EOF))
            proto_note(reader->diag, reader->current.span,
                     "a form wanting punctuation between its holes wants the "
                     "call shape: @syntax %.*s(...) => ... .",
                     name.length, name.start);
        goto give_up;
    }
    advance(reader);

    ProtoNode *template = expression(reader);
    if (template == NULL) goto give_up;

    const char *shadowed = shadowed_parameter(template, params, param_count);
    if (shadowed != NULL) {
        error_at(reader, proto_node_extent(template),
                 "this template binds '%s', which is already a parameter of "
                 "'%.*s'", shadowed, name.length, name.start);
        proto_node_free(template);
        goto give_up;
    }

    check_distinguishable(reader, name, parts, part_count);
    if (reader->panicked) {
        proto_node_free(template);
        goto give_up;
    }

    ProtoSpan where = { directive.span.source, directive.span.offset,
                      (name.span.offset + name.span.length)
                          - directive.span.offset };

    const ProtoMacro *clash = proto_dialect_add_macro(reader->dialect,
                                                  name.start, name.length,
                                                  params, kinds, param_count,
                                                  parts, part_count,
                                                  template, where);
    if (clash != NULL)
        collision(reader, "form", clash->name, name.span, clash->declared_at);
    return;

give_up:
    for (int i = 0; i < param_count; i++) free(params[i]);
    free(params);
    free(kinds);
    for (int i = 0; i < part_count; i++) free(parts[i].text);
    free(parts);
}

static void read_file(ProtoUnit *unit, const ProtoSource *source,
                      const ProtoSource *primary, ProtoDialect *dialect,
                      ProtoDiagnostics *diag, const Use *use, ProtoNode *module);

/* How deep `@use` may nest. Solveig allows an `@include` 64 deep and says so;
   a header that has gone further than that has gone wrong in a way a deeper
   limit would only postpone. */
#define PROTO_USE_LIMIT 64

/* `@use "arith.pro".`
 *
 * Reads that file's header into this module's dialect. The file is looked for
 * beside the one using it first, then in each `-I` directory, then in
 * PROTO_PATH -- the order Solveig's `@include` uses, because a program with
 * its dialect in the same folder should not need a command line to say so. */
static void directive_use(Reader *reader)
{
    ProtoToken directive = reader->previous;

    if (!check(reader, PROTO_TOK_STRING)) {
        error_here(reader, "'@use' takes the dialect file, in quotes");
        return;
    }
    ProtoToken quoted = reader->current;
    char *name = proto_strndup(quoted.start + 1, (size_t)quoted.length - 2);
    advance(reader);

    ProtoSpan at = { directive.span.source, directive.span.offset,
                   (quoted.span.offset + quoted.span.length)
                       - directive.span.offset };

    int depth = 0;
    for (const Use *use = reader->use; use != NULL; use = use->outer) depth++;
    if (depth >= PROTO_USE_LIMIT) {
        error_at(reader, at, "@use is nested more than %d deep", PROTO_USE_LIMIT);
        note_trail(reader);
        free(name);
        return;
    }

    char *path = proto_unit_resolve(reader->unit, reader->source, name);
    if (path == NULL) {
        error_at(reader, at, "cannot find '%s'", name);
        proto_note(reader->diag, at,
                 "looked beside %s, then in each -I directory, then in "
                 "PROTO_PATH", reader->source->path);
        note_trail(reader);
        free(name);
        return;
    }

    /* A file still being read is a file using itself, however many hops away.
       Caught here rather than left to the load-once rule below, which would
       terminate and then report the operators as undeclared -- true, and no
       help at all in finding out why. */
    for (const Use *use = reader->use; use != NULL; use = use->outer)
        if (strcmp(use->source->path, path) == 0) {
            error_at(reader, at, "'%s' is already being read -- @use is a cycle",
                     path);
            note_trail(reader);
            free(path);
            free(name);
            return;
        }

    /* Read once. Two dialects that both use a third meet it once, so its
       declarations are not added twice and do not collide with themselves. */
    if (proto_unit_loaded(reader->unit, path) != NULL) {
        free(path);
        free(name);
        return;
    }

    const ProtoSource *source = proto_unit_read(reader->unit, path);
    if (source == NULL) {
        error_at(reader, at, "cannot read '%s'", path);
        note_trail(reader);
        free(path);
        free(name);
        return;
    }

    Use use = { reader->use, source, at };
    read_file(reader->unit, source, reader->primary, reader->dialect,
              reader->diag, &use, NULL);

    free(path);
    free(name);
}

/* Answers false at the first token that is not a header directive. */
static bool header_directive(Reader *reader)
{
    if (!check(reader, PROTO_TOK_DIRECTIVE)) return false;

    ProtoToken directive = reader->current;
    if (token_is(&directive, "@include")) return false;   /* a statement */

    advance(reader);

    if (token_is(&directive, "@infix")) {
        directive_operator(reader, true, PROTO_ASSOC_LEFT);
    } else if (token_is(&directive, "@infixr")) {
        directive_operator(reader, true, PROTO_ASSOC_RIGHT);
    } else if (token_is(&directive, "@prefix")) {
        directive_operator(reader, false, PROTO_ASSOC_LEFT);
    } else if (token_is(&directive, "@syntax")) {
        directive_syntax(reader);
    } else if (token_is(&directive, "@use")) {
        directive_use(reader);
    } else {
        error_at(reader, directive.span,
                 "'%.*s' is not a directive Proto knows",
                 directive.length, directive.start);
        proto_note(reader->diag, directive.span,
                 "the header takes @use, @infix, @infixr, @prefix "
                 "and @syntax");
    }

    if (!reader->panicked) consume(reader, PROTO_TOK_DOT, "'.' after a directive");
    if (reader->panicked) synchronize(reader);
    return true;
}

/* ------------------------------------------------------------- expressions */

static ProtoNode *block(Reader *reader, ProtoToken open);

/* Whether what follows is `NAME { "," NAME } "|"`, without consuming it.
 *
 * The whole reason a block's parameters and its body can be told apart, and
 * therefore the one place the reader looks ahead. Solveig's grammar settles it
 * the same way -- see docs/GRAMMAR.md there, "the leading `|` of a temporary
 * list is what tells the two apart". */
static bool looks_like_names_then_bar(Reader *reader)
{
    ProtoLexer saved_lexer = reader->lexer;
    ProtoToken saved_current = reader->current;
    ProtoToken saved_previous = reader->previous;
    bool saved_panicked = reader->panicked;
    int saved_errors = reader->diag->errors;

    bool matched = false;
    for (;;) {
        if (!check(reader, PROTO_TOK_NAME)) break;
        advance(reader);
        if (match(reader, PROTO_TOK_COMMA)) continue;
        matched = check(reader, PROTO_TOK_BAR);
        break;
    }

    reader->lexer = saved_lexer;
    reader->current = saved_current;
    reader->previous = saved_previous;
    reader->panicked = saved_panicked;
    reader->diag->errors = saved_errors;
    return matched;
}

/* A use of a pattern form, matched against every form under that word at once.
 *
 * No backtracking, and none needed. A hole is parsed once and shared by every
 * candidate still standing, so two forms can only part company at a word -- and
 * the declaration refused any pair that would have parted company anywhere
 * else. So each step either reads an expression or looks at one token, and the
 * candidates that do not agree with it are dropped.
 *
 * Which is how `if <c> then <a>` and `if <c> then <a> else <b>` live under one
 * word: after the second hole the short one has ended and the long one wants
 * `else`, and the next token settles it. */
static ProtoNode *pattern_use(Reader *reader, ProtoToken name)
{
    const ProtoMacro *alive[32];
    int count = proto_dialect_forms(reader->dialect, name.start, name.length,
                                  alive, 32);
    if (count > 32) count = 32;

    ProtoNode *node = proto_node_leaf(PROTO_NODE_MACRO, name.span,
                                  name.start, name.length);
    int position = 1;

    for (;;) {
        bool wants_hole = false;
        int pending = 0;
        for (int i = 0; i < count; i++)
            if (alive[i]->part_count > position) {
                pending++;
                if (alive[i]->parts[position].is_hole) wants_hole = true;
            }

        if (pending == 0) break;                /* every survivor has ended */

        if (wants_hole) {
            /* Every pending candidate wants one here, the declaration having
               refused any that disagreed. A candidate that ended earlier cannot
               still be standing, since a hole never follows a hole. */
            int kept = 0;
            for (int i = 0; i < count; i++)
                if (alive[i]->part_count > position) alive[kept++] = alive[i];
            count = kept;

            ProtoNode *argument = expression(reader);
            if (argument == NULL) { proto_node_free(node); return NULL; }
            proto_node_add(node, argument);
            position++;
            continue;
        }

        /* They want words. The token decides which, and a candidate that has
           ended here is what a token matching none of them falls back to. */
        int kept = 0;
        if (check(reader, PROTO_TOK_NAME))
            for (int i = 0; i < count; i++)
                if (alive[i]->part_count > position &&
                    (int)strlen(alive[i]->parts[position].text)
                        == reader->current.length &&
                    memcmp(alive[i]->parts[position].text,
                           reader->current.start,
                           (size_t)reader->current.length) == 0)
                    alive[kept++] = alive[i];

        if (kept > 0) {
            count = kept;
            advance(reader);
            position++;
            continue;
        }

        for (int i = 0; i < count; i++)
            if (alive[i]->part_count == position) alive[kept++] = alive[i];

        if (kept == 0) {
            /* Deduplicated: two forms wanting the same word here is the
               ordinary case -- it is where they have not parted company yet --
               and "expected 'then' or 'then'" is not a sentence. */
            char expected[256];
            int written = 0;
            int listed = 0;
            for (int i = 0; i < count && written < (int)sizeof expected - 8; i++) {
                const char *word = alive[i]->parts[position].text;
                bool seen = false;
                for (int j = 0; j < i; j++)
                    if (strcmp(alive[j]->parts[position].text, word) == 0)
                        seen = true;
                if (seen) continue;
                written += snprintf(expected + written,
                                    sizeof expected - (size_t)written,
                                    "%s'%s'", listed++ > 0 ? " or " : "", word);
            }
            error_here(reader, "expected %s here, in the form '%.*s'",
                       expected, name.length, name.start);
            proto_note(reader->diag, alive[0]->declared_at, "declared here");
            proto_node_free(node);
            return NULL;
        }
        count = kept;
        break;
    }

    /* Exactly one, because two forms spelled the same way are one form and the
       collision rule already said so. */
    node->form = proto_dialect_index_of(reader->dialect, alive[0]);
    return node;
}

/* A use of a declared form. The arity is known here, so it is checked here --
   at the call, with the declaration pointed at, rather than during expansion
   where neither is in front of the reader. */
static ProtoNode *macro_use(Reader *reader, ProtoToken name, const ProtoMacro *macro)
{
    if (macro->parts != NULL) return pattern_use(reader, name);

    ProtoNode *node = proto_node_leaf(PROTO_NODE_MACRO, name.span,
                                  name.start, name.length);
    node->form = proto_dialect_index_of(reader->dialect, macro);

    if (macro->param_count == 0) {
        if (check(reader, PROTO_TOK_LPAREN)) {
            error_here(reader, "'%s' takes no arguments", macro->name);
            proto_note(reader->diag, macro->declared_at, "declared here");
            proto_node_free(node);
            return NULL;
        }
        return node;
    }

    if (!consume(reader, PROTO_TOK_LPAREN, "'(' and the arguments")) {
        proto_note(reader->diag, macro->declared_at, "'%s' is declared here",
                 macro->name);
        proto_node_free(node);
        return NULL;
    }

    if (!check(reader, PROTO_TOK_RPAREN)) {
        do {
            ProtoNode *argument = expression(reader);
            if (argument == NULL) { proto_node_free(node); return NULL; }
            proto_node_add(node, argument);
        } while (match(reader, PROTO_TOK_COMMA));
    }
    if (!consume(reader, PROTO_TOK_RPAREN, "')' after the arguments")) {
        proto_node_free(node);
        return NULL;
    }

    if (node->count != macro->param_count) {
        error_at(reader, proto_node_extent(node),
                 "'%s' takes %d argument%s, and %d %s given",
                 macro->name, macro->param_count,
                 macro->param_count == 1 ? "" : "s",
                 node->count, node->count == 1 ? "was" : "were");
        proto_note(reader->diag, macro->declared_at, "declared here");
        proto_node_free(node);
        return NULL;
    }
    return node;
}

static ProtoNode *primary(Reader *reader)
{
    ProtoToken token = reader->current;

    switch (token.type) {
        case PROTO_TOK_INTEGER:
            advance(reader);
            /* Without the '#', which the emitter puts back. The tag is
               Solveig's spelling of the type, not part of the number. */
            return proto_node_leaf(PROTO_NODE_INTEGER, token.span,
                                 token.start + 1, token.length - 1);
        case PROTO_TOK_FLOAT:
            advance(reader);
            return proto_node_leaf(PROTO_NODE_FLOAT, token.span,
                                 token.start, token.length);
        case PROTO_TOK_STRING:
            advance(reader);
            /* Inside the quotes; escapes still as written. */
            return proto_node_leaf(PROTO_NODE_STRING, token.span,
                                 token.start + 1, token.length - 2);
        case PROTO_TOK_SYMBOL:
            advance(reader);
            return proto_node_leaf(PROTO_NODE_SYMBOL, token.span,
                                 token.start + 1, token.length - 1);

        case PROTO_TOK_NAME: {
            /* A declared form wins over everything else a name could be, which
               is the module's own decision: it wrote the declaration. */
            const ProtoMacro *macro = proto_dialect_macro(reader->dialect,
                                                      token.start, token.length);
            advance(reader);
            if (macro != NULL) return macro_use(reader, token, macro);

            /* `f(x)` is `x:f` -- prefix application is a send to its argument,
               which is Solveig's rule and not a second one. */
            if (check(reader, PROTO_TOK_LPAREN)) {
                advance(reader);
                ProtoNode *argument = expression(reader);
                if (argument == NULL) return NULL;
                if (!consume(reader, PROTO_TOK_RPAREN, "')'")) {
                    proto_node_free(argument);
                    return NULL;
                }
                ProtoNode *send = proto_node_leaf(PROTO_NODE_SEND, token.span,
                                              token.start, token.length);
                proto_node_add(send, argument);
                return send;
            }
            return proto_node_leaf(PROTO_NODE_NAME, token.span,
                                 token.start, token.length);
        }

        case PROTO_TOK_LPAREN: {
            advance(reader);
            ProtoNode *group = proto_node_new(PROTO_NODE_SEQUENCE, token.span);
            do {
                if (check(reader, PROTO_TOK_RPAREN)) break;
                ProtoNode *inner = expression(reader);
                if (inner == NULL) { proto_node_free(group); return NULL; }
                proto_node_add(group, inner);
            } while (match(reader, PROTO_TOK_DOT));
            if (!consume(reader, PROTO_TOK_RPAREN, "')'")) {
                proto_node_free(group);
                return NULL;
            }
            return group;
        }

        case PROTO_TOK_LBRACKET: {
            advance(reader);
            ProtoNode *array = proto_node_new(PROTO_NODE_ARRAY, token.span);
            if (!check(reader, PROTO_TOK_RBRACKET)) {
                do {
                    ProtoNode *element = expression(reader);
                    if (element == NULL) { proto_node_free(array); return NULL; }
                    proto_node_add(array, element);
                } while (match(reader, PROTO_TOK_COMMA));
            }
            if (!consume(reader, PROTO_TOK_RBRACKET, "']'")) {
                proto_node_free(array);
                return NULL;
            }
            return array;
        }

        case PROTO_TOK_LBRACE:
            advance(reader);
            return block(reader, token);

        default:
            error_here(reader, "expected an expression, found %s",
                       proto_token_type_name(token.type));
            return NULL;
    }
}

static ProtoNode *block(Reader *reader, ProtoToken open)
{
    ProtoNode *node = proto_node_new(PROTO_NODE_BLOCK, open.span);

    if (looks_like_names_then_bar(reader)) {
        do {
            proto_node_add_param(node, reader->current.start,
                               reader->current.length);
            advance(reader);
        } while (match(reader, PROTO_TOK_COMMA));
        advance(reader);                                  /* the '|' */
    }

    /* Temporaries carry a leading bar as well as a trailing one, which is what
       distinguishes `{ | a | a }` from `{ a | a }`. */
    if (check(reader, PROTO_TOK_BAR)) {
        advance(reader);
        if (!check(reader, PROTO_TOK_BAR)) {
            do {
                if (!check(reader, PROTO_TOK_NAME)) {
                    error_here(reader, "a temporary is a name");
                    proto_node_free(node);
                    return NULL;
                }
                proto_node_add_temp(node, reader->current.start,
                                  reader->current.length);
                advance(reader);
            } while (match(reader, PROTO_TOK_COMMA));
        }
        if (!consume(reader, PROTO_TOK_BAR, "'|' after the temporaries")) {
            proto_node_free(node);
            return NULL;
        }
    }

    while (!check(reader, PROTO_TOK_RBRACE) && !check(reader, PROTO_TOK_EOF)) {
        ProtoNode *inner = statement(reader);
        if (inner == NULL) {
            proto_node_free(node);
            return NULL;
        }
        proto_node_add(node, inner);
    }

    if (!consume(reader, PROTO_TOK_RBRACE, "'}' to close this block")) {
        proto_note(reader->diag, open.span, "the block opened here");
        proto_node_free(node);
        return NULL;
    }
    return node;
}

/* `receiver:selector` and `receiver:selector(a, b)`, chaining left to right. */
static ProtoNode *postfix(Reader *reader)
{
    ProtoNode *left = primary(reader);
    if (left == NULL) return NULL;

    while (check(reader, PROTO_TOK_COLON)) {
        advance(reader);
        if (!check(reader, PROTO_TOK_NAME)) {
            error_here(reader, "':' sends a message, and a message is a name");
            proto_node_free(left);
            return NULL;
        }
        ProtoToken selector = reader->current;
        advance(reader);

        ProtoNode *send = proto_node_leaf(PROTO_NODE_SEND, selector.span,
                                      selector.start, selector.length);
        proto_node_add(send, left);

        if (match(reader, PROTO_TOK_LPAREN)) {
            if (!check(reader, PROTO_TOK_RPAREN)) {
                do {
                    ProtoNode *argument = expression(reader);
                    if (argument == NULL) { proto_node_free(send); return NULL; }
                    proto_node_add(send, argument);
                } while (match(reader, PROTO_TOK_COMMA));
            }
            if (!consume(reader, PROTO_TOK_RPAREN, "')' after the arguments")) {
                proto_node_free(send);
                return NULL;
            }
        }
        left = send;
    }
    return left;
}

static ProtoNode *unary(Reader *reader)
{
    if (check(reader, PROTO_TOK_OPERATOR)) {
        ProtoToken op = reader->current;
        const ProtoPrefix *prefix = proto_dialect_prefix(reader->dialect,
                                                     op.start, op.length);
        if (prefix == NULL) {
            error_at(reader, op.span,
                     "'%.*s' has no meaning in this module",
                     op.length, op.start);
            proto_note(reader->diag, op.span,
                     "a module declares its operators in its header: "
                     "@prefix %.*s <message>.", op.length, op.start);
            return NULL;
        }
        advance(reader);
        ProtoNode *operand = unary(reader);
        if (operand == NULL) return NULL;

        if (prefix->form >= 0) {
            ProtoNode *use = proto_node_leaf(PROTO_NODE_MACRO, op.span,
                                         prefix->spelling,
                                         (int)strlen(prefix->spelling));
            use->form = prefix->form;
            proto_node_add(use, operand);
            return use;
        }

        ProtoNode *send = proto_node_leaf(PROTO_NODE_SEND, op.span,
                                      prefix->selector,
                                      (int)strlen(prefix->selector));
        proto_node_add(send, operand);
        return send;
    }
    return postfix(reader);
}

/* Precedence climbing over whatever the header declared.
 *
 * Operators are the extension point 0.1.0 ships because a precedence table
 * composes: adding an operator cannot change what an expression that does not
 * use it already meant. A general grammar rule can, and silently, which is why
 * that one waits for a design rather than an implementation. */
static ProtoNode *infix(Reader *reader, int minimum)
{
    ProtoNode *left = unary(reader);
    if (left == NULL) return NULL;

    while (check(reader, PROTO_TOK_OPERATOR)) {
        ProtoToken op = reader->current;
        const ProtoInfix *entry = proto_dialect_infix(reader->dialect,
                                                  op.start, op.length);
        if (entry == NULL) {
            error_at(reader, op.span, "'%.*s' has no meaning in this module",
                     op.length, op.start);
            proto_note(reader->diag, op.span,
                     "a module declares its operators in its header: "
                     "@infix %.*s <precedence> <message>.",
                     op.length, op.start);
            proto_node_free(left);
            return NULL;
        }
        if (entry->precedence < minimum) break;

        advance(reader);
        int next = entry->assoc == PROTO_ASSOC_LEFT ? entry->precedence + 1
                                                  : entry->precedence;
        ProtoNode *right = infix(reader, next);
        if (right == NULL) { proto_node_free(left); return NULL; }

        /* The span is the operator's. What the node covers is worked out by
           proto_node_extent when something needs to underline the whole of it. */
        ProtoNode *made;
        if (entry->form >= 0) {
            made = proto_node_leaf(PROTO_NODE_MACRO, op.span, entry->spelling,
                                 (int)strlen(entry->spelling));
            made->form = entry->form;
        } else {
            made = proto_node_leaf(PROTO_NODE_SEND, op.span, entry->selector,
                                 (int)strlen(entry->selector));
        }
        proto_node_add(made, left);
        proto_node_add(made, right);
        left = made;
    }
    return left;
}

static bool assignable(const ProtoNode *node)
{
    /* A name, or a slot: `x := v` and `r:name := v`. A send with arguments is
       not a place, and neither is anything else. */
    return node->kind == PROTO_NODE_NAME ||
           (node->kind == PROTO_NODE_SEND && node->count == 1);
}

static ProtoNode *expression(Reader *reader)
{
    ProtoNode *left = infix(reader, 0);
    if (left == NULL) return NULL;

    if (check(reader, PROTO_TOK_ASSIGN)) {
        ProtoToken assign = reader->current;
        if (!assignable(left)) {
            error_at(reader, proto_node_extent(left),
                     "this cannot be assigned to");
            proto_node_free(left);
            return NULL;
        }
        advance(reader);
        ProtoNode *value = expression(reader);
        if (value == NULL) { proto_node_free(left); return NULL; }

        ProtoNode *node = proto_node_new(PROTO_NODE_ASSIGN, assign.span);
        proto_node_add(node, left);
        proto_node_add(node, value);
        return node;
    }
    return left;
}

/* ------------------------------------------------------------- statements */

static ProtoNode *statement(Reader *reader)
{
    /* `@include "text.sol".` is Solveig's directive and stays Solveig's: it is
       carried through to the generated file unread. Proto has nothing to say
       about it yet, and inventing a second include with different rules while
       the first one works is how two of them end up existing. */
    if (check(reader, PROTO_TOK_DIRECTIVE) &&
        token_is(&reader->current, "@include")) {
        ProtoToken directive = reader->current;
        advance(reader);
        if (!check(reader, PROTO_TOK_STRING)) {
            error_here(reader, "'@include' takes the file name, in quotes");
            return NULL;
        }
        ProtoNode *node = proto_node_leaf(PROTO_NODE_INCLUDE, directive.span,
                                      reader->current.start + 1,
                                      reader->current.length - 2);
        advance(reader);
        if (!consume(reader, PROTO_TOK_DOT, "'.' after the include")) {
            proto_node_free(node);
            return NULL;
        }
        return node;
    }

    ProtoNode *node = expression(reader);
    if (node == NULL) return NULL;

    /* A separator between two, optional after the last -- in a file, in a
       block and in a group alike, which is Solveig's rule. */
    if (!match(reader, PROTO_TOK_DOT) &&
        !check(reader, PROTO_TOK_RBRACE) && !check(reader, PROTO_TOK_EOF)) {
        error_here(reader, "expected '.' after this statement, found %s",
                   proto_token_type_name(reader->current.type));
        proto_node_free(node);
        return NULL;
    }
    return node;
}

/* One file, header first and then whatever the caller allows after it.
 *
 * `module` is where statements go, and NULL means there is nowhere for them --
 * a dialect file, which holds directives and nothing else. That split is what
 * keeps the two kinds of file from becoming one kind with a rule about which
 * half is read: a dialect provides syntax, and Solveig's own `@include`
 * provides code, so there is no third thing for a `.pro` to be. */
static void read_file(ProtoUnit *unit, const ProtoSource *source,
                      const ProtoSource *primary, ProtoDialect *dialect,
                      ProtoDiagnostics *diag, const Use *use, ProtoNode *module)
{
    Reader reader;
    proto_lexer_init(&reader.lexer, source);
    reader.source = source;
    reader.primary = primary;
    reader.unit = unit;
    reader.use = use;
    reader.dialect = dialect;
    reader.diag = diag;
    reader.panicked = false;
    reader.previous.type = PROTO_TOK_EOF;
    reader.current.type = PROTO_TOK_EOF;
    reader.current.span = PROTO_SPAN_NONE;
    reader.current.start = source->text;
    reader.current.length = 0;
    reader.current.message = NULL;
    advance(&reader);

    while (header_directive(&reader)) { }

    if (module == NULL) {
        if (!check(&reader, PROTO_TOK_EOF)) {
            error_at(&reader, reader.current.span,
                     "a dialect file holds directives, and this is a statement");
            proto_note(diag, reader.current.span,
                     "code goes in a .sol beside it, reached with "
                     "@include -- see the README, 'A dialect is a file'");
            note_trail(&reader);
        }
        return;
    }

    while (!check(&reader, PROTO_TOK_EOF)) {
        /* A header directive down here is the one mistake worth naming
           precisely, because the file looks right and the operator quietly did
           not exist for the statements above it. */
        if (check(&reader, PROTO_TOK_DIRECTIVE) &&
            !token_is(&reader.current, "@include")) {
            error_at(&reader, reader.current.span,
                     "a module settles its syntax before its first statement");
            proto_note(diag, reader.current.span,
                     "move this above the code, with the other directives");
            synchronize(&reader);
            continue;
        }

        /* Where the statement began, so that the loop can prove it moved.
         *
         * `synchronize` stops *at* a closing bracket without consuming it,
         * which is right when something above is waiting to consume it and
         * wrong here, where nothing is: a `)` that belongs to nobody would be
         * read as a statement, fail, be synchronised to, and be read again.
         * That was an infinite loop for every version up to 0.5.0, reachable
         * from any error that leaves an unmatched closer at this level --
         * `f(#1 % #2)` with `%` undeclared is enough.
         *
         * Guarding the loop rather than teaching `synchronize` about its
         * caller, because the property wanted is the loop's: a pass that
         * reports an error must consume something, whatever the error was. */
        ProtoSpan began = reader.current.span;

        ProtoNode *node = statement(&reader);
        if (node == NULL) {
            synchronize(&reader);
            if (reader.current.span.offset == began.offset &&
                reader.current.span.source == began.source &&
                !check(&reader, PROTO_TOK_EOF))
                advance(&reader);
            continue;
        }
        proto_node_add(module, node);
    }
}

ProtoNode *proto_read(const ProtoSource *source, ProtoUnit *unit,
                  ProtoDialect *dialect, ProtoDiagnostics *diag)
{
    ProtoNode *module = proto_node_new(PROTO_NODE_SEQUENCE, PROTO_SPAN_NONE);
    Use use = { NULL, source, PROTO_SPAN_NONE };

    read_file(unit, source, source, dialect, diag, &use, module);

    if (diag->errors > 0) {
        proto_node_free(module);
        return NULL;
    }
    return module;
}
