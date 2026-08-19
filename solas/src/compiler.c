/* compiler.c -- single pass: the parser drives emission straight into the
 * chunk, so there is no AST. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solas/compiler.h"
#include "solas/parser.h"

#define SOL_MAX_LOCALS 256

/* One entry per named slot in the frame being compiled. Slot 0 is the receiver.
   Each block gets its own scope, and resolve_name walks the chain outward, so a
   flat list per frame is enough. */
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
static void array_literal(Compiler *c);
static void string_literal(Compiler *c);
static int  resolve_local(Scope *scope, const SolToken *name);
static int  declare_local(Scope *scope, const char *name, int length);

/* Finds `name` along the lexical chain. Returns its slot and sets *depth to how
   many frames out it lives -- 0 for this one, 1 for the enclosing block, and so
   on. Returns -1 if it is not a local anywhere, which makes it a global. */
static int resolve_name(Scope *scope, const SolToken *name, int *depth)
{
    int d = 0;
    for (Scope *s = scope; s != NULL; s = s->enclosing) {
        int slot = resolve_local(s, name);
        if (slot >= 0) { *depth = d; return slot; }
        if (!s->is_block) break;      /* the top level holds globals, not locals */
        d++;                          /* crossed a frame boundary */
    }
    return -1;
}

/* `self` is always slot 0 of the frame being compiled.
 *
 * It is not resolved lexically to some enclosing frame, because which block
 * ends up invoked as a method is not knowable here -- a block can be built by
 * one block and bound to a slot by another. Instead the VM captures the
 * receiver into the block when the block is created, and a send to a slot
 * holding it overrides slot 0 with its own receiver. Lexical either way, but
 * decided where the answer is actually known. */
static bool inside_a_block(Scope *scope)
{
    return scope != NULL && scope->is_block;
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

/* Same, for a name the compiler supplies rather than reads from the source --
   the `array` and `of` that an array literal desugars to. */
static uint8_t name_literal(Compiler *c, const char *name, int length)
{
    int index = sol_chunk_add_name(c->scope->chunk, name, length);
    if (index > UINT8_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous, "too many names in one chunk");
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

/* `| a, b |` -- declares temporaries in the frame being compiled.
 *
 * Only parameters and names declared here are locals. Everything else is a
 * global, so assigning `counter := counter:add(#1)` inside a method updates the
 * counter everyone can see rather than shadowing it with a fresh local. */
static void declarations(Compiler *c)
{
    SolParser *p = &c->parser;

    do {
        sol_parser_consume(p, TOK_IDENT, "expected a name to declare");
        if (p->panicked) return;

        SolToken name = p->previous;
        if (resolve_local(c->scope, &name) >= 0) {
            sol_parser_error(p, &name, "that name is already declared here");
            return;
        }
        if (declare_local(c->scope, name.start, name.length) < 0) {
            sol_parser_error(p, &name, "too many names declared in one frame");
            return;
        }
    } while (sol_parser_match(p, TOK_COMMA));

    sol_parser_consume(p, TOK_PIPE, "expected '|' to close the declarations");
}

/* Parses `| ... |` if it is there. */
static void optional_declarations(Compiler *c)
{
    if (sol_parser_match(&c->parser, TOK_PIPE)) declarations(c);
}

static void emit_access(Compiler *c, bool store, int depth, int slot)
{
    if (depth == 0) {
        emit_pair(c, store ? OP_SET_LOCAL : OP_LOCAL, (uint8_t)slot);
    } else {
        emit(c, store ? OP_SET_OUTER : OP_OUTER);
        emit(c, (uint8_t)depth);
        emit(c, (uint8_t)slot);
    }
}

/* IDENT is either an assignment target or a name to resolve. One token of
 * lookahead is enough because a target is always a bare identifier.
 *
 * Only parameters and declared temporaries are locals; anything else is a
 * global. Assignment never declares, which is what lets a block reach out and
 * update a name rather than shadowing it.
 */
static void identifier(Compiler *c)
{
    SolToken name = c->parser.previous;
    int depth = 0;
    int slot;

    if (name.length == 4 && memcmp(name.start, "self", 4) == 0) {
        if (!inside_a_block(c->scope)) {
            sol_parser_error(&c->parser, &name,
                             "'self' is only meaningful inside a block");
            return;
        }
        if (sol_parser_match(&c->parser, TOK_ASSIGN)) {
            sol_parser_error(&c->parser, &name, "cannot assign to 'self'");
            return;
        }
        emit_access(c, false, 0, 0);      /* slot 0 of this frame */
        return;
    }

    slot = resolve_name(c->scope, &name, &depth);

    if (sol_parser_match(&c->parser, TOK_ASSIGN)) {
        expression(c);
        if (slot >= 0) emit_access(c, true, depth, slot);
        else           emit_pair(c, OP_SET_GLOBAL, name_operand(c, &name));
        return;
    }

    if (slot >= 0) emit_access(c, false, depth, slot);
    else           emit_pair(c, OP_GLOBAL, name_operand(c, &name));
}

/* The token spans the quotes; the string is what lies between them, with the
 * escapes resolved. The decoded bytes are interned in the chunk's text table
 * alongside selectors and global names, all three being interned text.
 *
 * An unrecognised escape is an error rather than a literal backslash, so a typo
 * is caught where it is written instead of appearing in the output.
 *
 * There is no `\0`: the text table is NUL-terminated in memory, so an embedded
 * one would truncate the string. The wire format already carries lengths, so
 * lifting that means giving the in-memory table lengths too.
 */
static void string_literal(Compiler *c)
{
    SolToken token = c->parser.previous;
    const char *source = token.start + 1;
    int length = token.length - 2;

    char *decoded = malloc((size_t)length + 1);
    if (decoded == NULL) {
        sol_parser_error(&c->parser, &token, "out of memory reading a string");
        return;
    }

    int out = 0;
    for (int i = 0; i < length; i++) {
        if (source[i] != '\\') {
            decoded[out++] = source[i];
            continue;
        }
        if (++i == length) {
            sol_parser_error(&c->parser, &token, "a string ends with a lone backslash");
            free(decoded);
            return;
        }
        switch (source[i]) {
        case '"':  decoded[out++] = '"';  break;
        case '\\': decoded[out++] = '\\'; break;
        case 'n':  decoded[out++] = '\n'; break;
        case 't':  decoded[out++] = '\t'; break;
        case 'r':  decoded[out++] = '\r'; break;
        default:
            sol_parser_error(&c->parser, &token,
                             "unknown escape in a string; \\\" \\\\ \\n \\t \\r are the escapes");
            free(decoded);
            return;
        }
    }

    emit_pair(c, OP_STRING, name_literal(c, decoded, out));
    free(decoded);
}

static void primary(Compiler *c)
{
    SolParser *p = &c->parser;

    if (sol_parser_match(p, TOK_LBRACE))     { block_literal(c); return; }
    if (sol_parser_match(p, TOK_LBRACKET))   { array_literal(c); return; }
    if (sol_parser_match(p, TOK_IDENT))      { identifier(c); return; }
    if (sol_parser_match(p, TOK_INT))        { integer_literal(c); return; }
    if (sol_parser_match(p, TOK_FLOAT))      { float_literal(c); return; }
    if (sol_parser_match(p, TOK_LPAREN)) {
        /* Parentheses group. With more than one statement inside, the earlier
           results are discarded and the last one is the value -- which is what
           gives a method body more than a single expression. A group may open
           with `| a, b |`, declaring temporaries of the frame it sits in. */
        optional_declarations(c);
        expression(c);
        for (;;) {
            if (p->current.type == TOK_RPAREN) break;
            if (!sol_parser_match(p, TOK_DOT)) {
                sol_parser_error(p, &p->current, "expected '.' between statements");
                break;
            }
            if (p->current.type == TOK_RPAREN) break;   /* a trailing '.' is fine */
            emit(c, OP_POP);
            expression(c);
        }
        sol_parser_consume(p, TOK_RPAREN, "expected ')'");
        return;
    }
    if (sol_parser_match(p, TOK_STRING)) { string_literal(c); return; }
    if (sol_parser_match(p, TOK_SYMBOL)) {
        /* The token spans the leading quote; the name is what follows it. */
        SolToken token = p->previous;
        emit_pair(c, OP_SYMBOL,
                  name_literal(c, token.start + 1, token.length - 1));
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

/* `receiver:name := value` binds a slot, and it is the same `:=` as everywhere
 * else: the right-hand side is evaluated, then bound. A slot holding a block is
 * what makes a method.
 *
 * Single pass, so the send has already been emitted by the time `:=` appears.
 * A zero-argument send is exactly three bytes and the receiver is still on the
 * stack beneath it, so rewinding the chunk to where that send started undoes it
 * precisely -- no extra lookahead, and still no AST.
 */
static void expression(Compiler *c)
{
    SolParser *p = &c->parser;

    primary(c);

    int     target_at = -1;      /* where the last zero-argument send started */
    uint8_t target_name = 0;

    /* Sends chain left to right: `a:add(#1):print` sends print to the sum. */
    while (sol_parser_match(p, TOK_COLON)) {
        sol_parser_consume(p, TOK_IDENT, "expected a message name after ':'");
        SolToken selector = p->previous;

        int at = c->scope->chunk->count;
        uint8_t argc = arguments(c);
        uint8_t name = name_operand(c, &selector);

        emit(c, OP_SEND);
        emit(c, name);
        emit(c, argc);

        target_at = (argc == 0) ? at : -1;
        target_name = name;
    }

    if (target_at >= 0 && sol_parser_match(p, TOK_ASSIGN)) {
        c->scope->chunk->count = target_at;      /* unemit the send */
        expression(c);
        emit_pair(c, OP_SET_SLOT, target_name);
    }
}

/* Does `chunk` reach out of its own frame? One that does not is independent of
   where it was written and may outlive it. A block nested inside is not
   consulted: its depths are counted from its own frame, so whether it reaches
   past this one is its business, recorded on its own flag. */
static bool touches_home(const SolChunk *chunk)
{
    for (int offset = 0; offset < chunk->count; ) {
        uint8_t op = chunk->code[offset];
        if (op == OP_OUTER || op == OP_SET_OUTER) return true;

        switch (op) {
        case OP_CONST: case OP_GLOBAL: case OP_SET_GLOBAL:
        case OP_LOCAL: case OP_SET_LOCAL: case OP_BLOCK:
        case OP_SET_SLOT: case OP_STRING: case OP_SYMBOL:
            offset += 2; break;
        case OP_SEND: case OP_OUTER: case OP_SET_OUTER:
            offset += 3; break;
        default:
            offset += 1; break;
        }
    }
    return false;
}

/* `{ ... }` -- code as a value.
 *
 * The body compiles exactly like a method body, into a chunk of its own held in
 * the enclosing chunk's method table. What makes it a block is OP_BLOCK, which
 * captures the running frame as the block's home so `self` and the enclosing
 * locals still mean the right thing whenever it is eventually run. */
/* `[a, b]` -- an array literal, and nothing more than a way of writing
 * `array:of(a, b)`. The receiver goes on the stack first, then the elements,
 * then the send, which is exactly what the parenthesised form emits.
 *
 * Being real desugaring rather than a lookalike has one visible consequence: the
 * `array` it sends to is the ordinary global, so rebinding that name changes
 * both spellings together. They cannot drift apart, which is the point.
 *
 * `[]` sends `of` with no arguments and answers an empty array.
 */
static void array_literal(Compiler *c)
{
    SolParser *p = &c->parser;

    emit_pair(c, OP_GLOBAL, name_literal(c, "array", 5));

    int count = 0;
    if (!sol_parser_match(p, TOK_RBRACKET)) {
        do {
            expression(c);
            if (count == UINT8_MAX) {
                sol_parser_error(p, &p->current,
                                 "too many elements in one array literal");
                return;
            }
            count++;
        } while (sol_parser_match(p, TOK_COMMA));
        sol_parser_consume(p, TOK_RBRACKET, "expected ']' after the elements");
    }

    emit(c, OP_SEND);
    emit(c, name_literal(c, "of", 2));
    emit(c, (uint8_t)count);
}

/* Parameters come first, closed by `|`:
 *
 *     { a, b | a:add(b) }
 *     { | t | ... }          a leading '|' means no parameters, just temporaries
 *
 * That leading `|` is what separates the two cases, and is why parameters could
 * not reuse the parenthesised form: `{ (a) }` would be both a one-parameter
 * block and a block answering the value of `a`.
 */
static void block_parameters(Compiler *c, SolMethod *code)
{
    SolParser *p = &c->parser;

    if (p->current.type != TOK_IDENT) return;   /* '|' or a body, not parameters */

    /* `a, b |` is a parameter list; a bare expression is not. Scanning a copy of
       the lexer settles it without disturbing the token stream. */
    SolLexer probe = p->lexer;
    SolToken token = sol_lexer_next(&probe);
    while (token.type == TOK_COMMA) {
        if (sol_lexer_next(&probe).type != TOK_IDENT) return;
        token = sol_lexer_next(&probe);
    }
    if (token.type != TOK_PIPE) return;

    do {
        sol_parser_consume(p, TOK_IDENT, "expected a parameter name");
        if (p->panicked) return;

        SolToken name = p->previous;
        if (resolve_local(c->scope, &name) >= 0) {
            sol_parser_error(p, &name, "that name is already a parameter here");
            return;
        }
        if (declare_local(c->scope, name.start, name.length) < 0) {
            sol_parser_error(p, &name, "too many parameters");
            return;
        }
        code->arity++;
    } while (sol_parser_match(p, TOK_COMMA));

    sol_parser_consume(p, TOK_PIPE, "expected '|' after the block parameters");
}

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
    /* Slot 0 of a block frame holds whatever the send placed there: the block
       itself for `value`, or the receiver when a slot holding this block is
       sent. It cannot be named -- `self` finds it by position instead, on the
       outermost block of the nest. Parameters follow, landing in slots
       1..arity exactly as a send lays them out. */
    declare_local(&scope, "", 0);

    c->scope = &scope;
    block_parameters(c, code);
    optional_declarations(c);
    if (p->current.type == TOK_RBRACE) {
        emit(c, OP_NIL);                     /* an empty block answers nil */
    } else {
        expression(c);
        for (;;) {
            if (p->current.type == TOK_RBRACE) break;
            if (!sol_parser_match(p, TOK_DOT)) {
                sol_parser_error(p, &p->current, "expected '.' between statements");
                break;
            }
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

    /* Advance before testing, so recovery always consumes at least one token.
       Checking first meant that a statement which failed without consuming
       anything -- `primary` reports an unexpected token without taking it --
       could be retried forever when the token before it happened to be a '.',
       since synchronise would then return having moved nothing. */
    while (p->current.type != TOK_EOF) {
        sol_parser_advance(p);
        if (p->previous.type == TOK_DOT) return;
    }
}

/* `.` separates statements rather than terminating them, so it is required
   between two and optional after the last. That is what groups and blocks
   already did; the top level used to accept its absence anywhere, which meant a
   missing one could never be reported. */
static void statement(Compiler *c)
{
    SolParser *p = &c->parser;

    expression(c);
    if (!sol_parser_match(p, TOK_DOT) && p->current.type != TOK_EOF) {
        sol_parser_error(p, &p->current, "expected '.' between statements");
    }
    emit(c, OP_POP);                         /* a statement leaves nothing behind */

    if (p->panicked) synchronise(c);
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
