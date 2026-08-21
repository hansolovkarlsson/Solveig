/* A point in time: a value, held as nanoseconds since the epoch, always UTC.
 *
 * Tested against instants somebody knows rather than against `system:time`,
 * which is why `time:fromSeconds` exists at all -- without it the only instants
 * a program can have are the current one and a file's, and neither can be
 * checked against an expected answer. */
#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "solas/compiler.h"
#include "solum/gc.h"
#include "solum/vm.h"

static SolResult run(SolVM *vm, SolChunk *chunk, const char *source)
{
    sol_chunk_init(chunk);
    if (!sol_compile(source, chunk)) return SOL_COMPILE_ERROR;
    return sol_vm_run(vm, chunk);
}

static SolValue global(SolVM *vm, const char *name)
{
    SolSlot *slot = sol_object_lookup(vm->root, name);
    return slot ? slot->value : SOL_NIL_VAL;
}

static bool is_text(SolValue value, const char *expected)
{
    if (!SOL_IS_STRING(value)) return false;
    const SolString *s = SOL_AS_STRING(value);
    return s->length == (int)strlen(expected) &&
           memcmp(s->chars, expected, (size_t)s->length) == 0;
}

/* 946684800 is 2000-01-01T00:00:00Z, and it was a Saturday. */
static void test_a_date_somebody_knows(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "y2k := time:fromSeconds(946684800.0)."
        "shown := y2k:asString."
        "y := y2k:year. m := y2k:month. d := y2k:day."
        "h := y2k:hour. mi := y2k:minute. s := y2k:second."
        "w := y2k:weekday."
        "back := y2k:asSeconds.") == SOL_OK);

    assert(is_text(global(&vm, "shown"), "2000-01-01T00:00:00Z"));
    assert(SOL_AS_INT(global(&vm, "y")) == 2000);
    assert(SOL_AS_INT(global(&vm, "m")) == 1);      /* January is #1, not #0 */
    assert(SOL_AS_INT(global(&vm, "d")) == 1);
    assert(SOL_AS_INT(global(&vm, "h")) == 0);
    assert(SOL_AS_INT(global(&vm, "mi")) == 0);
    assert(SOL_AS_INT(global(&vm, "s")) == 0);
    assert(SOL_AS_INT(global(&vm, "w")) == 6);      /* Monday is #1, so Saturday */
    assert(SOL_AS_FLOAT(global(&vm, "back")) == 946684800.0);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a known instant reads back as the date it is\n");
}

/* Before the epoch the seconds are negative, and C division truncates towards
   zero -- so the split into calendar parts has to floor, or an instant a
   fraction before midnight lands on the wrong day. */
static void test_before_the_epoch(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "epoch := time:fromSeconds(0.0)."
        "atEpoch := epoch:asString."
        "before := time:fromSeconds(0.0:sub(86400.0)):asString."
        /* half a second before the epoch is still 1969, not 1970 */
        "sliver := time:fromSeconds(0.0:sub(0.5))."
        "year := sliver:year. day := sliver:day.") == SOL_OK);

    assert(is_text(global(&vm, "atEpoch"), "1970-01-01T00:00:00Z"));
    assert(is_text(global(&vm, "before"), "1969-12-31T00:00:00Z"));
    assert(SOL_AS_INT(global(&vm, "year")) == 1969);
    assert(SOL_AS_INT(global(&vm, "day")) == 31);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  an instant before the epoch counts backwards properly\n");
}

/* A value: two of the same instant are the same time, and equality is exact
   because the nanoseconds are integers rather than a float of seconds. */
static void test_a_time_is_a_value(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := time:fromSeconds(946684800.0)."
        "b := time:fromSeconds(946684800.0)."
        "same := a:equals(b). differ := a:notEquals(b)."
        "kind := a:isKindOf(time). rooted := a:isKindOf(object)."
        "notNumber := a:isKindOf(integer). there := a:notNil."
        /* and therefore a dictionary key like any other value */
        "d := dictionary:new. d:atPut(a, \"kept\")."
        "found := d:at(b)."
        "one := d:size.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "same")));
    assert(SOL_AS_BOOL(global(&vm, "differ")) == false);
    assert(SOL_AS_BOOL(global(&vm, "kind")));
    assert(SOL_AS_BOOL(global(&vm, "rooted")));
    assert(SOL_AS_BOOL(global(&vm, "notNumber")) == false);
    assert(SOL_AS_BOOL(global(&vm, "there")));
    assert(is_text(global(&vm, "found"), "kept"));
    assert(SOL_AS_INT(global(&vm, "one")) == 1);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a time is a value, so it compares and keys by its instant\n");
}

static void test_measuring_and_moving(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "start := time:fromSeconds(1000.0)."
        "later := start:plusSeconds(3600.0)."
        "gap := later:secondsSince(start)."
        "backwards := start:secondsSince(later)."      /* negative, not an error */
        "fraction := start:plusSeconds(0.25):secondsSince(start)."
        "before := start:lessThan(later). after := later:greaterThan(start)."
        "notAfter := start:lessOrEqual(start)."
        "notBefore := start:greaterOrEqual(start).") == SOL_OK);

    assert(SOL_AS_FLOAT(global(&vm, "gap")) == 3600.0);
    assert(SOL_AS_FLOAT(global(&vm, "backwards")) == -3600.0);
    assert(SOL_AS_FLOAT(global(&vm, "fraction")) == 0.25);
    assert(SOL_AS_BOOL(global(&vm, "before")));
    assert(SOL_AS_BOOL(global(&vm, "after")));
    assert(SOL_AS_BOOL(global(&vm, "notAfter")));
    assert(SOL_AS_BOOL(global(&vm, "notBefore")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  measuring a gap and moving along by one\n");
}

static void test_formatting(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "y2k := time:fromSeconds(946684800.0)."
        "iso := y2k:asString."
        "date := y2k:asString(\"%Y-%m-%d\")."
        "clock := y2k:asString(\"%H:%M:%S\")."
        "plain := y2k:asString(\"nothing to replace\").") == SOL_OK);

    assert(is_text(global(&vm, "iso"), "2000-01-01T00:00:00Z"));
    assert(is_text(global(&vm, "date"), "2000-01-01"));
    assert(is_text(global(&vm, "clock"), "00:00:00"));
    assert(is_text(global(&vm, "plain"), "nothing to replace"));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  ISO-8601 by default, and strftime when asked\n");
}

/* `system:time` is a calendar and `system:clock` is a stopwatch. Only the first
   knows what year it is; only the second is safe to subtract for a duration. */
static void test_now_and_a_files_time(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "now := system:time."
        "sane := now:year:greaterThan(#2020):and({ now:year:lessThan(#2200) })."
        "isTime := now:isKindOf(time)."
        /* it moves forward, or at least never backward */
        "later := system:time."
        "ordered := later:greaterOrEqual(now)."
        /* a file has one too, which is what fileSize was waiting for */
        "stamp := system:modifiedAt(\"examples/time.sol\")."
        "real := stamp:year:greaterThan(#2000).") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "sane")));
    assert(SOL_AS_BOOL(global(&vm, "isTime")));
    assert(SOL_AS_BOOL(global(&vm, "ordered")));
    assert(SOL_AS_BOOL(global(&vm, "real")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  now, and when a file was last written\n");
}

static void test_what_a_time_refuses(void)
{
    static const char *refused[] = {
        "time:new.",                              /* nothing to construct */
        "time:fromSeconds(#1).",                  /* strict: a float, or asFloat */
        "time:fromSeconds(\"now\").",
        "time:fromSeconds.",
        "system:time:plusSeconds(#1).",
        "system:time:secondsSince(#1).",          /* a time, not a number */
        "system:time:lessThan(#1).",
        "system:time:asString(#1).",
        "system:time(#1).",
        "system:modifiedAt(\"no-such-file\").",
        "time:fromSeconds(1.0e300).",             /* beyond any calendar */
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM vm; sol_vm_init(&vm);
        SolChunk chunk;
        assert(run(&vm, &chunk, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&chunk); sol_vm_free(&vm);
    }
    printf("  a time refuses what it cannot mean\n");
}

/* ---- reading one back --------------------------------------------------- *
 *
 * `asTime` on `string`, beside `asInteger`, `asFloat` and `asSymbol`, which is
 * where a conversion *from* text has always lived here.
 */
static void test_parsing_iso_8601(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "full := \"2000-01-01T00:00:00Z\":asTime:asString."
        "dateOnly := \"2000-01-01\":asTime:asString."       /* midnight */
        "noZone := \"2026-08-20T09:14:02\":asTime:asString."  /* no zone is UTC */
        "spaced := \"2026-08-20 09:14:02\":asTime:asString."  /* T or a space */
        /* an offset is arithmetic, and is taken off */
        "east := \"2026-08-20T09:14:02+01:00\":asTime:asString."
        "west := \"2026-08-20T09:14:02-05:00\":asTime:asString."
        "compact := \"2026-08-20T09:14:02+0100\":asTime:asString."
        /* a fraction of a second survives the parse */
        "fraction := \"2026-08-20T09:14:02.25Z\":asTime:secondsSince("
        "    \"2026-08-20T09:14:02Z\":asTime).") == SOL_OK);

    assert(is_text(global(&vm, "full"), "2000-01-01T00:00:00Z"));
    assert(is_text(global(&vm, "dateOnly"), "2000-01-01T00:00:00Z"));
    assert(is_text(global(&vm, "noZone"), "2026-08-20T09:14:02Z"));
    assert(is_text(global(&vm, "spaced"), "2026-08-20T09:14:02Z"));
    assert(is_text(global(&vm, "east"), "2026-08-20T08:14:02Z"));
    assert(is_text(global(&vm, "west"), "2026-08-20T14:14:02Z"));
    assert(is_text(global(&vm, "compact"), "2026-08-20T08:14:02Z"));
    assert(SOL_AS_FLOAT(global(&vm, "fraction")) == 0.25);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  ISO-8601 reads back, offsets included\n");
}

/* The round trip is the promise worth making: what `asString` writes, `asTime`
   reads. Only to the second, because that is all `asString` writes. */
static void test_the_round_trip(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "t := time:fromSeconds(1755000000.0)."
        "same := t:asString:asTime:equals(t)."
        /* and through the numbers, where a fraction does survive */
        "u := time:fromSeconds(1755000000.25)."
        "exact := u:asSeconds:equals(1755000000.25)."
        "back := time:fromSeconds(u:asSeconds):equals(u)."
        /* before the epoch too, where the arithmetic has to floor */
        "old := time:fromSeconds(0.0:sub(1.5))."
        "shown := old:asString."
        "oldBack := old:asSeconds.") == SOL_OK);

    assert(SOL_AS_BOOL(global(&vm, "same")));
    assert(SOL_AS_BOOL(global(&vm, "exact")));
    assert(SOL_AS_BOOL(global(&vm, "back")));
    assert(is_text(global(&vm, "shown"), "1969-12-31T23:59:59Z"));
    assert(SOL_AS_FLOAT(global(&vm, "oldBack")) == -1.5);

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  what asString writes, asTime reads\n");
}

/* A date that does not exist is refused rather than rolled into the next month,
   which is what almost every date parser does quietly. */
static void test_a_date_that_does_not_exist(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    /* The leap year is the pair worth testing: one of these is a real day. */
    assert(run(&vm, &chunk, "leap := \"2024-02-29\":asTime:asString.") == SOL_OK);
    assert(is_text(global(&vm, "leap"), "2024-02-29T00:00:00Z"));
    sol_chunk_free(&chunk); sol_vm_free(&vm);

    static const char *refused[] = {
        "\"2026-02-29\":asTime.",      /* 2026 is not a leap year */
        "\"2026-02-30\":asTime.",
        "\"2026-04-31\":asTime.",      /* April has thirty days */
        "\"2026-13-01\":asTime.",
        "\"2026-00-01\":asTime.",
        "\"2026-01-00\":asTime.",
        "\"2026-08-20T24:00:00\":asTime.",
        "\"2026-08-20T09:14:02+99:00\":asTime.",
        "\"not a time\":asTime.",
        "\"2026-08-20T09:14\":asTime.",          /* seconds are not optional */
        "\"2026-08-20T09:14:02 extra\":asTime.", /* strict to the end */
        "\"\":asTime.",
        "\"2026-08-20\":asTime(#1).",
        "\"nope\":asTime(\"%Y-%m-%d\").",
    };

    for (size_t i = 0; i < sizeof(refused) / sizeof(refused[0]); i++) {
        SolVM v; sol_vm_init(&v);
        SolChunk c;
        assert(run(&v, &c, refused[i]) == SOL_RUNTIME_ERROR);
        sol_chunk_free(&c); sol_vm_free(&v);
    }
    printf("  February the 30th is refused, not rolled into March\n");
}

/* With a format, the C library reads it -- the same alphabet `asString` writes
   in, so the two are counterparts rather than two half-learned languages. */
static void test_parsing_with_a_format(void)
{
    SolVM vm; sol_vm_init(&vm);
    SolChunk chunk;

    assert(run(&vm, &chunk,
        "a := \"20/08/2026\":asTime(\"%d/%m/%Y\"):asString."
        "b := \"2026 August 20\":asTime(\"%Y %B %d\"):asString."
        /* a format naming no day means the first of the month */
        "c := \"2026-08\":asTime(\"%Y-%m\"):asString."
        /* and what asString wrote, a matching format reads */
        "t := time:fromSeconds(946684800.0)."
        "round := t:asString(\"%Y-%m-%d %H:%M:%S\"):asTime(\"%Y-%m-%d %H:%M:%S\")."
        "same := round:equals(t).") == SOL_OK);

    assert(is_text(global(&vm, "a"), "2026-08-20T00:00:00Z"));
    assert(is_text(global(&vm, "b"), "2026-08-20T00:00:00Z"));
    assert(is_text(global(&vm, "c"), "2026-08-01T00:00:00Z"));
    assert(SOL_AS_BOOL(global(&vm, "same")));

    sol_chunk_free(&chunk); sol_vm_free(&vm);
    printf("  a format reads what the same format writes\n");
}

int main(void)
{
    test_a_date_somebody_knows();
    test_before_the_epoch();
    test_a_time_is_a_value();
    test_measuring_and_moving();
    test_formatting();
    test_now_and_a_files_time();
    test_what_a_time_refuses();
    test_parsing_iso_8601();
    test_the_round_trip();
    test_a_date_that_does_not_exist();
    test_parsing_with_a_format();
    printf("test_time: ok\n");
    return 0;
}
