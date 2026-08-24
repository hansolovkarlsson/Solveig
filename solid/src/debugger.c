/* Solid: deciding when to stop, and what to say when stopped. */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solid/debugger.h"
#include "solum/bytecode.h"

void solid_init(Solid *solid)
{
    solid->mode = SOLID_STEP;         /* stop on the first line, so there is
                                         somewhere to set a breakpoint from */
    solid->depth = 0;
    solid->line = 0;
    solid->last_offer_depth = -1;
    solid->quitting = false;
    solid->breaks = NULL;
    solid->break_count = 0;
    solid->break_capacity = 0;
    solid->listing_file = NULL;
    solid->listing_line = 0;
}

void solid_free(Solid *solid)
{
    for (int i = 0; i < solid->break_count; i++) free(solid->breaks[i].file);
    free(solid->breaks);
    free(solid->listing_file);
    solid_init(solid);
}

/* ---- where we are ------------------------------------------------------- */

static const SolFrame *current_frame(const SolVM *vm)
{
    return vm->frame_count > 0 ? &vm->frames[vm->frame_count - 1] : NULL;
}

/* The offset the frame is about to execute, which is where it *is* -- the trace
   in vm.c looks one back because it reports a call that has already been made,
   and this reports a line that has not yet run. */
static int frame_offset(const SolFrame *frame)
{
    int offset = (int)(frame->ip - frame->chunk->code);
    if (offset < 0) offset = 0;
    if (offset >= frame->chunk->count) offset = frame->chunk->count - 1;
    return offset < 0 ? 0 : offset;
}

static int frame_line(const SolFrame *frame)
{
    return frame->chunk->count > 0 ? frame->chunk->lines[frame_offset(frame)] : 0;
}

static const char *frame_file(const SolFrame *frame)
{
    return sol_chunk_file_of(frame->chunk, frame_offset(frame));
}

static const char *frame_what(const SolFrame *frame)
{
    if (frame->method == NULL) return "script";
    return frame->method->is_block ? "block" : frame->method->name;
}

/* A breakpoint is written as it is easiest to type -- `parse.sol:12` -- and
   matched against the end of the path a chunk recorded, which is however the
   file was reached. Matching whole paths would mean typing the include path a
   library was found on, which nobody knows offhand. */
static bool path_ends_with(const char *path, const char *suffix)
{
    size_t plen = strlen(path), slen = strlen(suffix);
    if (slen == 0 || slen > plen) return false;
    if (strcmp(path + plen - slen, suffix) != 0) return false;
    return plen == slen || path[plen - slen - 1] == '/';
}

static bool at_breakpoint(const Solid *solid, const SolFrame *frame)
{
    const char *file = frame_file(frame);
    int line = frame_line(frame);

    for (int i = 0; i < solid->break_count; i++) {
        if (solid->breaks[i].line != line) continue;
        if (solid->breaks[i].file[0] == '\0') return true;   /* any file */
        if (path_ends_with(file, solid->breaks[i].file)) return true;
    }
    return false;
}

/* ---- showing ------------------------------------------------------------ */

static void show_place(const SolVM *vm)
{
    const SolFrame *frame = current_frame(vm);
    if (frame == NULL) return;

    const char *file = frame_file(frame);
    if (file[0] != '\0') {
        printf("%s:%d  in %s\n", file, frame_line(frame), frame_what(frame));
    } else {
        printf("line %d  in %s\n", frame_line(frame), frame_what(frame));
    }
}

/* The line itself, read from the file the chunk named. A source file that has
   moved or changed since is a thing this cannot detect, so it says what it
   found rather than pretending. */
static void show_source(const SolVM *vm, const char *file, int from, int count)
{
    char resolved[4096];
    if (file == NULL) {
        const SolFrame *frame = current_frame(vm);
        if (frame == NULL) return;
        snprintf(resolved, sizeof resolved, "%s", frame_file(frame));
        file = resolved;
    }
    if (file[0] == '\0') { printf("no source: this came from the prompt\n"); return; }

    FILE *f = fopen(file, "r");
    if (f == NULL) { printf("cannot read %s\n", file); return; }

    char line[1024];
    int at = 0;
    while (fgets(line, sizeof line, f) != NULL) {
        at++;
        if (at < from) continue;
        if (at >= from + count) break;
        printf("%5d  %s", at, line);
        if (strchr(line, '\n') == NULL) printf("\n");
    }
    fclose(f);
}

static void show_where(const SolVM *vm)
{
    for (int i = vm->frame_count - 1; i >= 0; i--) {
        const SolFrame *frame = &vm->frames[i];
        const char *file = frame_file(frame);
        printf("%s#%d  ", i == vm->frame_count - 1 ? "-> " : "   ",
               vm->frame_count - 1 - i);
        if (file[0] != '\0') printf("%s:%d", file, frame_line(frame));
        else                 printf("line %d", frame_line(frame));
        printf("  in %s\n", frame_what(frame));
    }
}

static void print_value(SolValue value)
{
    SolText text;
    sol_text_init(&text);
    sol_value_render(NULL, value, &text);
    fwrite(text.chars, 1, (size_t)text.length, stdout);
    sol_text_free(&text);
}

/* Every slot of the frame, by the name it was given. Slot 0 is the receiver and
   has no name of its own, so it is written as `self` -- which is what it is
   called from inside the block anyway. */
static void show_locals(const SolVM *vm)
{
    const SolFrame *frame = current_frame(vm);
    if (frame == NULL) return;

    int slots = frame->method != NULL ? frame->method->slot_count
                                      : frame->chunk->slot_count;
    bool any = false;
    for (int i = 0; i < slots; i++) {
        const char *name = sol_chunk_slot_name(frame->chunk, i);
        if (i == 0) {
            if (frame->method == NULL) continue;    /* the script has no self */
            name = "self";
        }
        if (name[0] == '\0') continue;              /* a slot nobody named */

        printf("  %-16s ", name);
        print_value(frame->slots[i]);
        printf("\n");
        any = true;
    }
    if (!any) printf("  (none)\n");
}

/* The globals, which is the one thing a program cannot ask for itself: they are
   slots on an object with no name in the language, so `slots` cannot reach them
   and neither can `perform` (2.10 in ROADMAP.md). A debugger holds the root
   directly, so here the question is answerable.

   What a person means by "the globals" is almost never the eighty-odd names the
   machine arrived with. A new name goes on the front of the slot list, so the
   ones this program bound are exactly the run ahead of `builtin_globals` -- and
   they are printed oldest first, the order `slots` answers in and the order
   they were written. `globals all` includes what was already there. */
static void show_globals(const SolVM *vm, bool everything)
{
    int total = vm->root->slot_count;
    int mine  = total - vm->builtin_globals;
    int shown = everything ? total : mine;

    if (shown <= 0) {
        printf("  (none bound by this program)\n");
        return;
    }

    /* The list runs newest first, and reading it that way would put the last
       line of the program at the top. Collected and walked back instead. */
    SolSlot **order = malloc(sizeof(SolSlot *) * (size_t)total);
    if (order == NULL) { printf("  out of memory\n"); return; }

    int count = 0;
    for (SolSlot *slot = vm->root->slots; slot != NULL && count < total;
         slot = slot->next) {
        order[count++] = slot;
    }

    for (int i = shown - 1; i >= 0; i--) {
        if (i >= count) continue;
        printf("  %-16s ", order[i]->name);
        print_value(order[i]->value);
        if (everything && i >= mine) printf("    (built in)");
        printf("\n");
    }
    free(order);

    if (!everything && vm->builtin_globals > 0) {
        printf("  -- and %d built in; `globals all` for those too\n",
               vm->builtin_globals);
    }
}

/* A name, looked for where a person would expect it: this frame first, then the
   globals. A local shadows a global of the same name inside its frame, and this
   answers the one the code at this line would have got. */
static bool find_local(const SolVM *vm, const char *name, SolValue *out)
{
    const SolFrame *frame = current_frame(vm);
    if (frame == NULL) return false;

    int slots = frame->method != NULL ? frame->method->slot_count
                                      : frame->chunk->slot_count;
    for (int i = 0; i < slots; i++) {
        const char *slot = (i == 0 && frame->method != NULL)
                         ? "self" : sol_chunk_slot_name(frame->chunk, i);
        if (slot[0] != '\0' && strcmp(slot, name) == 0) {
            *out = frame->slots[i];
            return true;
        }
    }
    return false;
}

static void show_name(SolVM *vm, const char *name)
{
    SolValue value;
    if (find_local(vm, name, &value)) {
        printf("  %s = ", name);
        print_value(value);
        printf("    (a local)\n");
        return;
    }

    SolSlot *slot = sol_object_lookup(vm->root, name);
    if (slot != NULL) {
        printf("  %s = ", name);
        print_value(slot->value);
        printf("    (a global)\n");
        return;
    }
    printf("  no name '%s' here\n", name);
}

/* ---- breakpoints -------------------------------------------------------- */

static void add_break(Solid *solid, const char *file, int line)
{
    if (solid->break_capacity < solid->break_count + 1) {
        int capacity = solid->break_capacity < 8 ? 8 : solid->break_capacity * 2;
        SolidBreakpoint *grown = realloc(solid->breaks,
                                         sizeof(SolidBreakpoint) * (size_t)capacity);
        if (grown == NULL) { printf("out of memory\n"); return; }
        solid->breaks = grown;
        solid->break_capacity = capacity;
    }

    size_t length = strlen(file);
    char *copy = malloc(length + 1);
    if (copy == NULL) { printf("out of memory\n"); return; }
    memcpy(copy, file, length + 1);

    solid->breaks[solid->break_count].file = copy;
    solid->breaks[solid->break_count].line = line;
    solid->break_count++;

    if (file[0] != '\0') printf("break at %s:%d\n", file, line);
    else                 printf("break at line %d, in any file\n", line);
}

static void show_breaks(const Solid *solid)
{
    if (solid->break_count == 0) { printf("  (none)\n"); return; }
    for (int i = 0; i < solid->break_count; i++) {
        printf("  %d  %s:%d\n", i,
               solid->breaks[i].file[0] != '\0' ? solid->breaks[i].file : "*",
               solid->breaks[i].line);
    }
}

static void drop_break(Solid *solid, int which)
{
    if (which < 0 || which >= solid->break_count) {
        printf("no breakpoint %d\n", which);
        return;
    }
    free(solid->breaks[which].file);
    for (int i = which; i < solid->break_count - 1; i++) {
        solid->breaks[i] = solid->breaks[i + 1];
    }
    solid->break_count--;
    printf("dropped %d\n", which);
}

/* ---- the prompt --------------------------------------------------------- */

static void show_help(void)
{
    printf(
        "  step, s        run to the next line, into calls\n"
        "  next, n        run to the next line, over calls\n"
        "  finish, f      run until this frame returns\n"
        "  continue, c    run to the next breakpoint\n"
        "  where, w       the frames, innermost first\n"
        "  locals, l      this frame's slots, by name\n"
        "  globals, g     what this program bound; `globals all` for the rest\n"
        "  print NAME, p  a local, or a global\n"
        "  list [N]       source around here, or from line N\n"
        "  break F:L, b   stop at that line; `break L` for any file\n"
        "  breaks         what is set\n"
        "  delete N       drop breakpoint N\n"
        "  quit, q        stop the program and leave\n");
}

/* True when the program should carry on. */
static bool command(Solid *solid, SolVM *vm, char *line)
{
    while (*line == ' ') line++;
    char *word = line;
    while (*line != '\0' && *line != ' ' && *line != '\n') line++;
    if (*line != '\0') { *line = '\0'; line++; }
    while (*line == ' ') line++;

    char *rest = line;
    for (char *p = rest; *p != '\0'; p++) {
        if (*p == '\n') { *p = '\0'; break; }
    }

    if (word[0] == '\0')                                    return false;  /* reprompt */

    if (!strcmp(word, "step") || !strcmp(word, "s")) {
        solid->mode = SOLID_STEP;
        return true;
    }
    if (!strcmp(word, "next") || !strcmp(word, "n")) {
        const SolFrame *here = current_frame(vm);
        solid->mode = SOLID_NEXT;
        solid->depth = vm->frame_count;
        solid->line = here != NULL ? frame_line(here) : 0;
        return true;
    }
    if (!strcmp(word, "finish") || !strcmp(word, "f")) {
        solid->mode = SOLID_FINISH;
        solid->depth = vm->frame_count;
        return true;
    }
    if (!strcmp(word, "continue") || !strcmp(word, "c")) {
        solid->mode = SOLID_CONTINUE;
        return true;
    }
    if (!strcmp(word, "quit") || !strcmp(word, "q")) {
        solid->quitting = true;
        return true;
    }

    if (!strcmp(word, "where") || !strcmp(word, "w")) { show_where(vm); return false; }
    if (!strcmp(word, "locals") || !strcmp(word, "l")) { show_locals(vm); return false; }
    if (!strcmp(word, "globals") || !strcmp(word, "g")) {
        show_globals(vm, !strcmp(rest, "all"));
        return false;
    }
    if (!strcmp(word, "help") || !strcmp(word, "?")) { show_help(); return false; }
    if (!strcmp(word, "breaks")) { show_breaks(solid); return false; }

    if (!strcmp(word, "print") || !strcmp(word, "p")) {
        if (rest[0] == '\0') printf("print what?\n");
        else                 show_name(vm, rest);
        return false;
    }

    if (!strcmp(word, "list")) {
        const SolFrame *frame = current_frame(vm);
        int from = rest[0] != '\0' ? atoi(rest)
                                   : (frame ? frame_line(frame) - 2 : 1);
        if (from < 1) from = 1;
        show_source(vm, NULL, from, 10);
        return false;
    }

    if (!strcmp(word, "break") || !strcmp(word, "b")) {
        if (rest[0] == '\0') { printf("break where?\n"); return false; }

        char *colon = strrchr(rest, ':');
        if (colon != NULL) {
            *colon = '\0';
            add_break(solid, rest, atoi(colon + 1));
        } else {
            add_break(solid, "", atoi(rest));      /* a line in any file */
        }
        return false;
    }

    if (!strcmp(word, "delete")) {
        if (rest[0] == '\0') printf("delete which?\n");
        else                 drop_break(solid, atoi(rest));
        return false;
    }

    printf("no command '%s' -- try `help`\n", word);
    return false;
}

/* ---- the hook ----------------------------------------------------------- */

void solid_stop(SolVM *vm, void *context)
{
    Solid *solid = (Solid *)context;
    const SolFrame *frame = current_frame(vm);
    if (frame == NULL) return;

    /* The program is failing rather than stepping. Nothing can be resumed from
       here, but the frames are still standing, which is the one moment worth
       having a debugger for rather than a prompt afterwards. */
    if (vm->debug_failed) {
        if (solid->quitting) return;
        printf("\n-- %s\n", vm->error_message.length > 0
                             ? vm->error_message.chars : "the program failed");
        show_place(vm);
        show_source(vm, NULL, frame_line(frame), 1);
        printf("   (it cannot go on from here; look around, then `quit`)\n");

        for (;;) {
            printf("(solid) ");
            fflush(stdout);

            char line[1024];
            if (fgets(line, sizeof line, stdin) == NULL) { printf("\n"); break; }

            /* Anything that would resume means "let it fall over" here. */
            char *word = line;
            while (*word == ' ') word++;
            if (!strncmp(word, "c", 1) || !strncmp(word, "q", 1) ||
                !strncmp(word, "s", 1) || !strncmp(word, "n", 1) ||
                !strncmp(word, "f", 1)) {
                break;
            }
            command(solid, vm, line);
        }
        return;
    }

    /* Whether this stop is one the traveller asked for. A breakpoint is checked
       whatever the mode, so `continue` still lands on one. */
    /* A breakpoint fires on arriving at its line, not on coming back to it. A
       call written on line 10 returns to line 10, and stopping there twice
       makes one breakpoint look like two.
     *
       The signal is the frame count *dropping* since the last offer, which
       happens only on a return. A loop calling the same block over and over
       never drops -- the frame goes and another is pushed before the next
       instruction runs -- so a breakpoint inside one still fires every time
       round, which the first version of this got wrong. */
    bool returning = solid->last_offer_depth > vm->frame_count;
    solid->last_offer_depth = vm->frame_count;

    bool stop = !returning && at_breakpoint(solid, frame);
    if (!stop) {
        switch (solid->mode) {
        case SOLID_STEP:     stop = true; break;
        case SOLID_NEXT:
            /* Back in the frame it was asked from, *and* somewhere else in it.
               Returning from a call lands on the line the call was written on,
               which is where `next` was typed -- stopping there again would
               make stepping over a call take two presses and look like one had
               been missed. */
            stop = vm->frame_count < solid->depth ||
                   (vm->frame_count == solid->depth &&
                    frame_line(frame) != solid->line);
            break;
        case SOLID_FINISH:   stop = vm->frame_count < solid->depth; break;
        case SOLID_CONTINUE: stop = false; break;
        }
    }
    if (!stop) return;

    show_place(vm);
    show_source(vm, NULL, frame_line(frame), 1);

    for (;;) {
        printf("(solid) ");
        fflush(stdout);

        char line[1024];
        if (fgets(line, sizeof line, stdin) == NULL) {
            /* End of input is the same as quitting: there is nobody to ask. */
            solid->quitting = true;
            printf("\n");
            break;
        }
        if (command(solid, vm, line)) break;
    }

    /* Leaving is an exit rather than a failure: the program is stopped on
       purpose, so it should not be reported as though it had gone wrong.
       `exiting` is what `system:exit` sets, and every loop that has to stop
       already checks it. */
    if (solid->quitting) {
        vm->exiting = true;
        vm->had_error = true;      /* the flag every loop checks to unwind */
        vm->exit_code = 0;
    }
}
