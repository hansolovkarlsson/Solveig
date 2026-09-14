; conformance: the @expr region is off unless the front end is asked for it
; varies: front
; refused: expr/region-off
;
; Solveig's own compiler has an infix region, `@expr(...)`, behind a flag:
; `solas --expr`. It is notation over the sends -- the bytes are the chain's --
; and it is not part of the language a second front end has to have. A
; conforming compile of this file, with nothing asked for, refuses the
; directive.

@expr( #1 + #2 ):print.
