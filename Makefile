# Phoenix -- a compiler whose syntax arrives with the file it is compiling.
#
#   make            build bin/phoenix
#   make test       build and run the test suite, through the real pipeline
#   make run        compile and run examples/vectors.phx
#   make examples   every examples/*.phx, to .sol and then to .sob
#   make install    install to $(PREFIX), default /usr/local
#   make uninstall  take it back out again
#   make clean      remove build artefacts
#
# **The build needs no Solveig.** Phoenix emits Solveig *source*, and source is
# text, so nothing here links against libsol.a or includes a solum header. That
# is not an accident of where the code ended up; it is the arrangement being
# tested. A front end with privileged access to the compiler it targets proves
# only that its author can write one, and the whole claim Phoenix is making is
# that a dialect is something anybody can write on top of a substrate they do
# not get to change.
#
# So Solveig is checked for by `run`, `examples` and `test`, which hand it a
# file, and by nothing else.

SOLVEIG ?= ../Solveig

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -g
INCLUDES = -Iphoenix/include

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
#
#   make clean && make test SANITIZE="-fsanitize=address,undefined"
SANITIZE =

BUILD = build
BIN   = bin
DIST  = dist

PREFIX ?= /usr/local
BINDIR  = $(DESTDIR)$(PREFIX)/bin
LIBDIR  = $(DESTDIR)$(PREFIX)/lib/phoenix

LIB_SRCS = $(wildcard phoenix/src/*.c)
LIB_OBJS = $(LIB_SRCS:%.c=$(BUILD)/%.o)
LIB      = $(BUILD)/libphoenix.a

TEST_SRCS = $(wildcard tests/*.c)
TEST_BINS = $(TEST_SRCS:tests/%.c=$(BUILD)/tests/%)

# The dialect files the examples reach with @use. Listed so that changing one
# rebuilds every example, which a per-example dependency could not do without
# reading the headers to find out which uses what.
DIALECTS = $(wildcard lib/*.phx)

EXAMPLE_SRCS = $(wildcard examples/*.phx)
EXAMPLE_SOLS = $(EXAMPLE_SRCS:.phx=.sol)
EXAMPLE_SOBS = $(EXAMPLE_SRCS:.phx=.sob)

# programs/ember -- a compiler written in Phoenix, and the only customer any of
# this has. Built and run by `make test`, because a language with no program
# written in it has never been tested by anything but its own examples.
EMBER      = programs/ember
EMBER_SRCS = $(wildcard $(EMBER)/examples/*.em)
EMBER_ASM  = $(EMBER_SRCS:.em=.s)
EMBER_BINS = $(EMBER_SRCS:.em=.out)

# programs/grammar -- a second customer, and a different domain: notation for
# something recursive, where ember's was notation for something flat.
GRAMMAR       = programs/grammar
GRAMMAR_SRCS  = $(wildcard $(GRAMMAR)/examples/*.phx)
GRAMMAR_SOLS  = $(GRAMMAR_SRCS:.phx=.sol)
GRAMMAR_SOBS  = $(GRAMMAR_SRCS:.phx=.sob)

# programs/digest -- a third customer, and the first for the *operator* half of
# Phoenix: sixty-four rounds of shifts, rotations and masked additions, in the
# notation FIPS 180-4 writes them in.
DIGEST = programs/digest

# The Solveig a `.sol` is about to be handed to, read from the same header its
# binaries report their version out of. Checked rather than assumed because the
# failure it prevents is unhelpful: `solas` not being there gives a shell error
# about a missing file and says nothing about which file or why.
SOLVEIG_MINIMUM = 0.40.0
SOLVEIG_VERSION = $(shell grep SOLUM_VERSION \
                    $(SOLVEIG)/solum/include/solum/common.h 2>/dev/null \
                    | tr -d '"' | awk '{print $$3}')

.PHONY: all test run examples ember grammar digest check install uninstall dist clean

# Without this, make treats a generated .sol as an intermediate and deletes it
# after the .sob is built -- taking the map with it. Both are the artefacts
# somebody reaches for when the generated code is what they need to read.
.SECONDARY: $(EXAMPLE_SOLS) $(EMBER)/emberc.sol $(EMBER)/emberc.sob $(EMBER_ASM) \
            $(GRAMMAR_SOLS) $(DIGEST)/sha256.sol

all: $(BIN)/phoenix

$(BIN)/phoenix: phoenix/cmd/main.c $(LIB)
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
# errors depending on which target reached it first.
check:
	@test -n "$(SOLVEIG_VERSION)" || \
	    { echo "phoenix: $(SOLVEIG) is not a Solveig checkout."; \
	      echo "      make SOLVEIG=/path/to/Solveig"; exit 1; }
	@test -x "$(SOLVEIG)/bin/solas" || \
	    { echo "phoenix: $(SOLVEIG) has not been built -- no bin/solas."; \
	      echo "      make -C $(SOLVEIG)"; exit 1; }
	@echo "$(SOLVEIG_VERSION) $(SOLVEIG_MINIMUM)" \
	    | awk '{ split($$1, a, "."); split($$2, b, "."); \
	             exit !(a[1] > b[1] || (a[1] == b[1] && a[2] >= b[2])) }' || \
	    { echo "phoenix: found Solveig $(SOLVEIG_VERSION) under $(SOLVEIG),"; \
	      echo "  and this needs $(SOLVEIG_MINIMUM) or later."; \
	      echo "  Update that checkout, or point SOLVEIG at a newer one."; exit 1; }

# The map is written every time rather than on request. It costs a file and it
# is the thing that is never there when it is wanted.
examples/%.sol: examples/%.phx $(DIALECTS) $(BIN)/phoenix
	@$(BIN)/phoenix --map $< -o $@

examples/%.sob: examples/%.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

examples: $(EXAMPLE_SOLS) $(EXAMPLE_SOBS)

$(EMBER)/emberc.sol: $(EMBER)/emberc.phx $(EMBER)/asm.phx $(DIALECTS) $(BIN)/phoenix
	@$(BIN)/phoenix --map $< -o $@

$(EMBER)/emberc.sob: $(EMBER)/emberc.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

$(EMBER)/examples/%.s: $(EMBER)/examples/%.em $(EMBER)/emberc.sob | check
	@$(SOLVEIG)/bin/solvm $(EMBER)/emberc.sob $< > $@

$(EMBER)/examples/%.out: $(EMBER)/examples/%.s
	@$(CC) $< -o $@

# The whole stack, in one target: .phx to .sol to .sob, then a .em through that
# to assembly, then cc. Five programs and two languages to print a prime.
ember: $(EMBER_BINS)
	@for b in $(EMBER_BINS); do echo "-- $$b"; $$b; done

$(GRAMMAR)/examples/%.sol: $(GRAMMAR)/examples/%.phx $(GRAMMAR)/peg.phx $(DIALECTS) $(BIN)/phoenix
	@$(BIN)/phoenix --map $< -o $@

$(GRAMMAR)/examples/%.sob: $(GRAMMAR)/examples/%.sol | check
	@$(SOLVEIG)/bin/solas $< -o $@

grammar: $(GRAMMAR_SOBS)
	@for g in $(GRAMMAR_SOBS); do echo "-- $$g"; $(SOLVEIG)/bin/solvm $$g; done

$(DIGEST)/sha256.sol: $(DIGEST)/sha256.phx $(DIGEST)/sha2.phx $(BIN)/phoenix
	@$(BIN)/phoenix --map $< -o $@

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
test: $(BIN)/phoenix $(TEST_BINS) $(EXAMPLE_SOBS) $(EMBER_BINS) $(GRAMMAR_SOBS) \
      $(DIGEST)/sha256.sob
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
	@echo "all tests passed"

# The dialects go in beside the binary, and nothing looks for them there.
#
# Solveig's binaries are told their library path at build time and search it, so
# `@include "text.sol"` works from anywhere. Phoenix does not do that yet, and
# saying so is better than half of it: PHOENIX_PATH is how a @use finds an
# installed dialect, and it is one line in a profile.
install: all
	@mkdir -p $(BINDIR) $(LIBDIR)
	cp $(BIN)/phoenix $(BINDIR)
	cp $(DIALECTS) $(LIBDIR)
	@echo "installed to $(DESTDIR)$(PREFIX)"
	@echo "  export PHOENIX_PATH=$(PREFIX)/lib/phoenix    # so @use can find these"

uninstall:
	rm -f $(BINDIR)/phoenix
	rm -rf $(LIBDIR)

# From HEAD rather than the working tree: a tarball of uncommitted work is a
# tarball nobody can get back to.
VERSION = $(shell grep PHOENIX_VERSION phoenix/include/phoenix/common.h \
            | head -1 | tr -d '"' | awk '{print $$3}')

dist:
	@mkdir -p $(DIST)
	git archive --format=tar.gz --prefix=phoenix-$(VERSION)/ \
	    -o $(DIST)/phoenix-$(VERSION).tar.gz HEAD
	@echo "$(DIST)/phoenix-$(VERSION).tar.gz"

clean:
	rm -rf $(BUILD) $(BIN)
	rm -f $(EXAMPLE_SOLS) $(EXAMPLE_SOLS:.sol=.sol.map) $(EXAMPLE_SOBS)
	rm -f $(EMBER)/emberc.sol $(EMBER)/emberc.sol.map $(EMBER)/emberc.sob
	rm -f $(EMBER_ASM) $(EMBER_BINS)
	rm -rf $(EMBER)/examples/*.dSYM
	rm -f $(GRAMMAR_SOLS) $(GRAMMAR_SOLS:.sol=.sol.map) $(GRAMMAR_SOBS)

-include $(LIB_OBJS:.o=.d)
