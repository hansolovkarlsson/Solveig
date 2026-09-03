; conformance: a temporary may not take a parameter's name
; varies: front
; refused: names/temporary-shadows-a-parameter
;
; The same one namespace as the case beside this one, approached from the other
; side: the parameter is already in the frame when the temporaries are read.

{ k | | k | k }:value(#1):print.
