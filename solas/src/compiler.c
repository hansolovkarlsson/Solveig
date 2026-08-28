/* compiler.c -- single pass: the parser drives emission straight into the
 * chunk, so there is no AST. */
#define _POSIX_C_SOURCE 200809L    /* realpath, for resolving an include */

#include "config.h"                 /* generated: SOL_LIB_DIR, from PREFIX */

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

/* Every file compiled so far, by where it actually is on disk, and how deep
   the includes currently nest. One of these is shared by every file in one
   compilation -- see `include_directive` for why a file is compiled once. */
/* A global bound at some file's top level, and which file bound it. Kept so
   that a second file binding the same name can be told about it -- see
   `note_global_binding`. */
typedef struct {
    char *name;
    char *file;                /* the path that bound it, or NULL for none */
} BoundName;

typedef struct {
    char **paths;
    int    count;
    int    capacity;
    int    depth;

    BoundName *bound;          /* globals bound so far, across every file */
    int        bound_count;
    int        bound_capacity;
} Includes;

typedef struct {
    SolParser   parser;
    Scope      *scope;
    const char *path;      /* the file being compiled, or NULL for plain text */
    Includes   *includes;  /* shared with every file this compilation reaches */
    const SolSearchPath *search;   /* where an include falls back to, or NULL */

    /* While compiling the right-hand side of `name := ...`, which name it is
       and whether that name was read in the course of it. `x := x:add(#1)`
       updates a global rather than claiming it, and only the claim is worth
       warning about -- see `note_global_binding`. */
    const SolToken *assigning;
    bool            assigned_name_was_read;
} Compiler;

static void expression(Compiler *c);
static void send_expression(Compiler *c);
static void math_sum(Compiler *c);
static void math_unary(Compiler *c);
static void math_directive(Compiler *c);
static void statement(Compiler *c);
static void note_global_binding(Compiler *c, const SolToken *name);
static void block_literal(Compiler *c);
static bool inline_conditional(Compiler *c, const SolToken *selector);
static bool inline_logical(Compiler *c, const SolToken *selector);
static bool inline_while(Compiler *c);
static bool inline_do_until(Compiler *c);

/* Is this token exactly this word? */
static bool token_is(const SolToken *token, const char *word)
{
    size_t length = strlen(word);
    return token->length == (int)length &&
           memcmp(token->start, word, length) == 0;
}
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

/* Every byte carries the line it came from, and the file that line is in.
 *
 * A chunk is one compiled unit and `@include` puts a library's code into the
 * same one, so a line number on its own named a line in a file nobody had
 * recorded -- and it read as a line of the file being looked at, which is worse
 * than saying nothing. The file is set on the chunk rather than passed here
 * because it changes at an include and not per byte. */
static void emit(Compiler *c, uint8_t byte)
{
    SolChunk *chunk = c->scope->chunk;
    chunk->writing_file = sol_chunk_file(chunk, c->path);
    sol_chunk_write(chunk, byte, c->parser.previous.line);
}

static void emit_pair(Compiler *c, uint8_t a, uint8_t b)
{
    emit(c, a);
    emit(c, b);
}

/* A side-table index, in whichever order `sol_u16_first` says. That pair is the
   only place the byte order is written down -- see bytecode.h. */
static void emit_index(Compiler *c, int index)
{
    emit(c, sol_u16_first((uint16_t)index));
    emit(c, sol_u16_second((uint16_t)index));
}

/* Interns the token's text and returns its operand index. Both tables intern,
   so the ceiling counts distinct entries: a chunk may mention `print` and `#1`
   as often as it likes and spend one slot on each. */
static int name_operand(Compiler *c, const SolToken *token)
{
    int index = sol_chunk_add_name(c->scope->chunk, token->start, token->length);
    if (index > UINT16_MAX) {
        sol_parser_error(&c->parser, token, "too many names in one chunk");
        return 0;
    }
    return index;
}

/* Same, for a name the compiler supplies rather than reads from the source --
   the `array` and `of` that an array literal desugars to. */
static int name_literal(Compiler *c, const char *name, int length)
{
    int index = sol_chunk_add_name(c->scope->chunk, name, length);
    if (index > UINT16_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous, "too many names in one chunk");
        return 0;
    }
    return index;
}

static int constant_operand(Compiler *c, SolValue value)
{
    int index = sol_chunk_add_constant(c->scope->chunk, value);
    if (index > UINT16_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous,
                         "too many constants in one chunk");
        return 0;
    }
    return index;
}

/* An opcode and the side-table index it carries -- the shape most instructions
   have, now that those indices are two bytes. */
static void emit_indexed(Compiler *c, uint8_t op, int index)
{
    emit(c, op);
    emit_index(c, index);
}

/* ---- literals -------------------------------------------------------- */

/* `negate` is set only by `@math`'s unary minus, which folds `-3` back to the
   one constant `3` would have been rather than emitting a `negated` send after
   it. That is what makes the region's `-` value-preserving to the byte. */
static void integer_literal(Compiler *c, bool negate)
{
    const SolToken *token = &c->parser.previous;

    /* The tag says the base: '#' decimal, '$' hexadecimal, '%' binary. All
       three are integers and all three reach the same constant, so this is the
       whole of what the three spellings cost -- the machine never learns that
       there was more than one. */
    int base = token->start[0] == '$' ? 16
             : token->start[0] == '%' ? 2
             : 10;

    /* Skip the tag; strtoll handles the optional sign, which only decimal has. */
    errno = 0;
    char *end;
    long long value = strtoll(token->start + 1, &end, base);
    if (errno == ERANGE || (negate && value == INT64_MIN)) {
        sol_parser_error(&c->parser, token, "integer literal out of range");
        return;
    }
    if (negate) value = -value;
    emit_indexed(c, OP_CONST, constant_operand(c, SOL_INT_VAL((int64_t)value)));
}

static void float_literal(Compiler *c, bool negate)
{
    const SolToken *token = &c->parser.previous;
    double value = strtod(token->start, NULL);
    if (negate) value = -value;
    emit_indexed(c, OP_CONST, constant_operand(c, SOL_FLOAT_VAL(value)));
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

    /* Kept on the chunk as well as here, so that what the compiler knew about
       slot 3 outlives the compiler. Anything looking at a running frame could
       otherwise say `slot 3` and not `average`. */
    sol_chunk_name_slot(scope->chunk, scope->local_count, name, length);

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

/* Parses `| ... |` if it is there, anywhere it is there.
 *
 * This used to refuse a declaration at the top level of a script, and the
 * reason was real: a temporary needs a frame slot to live in, and the script's
 * frame reserved none. A name declared there was emitted as OP_SET_LOCAL
 * against the bottom of the expression stack, where it quietly overwrote
 * whatever the enclosing expression had already put there. The verifier refused
 * it -- a top-level OP_LOCAL indexed a frame of size zero -- so `solas` failed
 * at the point of writing the file and said the bytecode was inconsistent,
 * while Solis, which runs what it just compiled without verifying, answered
 * wrongly instead. One source mistake, reported as an internal fault by one
 * front end and not at all by the other.
 *
 * The frame has slots now. `SolChunk.slot_count` says how many, `sol_vm_run`
 * reserves them, and the verifier bounds-checks against the real number rather
 * than zero -- so the thing that had to be refused simply works, and the
 * restriction the refusal stood in for is gone. */
static void optional_declarations(Compiler *c)
{
    SolParser *p = &c->parser;

    if (!sol_parser_match(p, TOK_PIPE)) return;
    declarations(c);
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
        /* Saved and restored, so that an assignment inside the right-hand side
           of another one does not answer for it. */
        const SolToken *outer_name = c->assigning;
        bool outer_read = c->assigned_name_was_read;
        c->assigning = &name;
        c->assigned_name_was_read = false;

        expression(c);

        bool was_read = c->assigned_name_was_read;
        c->assigning = outer_name;
        c->assigned_name_was_read = outer_read;

        if (slot >= 0) {
            emit_access(c, true, depth, slot);
        } else {
            if (!was_read) note_global_binding(c, &name);
            emit_indexed(c, OP_SET_GLOBAL, name_operand(c, &name));
        }
        return;
    }

    if (slot >= 0) {
        emit_access(c, false, depth, slot);
    } else {
        if (c->assigning != NULL &&
            c->assigning->length == name.length &&
            memcmp(c->assigning->start, name.start, (size_t)name.length) == 0) {
            c->assigned_name_was_read = true;
        }
        emit_indexed(c, OP_GLOBAL, name_operand(c, &name));
    }
}

/* Resolves the escapes in a string token, answering a fresh NUL-terminated
 * buffer of `*out_length` bytes, or NULL after reporting the error. Separate
 * from emitting one because an `include` needs the text of its file name and
 * emits nothing at all.
 *
 * An unrecognised escape is an error rather than a literal backslash, so a typo
 * is caught where it is written instead of appearing in the output.
 *
 * There is no `\0`: the text table is NUL-terminated in memory, so an embedded
 * one would truncate the string. The wire format already carries lengths, so
 * lifting that means giving the in-memory table lengths too.
 */
static char *decode_string(Compiler *c, const SolToken *token, int *out_length)
{
    const char *source = token->start + 1;
    int length = token->length - 2;

    char *decoded = malloc((size_t)length + 1);
    if (decoded == NULL) {
        sol_parser_error(&c->parser, token, "out of memory reading a string");
        return NULL;
    }

    int out = 0;
    for (int i = 0; i < length; i++) {
        if (source[i] != '\\') {
            decoded[out++] = source[i];
            continue;
        }
        if (++i == length) {
            sol_parser_error(&c->parser, token, "a string ends with a lone backslash");
            free(decoded);
            return NULL;
        }
        switch (source[i]) {
        case '"':  decoded[out++] = '"';  break;
        case '\\': decoded[out++] = '\\'; break;
        case 'n':  decoded[out++] = '\n'; break;
        case 't':  decoded[out++] = '\t'; break;
        case 'r':  decoded[out++] = '\r'; break;
        default:
            sol_parser_error(&c->parser, token,
                             "unknown escape in a string; \\\" \\\\ \\n \\t \\r are the escapes");
            free(decoded);
            return NULL;
        }
    }

    decoded[out] = '\0';
    *out_length = out;
    return decoded;
}

/* The token spans the quotes, and `decode_string` has already resolved what is
   between them. The decoded bytes are interned in the chunk's text table
   alongside selectors and global names, all three being interned text. */
static void string_literal(Compiler *c)
{
    SolToken token = c->parser.previous;
    int length = 0;
    char *decoded = decode_string(c, &token, &length);
    if (decoded == NULL) return;

    emit_indexed(c, OP_STRING, name_literal(c, decoded, length));
    free(decoded);
}

static void primary(Compiler *c)
{
    SolParser *p = &c->parser;

    if (sol_parser_match(p, TOK_LBRACE))     { block_literal(c); return; }
    if (sol_parser_match(p, TOK_LBRACKET))   { array_literal(c); return; }
    if (sol_parser_match(p, TOK_IDENT))      { identifier(c); return; }
    if (sol_parser_match(p, TOK_INT))        { integer_literal(c, false); return; }
    if (sol_parser_match(p, TOK_FLOAT))      { float_literal(c, false); return; }
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
        emit_indexed(c, OP_SYMBOL,
                     name_literal(c, token.start + 1, token.length - 1));
        return;
    }

    /* `@math` is the one directive that answers a value, so it is the one that
       may stand here. Every other is a statement: `statement` has already taken
       the ones standing where they may, so reaching here means this one is
       buried in an expression, where a file compiled in would have nowhere to
       go. */
    if (p->current.type == TOK_DIRECTIVE) {
        if (token_is(&p->current, "@math")) { math_directive(c); return; }
        sol_parser_error(p, &p->current,
                         "a directive must stand alone as a statement");
        return;
    }

    /* An operator outside a region. Worth its own sentence: three of these five
       characters were *unexpected character* before `@math` existed, and
       "expected an expression" would send the reader looking for a missing
       operand rather than a missing region. */
    switch (p->current.type) {
    case TOK_PLUS: case TOK_MINUS: case TOK_STAR: case TOK_SLASH: case TOK_CARET:
        sol_parser_error(p, &p->current,
                         "an operator needs something to its left; inside "
                         "'@math(...)' only '-' may open an expression");
        return;
    default:
        break;
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
static void send_expression(Compiler *c)
{
    SolParser *p = &c->parser;

    /* `whileTrue` and `doUntil` have to be recognised before their receiver is
       compiled, since for both the receiver is a block whose code is spliced in
       rather than made. Everything else starts here. */
    if (!inline_while(c) && !inline_do_until(c)) primary(c);

    int     target_at = -1;      /* where the last zero-argument send started */
    int target_name = 0;

    /* Sends chain left to right: `a:add(#1):print` sends print to the sum. */
    while (sol_parser_match(p, TOK_COLON)) {
        sol_parser_consume(p, TOK_IDENT, "expected a message name after ':'");
        SolToken selector = p->previous;

        if (inline_conditional(c, &selector) || inline_logical(c, &selector)) {
            target_at = -1;              /* never a `receiver:name := value` */
            continue;
        }

        int at = c->scope->chunk->count;
        uint8_t argc = arguments(c);
        int name = name_operand(c, &selector);

        emit_indexed(c, OP_SEND, name);
        emit(c, argc);

        target_at = (argc == 0) ? at : -1;
        target_name = name;
    }

    if (target_at >= 0 && sol_parser_match(p, TOK_ASSIGN)) {
        c->scope->chunk->count = target_at;      /* unemit the send */
        expression(c);
        emit_indexed(c, OP_SET_SLOT, target_name);
    }

    /* An operator left over outside a region, reported here because here is
       where every expression ends: `b := a + 2` finishes at `a` and the stray
       `+` would otherwise be described by whatever came next -- *expected '.'
       between statements* at the top level, *expected ')' after arguments*
       inside a call. Those send the reader looking for a missing separator
       rather than a missing `@math`. */
    if (!p->lexer.infix) {
        switch (p->current.type) {
        case TOK_PLUS: case TOK_STAR: case TOK_SLASH: case TOK_CARET:
            sol_parser_error(p, &p->current,
                             "arithmetic is written as sends here; '@math(...)' "
                             "is where the operators are");
            break;
        default:
            break;
        }
    }
}

/* ---- @math: infix arithmetic ----------------------------------------- *
 *
 * `@math(a^2 + 3 * ((a/2):sin + b:sqrt))`.
 *
 * **Notation, never a second semantics.** Every operator lowers to the send it
 * reads as -- `+` to `add`, `^` to `pow` -- so the region emits exactly the
 * bytes the chain would have. That is the rule `[#1, #2]` already lives under,
 * and `array_literal` desugars the same way, from names the compiler supplies
 * rather than reads.
 *
 * **A term is an ordinary Solum expression**, which is why there is no
 * `sin(x)` here: a prefix-call rule would have to map `f(x)` to `x:f` and would
 * then break on `atan2`, which is class-side, and on `pow`, which takes an
 * argument. `(a/2):sin` needs no rule at all. Whether the prefix form earns a
 * place is a second decision, and the thing that should settle it is a page of
 * transcribed formulas rather than the example that prompted this.
 *
 * **The whole region is in the mode, nested constructs included.** `expression`
 * dispatches on it, so an argument list, an array literal, a group and a block
 * body inside `@math` all read as infix too. That is what makes `f:value(-3)`
 * and `[1.0, -3.0]` mean what they look like rather than being the one corner
 * where the rules change back.
 *
 *     sum     = product { ("+" | "-") product } .
 *     product = unary { ("*" | "/") unary } .
 *     unary   = "-" unary | power .
 *     power   = term [ "^" unary ] .
 *     term    = expression .
 */

/* An operator's send: one argument, and a name the compiler supplies. */
static void math_send(Compiler *c, const char *name, int length, uint8_t argc)
{
    emit_indexed(c, OP_SEND, name_literal(c, name, length));
    emit(c, argc);
}

/* `-3` is the constant `-3`, not `3` with a `negated` after it -- but only when
 * the literal really is what the minus applies to. `^` binds tighter, so in
 * `-2^2` the minus takes the power and not the 2.
 *
 * Answering that needs the token *after* the one the parser is holding, and
 * scanning a copy of the lexer is how this file already asks such a question --
 * see `inlinable_arguments`, which settles the same kind of thing before a byte
 * is written.
 */
static bool negated_literal(Compiler *c)
{
    SolParser *p = &c->parser;

    if (p->current.type != TOK_INT && p->current.type != TOK_FLOAT) return false;

    SolLexer ahead = p->lexer;
    if (sol_lexer_next(&ahead).type == TOK_CARET) return false;

    sol_parser_advance(p);
    if (p->previous.type == TOK_INT) integer_literal(c, true);
    else                             float_literal(c, true);
    return true;
}

/* Right-associative, and tighter than the unary minus above it, so `-2^2` is
   `-(2^2)` and `2^3^2` is `2^(3^2)`. SolaBasic's ladder made both of those
   calls first and agreeing with it costs nothing. */
static void math_power(Compiler *c)
{
    send_expression(c);
    if (sol_parser_match(&c->parser, TOK_CARET)) {
        math_unary(c);                       /* so `2^-3` reads as it looks */
        math_send(c, "pow", 3, 1);
    }
}

static void math_unary(Compiler *c)
{
    if (sol_parser_match(&c->parser, TOK_MINUS)) {
        if (negated_literal(c)) return;
        math_unary(c);
        math_send(c, "negated", 7, 0);
        return;
    }
    math_power(c);
}

static void math_product(Compiler *c)
{
    SolParser *p = &c->parser;
    math_unary(c);
    for (;;) {
        if (sol_parser_match(p, TOK_STAR))       { math_unary(c); math_send(c, "mul", 3, 1); }
        else if (sol_parser_match(p, TOK_SLASH)) { math_unary(c); math_send(c, "div", 3, 1); }
        else return;
    }
}

static void math_sum(Compiler *c)
{
    SolParser *p = &c->parser;
    math_product(c);
    for (;;) {
        if (sol_parser_match(p, TOK_PLUS))       { math_product(c); math_send(c, "add", 3, 1); }
        else if (sol_parser_match(p, TOK_MINUS)) { math_product(c); math_send(c, "sub", 3, 1); }
        else return;
    }
}

/* The one directive that is an expression, and the reason is the same one that
 * keeps `@include` a statement: an include has nowhere to compile a file into
 * inside an expression, and this has nowhere else to be. It answers a value.
 *
 * The lexer's mode is set before the '(' is consumed and cleared before the ')'
 * is, so the tokens on either side of the region are scanned by the rules of
 * where they actually are. Saved and restored rather than assigned, so a
 * `@math` inside a `@math` leaves the outer one as it found it.
 */
static void math_directive(Compiler *c)
{
    SolParser *p = &c->parser;
    sol_parser_advance(p);                       /* the '@math' itself */

    bool was_infix = p->lexer.infix;
    p->lexer.infix = true;
    sol_parser_consume(p, TOK_LPAREN, "expected '(' after '@math'");

    math_sum(c);

    p->lexer.infix = was_infix;
    sol_parser_consume(p, TOK_RPAREN, "expected ')' closing '@math'");
}

/* Inside a `@math` region every expression is an infix one, nested constructs
   included. Outside, the language has no operators and this is the send chain
   it always was. */
static void expression(Compiler *c)
{
    if (c->parser.lexer.infix) { math_sum(c); return; }
    send_expression(c);
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
        offset += sol_op_length(op);
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

    emit_indexed(c, OP_GLOBAL, name_literal(c, "array", 5));

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

    emit_indexed(c, OP_SEND, name_literal(c, "of", 2));
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

/* The statements between `{` and `}`, leaving the last one's value on the
 * stack, and consuming the closing brace. Shared with the inlined conditionals,
 * which compile the very same body into the enclosing chunk instead. */
static void block_body(Compiler *c)
{
    SolParser *p = &c->parser;

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
    block_body(c);
    emit(c, OP_RETURN);
    c->scope = scope.enclosing;

    code->slot_count = scope.local_count;
    code->captures = touches_home(&code->chunk);

    int index = sol_chunk_add_method(c->scope->chunk, code);
    if (index > UINT16_MAX) {
        sol_parser_error(p, &p->previous, "too many blocks in one chunk");
        return;
    }
    emit_indexed(c, OP_BLOCK, index);
}

/* ---- inlined control flow ------------------------------------------------
 *
 * `ifTrue`, `ifFalse`, `ifElse`, and `whileTrue` are ordinary messages, and a
 * program can still send them that way -- through `perform`, or with a block
 * held in a variable. But written literally, which is how they are almost
 * always written, the compiler can emit jumps around the bodies instead of
 * allocating a block and entering a frame per branch or per pass.
 *
 * This is an optimisation and must not change what the program means, which is
 * where the restrictions come from. It applies only when every argument is a
 * block written right there, with no parameters and no temporaries:
 *
 *   - a block with parameters is an arity error when `ifElse` calls it with
 *     none, and inlining would quietly make it work;
 *   - a block's temporaries belong to its own frame, and inlining would declare
 *     them in the enclosing one, where they could collide with a name already
 *     there -- turning an optimisation into a compile error.
 *
 * Anything else falls back to a real send, so the slow path stays correct
 * rather than merely unused.
 */

/* Is the block starting at `probe` (positioned just after its `{`) free of
   parameters and temporaries? Scans a copy, disturbing nothing. */
static bool block_is_plain(SolLexer probe)
{
    SolToken first = sol_lexer_next(&probe);
    if (first.type == TOK_PIPE) return false;         /* temporaries */
    if (first.type != TOK_IDENT) return true;

    /* `a |` and `a, b |` are parameter lists; a bare `a` is a body. */
    SolToken next = sol_lexer_next(&probe);
    while (next.type == TOK_COMMA) {
        if (sol_lexer_next(&probe).type != TOK_IDENT) return true;
        next = sol_lexer_next(&probe);
    }
    return next.type != TOK_PIPE;
}

/* Advances `probe` past the block whose `{` has just been read. */
static bool skip_block(SolLexer *probe)
{
    for (int depth = 1; depth > 0; ) {
        SolToken token = sol_lexer_next(probe);
        if (token.type == TOK_EOF || token.type == TOK_ERROR) return false;
        if (token.type == TOK_LBRACE) depth++;
        if (token.type == TOK_RBRACE) depth--;
    }
    return true;
}

/* Does the argument list ahead consist of exactly `wanted` inlinable blocks?
   The parser is single-pass and emits as it goes, so this has to be settled
   before a single byte is written. */
static bool inlinable_arguments(Compiler *c, int wanted)
{
    SolLexer probe = c->parser.lexer;      /* positioned just after `(` */

    for (int i = 0; i < wanted; i++) {
        if (i > 0 && sol_lexer_next(&probe).type != TOK_COMMA) return false;
        if (sol_lexer_next(&probe).type != TOK_LBRACE) return false;
        if (!block_is_plain(probe)) return false;
        if (!skip_block(&probe)) return false;
    }
    return sol_lexer_next(&probe).type == TOK_RPAREN;
}

/* Closes a loop by jumping back to `top`. The only backward jump we emit, and
   the offset is subtracted rather than added, so it stays unsigned like the
   others. */
static void emit_loop(Compiler *c, int top)
{
    emit(c, OP_LOOP);

    int distance = c->scope->chunk->count + 2 - top;   /* from past the operand */
    if (distance > UINT16_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous,
                         "loop body is too large to jump back over");
        distance = 0;
    }
    emit(c, sol_u16_first((uint16_t)distance));
    emit(c, sol_u16_second((uint16_t)distance));
}

/* Emits a jump with a blank offset, answering where to patch it. */
static int emit_jump(Compiler *c, uint8_t op)
{
    emit(c, op);
    emit(c, 0xff);
    emit(c, 0xff);
    return c->scope->chunk->count - 2;
}

/* Points a jump emitted earlier at the instruction about to be written. */
static void patch_jump(Compiler *c, int slot)
{
    SolChunk *chunk = c->scope->chunk;
    /* The offset is measured from the end of the whole instruction, which is
       not always the end of the operand being patched -- OP_JUMP_IF_FALSE
       carries a selector after it. */
    int from = slot - 1 + sol_op_length(chunk->code[slot - 1]);
    int distance = chunk->count - from;

    if (distance > UINT16_MAX) {
        sol_parser_error(&c->parser, &c->parser.previous,
                         "conditional is too large to jump over");
        return;
    }
    sol_write_u16(&chunk->code[slot], (uint16_t)distance);
}

/* Compiles one `{ ... }` argument straight into the enclosing chunk. Because it
   is the enclosing scope, a name resolves exactly as it would have from inside
   the block, one lexical level nearer -- so OP_OUTER depths come out right
   without anything having to adjust them. */
static void inline_branch(Compiler *c)
{
    sol_parser_consume(&c->parser, TOK_LBRACE, "expected a block");
    block_body(c);
}

/* Answers whether it handled the send. The receiver is already compiled and on
   the stack; `selector` has been consumed. */
static bool inline_conditional(Compiler *c, const SolToken *selector)
{
    SolParser *p = &c->parser;

    bool if_true  = token_is(selector, "ifTrue");
    bool if_false = token_is(selector, "ifFalse");
    bool if_else  = token_is(selector, "ifElse");
    if (!if_true && !if_false && !if_else) return false;

    if (p->current.type != TOK_LPAREN) return false;
    if (!inlinable_arguments(c, if_else ? 2 : 1)) return false;

    int name = name_operand(c, selector);
    sol_parser_consume(p, TOK_LPAREN, "expected '(' after the message name");

    /* The condition is on the stack; this pops it and branches. */
    int to_else = emit_jump(c, OP_JUMP_IF_FALSE);
    emit_index(c, name);

    if (if_false) {
        /* Inverted: the branch that *is* taken runs the body, so falling
           through is the true case and answers nil. Nothing needs popping --
           the false path jumps over the nil rather than past it. */
        emit(c, OP_NIL);
        int to_end = emit_jump(c, OP_JUMP);
        patch_jump(c, to_else);
        inline_branch(c);
        patch_jump(c, to_end);
    } else {
        inline_branch(c);
        int to_end = emit_jump(c, OP_JUMP);
        patch_jump(c, to_else);
        if (if_else) {
            sol_parser_consume(p, TOK_COMMA, "expected ',' between the branches");
            inline_branch(c);
        } else {
            emit(c, OP_NIL);             /* `ifTrue` answers nil when it is not */
        }
        patch_jump(c, to_end);
    }

    sol_parser_consume(p, TOK_RPAREN, "expected ')' after arguments");
    return true;
}

/* `and` and `or`, which short-circuit through a block exactly as `ifTrue` does
 * -- which is why they take one rather than a boolean, and why the same jumps
 * serve.
 *
 * They differ from the conditionals in what comes out. `ifTrue` answers nil on
 * the path it does not take, and any value on the path it does; `and` answers a
 * boolean either way, and the one it answers on the long path is whatever the
 * block said. So the block's answer is the reply, and it has to be a boolean --
 * which is the check the primitive makes after calling the block, and which
 * OP_CHECK_BOOL makes here, in the same words.
 *
 *      and:                            or:
 *        JUMP_IF_FALSE -> false          JUMP_IF_FALSE -> run
 *        <body>                          CONST true
 *        CHECK_BOOL                      JUMP -> end
 *        JUMP -> end                   run:
 *      false:                            <body>
 *        CONST false                     CHECK_BOOL
 *      end:                            end:
 *
 * The short-circuit answer is a constant rather than the global `true` or
 * `false`, which a program can rebind: reading it would make the shortcut and
 * the long path disagree about what `and` answers.
 */
static bool inline_logical(Compiler *c, const SolToken *selector)
{
    SolParser *p = &c->parser;

    bool is_and = token_is(selector, "and");
    bool is_or  = token_is(selector, "or");
    if (!is_and && !is_or) return false;

    if (p->current.type != TOK_LPAREN) return false;
    if (!inlinable_arguments(c, 1)) return false;

    int name = name_operand(c, selector);
    sol_parser_consume(p, TOK_LPAREN, "expected '(' after the message name");

    /* Pops the receiver and branches on it. A non-boolean is reported here as
       not understanding the message, which is what the send would have said --
       `and` lives on the boolean class, so no other receiver finds it. */
    int to_shortcut = emit_jump(c, OP_JUMP_IF_FALSE);
    emit_index(c, name);

    if (is_and) {
        inline_branch(c);
        emit_indexed(c, OP_CHECK_BOOL, name);
        int to_end = emit_jump(c, OP_JUMP);
        patch_jump(c, to_shortcut);
        emit_indexed(c, OP_CONST, constant_operand(c, SOL_BOOL_VAL(false)));
        patch_jump(c, to_end);
    } else {
        /* Inverted, as `ifFalse` is: a true receiver settles `or`, so the
           branch that falls through is the shortcut and the one taken runs the
           block. */
        emit_indexed(c, OP_CONST, constant_operand(c, SOL_BOOL_VAL(true)));
        int to_end = emit_jump(c, OP_JUMP);
        patch_jump(c, to_shortcut);
        inline_branch(c);
        emit_indexed(c, OP_CHECK_BOOL, name);
        patch_jump(c, to_end);
    }

    sol_parser_consume(p, TOK_RPAREN, "expected ')' after arguments");
    return true;
}

/* `{ condition }:whileTrue({ body })`.
 *
 * The odd one out, because the condition is the *receiver*: by the time the
 * selector has been read, an ordinary compile would already have emitted an
 * OP_BLOCK for it. So this runs before the receiver is compiled at all, reading
 * ahead over the whole form to decide, and the parser stays single-pass -- it
 * still never revisits a token it has emitted for.
 *
 * The same two restrictions as the conditionals, for the same reasons, and now
 * on the receiver as well: both blocks must be written right there, with no
 * parameters and no temporaries. `whileTrue` calls each with none, and their
 * temporaries would land in the enclosing frame.
 *
 *      loop:  <condition>          -- re-run every pass, which is why it is a
 *             EXIT_IF_FALSE -> end    block in the source and not a value
 *             <body>
 *             POP                  -- the body's value is discarded
 *             LOOP -> loop
 *      end:   NIL                  -- what whileTrue answers
 *
 * Answers whether it handled the expression; nothing has been emitted if not.
 */
/* `{ body }:doUntil({ condition })` -- the body first, then the test.
 *
 * Shaped like `inline_while` and different in two ways. The body comes first,
 * so it runs before anything is tested, which is the whole point of the message
 * and the one loop `whileTrue` cannot express without a flag. And the sense is
 * inverted: this leaves when the condition is *true*.
 *
 * There is no OP_EXIT_IF_TRUE, and adding one would have meant a new opcode and
 * a name index on it to complain with. OP_CHECK_BOOL already carries a name and
 * already refuses a non-boolean, so it goes in front: the check errors as
 * `doUntil` if the condition answered something else, and by the time
 * OP_EXIT_IF_FALSE sees the value it can only be a boolean, so its `whileTrue`
 * wording is unreachable. What that costs is one instruction and one jump an
 * iteration, against two block calls and two frames saved.
 *
 *      top:  body / POP / condition / CHECK_BOOL
 *            EXIT_IF_FALSE -> again        ; false: go round
 *            JUMP          -> end          ; true: leave
 *      again: LOOP -> top
 *      end:  NIL
 */
static bool inline_do_until(Compiler *c)
{
    SolParser *p = &c->parser;

    if (p->current.type != TOK_LBRACE) return false;

    /* Read the whole thing on a copy of the lexer before committing to any of
       it, as `inline_while` does. */
    SolLexer probe = p->lexer;                 /* positioned just after the `{` */
    if (!block_is_plain(probe)) return false;
    if (!skip_block(&probe)) return false;
    if (sol_lexer_next(&probe).type != TOK_COLON) return false;

    SolToken selector = sol_lexer_next(&probe);
    if (selector.type != TOK_IDENT || !token_is(&selector, "doUntil")) return false;

    if (sol_lexer_next(&probe).type != TOK_LPAREN) return false;
    if (sol_lexer_next(&probe).type != TOK_LBRACE) return false;
    if (!block_is_plain(probe)) return false;
    if (!skip_block(&probe)) return false;
    if (sol_lexer_next(&probe).type != TOK_RPAREN) return false;

    int top = c->scope->chunk->count;
    inline_branch(c);                          /* the body */
    emit(c, OP_POP);

    sol_parser_consume(p, TOK_COLON, "expected ':' before 'doUntil'");
    sol_parser_consume(p, TOK_IDENT, "expected 'doUntil'");
    sol_parser_consume(p, TOK_LPAREN, "expected '(' after the message name");

    inline_branch(c);                          /* the condition */
    emit_indexed(c, OP_CHECK_BOOL, name_literal(c, "doUntil", 7));

    int to_again = emit_jump(c, OP_EXIT_IF_FALSE);
    int to_end   = emit_jump(c, OP_JUMP);

    patch_jump(c, to_again);
    emit_loop(c, top);

    patch_jump(c, to_end);
    emit(c, OP_NIL);

    sol_parser_consume(p, TOK_RPAREN, "expected ')' after arguments");
    return true;
}

static bool inline_while(Compiler *c)
{
    SolParser *p = &c->parser;

    if (p->current.type != TOK_LBRACE) return false;

    /* Read the whole `{ ... }:whileTrue({ ... })` on a copy of the lexer before
       committing to any of it. */
    SolLexer probe = p->lexer;                 /* positioned just after the `{` */
    if (!block_is_plain(probe)) return false;
    if (!skip_block(&probe)) return false;
    if (sol_lexer_next(&probe).type != TOK_COLON) return false;

    SolToken selector = sol_lexer_next(&probe);
    if (selector.type != TOK_IDENT || !token_is(&selector, "whileTrue")) return false;

    if (sol_lexer_next(&probe).type != TOK_LPAREN) return false;
    if (sol_lexer_next(&probe).type != TOK_LBRACE) return false;
    if (!block_is_plain(probe)) return false;
    if (!skip_block(&probe)) return false;
    if (sol_lexer_next(&probe).type != TOK_RPAREN) return false;

    int top = c->scope->chunk->count;
    inline_branch(c);                          /* the condition */

    int to_end = emit_jump(c, OP_EXIT_IF_FALSE);

    sol_parser_consume(p, TOK_COLON, "expected ':' before 'whileTrue'");
    sol_parser_consume(p, TOK_IDENT, "expected 'whileTrue'");
    sol_parser_consume(p, TOK_LPAREN, "expected '(' after the message name");

    inline_branch(c);                          /* the body */
    emit(c, OP_POP);
    emit_loop(c, top);

    patch_jump(c, to_end);
    emit(c, OP_NIL);

    sol_parser_consume(p, TOK_RPAREN, "expected ')' after arguments");
    return true;
}

/* An include is a compile-time directive rather than a message:
 *
 *     @include "lib.sol".
 *
 * compiles that file into this chunk at that point, as though its text had been
 * written there. Globals are one flat namespace and stay one -- two files
 * binding the same name collide exactly as two `:=` in one file already do, the
 * later winning -- so there is nothing here beyond finding the file.
 *
 * The '@' is what says this is not a message. It was spelled `"lib.sol":include`
 * to begin with, because that shape already parsed -- and it read as a send to a
 * string, which it never was: no string was pushed, nothing was sent, and the
 * whole thing had vanished before the program ran. The disguise cost a two-token
 * lookahead in `statement` to spot one, and a special error in `primary` to
 * refuse the same shape everywhere else it parsed. A distinct token needs
 * neither: it is a directive from its first character.
 *
 * '@' names the space rather than this one word. What follows it happens while
 * compiling, and nothing there is a message to anything.
 *
 * The file is found relative to the file including it, not to the working
 * directory, so a program can be moved without its includes breaking. At the
 * prompt there is no file to be relative to, and the working directory it is.
 *
 * Each file is compiled at most once per compilation, keyed by where it turns
 * out to be on disk. C compiles it every time and leaves the file to guard
 * itself, which needs conditional compilation -- Solum has none -- and a second
 * copy could only rebind names already bound and repeat whatever the file did
 * on the way. Compiling once also means a cycle stops instead of recurring.
 */
#define SOL_MAX_INCLUDE_DEPTH 64

static char *copy_string(const char *text)
{
    size_t length = strlen(text);
    char *copy = malloc(length + 1);
    if (copy != NULL) memcpy(copy, text, length + 1);
    return copy;
}

/* Joins the name in an include to the directory of the file doing the
   including. An absolute name, or an includer that came from no file, is taken
   as it stands. */
/* ---- the search path --------------------------------------------------- */

void sol_search_path_init(SolSearchPath *search)
{
    search->directories = NULL;
    search->count = 0;
    search->capacity = 0;
}

void sol_search_path_add(SolSearchPath *search, const char *directory)
{
    if (directory == NULL || directory[0] == '\0') return;

    if (search->capacity < search->count + 1) {
        int capacity = search->capacity < 4 ? 4 : search->capacity * 2;
        char **grown = realloc(search->directories, sizeof(char *) * (size_t)capacity);
        if (grown == NULL) return;          /* the include simply will not find it */
        search->directories = grown;
        search->capacity = capacity;
    }

    char *copy = copy_string(directory);
    if (copy == NULL) return;
    search->directories[search->count++] = copy;
}

void sol_search_path_free(SolSearchPath *search)
{
    for (int i = 0; i < search->count; i++) free(search->directories[i]);
    free(search->directories);
    sol_search_path_init(search);
}

/* `SOLUM_PATH` first, then the library beside the binary, then where the
 * install put it.
 *
 * The second is derived from argv[0], which says where the binary is only when
 * it was named with a path -- `./bin/solas` or an absolute one. Invoked by bare
 * name through PATH it says nothing, and searching PATH over again to guess is
 * not done here.
 *
 * The third is what an installed binary has instead, and it is not a guess: the
 * Makefile writes SOL_LIB_DIR from the same PREFIX that `make install` copies
 * the library to, so the binary is told rather than left to work it out. It is
 * last because a checkout has to keep winning over anything installed on the
 * machine -- otherwise testing a change would silently read the old library.
 * `SOLUM_PATH` and `-I` still come first and still override everything. */
void sol_search_path_add_defaults(SolSearchPath *search, const char *argv0)
{
    const char *env = getenv("SOLUM_PATH");
    if (env != NULL) {
        const char *at = env;
        while (*at != '\0') {
            const char *colon = strchr(at, ':');
            size_t length = colon == NULL ? strlen(at) : (size_t)(colon - at);

            if (length > 0) {
                char *directory = malloc(length + 1);
                if (directory != NULL) {
                    memcpy(directory, at, length);
                    directory[length] = '\0';
                    sol_search_path_add(search, directory);
                    free(directory);
                }
            }
            if (colon == NULL) break;
            at = colon + 1;
        }
    }

    /* `bin/solas` -> `bin/../lib`, which is `lib` beside it. */
    const char *slash = argv0 == NULL ? NULL : strrchr(argv0, '/');
    if (slash != NULL) {
        size_t directory = (size_t)(slash - argv0) + 1;
        static const char *suffix = "../lib";

        char *shipped = malloc(directory + strlen(suffix) + 1);
        if (shipped != NULL) {
            memcpy(shipped, argv0, directory);
            memcpy(shipped + directory, suffix, strlen(suffix) + 1);
            sol_search_path_add(search, shipped);
            free(shipped);
        }
    }

#if defined(SOL_LIB_DIR)
    sol_search_path_add(search, SOL_LIB_DIR);
#endif
}

static char *resolve_against(const char *including, const char *name)
{
    const char *slash = including == NULL ? NULL : strrchr(including, '/');
    if (name[0] == '/' || slash == NULL) return copy_string(name);

    size_t directory = (size_t)(slash - including) + 1;
    size_t length = strlen(name);

    char *joined = malloc(directory + length + 1);
    if (joined == NULL) return NULL;
    memcpy(joined, including, directory);
    memcpy(joined + directory, name, length + 1);
    return joined;
}

/* What to key a file by: where it really is, so that two spellings of one file
   are one file. Falls back to the path as written when it cannot be resolved,
   which means the file is missing and the read is about to say so. */
/* Is there a file here to read? Asked before choosing a path rather than by
   reading and discarding, so a name found on the search path is opened once. */
static bool readable(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL) return false;
    fclose(f);
    return true;
}

static char *join_path(const char *directory, const char *name)
{
    size_t length = strlen(directory);
    bool slash = length > 0 && directory[length - 1] == '/';

    char *joined = malloc(length + (slash ? 0 : 1) + strlen(name) + 1);
    if (joined == NULL) return NULL;

    memcpy(joined, directory, length);
    if (!slash) joined[length++] = '/';
    memcpy(joined + length, name, strlen(name) + 1);
    return joined;
}

/* Beside the file including it first, then the search path -- C's rule for a
   quoted include, and for C's reason: your own files are found without saying
   where they are, and a name you do not have locally comes from the library.
   An absolute name is taken as it stands and searches nothing.

   Answers the relative candidate when nothing is found anywhere, so that the
   error names the file the program most likely meant. */
static char *resolve_include(Compiler *c, const char *name)
{
    char *relative = resolve_against(c->path, name);
    if (relative == NULL || name[0] == '/') return relative;
    if (readable(relative)) return relative;

    if (c->search != NULL) {
        for (int i = 0; i < c->search->count; i++) {
            char *candidate = join_path(c->search->directories[i], name);
            if (candidate == NULL) continue;
            if (readable(candidate)) {
                free(relative);
                return candidate;
            }
            free(candidate);
        }
    }
    return relative;
}

/* The file of this name the search path would have found, had the includer not
   had one beside it. Only for the warning below: it names what was shadowed, so
   the reader is told which file they were expecting rather than only that they
   did not get it. */
static char *on_search_path(const Compiler *c, const char *name)
{
    if (c->search == NULL || name[0] == '/') return NULL;

    for (int i = 0; i < c->search->count; i++) {
        char *candidate = join_path(c->search->directories[i], name);
        if (candidate == NULL) continue;
        if (readable(candidate)) return candidate;
        free(candidate);
    }
    return NULL;
}

static char *identity_of(const char *path)
{
    char *real = realpath(path, NULL);
    return real != NULL ? real : copy_string(path);
}

static bool already_included(const Includes *includes, const char *identity)
{
    for (int i = 0; i < includes->count; i++) {
        if (strcmp(includes->paths[i], identity) == 0) return true;
    }
    return false;
}

/* Takes ownership of `identity`. */
static void remember_included(Includes *includes, char *identity)
{
    if (includes->capacity < includes->count + 1) {
        int capacity = includes->capacity < 8 ? 8 : includes->capacity * 2;
        char **paths = realloc(includes->paths, sizeof(char *) * (size_t)capacity);
        if (paths == NULL) {
            fprintf(stderr, "solas: out of memory\n");
            exit(1);
        }
        includes->paths = paths;
        includes->capacity = capacity;
    }
    includes->paths[includes->count++] = identity;
}

static void includes_free(Includes *includes)
{
    for (int i = 0; i < includes->bound_count; i++) {
        free(includes->bound[i].name);
        free(includes->bound[i].file);
    }
    free(includes->bound);

    for (int i = 0; i < includes->count; i++) free(includes->paths[i]);
    free(includes->paths);
}

/* Compiles one file's statements into the chunk `parent` is filling, sharing
   its scope: an included file's top level is the top level. */
static bool compile_included(Compiler *parent, const char *source, const char *path)
{
    Compiler c;
    c.scope = parent->scope;
    c.path = path;
    c.includes = parent->includes;
    c.search = parent->search;
    c.assigning = NULL;
    c.assigned_name_was_read = false;
    sol_parser_init(&c.parser, source, path);

    while (!sol_parser_match(&c.parser, TOK_EOF)) {
        statement(&c);
    }
    return !c.parser.had_error;
}

/* One global, bound. Warns when a *different* file bound the same name first.
 *
 * There is no module system: an included file binds into the one global
 * namespace, so two files that both use a name do not collide -- the later one
 * wins, quietly, and which one a program gets depends on include order rather
 * than on anything written where the name is used. That is roadmap 6.21, and
 * this is the cheap half of what a module system would give: not a namespace,
 * but a sentence saying the namespace was shared.
 *
 * `lib/text.sol` is why this exists. It bound one object called `text`, the
 * first program to use it had a variable of that name, and the library broke
 * from a distance with `string does not understand 'utf8'` -- a run-time
 * message about a type, for a compile-time collision between two files.
 *
 * A warning rather than an error, because rebinding is legal and sometimes
 * meant: a program may want to replace something a library bound. Saying so
 * without forbidding it is the bargain the self-include warning already struck.
 *
 * Only globals. A library that adds `integer:asUtf8` binds no name at all --
 * that is a send, not an assignment -- which is why the tiers in 6.21 put a
 * method on a built-in class above an object of one's own.
 *
 * And only a *claim*, not an update. `times := times:add(#1)` reads the name
 * before writing it, so it is working on somebody else's global rather than
 * declaring its own, and that is a thing files legitimately do across an
 * include. The caller decides which this is; the rule is that a name you read
 * in the course of assigning it is one you are updating.
 */
static void note_global_binding(Compiler *c, const SolToken *name)
{
    Includes *includes = c->includes;
    if (includes == NULL) return;

    for (int i = 0; i < includes->bound_count; i++) {
        BoundName *bound = &includes->bound[i];
        if ((int)strlen(bound->name) != name->length ||
            memcmp(bound->name, name->start, (size_t)name->length) != 0) {
            continue;
        }

        bool same_file = (bound->file == NULL && c->path == NULL) ||
                         (bound->file != NULL && c->path != NULL &&
                          strcmp(bound->file, c->path) == 0);
        if (same_file) return;           /* a file rebinding its own name */

        char message[512];
        snprintf(message, sizeof message,
                 "'%.*s' was already bound by %s -- this one wins, and nothing "
                 "else will say so",
                 name->length, name->start,
                 bound->file != NULL ? bound->file : "earlier input");
        sol_parser_warning(&c->parser, name, message);

        /* This file owns the name from here on, so rebinding it again below is
           silent and a third file is told about this one rather than the first.
           One warning per collision is the useful amount. */
        char *owner = c->path != NULL ? copy_string(c->path) : NULL;
        if (c->path == NULL || owner != NULL) {
            free(bound->file);
            bound->file = owner;
        }
        return;
    }

    if (includes->bound_capacity < includes->bound_count + 1) {
        int capacity = includes->bound_capacity < 8
                     ? 8 : includes->bound_capacity * 2;
        BoundName *grown = realloc(includes->bound,
                                   sizeof(BoundName) * (size_t)capacity);
        if (grown == NULL) return;       /* the warning is not worth failing for */
        includes->bound = grown;
        includes->bound_capacity = capacity;
    }

    char *copy = malloc((size_t)name->length + 1);
    if (copy == NULL) return;
    memcpy(copy, name->start, (size_t)name->length);
    copy[name->length] = '\0';

    char *file = c->path != NULL ? copy_string(c->path) : NULL;
    if (c->path != NULL && file == NULL) { free(copy); return; }

    includes->bound[includes->bound_count].name = copy;
    includes->bound[includes->bound_count].file = file;
    includes->bound_count++;
}

/* Entered with `@include` consumed and the file name next. */
static void include_directive(Compiler *c)
{
    SolParser *p = &c->parser;

    if (p->current.type != TOK_STRING) {
        sol_parser_error(p, &p->current, "@include needs a file name in quotes");
        return;
    }
    sol_parser_advance(p);
    SolToken where = p->previous;

    if (!sol_parser_match(p, TOK_DOT) && p->current.type != TOK_EOF) {
        sol_parser_error(p, &p->current, "expected '.' between statements");
    }

    int length = 0;
    char *name = decode_string(c, &where, &length);
    if (name == NULL) return;
    if (length == 0) {
        sol_parser_error(p, &where, "@include needs a file name");
        free(name);
        return;
    }

    char *path = resolve_include(c, name);
    if (path == NULL) {
        sol_parser_error(p, &where, "out of memory resolving an include");
        free(name);
        return;
    }

    char *identity = identity_of(path);
    if (identity == NULL) {
        sol_parser_error(p, &where, "out of memory resolving an include");
        free(name);
        free(path);
        return;
    }

    /* A file that includes a library of its own name finds *itself*: the search
       looks beside the includer first, and a file is beside itself. Since a
       file is compiled once, the include then does nothing at all -- the
       program compiles cleanly and fails at run time with an undefined name,
       which is a long way from the line that caused it.
     *
       Shadowing is C's rule and worth keeping; a file including itself is not
       what anybody meant, and the compiler is holding both halves of the
       question. So this is a warning and not an error: the file is still
       compiled, and the status is unchanged.
     *
       Only the direct case. Two files that include each other are a cycle that
       include-once ends on purpose, and a file reached twice by different
       routes is the ordinary reason include-once exists. Neither is a mistake. */
    if (c->path != NULL) {
        char *self = identity_of(c->path);
        if (self != NULL && strcmp(self, identity) == 0) {
            char *shadowed = on_search_path(c, name);
            char message[512];
            if (shadowed != NULL) {
                snprintf(message, sizeof message,
                         "this file includes itself, so the include does nothing "
                         "-- a file beside the includer wins, and '%s' on the "
                         "search path is what it shadowed", shadowed);
            } else {
                snprintf(message, sizeof message,
                         "this file includes itself, so the include does nothing");
            }
            sol_parser_warning(p, &where, message);
            free(shadowed);
        }
        free(self);
    }

    free(name);

    if (already_included(c->includes, identity)) {
        free(identity);
        free(path);
        return;
    }

    if (c->includes->depth >= SOL_MAX_INCLUDE_DEPTH) {
        sol_parser_error(p, &where, "includes nested too deeply");
        free(identity);
        free(path);
        return;
    }

    char *source = sol_read_file(path);
    if (source == NULL) {
        char message[512];
        if (c->search != NULL && c->search->count > 0 && path[0] != '/') {
            snprintf(message, sizeof message,
                     "cannot read the included file '%s', and it is not on the "
                     "search path either", path);
        } else {
            snprintf(message, sizeof message, "cannot read the included file '%s'", path);
        }
        sol_parser_error(p, &where, message);
        free(identity);
        free(path);
        return;
    }
    remember_included(c->includes, identity);   /* before compiling: a cycle ends here */

    c->includes->depth++;
    bool ok = compile_included(c, source, path);
    c->includes->depth--;

    if (!ok) {
        /* The errors have been reported against the included file, which on its
           own does not say how the compiler got there. */
        p->had_error = true;
        if (c->path != NULL) {
            fprintf(stderr, "  ... included from %s, line %d\n", c->path, where.line);
        } else {
            fprintf(stderr, "  ... included from line %d\n", where.line);
        }
    }

    free(source);
    free(path);
}

/* Which directive this is. There is one, and an unknown one is refused here
   rather than left to parse as something else: `@` is the compiler's own space,
   so a name in it that the compiler does not know is a mistake, not a message
   it might learn later. */
static void directive_statement(Compiler *c)
{
    SolParser *p = &c->parser;
    SolToken name = p->current;
    sol_parser_advance(p);

    if (token_is(&name, "@include")) {
        include_directive(c);
        return;
    }

    /* The error prints the offending token and underlines it, so naming it here
       too would only say it twice. */
    sol_parser_error(p, &name, "unknown directive");
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

    /* A directive stands alone, and this is the only place one may stand --
       except `@math`, which answers a value, so a statement opening with one is
       an expression statement like any other. */
    if (p->current.type == TOK_DIRECTIVE && !token_is(&p->current, "@math")) {
        directive_statement(c);
        if (p->panicked) synchronise(c);
        return;
    }

    expression(c);
    if (!sol_parser_match(p, TOK_DOT) && p->current.type != TOK_EOF) {
        sol_parser_error(p, &p->current, "expected '.' between statements");
    }
    emit(c, OP_POP);                         /* a statement leaves nothing behind */

    if (p->panicked) synchronise(c);
}

char *sol_read_file(const char *path)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) return NULL;

    if (fseek(file, 0L, SEEK_END) != 0) { fclose(file); return NULL; }
    long size = ftell(file);
    if (size < 0) { fclose(file); return NULL; }
    rewind(file);

    char *buffer = malloc((size_t)size + 1);
    if (buffer == NULL) { fclose(file); return NULL; }

    /* A short read is a failure rather than a shorter program: `fopen` on a
       directory succeeds on some systems, and reading one does not. */
    size_t read = fread(buffer, 1, (size_t)size, file);
    fclose(file);
    if (read != (size_t)size) {
        free(buffer);
        return NULL;
    }
    buffer[read] = '\0';
    return buffer;
}

bool sol_compile_source(const char *source, const char *path, SolChunk *chunk)
{
    return sol_compile_file(source, path, NULL, chunk);
}

bool sol_compile_file(const char *source, const char *path,
                      const SolSearchPath *search, SolChunk *chunk)
{
    Scope top;
    top.enclosing = NULL;
    top.chunk = chunk;
    top.local_count = 0;
    top.in_method = false;      /* no self: a script has no receiver */
    top.is_block = false;

    /* Slot 0 is reserved and unnameable, as it is in a block frame -- there it
       holds the receiver, and here it holds nothing, so that a slot index means
       the same thing wherever it is written. A temporary declared at the top
       level lands in slot 1 upwards. */
    declare_local(&top, "", 0);

    Includes includes;
    includes.paths = NULL;
    includes.count = 0;
    includes.capacity = 0;
    includes.depth = 0;
    includes.bound = NULL;
    includes.bound_count = 0;
    includes.bound_capacity = 0;

    Compiler c;
    c.scope = &top;
    c.path = path;
    c.includes = &includes;
    c.search = search;
    c.assigning = NULL;
    c.assigned_name_was_read = false;
    sol_parser_init(&c.parser, source, path);

    /* The file being compiled counts as included, so that a file reached
       through its own includes is not compiled a second time. */
    if (path != NULL) {
        char *identity = identity_of(path);
        if (identity != NULL) remember_included(&includes, identity);
    }

    while (!sol_parser_match(&c.parser, TOK_EOF)) {
        statement(&c);
    }
    emit(&c, OP_HALT);

    /* What the script's frame must reserve. `sol_vm_run` reads it. */
    chunk->slot_count = top.local_count;

    includes_free(&includes);
    return !c.parser.had_error;
}

bool sol_compile(const char *source, SolChunk *chunk)
{
    return sol_compile_source(source, NULL, chunk);
}
