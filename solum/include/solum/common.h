/* common.h -- shared basics for the Solum runtime. */
#ifndef SOLUM_COMMON_H
#define SOLUM_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SOLUM_VERSION "0.6.0"

/* FNV-1a over `length` bytes. One hash for everything that needs one -- the
   symbol intern table, the VM's name table, and the hash index a chunk keeps
   over its side tables -- so there is one function to reason about rather than
   three that happen to agree. */
uint32_t sol_hash_bytes(const char *chars, int length);

#endif /* SOLUM_COMMON_H */
