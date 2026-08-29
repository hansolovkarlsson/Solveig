# net — UDP sockets, as an extension

*The first bundle this repository ships, and the first two Solveig programs
written to talk to each other.*

```sh
make                                   # builds build/extensions/net.so

./bin/solas extensions/net/server.sol -o /tmp/server.sob
./bin/solas extensions/net/client.sol -o /tmp/client.sob

./bin/solvm --extension=build/extensions/net.so /tmp/server.sob 7777 &
./bin/solvm --extension=build/extensions/net.so /tmp/client.sob 7777 "add 5" get stop
```

```text
"add 5 -> 5"
"get -> 5"
"stop -> 5"
```

`make install` puts it beside the library, at `$(PREFIX)/lib/solum/net.so`.
Nothing looks for it there — `--extension=` takes a path, and a host that did
not name one gets no networking — so installing it is only so that a path exists
to name.

**It is an extension and not a machine.** A socket built into the VM is a
capability every script gets whether or not the host meant to grant it; a bundle
is one a host names on a command line and can decline to name. The core stays
the size it was, which is the argument
[ideas.md](../../docs/ideas.md#networking-and-sending-code-to-a-machine-that-is-already-running)
makes and the reason this is here rather than in `builtins.c`.

**It lives in this tree where GTK and SDL2 do not**, and the difference is the
front page's sentence rather than a policy: a bundle needing a toolkit installed
would make *no dependencies beyond a C11 compiler and `make`* false, and sockets
need POSIX, which every `dlopen` and `fork` here already assumes.

## The five messages

| | |
| --- | --- |
| `net:udp(#port)` | a bound UDP socket; `#0` asks the system for a free port |
| `net:port(socket)` | the port it actually got |
| `net:send(socket, "127.0.0.1", #port, text)` | bytes written |
| `net:receive(socket)` | the packet waiting, or **nil**; never waits |
| `net:waitFor(socket, #ms)` | **true** if one arrived inside the timeout |

There is no `close`. The collector closes a socket the program lets go of, and
teardown closes one it was still holding — including when a limit took the
program away mid-flight, which is exactly when an explicit close would not have
run.

**A packet is an object with `host`, `port` and `text`**, so a reply is
`net:send(sock, packet:host, packet:port, "...")` and reads as one.

## What writing the programs decided

**A packet has to say who sent it.** The socket in
[the extension probe](../../experiment/extension-probe/) read with `recv`, so it
handed back the bytes alone — and the first client and server written against it
could not answer each other. The client had to write its own port *inside the
message* for the server to parse out. `recvfrom` and a packet with a `host` and
a `port` is what turned two programs shouting into two programs talking.

**Waiting has a timeout, and that is the design.** A blocking read stops the only
thread there is, and worse, it stops the dispatch loop — which is where `--steps`
counts and `--memory` is checked. A program parked in a syscall inside a
primitive is a program no limit can reach, so a blocking read would quietly
suspend the guarantee
[6.33](../../docs/COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done)
was built to make. `waitFor` bounds the wait and hands the decision back to a
loop the program wrote.

**A packet is an object because the surface has no dictionary.** The language's
own convention for an answer with fields is one — `system:terminalSize` gives
`"rows"` and `"columns"` — and the extension surface promises `sol_object_new`
and `sol_array_new` and nothing that builds a dictionary. This is the first
thing a real extension has wanted that
[the contract](../../docs/extensions.md) does not carry.

**The handle is `fd + 1`.** `sol_foreign_handle` answers NULL for a cell of the
wrong kind or one already released, so a handle that is itself NULL cannot be
told from a released one — and descriptor 0 is a real descriptor. It is standard
input today and so never a socket, which is the kind of reasoning that stops
being true on the machine where the program was started with its input closed.

**One root, proved.** `packet_new` allocates three cells, and the object is
rooted with `sol_gc_push_temp` because `sol_string_new` collects. Take the root
out and `tests/test_cli.c` fails under `SOLUM_GC_STRESS=1` with *object does not
understand 'notNil'* — an object swept between being made and being filled. The
strings need no root, and that was checked rather than assumed:
`sol_object_define` takes its slot from `malloc` and interns its name in a
permanent table, so nothing between the string and its slot can collect.

## What is not here

TCP, so no streams and no `accept`. IPv6. And any name resolution — `send` takes
an address `inet_pton` accepts and not a hostname, because resolving one means
`getaddrinfo`, which blocks, which is the thing `waitFor` exists to avoid.

Each is absent because no program has asked yet, which is the rule the rest of
this language was built by.
