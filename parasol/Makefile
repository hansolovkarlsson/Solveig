# Parasol -- a compiler whose syntax arrives with the file it is compiling.
#
#   make            build ../bin/parasol, beside Solveig's four
#   make test       build and run the test suite, through the real pipeline
#   make run        compile and run examples/vectors.psol
#   make examples   every examples/*.psol, to .sol and then to .sob
#   make install    install to $(PREFIX), default /usr/local
#   make uninstall  take it back out again
#   make clean      remove build artefacts
#
# **The build needs no Solveig.** Parasol emits Solveig *source*, and source is
# text, so nothing here links against libsol.a or includes a solum header. That
# is not an accident of where the code ended up; it is the arrangement being
# tested. A front end with privileged access to the compiler it targets proves
# only that its author can write one, and the whole claim Parasol is making is
# that a dialect is something anybody can write on top of a substrate they do
# not get to change.
#
# Since 2026-09-12 that arrangement holds inside Solveig's own tree, as
# `parasol/`. The parent's `make` builds the compiler and its `make test` runs
# this suite, so a change to the substrate that breaks a dialect goes red in
# the same run. Since 2026-09-13 the compiler is written to $(SOLVEIG)/bin,
# beside the four binaries, so that one directory holds the whole toolkit.
# Nothing about the boundary moved: this Makefile still reaches Solveig only
# through the binaries under $(SOLVEIG)/bin, reading four and writing one,
# and only from `run`, `examples` and `test`, which hand them a file. The
# journal has the reasons for both the original placement and the move.

SOLVEIG ?= ..

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -g
INCLUDES = -Iparasol/include

# `-std=c11` asks for ISO C and nothing besides, and glibc takes that at its
# word. Solveig's Makefile carries the same two lines for the same reason and
# explains them at length; this is a C file like any other.
ifeq ($(shell uname -s),Darwin)
STANDARD = -D_DARWIN_C_SOURCE
else
STANDARD = -D_XOPEN_SOURCE=700
endif

# Empty by default; the sanitizers go here rather than into CFLAGS, which is
# `?=` and would lose the warning flags if it were set on the command line.
# `make sanitize` is the way to use it.
SANITIZE =

BUILD = build
# Solveig's bin/, so `clean` below removes the one file this puts there and
# never the directory: Solveig's four binaries are not this Makefile's to take.
BIN   ?= $(SOLVEIG)/bin
DIST  = dist

PREFIX ?= /usr/local
BINDIR  = $(DESTDIR)$(PREFIX)/bin
LIBDIR  = $(DESTDIR)$(PREFIX)/lib/parasol

LIB_SRCS = $(wildcard parasol/src/*.c)
LIB_OBJS = $(LIB_SRCS:%.c=$(BUILD)/%.o)
LIB      = $(BUILD)/libparasol.a

TEST_SRCS = $(wildcard tests/*.c)
TEST_BINS = $(TEST_SRCS:tests/%.c=$(BUILD)/tests/%)

# The dialect files the examples reach with @use. Listed so that changing one
# rebuilds every example, which a per-example dependency could not do without
# reading the headers to find out which uses what.
DIALECTS = $(wildcard lib/*.psol)

EXAMPLE_SRCS = $(wildcard examples/*.psol)
EXAMPLE_SOLS = $(EXAMPLE_SRCS:.psol=.sol)
EXAMPLE_SOBS = $(EXAMPLE_SRCS:.psol=.sob)

# programs/ember -- a compiler written in Parasol, and the only customer any of
# this has. Built and run by `make test`, because a language with no program
# written in it has never been tested by anything but its own examples.
EMBER      = programs/ember
EMBER_SRCS = $(wildcard $(EMBER)/examples/*.em)
EMBER_ASM  = $(EMBER_SRCS:.em=.s)
EMBER_BINS = $(EMBER_SRCS:.em=.out)

# programs/grammar -- a second customer, and a different domain: notation for
# something recursive, where ember's was notation for something flat.
GRAMMAR       = programs/grammar
GRAMMAR_SRCS  = $(wildcard $(GRAMMAR)/examples/*.psol)
GRAMMAR_SOLS  = $(GRAMMAR_SRCS:.psol=.sol)
GRAMMAR_SOBS  = $(GRAMMAR_SRCS:.psol=.sob)

# programs/digest -- a third customer, and the first for the *operator* half of
# Parasol: sixty-four rounds of shifts, rotations and masked additions, in the
# notation FIPS 180-4 writes them in.
DIGEST = programs/digest
LEDGER = programs/ledger
PROSE  = programs/prose

# programs/basic -- the sixth, and the first that is not a pass over its input:
# an interpreter has a counter that can go backwards. Its `.bas` files are data
# it reads at run time, so nothing here compiles them.
BASIC  = programs/basic

# programs/bignum -- the seventh, and the first in two modules: a library in
# one dialect and a driver in another, the driver reaching the library's
# *generated* source with @include. So calc.sol depends on bignum.sol, which
# is the first time this file has had to order two Parasol modules.
BIGNUM = programs/bignum

.PHONY: all test sanitize run examples ember grammar digest ledger prose basic \
        bignum check install uninstall dist clean

# Without this, make treats a generated .sol as an intermediate and deletes it
# after the .sob is built -- taking the map with it. Both are the artefacts
# somebody reaches for when the generated code is what they need to read.
.SECONDARY: $(EXAMPLE_SOLS) $(EMBER)/emberc.sol $(EMBER)/emberc.sob $(EMBER_ASM) \
            $(GRAMMAR_SOLS) $(DIGEST)/sha256.sol $(LEDGER)/ledger.sol \
            $(PROSE)/note.sol $(BASIC)/basic.sol $(BIGNUM)/bignum.sol \
            $(BIGNUM)/calc.sol

all: $(BIN)/parasol

$(BIN)/parasol: parasol/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(INCLUDES) $< $(LIB) -o $@

$(LIB): $(LIB_OBJS)
	@mkdir -p $(@D)
	ar rcs $@ $^

$(BUILD)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/tests/%: tests/%.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(SANITIZE) $(STANDARD) $(INCLUDES) $< $(LIB) -o $@

# Said once, here, because a missing Solveig produces three different unhelpful
# errors depending on which target reached it first. The minimum-version test
# went with the move into Solveig's tree: the parent is by construction the
# version this speaks to, and a checkout pointed at by SOLVEIG= is the caller's
# own affair. PARASOL_SOLVEIG_MINIMUM in common.h still records the language
# level, for anybody building against a Solveig that is not the parent.
check:
	@test -x "$(SOLVEIG)/bin/solas" || \
	    { echo "parasol: $(SOLVEIG) has not been built -- no bin/solas."; \
	      echo "      make -C $(SOLVEIG)"; exit 1; }

# The map is written every time rather than on request. It costs a file and it
# is the thing that is never there when it is wanted.
examples/%.sol: examples/%.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

examples/%.sob: examples/%.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

examples: $(EXAMPLE_SOLS) $(EXAMPLE_SOBS)

$(EMBER)/emberc.sol: $(EMBER)/emberc.psol $(EMBER)/asm.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(EMBER)/emberc.sob: $(EMBER)/emberc.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

$(EMBER)/examples/%.s: $(EMBER)/examples/%.em $(EMBER)/emberc.sob | check
	@$(SOLVEIG)/bin/solvm $(EMBER)/emberc.sob $< > $@

$(EMBER)/examples/%.out: $(EMBER)/examples/%.s
	@$(CC) $< -o $@

# The whole stack, in one target: .psol to .sol to .sob, then a .em through that
# to assembly, then cc. Five programs and two languages to print a prime.
ember: $(EMBER_BINS)
	@for b in $(EMBER_BINS); do echo "-- $$b"; $$b; done

$(GRAMMAR)/examples/%.sol: $(GRAMMAR)/examples/%.psol $(GRAMMAR)/peg.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(GRAMMAR)/examples/%.sob: $(GRAMMAR)/examples/%.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

grammar: $(GRAMMAR_SOBS)
	@for g in $(GRAMMAR_SOBS); do echo "-- $$g"; $(SOLVEIG)/bin/solvm $$g; done

$(DIGEST)/sha256.sol: $(DIGEST)/sha256.psol $(DIGEST)/sha2.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(DIGEST)/sha256.sob: $(DIGEST)/sha256.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

# With no arguments it hashes the vectors it carries, which is the check; with a
# file it is the tool. The expected digests are the ones printed in FIPS 180-4
# and the ones `shasum -a 256` gives, which agreed before this was committed.
digest: $(DIGEST)/sha256.sob
	@$(SOLVEIG)/bin/solvm $(DIGEST)/sha256.sob

run: examples/vectors.sob
	@$(SOLVEIG)/bin/solvm examples/vectors.sob

# The examples are compiled *and run* by the suite, all the way down to a `.sob`
# that SolVM executes. A front end that emits text can be wrong in a way no unit
# test sees -- valid-looking Solveig that Solveig rejects, or accepts and reads
# differently -- and the only witness to that is the real compiler.
test: $(BIN)/parasol $(TEST_BINS) $(EXAMPLE_SOBS) $(EMBER_BINS) $(GRAMMAR_SOBS) \
      $(DIGEST)/sha256.sob $(LEDGER)/ledger.sob $(PROSE)/note.sob \
      $(BASIC)/basic.sob $(BIGNUM)/calc.sob
	@for t in $(TEST_BINS); do echo "-- $$t"; $$t || exit 1; done
	@for e in $(EXAMPLE_SOBS); do echo "-- $$e"; \
	    $(SOLVEIG)/bin/solvm $$e > /dev/null || exit 1; done
	@for b in $(EMBER_BINS); do echo "-- $$b"; \
	    $$b | diff -u $${b%.out}.expected - || exit 1; done
	@for g in $(GRAMMAR_SOBS); do echo "-- $$g"; \
	    $(SOLVEIG)/bin/solvm $$g | diff -u $${g%.sob}.expected - || exit 1; done
	@echo "-- $(DIGEST)/sha256.sob"
	@$(SOLVEIG)/bin/solvm $(DIGEST)/sha256.sob \
	    | diff -u $(DIGEST)/sha256.expected - || exit 1
	@echo "-- $(LEDGER)/ledger.sob"
	@$(SOLVEIG)/bin/solvm $(LEDGER)/ledger.sob \
	    | diff -u $(LEDGER)/ledger.expected - || exit 1
	@echo "-- $(PROSE)/note.sob"
	@$(SOLVEIG)/bin/solvm $(PROSE)/note.sob \
	    | diff -u $(PROSE)/prose.expected - || exit 1
	@echo "-- $(BASIC)/basic.sob"
	@{ $(SOLVEIG)/bin/solvm $(BASIC)/basic.sob $(BASIC)/examples/fizzbuzz.bas; \
	   $(SOLVEIG)/bin/solvm $(BASIC)/basic.sob $(BASIC)/examples/primes.bas; \
	   printf 'Ada\n36\n' \
	     | $(SOLVEIG)/bin/solvm $(BASIC)/basic.sob $(BASIC)/examples/greet.bas; \
	 } | diff -u $(BASIC)/basic.expected - || exit 1
	@echo "-- $(BIGNUM)/calc.sob"
	@$(SOLVEIG)/bin/solvm $(BIGNUM)/calc.sob \
	    | diff -u $(BIGNUM)/bignum.expected - || exit 1
	@echo "all tests passed"

# The suite under AddressSanitizer and UBSan, which is a separate build rather
# than a flag on this one: every object has to be compiled with them and the
# tree caches objects, so this cleans first.
#
# **It is a target and not a comment because of POSTMORTEM.md 15.** The
# invocation had been documented here since the first commit, had never been
# run, and is what catches the one class of defect this suite structurally
# cannot: a read of freed memory is a crash only when the allocator happens to
# make it one, so `test_use` can hold the exact shape of the bug and pass.
sanitize:
	@$(MAKE) --no-print-directory clean
	@$(MAKE) --no-print-directory test SANITIZE="-fsanitize=address,undefined"
	@echo "clean under -fsanitize=address,undefined"
	@echo "  $(BIN)/parasol is instrumented now -- 'make clean' restores a normal build"

$(LEDGER)/ledger.sol: $(LEDGER)/ledger.psol $(LEDGER)/money.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(LEDGER)/ledger.sob: $(LEDGER)/ledger.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

# The figures it prints were produced independently, in exact decimal, and are
# in ledger.expected. A program that verifies itself verifies nothing.
ledger: $(LEDGER)/ledger.sob
	@$(SOLVEIG)/bin/solvm $(LEDGER)/ledger.sob

$(PROSE)/note.sol: $(PROSE)/note.psol $(PROSE)/prose.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(PROSE)/note.sob: $(PROSE)/note.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

# The document is the program. prose.expected is derived from note.psol by hand
# rather than captured from a run -- see README.md.
prose: $(PROSE)/note.sob
	@$(SOLVEIG)/bin/solvm $(PROSE)/note.sob

$(BASIC)/basic.sol: $(BASIC)/basic.psol $(BASIC)/interp.psol $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(BASIC)/basic.sob: $(BASIC)/basic.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

# With a file it runs it; with none it is a prompt. basic.expected is worked out
# from the three `.bas` files by hand and not captured from a run.
basic: $(BASIC)/basic.sob
	@$(SOLVEIG)/bin/solvm $(BASIC)/basic.sob $(BASIC)/examples/fizzbuzz.bas

# Two Parasol modules, and solas sees both: calc.sol includes bignum.sol, so the
# .sob depends on the generated library as well as on the generated driver.
$(BIGNUM)/bignum.sol: $(BIGNUM)/bignum.psol $(BIGNUM)/limbs.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(BIGNUM)/calc.sol: $(BIGNUM)/calc.psol $(DIALECTS) $(BIN)/parasol
	@$(BIN)/parasol --map $< -o $@

$(BIGNUM)/calc.sob: $(BIGNUM)/calc.sol $(BIGNUM)/bignum.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

# Every answer it prints was produced by bc first, and is in bignum.expected.
bignum: $(BIGNUM)/calc.sob
	@$(SOLVEIG)/bin/solvm $(BIGNUM)/calc.sob

# The dialects go in beside the binary, and nothing looks for them there.
#
# Solveig's binaries are told their library path at build time and search it, so
# `@include "text.sol"` works from anywhere. Parasol does not do that yet, and
# saying so is better than half of it: PARASOL_PATH is how a @use finds an
# installed dialect, and it is one line in a profile.
install: all
	@mkdir -p $(BINDIR) $(LIBDIR)
	cp $(BIN)/parasol $(BINDIR)
	cp $(DIALECTS) $(LIBDIR)
	@echo "installed to $(DESTDIR)$(PREFIX)"
	@echo "  export PARASOL_PATH=$(PREFIX)/lib/parasol    # so @use can find these"

uninstall:
	rm -f $(BINDIR)/parasol
	rm -rf $(LIBDIR)

# From HEAD rather than the working tree: a tarball of uncommitted work is a
# tarball nobody can get back to.
VERSION = $(shell grep PARASOL_VERSION parasol/include/parasol/common.h \
            | head -1 | tr -d '"' | awk '{print $$3}')

dist:
	@mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=parasol-$(VERSION)/ \
	    -o $(DIST)/parasol-$(VERSION).tar.gz HEAD
	@echo "$(DIST)/parasol-$(VERSION).tar.gz"

clean:
	rm -rf $(BUILD) $(BIN)/parasol.dSYM
	rm -f $(BIN)/parasol
	rm -f $(EXAMPLE_SOLS) $(EXAMPLE_SOLS:.sol=.sol.map) $(EXAMPLE_SOBS)
	rm -f $(EMBER)/emberc.sol $(EMBER)/emberc.sol.map $(EMBER)/emberc.sob
	rm -f $(EMBER_ASM) $(EMBER_BINS)
	rm -rf $(EMBER)/examples/*.dSYM
	rm -f $(GRAMMAR_SOLS) $(GRAMMAR_SOLS:.sol=.sol.map) $(GRAMMAR_SOBS)
	rm -f $(LEDGER)/ledger.sol $(LEDGER)/ledger.sol.map $(LEDGER)/ledger.sob
	rm -f $(BASIC)/basic.sol $(BASIC)/basic.sol.map $(BASIC)/basic.sob
	rm -f $(PROSE)/note.sol $(PROSE)/note.sol.map $(PROSE)/note.sob
	rm -f $(BIGNUM)/bignum.sol $(BIGNUM)/bignum.sol.map
	rm -f $(BIGNUM)/calc.sol $(BIGNUM)/calc.sol.map $(BIGNUM)/calc.sob

-include $(LIB_OBJS:.o=.d)
