; conformance: error:raise is the only way to raise, so re-raising is error:raise(e:message)
; varies: machine
;
; The text here is the program's own, which is why this case may compare it: an
; implementation that changed it would be changing what the program said rather
; than how it words its own failures.

{ error:raise("bad input on line 3") }:onError({ e | e:message:display }).

; Passing one on is a single message, and the outer handler sees it.
{ { error:raise("inner") }:onError({ e |
      error:raise(e:message:concat(" -- passed on")) })
}:onError({ e | e:message:display }).

; An error raised inside a handler is not caught by that handler; it propagates.
{ { error:raise("first") }:onError({ e | error:raise("second") }) }:onError({ e |
    e:message:display }).

; A handler that decides the failure is not its own passes it on unchanged.
handle := { thunk |
    thunk:onError({ e |
        e:message:equals("empty"):ifElse(
            { "(nothing given)" },
            { error:raise(e:message) }) }) }.
{ handle:value({ error:raise("empty") }) }:onError({ e | "unreachable":display }):display.
{ handle:value({ error:raise("other") }) }:onError({ e | e:message:display }).
