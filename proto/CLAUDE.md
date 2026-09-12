# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Start here

`scratch/daily-standup.md` — written at the end of the previous working day to
be read at the start of the next: where the tree was left, what went in, and
what is outstanding. `scratch/` is gitignored and is not part of this
repository, so the file is absent on a fresh clone and on any day that was not
closed out. When it is absent, `git log` and the documents named below are the
way in.

## What this is

A compiler whose syntax arrives with the file it is compiling: a module
declares its own grammar in its header, and that grammar holds for that file
and no other. The output is Solveig source, which `solas` turns into bytecode.

## Commands

`make`, `make test`, `make check`, `make examples`, `make clean`. See the
Makefile for the rest — `grammar`, `ledger`, `prose`, `sanitize` and others.

## The records

In `docs/`: `journal.md` (why, in order — **newest first**), `POSTMORTEM.md`
(every defect, and what found it), `COMPLETED.md` and `ROADMAP.md` (what
exists and what does not — an item moves when it is settled, including settled
against), `CHANGELOG.md` (when). `conventions.md` states this repository's own
house rules; read it first.

Each of those opens with a note stating its own job. That note is the
specification for what belongs in it — follow it over any general instruction.
