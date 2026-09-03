; conformance: a bare identifier is a lookup -- local, then an enclosing frame's local, then a global
; varies: front
;
; It is not a send, so nothing can intercept it, and the three scopes are tried
; in that order. Only parameters and names declared with `| ... |` are locals;
; everything else is a global.

g := #1.

f := { | g |
    g := #2.
    g                    ; the local shadows the global
}.
f:value:print.
g:print.

outer := { | t |
    t := #3.
    { t:add(#1) }:value  ; the inner block reads the enclosing frame
}.
outer:value:print.

; A global written inside a block updates the global, since it is not a local.
counter := #0.
bump := { counter := counter:add(#1) }.
bump:value.
bump:value.
counter:print.
