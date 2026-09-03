; conformance: removeLast refuses an empty array rather than answering nil
; varies: machine
; status: nonzero
;
; The same choice 'at' makes about an index. Ask 'size' first, which is the shape
; a stack's loop condition already has.

s := [#1].
s:removeLast:print.
s:size:print.
s:removeLast:print.
