// Network connections by name
// ============================
//
// Net.connect(host, port) connects a TCP stream socket to a host name or an
// address (IPv4 or IPv6), resolving names with getaddrinfo (IPv4 first), and answers it as
// a Base `Socket`, like TCP.connect (which takes IPv4 literals only). The
// lookup blocks the event loop (glibc's resolver gives up after a few seconds
// per server; the systemd watchdog covers a stuck one); the connect itself
// does not, and gives up after NET_CONNECT_MS (ETIMEDOUT). Sockets are
// close-on-exec. Mirrors bend2/effs/tcp_connect.c.

#include <netdb.h>

#define NET_CONNECT_MS 10000

static Term net_connect_more(Env e, IoWork* w) {
  int       fd  = (int)w->made;
  int       err = (int)w->code;
  socklen_t len = sizeof(err);
  if (err == EINPROGRESS) {
    // Woken either because the socket became writable (connected or failed)
    // or because the deadline passed: only a writable socket has an answer.
    struct pollfd p = {fd, POLLOUT, 0};
    int ready;
    do {
      ready = poll(&p, 1, 0);
    } while (ready < 0 && errno == EINTR);
    if (ready <= 0) {
      err = ETIMEDOUT;
    } else if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)) {
      err = errno;
    }
  }
  if (err != 0 && fd >= 0) {
    close(fd);
  }
  return err != 0 ? io_fail(e, (u32)err, NULL) : io_done(e, io_hand(fd));
}

Term net_connect_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* host = io_cstr(e, f[0], &n);
  u32   port = (u32)f[1];
  char  serv[16];
  snprintf(serv, sizeof(serv), "%u", port);
  struct addrinfo hints, *res = NULL;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family   = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  int bad = io_nul(host, n) || n == 0 || port > 65535;
  int gai = bad ? EAI_NONAME : getaddrinfo(host, serv, &hints, &res);
  free(host);
  if (gai != 0) {
    return io_fail(e, (u32)(bad ? EINVAL : gai == EAI_SYSTEM ? errno : EHOSTUNREACH), NULL);
  }
  // Prefer IPv4 (brokers on a LAN often listen on IPv4 only).
  struct addrinfo* at = res;
  for (struct addrinfo* r = res; r != NULL; r = r->ai_next) {
    if (r->ai_family == AF_INET) {
      at = r;
      break;
    }
  }
  int fd = socket(at->ai_family, at->ai_socktype, at->ai_protocol);
  if (fd >= 0 && (fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) < 0 || fcntl(fd, F_SETFD, FD_CLOEXEC) < 0)) {
    close(fd);
    fd = -1;
  }
  w->made = fd;
  io_sys_end(w, fd < 0 ? fd : connect(fd, at->ai_addr, at->ai_addrlen));
  freeaddrinfo(res);
  return w->code == EINPROGRESS
    ? io_wait_on(w, fd, POLLOUT, io_until(NET_CONNECT_MS), net_connect_more) : net_connect_more(e, w);
}

static void __attribute__((constructor)) net_connect_use(void) {
  io_eff(CID(Net.connect), net_connect_run);
}
