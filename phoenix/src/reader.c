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

#include "phoenix/lex.h"
#include "phoenix/reader.h"

typedef struct {
    PhxLexer lexer;
    PhxToken current;
    PhxToken previous;
    const PhxSource *source;
    PhxDialect *dialect;
    PhxDiagnostics *diag;
    bool panicked;          /* suppresses the cascade after one error */
} Reader;

static PhxNode *expression(Reader *reader);
static PhxNode *statement(Reader *reader);

/* ------------------------------------------------------------------ tokens */

static void advance(Reader *reader)
{
    reader->previous = reader->current;
    for (;;) {
        reader->current = phx_lexer_next(&reader->lexer);
        if (reader->current.type != PHX_TOK_ERROR) return;
        if (!reader->panicked) {
            phx_error(reader->diag, reader->current.span, "%s",
                      reader->current.message);
            reader->panicked = true;
        } else {
            reader->diag->errors++;
        }
    }
}

static bool check(Reader *reader, PhxTokenType type)
{
    return reader->current.type == type;
}

static bool match(Reader *reader, PhxTokenType type)
{
    if (!check(reader, type)) return false;
    advance(reader);
    return true;
}

static void error_here(Reader *reader, const char *format, ...);

static bool consume(Reader *reader, PhxTokenType type, const char *what)
{
    if (match(reader, type)) return true;
    if (!reader->panicked) {
        phx_error(reader->diag, reader->current.span, "expected %s, found %s",
                  what, phx_token_type_name(reader->current.type));
        reader->panicked = true;
    }
    return false;
}

static void error_at(Reader *reader, PhxSpan span, const char *format, ...)
{
    if (reader->panicked) return;
    va_list args;
    va_start(args, format);
    /* phx_error is variadic itself, so the message is formatted here and
       handed over whole. One buffer rather than a second vararg entry point:
       diag.h says every error takes a span and nothing else, and keeping that
       true is worth a fixed buffer. */
    char message[512];
    vsnprintf(message, sizeof message, format, args);
    va_end(args);
    phx_error(reader->diag, span, "%s", message);
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

/* After an error, skip to just past the next statement end at the outermost
   level, so a second mistake in the same file is still reported. */
static void synchronize(Reader *reader)
{
    reader->panicked = false;
    int depth = 0;
    while (!check(reader, PHX_TOK_EOF)) {
        switch (reader->current.type) {
            case PHX_TOK_LPAREN: case PHX_TOK_LBRACKET: case PHX_TOK_LBRACE:
                depth++; break;
            case PHX_TOK_RPAREN: case PHX_TOK_RBRACKET: case PHX_TOK_RBRACE:
                if (depth == 0) return;
                depth--; break;
            case PHX_TOK_DOT:
                if (depth == 0) { advance(reader); return; }
                break;
            default: break;
        }
        advance(reader);
    }
}

static bool token_is(const PhxToken *token, const char *word)
{
    return (int)strlen(word) == token->length &&
           memcmp(token->start, word, (size_t)token->length) == 0;
}

/* -------------------------------------------------------------- directives */

/* `@infix + 60 add.`  `@infixr ^ 80 raisedTo.`  `@prefix ~ not.` */
static void directive_operator(Reader *reader, bool infix, PhxAssoc assoc)
{
    PhxToken directive = reader->previous;

    if (!check(reader, PHX_TOK_OPERATOR)) {
        error_here(reader,
                   "'%.*s' declares an operator, and an operator is written "
                   "out of + - * / < > = ! & ^ %% ~ ?",
                   directive.length, directive.start);
        return;
    }
    PhxToken spelling = reader->current;
    advance(reader);

    int precedence = 0;
    if (infix) {
        /* Read as a plain number rather than as a Solveig literal: a directive
           is Phoenix talking to its own compiler, and `#60` there would be
           spelling a tag that has nowhere to go. */
        if (!check(reader, PHX_TOK_FLOAT)) {
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

    if (!check(reader, PHX_TOK_NAME)) {
        error_here(reader, "'%.*s %.*s' needs the message it becomes",
                   directive.length, directive.start,
                   spelling.length, spelling.start);
        return;
    }
    PhxToken selector = reader->current;
    advance(reader);

    PhxSpan where = { directive.span.offset,
                      (selector.span.offset + selector.span.length)
                          - directive.span.offset };

    if (infix) {
        const PhxInfix *clash = phx_dialect_add_infix(
            reader->dialect, spelling.start, spelling.length,
            selector.start, selector.length, precedence, assoc, where);
        if (clash != NULL) {
            error_at(reader, spelling.span,
                     "'%s' has already been declared in this module",
                     clash->spelling);
            phx_note(reader->diag, clash->declared_at, "as '%s', here",
                     clash->selector);
        }
    } else {
        const PhxPrefix *clash = phx_dialect_add_prefix(
            reader->dialect, spelling.start, spelling.length,
            selector.start, selector.length, where);
        if (clash != NULL) {
            error_at(reader, spelling.span,
                     "prefix '%s' has already been declared in this module",
                     clash->spelling);
            phx_note(reader->diag, clash->declared_at, "as '%s', here",
                     clash->selector);
        }
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
static const char *shadowed_parameter(const PhxNode *node,
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

/* `@syntax unless(test, body) => test:not:ifTrue({ body }).`
 *
 * The template is read here, under the header as it stands at this line, so a
 * form may use the operators and the forms declared above it and none of what
 * comes after. */
static void directive_syntax(Reader *reader)
{
    PhxToken directive = reader->previous;

    if (!check(reader, PHX_TOK_NAME)) {
        error_here(reader, "'@syntax' names the form it declares");
        return;
    }
    PhxToken name = reader->current;
    advance(reader);

    char **params = NULL;
    int param_count = 0;

    if (match(reader, PHX_TOK_LPAREN)) {
        if (!check(reader, PHX_TOK_RPAREN)) {
            do {
                if (!check(reader, PHX_TOK_NAME)) {
                    error_here(reader, "a parameter of a form is a name");
                    goto give_up;
                }
                params = phx_realloc(params,
                                     (size_t)(param_count + 1) * sizeof *params);
                params[param_count++] = phx_strndup(reader->current.start,
                                                    (size_t)reader->current.length);
                advance(reader);
            } while (match(reader, PHX_TOK_COMMA));
        }
        if (!consume(reader, PHX_TOK_RPAREN, "')' after the parameters"))
            goto give_up;
    }

    if (!check(reader, PHX_TOK_OPERATOR) ||
        !token_is(&reader->current, "=>")) {
        error_here(reader, "'@syntax %.*s' needs '=>' and then what it stands for",
                   name.length, name.start);
        goto give_up;
    }
    advance(reader);

    PhxNode *template = expression(reader);
    if (template == NULL) goto give_up;

    const char *shadowed = shadowed_parameter(template, params, param_count);
    if (shadowed != NULL) {
        error_at(reader, phx_node_extent(template),
                 "this template binds '%s', which is already a parameter of "
                 "'%.*s'", shadowed, name.length, name.start);
        phx_node_free(template);
        goto give_up;
    }

    PhxSpan where = { directive.span.offset,
                      (name.span.offset + name.span.length)
                          - directive.span.offset };

    const PhxMacro *clash = phx_dialect_add_macro(reader->dialect,
                                                  name.start, name.length,
                                                  params, param_count,
                                                  template, where);
    if (clash != NULL) {
        error_at(reader, name.span,
                 "'%s' has already been declared in this module", clash->name);
        phx_note(reader->diag, clash->declared_at, "here");
    }
    return;

give_up:
    for (int i = 0; i < param_count; i++) free(params[i]);
    free(params);
}

/* Answers false at the first token that is not a header directive. */
static bool header_directive(Reader *reader)
{
    if (!check(reader, PHX_TOK_DIRECTIVE)) return false;

    PhxToken directive = reader->current;
    if (token_is(&directive, "@include")) return false;   /* a statement */

    advance(reader);

    if (token_is(&directive, "@language")) {
        if (!check(reader, PHX_TOK_NAME)) {
            error_here(reader, "'@language' names the dialect this module "
                               "is written in");
        } else if (reader->dialect->name != NULL) {
            error_at(reader, directive.span,
                     "this module has already declared its language");
            phx_note(reader->diag, reader->dialect->declared_at, "as '%s', here",
                     reader->dialect->name);
            advance(reader);
        } else {
            reader->dialect->name = phx_strndup(reader->current.start,
                                                (size_t)reader->current.length);
            reader->dialect->declared_at = directive.span;
            advance(reader);
        }
    } else if (token_is(&directive, "@infix")) {
        directive_operator(reader, true, PHX_ASSOC_LEFT);
    } else if (token_is(&directive, "@infixr")) {
        directive_operator(reader, true, PHX_ASSOC_RIGHT);
    } else if (token_is(&directive, "@prefix")) {
        directive_operator(reader, false, PHX_ASSOC_LEFT);
    } else if (token_is(&directive, "@syntax")) {
        directive_syntax(reader);
    } else {
        error_at(reader, directive.span,
                 "'%.*s' is not a directive Phoenix knows",
                 directive.length, directive.start);
        phx_note(reader->diag, directive.span,
                 "the header takes @language, @infix, @infixr, @prefix "
                 "and @syntax");
    }

    if (!reader->panicked) consume(reader, PHX_TOK_DOT, "'.' after a directive");
    if (reader->panicked) synchronize(reader);
    return true;
}

/* ------------------------------------------------------------- expressions */

static PhxNode *block(Reader *reader, PhxToken open);

/* Whether what follows is `NAME { "," NAME } "|"`, without consuming it.
 *
 * The whole reason a block's parameters and its body can be told apart, and
 * therefore the one place the reader looks ahead. Solveig's grammar settles it
 * the same way -- see docs/GRAMMAR.md there, "the leading `|` of a temporary
 * list is what tells the two apart". */
static bool looks_like_names_then_bar(Reader *reader)
{
    PhxLexer saved_lexer = reader->lexer;
    PhxToken saved_current = reader->current;
    PhxToken saved_previous = reader->previous;
    bool saved_panicked = reader->panicked;
    int saved_errors = reader->diag->errors;

    bool matched = false;
    for (;;) {
        if (!check(reader, PHX_TOK_NAME)) break;
        advance(reader);
        if (match(reader, PHX_TOK_COMMA)) continue;
        matched = check(reader, PHX_TOK_BAR);
        break;
    }

    reader->lexer = saved_lexer;
    reader->current = saved_current;
    reader->previous = saved_previous;
    reader->panicked = saved_panicked;
    reader->diag->errors = saved_errors;
    return matched;
}

/* A use of a declared form. The arity is known here, so it is checked here --
   at the call, with the declaration pointed at, rather than during expansion
   where neither is in front of the reader. */
static PhxNode *macro_use(Reader *reader, PhxToken name, const PhxMacro *macro)
{
    PhxNode *node = phx_node_leaf(PHX_NODE_MACRO, name.span,
                                  name.start, name.length);

    if (macro->param_count == 0) {
        if (check(reader, PHX_TOK_LPAREN)) {
            error_here(reader, "'%s' takes no arguments", macro->name);
            phx_note(reader->diag, macro->declared_at, "declared here");
            phx_node_free(node);
            return NULL;
        }
        return node;
    }

    if (!consume(reader, PHX_TOK_LPAREN, "'(' and the arguments")) {
        phx_note(reader->diag, macro->declared_at, "'%s' is declared here",
                 macro->name);
        phx_node_free(node);
        return NULL;
    }

    if (!check(reader, PHX_TOK_RPAREN)) {
        do {
            PhxNode *argument = expression(reader);
            if (argument == NULL) { phx_node_free(node); return NULL; }
            phx_node_add(node, argument);
        } while (match(reader, PHX_TOK_COMMA));
    }
    if (!consume(reader, PHX_TOK_RPAREN, "')' after the arguments")) {
        phx_node_free(node);
        return NULL;
    }

    if (node->count != macro->param_count) {
        error_at(reader, phx_node_extent(node),
                 "'%s' takes %d argument%s, and %d %s given",
                 macro->name, macro->param_count,
                 macro->param_count == 1 ? "" : "s",
                 node->count, node->count == 1 ? "was" : "were");
        phx_note(reader->diag, macro->declared_at, "declared here");
        phx_node_free(node);
        return NULL;
    }
    return node;
}

static PhxNode *primary(Reader *reader)
{
    PhxToken token = reader->current;

    switch (token.type) {
        case PHX_TOK_INTEGER:
            advance(reader);
            /* Without the '#', which the emitter puts back. The tag is
               Solveig's spelling of the type, not part of the number. */
            return phx_node_leaf(PHX_NODE_INTEGER, token.span,
                                 token.start + 1, token.length - 1);
        case PHX_TOK_FLOAT:
            advance(reader);
            return phx_node_leaf(PHX_NODE_FLOAT, token.span,
                                 token.start, token.length);
        case PHX_TOK_STRING:
            advance(reader);
            /* Inside the quotes; escapes still as written. */
            return phx_node_leaf(PHX_NODE_STRING, token.span,
                                 token.start + 1, token.length - 2);
        case PHX_TOK_SYMBOL:
            advance(reader);
            return phx_node_leaf(PHX_NODE_SYMBOL, token.span,
                                 token.start + 1, token.length - 1);

        case PHX_TOK_NAME: {
            /* A declared form wins over everything else a name could be, which
               is the module's own decision: it wrote the declaration. */
            const PhxMacro *macro = phx_dialect_macro(reader->dialect,
                                                      token.start, token.length);
            advance(reader);
            if (macro != NULL) return macro_use(reader, token, macro);

            /* `f(x)` is `x:f` -- prefix application is a send to its argument,
               which is Solveig's rule and not a second one. */
            if (check(reader, PHX_TOK_LPAREN)) {
                advance(reader);
                PhxNode *argument = expression(reader);
                if (argument == NULL) return NULL;
                if (!consume(reader, PHX_TOK_RPAREN, "')'")) {
                    phx_node_free(argument);
                    return NULL;
                }
                PhxNode *send = phx_node_leaf(PHX_NODE_SEND, token.span,
                                              token.start, token.length);
                phx_node_add(send, argument);
                return send;
            }
            return phx_node_leaf(PHX_NODE_NAME, token.span,
                                 token.start, token.length);
        }

        case PHX_TOK_LPAREN: {
            advance(reader);
            PhxNode *group = phx_node_new(PHX_NODE_SEQUENCE, token.span);
            do {
                if (check(reader, PHX_TOK_RPAREN)) break;
                PhxNode *inner = expression(reader);
                if (inner == NULL) { phx_node_free(group); return NULL; }
                phx_node_add(group, inner);
            } while (match(reader, PHX_TOK_DOT));
            if (!consume(reader, PHX_TOK_RPAREN, "')'")) {
                phx_node_free(group);
                return NULL;
            }
            return group;
        }

        case PHX_TOK_LBRACKET: {
            advance(reader);
            PhxNode *array = phx_node_new(PHX_NODE_ARRAY, token.span);
            if (!check(reader, PHX_TOK_RBRACKET)) {
                do {
                    PhxNode *element = expression(reader);
                    if (element == NULL) { phx_node_free(array); return NULL; }
                    phx_node_add(array, element);
                } while (match(reader, PHX_TOK_COMMA));
            }
            if (!consume(reader, PHX_TOK_RBRACKET, "']'")) {
                phx_node_free(array);
                return NULL;
            }
            return array;
        }

        case PHX_TOK_LBRACE:
            advance(reader);
            return block(reader, token);

        default:
            error_here(reader, "expected an expression, found %s",
                       phx_token_type_name(token.type));
            return NULL;
    }
}

static PhxNode *block(Reader *reader, PhxToken open)
{
    PhxNode *node = phx_node_new(PHX_NODE_BLOCK, open.span);

    if (looks_like_names_then_bar(reader)) {
        do {
            phx_node_add_param(node, reader->current.start,
                               reader->current.length);
            advance(reader);
        } while (match(reader, PHX_TOK_COMMA));
        advance(reader);                                  /* the '|' */
    }

    /* Temporaries carry a leading bar as well as a trailing one, which is what
       distinguishes `{ | a | a }` from `{ a | a }`. */
    if (check(reader, PHX_TOK_BAR)) {
        advance(reader);
        if (!check(reader, PHX_TOK_BAR)) {
            do {
                if (!check(reader, PHX_TOK_NAME)) {
                    error_here(reader, "a temporary is a name");
                    phx_node_free(node);
                    return NULL;
                }
                phx_node_add_temp(node, reader->current.start,
                                  reader->current.length);
                advance(reader);
            } while (match(reader, PHX_TOK_COMMA));
        }
        if (!consume(reader, PHX_TOK_BAR, "'|' after the temporaries")) {
            phx_node_free(node);
            return NULL;
        }
    }

    while (!check(reader, PHX_TOK_RBRACE) && !check(reader, PHX_TOK_EOF)) {
        PhxNode *inner = statement(reader);
        if (inner == NULL) {
            phx_node_free(node);
            return NULL;
        }
        phx_node_add(node, inner);
    }

    if (!consume(reader, PHX_TOK_RBRACE, "'}' to close this block")) {
        phx_note(reader->diag, open.span, "the block opened here");
        phx_node_free(node);
        return NULL;
    }
    return node;
}

/* `receiver:selector` and `receiver:selector(a, b)`, chaining left to right. */
static PhxNode *postfix(Reader *reader)
{
    PhxNode *left = primary(reader);
    if (left == NULL) return NULL;

    while (check(reader, PHX_TOK_COLON)) {
        advance(reader);
        if (!check(reader, PHX_TOK_NAME)) {
            error_here(reader, "':' sends a message, and a message is a name");
            phx_node_free(left);
            return NULL;
        }
        PhxToken selector = reader->current;
        advance(reader);

        PhxNode *send = phx_node_leaf(PHX_NODE_SEND, selector.span,
                                      selector.start, selector.length);
        phx_node_add(send, left);

        if (match(reader, PHX_TOK_LPAREN)) {
            if (!check(reader, PHX_TOK_RPAREN)) {
                do {
                    PhxNode *argument = expression(reader);
                    if (argument == NULL) { phx_node_free(send); return NULL; }
                    phx_node_add(send, argument);
                } while (match(reader, PHX_TOK_COMMA));
            }
            if (!consume(reader, PHX_TOK_RPAREN, "')' after the arguments")) {
                phx_node_free(send);
                return NULL;
            }
        }
        left = send;
    }
    return left;
}

static PhxNode *unary(Reader *reader)
{
    if (check(reader, PHX_TOK_OPERATOR)) {
        PhxToken op = reader->current;
        const PhxPrefix *prefix = phx_dialect_prefix(reader->dialect,
                                                     op.start, op.length);
        if (prefix == NULL) {
            error_at(reader, op.span,
                     "'%.*s' has no meaning in this module",
                     op.length, op.start);
            phx_note(reader->diag, op.span,
                     "a module declares its operators in its header: "
                     "@prefix %.*s <message>.", op.length, op.start);
            return NULL;
        }
        advance(reader);
        PhxNode *operand = unary(reader);
        if (operand == NULL) return NULL;

        PhxNode *send = phx_node_leaf(PHX_NODE_SEND, op.span,
                                      prefix->selector,
                                      (int)strlen(prefix->selector));
        phx_node_add(send, operand);
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
static PhxNode *infix(Reader *reader, int minimum)
{
    PhxNode *left = unary(reader);
    if (left == NULL) return NULL;

    while (check(reader, PHX_TOK_OPERATOR)) {
        PhxToken op = reader->current;
        const PhxInfix *entry = phx_dialect_infix(reader->dialect,
                                                  op.start, op.length);
        if (entry == NULL) {
            error_at(reader, op.span, "'%.*s' has no meaning in this module",
                     op.length, op.start);
            phx_note(reader->diag, op.span,
                     "a module declares its operators in its header: "
                     "@infix %.*s <precedence> <message>.",
                     op.length, op.start);
            phx_node_free(left);
            return NULL;
        }
        if (entry->precedence < minimum) break;

        advance(reader);
        int next = entry->assoc == PHX_ASSOC_LEFT ? entry->precedence + 1
                                                  : entry->precedence;
        PhxNode *right = infix(reader, next);
        if (right == NULL) { phx_node_free(left); return NULL; }

        /* The span is the operator's. What the node covers is worked out by
           phx_node_extent when something needs to underline the whole of it. */
        PhxNode *send = phx_node_leaf(PHX_NODE_SEND, op.span,
                                      entry->selector,
                                      (int)strlen(entry->selector));
        phx_node_add(send, left);
        phx_node_add(send, right);
        left = send;
    }
    return left;
}

static bool assignable(const PhxNode *node)
{
    /* A name, or a slot: `x := v` and `r:name := v`. A send with arguments is
       not a place, and neither is anything else. */
    return node->kind == PHX_NODE_NAME ||
           (node->kind == PHX_NODE_SEND && node->count == 1);
}

static PhxNode *expression(Reader *reader)
{
    PhxNode *left = infix(reader, 0);
    if (left == NULL) return NULL;

    if (check(reader, PHX_TOK_ASSIGN)) {
        PhxToken assign = reader->current;
        if (!assignable(left)) {
            error_at(reader, phx_node_extent(left),
                     "this cannot be assigned to");
            phx_node_free(left);
            return NULL;
        }
        advance(reader);
        PhxNode *value = expression(reader);
        if (value == NULL) { phx_node_free(left); return NULL; }

        PhxNode *node = phx_node_new(PHX_NODE_ASSIGN, assign.span);
        phx_node_add(node, left);
        phx_node_add(node, value);
        return node;
    }
    return left;
}

/* ------------------------------------------------------------- statements */

static PhxNode *statement(Reader *reader)
{
    /* `@include "text.sol".` is Solveig's directive and stays Solveig's: it is
       carried through to the generated file unread. Phoenix has nothing to say
       about it yet, and inventing a second include with different rules while
       the first one works is how two of them end up existing. */
    if (check(reader, PHX_TOK_DIRECTIVE) &&
        token_is(&reader->current, "@include")) {
        PhxToken directive = reader->current;
        advance(reader);
        if (!check(reader, PHX_TOK_STRING)) {
            error_here(reader, "'@include' takes the file name, in quotes");
            return NULL;
        }
        PhxNode *node = phx_node_leaf(PHX_NODE_INCLUDE, directive.span,
                                      reader->current.start + 1,
                                      reader->current.length - 2);
        advance(reader);
        if (!consume(reader, PHX_TOK_DOT, "'.' after the include")) {
            phx_node_free(node);
            return NULL;
        }
        return node;
    }

    PhxNode *node = expression(reader);
    if (node == NULL) return NULL;

    /* A separator between two, optional after the last -- in a file, in a
       block and in a group alike, which is Solveig's rule. */
    if (!match(reader, PHX_TOK_DOT) &&
        !check(reader, PHX_TOK_RBRACE) && !check(reader, PHX_TOK_EOF)) {
        error_here(reader, "expected '.' after this statement, found %s",
                   phx_token_type_name(reader->current.type));
        phx_node_free(node);
        return NULL;
    }
    return node;
}

PhxNode *phx_read(const PhxSource *source, PhxDialect *dialect,
                  PhxDiagnostics *diag)
{
    Reader reader;
    phx_lexer_init(&reader.lexer, source->text);
    reader.source = source;
    reader.dialect = dialect;
    reader.diag = diag;
    reader.panicked = false;
    reader.previous.type = PHX_TOK_EOF;
    reader.current.type = PHX_TOK_EOF;
    reader.current.span = PHX_SPAN_NONE;
    reader.current.start = source->text;
    reader.current.length = 0;
    reader.current.message = NULL;
    advance(&reader);

    while (header_directive(&reader)) { }

    PhxNode *module = phx_node_new(PHX_NODE_SEQUENCE, PHX_SPAN_NONE);

    while (!check(&reader, PHX_TOK_EOF)) {
        /* A header directive down here is the one mistake worth naming
           precisely, because the file looks right and the operator quietly did
           not exist for the statements above it. */
        if (check(&reader, PHX_TOK_DIRECTIVE) &&
            !token_is(&reader.current, "@include")) {
            error_at(&reader, reader.current.span,
                     "a module settles its syntax before its first statement");
            phx_note(diag, reader.current.span,
                     "move this above the code, with the other directives");
            synchronize(&reader);
            continue;
        }

        PhxNode *node = statement(&reader);
        if (node == NULL) {
            synchronize(&reader);
            continue;
        }
        phx_node_add(module, node);
    }

    if (diag->errors > 0) {
        phx_node_free(module);
        return NULL;
    }
    return module;
}
