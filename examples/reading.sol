; reading.sol -- reading standard input a line at a time.
;
; Run with:
;   ./bin/solas examples/reading.sol
;   ./bin/solvm examples/reading.sob < examples/hello.sol
;
; `system:readLine` answers one line, without its terminator, or nil when there
; is no more input. Nil is the end and "" is an empty line, so the two are never
; confused -- which is what lets the loop below be written the obvious way.

count := #0.
longest := "".

; Read one before the loop and one at the end of each pass. `whileTrue` tests
; before the body runs, so the first line has to be in hand before the first
; test -- there is no do-while here.
line := system:readLine.

{ line:notEquals(nil) }:whileTrue({
    count := count:add(#1).
    line:size:greaterThan(longest:size):ifTrue({ longest := line }).

    "{}  {}":fill([count:asString("4"), line]):display.
    line := system:readLine
}).

"":display.
"{} lines; the longest is {} characters":fill([count, longest:size]):display.

; Nothing to read is not a failure, but it is worth saying so.
count:equals(#0):ifTrue({
    "nothing on standard input":display.
    system:exit(#1)
}).
