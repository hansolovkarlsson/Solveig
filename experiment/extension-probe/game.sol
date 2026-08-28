; -- game.sol -- one program, three C libraries, no arrangement between them.
;
; Nothing here says "load" anything. `sdl`, `fastmath` and `net` are globals,
; put there before the run by whoever started the program.

sdl:open("solum game", #320, #240):print.

me   := net:udp(#0).
them := net:udp(#0).
"listening on ":display. net:port(me):print.

; -- the sort of thing the C library exists for: not expressible fast in Solum
left  := [1.0, 2.0, 3.0, 4.0].
right := [0.5, 0.25, 2.0, 1.0].

frame  := #0.
energy := 0.0.
packet := nil.
sdl:each({
    frame := @expr(frame + #1).

    ; -- graphics library drives the loop, maths library does the work,
    ; -- network library carries it to the other player
    energy := fastmath:dot(left, right).
    net:send(them, net:port(me), frame:asString:concat(":"):concat(energy:asString)).

    packet := net:poll(me).
    packet:notNil:ifTrue({ "  got ":display. packet:print }).

    frame:lessThan(#4) }).

sdl:close.
; -- no net:close: the sockets are closed when this program lets go of
; -- them, and by the machine going down if it does not.
"clean exit":print.
