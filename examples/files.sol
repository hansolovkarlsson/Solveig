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

; ---------------------------------------------------------------------------
; Reading part of one
;
; `readFile(path, from, count)` answers `count` bytes from `from`, which is a
; one-based byte position like every other index here. It is a range and not a
; handle: nothing to open, nothing to close, and two parts of a program can read
; two parts of a file without agreeing about anything.

system:readFile(path, #1, #6):print.        ; "apples"

; **A short range is the answer, not a failure.** Asking for more than is left
; gives back what was there, and asking from past the end gives back nothing --
; because "the last four kilobytes" of a file that turns out to be shorter is a
; reasonable question, and the string that comes back says its own size.
system:readFile(path, #10, #999):size:print.    ; #19, being all that was left
system:readFile(path, #999, #10):print.         ; ""

; `#0` is not a position, in a file or in a string.
{ system:readFile(path, #0, #4) }:onError({ e | e:message:display }).

; With `fileSize`, this is how to read the end of a file too large to hold: the
; whole-file form refuses anything past two gigabytes, and a range does not care
; how big the file is.
size := system:fileSize(path).
system:readFile(path, size:sub(#9), #10):print. ; "quinces 1\n"

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

; **Asking about a path is a different question from reading it**, and the four
; messages that ask agree about a path that is not there: `fileExists` and
; `isDirectory` answer false, `fileSize` and `modifiedAt` answer nil. Only
; `readFile` stops the program, because reading a file you have not got is
; wrong about something -- where *measuring* one is a fair question with a real
; answer.
system:fileSize(absent):print.                  ; nil
system:modifiedAt(absent):print.                ; nil

; Which is what lets a program watch a path across a rotation instead of dying
; on one -- `tail -f` polls `fileSize` and used to exit on the first `mv`. All
; four still raise for a path that cannot be *looked* at: a permission that
; stops the question being asked is not an answer to it.
system:fileSize(absent):isNil:print.            ; true -- and asking cost nothing

; ---------------------------------------------------------------------------
; Changing what is there
;
; These do something that cannot be undone. Nothing here asks twice or keeps a
; copy, so the looking is the program's job -- and the pieces to look with are
; `fileExists`, `isDirectory` and `fileSize`.

scratch := "build/example-scratch".

; "make sure it is there" is one message. `makeDirectory` answers **true** when
; it made one and **false** when a directory was already there -- so the common
; case needs no test, and a caller who cares which it was still finds out.
;
; Anything else is an error: no permission, no parent, or something that is not
; a directory already sitting at that name. That last one used to be reported
; the same way as "already there", which is the same news from `mkdir` and not
; the same news at all.
system:makeDirectory(scratch).

system:writeFile(scratch:concat("/note.txt"), "a line
").
system:fileSize(scratch:concat("/note.txt")):print.     ; #7, without reading it

; ---------------------------------------------------------------------------
; Which file is at this path
;
; Size and time are not identity: a log and the log that replaced it can agree
; on both. `fileId` answers what the filesystem calls the file -- device and
; inode, as a string -- and the only thing promised of it is `equals`.
;
; It is what tells a **rotation** from a **write**, which is the difference
; between following a log and losing a line out of it.
note := scratch:concat("/note.txt").
was := system:fileId(note).
was:equals(system:fileId(note)):print.          ; true -- the same file, asked twice

; A hard link is a second name for one file, so it answers the same id. A copy
; is a different file and does not.
system:writeFile(scratch:concat("/copy.txt"), system:readFile(note)).
was:equals(system:fileId(scratch:concat("/copy.txt"))):print.
                                                ; false -- same bytes, different file
system:remove(scratch:concat("/copy.txt")).

; ---------------------------------------------------------------------------
; What a file is besides its contents
;
; It has a mode and a time, and both can be read and written. A copy that keeps
; neither is not a copy of the file, which is what asked for these:
; programs/mirror.sol was giving every file it wrote today's date and the
; default permissions.

note := scratch:concat("/note.txt").

; `modeOf` answers the permission bits as an integer, and `setMode` takes one.
; A mode is three triples of bits, which is exactly what a binary literal is
; for: `%111101101` is `0755` with the triples where you can see them, where
; `#493` is the same number and tells you nothing. `asBase(#8)` gets the
; notation people recognise back out.
system:setMode(note, %111101101).
system:modeOf(note):asBase(#8):display.                 ; 755

; The time, the same way round: `setModifiedAt` takes what `modifiedAt` answers,
; so carrying a timestamp from one file to another is a read and a write of one
; value rather than a conversion through anything.
;
; `plusSeconds` wants a float, because a time is a float count of seconds and
; the language does not widen an integer for you -- see strictness.sol.
stamp := system:modifiedAt(note).
system:setModifiedAt(note, stamp:plusSeconds(86400.0:negated)).
system:modifiedAt(note):lessThan(stamp):print.          ; true -- a day earlier

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
