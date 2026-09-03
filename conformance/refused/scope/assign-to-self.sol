; conformance: 'self' cannot be assigned
; varies: front
; refused: scope/assign-to-self
;
; It is the receiver rather than a name bound to it, so there is nothing for an
; assignment to change. Slot 0 is where it lives and the frame does not own it.

integer:bad := { self := #1 }.
