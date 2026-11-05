// The wall clock
// ==============
//
// Clock.unix() is time(NULL) as a U32: seconds since 1970 (good until 2106). Never fails.

#include <time.h>

Term clock_unix_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)time(NULL);
}

static void __attribute__((constructor)) clock_unix_use(void) {
  io_eff(CID(Clock.unix), clock_unix_run);
}
