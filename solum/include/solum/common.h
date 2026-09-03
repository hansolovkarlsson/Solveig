/* common.h -- shared basics for the Solum runtime. */
#ifndef SOLUM_COMMON_H
#define SOLUM_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SOLUM_VERSION "0.42.0"

/* What a loaded extension is allowed to call.
 *
 * An extension is a separate binary whose calls back into the machine are left
 * unresolved on purpose and bound at `dlopen` against what the program exports
 * -- so the executable's symbol table *is* the ABI, and until this existed that
 * table was whatever in `libsol.a` happened not to be `static`: 146 functions,
 * where extend.h names 23 and the bundles here use 13 between them. An
 * extension could bind to the parser, the line editor, or the bytecode reader,
 * and marking one of those `static` would have broken it silently.
 *
 * So the surface is declared rather than inferred. Everything is compiled
 * `-fvisibility=hidden` and this marks the exceptions, at the declaration each
 * belongs to, which is the only place that cannot go stale the way a list
 * beside the linker would -- and which is the objection the Makefile raises to
 * hand-kept lists in three other places.
 *
 * `used` as well as the visibility, because the two answer different questions:
 * visibility is whether the symbol may be seen from outside, and `used` is
 * whether it may be discarded for having no caller inside. Every one of these
 * has no caller inside; that is what makes them an ABI.
 *
 * Empty on a compiler without the attributes, which then exports what it always
 * did -- more than it should, and never less, so nothing stops working. */
#if defined(__GNUC__)
#define SOL_API __attribute__((visibility("default"), used))
#else
#define SOL_API
#endif

/* FNV-1a over `length` bytes. One hash for everything that needs one -- the
   symbol intern table, the VM's name table, and the hash index a chunk keeps
   over its side tables -- so there is one function to reason about rather than
   three that happen to agree. */
uint32_t sol_hash_bytes(const char *chars, int length);

#endif /* SOLUM_COMMON_H */
