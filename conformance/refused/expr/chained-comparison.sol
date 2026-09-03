; conformance: comparisons do not chain inside an @expr region
; varies: front
; refused: expr/chained-comparison
;
; `a < b < c` would compare a boolean to c, so it is refused while compiling
; rather than left to fail while running. The infix region is a second grammar
; and this rule lives in the compiler rather than in it.

@expr( #1 < #2 < #3 ):print.
