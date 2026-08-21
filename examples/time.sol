; time.sol -- a point in time, and what you can ask it.
; Run with:  ./bin/solas examples/time.sol && ./bin/solvm examples/time.sob

; A time is a **value**, like a number: two of the same instant are the same
; time, nothing changes one, and there is no literal for one because there is
; nothing to write down that a clock or a file does not tell you.
now := system:time.
now:print.                                   ; 2026-08-21T16:57:41Z

; ---------------------------------------------------------------------------
; Everything is UTC, and that is the decision
;
; There is no local time here and no zone. A zone is a political fact that
; changes by legislation, twice a year in most places and retroactively in some.
; An instant is unambiguous; a wall-clock reading is not. The trailing Z is not
; decoration -- it is what says which of the two this is.

; ---------------------------------------------------------------------------
; Naming a particular moment

; `system:time` is now. `fromSeconds` is any instant, counted from the epoch,
; which is how one gets written down and read back.
y2k := time:fromSeconds(946684800.0).
y2k:print.                                   ; 2000-01-01T00:00:00Z
y2k:asSeconds:print.                         ; 946684800

; It is a float because that is the unit `secondsSince` and `plusSeconds` speak
; in, and because the language does not quietly turn an integer into one:
;   time:fromSeconds(946684800)  ->  'fromSeconds' expects a float, got integer

; ---------------------------------------------------------------------------
; What it can answer

y2k:year:print.                              ; #2000
y2k:month:print.                             ; #1   -- January is #1, not #0
y2k:day:print.                               ; #1
y2k:hour:print.                              ; #0
y2k:minute:print.                            ; #0
y2k:second:print.                            ; #0
y2k:weekday:print.                           ; #6   -- Monday is #1, so Saturday

; Before the epoch works, and counts backwards properly.
time:fromSeconds(0.0:sub(86400.0)):print.    ; 1969-12-31T00:00:00Z

; ---------------------------------------------------------------------------
; Comparing and measuring

deadline := y2k:plusSeconds(3600.0).
deadline:print.                              ; 2000-01-01T01:00:00Z
deadline:secondsSince(y2k):print.            ; 3600
y2k:lessThan(deadline):print.                ; true
deadline:greaterOrEqual(y2k):print.          ; true
y2k:equals(time:fromSeconds(946684800.0)):print.   ; true -- a value, so equal

; `secondsSince` rather than `sub`: a time minus a time is not a time, and the
; name says the direction and the unit, which is what a bare subtraction leaves
; you guessing. It answers a float, as `system:clock` differences do.

; A time is a value, so it may be a dictionary key like any other.
seen := dictionary:new.
seen:atPut(y2k, "the millennium").
seen:at(time:fromSeconds(946684800.0)):display.    ; the millennium

; ---------------------------------------------------------------------------
; Showing one

; `asString` with no argument is the ISO-8601 above. With one, the format is
; handed to the C library's `strftime`, whose alphabet is the one everybody
; already knows -- rather than a third spec language invented for the purpose.
y2k:asString("%Y-%m-%d"):display.            ; 2000-01-01
y2k:asString("%H:%M:%S"):display.            ; 00:00:00
y2k:asString("%A, %d %B %Y"):display.        ; Saturday, 01 January 2000
y2k:asString("day %j of %Y"):display.        ; day 001 of 2000

; ---------------------------------------------------------------------------
; Reading one back

; `asTime` is on `string`, beside `asInteger` and `asFloat` -- a conversion from
; text has always been the string's. With no argument it reads ISO-8601.
"2000-01-01T00:00:00Z":asTime:equals(y2k):print.        ; true
"2000-01-01":asTime:print.                              ; midnight
"2026-08-20 09:14:02":asTime:print.                     ; T or a space

; No zone means UTC, there being no other kind here. An *offset* is accepted,
; because an offset is arithmetic -- it says nothing about legislation.
"2026-08-20T09:14:02+01:00":asTime:print.               ; 08:14:02Z
"2026-08-20T09:14:02-05:00":asTime:print.               ; 14:14:02Z

; Strict, as asInteger is, and a date that does not exist is refused rather than
; rolled forward -- which is what almost every date parser does quietly.
"2024-02-29":asTime:print.                              ; a real leap day
;   "2026-02-29":asTime  ->  'asTime' cannot read that as a date
;   "2026-04-31":asTime  ->  'asTime' cannot read that as a date

; With a format, the C library reads it -- the same alphabet asString writes in.
"20/08/2026":asTime("%d/%m/%Y"):print.

; What asString writes, asTime reads.
y2k:asString:asTime:equals(y2k):print.                  ; true

; ---------------------------------------------------------------------------
; When a file was touched
;
; This is the message `fileSize` was waiting for: it could not be written until
; there was a time to answer with.

stamp := system:modifiedAt("examples/time.sol").
stamp:year:greaterThan(#2000):print.         ; true
"this example was last written in {}":fill([stamp:asString("%Y")]):display.

; `system:clock` is still there and is still not this. That one is a stopwatch --
; monotonic, unspecified epoch, only differences meaningful. This is a calendar.
; A program asking how long something took wants the first; one asking when it
; happened wants the second.
