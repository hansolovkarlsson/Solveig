; conformance: system:exit stops the program and is not an error, so onError does not catch it
; varies: machine
; status: 3
;
; It travels the way a failure does, so a cleanup still runs -- giving back a
; thing you borrowed is as necessary when a program is stopping as when it is
; failing -- but a handler watching for errors is not allowed to argue with a
; program that asked to stop.

{ "in the body":display.
  { "exiting":display. system:exit(#3) }:ensure({ "cleanup ran":display }).
  "not reached":display
}:onError({ e | "handler ran":display }).

"not reached either":display.
