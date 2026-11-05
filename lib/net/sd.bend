import Base

# Tells systemd something, e.g. "WATCHDOG=1" (no-op outside systemd).
def Sd.notify(msg: String) -> IO(Unit):
  import "./effs/sd_notify.c"
  import "./effs/sd_notify.js"
