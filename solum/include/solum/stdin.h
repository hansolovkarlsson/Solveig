/* The process's standard input, read through one buffer.
 *
 * **Why this file exists.** `readLine` used to read through stdio and `readKey`
 * through the file descriptor underneath it, and the two do not share a buffer:
 * `fgets` reads a *block* ahead, so a program that read a line and then asked
 * for a key lost whatever had arrived in the same block as the line. It lost it
 * silently, which is the part that made it worth fixing rather than
 * documenting. ROADMAP 6.36.
 *
 * So there is one window over standard input, and everything that reads it
 * takes from that window: `system:readLine`, `system:readKey`,
 * `system:keyWaiting`, and Solis' own reader when it is not editing a line at a
 * terminal. Bytes read ahead are held where the next reader will find them,
 * whichever reader that turns out to be.
 *
 * **It belongs to the process, not to a VM.** Standard input is one descriptor
 * however many machines are pointed at it, and a per-VM buffer would divide
 * what the operating system does not. `sol_vm_init` forgets whatever is held,
 * which is what makes a test that replaces stdin between cases start clean.
 *
 * **The terminal modes live here too.** A byte is read in non-canonical mode so
 * that a keypress arrives without a newline, and `sol_stdin_waiting` sets the
 * same mode for the length of its question -- without it the driver holds what
 * has been typed until a newline and the question is answered wrongly. Solis'
 * line editor keeps its own dance, because it holds raw mode across a whole
 * line of editing where this holds it for one read.
 */
#ifndef SOLUM_STDIN_H
#define SOLUM_STDIN_H

#include <stdbool.h>
#include <stddef.h>

/* Whether the buffer already holds a byte, which asks the system nothing. */
bool sol_stdin_held(void);

/* Fills the buffer if it is empty. False means the input has ended. The `raw`
   form puts a terminal in non-canonical mode for the length of the read, so
   that one keypress is one byte and no newline is waited for. */
bool sol_stdin_fill(void);
bool sol_stdin_fill_raw(void);

/* The unread bytes. The pointer is good until the next fill or take. */
const char *sol_stdin_window(size_t *length);

/* Consumes that many of them; never more than the window holds. */
void sol_stdin_take(size_t count);

/* The next byte, or -1 at the end of input. `sol_stdin_byte_raw` is what a
   program waiting for a keypress wants; `sol_stdin_byte` is for a reader that
   wants the terminal to go on editing the line for it. */
int sol_stdin_byte(void);
int sol_stdin_byte_raw(void);

/* Whether a byte is there to be read, waiting up to `milliseconds` for one.
   True at the end of input, where the read after it says so. */
bool sol_stdin_waiting(int milliseconds);

/* Forgets what is held. `sol_vm_init` calls it; a host that replaces standard
   input under a running machine wants it too. */
void sol_stdin_forget(void);

#endif
