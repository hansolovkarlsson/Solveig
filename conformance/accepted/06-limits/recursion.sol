; conformance: recursion works, and with a conditional it terminates
; varies: machine
;
; The run-time ceiling is 256 call frames, and this case deliberately does not
; sit on it. How many frames a given program reaches at a given depth is a
; question about what each construct costs -- an inlined ifElse costs none, an
; ordinary send costs one, a block argument costs another -- and a corpus that
; pinned the deepest working recursion would be scoring that accounting rather
; than the language. What is pinned here is that the recursion runs at a depth
; well inside the ceiling and answers.

integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul(self:sub(#1):factorial) })
}.
#10:factorial:print.
#20:factorial:print.

integer:down := { self:equals(#0):ifElse({ #0 }, { self:sub(#1):down:add(#1) }) }.
#100:down:print.

; Mutual recursion is the same mechanism.
integer:isEven := { self:equals(#0):ifElse({ true }, { self:sub(#1):isOdd }) }.
integer:isOdd := { self:equals(#0):ifElse({ false }, { self:sub(#1):isEven }) }.
#50:isEven:print.
#51:isEven:print.

; And running out of frames arrives at onError like any other failure, so a
; program can survive it rather than being stopped by it.
integer:forever := { self:add(#1):forever }.
{ #1:forever }:onError({ e | "caught":display }).
"still here":display.
