; conformance: a value class refuses 'new', there being no fresh distinct thing to answer with
; varies: machine
; status: nonzero
;
; Only object, array and dictionary construct, and the rule is mutability: 'new'
; belongs where something is made. The value classes refuse rather than going
; missing, because every built-in delegates to object, whose 'new' would
; otherwise answer a thing that fails every message an integer understands.

array:new:size:print.
object:new:isKindOf(object):print.
integer:new(#45):print.
