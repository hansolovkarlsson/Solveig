; reading.sol -- reading standard input a line at a time.
;
; Run with:
;   ./bin/solas examples/reading.sol
;   ./bin/solvm examples/reading.sob < examples/hello.sol
;
; `system:readLine` answers one line, without its terminator, or nil when there
; is no more input. Nil is the end and "" is an empty line, so the two are never
; confused -- which is what lets the loop below be written the obvious way.

; ---------------------------------------------------------------------------
; Asking, which comes before reading
;
; `display` ends the line, which is right for output and wrong for a question:
; a prompt and the answer typed after it belong on one line. `system:write` is
; the other half of the terminal from `readLine` -- it writes the string it is
; given and adds nothing, no newline and no rendering.
;
; It takes a string rather than any value, so there is no second rule about how
; things are turned into text: `#42:asString` says which form it wants.

system:write("how many lines? ").
"(reading from a file, so nothing was typed)":display.
;   how many lines? (reading from a file, so nothing was typed)

; The same stream `display` uses, so the two interleave in the order they were
; written -- including when the output is a pipe or a file rather than a
; terminal, where anything opening its own stream on the same output would not.

system:write("a").
system:write("b").
"c":display.                     ; abc

count := #0.
longest := "".

; Read one before the loop and one at the end of each pass. `whileTrue` tests
; before the body runs, so the first line has to be in hand before the first
; test -- there is no do-while here.
line := system:readLine.

{ line:notNil }:whileTrue({
    count := count:add(#1).
    line:size:greaterThan(longest:size):ifTrue({ longest := line }).

    "{}  {}":fill([count:asString("4"), line]):display.
    line := system:readLine
}).

"":display.
"{} lines; the longest is {} characters":fill([count, longest:size]):display.

; Nothing to read is not a failure, but it is worth saying so -- and saying it
; **on the other stream**, which is the whole of what `system:writeError` is
; for. The numbered lines above are this program's output; that nothing arrived
; is a different kind of thing, and a reader who redirects the output should get
; the lines in the file and the complaint on the terminal.
;
; `display`, `print` and `system:write` all go to standard output. This is the
; only way to reach the other one.
count:equals(#0):ifTrue({
    system:writeError("reading.sol: nothing on standard input\n").
    system:exit(#1)
}).
