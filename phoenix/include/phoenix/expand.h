/* expand.h -- declared forms, replaced by what they stand for.
 *
 * Runs over the tree the reader built, between reading and emitting, and turns
 * every PHX_NODE_MACRO into an instance of its template. Three things happen at
 * once, and they happen together because doing any of them later would mean
 * doing the others again:
 *
 *   substitution   a parameter in the template becomes a copy of the argument
 *                  at the use, keeping the argument's own spans -- so an error
 *                  in an argument points at the argument.
 *
 *   hygiene        every name the *template* binds is renamed to one nothing
 *                  in the module uses, so a form cannot capture a name its
 *                  caller passed it or happened to have.
 *
 *   provenance     every node the template produced records the use that
 *                  produced it, so a diagnostic can say which form it is inside
 *                  and where that form was written.
 *
 * **Expansion terminates, and not because a counter says so.** A form's
 * template is read under the header as it stood at its own line, so it can
 * mention only the forms declared above it. Expanding form N yields uses of
 * forms below N and never of N itself, and the highest index strictly falls.
 * That is a property of the header reading top to bottom rather than a limit
 * bolted on afterwards. */
#ifndef PHOENIX_EXPAND_H
#define PHOENIX_EXPAND_H

#include "phoenix/diag.h"
#include "phoenix/dialect.h"
#include "phoenix/tree.h"
#include "phoenix/unit.h"

/* The macro uses, kept alive after they are replaced.
 *
 * An expanded node points at the use it came from, and a diagnostic walks that
 * chain to print the trail -- so the uses have to outlive the expansion that
 * consumed them. They live here, and the caller frees this after the last
 * diagnostic rather than before. */
typedef struct {
    PhxNode **nodes;
    int count, capacity;
} PhxProvenance;

void phx_provenance_init(PhxProvenance *provenance);
void phx_provenance_free(PhxProvenance *provenance);

/* Rewrites `module` in place. Answers false if anything was reported.
 *
 * Takes the unit rather than one source because a generated name has to be
 * fresh against every file the module is made of. A template read from a
 * `@use`d dialect can bind a `t`, and a name checked only against the file on
 * the command line would be fresh there and taken here. */
bool phx_expand(PhxNode *module, const PhxUnit *unit,
                const PhxDialect *dialect, PhxDiagnostics *diag,
                PhxProvenance *provenance);

#endif /* PHOENIX_EXPAND_H */
