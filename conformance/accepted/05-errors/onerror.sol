; conformance: onError answers the receiver's answer when nothing failed and the handler's when something did
; varies: machine
;
; A caught error says nothing -- the message never reaches standard error and the
; program carries on. Nothing here pins the text of a failure this
; implementation raised: an error's wording is a thing the implementation
; chooses, and a suite that demanded ours would be scoring the words rather than
; the behaviour. What is pinned is that the failure arrives, as an object
; delegating to 'error', carrying a message.

r := { #7 }:onError({ e | #9 }).
r:print.

s := { error:raise("x"). #7 }:onError({ e | #9 }).
s:print.

{ nil:frobnicate }:onError({ e |
    e:isKindOf(error):print.
    e:message:notNil:print }).

; It catches everything, a misspelled message included, and it is an expression
; rather than a statement -- which is what lets a default be written inline.
text := { nil:frobnicate }:onError({ e | "(nothing)" }).
text:display.

"still here":display.
