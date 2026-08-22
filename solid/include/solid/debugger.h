/* debugger.h -- Solid, the interactive debugger.
 *
 * A program runs on an ordinary VM with a hook set. The VM offers a stop before
 * each instruction that begins a new line or changes frame; this decides
 * whether to take it, and when it does, reads commands until told to go on.
 *
 * So the machine knows nothing about stepping or breakpoints. It says where it
 * is and the debugger says whether that is interesting -- which is what keeps
 * `solum/` free of any of this, and what makes the hook cost one predictable
 * branch when nothing is driving.
 *
 * What it can show is what the chunk carries: the file and line of every frame
 * (6.27), and what each slot was called (6.28). Those were built first for
 * exactly this.
 */
#ifndef SOLID_DEBUGGER_H
#define SOLID_DEBUGGER_H

#include "solum/vm.h"

/* How the debugger is travelling. */
typedef enum {
    SOLID_STEP,       /* stop at the next line, wherever it is        */
    SOLID_NEXT,       /* stop at the next line in this frame or above */
    SOLID_FINISH,     /* stop when this frame has returned            */
    SOLID_CONTINUE,   /* stop only at a breakpoint                    */
} SolidMode;

typedef struct {
    char *file;       /* as written on the command; matched at the end of a path */
    int   line;
} SolidBreakpoint;

typedef struct {
    SolidMode mode;
    int       depth;        /* the frame count the mode was set at */
    int       line;         /* and the line, which `next` has to leave */

    /* The depth of the previous stop *offer*, whether or not it was taken.
       When it drops, this offer is a return -- the frame that was running has
       gone, and what we are looking at is the line the call was written on,
       which was already arrived at once. */
    int       last_offer_depth;
    bool      quitting;

    SolidBreakpoint *breaks;
    int              break_count;
    int              break_capacity;

    /* Where the last `list` finished, so a bare `list` walks on. */
    char *listing_file;
    int   listing_line;
} Solid;

void solid_init(Solid *solid);
void solid_free(Solid *solid);

/* The hook the VM calls. `context` is the Solid. */
void solid_stop(SolVM *vm, void *context);

#endif /* SOLID_DEBUGGER_H */
