import Base

# The wall clock, in seconds since 1970 (IO.now counts milliseconds from an arbitrary start, so it
# measures intervals but can't date anything).
def Clock.unix() -> IO(U32):
  import "./effs/clock_unix.c"
  import "./effs/clock_unix.js"
