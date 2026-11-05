// See sock_dup.c.

#include <sys/socket.h>

Term sock_shutdown_run(Env e, Term* f, IoWork* w) {
  shutdown((int)io_hand_v(f[0]), SHUT_RDWR);
  return f[0];
}

static void __attribute__((constructor)) sock_shutdown_use(void) {
  io_eff(CID(Sock.shutdown), sock_shutdown_run);
}
