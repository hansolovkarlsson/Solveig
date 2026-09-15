# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Start here

This directory is a subproject of Solveig, its parent, since 2026-09-12; the
parent's `CLAUDE.md` applies here too, and its `scratch/daily-standup.md` is
the standup for both. This directory's own `scratch/` is ignored and holds
what is Parasol's alone. When there is no standup, `git log -- parasol` and the
documents named below are the way in.

## What this is

A compiler whose syntax arrives with the file it is compiling: a module
declares its own grammar in its header, and that grammar holds for that file
and no other. The output is Solveig source, which `solas` turns into bytecode;
`parasol --sob` runs that `solas` for you and does not link it. Nothing under
`parasol/` includes a Solveig header, and that is the arrangement being tested.

## Commands

From the root, since 2026-09-14; there is no Makefile here. `make`, `make
test`, `make examples`, `make sanitize`, `make clean`, and one program at a
time as `make ember`, `grammar`, `digest`, `ledger`, `prose`, `minibasic` or
`bignum`. Since 2026-09-14 the examples are in `examples/`, the dialects in
`lib/` and the programs under `programs/`, beside Solveig's own, and what
`parasol` generates from them goes under `build/`. The Parasol section of the root Makefile says how the build keeps
the no-Solveig claim.

## The records

In `docs/`: `journal.md` (why, in order — **newest first**), `POSTMORTEM.md`
(every defect, and what found it), `COMPLETED.md` and `ROADMAP.md` (what
exists and what does not — an item moves when it is settled, including settled
against), `CHANGELOG.md` (when). Parasol's house rules were `conventions.md`
until 2026-09-15 and are in the root's `docs/method.md` now, with the rest of
its pages under `docs/PARASOL*.md`.

Each of those opens with a note stating its own job. That note is the
specification for what belongs in it — follow it over any general instruction.
