; server.sol -- a counter that answers over UDP, and the first Solveig program
; written to be talked to rather than run.
;
;   ./bin/solas extensions/net/server.sol -o /tmp/server.sob
;   ./bin/solvm --extension=build/extensions/net.so /tmp/server.sob 7777
;
; The protocol is one line of text, because a datagram is one message and the
; whole point of choosing UDP first was that framing is somebody else's problem:
;
;   "add 5"    add five to the total, and answer it
;   "get"      answer the total
;   "stop"     answer it once more and leave
;
; It replies to `packet:host` and `packet:port`, which is the thing the probe's
; socket could not do -- its read handed back the bytes and not the sender, so
; the first pair of programs written against it had the client write its own
; port inside the message. A packet that says where it came from is what turned
; two programs shouting into two programs talking.

port := system:arguments:size:greaterThan(#0):ifElse(
    { system:arguments:at(#1):asInteger(#10) },
    { #7777 }).

sock  := net:udp(port).
total := #0.
running := true.

"counter listening on ":display. net:port(sock):print.

; The loop the extension is shaped for: wait with a bound, and go round when
; nothing came. A blocking read would stop the machine, and a machine stopped
; inside a primitive is one `--steps` cannot reach.
{ running }:whileTrue({
    net:waitFor(sock, #1000):ifTrue({ | packet, text, reply |
        packet := net:receive(sock).
        packet:notNil:ifTrue({
            text := packet:text:trim.

            ; No `startsWith` in this language -- found by writing this
            ; program, and `indexOf` answering #1 is what it means anyway.
            reply := text:equals("get"):ifElse(
                { total:asString },
                { text:equals("stop"):ifElse(
                    { running := false. total:asString },
                    { text:indexOf("add "):equals(#1):ifElse(
                        { total := total:add(text:copyFrom(#5, text:size):asInteger(#10)).
                          total:asString },
                        { "?" }) }) }).

            "  {} from {}:{} -> {}":fill([text, packet:host, packet:port, reply]):print.
            net:send(sock, packet:host, packet:port, reply) }) }) }).

"counter stopping, total ":display. total:print.
