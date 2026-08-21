; log.sol -- reading an access log and reporting on it.
;
; Run with:  ./bin/solas examples/log.sol && ./bin/solvm examples/log.sob
; Or over a log of your own:  ./bin/solvm examples/log.sob path/to/access.log
;
; The other examples were written to demonstrate a feature. This one was written
; to do a job, and uses whatever the language turned out to have. Where it is
; awkward, the comment says so rather than hiding it -- that is the useful part.
;
; The format is six space-separated fields:
;
;   2026-08-20T09:14:02 GET /index.html 200 1043 12
;   time                method path      status bytes ms

; ---------------------------------------------------------------------------
; Where the log comes from
;
; `system:arguments` is an array of strings, empty when none were given. With no
; argument this writes a sample into build/ so the example runs anywhere.

sample := "2026-08-20T09:14:02 GET /index.html 200 1043 12
2026-08-20T09:14:03 GET /style.css 200 4820 4
2026-08-20T09:14:03 GET /app.js 200 88213 31
2026-08-20T09:14:07 GET /index.html 200 1043 9
2026-08-20T09:14:11 POST /api/login 200 87 240
2026-08-20T09:14:12 GET /api/user 200 412 33
2026-08-20T09:14:19 GET /favicon.ico 404 0 2
2026-08-20T09:14:22 GET /index.html 200 1043 11
2026-08-20T09:15:01 POST /api/login 401 92 198
2026-08-20T09:15:02 POST /api/login 401 92 205
2026-08-20T09:15:04 POST /api/login 401 92 1902
2026-08-20T09:15:09 GET /api/report 500 0 3011
2026-08-20T09:15:30 GET /index.html 200 1043 10
2026-08-20T09:16:00 GET /app.js 200 88213 28
2026-08-20T09:16:02 GET /favicon.ico 404 0 1
2026-08-20T09:17:44 GET /api/report 500 0 2874
2026-08-20T09:18:01 GET /index.html 200 1043 8
2026-08-20T09:18:40 GET /style.css 200 4820 5
".

path := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1) },
    { | fallback |
      fallback := "build/example-access.log".
      system:writeFile(fallback, sample).
      fallback }).

system:fileExists(path):ifFalse({
    "no such log: {}":fill([path]):display.
    system:exit(#1) }).

; ---------------------------------------------------------------------------
; One line, one object
;
; A prototype with the fields defaulted is the shape; `entry:new` delegates to
; it, and assigning gives each instance its own.

entry := object:new.
entry:time   := "".
entry:method := "".
entry:path   := "".
entry:status := #0.
entry:bytes  := #0.
entry:ms     := #0.

parse := { line | | f, e |
    f := line:split(" ").
    e := entry:new.
    e:time   := f:at(#1).
    e:method := f:at(#2).
    e:path   := f:at(#3).
    e:status := f:at(#4):asInteger.
    e:bytes  := f:at(#5):asInteger.
    e:ms     := f:at(#6):asInteger.
    e
}.

; `split` keeps every piece, so a file ending in a newline leaves an empty last
; one. That is what makes the round trip hold, and it is why this skips blanks
; rather than assuming the file is tidy.
entries := array:new.
system:readFile(path):split("\n"):do({ line |
    line:equals(""):ifFalse({ entries:add(parse:value(line)) })
}).

; ---------------------------------------------------------------------------
; Counting by key
;
; A dictionary keeps values under keys and finds them by hashing. This is the
; one thing the language did not have when this example was first written: the
; tally below was an array of pairs walked from the top, O(n) a lookup, and
; saying so here is what got `dictionary` built.
;
; Keys are values -- numbers, strings, symbols, booleans, nil -- because those
; are compared by content. An array or an object is compared by identity, so two
; that look alike would be two keys, and they are refused rather than surprising
; anybody.

counter := object:new.
counter:key   := "".
counter:count := #0.
counter:total := #0.

; `at(key, default)` is the form a counter wants: no separate "is it there?"
; before the answer.
bump := { table, key, amount | | c |
    c := table:at(key, nil).
    c:isNil:ifTrue({
        c := counter:new.
        c:key := key.
        table:atPut(key, c) }).
    c:count := c:count:add(#1).
    c:total := c:total:add(amount)
}.

byStatus := dictionary:new.
byPath   := dictionary:new.

entries:do({ e |
    bump:value(byStatus, e:status:asString, e:ms).
    bump:value(byPath, e:path, e:bytes)
}).

; `keys` and `values` answer arrays, in the table's order -- which is to say in
; no order worth relying on, so anything shown below is sorted first.

; ---------------------------------------------------------------------------
; The report

count := entries:size.
bytes := entries:inject(#0, { total, e | total:add(e:bytes) }).
slow  := entries:inject(#0, { total, e | total:add(e:ms) }).
errors := entries:select({ e | e:status:greaterOrEqual(#400) }).

"":display.
"{} requests from {}":fill([count, path]):display.
"{} distinct paths, {} distinct statuses":fill([
    byPath:keys:size, byStatus:size]):display.
"{} to {}":fill([entries:at(#1):time, entries:at(count):time]):display.
"":display.

"{} bytes served, {} on average":fill([
    bytes:asString(","),
    bytes:div(count):asString(",")]):display.

"{} ms total, {} on average, {} slowest":fill([
    slow:asString(","),
    slow:div(count),
    entries:sorted({ a, b | a:ms:greaterThan(b:ms) }):at(#1):ms]):display.

"{} of {} failed, {}%":fill([
    errors:size,
    count,
    errors:size:mul(#100):div(count)]):display.

; Ties are broken on the key, so the report is the same every run. A dictionary
; hands back its values in the table's order, which is arbitrary but not random
; -- and "arbitrary" is not good enough for something a person reads twice.
ranked := { a, b |
    a:count:equals(b:count):ifElse(
        { a:key:lessThan(b:key) },
        { a:count:greaterThan(b:count) })
}.

"":display.
"by status":display.
byStatus:values:sorted(ranked):do({ c |
    "  {} {} requests, {} ms total":fill([
        c:key:asString("<5"), c:count:asString("3"), c:total:asString(",5")]):display
}).

"":display.
"busiest paths":display.
byPath:values:sorted(ranked):first(#5):do({ c |
    "  {} {} requests, {} bytes":fill([
        c:key:asString("<14"), c:count:asString("3"), c:total:asString(",8")]):display
}).

"":display.
"slowest requests":display.
entries:sorted({ a, b |
    a:ms:equals(b:ms):ifElse({ a:path:lessThan(b:path) }, { a:ms:greaterThan(b:ms) })
}):first(#3):do({ e |
    "  {} ms  {} {}":fill([
        e:ms:asString("5"), e:method:asString("<5"), e:path]):display
}).

errors:size:greaterThan(#0):ifTrue({
    "":display.
    "failures":display.
    errors:do({ e |
        "  {} {} {}":fill([e:time, e:status, e:path]):display })
}).
