; client.sol -- talks to server.sol, one datagram at a time.
;
;   ./bin/solas extensions/net/client.sol -o /tmp/client.sob
;   ./bin/solvm --extension=build/extensions/net.so /tmp/client.sob 7777 "add 5" get
;
; A request and its answer, with a bounded wait between them. UDP does not
; promise delivery, so a reply that does not arrive is an ordinary outcome and
; the program says so rather than waiting forever -- which is the honest shape
; for a datagram and is why `waitFor` answers a boolean instead of blocking.

port := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1):asInteger(#10) },
    { #7777 }).

commands := system:arguments:size:greaterThan(#1):ifElse(
    { system:arguments:copyFrom(#2, system:arguments:size) },
    { ["add 5", "add 37", "get"] }).

; Port #0: the system picks one, and the server answers to whatever it picked.
; Nothing here has to know its own address for that to work.
sock := net:udp(#0).

commands:do({ command |
    net:send(sock, "127.0.0.1", port, command).
    net:waitFor(sock, #2000):ifElse(
        { | packet |
          packet := net:receive(sock).
          "{} -> {}":fill([command, packet:text]):print },
        { "{} -> no answer in 2s":fill([command]):print }) }).
