// Socket handles: not supported on the JS lane.
function sock_shutdown(socket) {
  return socket;
}

io_eff(CID(Sock.shutdown), sock_shutdown);
