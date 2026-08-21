/* Reading a line at the prompt: history, and the editing that goes with it.
 *
 * Two halves. The history is ordinary code and is tested as such. The editor
 * needs a terminal -- it does nothing without one, by design -- so the rest
 * drives `solis` through a pty and reads back what the program printed.
 *
 * Asserting on what was *run* rather than on what the screen shows is
 * deliberate: the screen is escape sequences and redraws, and a test that
 * matched them would fail on any change to how the line is painted while
 * telling us nothing about whether the editing worked. `#3` came out means the
 * cursor went where it was asked to. */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE

#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#include "solis/line.h"

/* ---- history ----------------------------------------------------------- */

static void test_history_keeps_what_was_typed(void)
{
    SolisHistory history = { NULL, 0, 0 };

    sol_history_add(&history, "#1:print.");
    sol_history_add(&history, "#2:print.");
    assert(history.count == 2);
    assert(strcmp(history.items[0], "#1:print.") == 0);
    assert(strcmp(history.items[1], "#2:print.") == 0);

    /* Empty lines are not worth a slot: pressing return on nothing should not
       put a blank between you and the line you wanted. */
    sol_history_add(&history, "");
    sol_history_add(&history, NULL);
    assert(history.count == 2);

    /* Nor is the same line twice running. Re-running something to watch it fail
       again should not mean pressing up twice to get past it. */
    sol_history_add(&history, "#2:print.");
    assert(history.count == 2);

    /* But the same line again later is a separate entry -- what is being
       suppressed is a repeat, not a recurrence. */
    sol_history_add(&history, "#3:print.");
    sol_history_add(&history, "#2:print.");
    assert(history.count == 4);

    /* Past the initial capacity, to exercise the growth. */
    for (int i = 0; i < 100; i++) {
        char line[32];
        snprintf(line, sizeof line, "#%d:print.", i);
        sol_history_add(&history, line);
    }
    assert(history.count == 104);
    assert(strcmp(history.items[103], "#99:print.") == 0);

    sol_history_free(&history);
    assert(history.count == 0);
    assert(history.items == NULL);
    printf("  history keeps what was typed, without blanks or repeats\n");
}

/* ---- the editor, through a terminal ------------------------------------ */

/* posix_openpt and friends rather than forkpty, which lives in <util.h> on one
   system and <pty.h> plus -lutil on another. These are POSIX and need no
   library, so the Makefile stays as it is. */
static int open_pty(int *slave_out)
{
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) return -1;
    if (grantpt(master) != 0 || unlockpt(master) != 0) { close(master); return -1; }

    const char *name = ptsname(master);
    if (name == NULL) { close(master); return -1; }

    int slave = open(name, O_RDWR | O_NOCTTY);
    if (slave < 0) { close(master); return -1; }

    *slave_out = slave;
    return master;
}

/* A running solis, and what it has written so far.
 *
 * Driven by waiting for what should appear rather than by sleeping: a test that
 * sleeps is a test that passes on a fast machine and fails on a busy one, and
 * this one has a program starting, a terminal changing mode, and a VM running
 * between each keystroke and its effect. `expect` reads until the text turns up
 * or the deadline does. */
typedef struct {
    int    master;
    pid_t  pid;
    char  *out;
    size_t length;
    size_t capacity;
    size_t scan_from;      /* where the next `expect` starts looking */
} Session;

static bool session_start_with_home(Session *s, const char *home)
{
    int slave = -1;
    s->master = open_pty(&slave);
    if (s->master < 0) return false;            /* no pty here */

    s->pid = fork();
    assert(s->pid >= 0);
    if (s->pid == 0) {
        close(s->master);
        setsid();
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, STDIN_FILENO);
        dup2(slave, STDOUT_FILENO);
        dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) close(slave);
        setenv("TERM", "xterm", 1);
        if (home != NULL) setenv("HOME", home, 1);
        execl("bin/solis", "solis", (char *)NULL);
        _exit(127);
    }
    close(slave);

    s->capacity = 8192;
    s->out = malloc(s->capacity);
    assert(s->out != NULL);
    s->out[0] = '\0';
    s->length = 0;
    s->scan_from = 0;
    return true;
}

static bool session_start(Session *s) { return session_start_with_home(s, NULL); }

/* Reads until `needle` appears after everything already matched, or two seconds
   pass. Answers whether it turned up. */
static bool session_expect(Session *s, const char *needle)
{
    for (int waited = 0; waited < 2000; waited += 20) {
        char *found = strstr(s->out + s->scan_from, needle);
        if (found != NULL) {
            s->scan_from = (size_t)(found - s->out) + strlen(needle);
            return true;
        }

        fd_set set;
        FD_ZERO(&set);
        FD_SET(s->master, &set);
        struct timeval timeout = { 0, 20000 };
        if (select(s->master + 1, &set, NULL, NULL, &timeout) <= 0) continue;

        if (s->capacity - s->length < 4096) {
            s->capacity *= 2;
            char *grown = realloc(s->out, s->capacity);
            assert(grown != NULL);
            s->out = grown;
        }
        ssize_t got = read(s->master, s->out + s->length, s->capacity - s->length - 1);
        if (got <= 0) break;
        s->length += (size_t)got;
        s->out[s->length] = '\0';
    }
    return strstr(s->out + s->scan_from, needle) != NULL;
}

static void session_send(Session *s, const char *keys)
{
    (void)!write(s->master, keys, strlen(keys));
}

/* Ctrl-d, and then wait for solis to actually finish.
 *
 * Closing the pty straight after sending it kills the session instead of ending
 * it, and anything solis does on the way out -- writing the history file, for
 * one -- does not happen. That is worth the extra few lines: a test that
 * hangs up on the program under test is testing a crash. */
static void session_end(Session *s)
{
    /* Wait for the prompt before sending, for the same reason the first key
       waits for it: raw mode is entered with TCSAFLUSH, so a ctrl-d that
       arrives while the previous line is still running is discarded, and solis
       then sits waiting for input that has already been thrown away. */
    session_expect(s, "> ");
    session_send(s, "\x04");

    for (int waited = 0; waited < 2000; waited += 20) {
        fd_set set;
        FD_ZERO(&set);
        FD_SET(s->master, &set);
        struct timeval timeout = { 0, 20000 };
        if (select(s->master + 1, &set, NULL, NULL, &timeout) <= 0) continue;

        char drain[1024];
        ssize_t got = read(s->master, drain, sizeof drain);
        if (got <= 0) break;                    /* the slave side is gone */
    }

    close(s->master);
    int status;
    waitpid(s->pid, &status, 0);
    free(s->out);
}

#define UP    "\x1b[A"
#define DOWN  "\x1b[B"
#define LEFT  "\x1b[D"
#define RIGHT "\x1b[C"

/* The prompt is written from inside the reader, after the terminal is in raw
   mode -- so seeing it is what says the editor is ready for a key. Sending
   before then loses it: raw mode is entered with TCSAFLUSH, which discards
   input already received. */
static bool ready(Session *s) { return session_expect(s, "> "); }

/* Typing a line and running it: the part that worked before any of this, and
   has to still. */
static void test_a_typed_line_still_runs(void)
{
    Session s;
    if (!session_start(&s)) { printf("  (no pty available; editor tests skipped)\n"); return; }

    assert(ready(&s));
    session_send(&s, "#1:add(#2):print.\r");
    assert(session_expect(&s, "#3"));

    session_end(&s);
    printf("  a typed line runs\n");
}

/* Up recalls, and what it recalls runs again. */
static void test_up_recalls_the_last_line(void)
{
    Session s;
    if (!session_start(&s)) return;

    assert(ready(&s));
    session_send(&s, "#7:mul(#6):print.\r");
    assert(session_expect(&s, "#42"));

    assert(ready(&s));
    session_send(&s, UP);
    /* The recalled text is painted before it is run, which is what says the
       recall happened rather than the line being retyped. */
    assert(session_expect(&s, "#7:mul(#6):print."));
    session_send(&s, "\r");
    assert(session_expect(&s, "#42"));

    session_end(&s);
    printf("  up recalls the last line, and it runs again\n");
}

/* The reason this exists: a typo, an error, up, and fix it in place. None of it
   works if the cursor does not go where it is told. */
static void test_the_cursor_goes_where_it_is_told(void)
{
    Session s;
    if (!session_start(&s)) return;

    assert(ready(&s));
    session_send(&s, "#1:adx(#2):print.\r");
    assert(session_expect(&s, "does not understand 'adx'"));

    assert(ready(&s));
    session_send(&s, UP);
    assert(session_expect(&s, "#1:adx(#2):print."));

    /* Eleven left, over ":print." and "(#2)", landing after the x. */
    for (int i = 0; i < 11; i++) session_send(&s, LEFT);
    session_send(&s, "\x7f");                   /* backspace over the x */
    session_send(&s, "d");
    assert(session_expect(&s, "#1:add(#2):print."));

    session_send(&s, "\r");
    assert(session_expect(&s, "#3"));

    session_end(&s);
    printf("  a typo is fixed in place with up and the arrow keys\n");
}

/* Browsing away from a half-typed line and back returns it, rather than the
   empty line a naive history walk leaves behind.
 *
 * The values are chosen so that what is *printed* never appears in what was
 * *typed*: the editor paints every keystroke, so a test looking for "kept"
 * after typing `"kept":display.` matches the painting rather than the running,
 * and everything after it is a keystroke out of step. Arithmetic keeps the two
 * apart -- nothing in `#100:add(#5):print.` spells #105. */
static void test_a_half_typed_line_survives_browsing(void)
{
    Session s;
    if (!session_start(&s)) return;

    assert(ready(&s));
    session_send(&s, "#7:mul(#6):print.\r");
    assert(session_expect(&s, "#42"));           /* only ever in the output */

    assert(ready(&s));
    session_send(&s, "#100:ad");                 /* half a line */
    session_send(&s, UP);
    assert(session_expect(&s, "#7:mul(#6):print."));   /* the recall, painted */
    session_send(&s, DOWN);
    session_send(&s, "d(#5):print.\r");          /* finishing what was kept */
    assert(session_expect(&s, "#105"));

    session_end(&s);
    printf("  a half-typed line survives browsing away and back\n");
}

/* ctrl-h lists the last few lines -- and only on an empty line, because ctrl-h
   *is* backspace: it sends the same byte 8 that a backspace key sends on many
   terminals. Taking the key over outright would break deleting for those
   keyboards. On an empty line there is nothing to delete, so it is free exactly
   there. */
static void test_ctrl_h_lists_recent_lines(void)
{
    Session s;
    if (!session_start_with_home(&s, "build/tests/home-ctrl-h")) return;
    mkdir("build/tests/home-ctrl-h", 0700);
    remove("build/tests/home-ctrl-h/.solis_history");

    assert(ready(&s));
    session_send(&s, "#7:mul(#6):print.\r");
    assert(session_expect(&s, "#42"));
    assert(ready(&s));
    session_send(&s, "#2:add(#3):print.\r");
    assert(session_expect(&s, "#5"));

    assert(ready(&s));
    session_send(&s, "\x08");
    /* Numbered, oldest of the shown first. */
    assert(session_expect(&s, "1  #7:mul(#6):print."));
    assert(session_expect(&s, "2  #2:add(#3):print."));

    session_end(&s);
    remove("build/tests/home-ctrl-h/.solis_history");
    printf("  ctrl-h on an empty line lists the recent ones\n");
}

/* And with something typed it is still backspace, which is the whole reason the
   listing is bound where it is. */
static void test_ctrl_h_still_deletes(void)
{
    Session s;
    if (!session_start(&s)) return;

    assert(ready(&s));
    /* Type a wrong digit, take it back with ctrl-h, and run the corrected line.
       #4 rather than #3 would come out if the delete had not happened. */
    session_send(&s, "#1:add(#22");
    session_send(&s, "\x08");
    session_send(&s, "):print.\r");
    assert(session_expect(&s, "#3"));

    session_end(&s);
    printf("  ctrl-h with something typed is still backspace\n");
}

/* ---- history between sessions ------------------------------------------ */

static void test_the_history_file_is_under_home(void)
{
    char buffer[4096];

    setenv("HOME", "/tmp/solum-home", 1);
    const char *path = sol_history_path(buffer, sizeof buffer);
    assert(path != NULL);
    assert(strcmp(path, "/tmp/solum-home/.solis_history") == 0);

    /* No HOME, no file -- history then lasts as long as the session, which is
       what it did before any of this. */
    unsetenv("HOME");
    assert(sol_history_path(buffer, sizeof buffer) == NULL);

    /* A HOME too long to build a path from is the same answer, rather than a
       truncated path pointing somewhere nobody meant. */
    char huge[5000];
    memset(huge, 'x', sizeof huge - 1);
    huge[sizeof huge - 1] = '\0';
    setenv("HOME", huge, 1);
    assert(sol_history_path(buffer, sizeof buffer) == NULL);

    setenv("HOME", "/tmp/solum-home", 1);
    printf("  the history file is $HOME/.solis_history, or nowhere\n");
}

static void test_history_survives_being_written_and_read(void)
{
    const char *path = "build/tests/history-round-trip";
    remove(path);

    SolisHistory written = { NULL, 0, 0 };
    sol_history_add(&written, "#1:print.");
    sol_history_add(&written, "\"a string with spaces\":display.");
    sol_history_add(&written, "p:go := { \"x\":display }.");
    sol_history_save(&written, path, SOLIS_HISTORY_MAX);

    SolisHistory read = { NULL, 0, 0 };
    sol_history_load(&read, path);
    assert(read.count == written.count);
    for (int i = 0; i < read.count; i++) {
        assert(strcmp(read.items[i], written.items[i]) == 0);
    }

    sol_history_free(&written);
    sol_history_free(&read);
    remove(path);

    /* A file that is not there is what the first run looks like, not an error. */
    SolisHistory missing = { NULL, 0, 0 };
    sol_history_load(&missing, "build/tests/history-that-is-not-there");
    assert(missing.count == 0);
    sol_history_free(&missing);

    /* And no path at all is the same. */
    SolisHistory nowhere = { NULL, 0, 0 };
    sol_history_load(&nowhere, NULL);
    sol_history_save(&nowhere, NULL, SOLIS_HISTORY_MAX);
    assert(nowhere.count == 0);
    sol_history_free(&nowhere);

    printf("  history survives being written and read back\n");
}

/* The file is trimmed on the way out, so a prompt used for years does not leave
   a file that has to be managed. The newest are the ones kept. */
static void test_the_history_file_is_capped(void)
{
    const char *path = "build/tests/history-capped";
    remove(path);

    SolisHistory big = { NULL, 0, 0 };
    for (int i = 0; i < 1500; i++) {
        char line[32];
        snprintf(line, sizeof line, "#%d:print.", i);
        sol_history_add(&big, line);
    }
    assert(big.count == 1500);
    sol_history_save(&big, path, SOLIS_HISTORY_MAX);

    SolisHistory back = { NULL, 0, 0 };
    sol_history_load(&back, path);
    assert(back.count == SOLIS_HISTORY_MAX);
    assert(strcmp(back.items[0], "#500:print.") == 0);          /* the oldest kept */
    assert(strcmp(back.items[back.count - 1], "#1499:print.") == 0);  /* the newest */

    sol_history_free(&big);
    sol_history_free(&back);
    remove(path);
    printf("  the history file keeps the newest %d lines\n", SOLIS_HISTORY_MAX);
}

/* End to end: what one session typed, the next one recalls. */
static void test_history_reaches_the_next_session(void)
{
    const char *home = "build/tests/home";
    char history[256];
    snprintf(history, sizeof history, "%s/.solis_history", home);
    mkdir(home, 0700);
    remove(history);

    Session first;
    if (!session_start_with_home(&first, home)) return;
    assert(ready(&first));
    session_send(&first, "#7:mul(#6):print.\r");
    assert(session_expect(&first, "#42"));
    session_end(&first);

    /* A second solis, started fresh, with nothing typed into it. */
    Session second;
    if (!session_start_with_home(&second, home)) return;
    assert(ready(&second));
    session_send(&second, UP);
    assert(session_expect(&second, "#7:mul(#6):print."));
    session_send(&second, "\r");
    assert(session_expect(&second, "#42"));
    session_end(&second);

    remove(history);
    printf("  what one session typed, the next one recalls\n");
}

int main(void)
{
    test_history_keeps_what_was_typed();
    test_a_typed_line_still_runs();
    test_up_recalls_the_last_line();
    test_the_cursor_goes_where_it_is_told();
    test_a_half_typed_line_survives_browsing();
    test_ctrl_h_lists_recent_lines();
    test_ctrl_h_still_deletes();
    test_the_history_file_is_under_home();
    test_history_survives_being_written_and_read();
    test_the_history_file_is_capped();
    test_history_reaches_the_next_session();
    printf("test_line: ok\n");
    return 0;
}
