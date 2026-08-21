/* line.h -- reading a line at the prompt, with editing and history.
 *
 * The terminal does line editing itself in its usual "cooked" mode, which is
 * why `sol_input_read_line` and its `fgets` were enough to begin with: backspace
 * worked because the tty handled it before solis ever saw the line. What the tty
 * does *not* do is history, so an arrow key arrived as the three bytes of its
 * escape sequence and was compiled as if they had been typed -- which is what
 * asking for the previous line looked like.
 *
 * Getting history means taking the editing over: raw mode, and every key
 * handled here. That is roadmap 6.10, which had been waiting for a program that
 * needed it, and the program turned out to be solis.
 *
 * This is the first part of the runtime that behaves differently by platform.
 * It is termios, so Unix; anything else falls back to reading a line as before,
 * and so does a pipe or a file, which is what keeps the tests and `solis
 * program.sol` working.
 */
#ifndef SOLIS_LINE_H
#define SOLIS_LINE_H

#include "solis/input.h"
#include "solum/common.h"

/* Lines as they were entered, oldest first. */
typedef struct {
    char **items;
    int    count;
    int    capacity;
} SolisHistory;

void sol_history_add(SolisHistory *history, const char *line);
void sol_history_free(SolisHistory *history);

/* Is standard input a terminal that can be put in raw mode? When it is not --
   a pipe, a file, a dumb terminal -- the caller reads as it always did. */
bool sol_line_editing_available(void);

/* Writes `prompt`, reads one line with editing, and appends it to `input` with
   its newline. Answers false at end of input with nothing typed, which is what
   ctrl-d on an empty line means.
 *
 * The line is added to `history` if it has anything in it. */
bool sol_line_read(SolisInput *input, SolisHistory *history, const char *prompt);

#endif /* SOLIS_LINE_H */
