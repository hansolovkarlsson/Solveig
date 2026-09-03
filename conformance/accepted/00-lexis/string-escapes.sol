; conformance: the five string escapes, and no others
; varies: front
;
; \" \\ \n \t \r are the whole set. Any other escape is an error rather than a
; literal backslash, and there is no \0. A literal newline inside the quotes
; works too, and is the same character as \n.

"she said \"hi\"":display.
"one\ntwo":display.
"a\tb":display.
"back\\slash":display.

; system:write ends no line, so what the escape put there is the only thing
; between the two halves.
system:write("carriage\rreturn").
system:write("\n").

"a
b":display.
