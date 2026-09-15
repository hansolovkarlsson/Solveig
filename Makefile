# Solum -- build for all three components.
#
#   make            build bin/solas, bin/solvm, bin/solis, bin/solid, bin/parasol
#   make test       build and run the test suite, Parasol's included
#   make sanitize   the suite again under AddressSanitizer and UBSan, from clean
#   make examples   every example, Solveig's and Parasol's, to a .sob
#   make embed      build bin/solhost -- see solum/include/solum/embed.h
#   make install    install to $(PREFIX), default /usr/local
#   make uninstall  take it back out again
#   make dist       a source tarball of HEAD, named for the version
#   make clean      remove build artefacts
#
# The Parasol rules are in a section of their own further down, and one of
# Parasol's programs at a time is `make ember`, `grammar`, `digest`, `ledger`,
# `prose`, `basic` or `bignum`.

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -g
INCLUDES = -Isolum/include -Isolas/include -Isolis/include -Isolid/include \
           -I$(BUILD)
AR      ?= ar

# What the standard library has to be asked for, and what has to be linked.
#
# `-std=c11` asks for ISO C and nothing besides, and glibc takes that at its
# word: `realpath`, `gmtime_r` and `strptime` stay hidden until a feature-test
# macro says which standard beyond ISO the file wants. Apple's headers show them
# regardless, which is why this was found by a Linux runner and not here. macOS
# goes the other way -- naming a standard *narrows* what is visible -- so
# _DARWIN_C_SOURCE is the one to set there, and it is what brings back the
# sub-second `struct stat` fields builtins.c reads.
#
# Per-file `#define`s came first and are kept where they explain which function
# needed them. This is here because forgetting one is a build failure on a
# machine the author is not sitting at.
ifeq ($(shell uname -s),Darwin)
STANDARD = -D_DARWIN_C_SOURCE
else
STANDARD = -D_XOPEN_SOURCE=700
endif

# libm is part of libSystem on macOS and a separate library everywhere else, so
# `sqrt`, `floor` and `llround` resolve here and fail to link there. Harmless on
# macOS, which is why it is not conditional.
LDLIBS = -lm

# What lets a loaded extension resolve `sol_*` back into the program that loaded
# it -- see solum/include/solum/extend.h and docs/extensions.md.
#
# The obvious statement of the problem is wrong and was believed for a while: it
# is not that nothing is exported. A Mach-O executable exports its global
# symbols without being asked, and `-Wl,-export_dynamic` on macOS was measured
# to change the count not at all, which is why it is absent below.
#
# What actually fails is that a linker takes objects out of an archive *on
# demand*. A symbol reaches the executable's export table only if the executable
# already referenced it -- so `sol_object_define_primitive` was there, because
# builtins.c uses it, and `sol_vm_set_global` was not, because it lives in
# embed.c and no front end here calls it. The four binaries exported four
# different accidental sets: 100, 118, 133 and 118 `sol_*` symbols. Whole-archive
# linking makes all four 139, which is a surface somebody chose.
#
# ELF is the other way round and needs both: `--whole-archive` to keep the
# objects, and `-rdynamic` to put them in the dynamic symbol table, which an
# executable otherwise does not get.
#
# `-ldl` for `dlopen`. Folded into libc in glibc 2.34 and a harmless empty stub
# since, so it is right for both old and new.
ifeq ($(shell uname -s),Darwin)
WHOLE_LIB = -Wl,-force_load,$(LIB)
EXPORT    =
# A bundle leaves `sol_*` unresolved for the loading program to satisfy. ELF
# does that by default; Mach-O has to be told, and refuses to link otherwise.
BUNDLE_LD = -Wl,-undefined,dynamic_lookup
else
WHOLE_LIB = -Wl,--whole-archive $(LIB) -Wl,--no-whole-archive
EXPORT    = -rdynamic
LDLIBS   += -ldl
BUNDLE_LD =
endif

# Empty by default; the sanitizers go here rather than into CFLAGS.
#
#   make clean && make test SANITIZE="-fsanitize=address,undefined"
#
# CFLAGS is not the place for them. It is `?=`, so setting it on the command
# line replaces the warning flags -- and, less visibly, `+=` on a target below
# stops applying, which would link test_threads without `-pthread` and say
# nothing about it. A separate variable leaves both alone.
#
# The same value has to reach the link, which it does: every rule that links
# passes this too, and -fsanitize is a link-time flag as much as a compile-time
# one.
SANITIZE =

# Everything compiled into the machine is hidden unless `SOL_API` says
# otherwise -- see the note on it in solum/include/solum/common.h. This is what
# turns the extension ABI from "whatever in libsol.a is not static", which was
# 146 functions including the parser and the line editor, into the 23 that
# extend.h names.
#
# Deliberately not on the bundle rules further down. `sol_extension_init` is the
# *bundle's* symbol rather than the machine's, and hiding it would mean every
# extension source anywhere needed a new annotation to keep working. What a
# bundle exports is its own business; this is about what the machine promises.
VISIBILITY = -fvisibility=hidden

BUILD = build
BIN   = bin
DIST  = dist

# Where `make install` puts things. DESTDIR stages an install somewhere else
# for packaging and is not part of the path a binary looks in at run time,
# which is why SOL_LIB_DIR below is built from PREFIX alone.
PREFIX ?= /usr/local
BINDIR  = $(DESTDIR)$(PREFIX)/bin
LIBDIR  = $(DESTDIR)$(PREFIX)/lib/solum

# How a binary that was found on PATH learns where its library went.
#
# `argv[0]` says where the binary is only when it was named with a path. Run as
# `solas` off PATH it says nothing, and searching PATH again to guess is what
# compiler.c deliberately refuses to do -- but a path the install *told* it is
# not a guess.
#
# Written to a file rather than passed as `-D` so that changing PREFIX rebuilds
# what depends on it. A binary carrying a path from a previous PREFIX fails by
# not finding `@include "text.sol"`, with nothing on screen saying why, and a
# command-line `-D` leaves stale objects holding the old value. The file is
# replaced only when its contents change, so re-running make costs nothing.
CONFIG = $(BUILD)/config.h

LIB_SRCS  = $(wildcard solum/src/*.c) $(wildcard solas/src/*.c) \
            $(wildcard solis/src/*.c) $(wildcard solid/src/*.c)
LIB_OBJS  = $(LIB_SRCS:%.c=$(BUILD)/%.o)
LIB       = $(BUILD)/libsol.a

# ext_probe.c is a shared object rather than a test binary -- it has no `main`
# and is built by the rule further down. Filtered out here so that the wildcard
# stays a wildcard: a new tests/*.c is still picked up without editing a list,
# which is the property this line has always been for.
TEST_SRCS = $(filter-out tests/ext_probe.c,$(wildcard tests/*.c))
TEST_BINS = $(TEST_SRCS:tests/%.c=$(BUILD)/tests/%)

# Five since 2026-09-14: bin/parasol is built by its own rule in the Parasol
# section, linked against its own library and nothing here, and is in this
# list for what the list is used for -- `all`, `install` and `uninstall`.
BINARIES = $(BIN)/solas $(BIN)/solvm $(BIN)/solis $(BIN)/solid $(BIN)/parasol

# The bundles this repository ships. Built by `all` and loaded by nobody unless
# a host asks with `--extension=`, which is the whole arrangement: the
# capability is here, and granting it is still a decision taken on a command
# line. The rule is beside the test probe's, further down.
EXTENSIONS = $(BUILD)/extensions/net.so

.PHONY: all test sanitize examples embed install uninstall dist clean FORCE
all: $(BINARIES) $(EXTENSIONS)

# Below `all`, because make's default goal is whichever target it reads first
# and this one is not it. Rebuilt every run and replaced only when its contents
# change, so a new PREFIX rebuilds what depends on it and an unchanged one
# costs nothing.
$(CONFIG): FORCE
	@mkdir -p $(@D)
	@echo '/* Generated by the Makefile. Set PREFIX there, not here. */' > $@.new
	@echo '#define SOL_LIB_DIR "$(PREFIX)/lib/solum"' >> $@.new
	@cmp -s $@.new $@ || mv $@.new $@
	@rm -f $@.new

FORCE:

# ---------------------------------------------------------------------------
# Parasol -- a compiler whose syntax arrives with the file it is compiling.
#
# **Parasol's build takes nothing from Solveig.** Parasol emits Solveig
# *source*, and source is text, so nothing below includes a solum header or
# links libsol.a. That is not an accident of where the code ended up; it is the
# arrangement being tested. A front end with privileged access to the compiler
# it targets proves only that its author can write one, and the whole claim
# Parasol is making is that a dialect is something anybody can write on top of
# a substrate they do not get to change.
#
# Until 2026-09-14 that claim was kept by a separate Makefile under parasol/,
# which could not reach the headers because it did not know where they were.
# In one file it is kept by the rules instead, and by the build itself: every
# Parasol object is compiled with PARASOL_INCLUDES and not INCLUDES, so an
# `#include "solum/..."` fails to compile; bin/parasol is linked against
# libparasol.a and not libsol.a, so a `sol_*` reference fails to link; and
# `test` reads the binary's symbol table and refuses one that exports any. The
# only way Parasol reaches Solveig is the way a user does -- the binaries under
# bin/, which the program rules below hand a file, and which `parasol --sob`
# runs from inside the compiler.
#
# Under $(BUILD)/parasol/ rather than beside the other objects, and by a pattern
# rule of its own, which is why this section sits *above* the generic
# $(BUILD)/%.o rule: GNU make 3.81, which is the one macOS ships, takes the
# first pattern rule that matches, and 4.x the one with the shortest stem, and
# this order satisfies both. So the generic rule, with its solum include path,
# never sees a Parasol source.
PARASOL_INCLUDES = -Iparasol/parasol/include
PARASOL_SRCS     = $(wildcard parasol/parasol/src/*.c)
PARASOL_OBJS     = $(PARASOL_SRCS:parasol/%.c=$(BUILD)/parasol/%.o)
PARASOL_LIB      = $(BUILD)/libparasol.a

PARASOL_TEST_SRCS = $(wildcard parasol/tests/*.c)
PARASOL_TEST_BINS = $(PARASOL_TEST_SRCS:parasol/tests/%.c=$(BUILD)/parasol/tests/%)

# What `test` runs against the linked binary. On macOS the symbols carry a
# leading underscore and on ELF they do not; `parasol_` contains `sol_` and is
# not matched, because the pattern wants the space or the underscore right
# before it.
PARASOL_BOUNDARY = if nm -g $(BIN)/parasol | grep -Eq ' _?sol_'; then \
                       echo "bin/parasol exports a sol_ symbol -- it has linked Solveig"; exit 1; fi

$(BIN)/parasol: parasol/parasol/cmd/main.c $(PARASOL_LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(PARASOL_INCLUDES) $< $(PARASOL_LIB) -o $@

$(PARASOL_LIB): $(PARASOL_OBJS)
	@mkdir -p $(@D)
	$(AR) rcs $@ $^

$(BUILD)/parasol/%.o: parasol/%.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(PARASOL_INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/parasol/tests/%: parasol/tests/%.c $(PARASOL_LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(PARASOL_INCLUDES) $< $(PARASOL_LIB) -o $@

# The dialect files the examples reach with @use. Listed so that changing one
# rebuilds every example, which a per-example dependency could not do without
# reading the headers to find out which uses what.
DIALECTS = $(wildcard parasol/lib/*.psol)

PARASOL_EXAMPLE_SRCS = $(wildcard parasol/examples/*.psol)
PARASOL_EXAMPLE_SOLS = $(PARASOL_EXAMPLE_SRCS:.psol=.sol)
PARASOL_EXAMPLE_SOBS = $(PARASOL_EXAMPLE_SRCS:.psol=.sob)

# The map is written every time rather than on request. It costs a file and it
# is the thing that is never there when it is wanted. And the two steps are
# done here rather than by `parasol --sob`, so that the suite goes on checking
# the pipeline a Makefile writes and not only the one the driver drives;
# parasol/tests/test_sob.c checks the driver.
parasol/examples/%.sol: parasol/examples/%.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

parasol/examples/%.sob: parasol/examples/%.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# The programs written in Parasol, each with its own README. Built and run by
# `test`, because a language with no program written in it has never been
# tested by anything but its own examples.
#
# ember -- a compiler written in Parasol, and the first customer any of this
# had. The whole stack in one target: .psol to .sol to .sob, then a .em through
# that to assembly, then cc. Five programs and two languages to print a prime.
EMBER      = parasol/programs/ember
EMBER_SRCS = $(wildcard $(EMBER)/examples/*.em)
EMBER_ASM  = $(EMBER_SRCS:.em=.s)
EMBER_BINS = $(EMBER_SRCS:.em=.out)

# grammar -- a second customer, and a different domain: notation for something
# recursive, where ember's was notation for something flat.
GRAMMAR       = parasol/programs/grammar
GRAMMAR_SRCS  = $(wildcard $(GRAMMAR)/examples/*.psol)
GRAMMAR_SOLS  = $(GRAMMAR_SRCS:.psol=.sol)
GRAMMAR_SOBS  = $(GRAMMAR_SRCS:.psol=.sob)

# digest -- the third, and the first for the *operator* half of Parasol:
# sixty-four rounds of shifts, rotations and masked additions, in the notation
# FIPS 180-4 writes them in. ledger and prose the fourth and fifth.
DIGEST = parasol/programs/digest
LEDGER = parasol/programs/ledger
PROSE  = parasol/programs/prose

# basic -- the sixth, and the first that is not a pass over its input: an
# interpreter has a counter that can go backwards. Its `.bas` files are data it
# reads at run time, so nothing here compiles them.
BASIC  = parasol/programs/basic

# bignum -- the seventh, and the first in two modules: a library in one dialect
# and a driver in another, the driver reaching the library's *generated* source
# with @include. So calc.sol depends on bignum.sol.
BIGNUM = parasol/programs/bignum

.PHONY: ember grammar digest ledger prose basic bignum

# Without this, make treats a generated .sol as an intermediate and deletes it
# after the .sob is built -- taking the map with it. Both are the artefacts
# somebody reaches for when the generated code is what they need to read.
.SECONDARY: $(PARASOL_EXAMPLE_SOLS) $(EMBER)/emberc.sol $(EMBER)/emberc.sob $(EMBER_ASM) \
            $(GRAMMAR_SOLS) $(DIGEST)/sha256.sol $(LEDGER)/ledger.sol \
            $(PROSE)/note.sol $(BASIC)/basic.sol $(BIGNUM)/bignum.sol \
            $(BIGNUM)/calc.sol

$(EMBER)/emberc.sol: $(EMBER)/emberc.psol $(EMBER)/asm.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(EMBER)/emberc.sob: $(EMBER)/emberc.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

$(EMBER)/examples/%.s: $(EMBER)/examples/%.em $(EMBER)/emberc.sob $(BIN)/solvm
	@$(BIN)/solvm $(EMBER)/emberc.sob $< > $@

$(EMBER)/examples/%.out: $(EMBER)/examples/%.s
	@$(CC) $< -o $@

ember: $(EMBER_BINS)
	@for b in $(EMBER_BINS); do echo "-- $$b"; $$b; done

$(GRAMMAR)/examples/%.sol: $(GRAMMAR)/examples/%.psol $(GRAMMAR)/peg.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(GRAMMAR)/examples/%.sob: $(GRAMMAR)/examples/%.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

grammar: $(GRAMMAR_SOBS)
	@for g in $(GRAMMAR_SOBS); do echo "-- $$g"; $(BIN)/solvm $$g; done

$(DIGEST)/sha256.sol: $(DIGEST)/sha256.psol $(DIGEST)/sha2.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(DIGEST)/sha256.sob: $(DIGEST)/sha256.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# With no arguments it hashes the vectors it carries, which is the check; with a
# file it is the tool. The expected digests are the ones printed in FIPS 180-4
# and the ones `shasum -a 256` gives, which agreed before this was committed.
digest: $(DIGEST)/sha256.sob
	@$(BIN)/solvm $(DIGEST)/sha256.sob

$(LEDGER)/ledger.sol: $(LEDGER)/ledger.psol $(LEDGER)/money.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(LEDGER)/ledger.sob: $(LEDGER)/ledger.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# The figures it prints were produced independently, in exact decimal, and are
# in ledger.expected. A program that verifies itself verifies nothing.
ledger: $(LEDGER)/ledger.sob
	@$(BIN)/solvm $(LEDGER)/ledger.sob

$(PROSE)/note.sol: $(PROSE)/note.psol $(PROSE)/prose.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(PROSE)/note.sob: $(PROSE)/note.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# The document is the program. prose.expected is derived from note.psol by hand
# rather than captured from a run -- see its README.
prose: $(PROSE)/note.sob
	@$(BIN)/solvm $(PROSE)/note.sob

$(BASIC)/basic.sol: $(BASIC)/basic.psol $(BASIC)/interp.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(BASIC)/basic.sob: $(BASIC)/basic.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# With a file it runs it; with none it is a prompt. basic.expected is worked out
# from the three `.bas` files by hand and not captured from a run.
basic: $(BASIC)/basic.sob
	@$(BIN)/solvm $(BASIC)/basic.sob $(BASIC)/examples/fizzbuzz.bas

# Two Parasol modules, and solas sees both: calc.sol includes bignum.sol, so the
# .sob depends on the generated library as well as on the generated driver.
$(BIGNUM)/bignum.sol: $(BIGNUM)/bignum.psol $(BIGNUM)/limbs.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(BIGNUM)/calc.sol: $(BIGNUM)/calc.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(BIGNUM)/calc.sob: $(BIGNUM)/calc.sol $(BIGNUM)/bignum.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# Every answer it prints was produced by bc first, and is in bignum.expected.
bignum: $(BIGNUM)/calc.sob
	@$(BIN)/solvm $(BIGNUM)/calc.sob

# ---------------------------------------------------------------------------

# Not in `all`: it is a demonstration of the C interface rather than a program
# anybody installs. See embed/host.c and docs/embedding.md.
embed: $(BIN)/solhost

$(BIN)/solhost: embed/host.c $(LIB) | $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) $(EXPORT) \
	    $< $(WHOLE_LIB) -o $@ $(LDLIBS)

$(BIN)/solas: solas/cmd/main.c $(LIB) | $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) $(EXPORT) \
	    $< $(WHOLE_LIB) -o $@ $(LDLIBS)

$(BIN)/solvm: solum/cmd/main.c $(LIB) | $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) $(EXPORT) \
	    $< $(WHOLE_LIB) -o $@ $(LDLIBS)

$(BIN)/solis: solis/cmd/main.c $(LIB) | $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) $(EXPORT) \
	    $< $(WHOLE_LIB) -o $@ $(LDLIBS)

$(BIN)/solid: solid/cmd/main.c $(LIB) | $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) $(EXPORT) \
	    $< $(WHOLE_LIB) -o $@ $(LDLIBS)

$(LIB): $(LIB_OBJS)
	@mkdir -p $(@D)
	$(AR) rcs $@ $^

$(BUILD)/%.o: %.c $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/tests/%: tests/%.c $(LIB) | $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(VISIBILITY) $(INCLUDES) $(EXPORT) \
	    $< $(WHOLE_LIB) -o $@ $(LDLIBS)

# The one test that needs threads. Nothing else links anything, and the point of
# keeping it to one target is that a build without pthreads still gets the rest.
$(BUILD)/tests/test_threads: CFLAGS += -pthread

# A real extension, built as a real shared object, because one question cannot
# be answered without one: whether a loaded bundle can resolve `sol_*` back into
# the binary that loaded it. See tests/ext_probe.c for why a test binary cannot
# stand in for `bin/solvm` here.
#
# Built here rather than by the test at run time. A test that shells out to a
# compiler is a test that fails differently on every machine, and this way a
# platform that cannot build a bundle at all says so during the build.
EXT_PROBE = $(BUILD)/tests/ext_probe.so

$(EXT_PROBE): tests/ext_probe.c $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(INCLUDES) -fPIC -shared \
	    $< -o $@ $(BUNDLE_LD)

# The bundles this repository ships, built by `all` and loaded by nobody unless
# a host asks for one with `--extension=`. That is the whole arrangement: the
# capability is here, and granting it is still a decision somebody takes on a
# command line.
#
# These may live here, where GTK and SDL2 may not, and the difference is the
# front page's sentence rather than a policy about extensions. A bundle that
# needs a toolkit installed would make *no dependencies beyond a C11 compiler
# and `make`* false; sockets need POSIX, which is already assumed by every
# `dlopen` and `fork` in this tree.
$(BUILD)/extensions/net.so: extensions/net/net.c $(CONFIG)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(INCLUDES) -fPIC -shared \
	    $< -o $@ $(BUNDLE_LD)

# An example that loads a compiled file needs one to be there. `system:load`
# takes bytecode and never source, so `examples/load.sol` wants
# `examples/library.sob` on disk -- and bytecode is a build artefact that is not
# committed, so on a fresh clone it is not. The example passed only on the
# machine where somebody had happened to compile the library by hand.
#
# Wildcarded rather than listing the two or three that are wanted, for the
# reason the install rule gives below: a hand-kept list here goes stale.
EXAMPLE_SRCS = $(wildcard examples/*.sol)
EXAMPLE_SOBS = $(EXAMPLE_SRCS:.sol=.sob)

examples/%.sob: examples/%.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# The one example written to the `@expr` region, which is off unless asked for.
# Its first line says so, and this rule is that line kept true.
examples/operators.sob: examples/operators.sol $(BIN)/solas
	@$(BIN)/solas --expr $< -o $@

# The benchmark programs under comparisons/ are compiled by `make test` and not
# run by it. Compiled, because a program that stops compiling is exactly the rot
# that happens to code nothing builds -- and these are cited by
# docs/performance.md, which makes them documentation.
#
# Not run, because each is sized to take about a second by design and there are
# nine of them, run against CPython -- about ninety seconds. The suite is about
# eighty-eight, so that is a doubling rather than the twelvefold this comment
# used to claim: it said *a suite that takes eight*, which had stopped being
# true without anybody measuring. The conclusion is unchanged and the reason is
# now the right size. They are run by comparisons/python/run.sh, deliberately,
# by somebody who meant to.
#
# Where the time goes, measured on 2026-09-03: test_documents 55 seconds at 41%
# CPU, test_cli 27 at 96%, and the other thirty-eight binaries plus the
# conformance corpus about seven between them. The suite spends nearly two
# fifths of its wall clock waiting on subprocesses, so the total drifts by a
# few seconds between runs and is not worth quoting more precisely than this.
COMPARISON_SRCS = $(wildcard comparisons/*/*.sol) $(wildcard comparisons/*/probes/*.sol)
COMPARISON_SOBS = $(COMPARISON_SRCS:.sol=.sob)

comparisons/%.sob: comparisons/%.sol $(BIN)/solas
	@$(BIN)/solas $< -o $@

# The binaries too: test_cli runs them as a shell would, a `main` not being
# something the library holds.
#
# And the conformance corpus, which is the one part of this suite written in the
# language rather than about it. It is here rather than beside the oracles for
# the reason those are not: it needs no network and no clone, it takes about a
# second, and a corpus a second implementation is invited to score itself against
# has to be one this implementation is continuously scored against too. The day
# one of the eleven chunk limits moves, this is what says so.
#
# It runs with its own defaults, which name $(BIN)/solas and $(BIN)/solvm --
# so `make test SANITIZE=...` scores the sanitised build, as the C tests do.
# Pointing it elsewhere is SOL_COMPILE and SOL_RUN, and that is a thing somebody
# does deliberately rather than something this target decides for them.
# It runs first, and that is not a statement about which matters more. The C
# suite is about eighty seconds on this machine and the corpus is one, so a case
# that breaks says so at the start rather than after a minute and a half of
# something else.
#
# Then Parasol's, in the same run, so that a change here which breaks a dialect
# goes red beside the change. Its examples and programs are compiled *and run*,
# all the way down to a .sob that SolVM executes: a front end that emits text
# can be wrong in a way no unit test sees -- valid-looking Solveig that Solveig
# rejects, or accepts and reads differently -- and the only witness is the real
# compiler. PARASOL_BIN is for parasol/tests/test_sob.c, which runs the
# binaries rather than linking the library and has to be told where they are.
test: $(BINARIES) $(TEST_BINS) $(EXAMPLE_SOBS) $(COMPARISON_SOBS) $(EXT_PROBE) $(EXTENSIONS) \
      $(PARASOL_TEST_BINS) $(PARASOL_EXAMPLE_SOBS) $(EMBER_BINS) $(GRAMMAR_SOBS) \
      $(DIGEST)/sha256.sob $(LEDGER)/ledger.sob $(PROSE)/note.sob \
      $(BASIC)/basic.sob $(BIGNUM)/calc.sob
	@echo "-- conformance"
	@sh conformance/run.sh
	@for t in $(TEST_BINS); do echo "-- $$t"; $$t || exit 1; done
	@echo "-- parasol"
	@$(PARASOL_BOUNDARY)
	@for t in $(PARASOL_TEST_BINS); do echo "-- $$t"; PARASOL_BIN=$(BIN) $$t || exit 1; done
	@for e in $(PARASOL_EXAMPLE_SOBS); do echo "-- $$e"; \
	    $(BIN)/solvm $$e > /dev/null || exit 1; done
	@for b in $(EMBER_BINS); do echo "-- $$b"; \
	    $$b | diff -u $${b%.out}.expected - || exit 1; done
	@for g in $(GRAMMAR_SOBS); do echo "-- $$g"; \
	    $(BIN)/solvm $$g | diff -u $${g%.sob}.expected - || exit 1; done
	@echo "-- $(DIGEST)/sha256.sob"
	@$(BIN)/solvm $(DIGEST)/sha256.sob | diff -u $(DIGEST)/sha256.expected - || exit 1
	@echo "-- $(LEDGER)/ledger.sob"
	@$(BIN)/solvm $(LEDGER)/ledger.sob | diff -u $(LEDGER)/ledger.expected - || exit 1
	@echo "-- $(PROSE)/note.sob"
	@$(BIN)/solvm $(PROSE)/note.sob | diff -u $(PROSE)/prose.expected - || exit 1
	@echo "-- $(BASIC)/basic.sob"
	@{ $(BIN)/solvm $(BASIC)/basic.sob $(BASIC)/examples/fizzbuzz.bas; \
	   $(BIN)/solvm $(BASIC)/basic.sob $(BASIC)/examples/primes.bas; \
	   printf 'Ada\n36\n' | $(BIN)/solvm $(BASIC)/basic.sob $(BASIC)/examples/greet.bas; \
	 } | diff -u $(BASIC)/basic.expected - || exit 1
	@echo "-- $(BIGNUM)/calc.sob"
	@$(BIN)/solvm $(BIGNUM)/calc.sob | diff -u $(BIGNUM)/bignum.expected - || exit 1
	@echo "all tests passed"

# The suite under AddressSanitizer and UBSan, as a separate build rather than a
# flag on this one: every object has to be compiled with them and the tree
# caches objects, so it cleans first. Came in with Parasol's Makefile on
# 2026-09-14, where it was a target because of its POSTMORTEM.md 15: the
# invocation had been documented and never run, and it is what catches the one
# class of defect a suite structurally cannot -- a read of freed memory is a
# crash only when the allocator happens to make it one. It leaves instrumented
# binaries in bin/; `make clean` restores a normal build.
sanitize:
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory test SANITIZE="-fsanitize=address,undefined"
	@echo "clean under -fsanitize=address,undefined"
	@echo "  bin/ is instrumented now -- 'make clean' restores a normal build"

examples: $(EXAMPLE_SOBS) $(PARASOL_EXAMPLE_SOBS)

# The library is copied, not installed one file at a time, because which files
# make it up is the library's business and a list here would go stale the way
# every other hand-kept list in this repository has.
# The bundles go beside the library rather than on any search path: nothing
# looks for an extension, because `--extension=` takes a path and a host that
# did not name one is a host that gets none. Installing them is only so that a
# path exists to name after `make install`.
#
# Parasol's dialects go in beside the library, in the same directory. Solveig's
# binaries are told that path at build time and search it, so `@include
# "text.sol"` works from anywhere; parasol does not do that yet, and saying so
# is better than half of it: PARASOL_PATH is how a @use finds an installed
# dialect, and it is one line in a profile. (Step 4 of the roadmap's plan is
# where parasol learns to look beside its own binary too.)
install: all
	@mkdir -p $(BINDIR) $(LIBDIR)
	cp $(BINARIES) $(BINDIR)
	cp lib/*.sol $(LIBDIR)
	cp $(DIALECTS) $(LIBDIR)
	cp $(EXTENSIONS) $(LIBDIR)
	@echo "installed to $(DESTDIR)$(PREFIX)"
	@echo "  export PARASOL_PATH=$(PREFIX)/lib/solum    # so a @use can find the dialects"

uninstall:
	rm -f $(patsubst $(BIN)/%,$(BINDIR)/%,$(BINARIES))
	rm -rf $(LIBDIR)

# The version comes from the header the binaries report, so a tarball cannot be
# named for a version the program inside it does not claim.
# Spelled without a capture group on purpose: make counts the parentheses
# inside $(shell ...) and a `\(` in a sed script closes it early.
VERSION = $(shell grep SOLUM_VERSION solum/include/solum/common.h | tr -d '"' | awk '{print $$3}')

# From HEAD rather than from the working tree: a tarball of uncommitted work is
# a tarball nobody can get back to.
#
# Into `dist/` rather than the root, which is where they used to land and where
# four of them accumulated before anyone minded. `clean` does not take it: a
# tarball is a release artefact and not an intermediate one, and `make clean`
# before a rebuild should not delete the thing you were about to publish.
dist:
	@mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=solveig-$(VERSION)/ \
	    -o $(DIST)/solveig-$(VERSION).tar.gz HEAD
	@echo "$(DIST)/solveig-$(VERSION).tar.gz"

clean:
	rm -rf $(BUILD) $(BIN)
	rm -f $(PARASOL_EXAMPLE_SOLS) $(PARASOL_EXAMPLE_SOLS:.sol=.sol.map) $(PARASOL_EXAMPLE_SOBS)
	rm -f $(EMBER)/emberc.sol $(EMBER)/emberc.sol.map $(EMBER)/emberc.sob
	rm -f $(EMBER_ASM) $(EMBER_BINS)
	rm -rf $(EMBER)/examples/*.dSYM
	rm -f $(GRAMMAR_SOLS) $(GRAMMAR_SOLS:.sol=.sol.map) $(GRAMMAR_SOBS)
	rm -f $(DIGEST)/sha256.sol $(DIGEST)/sha256.sol.map $(DIGEST)/sha256.sob
	rm -f $(LEDGER)/ledger.sol $(LEDGER)/ledger.sol.map $(LEDGER)/ledger.sob
	rm -f $(PROSE)/note.sol $(PROSE)/note.sol.map $(PROSE)/note.sob
	rm -f $(BASIC)/basic.sol $(BASIC)/basic.sol.map $(BASIC)/basic.sob
	rm -f $(BIGNUM)/bignum.sol $(BIGNUM)/bignum.sol.map \
	      $(BIGNUM)/calc.sol $(BIGNUM)/calc.sol.map $(BIGNUM)/calc.sob

-include $(LIB_OBJS:.o=.d) $(PARASOL_OBJS:.o=.d)
