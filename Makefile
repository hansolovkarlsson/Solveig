# Solum -- build for all three components.
#
#   make            build bin/solas, bin/solvm, bin/solis, bin/solid
#   make test       build and run the test suite
#   make embed      build bin/solhost -- see solum/include/solum/embed.h
#   make clean      remove build artefacts

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -g
INCLUDES = -Isolum/include -Isolas/include -Isolis/include -Isolid/include
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

BUILD = build
BIN   = bin

LIB_SRCS  = $(wildcard solum/src/*.c) $(wildcard solas/src/*.c) \
            $(wildcard solis/src/*.c) $(wildcard solid/src/*.c)
LIB_OBJS  = $(LIB_SRCS:%.c=$(BUILD)/%.o)
LIB       = $(BUILD)/libsol.a

TEST_SRCS = $(wildcard tests/*.c)
TEST_BINS = $(TEST_SRCS:tests/%.c=$(BUILD)/tests/%)

BINARIES = $(BIN)/solas $(BIN)/solvm $(BIN)/solis $(BIN)/solid

.PHONY: all test embed clean
all: $(BINARIES)

# Not in `all`: it is a demonstration of the C interface rather than a program
# anybody installs. See embed/host.c and docs/embedding.md.
embed: $(BIN)/solhost

$(BIN)/solhost: embed/host.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $^ -o $@ $(LDLIBS)

$(BIN)/solas: solas/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $^ -o $@ $(LDLIBS)

$(BIN)/solvm: solum/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $^ -o $@ $(LDLIBS)

$(BIN)/solis: solis/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $^ -o $@ $(LDLIBS)

$(BIN)/solid: solid/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $^ -o $@ $(LDLIBS)

$(LIB): $(LIB_OBJS)
	@mkdir -p $(@D)
	$(AR) rcs $@ $^

$(BUILD)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/tests/%: tests/%.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(STANDARD) $(INCLUDES) $^ -o $@ $(LDLIBS)

# The one test that needs threads. Nothing else links anything, and the point of
# keeping it to one target is that a build without pthreads still gets the rest.
$(BUILD)/tests/test_threads: CFLAGS += -pthread

# The binaries too: test_cli runs them as a shell would, a `main` not being
# something the library holds.
test: $(BINARIES) $(TEST_BINS)
	@for t in $(TEST_BINS); do echo "-- $$t"; $$t || exit 1; done
	@echo "all tests passed"

clean:
	rm -rf $(BUILD) $(BIN)

-include $(LIB_OBJS:.o=.d)
