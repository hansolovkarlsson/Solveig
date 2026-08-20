/* input.h -- reading a submission at the prompt.
 *
 * Solis reads until the input is a thing that could compile, then compiles and
 * runs it. That is not the same as reading a line: a method body spans several,
 * and a line is not a unit of anything in this language -- `.` separates
 * statements and a newline is ordinary whitespace.
 *
 * Split out from the loop so it can be tested. Deciding whether input is
 * finished has more corners than it looks: a brace inside a string is not a
 * bracket, a comment runs to the end of its line, and a backslash claims the
 * character after it.
 */
#ifndef SOLIS_INPUT_H
#define SOLIS_INPUT_H

#include <stdio.h>

#include "solum/common.h"

/* A growable buffer for what has been typed so far.
 *
 * It used to be 1024 bytes read by a single `fgets` with no overflow check, so
 * a longer line was cut and its tail arrived as if it were the next line --
 * which produced at least one baffling session, where a generated 255-element
 * array literal looked like it had failed to compile when it had merely been
 * severed mid-token. */
typedef struct {
    char  *text;
    size_t length;
    size_t capacity;
} SolisInput;

void sol_input_append(SolisInput *input, const char *chunk);
void sol_input_clear(SolisInput *input);
void sol_input_free(SolisInput *input);

/* Appends one line of any length. Answers false only at end of input with
   nothing read; a final line carrying no newline of its own still counts. */
bool sol_input_read_line(SolisInput *input, FILE *in);

/* How much is still open. Both an unclosed bracket and an unclosed string
   outlive a line, so the state carries across them. */
typedef struct {
    int  depth;        /* unclosed ( [ {                   */
    bool in_string;    /* a " that has not been closed yet */
} SolisScan;

void sol_scan_reset(SolisScan *state);

/* Advances the state over `text`, which is the part not yet seen. */
void sol_scan(SolisScan *state, const char *text);

/* Could what has been typed still be finished? */
bool sol_scan_wants_more(const SolisScan *state);

#endif /* SOLIS_INPUT_H */
