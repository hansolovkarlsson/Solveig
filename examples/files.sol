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

; `split` takes the file apart. There are always occurrences + 1 pieces, so a
; file ending in a newline leaves an empty last piece -- which is why the count
; is one less than the number of pieces here.
lines := text:split("\n").
"{} lines":fill([lines:size:sub(#1)]):display.

; The pieces are ordinary strings. Each line here is a name and a count.
lines:do({ line | | at, name, count |
    line:equals(""):ifFalse({
        at := line:indexOf(" ").
        name := line:copyFrom(#1, at:sub(#1)).
        count := line:copyFrom(at:add(#1), line:size):asInteger.
        "{} -> {}":fill([name, count:mul(#2)]):display })
}).

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

; ---------------------------------------------------------------------------
; Changing what is there
;
; These do something that cannot be undone. Nothing here asks twice or keeps a
; copy, so the looking is the program's job -- and the pieces to look with are
; `fileExists`, `isDirectory` and `fileSize`.

scratch := "build/example-scratch".

; "make sure it is there" is two messages rather than one, and says which of the
; two it meant. `makeDirectory` on a directory that exists is an error.
system:isDirectory(scratch):ifFalse({ system:makeDirectory(scratch) }).

system:writeFile(scratch:concat("/note.txt"), "a line
").
system:fileSize(scratch:concat("/note.txt")):print.     ; #7, without reading it

; Renaming and moving are the same operation, and it works on a directory too.
system:rename(scratch:concat("/note.txt"), scratch:concat("/kept.txt")).
system:filesIn(scratch):print.                          ; ["kept.txt"]

; `remove` takes a file, or an *empty* directory. There is deliberately no
; recursive form: deleting a tree is not something to make one message wide, and
; a program that means it can walk with `filesIn` and remove what it finds.
system:remove(scratch:concat("/kept.txt")).
system:remove(scratch).
system:isDirectory(scratch):print.                      ; false

; Each refusal names the reason the system gave, so a script can tell a missing
; file from a directory that still has something in it:
;
;   system:remove("build")   ->  cannot remove 'build': Directory not empty
