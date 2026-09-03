; conformance: a parameter declared twice is refused
; varies: front
; refused: names/duplicate-parameter
;
; The third of the three, and the one with its own sentence: a duplicate
; parameter is reported as a parameter rather than as a name, because at the
; point it is read the frame holds nothing else.

{ a, a | a }:value(#1, #2):print.
