import Base

# Connects to host:port over TCP, where host is a name ("mac.lan") or an
# IPv4/IPv6 address. Answers an ordinary Base Socket.
def Net.connect(host: String, port: U32) -> IO(Result<&1, &1, U32 & String, Socket>):
  import "./effs/net_connect.c"
  import "./effs/net_connect.js"
