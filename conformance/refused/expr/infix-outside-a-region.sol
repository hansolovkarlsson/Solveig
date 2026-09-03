; conformance: an infix operator outside an @expr region is refused rather than parsed
; varies: front
; refused: expr/infix-outside-a-region
;
; The language has no operators; @expr is where they are. A '+' met outside a
; region is not a send and not a name, and saying so at the point it appears is
; what stops it being read as two statements.

x := #1 + #2.
x:print.
