/* lex.c -- the fixed core lexer.
 *
 * Solveig's spellings, deliberately: `#42` for an integer against bare `42` for
 * a float, `'name` for a symbol, `;` to the end of the line for a comment. A
 * Proto file should be readable by somebody who knows Solveig without a
 * second set of habits, and the header at the top of the file is where the two
 * are supposed to differ. */
#include <string.h>

#include "proto/lex.h"

void proto_lexer_init(ProtoLexer *lexer, const ProtoSource *source)
{
    lexer->source = source;
    lexer->start = source->text;
    lexer->current = source->text;
}

static bool is_alpha(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static bool is_digit(char c) { return c >= '0' && c <= '9'; }

static bool is_hexdigit(char c)
{
    return is_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static bool is_alnum(char c) { return is_alpha(c) || is_digit(c); }

/* What may run together into one operator token.
 *
 * A single `|` is not here and cannot be: it separates a block's parameters
 * from its body, and a dialect that could spell an operator `|` would be a
 * dialect in which `{ a | b }` has two readings. `:` and `.` are out for the
 * same kind of reason. A dialect gets the characters that mean nothing until it
 * says so.
 *
 * `||` *is* available, and is started by the case below rather than by this
 * set, because it is two bars and not a bar. Nothing legal was given up for it:
 * a block reads a lone bar in every position it looks for one, so `{ a | b }`
 * and `{ x | | t | t }` are untouched, and `{ a || b }` was an error before
 * this token existed. What it did cost is `{ || … }`, which used to parse as an
 * empty list of temporaries and emit nothing; that is written `{ | | … }` now.
 *
 * `\` remains, and is still the spelling for a *bitwise* or -- `\/` and `/\`
 * are a convention old enough to borrow, and single `|` is still not available
 * to anybody. What `||` buys is the logical one, in the spelling every C-like
 * dialect would otherwise have had to apologise for. */
static bool is_operator(char c)
{
    return strchr("+-*/<>=!&^%~?\\", c) != NULL;
}

static ProtoToken make(ProtoLexer *lexer, ProtoTokenType type, const char *start)
{
    ProtoToken token;
    token.type = type;
    token.start = start;
    token.length = (int)(lexer->current - start);
    token.span.source = lexer->source;
    token.span.offset = (uint32_t)(start - lexer->start);
    token.span.length = (uint32_t)token.length;
    token.message = NULL;
    return token;
}

static ProtoToken error_at(ProtoLexer *lexer, const char *start,
                         const char *message)
{
    ProtoToken token = make(lexer, PROTO_TOK_ERROR, start);
    token.message = message;
    return token;
}

static void skip_blanks(ProtoLexer *lexer)
{
    for (;;) {
        char c = *lexer->current;
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            lexer->current++;
        } else if (c == ';') {
            while (*lexer->current != '\0' && *lexer->current != '\n')
                lexer->current++;
        } else {
            return;
        }
    }
}

ProtoToken proto_lexer_next(ProtoLexer *lexer)
{
    skip_blanks(lexer);

    const char *start = lexer->current;
    char c = *lexer->current;

    if (c == '\0') return make(lexer, PROTO_TOK_EOF, start);

    if (is_alpha(c)) {
        while (is_alnum(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_NAME, start);
    }

    /* `#42` and `#-42`. The digits are checked here rather than left to the
       emitter, because `#` followed by nothing is a mistake with a place to
       point at and a bare `#` reaching Solveig is a mistake without one.

       **The sign belongs to the number**, which is Solveig's rule -- its
       grammar is `"#" [ "-" ] digit { digit }`. It is safe here in a way a sign
       on a *bare* number is not: nothing but an integer can begin with `#`, so
       there is no second reading for `-` to have. A leading `-` on a float
       stays the declared prefix operator, and must; see docs/ROADMAP.md. */
    if (c == '#') {
        lexer->current++;
        /* `#[` opens a dictionary, and is taken here because `#` is already
           consumed and nothing else may follow it. It is one token rather than
           two so that `# [` is the error it looks like. */
        if (*lexer->current == '[') {
            lexer->current++;
            return make(lexer, PROTO_TOK_HASH_LBRACKET, start);
        }
        if (*lexer->current == '-') lexer->current++;
        if (!is_digit(*lexer->current))
            return error_at(lexer, start, "'#' introduces an integer, and needs digits after it");
        while (is_digit(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_INTEGER, start);
    }

    /* `$FF08`, hexadecimal, and Solveig's own spelling. Purely additive: `$` is
       not an operator character and means nothing else here. It takes no sign,
       because it is for looking at bits. */
    if (c == '$') {
        lexer->current++;
        if (!is_hexdigit(*lexer->current))
            return error_at(lexer, start,
                            "'$' introduces a hexadecimal integer, and needs digits after it");
        while (is_hexdigit(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_INTEGER, start);
    }

    if (is_digit(c)) {
        while (is_digit(*lexer->current)) lexer->current++;
        /* Only a digit after the dot makes it part of the number; `#1.` and
           `a:size.` both end a statement and must keep doing so. */
        if (*lexer->current == '.' && is_digit(lexer->current[1])) {
            lexer->current++;
            while (is_digit(*lexer->current)) lexer->current++;
        }
        /* An exponent, and only when the digits are actually there: `2e10` is
           one number and `2 exp` is two tokens, so the whole tail is looked at
           before any of it is consumed. `1e` is the float 1 and the name `e`,
           which is what it looks like. */
        if (*lexer->current == 'e' || *lexer->current == 'E') {
            const char *after = lexer->current + 1;
            if (*after == '+' || *after == '-') after++;
            if (is_digit(*after)) {
                lexer->current = after;
                while (is_digit(*lexer->current)) lexer->current++;
            }
        }
        return make(lexer, PROTO_TOK_FLOAT, start);
    }

    if (c == '"') {
        lexer->current++;
        while (*lexer->current != '"') {
            if (*lexer->current == '\0')
                return error_at(lexer, start, "this string is never closed");
            /* Escapes are counted, not interpreted: the text goes to Solveig
               as written, and Solveig's own lexer is what decides what `\n`
               means. Two interpretations of one escape is one too many.

               **The five are checked, though.** Solveig's grammar is
               `escape = "\\" ( '"' | "\\" | "n" | "t" | "r" )` and its
               compiler refuses anything else. Taking `\q` here and emitting it
               produced a `.sol` that `solas` rejected, with the error landing
               on generated code -- Proto emitting invalid Solveig, which is the
               one failure the whole map exists to prevent. See
               docs/POSTMORTEM.md 17. */
            if (*lexer->current == '\\') {
                if (strchr("\"\\ntr", lexer->current[1]) == NULL ||
                    lexer->current[1] == '\0')
                    return error_at(lexer, lexer->current,
                                    "unknown escape; \\\" \\\\ \\n \\t \\r are the five");
                lexer->current++;
            }
            lexer->current++;
        }
        lexer->current++;
        return make(lexer, PROTO_TOK_STRING, start);
    }

    if (c == '\'') {
        lexer->current++;
        if (!is_alpha(*lexer->current))
            return error_at(lexer, start, "a symbol is a quote and then a name");
        while (is_alnum(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_SYMBOL, start);
    }

    if (c == '@') {
        lexer->current++;
        if (!is_alpha(*lexer->current))
            return error_at(lexer, start, "a directive is '@' and then a name");
        while (is_alnum(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_DIRECTIVE, start);
    }

    /* Before the operator run, so that `:=` is one token and not `:` and `=`.
       Maximal munch is what lets a dialect declare `<=` without `<` having to
       stop existing. */
    if (c == ':') {
        lexer->current++;
        if (*lexer->current == '=') {
            lexer->current++;
            return make(lexer, PROTO_TOK_ASSIGN, start);
        }
        return make(lexer, PROTO_TOK_COLON, start);
    }

    /* `||` is the one operator token that does not begin with an operator
       character, and it takes exactly two bars: `|` is not in the set above, so
       a third bar is a bar again and `|||` is the operator `||` and then a lone
       `|`. Anything else operator-shaped after the two runs on as usual, `||=`
       being one token for the same reason `<=` is. */
    if (c == '|' && lexer->current[1] == '|') {
        lexer->current += 2;
        while (is_operator(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_OPERATOR, start);
    }

    if (is_operator(c)) {
        while (is_operator(*lexer->current)) lexer->current++;
        return make(lexer, PROTO_TOK_OPERATOR, start);
    }

    lexer->current++;
    switch (c) {
        case '.': return make(lexer, PROTO_TOK_DOT, start);
        case ',': return make(lexer, PROTO_TOK_COMMA, start);
        case '|': return make(lexer, PROTO_TOK_BAR, start);
        case '(': return make(lexer, PROTO_TOK_LPAREN, start);
        case ')': return make(lexer, PROTO_TOK_RPAREN, start);
        case '[': return make(lexer, PROTO_TOK_LBRACKET, start);
        case ']': return make(lexer, PROTO_TOK_RBRACKET, start);
        case '{': return make(lexer, PROTO_TOK_LBRACE, start);
        case '}': return make(lexer, PROTO_TOK_RBRACE, start);
        default:  break;
    }

    return error_at(lexer, start, "this character means nothing here");
}

const char *proto_token_type_name(ProtoTokenType type)
{
    switch (type) {
        case PROTO_TOK_EOF:       return "end of file";
        case PROTO_TOK_ERROR:     return "an error";
        case PROTO_TOK_NAME:      return "a name";
        case PROTO_TOK_INTEGER:   return "an integer";
        case PROTO_TOK_FLOAT:     return "a number";
        case PROTO_TOK_STRING:    return "a string";
        case PROTO_TOK_SYMBOL:    return "a symbol";
        case PROTO_TOK_DIRECTIVE: return "a directive";
        case PROTO_TOK_OPERATOR:  return "an operator";
        case PROTO_TOK_HASH_LBRACKET: return "'#['";
        case PROTO_TOK_ASSIGN:    return "':='";
        case PROTO_TOK_COLON:     return "':'";
        case PROTO_TOK_DOT:       return "'.'";
        case PROTO_TOK_COMMA:     return "','";
        case PROTO_TOK_BAR:       return "'|'";
        case PROTO_TOK_LPAREN:    return "'('";
        case PROTO_TOK_RPAREN:    return "')'";
        case PROTO_TOK_LBRACKET:  return "'['";
        case PROTO_TOK_RBRACKET:  return "']'";
        case PROTO_TOK_LBRACE:    return "'{'";
        case PROTO_TOK_RBRACE:    return "'}'";
    }
    return "something";
}
