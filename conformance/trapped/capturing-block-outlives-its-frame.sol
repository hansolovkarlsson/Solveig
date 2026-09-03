; conformance: a block that reads its enclosing frame cannot be called after that frame has returned
; varies: machine
; status: nonzero
;
; The permitted half -- a block touching nothing outside itself -- is pinned in
; accepted/03-blocks/escaping.sol. This is the other half, and it is reported
; rather than left to read whatever now sits in the frame's place.

free := { { #42 } }:value.
free:value:print.

capturing := { | t | t := #1. { t } }:value.
"the frame has returned":display.
capturing:value:print.
