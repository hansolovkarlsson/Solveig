; files.sol -- reading and writing whole files.
; Run with:  ./bin/solas examples/files.sol && ./bin/solvm examples/files.sob
;
; Reading and writing are on `system` rather than on the string naming the file.
; A string does not know anything about files, and `system` is where what
; belongs to the world outside the program lives.
;
; This writes into build/, which `make clean` takes away again.

path := "build/example-notes.txt".

; ---------------------------------------------------------------------------
; Writing
;
; `writeFile` replaces what is there, and creates the file if it is not. It
; answers nil: there is nothing useful to chain from a write.

system:writeFile(path, "apples 3\npears 12\nquinces 1\n").
system:fileExists(path):print.                  ; true

; ---------------------------------------------------------------------------
; Reading
;
; `readFile` answers the whole file as one string. A string is bytes, so what
; comes back is exactly what went in.

text := system:readFile(path).
"{} bytes":fill([text:size]):display.

; There is no `split` yet, so counting lines is a walk. `at` is one-based and
; answers a one-character string.
lines := #0.
i := #1.
{ i:lessOrEqual(text:size) }:whileTrue({
    text:at(i):equals("\n"):ifTrue({ lines := lines:add(#1) }).
    i := i:add(#1)
}).
"{} lines":fill([lines]):display.

; ---------------------------------------------------------------------------
; When the file is not there
;
; A missing file is an error, not nil -- the same answer an out-of-range index
; gets. `readLine` answering nil at the end of input is not the precedent:
; running out of input is how a loop finishes, where a file that is not there is
; a program expecting something that is not so.
;
; `fileExists` is how to ask first. It is about a *file*, so a directory
; answers false -- it answers the question `readFile` asks.

absent := "build/no-such-file".

system:fileExists(absent):ifElse(
    { system:readFile(absent):display },
    { "{} is not there; readFile would stop the program":fill([absent]):display }).

system:fileExists("build"):print.               ; false -- a directory is not a file
