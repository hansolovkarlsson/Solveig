/* compiler.c -- single pass: the parser drives emission straight into the
 * chunk, so there is no AST. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solas/parser.h"

#define SOL_MAX_LOCALS 256

/* One entry per named slot in the frame being compiled. Slot 0 is always self.
   There are no blocks yet, so a flat list per method is enough. */
typedef struct {
    const char *name;
    int         length;
} Local;

/* Per-frame compiler state, chained so a method body can be compiled without
   disturbing the enclosing chunk. */
typedef struct Scope {
    struct Scope *enclosing;
    SolChunk     *chunk;
    Local         locals[SOL_MAX_LOCALS];
    int           local_count;
    bool          in_method;   /* the top level has no self and no locals    */
    bool          is_block;    /* a block reads self and outer locals via OUTER */
} Scope;

typedef struct {
    SolParser parser;
    Scope    *scope;
} Compiler;

static void expression(Compiler *c);
static void statement(Compiler *c);
static void block_literal(Compiler *c);

/* The nearest enclosing method scope. A block's locals live in the method it
   was written in, and blocks nested in blocks share that same frame, so this
   walks past any number of block scopes. */
static Scope *home_scope(Scope *scope)
{
    while (scope != NULL && scope->is_block) scope = scope->enclosing;
    return scope;
}

static void emit(Compiler *c, uint8_t byte)
{
    sol_chunk_write(c->scope->chunk, byte, c->parser.previous.line);
}

static void emit_pair(Compiler *c, uint8_t a, uint8_t b)
{
    emit(c, a);
    emit(c, b);
}

/* Interns the token's text and returns its operand index, refusing to overflow
   the one-byte operand. */
static uint8_t name_operand(Compiler *c, const SolToken *token)
{
    int index = sol_chunk_add_name(c->scope->chunk, token->start, token->length);
    if (index > UINT8_MAX) {
        sol_parser_error(&c->parser, token, "too many names in one chunk");
        return 0;
    }
    return (uint8_t)index;
}

static uint8_t constant_operand(Compiler *c, SolValue value)
{
    int index = sol_chunk_add_constant(c->scope->chunk, value);
    if (index > UINT8_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous,
                         "too many constants in one chunk");
        return 0;
    }
    return (uint8_t)index;
}

/* ---- literals -------------------------------------------------------- */

static void integer_literal(Compiler *c)
{
    const SolToken *token = &c->parser.previous;

    /* Skip the '#' type tag; strtoll handles the optional sign. */
    errno = 0;
    char *end;
    long long value = strtoll(token->start + 1, &end, 10);
    if (errno == ERANGE) {
        sol_parser_error(&c->parser, token, "integer literal out of range");
        return;
    }
    emit_pair(c, OP_CONST, constant_operand(c, SOL_INT_VAL((int64_t)value)));
}

static void float_literal(Compiler *c)
{
    const SolToken *token = &c->parser.previous;
    double value = strtod(token->start, NULL);
    emit_pair(c, OP_CONST, constant_operand(c, SOL_FLOAT_VAL(value)));
}

/* ---- expressions ----------------------------------------------------- */

/* Slot of `name` in the frame being compiled, or -1 if it is not a local. */
static int resolve_local(Scope *scope, const SolToken *name)
{
    for (int i = scope->local_count - 1; i >= 0; i--) {
        Local *local = &scope->locals[i];
        if (local->length == name->length &&
            memcmp(local->name, name->start, (size_t)name->length) == 0) {
            return i;
        }
    }
    return -1;
}

/* Reserves a slot. Returns -1 if the frame is full. */
static int declare_local(Scope *scope, const char *name, int length)
{
    if (scope->local_count == SOL_MAX_LOCALS) return -1;
    Local *local = &scope->locals[scope->local_count];
    local->name = name;
    local->length = length;
    return scope->local_count++;
}

/* IDENT is either an assignment target or a name to resolve. One token of
 * lookahead is enough because a target is always a bare identifier.
 *
 * Resolution goes: this frame's locals, then the enclosing method's locals if
 * we are inside a block, then the globals. Assigning to a new name declares a
 * local in the current frame; at the top level it binds a global.
 */
static void identifier(Compiler *c)
{
    SolToken name = c->parser.previous;
    Scope *scope = c->scope;
    Scope *home = home_scope(scope);

    int slot = resolve_local(scope, &name);
    int outer = -1;
    if (slot < 0 && scope->is_block && home != NULL && home->in_method) {
        outer = resolve_local(home, &name);
    }

    if (sol_parser_match(&c->parser, TOK_ASSIGN)) {
        if (slot < 0 && outer < 0) {
            /* A block declares nothing of its own. A new name inside one
               belongs to the enclosing method, so that `{ i := i:add(#1) }`
               updates the `i` everyone else can see rather than a private copy
               that vanishes when the block returns. At the top level there is
               no enclosing method and it stays a global. */
            if (scope->is_block) {
                if (home != NULL && home->in_method) {
                    outer = declare_local(home, name.start, name.length);
                    if (outer < 0) {
                        sol_parser_error(&c->parser, &name,
                                         "too many locals in one method");
                        return;
                    }
                }
            } else if (scope->in_method) {
                slot = declare_local(scope, name.start, name.length);
                if (slot < 0) {
                    sol_parser_error(&c->parser, &name, "too many locals in one frame");
                    return;
                }
            }
        }
        expression(c);
        if (slot >= 0)       emit_pair(c, OP_SET_LOCAL, (uint8_t)slot);
        else if (outer >= 0) emit_pair(c, OP_SET_OUTER, (uint8_t)outer);
        else                 emit_pair(c, OP_SET_GLOBAL, name_operand(c, &name));
        return;
    }

    if (slot >= 0)       emit_pair(c, OP_LOCAL, (uint8_t)slot);
    else if (outer >= 0) emit_pair(c, OP_OUTER, (uint8_t)outer);
    else                 emit_pair(c, OP_GLOBAL, name_operand(c, &name));
}

static void primary(Compiler *c)
{
    SolParser *p = &c->parser;

    if (sol_parser_match(p, TOK_LBRACE))     { block_literal(c); return; }
    if (sol_parser_match(p, TOK_IDENT))      { identifier(c); return; }
    if (sol_parser_match(p, TOK_INT))        { integer_literal(c); return; }
    if (sol_parser_match(p, TOK_FLOAT))      { float_literal(c); return; }
    if (sol_parser_match(p, TOK_LPAREN)) {
        /* Parentheses group. With more than one statement inside, the earlier
           results are discarded and the last one is the value -- which is what
           gives a method body more than a single expression. */
        expression(c);
        while (sol_parser_match(p, TOK_DOT)) {
            if (p->current.type == TOK_RPAREN) break;   /* a trailing '.' is fine */
            emit(c, OP_POP);
            expression(c);
        }
        sol_parser_consume(p, TOK_RPAREN, "expected ')'");
        return;
    }
    if (sol_parser_match(p, TOK_STRING)) {
        sol_parser_error(p, &p->previous,
                         "strings are scanned but have no runtime type yet");
        return;
    }
    if (sol_parser_match(p, TOK_SYMBOL)) {
        sol_parser_error(p, &p->previous,
                         "symbols are scanned but have no runtime type yet");
        return;
    }

    sol_parser_error(p, &p->current, "expected an expression");
}

/* Arguments to one message: '(' expression ( ',' expression )* ')' */
static uint8_t arguments(Compiler *c)
{
    SolParser *p = &c->parser;
    int argc = 0;

    if (!sol_parser_match(p, TOK_LPAREN)) return 0;   /* a bare `a:print` */

    if (!sol_parser_match(p, TOK_RPAREN)) {
        do {
            expression(c);
            if (++argc > UINT8_MAX) {
                sol_parser_error(p, &p->current, "too many arguments");
                return 0;
            }
        } while (sol_parser_match(p, TOK_COMMA));
        sol_parser_consume(p, TOK_RPAREN, "expected ')' after arguments");
    }
    return (uint8_t)argc;
}

static void expression(Compiler *c)
{
    SolParser *p = &c->parser;

    primary(c);

    /* Sends chain left to right: `a:add(#1):print` sends print to the sum. */
    while (sol_parser_match(p, TOK_COLON)) {
        sol_parser_consume(p, TOK_IDENT, "expected a message name after ':'");
        SolToken selector = p->previous;
        uint8_t argc = arguments(c);

        emit(c, OP_SEND);
        emit(c, name_operand(c, &selector));
        emit(c, argc);
    }
}

/* Does `chunk` read or write the home frame, directly or through a block
   nested inside it? A block that does not is independent of the frame it was
   written in, and may outlive it. */
static bool touches_home(const SolChunk *chunk)
{
    for (int offset = 0; offset < chunk->count; ) {
        uint8_t op = chunk->code[offset];
        if (op == OP_OUTER || op == OP_SET_OUTER) return true;

        switch (op) {
        case OP_CONST: case OP_GLOBAL: case OP_SET_GLOBAL:
        case OP_LOCAL: case OP_SET_LOCAL: case OP_OUTER:
        case OP_SET_OUTER: case OP_BLOCK:
            offset += 2; break;
        case OP_SEND: case OP_DEF_METHOD:
            offset += 3; break;
        default:
            offset += 1; break;
        }
    }
    /* A nested block shares this frame's home, so its captures count too. */
    for (int i = 0; i < chunk->methods.count; i++) {
        const SolMethod *inner = chunk->methods.methods[i];
        if (inner->is_block && touches_home(&inner->chunk)) return true;
    }
    return false;
}

/* `{ ... }` -- code as a value.
 *
 * The body compiles exactly like a method body, into a chunk of its own held in
 * the enclosing chunk's method table. What makes it a block is OP_BLOCK, which
 * captures the running frame as the block's home so `self` and the enclosing
 * locals still mean the right thing whenever it is eventually run. */
static void block_literal(Compiler *c)
{
    SolParser *p = &c->parser;

    SolMethod *code = sol_method_new("block", 5, 0);
    code->is_block = true;

    Scope scope;
    scope.enclosing = c->scope;
    scope.chunk = &code->chunk;
    scope.local_count = 0;
    scope.in_method = true;
    scope.is_block = true;
    /* Slot 0 of a block frame holds the block itself, and cannot be named --
       `self` resolves past it, to the home frame's slot 0. */
    declare_local(&scope, "", 0);

    c->scope = &scope;
    if (p->current.type == TOK_RBRACE) {
        emit(c, OP_NIL);                     /* an empty block answers nil */
    } else {
        expression(c);
        while (sol_parser_match(p, TOK_DOT)) {
            if (p->current.type == TOK_RBRACE) break;   /* a trailing '.' is fine */
            emit(c, OP_POP);
            expression(c);
        }
    }
    sol_parser_consume(p, TOK_RBRACE, "expected '}' to close the block");
    emit(c, OP_RETURN);
    c->scope = scope.enclosing;

    code->slot_count = scope.local_count;
    code->captures = touches_home(&code->chunk);

    int index = sol_chunk_add_method(c->scope->chunk, code);
    if (index > UINT8_MAX) {
        sol_parser_error(p, &p->previous, "too many blocks in one chunk");
        return;
    }
    emit_pair(c, OP_BLOCK, (uint8_t)index);
}

/* After an error, skip to the next statement boundary so one mistake does not
   cascade into a screenful. */
static void synchronise(Compiler *c)
{
    SolParser *p = &c->parser;
    p->panicked = false;

    while (p->current.type != TOK_EOF) {
        if (p->previous.type == TOK_DOT) return;
        sol_parser_advance(p);
    }
}

/* Is the statement ahead a method definition rather than an expression?
 *
 *     integer:double() := ...
 *
 * The shape is IDENT ':' IDENT '(' params ')' ':=', which needs more lookahead
 * than the parser carries. A SolLexer is three pointers, so a copy scans ahead
 * cheaply and is thrown away; nothing in the real token stream moves. */
static bool ahead_is_method_definition(SolParser *p)
{
    if (p->current.type != TOK_IDENT) return false;

    SolLexer probe = p->lexer;      /* positioned just past p->current */
    if (sol_lexer_next(&probe).type != TOK_COLON) return false;
    if (sol_lexer_next(&probe).type != TOK_IDENT) return false;

    SolToken token = sol_lexer_next(&probe);
    if (token.type != TOK_LPAREN) return false;

    token = sol_lexer_next(&probe);
    if (token.type != TOK_RPAREN) {
        for (;;) {
            if (token.type != TOK_IDENT) return false;
            token = sol_lexer_next(&probe);
            if (token.type == TOK_RPAREN) break;
            if (token.type != TOK_COMMA) return false;
            token = sol_lexer_next(&probe);
        }
    }
    return sol_lexer_next(&probe).type == TOK_ASSIGN;
}

/* `integer:double() := self:mul(#2).`
 *
 * The target is an ordinary expression, evaluated and left on the stack for
 * OP_DEF_METHOD, so a method is bound on a class exactly as `:=` binds a name
 * in the globals. */
static void method_definition(Compiler *c)
{
    SolParser *p = &c->parser;

    sol_parser_consume(p, TOK_IDENT, "expected the class to define on");
    SolToken target = p->previous;

    sol_parser_consume(p, TOK_COLON, "expected ':'");
    sol_parser_consume(p, TOK_IDENT, "expected a method name");
    SolToken name = p->previous;

    /* Collect parameter names before compiling, so arity is known up front. */
    SolToken params[SOL_MAX_LOCALS];
    int arity = 0;
    sol_parser_consume(p, TOK_LPAREN, "expected '(' after the method name");
    if (!sol_parser_match(p, TOK_RPAREN)) {
        do {
            if (arity == UINT8_MAX) {
                sol_parser_error(p, &p->current, "too many parameters");
                return;
            }
            sol_parser_consume(p, TOK_IDENT, "expected a parameter name");
            params[arity++] = p->previous;
        } while (sol_parser_match(p, TOK_COMMA));
        sol_parser_consume(p, TOK_RPAREN, "expected ')' after parameters");
    }
    sol_parser_consume(p, TOK_ASSIGN, "expected ':=' before the method body");

    SolMethod *method = sol_method_new(name.start, name.length, arity);

    /* Compile the body into the method's own chunk. */
    Scope scope;
    scope.enclosing = c->scope;
    scope.chunk = &method->chunk;
    scope.local_count = 0;
    scope.in_method = true;
    scope.is_block = false;
    declare_local(&scope, "self", 4);            /* slot 0 */
    for (int i = 0; i < arity; i++) {
        declare_local(&scope, params[i].start, params[i].length);
    }

    c->scope = &scope;
    expression(c);
    emit(c, OP_RETURN);                          /* the body's value is the reply */
    c->scope = scope.enclosing;

    method->slot_count = scope.local_count;

    int method_index = sol_chunk_add_method(c->scope->chunk, method);
    if (method_index > UINT8_MAX) {
        sol_parser_error(p, &name, "too many methods in one chunk");
        return;
    }

    /* Evaluate the target, then bind. */
    emit_pair(c, OP_GLOBAL, name_operand(c, &target));
    emit(c, OP_DEF_METHOD);
    emit(c, (uint8_t)method_index);
    emit(c, name_operand(c, &name));
}

static void statement(Compiler *c)
{
    if (ahead_is_method_definition(&c->parser)) {
        method_definition(c);
    } else {
        expression(c);
    }
    sol_parser_match(&c->parser, TOK_DOT);   /* the terminator stays optional */
    emit(c, OP_POP);                         /* a statement leaves nothing behind */

    if (c->parser.panicked) synchronise(c);
}

bool sol_compile(const char *source, SolChunk *chunk)
{
    Scope top;
    top.enclosing = NULL;
    top.chunk = chunk;
    top.local_count = 0;
    top.in_method = false;
    top.is_block = false;

    Compiler c;
    c.scope = &top;
    sol_parser_init(&c.parser, source);

    while (!sol_parser_match(&c.parser, TOK_EOF)) {
        statement(&c);
    }
    emit(&c, OP_HALT);

    return !c.parser.had_error;
}
