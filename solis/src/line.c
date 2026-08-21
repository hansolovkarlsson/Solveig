/* Reading a line with editing and history. See line.h for why this exists. */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solis/line.h"

/* ---- history ----------------------------------------------------------- */

void sol_history_add(SolisHistory *history, const char *line)
{
    if (line == NULL || line[0] == '\0') return;

    /* The same line twice running is one entry. Somebody re-running a thing to
       watch it fail again should not have to press up twice to get past it. */
    if (history->count > 0 &&
        strcmp(history->items[history->count - 1], line) == 0) {
        return;
    }

    if (history->capacity < history->count + 1) {
        int capacity = history->capacity < 16 ? 16 : history->capacity * 2;
        char **grown = realloc(history->items, sizeof(char *) * (size_t)capacity);
        if (grown == NULL) return;      /* history is not worth failing for */
        history->items = grown;
        history->capacity = capacity;
    }

    size_t length = strlen(line);
    char *copy = malloc(length + 1);
    if (copy == NULL) return;
    memcpy(copy, line, length + 1);

    history->items[history->count++] = copy;
}

void sol_history_free(SolisHistory *history)
{
    for (int i = 0; i < history->count; i++) free(history->items[i]);
    free(history->items);
    history->items = NULL;
    history->count = 0;
    history->capacity = 0;
}

/* ---- history between sessions ------------------------------------------ */

const char *sol_history_path(char *buffer, size_t size)
{
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') return NULL;

    int written = snprintf(buffer, size, "%s/.solis_history", home);
    if (written < 0 || (size_t)written >= size) return NULL;
    return buffer;
}

void sol_history_load(SolisHistory *history, const char *path)
{
    if (path == NULL) return;

    FILE *file = fopen(path, "r");
    if (file == NULL) return;          /* the first run, most likely */

    char line[4096];
    while (fgets(line, sizeof line, file) != NULL) {
        size_t length = strlen(line);
        /* A line longer than the buffer arrives in pieces; the tail would be
           added as if it were its own entry, so drop anything unterminated
           rather than inventing a line nobody typed. */
        if (length == 0 || line[length - 1] != '\n') continue;
        line[length - 1] = '\0';
        sol_history_add(history, line);
    }
    fclose(file);
}

void sol_history_save(const SolisHistory *history, const char *path, int limit)
{
    if (path == NULL || history->count == 0) return;

    FILE *file = fopen(path, "w");
    if (file == NULL) return;          /* not worth complaining about */

    int from = history->count > limit ? history->count - limit : 0;
    for (int i = from; i < history->count; i++) {
        /* An entry is one line as typed, so it holds no newline -- but writing
           one that did would turn a single entry into two on the way back. */
        if (strchr(history->items[i], '\n') != NULL) continue;
        fprintf(file, "%s\n", history->items[i]);
    }
    fclose(file);
}

/* ---- the editor -------------------------------------------------------- */

#if defined(__unix__) || defined(__APPLE__)

#include <termios.h>
#include <unistd.h>

bool sol_line_editing_available(void)
{
    if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) return false;

    /* A terminal that cannot do escape sequences cannot do this. */
    const char *term = getenv("TERM");
    if (term == NULL || strcmp(term, "dumb") == 0) return false;

    struct termios probe;
    return tcgetattr(STDIN_FILENO, &probe) == 0;
}

/* What is being edited. The buffer grows; `cursor` is a byte offset into it.
 *
 * Bytes, not characters: a multi-byte character moved over one byte at a time
 * would be split, and the redraw would be wrong until the cursor left it. That
 * matches the language, where [a string is bytes](ROADMAP 2.13), and it is the
 * same limitation rather than a new one. */
typedef struct {
    char  *text;
    size_t length;
    size_t capacity;
    size_t cursor;
} Line;

static bool line_reserve(Line *line, size_t wanted)
{
    if (line->capacity >= wanted) return true;
    size_t capacity = line->capacity < 128 ? 128 : line->capacity;
    while (capacity < wanted) capacity *= 2;

    char *grown = realloc(line->text, capacity);
    if (grown == NULL) return false;
    line->text = grown;
    line->capacity = capacity;
    return true;
}

static void line_insert(Line *line, char c)
{
    if (!line_reserve(line, line->length + 2)) return;
    memmove(line->text + line->cursor + 1, line->text + line->cursor,
            line->length - line->cursor);
    line->text[line->cursor++] = c;
    line->length++;
    line->text[line->length] = '\0';
}

static void line_delete_before(Line *line)
{
    if (line->cursor == 0) return;
    memmove(line->text + line->cursor - 1, line->text + line->cursor,
            line->length - line->cursor);
    line->cursor--;
    line->length--;
    line->text[line->length] = '\0';
}

static void line_delete_at(Line *line)
{
    if (line->cursor >= line->length) return;
    memmove(line->text + line->cursor, line->text + line->cursor + 1,
            line->length - line->cursor - 1);
    line->length--;
    line->text[line->length] = '\0';
}

static void line_set(Line *line, const char *text)
{
    size_t length = strlen(text);
    if (!line_reserve(line, length + 1)) return;
    memcpy(line->text, text, length + 1);
    line->length = length;
    line->cursor = length;
}

/* Redraws the whole line every time.
 *
 * Wasteful in principle and invisible in practice at these lengths, and it is
 * the version that cannot drift: the alternative is tracking what the terminal
 * already shows, which is a second model of the same thing and the usual source
 * of a display that disagrees with the buffer. */
static void refresh(const char *prompt, const Line *line)
{
    size_t prompt_length = strlen(prompt);
    char escape[32];

    (void)!write(STDOUT_FILENO, "\r", 1);
    (void)!write(STDOUT_FILENO, prompt, prompt_length);
    (void)!write(STDOUT_FILENO, line->text, line->length);
    (void)!write(STDOUT_FILENO, "\x1b[K", 3);      /* clear what was longer */

    (void)!write(STDOUT_FILENO, "\r", 1);
    int n = snprintf(escape, sizeof escape, "\x1b[%zuC", prompt_length + line->cursor);
    if (n > 0) (void)!write(STDOUT_FILENO, escape, (size_t)n);
}

static bool read_byte(char *out)
{
    ssize_t got = read(STDIN_FILENO, out, 1);
    return got == 1;
}

bool sol_line_read(SolisInput *input, SolisHistory *history, const char *prompt)
{
    struct termios original;
    if (tcgetattr(STDIN_FILENO, &original) != 0) return false;

    struct termios raw = original;
    /* ISIG stays on, so ctrl-c still interrupts and ctrl-z still suspends --
       those belong to the terminal and taking them over would be a surprise.
       ICANON and ECHO go, which is the line editing this replaces. */
    raw.c_lflag &= (tcflag_t)~(ICANON | ECHO);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) return false;

    Line line = { NULL, 0, 0, 0 };
    if (!line_reserve(&line, 128)) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original);
        return false;
    }
    line.text[0] = '\0';

    /* Where up-arrow is in the history. `count` means "on the line being
       typed", which is what down-arrow comes back to. */
    int at = history->count;
    char *pending = NULL;         /* the line being typed, while browsing */

    bool finished = false;
    bool got_line = false;

    refresh(prompt, &line);

    while (!finished) {
        char c;
        if (!read_byte(&c)) {                  /* end of input */
            finished = true;
            got_line = line.length > 0;
            if (got_line) (void)!write(STDOUT_FILENO, "\n", 1);
            break;
        }

        if (c == '\r' || c == '\n') {
            (void)!write(STDOUT_FILENO, "\n", 1);
            finished = true;
            got_line = true;
            break;
        }

        if (c == 4) {                          /* ctrl-d */
            if (line.length == 0) {            /* on an empty line, end of input */
                finished = true;
                got_line = false;
                break;
            }
            line_delete_at(&line);             /* otherwise, delete forwards */
            refresh(prompt, &line);
            continue;
        }

        if (c == 127 || c == 8) {              /* backspace */
            line_delete_before(&line);
            refresh(prompt, &line);
            continue;
        }

        if (c == 1) { line.cursor = 0; refresh(prompt, &line); continue; }        /* ctrl-a */
        if (c == 5) { line.cursor = line.length; refresh(prompt, &line); continue; } /* ctrl-e */

        if (c == 21) {                         /* ctrl-u, discard the line */
            line.length = 0;
            line.cursor = 0;
            line.text[0] = '\0';
            refresh(prompt, &line);
            continue;
        }

        if (c == 12) {                         /* ctrl-l, clear the screen */
            (void)!write(STDOUT_FILENO, "\x1b[H\x1b[2J", 7);
            refresh(prompt, &line);
            continue;
        }

        if (c == 27) {                         /* an escape sequence */
            char one, two;
            if (!read_byte(&one) || !read_byte(&two)) continue;
            if (one != '[' && one != 'O') continue;

            if (two == 'A' || two == 'B') {    /* up, down */
                if (history->count == 0) continue;

                /* Stepping off the line being typed keeps it, so that coming
                   back down returns what was there rather than an empty line. */
                if (at == history->count) {
                    free(pending);
                    pending = malloc(line.length + 1);
                    if (pending != NULL) memcpy(pending, line.text, line.length + 1);
                }

                if (two == 'A') { if (at > 0) at--; }
                else            { if (at < history->count) at++; }

                if (at == history->count) line_set(&line, pending != NULL ? pending : "");
                else                      line_set(&line, history->items[at]);
                refresh(prompt, &line);
                continue;
            }

            if (two == 'C') {                  /* right */
                if (line.cursor < line.length) line.cursor++;
                refresh(prompt, &line);
                continue;
            }
            if (two == 'D') {                  /* left */
                if (line.cursor > 0) line.cursor--;
                refresh(prompt, &line);
                continue;
            }
            if (two == 'H') { line.cursor = 0; refresh(prompt, &line); continue; }
            if (two == 'F') { line.cursor = line.length; refresh(prompt, &line); continue; }

            if (two == '3') {                  /* delete, which ends with ~ */
                char tilde;
                if (read_byte(&tilde) && tilde == '~') {
                    line_delete_at(&line);
                    refresh(prompt, &line);
                }
                continue;
            }
            continue;                          /* anything else: ignore it */
        }

        if ((unsigned char)c < 32) continue;   /* other control keys: ignore */

        line_insert(&line, c);
        refresh(prompt, &line);
    }

    tcsetattr(STDIN_FILENO, TCSAFLUSH, &original);

    if (got_line) {
        sol_history_add(history, line.text);
        sol_input_append(input, line.text);
        sol_input_append(input, "\n");
    }

    free(pending);
    free(line.text);
    return got_line;
}

#else   /* not a Unix, so no termios and no editing */

bool sol_line_editing_available(void) { return false; }

bool sol_line_read(SolisInput *input, SolisHistory *history, const char *prompt)
{
    (void)input; (void)history; (void)prompt;
    return false;
}

#endif
