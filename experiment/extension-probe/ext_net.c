/* ext_net.c -- UDP, standing in for "a networking library for multiplayer".
 *
 * It hands a socket back to Solum as a plain integer, which is exactly the
 * thing SolForeign is for and exactly what is wrong without it: nothing closes
 * it when the program is stopped, it is not counted against --memory, and a
 * program can invent one. Written this way on purpose, so the gap is visible
 * rather than described.
 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "solum/embed.h"
#include "solum/object.h"
#include "solum/value.h"
#include "solum/vm.h"

/* net:udp(#port) -- 0 asks the system for a free one. Answers the port bound. */
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
    return SOL_INT_VAL(fd);
}

static SolValue prim_port(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_INT) {
        sol_vm_runtime_error(vm, "port expects a socket");
        return SOL_NIL_VAL;
    }
    struct sockaddr_in addr;
    socklen_t len = sizeof addr;
    if (getsockname((int)args[0].as.integer, (struct sockaddr *)&addr, &len) < 0) {
        sol_vm_runtime_error(vm, "port: not a socket");
        return SOL_NIL_VAL;
    }
    return SOL_INT_VAL(ntohs(addr.sin_port));
}

/* net:send(#socket, #port, "text") -- to loopback, which is all a demo needs. */
static SolValue prim_send(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 3 || args[0].type != SOL_INT || args[1].type != SOL_INT ||
        args[2].type != SOL_STRING) {
        sol_vm_runtime_error(vm, "send expects a socket, a port and a string");
        return SOL_NIL_VAL;
    }
    struct sockaddr_in to;
    memset(&to, 0, sizeof to);
    to.sin_family = AF_INET;
    to.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    to.sin_port = htons((unsigned short)args[1].as.integer);
    SolString *s = args[2].as.string;
    ssize_t n = sendto((int)args[0].as.integer, s->chars, (size_t)s->length, 0,
                       (struct sockaddr *)&to, sizeof to);
    return SOL_INT_VAL((int64_t)n);
}

/* net:poll(#socket) -- a datagram if one is waiting, nil if none is. */
static SolValue prim_poll(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    if (argc != 1 || args[0].type != SOL_INT) {
        sol_vm_runtime_error(vm, "poll expects a socket");
        return SOL_NIL_VAL;
    }
    (void)self;
    char buf[2048];
    ssize_t n = recv((int)args[0].as.integer, buf, sizeof buf, 0);
    if (n <= 0) return SOL_NIL_VAL;
    return SOL_STRING_VAL(sol_string_new(vm, buf, (int)n));
}

static SolValue prim_close(SolVM *vm, SolValue self, SolValue *args, int argc)
{
    (void)self;
    if (argc != 1 || args[0].type != SOL_INT) {
        sol_vm_runtime_error(vm, "close expects a socket");
        return SOL_NIL_VAL;
    }
    close((int)args[0].as.integer);
    return SOL_NIL_VAL;
}

int sol_extension_init(SolVM *vm, int abi)
{
    if (abi != 1) return -1;
    SolObject *net = sol_object_new(vm, vm->object_class);
    sol_object_define_primitive(vm, net, "udp",   prim_udp);
    sol_object_define_primitive(vm, net, "port",  prim_port);
    sol_object_define_primitive(vm, net, "send",  prim_send);
    sol_object_define_primitive(vm, net, "poll",  prim_poll);
    sol_object_define_primitive(vm, net, "close", prim_close);
    sol_vm_set_global(vm, "net", SOL_OBJ_VAL(net));
    return 0;
}
