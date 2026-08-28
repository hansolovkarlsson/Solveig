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

; **The boundary is inherited**, so a thing made from this one is under it too.
; That is what makes a boundary worth drawing on a prototype: every counter a
; program actually holds is an object made from this one, and its own copy of
; `n` is where the number really lives. A line that stopped at the prototype
; would have protected only the default.
tally := counter:new.

; An inherited method still reaches what it inherited -- `bump` runs with
; `tally` as its self, so `self:n` is reachable, and `tally` gets a copy of `n`
; of its own. It starts from #2 because that is what its proto had reached.
tally:bump.
tally:total:print.                      ; #3

; But from outside, `tally` is the same two names its proto published --
; including for *adding* one. A prototype that says what it offers says it on
; behalf of everything made from it.
{ tally:n }:onError({ e | e:message:display }).
                                        ; 'n' is not exported by object
{ tally:twice := { self:bump } }:onError({ e | e:message:display }).
                                        ; 'twice' is not exported by object

; A boundary cannot be redrawn from outside, which is what makes it one rather
; than a note about intent.
{ counter:exports(['bump, 'total, 'n]) }:onError({ e | e:message:display }).
                                        ; 'exports' has already been declared and cannot be redrawn from outside
