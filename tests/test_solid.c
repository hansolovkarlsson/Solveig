/* Solid, the debugger: driven the way a person drives it, through its own
   prompt.
 *
 * The commands go in on stdin and what comes back is read, which is exactly
 * what a session is -- and unlike the prompt in solis this needs no terminal,
 * since Solid reads lines rather than keys. */
#define _POSIX_C_SOURCE 200809L

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

#define DIR "build/tests/solid"

static void write_file(const char *path, const char *text)
{
    FILE *f = fopen(path, "w");
    assert(f != NULL);
    fputs(text, f);
    fclose(f);
}

/* Runs solid over `program` with `commands` typed at it, and answers what it
   said. The caller frees nothing; the buffer is static-sized on purpose. */
static void session(const char *program, const char *commands,
                    char *out, size_t size)
{
    system("mkdir -p " DIR);
    write_file(DIR "/program.sol", program);

    char line[4096];
    snprintf(line, sizeof line, "printf '%s' | bin/solid " DIR "/program.sol 2>&1",
             commands);

    FILE *pipe = popen(line, "r");
    assert(pipe != NULL);

    size_t filled = 0, got;
    out[0] = '\0';
    while (filled + 1 < size &&
           (got = fread(out + filled, 1, size - filled - 1, pipe)) > 0) {
        filled += got;
    }
    out[filled] = '\0';
    pclose(pipe);
}

/* It stops before the first line, so there is somewhere to work from. */
static void test_it_stops_at_the_start(void)
{
    char out[16384];
    session("a := #1.\nb := #2.\n", "quit\\n", out, sizeof out);

    assert(strstr(out, "program.sol:1") != NULL);
    assert(strstr(out, "a := #1.") != NULL);      /* the source line, shown */
    printf("  it stops before the first line\n");
}

/* Stepping walks a line at a time; `next` goes over a call where `step` goes
   into it. */
static void test_stepping(void)
{
    char out[16384];
    const char *program =
        "double := { n | n:mul(#2) }.\n"
        "x := double:value(#21).\n"
        "x:print.\n";

    session(program, "step\\nstep\\nwhere\\nquit\\n", out, sizeof out);
    /* Two steps from line 1 reach line 2 and then inside the block. */
    assert(strstr(out, "program.sol:2") != NULL);
    assert(strstr(out, "#1  ") != NULL);          /* a second frame in `where` */

    session(program, "step\\nnext\\nwhere\\nquit\\n", out, sizeof out);
    /* `next` from line 2 goes over the call and lands on line 3. */
    assert(strstr(out, "program.sol:3") != NULL);
    printf("  step goes into a call and next goes over it\n");
}

/* A breakpoint, and the locals of the frame it stops in -- by name, which is
   what 6.28 was built for. */
static void test_breakpoint_and_locals(void)
{
    char out[16384];
    const char *program =
        "withdraw := { amount | | after |\n"
        "    after := #100:sub(amount).\n"
        "    after }.\n"
        "withdraw:value(#30):print.\n";

    session(program, "break program.sol:3\\ncontinue\\nlocals\\n"
                     "print amount\\nprint after\\nquit\\n", out, sizeof out);

    assert(strstr(out, "program.sol:3") != NULL);
    assert(strstr(out, "amount") != NULL);
    assert(strstr(out, "#30") != NULL);
    assert(strstr(out, "after") != NULL);
    assert(strstr(out, "#70") != NULL);
    printf("  a breakpoint stops, and locals are named\n");
}

/* The globals, which is the one namespace a program cannot ask about itself:
   they are slots on an object with no name in the language, so neither `slots`
   nor `perform` reaches them. The debugger holds the root, so it can.

   Two claims, and the second is the one worth having. The names this program
   bound are listed **in the order they were bound**, not the order the slot
   list holds them in -- a new slot goes on the front, so reading the list
   straight through would put the last line of the program first. And the
   eighty-odd names the machine arrived with stay out of the way until asked
   for, since a listing they dominate answers a question nobody asked. */
static void test_globals_are_what_this_program_bound(void)
{
    char out[16384];
    /* The breakpoint is on a line that does not mention the method, so that
       "not in the listing" is about the listing rather than about the source
       line the debugger echoes when it stops. */
    const char *program =
        "first := #1.\n"
        "second := \"two\".\n"
        "integer:tripled := { self:mul(#3) }.\n"
        "answer := #5:tripled.\n"
        "answer:print.\n";

    session(program, "break program.sol:5\\ncontinue\\nglobals\\nquit\\n",
            out, sizeof out);

    const char *a = strstr(out, "first");
    const char *b = strstr(out, "second");
    assert(a != NULL && b != NULL);
    assert(a < b);                       /* bound first, listed first */
    assert(strstr(out, "#1") != NULL);
    assert(strstr(out, "\"two\"") != NULL);

    /* A method is a slot on `integer`, not a global, so it is not here. */
    assert(strstr(out, "tripled") == NULL);

    /* And what the machine brought is counted rather than printed. */
    assert(strstr(out, "built in") != NULL);
    assert(strstr(out, "system") == NULL);

    /* Until it is asked for, and then it is marked. */
    session(program, "break program.sol:5\\ncontinue\\nglobals all\\nquit\\n",
            out, sizeof out);
    assert(strstr(out, "system") != NULL);
    assert(strstr(out, "random") != NULL);
    assert(strstr(out, "(built in)") != NULL);
    /* The program's own are still last, and still unmarked. */
    const char *mine = strstr(out, "second");
    assert(mine != NULL && strstr(out, "system") < mine);

    /* A program that binds nothing says so rather than printing an empty list. */
    session("integer:doubled := { self:mul(#2) }.\n#5:doubled:print.\n",
            "break program.sol:2\\ncontinue\\nglobals\\nquit\\n", out, sizeof out);
    assert(strstr(out, "none bound by this program") != NULL);

    printf("  globals are what this program bound, in the order it bound them\n");
}

/* A breakpoint inside a loop fires every time round. The first version of this
   suppressed the repeats, having confused "coming back to a line" with "coming
   back from a call written on it". */
static void test_a_breakpoint_in_a_loop_fires_each_time(void)
{
    char out[16384];
    /* The breakpoint line holds nothing but the block's body. A line a block
       *literal* also ends on belongs to the frame that defines it as well as
       to the one that runs it, and a line breakpoint rightly matches both --
       which is a fine thing for it to do and a poor thing to write a test on. */
    const char *program =
        "total := #0.\n"
        "adder := { n |\n"
        "    total := total:add(n).\n"
        "    total }.\n"
        "#1:toDo(#3, adder).\n"
        "total:print.\n";

    session(program, "break program.sol:3\\ncontinue\\nprint n\\ncontinue\\n"
                     "print n\\ncontinue\\nprint n\\nquit\\n", out, sizeof out);

    assert(strstr(out, "n = #1") != NULL);
    assert(strstr(out, "n = #2") != NULL);
    assert(strstr(out, "n = #3") != NULL);
    printf("  a breakpoint in a loop fires every time round\n");
}

/* And a breakpoint on a line a call is written on fires once for that visit,
   not twice -- arriving and returning are one arrival. */
static void test_a_breakpoint_fires_once_per_visit(void)
{
    char out[16384];
    const char *program =
        "double := { n | n:mul(#2) }.\n"
        "x := double:value(#21).\n"
        "y := #1.\n";

    session(program, "break program.sol:2\\ncontinue\\ncontinue\\nquit\\n",
            out, sizeof out);

    /* The second `continue` runs to the end rather than stopping again. */
    assert(strstr(out, "the program finished") != NULL);
    printf("  a breakpoint fires once for one visit to its line\n");
}

/* The thing a debugger can do that a prompt afterwards cannot: stop where it
   broke, with the frames still standing and the bad value still in one. */
static void test_it_stops_where_it_broke(void)
{
    char out[16384];
    const char *program =
        "divide := { a, b | a:div(b) }.\n"
        "divide:value(#100, #0):print.\n";

    session(program, "continue\\nwhere\\nlocals\\nprint b\\nquit\\n",
            out, sizeof out);

    assert(strstr(out, "division by zero") != NULL);
    assert(strstr(out, "cannot go on from here") != NULL);
    /* The frames are still there, and so is what made it fail. */
    assert(strstr(out, "b = #0") != NULL);
    assert(strstr(out, "a  ") != NULL);
    printf("  it stops where the program broke, with the frames standing\n");
}

/* Leaving is not a failure of the program. */
static void test_quitting_is_not_a_failure(void)
{
    system("mkdir -p " DIR);
    write_file(DIR "/quiet.sol", "a := #1.\n");
    int status = system("printf 'quit\\n' | bin/solid " DIR "/quiet.sol >/dev/null 2>&1");
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    printf("  quitting leaves with 0\n");
}

int main(void)
{
    test_it_stops_at_the_start();
    test_stepping();
    test_breakpoint_and_locals();
    test_globals_are_what_this_program_bound();
    test_a_breakpoint_in_a_loop_fires_each_time();
    test_a_breakpoint_fires_once_per_visit();
    test_it_stops_where_it_broke();
    test_quitting_is_not_a_failure();
    printf("test_solid: ok\n");
    return 0;
}
