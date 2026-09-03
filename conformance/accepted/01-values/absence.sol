; conformance: isNil and notNil are on every type, and absence is not emptiness
; varies: machine
;
; They have to be on every type: the point of asking is that you do not know what
; the receiver is, so a message only nil understood could not be sent to find
; out. "", #0, [] and false all answer notNil.

nil:isNil:print.
nil:notNil:print.

"":isNil:print.
#0:isNil:print.
[]:isNil:print.
false:isNil:print.
false:notNil:print.

; x:equals(nil) says the same thing and is what the language had before these.
nil:equals(nil):print.
#0:equals(nil):print.

; nil is a value with a printed form like any other, and it is what a message
; answers when it has nothing to say.
nil:print.
false:ifTrue({ #1 }):print.
[#1, #2]:indexOf(#9):print.
"abc":indexOf("z"):print.
