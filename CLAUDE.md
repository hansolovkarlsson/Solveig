# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Start here

`scratch/daily-standup.md` — written at the end of the previous working day to
be read at the start of the next: where the tree was left, what went in, and
what is outstanding. `scratch/` is gitignored and is not part of this
repository, so the file is absent on a fresh clone and on any day that was not
closed out. When it is absent, `git log` and the documents named below are the
way in.

## What this is

A small object-oriented language and its toolkit — bytecode compiler (Solas),
VM (SolVM), REPL (Solis) and debugger (Solid). Prototype-based, everything is a
message send. ~20k lines of C11, no dependencies. Docs are published at
<https://hansolovkarlsson.github.io/Solveig/>.

`parasol/` is Parasol, a second compiler that emits Solveig source, brought in
as a subproject on 2026-09-12 with its history and a member of the toolkit
since 2026-09-15 (the plan was `A member of the toolkit` on its roadmap, now
frozen; nothing of it is open since 0.47.0 closed 7.1). Its pages are
`docs/PARASOL*.md`, its records to the day it joined are frozen under
`docs/parasol/`, its open roadmap entries are section 7 of `docs/ROADMAP.md`,
and its house rules are in `docs/method.md`. It has nothing of its own: the
version is the tree's, written into the generated `config.h` by the Makefile,
and `parasol/` is `cmd`, `include` and `src`, as `solas/` is. The root Makefile
builds it since 2026-09-14, in a section that must include no Solveig header
and link no Solveig library, and `make test` runs its suite; nothing under
`parasol/` includes a Solveig header, and that is the arrangement being tested.
Its examples are in `examples/`, its dialects in `lib/` and its seven programs
are directories under `programs/`, none of them counted by `docs/programs.md`,
and everything `parasol` generates goes under `build/`.

## Commands

`make`, `make test`, `make embed`, `make dist`, `make install`, `make clean`;
`make examples` for every example to a `.sob`, `make sanitize` for the suite
under AddressSanitizer and UBSan from a clean build, and one Parasol program
at a time as `make ember`, `grammar`, `digest`, `ledger`, `prose`, `minibasic`
or `bignum`.

## The records

In `docs/`: `journal.md` (why, in order — **newest first**), `COMPLETED.md`
and `ROADMAP.md` (what exists and what does not — an item moves when it is
settled, including settled against), `CHANGELOG.md` (when it shipped).

**There is no `postmortem.md`, and one should not be created.** Predictions are
scored in `docs/ideas.md`, which keeps the claim above the outcome.
`docs/parasol/POSTMORTEM.md` is Parasol's, moved in with its other records on
2026-09-15 and closed the same day: nothing is appended to it, and a defect
found in Parasol after that date is recorded the way any other is.

Each of those opens with a note stating its own job. That note is the
specification for what belongs in it — follow it over any general instruction.

## The suite checks the documents

`make test` runs `tests/test_documents.c` and `programs/expect.sol` over the
prose, and `docs/programs.md` carries live counts inside HTML comment markers —
`<n><!--count docs-claims--> claims across <n><!--count docs-documents-->
documents`, where each `<n>` is whatever the last run left. **Adding a file
to `docs/` moves those numbers and turns the suite red.** Re-run `make test`
after writing any document here, and re-sync the count if it moved.
