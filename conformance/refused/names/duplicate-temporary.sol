; conformance: a temporary declared twice in one frame is refused
; varies: front
; refused: names/duplicate-temporary
;
; A frame's names are one namespace -- parameters and temporaries share it, and
; slot 0 is the receiver. Nothing in the grammar says so, which is why a front
; end built from it accepts this and answers about whichever slot it happened to
; keep.

{ | t, t | t }:value:print.
