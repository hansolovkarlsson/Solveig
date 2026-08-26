/* One window over standard input. See solum/include/solum/input.h for why. */
#include "solum/stdin.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>

/* Four kilobytes, which is one page and one `fgets` chunk. The size matters
   only for how much is read ahead of a reader that then asks for one byte --
   and since everything now takes from the same window, reading ahead costs
   nothing except when another *process* is waiting for the same input. See the
   note about `system:run` in the reference. */
#define SOL_STDIN_CAPACITY 4096

static struct {
    char   bytes[SOL_STDIN_CAPACITY];
    size_t start;
    size_t end;
} window;

bool sol_stdin_held(void)
{
    return window.start < window.end;
}

const char *sol_stdin_window(size_t *length)
{
    *length = window.end - window.start;
    return window.bytes + window.start;
}

void sol_stdin_take(size_t count)
{
    size_t available = window.end - window.start;
    window.start += count < available ? count : available;
    if (window.start >= window.end) {
        window.start = 0;
        window.end = 0;
    }
}

void sol_stdin_forget(void)
{
    window.start = 0;
    window.end = 0;
}

#if defined(__unix__) || defined(__APPLE__)

#include <poll.h>
#include <termios.h>
#include <unistd.h>

/* One read into an empty window. Not sticky at the end: a terminal answering
   nothing for a ctrl-D can be typed into again, and `read` says so each time it
   is asked, which is the behaviour to pass through rather than remember. */
static bool fill_now(void)
{
    ssize_t got;
    do {
        got = read(STDIN_FILENO, window.bytes, sizeof window.bytes);
    } while (got < 0 && errno == EINTR);

    if (got <= 0) return false;
    window.start = 0;
    window.end = (size_t)got;
    return true;
}

/* ICANON off so a keypress arrives without a newline, ECHO off because raw mode
   does not echo and a program that wants the key shown prints it. ISIG stays,
   so ctrl-c still interrupts a program waiting for a key rather than handing it
   the byte. VMIN of 1 asks for at least one byte and not for a full buffer. */
static bool raw_mode(struct termios *original, int least)
{
    if (!isatty(STDIN_FILENO)) return false;
    if (tcgetattr(STDIN_FILENO, original) != 0) return false;

    struct termios mode = *original;
    mode.c_lflag &= (tcflag_t)~(ICANON | ECHO);
    mode.c_cc[VMIN] = (cc_t)least;
    mode.c_cc[VTIME] = 0;
    return tcsetattr(STDIN_FILENO, TCSANOW, &mode) == 0;
}

bool sol_stdin_fill(void)
{
    if (sol_stdin_held()) return true;
    return fill_now();
}

bool sol_stdin_fill_raw(void)
{
    if (sol_stdin_held()) return true;

    struct termios original;
    bool raw = raw_mode(&original, 1);
    bool got = fill_now();
    if (raw) tcsetattr(STDIN_FILENO, TCSANOW, &original);
    return got;
}

bool sol_stdin_waiting(int milliseconds)
{
    if (sol_stdin_held()) return true;

    /* **The mode matters for a call that reads nothing.** A terminal in its
       ordinary mode holds what is typed until a newline, so a poll between two
       reads is told nothing has been typed however much has -- and an arrow
       key, which is what this exists to recognise, has its `[` and `B` sitting
       in the driver's line buffer. VMIN of 0 because nothing is read here. */
    struct termios original;
    bool raw = raw_mode(&original, 0);

    struct pollfd waiting;
    waiting.fd = STDIN_FILENO;
    waiting.events = POLLIN;
    waiting.revents = 0;

    int ready;
    do {
        ready = poll(&waiting, 1, milliseconds);
    } while (ready < 0 && errno == EINTR);   /* a signal is not an answer */

    if (raw) tcsetattr(STDIN_FILENO, TCSANOW, &original);
    return ready > 0;
}

#else   /* no termios and no poll: one buffer still, filled through stdio */

static bool fill_now(void)
{
    size_t got = fread(window.bytes, 1, sizeof window.bytes, stdin);
    if (got == 0) return false;
    window.start = 0;
    window.end = got;
    return true;
}

bool sol_stdin_fill(void)
{
    if (sol_stdin_held()) return true;
    return fill_now();
}

bool sol_stdin_fill_raw(void)
{
    /* Without termios there is no line discipline to turn off, and `fread`
       would block for a full buffer, so this reads one byte at a time. */
    if (sol_stdin_held()) return true;
    int c = fgetc(stdin);
    if (c == EOF) return false;
    window.bytes[0] = (char)c;
    window.start = 0;
    window.end = 1;
    return true;
}

bool sol_stdin_waiting(int milliseconds)
{
    (void)milliseconds;
    /* True, so a caller reads and blocks -- which is what it would have done
       without this question at all. False would make a program decide nothing
       is coming when it cannot know. */
    return true;
}

#endif

static int byte_after(bool filled)
{
    if (!filled) return -1;

    size_t available;
    const char *bytes = sol_stdin_window(&available);
    unsigned char byte = (unsigned char)bytes[0];
    sol_stdin_take(1);
    return (int)byte;
}

int sol_stdin_byte(void)     { return byte_after(sol_stdin_fill()); }
int sol_stdin_byte_raw(void) { return byte_after(sol_stdin_fill_raw()); }
