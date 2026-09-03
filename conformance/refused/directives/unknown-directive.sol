; conformance: a directive the compiler does not know is refused
; varies: front
; refused: directives/unknown-directive
;
; No identifier can begin with '@', so the directive space cannot collide with a
; name a program might want -- and an unknown one is a mistake rather than
; something to pass through.

@nosuch "f".
