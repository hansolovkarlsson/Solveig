/* ext_net.c -- UDP, standing in for "a networking library for multiplayer".
 *
 * **Rewritten once SolForeign existed, and that is the point of keeping it.**
 * The first version handed a socket back as a plain integer, which was written
 * that way deliberately to make the gap visible: nothing closed it when the
 * program was stopped, it was not counted against --memory, and a program could
 * invent one and pass it to `close`. All three arguments for the foreign cell
 * came from this file.
 *
 * Now the socket is a resource the machine holds. The differences are small and
 * all of them are the point:
 *
 *   - `net:udp` answers a `<socket>` rather than a number
 *   - every primitive asks `sol_foreign_handle(v, "socket")` instead of casting
 *   - `net:close` is gone; the collector closes it, and so does VM teardown,
 *     which is what saves a program a limit took away mid-flight
 */
#include <arpa/inet.h>
#include <stdint.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "solum/embed.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

/* The collector calls this: when the program lets go of the socket, and again
   for anything still held when the machine goes down. A program that was
   stopped by --steps still gets its sockets closed, which is the guarantee an
   explicit close could not make. */
static void close_socket(void *handle)
{
    close((int)(intptr_t)handle);
}

/* Sockets are small and the kernel's buffers are not the program's, so there is
   nothing honest to declare as a footprint. Zero says so. */
#define SOCKET_FOOTPRINT 0

/* Every primitive below asks for the handle this way, so a window from some
   other extension cannot arrive here and be read as a file descriptor. -1 is
   not a socket, and is what a closed or wrong-kind value answers as. */
static int socket_of(SolVM *vm, const char *message, SolValue value)
{
    void *handle = sol_foreign_handle(value, "socket");
    if (handle == NULL) {
        sol_vm_runtime_error(vm, "%s expects an open socket", message);
        return -1;
    }
    return (int)(intptr_t)handle;
}

/* net:udp(#port) -- 0 asks the system for a free one. Answers the socket. */
static SolValue prim_udp(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_INT) {
        sol_vm_runtime_error(vm, "udp expects an integer port");
        return SOL_NIL_VAL;
    }
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { sol_vm_runtime_error(vm, "udp: no socket"); return SOL_NIL_VAL; }
    fcntl(fd, F_SETFL, O_NONBLOCK);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((unsigned short)args[0].as.integer);
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        close(fd);
        sol_vm_runtime_error(vm, "udp: cannot bind");
        return SOL_NIL_VAL;
    }
    return SOL_FOREIGN_VAL(sol_foreign_new(vm, (void *)(intptr_t)fd,
                                           close_socket, "socket",
                                           SOCKET_FOOTPRINT));
}

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
        sol_vm_runtime_error(vm, "port: not a socket");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(ntohs(addr.sin_port));
}

/* net:send(#socket, #port, "text") -- to loopback, which is all a demo needs. */
static SolValue prim_send(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 3 || args[1].type != SOL_INT || args[2].type != SOL_STRING) {
        sol_vm_runtime_error(vm, "send expects a socket, a port and a string");
        return SOL_NIL_VAL;
    }
    int fd = socket_of(vm, "send", args[0]);
    if (fd < 0) return SOL_NIL_VAL;

    struct sockaddr_in to;
    memset(&to, 0, sizeof to);
    to.sin_family = AF_INET;
    to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    to.sin_port = htons((unsigned short)args[1].as.integer);
    SolString *s = args[2].as.string;
    ssize_t n = sendto(fd, s->chars, (size_t)s->length, 0,
                       (struct sockaddr *)&to, sizeof to);
    return SOL_INT_VAL((int64_t)n);
}

/* net:poll(#socket) -- a datagram if one is waiting, nil if none is. */
static SolValue prim_poll(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1) {
        sol_vm_runtime_error(vm, "poll expects a socket");
        return SOL_NIL_VAL;
    }
    int fd = socket_of(vm, "poll", args[0]);
    if (fd < 0) return SOL_NIL_VAL;

    char buf[2048];
    ssize_t n = recv(fd, buf, sizeof buf, 0);
    if (n <= 0) return SOL_NIL_VAL;
    return SOL_STRING_VAL(sol_string_new(vm, buf, (int)n));
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;
    SolObject *net = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, net, "udp",   prim_udp);
    sol_object_define_primitive(vm, net, "port",  prim_port);
    sol_object_define_primitive(vm, net, "send",  prim_send);
    sol_object_define_primitive(vm, net, "poll",  prim_poll);
    /* No `close`. The collector closes a socket the program has let go of, and
       VM teardown closes one it was still holding -- including when a limit
       took the program away, which is exactly when an explicit close would not
       have run. */
    sol_vm_set_global(vm, "net", SOL_OBJ_VAL(net));
    return 0;
}
