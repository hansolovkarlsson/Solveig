#include <stdlib.h>
#include <string.h>

#include "solum/stdin.h"
#include "solis/input.h"

void sol_input_append(SolisInput *input, const char *chunk)
{
    sol_input_append_bytes(input, chunk, strlen(chunk));
}

/* By length rather than to a NUL, because what it appends is now a slice of the
   window over standard input and a slice is not terminated. */
void sol_input_append_bytes(SolisInput *input, const char *chunk, size_t added)
{
    if (input->length + added + 1 > input->capacity) {
        size_t capacity = input->capacity < 256 ? 256 : input->capacity;
        while (capacity < input->length + added + 1) capacity *= 2;

        char *grown = realloc(input->text, capacity);
        if (grown == NULL) {
            fprintf(stderr, "solis: out of memory\n");
            exit(1);
        }
        input->text = grown;
        input->capacity = capacity;
    }
    memcpy(input->text + input->length, chunk, added);
    input->length += added;
    input->text[input->length] = '\0';
}

void sol_input_clear(SolisInput *input)
{
    input->length = 0;
    if (input->text != NULL) input->text[0] = '\0';
}

void sol_input_free(SolisInput *input)
{
    free(input->text);
    input->text = NULL;
    input->length = 0;
    input->capacity = 0;
}

/* **Takes from the window the language reads through** when the input is
   standard input, which is every caller there is. It used to be `fgets`, and
   `fgets` reads a block ahead into the C library's buffer -- so a script run at
   this prompt could ask for a key and be handed nothing, the bytes it wanted
   being held where nothing else could reach them. ROADMAP 6.36. */
bool sol_input_read_line(SolisInput *input)
{
    bool got_anything = false;

    for (;;) {
        if (!sol_stdin_fill()) return got_anything;
        got_anything = true;

        size_t available;
        const char *bytes = sol_stdin_window(&available);
        const char *newline = memchr(bytes, '\n', available);
        size_t take = newline != NULL ? (size_t)(newline - bytes) + 1 : available;

        sol_input_append_bytes(input, bytes, take);
        sol_stdin_take(take);
        if (newline != NULL) return true;
    }
}

void sol_scan_reset(SolisScan *state)
{
    state->depth = 0;
    state->in_string = false;
}

/* The question is whether what has been typed *could* still be finished, and
 * two things say it could: an unclosed bracket, and an unclosed string.
 *
 * Counting brackets naively would be wrong in two ways this has to avoid. A
 * brace inside a string is not a bracket -- `"{}"` is an ordinary template, and
 * `fill` templates are full of them -- and a `;` comment runs to the end of its
 * line, so anything inside one is text rather than code. The lexer already
 * knows both rules; this is the smallest thing that agrees with it.
 *
 * A closer with nothing open does not go negative. A stray `)` is a mistake for
 * the compiler to report, not a reason to sit waiting for input that could
 * never balance it.
 */
void sol_scan(SolisScan *state, const char *text)
{
    for (const char *at = text; *at != '\0'; at++) {
        if (state->in_string) {
            /* A backslash claims the next character, so `\"` does not end the
               string -- the same rule the lexer scans by. */
            if (*at == '\\' && at[1] != '\0') { at++; continue; }
            if (*at == '"') state->in_string = false;
            continue;
        }

        switch (*at) {
        case ';':
            while (at[1] != '\0' && at[1] != '\n') at++;
            break;
        case '"': state->in_string = true; break;
        case '(': case '[': case '{': state->depth++; break;
        case ')': case ']': case '}':
            if (state->depth > 0) state->depth--;
            break;
        default: break;
        }
    }
}

bool sol_scan_wants_more(const SolisScan *state)
{
    return state->depth > 0 || state->in_string;
}
