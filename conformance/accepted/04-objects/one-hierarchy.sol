; conformance: the built-in classes are ordinary objects, and everything delegates to 'object'
; varies: machine
;
; A class holds the messages its instances understand, so sending one of those to
; the class itself is an error rather than a shortcut. The line is the receiver
; each message requires, not which object holds it -- which is what makes the two
; sides separable, and what respondsTo agrees with.

#45:isKindOf(object):print.
"s":isKindOf(object):print.
[]:isKindOf(object):print.
integer:parent:equals(object):print.
object:parent:print.

array:respondsTo('of):print.
array:respondsTo('add):print.
[#1]:respondsTo('add):print.
[#1]:respondsTo('of):print.

; Only the three classes whose instances are references construct, there being a
; fresh distinct one to hand back.
array:new:equals(array:new):print.
"":equals(""):print.

; A method bound on 'object' is answered by every value, which is what a root is
; for.
object:describe := { "a ":concat(self:asString) }.
#45:describe:display.
"s":describe:display.
