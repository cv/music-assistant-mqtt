// Network connections by name: not supported on the JS lane.
function net_connect(host, port) {
  return io_fail(95); // EOPNOTSUPP
}

io_eff(CID(Net.connect), net_connect);
