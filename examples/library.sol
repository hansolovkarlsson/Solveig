; library.sol -- a file written to be included by another one.
;
; Nothing here marks it as a library. It is a file that binds names, and any
; other file can have them with one line:
;
;     "library.sol":include.
;
; See examples/include.sol, which does exactly that. Run that one:
;   ./bin/solas examples/include.sol && ./bin/solvm examples/include.sob

; Globals are one flat namespace across every file, so a library is easier to
; live with when it claims one name and hangs the rest off it. An ordinary
; object is all that takes.
temperature := object:new.

; Floats throughout: '#' would make these integers, and the two never mix.
temperature:cToF := { c | c:mul(1.8):add(32.0) }.
temperature:fToC := { f | f:sub(32.0):div(1.8) }.

; A block bound to a slot is a method, here and in any other file.
temperature:describe := { c |
    c:lessThan(0.0):ifElse(
        { "freezing" },
        { c:greaterThan(30.0):ifElse({ "hot" }, { "fine" }) })
}.
