// Socket handles
// ==============
//
// Sock.dup(s) answers a second handle on the same socket (dup(2), close-on-
// exec), so one
// computation can read while another writes. Sock.shutdown(s) shuts both
// directions down (shutdown(2)): a reader blocked on any handle of the socket
// wakes with end-of-stream. Both hand the original handle back.

Term sock_dup_run(Env e, Term* f, IoWork* w) {
  int  d = fcntl((int)io_hand_v(f[0]), F_DUPFD_CLOEXEC, 0);
  Term r = d < 0 ? io_fail(e, (u32)errno, NULL) : io_done(e, io_hand(d));
  return io_tup(e, f[0], r);
}

static void __attribute__((constructor)) sock_dup_use(void) {
  io_eff(CID(Sock.dup), sock_dup_run);
}
