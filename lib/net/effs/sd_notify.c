// systemd notifications
// ======================
//
// Sd.notify(msg) sends msg (e.g. "WATCHDOG=1") to systemd's notify socket
// ($NOTIFY_SOCKET), as sd_notify(3) does; without the variable (not run by
// systemd, or on the Mac) it does nothing. Never fails: a missed watchdog ping
// is what the watchdog is for.

#include <stddef.h>
#include <sys/socket.h>
#include <sys/un.h>

Term sd_notify_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* msg  = io_cstr(e, f[0], &n);
  const char* path = getenv("NOTIFY_SOCKET");
  if (path != NULL && path[0] != 0 && !io_nul(msg, n)) {
    struct sockaddr_un a;
    memset(&a, 0, sizeof(a));
    a.sun_family = AF_UNIX;
    size_t len = strlen(path);
    if (len < sizeof(a.sun_path)) {
      memcpy(a.sun_path, path, len);
      if (a.sun_path[0] == '@') {
        a.sun_path[0] = 0;  // abstract namespace
      }
      // One datagram socket for the whole run (the main loop notifies on
      // every pass); reopened if a send fails.
      static int fd = -1;
      if (fd < 0) {
        fd = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (fd >= 0) {
          fcntl(fd, F_SETFD, FD_CLOEXEC);
        }
      }
      if (fd >= 0 && sendto(fd, msg, (size_t)n, 0, (struct sockaddr*)&a, (socklen_t)(offsetof(struct sockaddr_un, sun_path) + len)) < 0) {
        close(fd);
        fd = -1;
      }
    }
  }
  free(msg);
  return term_pak(CID(Unit), 0);
}

static void __attribute__((constructor)) sd_notify_use(void) {
  io_eff(CID(Sd.notify), sd_notify_run);
}
