; conformance: ensure runs its cleanup whether the body finished or not, and answers the body's answer
; varies: machine
;
; The cleanup's answer is discarded, the cleanup not being what the expression is
; about. Nested, the cleanups run innermost first as the failure travels outward.

v := { #1 }:ensure({ "cleanup":display. #99 }).
v:print.

{ { error:raise("inner") }:ensure({ "tidy":display }) }:onError({ e | e:message:display }).

{ { { error:raise("deep") }:ensure({ "innermost":display }) }:ensure({ "outermost":display })
}:onError({ e | e:message:display }).

; When both fail, the body's failure is the one that carries on -- the first
; error wins, the second usually being a consequence of it.
{ { error:raise("body") }:ensure({ error:raise("cleanup") }) }:onError({ e | e:message:display }).

; A cleanup that fails on its own, with nothing to compete with, fails normally.
{ { #1 }:ensure({ error:raise("only me") }) }:onError({ e | e:message:display }).
