/* serialize.h -- the .sob bytecode file format.
 *
 * This is how Solas hands work to Solum. The format is little-endian
 * throughout, independent of the host, so a .sob file is portable.
 *
 *   offset  size  field
 *   0       4     magic "SOLB"
 *   4       2     format version (currently SOL_SOB_VERSION)
 *   6       2     the script's frame slot count, at least 1
                 (was reserved-must-be-zero before version 11: the top-level
                 chunk is the only one whose frame size is not already carried
                 by the method that owns it)
 *   8       4     name count
 *                 each name: u16 length, then that many bytes (no NUL)
 *           4     constant count
 *                 each constant: u8 tag, then its payload
 *                   0 = nil    (no payload)
 *                   1 = int    (i64)
 *                   2 = float  (f64, IEEE-754 binary64)
 *           4     code length, then that many bytes
 *           4     line-run count
 *                 each run: u32 length, u32 line
 *           4     method count
 *                 each method: u16 name length + bytes, u16 arity,
 *                 u16 slot count, u16 flags (1 = block, 2 = captures its home
 *                 frame), then that method's chunk, recursively
 *
 * Line numbers are run-length encoded because consecutive instructions almost
 * always share a line; the runs expand back into the chunk's parallel array on
 * load.
 *
 * Everything loaded from disk is verified before it can run -- see
 * sol_chunk_verify. A .sob file is untrusted input.
 */
#ifndef SOLUM_SERIALIZE_H
#define SOLUM_SERIALIZE_H

#include "solum/common.h"
#include "solum/bytecode.h"

#define SOL_SOB_MAGIC   "SOLB"
#define SOL_SOB_VERSION 11

typedef enum {
    SOL_SER_OK,
    SOL_SER_IO,           /* could not open, read, or write the file        */
    SOL_SER_BAD_MAGIC,    /* not a .sob file at all                         */
    SOL_SER_BAD_VERSION,  /* a .sob file this build cannot read             */
    SOL_SER_TRUNCATED,    /* the file ends in the middle of a structure     */
    SOL_SER_MALFORMED,    /* structurally intact but internally inconsistent*/
    SOL_SER_UNSUPPORTED   /* holds something this version cannot represent  */
} SolSerResult;

const char *sol_ser_message(SolSerResult result);

SolSerResult sol_chunk_save(const SolChunk *chunk, const char *path);

/* Initialises `chunk` and fills it from `path`. The chunk is verified before
   this returns OK; on any failure it is left freed and safe to discard. */
SolSerResult sol_chunk_load(SolChunk *chunk, const char *path);

/* Checks that the code is safe to execute: every instruction fits, every
   operand indexes something that exists, and the last instruction stops the
   machine so the dispatch loop cannot run off the end of the buffer. */
SolSerResult sol_chunk_verify(const SolChunk *chunk);

#endif /* SOLUM_SERIALIZE_H */
