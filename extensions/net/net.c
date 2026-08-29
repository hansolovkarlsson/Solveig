/* net.c -- UDP over IPv4, as an extension and not as a machine.
 *
 * Sockets are the capability this language kept saying it did not have. They
 * are here rather than in the VM on the argument
 * [ideas.md](../../docs/ideas.md#networking-and-sending-code-to-a-machine-that-is-already-running)
 * makes: a socket built in is a capability every script gets whether or not the
 * host meant to grant it, where a bundle is one a host names on the command
 * line and can decline to. The core stays the size it was.
 *
 *     solvm --extension=build/extensions/net.so server.sob
 *
 * **Five messages, and each one exists because a program asked for it.** The
 * first pair of programs written against the probe's socket -- the throwaway in
 * experiment/extension-probe that proved the mechanism -- could not answer each
 * other, because its `poll` handed back the bytes and not the sender. The
 * client had to write its own port *inside the message* for the server to parse
 * out. That is what `receive` answering a packet is for.
 *
 *     net:udp(#port)                        a socket, bound; #0 asks for any
 *     net:port(socket)                      the port it actually got
 *     net:send(socket, host, #port, text)   bytes written
 *     net:receive(socket)                   a packet, or nil if none is waiting
 *     net:waitFor(socket, #ms)              true if one arrived in time
 *
 * **A packet is an object with three slots** -- `host`, `port` and `text` -- so
 * a reply is `net:send(sock, packet:host, packet:port, "...")` and reads as
 * one. The language's own convention for an answer with fields is a dictionary,
 * which `system:terminalSize` uses; the extension surface promises
 * `sol_object_new` and `sol_array_new` and has no way to build a dictionary, so
 * this is an object. Worth noticing rather than working around silently: it is
 * the first thing a real extension has wanted that the promised surface does
 * not carry.
 *
 * **Waiting has a timeout, and that is the whole design.** A blocking `recv`
 * stops the only thread there is -- and worse, it stops the dispatch loop,
 * which is where `--steps` counts and where `--memory` is checked. A program
 * parked in a syscall inside a primitive is a program no limit can reach, so a
 * blocking read would quietly suspend the guarantee 6.33 was built to make.
 * `waitFor` bounds the wait, answers whether anything arrived, and hands the
 * decision back to a loop the program wrote.
 *
 * **What is not here**, each because nothing has asked yet: TCP, so no streams
 * and no `accept`; IPv6; and any name resolution -- `send` takes an address
 * that `inet_pton` accepts and not a hostname, because resolving one means
 * `getaddrinfo`, which blocks, which is the thing above.
 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "solum/extend.h"
#include "solum/gc.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

/* The collector calls this when the program lets go of a socket, and
   `sol_vm_free` calls it for one still held when the machine goes down --
   including when a limit took the program away mid-flight, which is exactly
   when an explicit `close` would not have run. So there is no `net:close`. */
static void close_socket(void *handle)
{
    close((int)(intptr_t)handle - 1);
}

/* A socket costs the program nothing the machine can measure: the kernel's
   buffers are not the heap. Zero says so, and inflating it to buy scheduling
   would make every `--memory` figure a lie. Descriptors are scarce in their own
   currency, which is what the collector's foreign pressure count is for. */
#define SOCKET_FOOTPRINT 0

/* **The handle is `fd + 1`, and that is not a flourish.** `sol_foreign_handle`
   answers NULL for a cell of the wrong kind or one already released, so a
   handle that is itself NULL cannot be told from a released one -- and file
   descriptor 0 is a real descriptor. It is standard input today and so never a
   socket, which is precisely the kind of reasoning that stops being true on the
   machine where the program was started with its input closed. */
static int socket_of(SolVM *vm, const char *message, SolValue value)
{
    void *handle = sol_foreign_handle(value, "socket");
    if (handle == NULL) {
        sol_vm_runtime_error(vm, "%s expects an open socket", message);
        return -1;
    }
    return (int)(intptr_t)handle - 1;
}

/* net:udp(#port) -- a bound UDP socket. #0 asks the system for a free port,
   which `net:port` then answers. Bound on every interface rather than on
   loopback, because two machines that need to talk is the whole point. */
static SolValue prim_udp(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_INT) {
        sol_vm_runtime_error(vm, "udp expects an integer port");
        return SOL_NIL_VAL;
    }
    int64_t port = args[0].as.integer;
    if (port < 0 || port > 65535) {
        sol_vm_runtime_error(vm, "udp: a port is 0 to 65535, got %lld",
                             (long long)port);
        return SOL_NIL_VAL;
    }

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { sol_vm_runtime_error(vm, "udp: no socket"); return SOL_NIL_VAL; }

    /* Non-blocking, so `receive` answers nil rather than stopping the machine.
       Waiting is `waitFor`, which is bounded and says so. */
    fcntl(fd, F_SETFL, O_NONBLOCK);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((unsigned short)port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        close(fd);
        sol_vm_runtime_error(vm, "udp: cannot bind port %lld", (long long)port);
        return SOL_NIL_VAL;
    }

    return SOL_FOREIGN_VAL(sol_foreign_new(vm, (void *)(intptr_t)(fd + 1),
                                           close_socket, "socket",
                                           SOCKET_FOOTPRINT));
}

/* net:port(socket) -- the port it is bound to, which is the only way to learn
   the one the system chose for `net:udp(#0)`. */
static SolValue prim_port(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1) {
        sol_vm_runtime_error(vm, "port expects a socket");
        return SOL_NIL_VAL;
    }
    int fd = socket_of(vm, "port", args[0]);
    if (fd < 0) return SOL_NIL_VAL;

    struct sockaddr_in addr;
    socklen_t len = sizeof addr;
    if (getsockname(fd, (struct sockaddr *)&addr, &len) < 0) {
        sol_vm_runtime_error(vm, "port: the socket is not bound");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(ntohs(addr.sin_port));
}

/* net:send(socket, "127.0.0.1", #port, "text") -- answers the bytes written.
   The address is written out; nothing here resolves a name. */
static SolValue prim_send(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 4 || args[1].type != SOL_STRING || args[2].type != SOL_INT ||
        args[3].type != SOL_STRING) {
        sol_vm_runtime_error(vm,
                             "send expects a socket, an address, a port and a string");
        return SOL_NIL_VAL;
    }
    int fd = socket_of(vm, "send", args[0]);
    if (fd < 0) return SOL_NIL_VAL;

    SolString *host = args[1].as.string;
    char dotted[INET_ADDRSTRLEN];
    if (host->length >= (int)sizeof dotted) {
        sol_vm_runtime_error(vm, "send: '%.*s' is not an address",
                             host->length, host->chars);
        return SOL_NIL_VAL;
    }
    memcpy(dotted, host->chars, (size_t)host->length);
    dotted[host->length] = '\0';

    struct sockaddr_in to;
    memset(&to, 0, sizeof to);
    to.sin_family = AF_INET;
    to.sin_port = htons((unsigned short)args[2].as.integer);
    if (inet_pton(AF_INET, dotted, &to.sin_addr) != 1) {
        sol_vm_runtime_error(vm, "send: '%s' is not an address -- a name is not "
                                 "resolved here", dotted);
        return SOL_NIL_VAL;
    }

    SolString *text = args[3].as.string;
    ssize_t n = sendto(fd, text->chars, (size_t)text->length, 0,
                       (struct sockaddr *)&to, sizeof to);
    if (n < 0) {
        sol_vm_runtime_error(vm, "send: the datagram was not sent");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL((int64_t)n);
}

/* A datagram carries at most 65,507 bytes over IPv4, so nothing here truncates
   one -- a short buffer would drop the rest of a packet silently, which is the
   worst kind of limit. Static rather than automatic because 64KB on the C stack
   is 64KB per re-entry of the dispatch loop, and safe as a static because the
   machine is single-threaded and says so
   ([3.11](../../docs/ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads)). */
static char datagram[65536];

/* Builds the packet `receive` answers: an object with `host`, `port` and
 * `text`.
 *
 * **One root, and it is load-bearing.** `sol_string_new` allocates through the
 * collector, and a cell held only in a C local is not a root -- so without the
 * push below, the packet is swept between being made and being filled. Under
 * `SOLUM_GC_STRESS=1` that is not theoretical: two hundred round trips answer
 * *object does not understand 'notNil'*, an object collected out from under the
 * program holding it.
 *
 * **And the strings need none, which was checked rather than assumed.** Rule 3
 * says nothing may hold a heap pointer across an allocation, and
 * `sol_object_define` looks like one -- but its slot comes from `malloc` and its
 * name is interned in the VM's permanent table, neither of which the collector
 * touches. So a string handed straight to `define` is stored before anything
 * can collect. Rooting them passes too, and is two lines saying something that
 * is not true.
 */
static SolValue packet_new(SolVM *vm, const char *host, int port,
                           const char *text, int length)
{
    SolObject *packet = sol_object_new(vm, vm->object_class);
    sol_gc_push_temp(vm, &packet->gc);

    sol_object_define(vm, packet, "host",
                      SOL_STRING_VAL(sol_string_new(vm, host, (int)strlen(host))));
    sol_object_define(vm, packet, "port", SOL_INT_VAL(port));
    sol_object_define(vm, packet, "text",
                      SOL_STRING_VAL(sol_string_new(vm, text, length)));

    sol_gc_pop_temp(vm);
    return SOL_OBJ_VAL(packet);
}

/* net:receive(socket) -- the packet waiting, or nil if none is. Never waits;
   `waitFor` is how a program waits. */
static SolValue prim_receive(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1) {
        sol_vm_runtime_error(vm, "receive expects a socket");
        return SOL_NIL_VAL;
    }
    int fd = socket_of(vm, "receive", args[0]);
    if (fd < 0) return SOL_NIL_VAL;

    struct sockaddr_in from;
    socklen_t len = sizeof from;
    ssize_t n = recvfrom(fd, datagram, sizeof datagram, 0,
                         (struct sockaddr *)&from, &len);
    if (n < 0) return SOL_NIL_VAL;            /* nothing waiting */

    char dotted[INET_ADDRSTRLEN] = "";
    inet_ntop(AF_INET, &from.sin_addr, dotted, sizeof dotted);
    return packet_new(vm, dotted, ntohs(from.sin_port), datagram, (int)n);
}

/* net:waitFor(socket, #ms) -- true if a datagram arrived inside the timeout.
 *
 * The bounded wait, and the reason the language can still stop this program:
 * `--steps` counts in the dispatch loop, so time spent inside a primitive is
 * time no limit is being checked. A timeout is what keeps that window a window.
 * `#0` asks whether one is waiting right now.
 */
static SolValue prim_wait_for(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 2 || args[1].type != SOL_INT) {
        sol_vm_runtime_error(vm, "waitFor expects a socket and a number of "
                                 "milliseconds");
        return SOL_NIL_VAL;
    }
    int fd = socket_of(vm, "waitFor", args[0]);
    if (fd < 0) return SOL_NIL_VAL;

    int64_t ms = args[1].as.integer;
    if (ms < 0) {
        sol_vm_runtime_error(vm, "waitFor: a wait is not negative");
        return SOL_NIL_VAL;
    }
    if (ms > 60000) ms = 60000;               /* a minute is long enough to be a bug */

    struct pollfd waiting = { .fd = fd, .events = POLLIN, .revents = 0 };
    int ready = poll(&waiting, 1, (int)ms);
    return SOL_BOOL_VAL(ready > 0 && (waiting.revents & POLLIN) != 0);
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;

    SolObject *net = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, net, "udp",     prim_udp);
    sol_object_define_primitive(vm, net, "port",    prim_port);
    sol_object_define_primitive(vm, net, "send",    prim_send);
    sol_object_define_primitive(vm, net, "receive", prim_receive);
    sol_object_define_primitive(vm, net, "waitFor", prim_wait_for);
    sol_vm_set_global(vm, "net", SOL_OBJ_VAL(net));
    return 0;
}
