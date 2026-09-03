; conformance: an index out of range is an error rather than nil
; varies: machine
; status: nonzero
;
; nil would be a second way of saying nothing beside the one the language has,
; and it would turn a mistake into a value that fails further on.

a := [#1, #2].
a:at(#2):print.
a:at(#3):print.
