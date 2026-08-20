# Solum -- build for all three components.
#
#   make            build bin/solas, bin/solvm, bin/solis
#   make test       build and run the test suite
#   make clean      remove build artefacts

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Wpedantic -g
INCLUDES = -Isolum/include -Isolas/include -Isolis/include
AR      ?= ar

BUILD = build
BIN   = bin

LIB_SRCS  = $(wildcard solum/src/*.c) $(wildcard solas/src/*.c) \
            $(wildcard solis/src/*.c)
LIB_OBJS  = $(LIB_SRCS:%.c=$(BUILD)/%.o)
LIB       = $(BUILD)/libsol.a

TEST_SRCS = $(wildcard tests/*.c)
TEST_BINS = $(TEST_SRCS:tests/%.c=$(BUILD)/tests/%)

BINARIES = $(BIN)/solas $(BIN)/solvm $(BIN)/solis

.PHONY: all test clean
all: $(BINARIES)

$(BIN)/solas: solas/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(BIN)/solvm: solum/cmd/main.c $(LIB)
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(INCLUDES) $^ -o $@

$(BIN)/solis: solis/cmd/main.c $(LIB)
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

test: $(TEST_BINS)
	@for t in $(TEST_BINS); do echo "-- $$t"; $$t || exit 1; done
	@echo "all tests passed"

clean:
	rm -rf $(BUILD) $(BIN)

-include $(LIB_OBJS:.o=.d)
