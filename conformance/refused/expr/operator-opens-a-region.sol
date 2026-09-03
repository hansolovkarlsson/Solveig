; conformance: only '-' and '~' may open an expression inside an @expr region
; varies: front
; refused: expr/operator-opens-a-region
;
; An operator needs something to its left. The two that may open one are the
; unary forms, and '*' has no unary reading to fall back on.

@expr( * #1 ):print.
