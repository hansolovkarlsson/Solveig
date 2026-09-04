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

## Commands

`make`, `make test`, `make embed`, `make dist`, `make install`, `make clean`.

## The records

In `docs/`: `journal.md` (why, in order — **newest first**), `COMPLETED.md`
and `ROADMAP.md` (what exists and what does not — an item moves when it is
settled, including settled against), `CHANGELOG.md` (when it shipped).

**There is no `postmortem.md`, and one should not be created.** Predictions are
scored in `docs/ideas.md`, which keeps the claim above the outcome.

Each of those opens with a note stating its own job. That note is the
specification for what belongs in it — follow it over any general instruction.

## The suite checks the documents

`make test` runs `tests/test_documents.c` and `programs/expect.sol` over the
prose, and `docs/programs.md` carries live counts inside HTML comment markers —
`476<!--count docs-claims--> claims across twenty-nine<!--count
docs-documents--> documents`. **Adding a file to `docs/` moves those numbers and
turns the suite red.** Re-run `make test` after writing any document here, and
re-sync the count if it moved.
