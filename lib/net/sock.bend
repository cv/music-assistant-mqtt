import Base

# A second handle on the same socket: one computation reads, another writes.
def Sock.dup(sock: Socket) -> IO(Socket & Result<&1, &1, U32 & String, Socket>):
  import "./effs/sock_dup.c"
  import "./effs/sock_dup.js"

# Shuts the socket down both ways; a reader on any of its handles sees the end.
def Sock.shutdown(sock: Socket) -> IO(Socket):
  import "./effs/sock_shutdown.c"
  import "./effs/sock_shutdown.js"
