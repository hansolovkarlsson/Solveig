; errors.sol -- failing, and deciding what to do about it.
; Run with:  ./bin/solas examples/errors.sol && ./bin/solvm examples/errors.sob
;
; Every failure in Solum stops the program unless something catches it. This is
; how something catches it.

; ---------------------------------------------------------------------------
; Catching

; `onError` runs the receiver, and if it fails runs the handler instead, giving
; it the error. Nothing is printed: a caught error was dealt with.
{ nil:frobnicate }:onError({ e | e:message:display }).
        ; nil does not understand 'frobnicate'

; It answers what the receiver answered when nothing went wrong, and what the
; handler answered when something did -- so it is an expression, and that is
; usually how you want it.
{ #1:add(#2) }:onError({ e | #0 }):print.        ; #3
{ nil:boom   }:onError({ e | #0 }):print.        ; #0

; Which makes a default for something that might not be there read plainly.
text := { system:readFile("build/no-such-file") }:onError({ e | "" }).
text:size:print.                                 ; #0

; ---------------------------------------------------------------------------
; Raising

; A program says a thing is wrong the same way the machine does.
{ error:raise("bad input on line 3") }:onError({ e | e:message:display }).
        ; bad input on line 3

; An error is an object, not a string. That is on purpose: the wording of these
; messages changes, so matching on the text would be a bad habit to make easy,
; and an object leaves room to say more about a failure later.
{ error:raise("x") }:onError({ e |
    e:isKindOf(error):print.                     ; true
    e:isKindOf(object):print.                    ; true -- like everything else
    e:message:isKindOf(string):print }).         ; true

; ---------------------------------------------------------------------------
; It catches everything, so pass on what you did not mean to catch

; There is no taxonomy of failures: `onError` catches a message you misspelled
; as readily as one you raised. A handler wrapped around too much hides
; mistakes, and the way out is to re-raise what you did not mean to handle.

check := { s |
    s:size:equals(#0):ifTrue({ error:raise("empty") }).
    s:size:greaterThan(#5):ifTrue({ error:raise("too long") }).
    s
}.

report := { s |
    { check:value(s) }:onError({ e |
        e:message:equals("empty"):ifElse(
            { "(nothing given)" },
            { error:raise(e:message) })          ; not ours -- pass it on
    })
}.

report:value(""):display.                        ; (nothing given)
report:value("ok"):display.                      ; ok

; "too long" is raised inside and passed on, so the outer handler sees it.
{ report:value("far too long") }:onError({ e | e:message:display }).
        ; too long

; A re-raised error's stack points at where it was re-raised rather than where
; it first failed. That is honest -- it is a new raise -- and it is the price of
; having exactly one way to raise rather than two.

; ---------------------------------------------------------------------------
; What is not caught

; `system:exit` travels the same way an error does, being a stop rather than a
; failure, and is deliberately not caught: a program asking to stop should not
; be argued with by something that was only watching for errors.
;
;   { system:exit(#4) }:onError({ e | "never runs":display }).

; An error inside the handler is not caught by that handler either -- it
; propagates, like any other failure.
{ { error:raise("first") }:onError({ e | nil:boom }) }
    :onError({ e | e:message:display }).         ; nil does not understand 'boom'

"done":display.
