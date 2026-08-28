; exports.sol -- deciding what an object shows the outside world.
; Run with:  ./bin/solas examples/exports.sol && ./bin/solvm examples/exports.sob

; An object with slots is already a namespace: one name in the flat global
; space, and everything else reached through it. What that does not give you is
; a way to say which of those slots are anybody else's business.
;
; A counter keeps a running total. `bump` and `total` are what it is for; `n` is
; where it happens to keep the number.
counter := object:new.
counter:n := #0.
counter:bump  := { self:n := self:n:add(#1) }.
counter:total := { self:n }.

; `exports` draws the line. From here on this object *is* these two names, as
; far as anything outside it is concerned.
counter:exports(['bump, 'total]).

counter:bump.
counter:bump.
counter:total:print.                    ; #2

; From inside nothing changed at all -- `bump` goes on reaching `self:n`, which
; is the only reason a boundary is usable. "Inside" means the frame doing the
; sending is running with this very object as its self.

; From outside, a name off the list can be neither read nor written. The write
; is the one that matters: without this rule, anything could reach in and put a
; string where the count goes.
{ counter:n }:onError({ e | e:message:display }).
                                        ; 'n' is not exported by object
{ counter:n := "not a number" }:onError({ e | e:message:display }).
                                        ; 'n' is not exported by object

; And a name that is not on the list cannot be *added* from outside either.
; Otherwise binding one that happens to collide with something private would
; quietly overwrite a slot the binder is not allowed to see -- which is the
; same accident wearing a different hat.
{ counter:fresh := #1 }:onError({ e | e:message:display }).
                                        ; 'fresh' is not exported by object

; Reflection keeps the line rather than walking around it: from outside,
; `slots` answers the exports and nothing else, and `respondsTo` agrees with
; what sending would actually do.
counter:slots:print.                    ; ['bump, 'total]
counter:respondsTo('bump):print.        ; true
counter:respondsTo('n):print.           ; false

; `exports` with no argument answers the list, so an object can be asked what
; it offers. An object that never drew a line answers nil, and behaves exactly
; as it always did -- which is nearly every object, including this one's proto.
counter:exports:print.                  ; ['bump, 'total]
object:new:exports:print.               ; nil

; **Privacy is inherited.** The check compares the *receiver* against the
; sender's self, not the object the slot was found on -- so a child's own
; method reaches what it inherited, while anything else still cannot.
tally := counter:new.
tally:twice := { self:bump. self:bump. self:n }.

; #4 rather than #2: `tally` reads `n` through its proto, where the count had
; already reached two, and binds its own from there. That is prototypes doing
; what prototypes do -- what matters here is that `self:n` was reachable at all.
tally:twice:print.                      ; #4

; A boundary cannot be redrawn from outside, which is what makes it one rather
; than a note about intent.
{ counter:exports(['bump, 'total, 'n]) }:onError({ e | e:message:display }).
                                        ; 'exports' has already been declared and cannot be redrawn from outside
