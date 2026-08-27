; load.sol -- bringing in a file that is already compiled.
; Run with:  ./bin/solas examples/load.sol && ./bin/solvm examples/load.sob
;
; Run it from the top of the repository, and the next paragraph says why.

; `system:load` is `@include`'s run-time twin. `@include` is a directive: it
; happens while compiling, it needs the source, and by the time the program runs
; there is nothing left of it. This is a message: it happens while running, it
; takes a `.sob` that was compiled separately, and it can be sent from anywhere
; a message can be sent.
;
; The path is resolved against the directory you are standing in, not against
; this file -- which is the one place the two differ in spirit as well as in
; timing. An `@include` is resolved while the file is being read and there is a
; file to be beside; a message has only the process, and the process has a
; working directory.
system:load("examples/library.sob").

; What it bound is simply here now. There is one flat namespace of globals and
; nothing marks a name as having come from somewhere else, which is exactly what
; `@include` does -- the whole of the connection between two files is the names
; one of them binds and the other one sends.
temperature:cToF(100.0):print.          ; 212
temperature:describe(35.0):display.     ; hot

; Because it is a message and not a directive, it happens when it is reached.
; This one is inside a block, so it happens when the block is called and not
; before -- something a directive cannot do, since a directive has already
; happened by the time there is a program to run.
loadAgain := { system:load("examples/library.sob") }.
"nothing has been loaded a second time yet":display.
loadAgain:value.

; And it really does run the file again. `@include` compiles a file once however
; many ways you reach it; this has no such memory, so loading twice runs the
; top level twice and binds everything a second time. For a file that only binds
; methods that is invisible, as it is here. For one that counts something it is
; not, and that is the caller's business to know.
temperature:cToF(0.0):print.            ; 32
