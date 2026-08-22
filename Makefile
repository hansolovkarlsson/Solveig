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
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(BIN)/solas: solas/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(BIN)/solvm: solum/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(BIN)/solis: solis/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(BIN)/solid: solid/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(LIB): $(LIB_OBJS)
	@mkdir -p $(@D)
	$(AR) rcs $@ $^

$(BUILD)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) -MMD -MP -c $< -o $@

$(BUILD)/tests/%: tests/%.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

# The binaries too: test_cli runs them as a shell would, a `main` not being
# something the library holds.
test: $(BINARIES) $(TEST_BINS)
	@for t in $(TEST_BINS); do echo "-- $$t"; $$t || exit 1; done
	@echo "all tests passed"

clean:
	rm -rf $(BUILD) $(BIN)

-include $(LIB_OBJS:.o=.d)
