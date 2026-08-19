#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "solum/bytecode.h"

void sol_chunk_init(SolChunk *chunk)
{
    chunk->count = 0;
    chunk->capacity = 0;
    chunk->code = NULL;
    chunk->lines = NULL;
    sol_value_array_init(&chunk->constants);
    chunk->names.count = 0;
    chunk->names.capacity = 0;
    chunk->names.names = NULL;
}

void sol_chunk_write(SolChunk *chunk, uint8_t byte, int line)
{
    if (chunk->capacity < chunk->count + 1) {
        int capacity = chunk->capacity < 8 ? 8 : chunk->capacity * 2;
        chunk->code = realloc(chunk->code, sizeof(uint8_t) * capacity);
        chunk->lines = realloc(chunk->lines, sizeof(int) * capacity);
        if (chunk->code == NULL || chunk->lines == NULL) {
            fprintf(stderr, "solum: out of memory\n");
            exit(1);
        }
        chunk->capacity = capacity;
    }
    chunk->code[chunk->count] = byte;
    chunk->lines[chunk->count] = line;
    chunk->count++;
}

int sol_chunk_add_constant(SolChunk *chunk, SolValue value)
{
    return sol_value_array_write(&chunk->constants, value);
}

int sol_chunk_add_name(SolChunk *chunk, const char *name, int length)
{
    SolNameArray *names = &chunk->names;

    for (int i = 0; i < names->count; i++) {
        if (strlen(names->names[i]) == (size_t)length &&
            memcmp(names->names[i], name, (size_t)length) == 0) {
            return i;
        }
    }

    if (names->capacity < names->count + 1) {
        int capacity = names->capacity < 8 ? 8 : names->capacity * 2;
        names->names = realloc(names->names, sizeof(char *) * capacity);
        if (names->names == NULL) {
            fprintf(stderr, "solum: out of memory\n");
            exit(1);
        }
        names->capacity = capacity;
    }

    char *copy = malloc((size_t)length + 1);
    if (copy == NULL) {
        fprintf(stderr, "solum: out of memory\n");
        exit(1);
    }
    memcpy(copy, name, (size_t)length);
    copy[length] = '\0';

    names->names[names->count] = copy;
    return names->count++;
}

const char *sol_chunk_name(const SolChunk *chunk, int index)
{
    if (index < 0 || index >= chunk->names.count) return "?";
    return chunk->names.names[index];
}

void sol_chunk_free(SolChunk *chunk)
{
    free(chunk->code);
    free(chunk->lines);
    sol_value_array_free(&chunk->constants);
    for (int i = 0; i < chunk->names.count; i++) free(chunk->names.names[i]);
    free(chunk->names.names);
    sol_chunk_init(chunk);
}

/* ---- disassembler ---------------------------------------------------- */

static int simple_instruction(const char *name, int offset)
{
    printf("%s\n", name);
    return offset + 1;
}

static int constant_instruction(const char *name, const SolChunk *chunk, int offset)
{
    uint8_t index = chunk->code[offset + 1];
    printf("%-8s %4d '", name, index);
    sol_value_print(chunk->constants.values[index]);
    printf("'\n");
    return offset + 2;
}

static int name_instruction(const char *name, const SolChunk *chunk, int offset)
{
    uint8_t index = chunk->code[offset + 1];
    printf("%-8s %4d '%s'\n", name, index, sol_chunk_name(chunk, index));
    return offset + 2;
}

static int send_instruction(const char *name, const SolChunk *chunk, int offset)
{
    uint8_t index = chunk->code[offset + 1];
    uint8_t argc  = chunk->code[offset + 2];
    printf("%-8s %4d '%s' (%d args)\n", name, index,
           sol_chunk_name(chunk, index), argc);
    return offset + 3;
}

int sol_chunk_disassemble_instruction(const SolChunk *chunk, int offset)
{
    printf("%04d ", offset);
    if (offset > 0 && chunk->lines[offset] == chunk->lines[offset - 1]) {
        printf("   | ");
    } else {
        printf("%4d ", chunk->lines[offset]);
    }

    uint8_t instruction = chunk->code[offset];
    switch (instruction) {
    case OP_CONST:  return constant_instruction("CONST", chunk, offset);
    case OP_NIL:    return simple_instruction("NIL", offset);
    case OP_GLOBAL: return name_instruction("GLOBAL", chunk, offset);
    case OP_SET_GLOBAL: return name_instruction("SETGLOB", chunk, offset);
    case OP_SEND:   return send_instruction("SEND", chunk, offset);
    case OP_POP:    return simple_instruction("POP", offset);
    case OP_RETURN: return simple_instruction("RETURN", offset);
    case OP_HALT:   return simple_instruction("HALT", offset);
    default:
        printf("unknown opcode %d\n", instruction);
        return offset + 1;
    }
}

void sol_chunk_disassemble(const SolChunk *chunk, const char *name)
{
    printf("== %s ==\n", name);
    for (int offset = 0; offset < chunk->count; ) {
        offset = sol_chunk_disassemble_instruction(chunk, offset);
    }
}
