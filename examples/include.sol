; include.sol -- splitting a program across files.
; Run with:  ./bin/solas examples/include.sol && ./bin/solvm examples/include.sob

; `@include "file".` compiles that file in at this point, as though its text had
; been written here. The '@' says it is a directive rather than a message: it
; happens while compiling, and by the time the program runs there is nothing
; left of it. It has to stand alone as a statement -- there is nowhere inside an
; expression for a file to go.
;
; The file is found beside this one, not beside wherever you happened to be
; standing when you ran the compiler.
@include "library.sol".

temperature:cToF(100.0):print.          ; 212
temperature:fToC(212.0):print.          ; 100

temperature:describe(0.0:sub(5.0)):display.   ; freezing
temperature:describe(21.0):display.           ; fine
temperature:describe(35.0):display.           ; hot

; A file is compiled once however many ways you reach it. Asking again is not
; an error, and does not make a second copy -- so two files may each include
; what they need without arranging between themselves who includes what.
@include "library.sol".

; What an included file binds are ordinary globals: there is one namespace, and
; nothing distinguishes a name bound over there from one bound here.
temperature:kToC := { k | k:sub(273.15) }.
temperature:kToC(300.0):asString(".2"):display.    ; 26.85
