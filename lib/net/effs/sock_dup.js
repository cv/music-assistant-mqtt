// Socket handles: not supported on the JS lane.
function sock_dup(socket) {
  return [socket, io_fail(95)]; // EOPNOTSUPP
}

io_eff(CID(Sock.dup), sock_dup);
