; log.sol -- reading an access log and reporting on it.
;
; Run with:  ./bin/solas programs/log.sol && ./bin/solvm programs/log.sob
; Or over a log of your own:  ./bin/solvm programs/log.sob path/to/access.log
;
; **The first program in this directory, and the reason the directory exists.**
; The files in examples/ were each written to demonstrate a feature. This one was
; written to do a job, and uses whatever the language turned out to have. Where
; it is awkward, the comment says so rather than hiding it -- that is the useful
; part, and it is what a program written to show a feature can never report,
; because it was written after the feature and to suit it.
;
; Every entry the roadmap gained after the first dozen arrived this way: somebody
; wrote one of these and found out what it wanted.
;
; It also expects its input to be damaged, because real input is. Three of the
; lines in the sample below are broken in different ways, and the report says so
; and carries on rather than stopping at the first one.
;
; That half was added after `onError` existed, and it found two things worth
; writing down. Surviving a bad *line* is not the same as surviving a bad
; *file*: a file of pure rubbish leaves nothing to report on, and the summary
; fell over on the empty array the first time it met one. And the division of
; labour that makes a report readable is that the machine says what went wrong
; -- `'four' is not an integer` names the offending text -- while the program
; says where, because only the program is counting lines.
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
2026-08-20T09:14:20 GET /truncated.html 200
2026-08-20T09:14:22 GET /index.html 200 1043 11
2026-08-20T09:15:01 POST /api/login 401 92 198
2026-08-20T09:15:02 POST /api/login 401 92 205
2026-08-20T09:15:04 POST /api/login 401 92 1902
2026-08-20T09:15:05 POST /api/login four 92 198
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
entry:time   := nil.        ; a time, once there was a time to parse it into
entry:method := "".
entry:path   := "".
entry:status := #0.
entry:bytes  := #0.
entry:ms     := #0.

; `parse` says what is wrong with a line rather than letting the first message
; that cannot cope fail on its behalf. `f:at(#4)` on a short line answers
; `index #4 is out of bounds for an array of size 3`, which is true and tells a
; reader nothing about their log.
parse := { line | | f, e |
    f := line:split(" ").
    f:size:equals(#6):ifFalse({
        error:raise("wanted 6 fields, got {}":fill([f:size])) }).

    e := entry:new.
    ; Parsed rather than kept as text. It was a string until there was a time
    ; type -- which worked, because these timestamps sort the same as strings
    ; and as instants. That is true of ISO-8601 and of no other format, so it
    ; was luck rather than design, and a malformed timestamp went unnoticed
    ; because nothing ever looked at one.
    e:time   := f:at(#1):asTime.
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
; A line that will not parse is reported and skipped, not fatal. `onError`
; answers the handler's value when the block failed, so the count and the
; complaint both come from one place.
;
; The number is the useful half. `'four' is not an integer` is a good message
; and a poor report on its own -- it does not say *where*. The machine supplies
; what went wrong and the program supplies where, which is the division that
; makes both worth having.
entries := array:new.
skipped := array:new.
lineNumber := #0.

system:readFile(path):split("\n"):do({ line |
    lineNumber := lineNumber:add(#1).
    line:equals(""):ifFalse({
        { entries:add(parse:value(line)) }:onError({ e |
            skipped:add("line {}: {}":fill([lineNumber, e:message])) })
    })
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

; Surviving every bad line is not the same as surviving a bad file. With nothing
; readable there is no first entry to ask the time of, and the report below
; would fail on the empty array -- which is what happened the first time this
; was tried against a file of pure rubbish. The skipped lines are the whole of
; what there is to say, so say that and leave.
count:equals(#0):ifTrue({
    "nothing readable in {}":fill([path]):display.
    skipped:do({ complaint | "  ":concat(complaint):display }).
    system:exit(#1) }).

bytes := entries:inject(#0, { total, e | total:add(e:bytes) }).
slow  := entries:inject(#0, { total, e | total:add(e:ms) }).
errors := entries:select({ e | e:status:greaterOrEqual(#400) }).

"":display.
"{} requests from {}":fill([count, path]):display.
"{} distinct paths, {} distinct statuses":fill([
    byPath:keys:size, byStatus:size]):display.
; The span, now that these are instants rather than text: `secondsSince`
; answers a number of seconds, which is a thing text could never have told us.
first := entries:at(#1):time.
last := entries:at(count):time.
"{} to {}":fill([first:asString("%H:%M:%S"), last:asString("%H:%M:%S")]):display.
"over {} seconds":fill([last:secondsSince(first):asString(".0")]):display.
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

skipped:size:greaterThan(#0):ifTrue({
    "":display.
    "{} lines could not be read":fill([skipped:size]):display.
    skipped:do({ complaint | "  ":concat(complaint):display })
}).

errors:size:greaterThan(#0):ifTrue({
    "":display.
    "failures":display.
    errors:do({ e |
        "  {} {} {}":fill([e:time:asString("%H:%M:%S"), e:status, e:path]):display })
}).
