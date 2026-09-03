; conformance: an undeclared name assigned inside a block is reported rather than becoming a local
; varies: machine
; status: nonzero
;
; Only the top level of a script may create a global, so a typo inside a block is
; a mistake rather than a variable that looks local and is not.

counter := #0.
{ counter := counter:add(#1) }:value.
counter:print.
{ countre := #1 }:value.
