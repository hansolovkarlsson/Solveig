/* gc.h -- the mark-sweep collector.
 *
 * The heap is small: everything allocated at run time is either a SolObject,
 * which owns its slot chain, or a SolBlock. Chunks, code, constants, and names
 * are compile-time data owned by whoever compiled them, and are not collected.
 *
 * Both heap types begin with a SolGCHeader, so one list threads the whole heap
 * and one sweep loop walks it. A new heap type joins by embedding the header and
 * adding a case to the tracer and the freer -- it does not add another list.
 *
 * Non-moving: a copying collector would have to fix up every SolValue in the
 * value stack, in slots, and in a block's captured self, for no benefit at this
 * size. Nothing outside gc.c may hold a heap pointer across an allocation
 * without that pointer being reachable from a root.
 */
#ifndef SOLUM_GC_H
#define SOLUM_GC_H

#include "solum/common.h"

typedef struct SolVM SolVM;

/* Bytes allocated before the first collection, and the floor the threshold is
   never allowed to fall below afterwards. */
#define SOL_GC_INITIAL_THRESHOLD (64 * 1024)

/* Foreign cells that may be made before one is collected regardless of bytes.
 *
 * Deliberately far below the smallest descriptor ceiling a system is likely to
 * impose -- macOS starts processes at 256 -- because the resource that runs out
 * is not the one the threshold above measures. Collections are cheap at these
 * heap sizes, and nothing reachable is freed by one, so the cost of being eager
 * here is a few microseconds and the cost of not being is a program that dies
 * holding memory it never used. */
#define SOL_GC_FOREIGN_PRESSURE 64

/* Depth of the temporary-root stack. Small on purpose: needing many at once
   means a value should be reachable from somewhere the tracer already looks. */
#define SOL_GC_MAX_TEMPS 8

typedef enum {
    SOL_GC_OBJECT,
    SOL_GC_BLOCK,
    SOL_GC_ARRAY,
    SOL_GC_DICT,
    SOL_GC_STRING,
    SOL_GC_SYMBOL,
    SOL_GC_DELEGATE,
    SOL_GC_CODE,    /* a compiled chunk tree; see SolCode in bytecode.h */
    SOL_GC_FOREIGN  /* a resource an extension owns; see SolForeign in object.h */
} SolGCType;

typedef struct SolGCHeader {
    struct SolGCHeader *next;    /* all-heap list, and the sweep list */
    SolGCType           type;
    bool                marked;
} SolGCHeader;

/* Registers a freshly allocated cell on the heap list. Called by the allocators
   in object.c once the cell's fields are set. */
void sol_gc_register(SolVM *vm, SolGCHeader *header, SolGCType type, size_t size);

/* Collects if this allocation should trigger one. Call *before* allocating, so
   the new cell -- which nothing points at yet -- cannot be swept. */
void sol_gc_maybe_collect(SolVM *vm);

/* Marks from the roots and frees everything unreachable. */
void sol_gc_collect(SolVM *vm);

/* Drops unreachable symbols from the intern table, between marking and
   sweeping. The table is the one structure that must *not* keep what it holds
   alive: a symbol interned once and never used again would otherwise live as
   long as the VM. */
void sol_gc_prune_symbols(SolVM *vm);

/* Frees the entire heap regardless of reachability, for VM shutdown. */
void sol_gc_free_all(SolVM *vm);

/* Temporary roots.
 *
 * A cell held only in a C local is invisible to the collector, so anything that
 * must survive an allocation goes here first. Push before the window opens, pop
 * when the cell is reachable from somewhere the tracer looks. */
void sol_gc_push_temp(SolVM *vm, SolGCHeader *header);
void sol_gc_pop_temp(SolVM *vm);

/* Live bytes, counting the cells themselves and the slots objects own. */
size_t sol_gc_live_bytes(const SolVM *vm);

/* Number of live cells, for tests that want to watch collection happen. */
int sol_gc_live_count(const SolVM *vm);

#endif /* SOLUM_GC_H */
