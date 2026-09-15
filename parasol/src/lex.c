/* lex.c -- the fixed core lexer.
 *
 * Solveig's spellings, deliberately: `#42` for an integer against bare `42` for
 * a float, `'name` for a symbol, `;` to the end of the line for a comment. A
 * Parasol file should be readable by somebody who knows Solveig without a
 * second set of habits, and the header at the top of the file is where the two
 * are supposed to differ. */
#include <string.h>

#include "parasol/lex.h"

void parasol_lexer_init(ParasolLexer *lexer, const ParasolSource *source)
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
 * from its body, and a character in this set runs together with its neighbours,
 * so a `|` here would make `|=` a spelling and `{ a | b }` a guess. `:` and `.`
 * are out for the same kind of reason. A dialect gets the characters that mean
 * nothing until it says so.
 *
 * **That is about the character set and not about `|` being declarable**, which
 * is a distinction this comment used to blur and docs/COMPLETED.md 12 used to
 * get wrong. A bar is a token in its own right, and since 0.14.0 a module may
 * declare one with `@infix` -- the parser looks it up, the lexer never has to,
 * and a block's parameters are settled before either. See docs/GRAMMAR.md.
 *
 * `\` is therefore free again. It was the bitwise `or` from 0.1.0 to 0.13.0
 * because `|` could not be had; it is spelled `|` now, and nothing in this
 * repository uses a backslash outside a string.
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

static ParasolToken make(ParasolLexer *lexer, ParasolTokenType type, const char *start)
{
    ParasolToken token;
    token.type = type;
    token.start = start;
    token.length = (int)(lexer->current - start);
    token.span.source = lexer->source;
    token.span.offset = (uint32_t)(start - lexer->start);
    token.span.length = (uint32_t)token.length;
    token.message = NULL;
    return token;
}

static ParasolToken error_at(ParasolLexer *lexer, const char *start,
                         const char *message)
{
    ParasolToken token = make(lexer, PARASOL_TOK_ERROR, start);
    token.message = message;
    return token;
}

static void skip_blanks(ParasolLexer *lexer)
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

ParasolToken parasol_lexer_next(ParasolLexer *lexer)
{
    skip_blanks(lexer);

    const char *start = lexer->current;
    char c = *lexer->current;

    if (c == '\0') return make(lexer, PARASOL_TOK_EOF, start);

    if (is_alpha(c)) {
        while (is_alnum(*lexer->current)) lexer->current++;
        return make(lexer, PARASOL_TOK_NAME, start);
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
            return make(lexer, PARASOL_TOK_HASH_LBRACKET, start);
        }
        if (*lexer->current == '-') lexer->current++;
        if (!is_digit(*lexer->current))
            return error_at(lexer, start, "'#' introduces an integer, and needs digits after it");
        while (is_digit(*lexer->current)) lexer->current++;
        return make(lexer, PARASOL_TOK_INTEGER, start);
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
        return make(lexer, PARASOL_TOK_INTEGER, start);
    }

    /* `%1011`, binary, and the third of Solveig's integer forms.
     *
     * **This one takes something away, and is the only spelling here that
     * does.** `%` is an operator character in Parasol and is not one in Solveig,
     * which has no `%` at all and can therefore give the whole character to the
     * literal. Here the two have to share, and the split is *immediately
     * followed by a binary digit*: `%1011` is a number and `%` before anything
     * else -- a space, a `#`, a `2`, another operator character -- is the
     * operator it always was.
     *
     * So a dialect that declares `%` loses `a %0…` and `a %1…` without a space.
     * Nothing in this repository writes that: `%` as mod is written `n % #2`,
     * because mod wants an integer and a bare digit is a float. And the loss is
     * loud rather than silent -- `a %10` becomes a name and then a number,
     * which is not an expression and is refused where it stands.
     *
     * Still no declaration is consulted, so a tool can tokenise a `.psol`
     * knowing nothing about its dialect, which is the line that matters.
     * Compare `||` in 0.9.0, which grew the vocabulary and cost only `{ || … }`
     * out of the *core*; this is the first time growing it has taken something
     * from what a dialect may declare. docs/ROADMAP.md argues it. */
    if (c == '%' && (lexer->current[1] == '0' || lexer->current[1] == '1')) {
        lexer->current++;
        while (*lexer->current == '0' || *lexer->current == '1') lexer->current++;
        return make(lexer, PARASOL_TOK_INTEGER, start);
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
        return make(lexer, PARASOL_TOK_FLOAT, start);
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
               on generated code -- Parasol emitting invalid Solveig, which is the
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
        return make(lexer, PARASOL_TOK_STRING, start);
    }

    if (c == '\'') {
        lexer->current++;
        if (!is_alpha(*lexer->current))
            return error_at(lexer, start, "a symbol is a quote and then a name");
        while (is_alnum(*lexer->current)) lexer->current++;
        return make(lexer, PARASOL_TOK_SYMBOL, start);
    }

    if (c == '@') {
        lexer->current++;
        if (!is_alpha(*lexer->current))
            return error_at(lexer, start, "a directive is '@' and then a name");
        while (is_alnum(*lexer->current)) lexer->current++;
        return make(lexer, PARASOL_TOK_DIRECTIVE, start);
    }

    /* Before the operator run, so that `:=` is one token and not `:` and `=`.
       Maximal munch is what lets a dialect declare `<=` without `<` having to
       stop existing. */
    if (c == ':') {
        lexer->current++;
        if (*lexer->current == '=') {
            lexer->current++;
            return make(lexer, PARASOL_TOK_ASSIGN, start);
        }
        return make(lexer, PARASOL_TOK_COLON, start);
    }

    /* `||` is the one operator token that does not begin with an operator
       character, and it takes exactly two bars: `|` is not in the set above, so
       a third bar is a bar again and `|||` is the operator `||` and then a lone
       `|`. Anything else operator-shaped after the two runs on as usual, `||=`
       being one token for the same reason `<=` is. */
    if (c == '|' && lexer->current[1] == '|') {
        lexer->current += 2;
        while (is_operator(*lexer->current)) lexer->current++;
        return make(lexer, PARASOL_TOK_OPERATOR, start);
    }

    if (is_operator(c)) {
        while (is_operator(*lexer->current)) lexer->current++;
        return make(lexer, PARASOL_TOK_OPERATOR, start);
    }

    lexer->current++;
    switch (c) {
        case '.': return make(lexer, PARASOL_TOK_DOT, start);
        case ',': return make(lexer, PARASOL_TOK_COMMA, start);
        case '|': return make(lexer, PARASOL_TOK_BAR, start);
        case '(': return make(lexer, PARASOL_TOK_LPAREN, start);
        case ')': return make(lexer, PARASOL_TOK_RPAREN, start);
        case '[': return make(lexer, PARASOL_TOK_LBRACKET, start);
        case ']': return make(lexer, PARASOL_TOK_RBRACKET, start);
        case '{': return make(lexer, PARASOL_TOK_LBRACE, start);
        case '}': return make(lexer, PARASOL_TOK_RBRACE, start);
        default:  break;
    }

    return error_at(lexer, start, "this character means nothing here");
}

const char *parasol_token_type_name(ParasolTokenType type)
{
    switch (type) {
        case PARASOL_TOK_EOF:       return "end of file";
        case PARASOL_TOK_ERROR:     return "an error";
        case PARASOL_TOK_NAME:      return "a name";
        case PARASOL_TOK_INTEGER:   return "an integer";
        case PARASOL_TOK_FLOAT:     return "a number";
        case PARASOL_TOK_STRING:    return "a string";
        case PARASOL_TOK_SYMBOL:    return "a symbol";
        case PARASOL_TOK_DIRECTIVE: return "a directive";
        case PARASOL_TOK_OPERATOR:  return "an operator";
        case PARASOL_TOK_HASH_LBRACKET: return "'#['";
        case PARASOL_TOK_ASSIGN:    return "':='";
        case PARASOL_TOK_COLON:     return "':'";
        case PARASOL_TOK_DOT:       return "'.'";
        case PARASOL_TOK_COMMA:     return "','";
        case PARASOL_TOK_BAR:       return "'|'";
        case PARASOL_TOK_LPAREN:    return "'('";
        case PARASOL_TOK_RPAREN:    return "')'";
        case PARASOL_TOK_LBRACKET:  return "'['";
        case PARASOL_TOK_RBRACKET:  return "']'";
        case PARASOL_TOK_LBRACE:    return "'{'";
        case PARASOL_TOK_RBRACE:    return "'}'";
    }
    return "something";
}
