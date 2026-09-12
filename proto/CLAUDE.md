# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Start here

This directory is a subproject of Solveig, its parent, since 2026-09-12; the
parent's `CLAUDE.md` applies here too, and its `scratch/daily-standup.md` is
the standup for both. This directory's own `scratch/` is ignored and holds
what is Proto's alone. When there is no standup, `git log -- proto` and the
documents named below are the way in.

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
