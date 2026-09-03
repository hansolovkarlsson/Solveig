; conformance: copyFrom includes both ends, first and last clamp, and indexOf answers nil
; varies: machine
;
; An index is one-based and out of range is an error rather than nil, which is
; the same choice removeLast makes about an empty array: nil would be a second
; way of saying nothing beside the one the language has.

a := [#1, #2, #3, #4, #5].
a:copyFrom(#2, #4):print.
a:copyFrom(#3, #2):print.
a:first(#2):print.
a:last(#2):print.
a:first(#99):print.
a:last(#0):print.

a:indexOf(#3):print.
a:indexOf(#9):print.
[[#1]]:indexOf([#1]):print.

; add answers the array so it chains, and removeLast is the other end of a stack.
s := array:new.
s:add(#1):add(#2):add(#3).
s:print.
s:removeLast:print.
s:print.
s:size:print.

; The receiver is untouched by the messages that answer a new one.
a:print.
["a", "b", "c"]:join("-"):display.
