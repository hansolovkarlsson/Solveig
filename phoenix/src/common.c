/* common.c -- allocation that stops rather than returning NULL. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "phoenix/common.h"

static void out_of_memory(void)
{
    fprintf(stderr, "phoenix: out of memory\n");
    exit(70);
}

void *phx_alloc(size_t size)
{
    void *p = malloc(size);
    if (p == NULL) out_of_memory();
    return p;
}

void *phx_realloc(void *pointer, size_t size)
{
    void *p = realloc(pointer, size);
    if (p == NULL) out_of_memory();
    return p;
}

char *phx_strndup(const char *chars, size_t length)
{
    char *copy = phx_alloc(length + 1);
    memcpy(copy, chars, length);
    copy[length] = '\0';
    return copy;
}
