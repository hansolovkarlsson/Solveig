# net — UDP sockets

*The reference for the bundle in [extensions/net](../extensions/net/), and for
the client and server that come with it.*

This is not part of the language. `solvm` has no networking and gains it only
when a host asks for it by name:

```text
make                                    # builds build/extensions/net.so
solvm --extension=build/extensions/net.so program.sob
```

Without that flag a program that mentions `net` fails at the line that first
names it — *undefined name 'net'* — which is the whole arrangement working: the
capability exists and granting it is a decision somebody takes on a command
line. Why it is an extension rather than a machine, and why it may live in this
repository when GTK and SDL2 may not, is in
[extensions/net/README.md](../extensions/net/README.md).

Everything here is IPv4 UDP. There is no TCP, no IPv6 and no name resolution —
see [What is not here](#what-is-not-here).

## The five messages

| | |
| --- | --- |
| [`net:udp(#port)`](#netudpport) | a bound socket |
| [`net:port(socket)`](#netportsocket) | the port it is bound to |
| [`net:send(socket, host, #port, text)`](#netsendsocket-host-port-text) | bytes written |
| [`net:receive(socket)`](#netreceivesocket) | a packet, or **nil** |
| [`net:waitFor(socket, #ms)`](#netwaitforsocket-ms) | **true** if one arrived in time |

There is no `close`, and that is deliberate. The collector closes a socket when
the program lets go of it, and machine teardown closes one still held —
including when a limit took the program away mid-flight, which is exactly when
an explicit close would not have run.

### `net:udp(#port)`

Answers a bound UDP socket. `#0` asks the system for a free port, which
`net:port` then reports. It binds on every interface, not on loopback, so
another machine can reach it.

```text
sock := net:udp(#7777).       ; a known port, for something to be found at
sock := net:udp(#0).          ; any free one, for something doing the finding
```

The socket is non-blocking, which is why `receive` answers **nil** rather than
waiting and why waiting is a message of its own.

| refuses | |
| --- | --- |
| `net:udp("7777")` | *udp expects an integer port* |
| `net:udp(#70000)` | *udp: a port is 0 to 65535, got 70000* |
| a port already in use | *udp: cannot bind port 7777* |

### `net:port(socket)`

The port the socket is bound to, as an integer. The only way to learn the one
the system chose for `net:udp(#0)`.

| refuses | |
| --- | --- |
| anything that is not an open socket | *port expects an open socket* |

### `net:send(socket, host, #port, text)`

Sends one datagram and answers how many bytes went out. `host` is an address
written out — `"127.0.0.1"` — and never a name.

```text
net:send(sock, "127.0.0.1", #7777, "add 5").      ; answers #5
```

A datagram is one message: what one `send` writes, one `receive` reads, whole or
not at all. Nothing here frames anything, which is the half of TCP that UDP
hands back to you and the reason the example's protocol is one line of text.

| refuses | |
| --- | --- |
| wrong arity or types | *send expects a socket, an address, a port and a string* |
| `net:send(sock, "nope", #1, "x")` | *send: 'nope' is not an address -- a name is not resolved here* |
| a datagram the system would not take | *send: the datagram was not sent* |

### `net:receive(socket)`

The packet waiting, or **nil** when none is. **It never waits.**

A packet is an object with three slots:

| | |
| --- | --- |
| `packet:host` | the address it came from, as a string |
| `packet:port` | the port it came from, as an integer |
| `packet:text` | the bytes, as a string |

So a reply is `net:send(sock, packet:host, packet:port, "...")` and reads as
one. That the packet says where it came from is the thing the socket in
[the extension probe](../experiment/extension-probe/) could not do, and it is
what separates two programs talking from two programs shouting.

A datagram carries at most 65,507 bytes over IPv4 and nothing here truncates
one.

| refuses | |
| --- | --- |
| anything that is not an open socket | *receive expects an open socket* |

### `net:waitFor(socket, #ms)`

Answers **true** if a datagram arrived inside the timeout and **false** if none
did. `#0` asks whether one is waiting right now. Waits of more than a minute are
treated as a minute.

```text
net:waitFor(sock, #2000):ifElse(
    { net:receive(sock):text:print },
    { "no answer in 2s":print }).
```

**Why a timeout rather than a blocking read.** A blocking read stops the only
thread there is — and it stops the *dispatch loop*, which is where `--steps`
counts and where `--memory` is checked. A program parked inside a primitive is a
program no limit can reach, so a blocking read would suspend the guarantee
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
makes for as long as the peer stayed silent. A bounded wait keeps that window a
window, and hands the decision about going round again back to the program.

| refuses | |
| --- | --- |
| wrong arity or types | *waitFor expects a socket and a number of milliseconds* |
| `net:waitFor(sock, #-1)` | *waitFor: a wait is not negative* |

## The shape a program takes

Every program using this ends up the same way, and it is worth seeing once:

```text
{ running }:whileTrue({
    net:waitFor(sock, #1000):ifTrue({ | packet |
        packet := net:receive(sock).
        packet:notNil:ifTrue({ ... }) }) }).
```

Wait with a bound; if something came, take it; go round. The `notNil` is not
superstition — `waitFor` says a datagram was readable, and by the time
`receive` runs it may have been discarded, so the two are separate questions and
the program asks both.

## The example

Two programs, and between them a counter that lives in the server.

```text
solas extensions/net/server.sol -o /tmp/server.sob
solas extensions/net/client.sol -o /tmp/client.sob

solvm --extension=build/extensions/net.so /tmp/server.sob 7777 &
solvm --extension=build/extensions/net.so /tmp/client.sob 7777 "add 5" "add 37" get stop
```

```text
client                        server
"add 5 -> 5"                  counter listening on #7777
"add 37 -> 42"                  add 5 from 127.0.0.1:60338 -> 5
"get -> 42"                     add 37 from 127.0.0.1:60338 -> 42
"stop -> 42"                    get from 127.0.0.1:60338 -> 42
                                stop from 127.0.0.1:60338 -> 42
                              counter stopping, total #42
```

**The protocol is one line of text**, because a datagram is one message and
framing is the problem UDP hands back:

| | |
| --- | --- |
| `add 5` | add five to the total, and answer it |
| `get` | answer the total |
| `stop` | answer it once more and leave |

**The client binds `#0` and the server answers whatever it was given.** Nothing
in the client has to know its own address for a reply to find it, which is the
packet's `host` and `port` doing their job.

**A reply that never comes is an ordinary outcome.** UDP promises nothing, so
the client waits two seconds and says *no answer in 2s* rather than waiting
forever. A program that needs delivery has to arrange it itself — which is a
fair summary of what TCP is for, and is why the absence below is a real one
rather than a shrug.

## What is not here

| | |
| --- | --- |
| **TCP** | no streams, no `accept`, and nothing that retries |
| **IPv6** | `AF_INET` only |
| **Name resolution** | `send` takes an address `inet_pton` accepts. Resolving a name means `getaddrinfo`, which blocks — the thing `waitFor` exists to avoid |
| **Broadcast and multicast** | no socket options are exposed at all |

Each is absent because no program has asked, which is the rule the rest of this
language was built by. The entry that would grow is
[ideas.md's networking entry](ideas.md#networking-and-sending-code-to-a-machine-that-is-already-running),
whose other half — sending *code* to a machine that is already running — is
untouched and wants
[3.4](ROADMAP.md#34-no-compatibility-across-sob-versions) and
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
first.

## What holds this page honest

Every block above is a transcript rather than a checked claim, because the
checker runs Solum and these need a bundle loaded. What stands behind them
instead:

- `test_the_net_extension_carries_a_datagram` in `tests/test_cli.c` runs a real
  round trip through the real binary and the real bundle, under
  `SOLUM_GC_STRESS=1`, and asserts that the packet names the sender.
- Every refusal quoted above was produced by running it.
- The client and server are in the tree and can be run as written.
