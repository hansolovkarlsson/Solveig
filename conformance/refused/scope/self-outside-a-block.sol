; conformance: 'self' is only meaningful inside a block
; varies: front
; refused: scope/self-outside-a-block
;
; There are no reserved words here, so `self` is an ordinary identifier that the
; compiler recognises in one place. A front end built from solum.bnf alone will
; accept this, because a grammar that says of itself that it has no keywords
; cannot carry a rule about one.
;
; 'self' is the receiver, held in slot 0 of a frame. At the top level of a script
; there is no receiver.

self:print.
