# Solum -- build for all three components.
#
#   make            build bin/solas, bin/solvm, bin/solis, bin/solid
#   make test       build and run the test suite
#   make embed      build bin/solhost -- see solum/include/solum/embed.h
#   make install    install to $(PREFIX), default /usr/local
#   make uninstall  take it back out again
#   make dist       a source tarball of HEAD, named for the version
#   make clean      remove build artefacts

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

BINARIES = $(BIN)/solas $(BIN)/solvm $(BIN)/solis $(BIN)/solid

# The bundles this repository ships. Built by `all` and loaded by nobody unless
# a host asks with `--extension=`, which is the whole arrangement: the
# capability is here, and granting it is still a decision taken on a command
# line. The rule is beside the test probe's, further down.
EXTENSIONS = $(BUILD)/extensions/net.so

.PHONY: all test embed install uninstall dist clean FORCE
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
test: $(BINARIES) $(TEST_BINS) $(EXAMPLE_SOBS) $(COMPARISON_SOBS) $(EXT_PROBE) $(EXTENSIONS)
	@echo "-- conformance"
	@sh conformance/run.sh
	@for t in $(TEST_BINS); do echo "-- $$t"; $$t || exit 1; done
	@echo "all tests passed"

# The library is copied, not installed one file at a time, because which files
# make it up is the library's business and a list here would go stale the way
# every other hand-kept list in this repository has.
# The bundles go beside the library rather than on any search path: nothing
# looks for an extension, because `--extension=` takes a path and a host that
# did not name one is a host that gets none. Installing them is only so that a
# path exists to name after `make install`.
install: all
	@mkdir -p $(BINDIR) $(LIBDIR)
	cp $(BINARIES) $(BINDIR)
	cp lib/*.sol $(LIBDIR)
	cp $(EXTENSIONS) $(LIBDIR)
	@echo "installed to $(DESTDIR)$(PREFIX)"

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

-include $(LIB_OBJS:.o=.d)
