import Base
import ./lib/net/run.bend as Rn
import ./lib/net/sd.bend as Sd
import ./lib/net/clock.bend as Ck
import ./lib/wire/bytes.bend as B
import ./lib/bridge/conf.bend as C
import ./lib/bridge/core.bend as Core
import ./lib/app/main.bend as App
# music-assistant-mqtt: Music Assistant's players and plays, published to MQTT.
#
#   mam [config]     (config: /etc/music-assistant-mqtt.conf)
#
# Reads the config once (problems are printed; without a broker or a token it exits with status
# 2, which a supervisor shouldn't restart), then runs sessions forever with the core's backoff
# between them (lib/app/main.bend runs one).

def version() -> String:
  "0.2.0"

def max_config() -> U32:
  65536

# Waits left ms in slices of at most 10 s, telling the watchdog after each.
def sleep_fed(fuel: Nat, +left: U32) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.sleep(Bool.pick(U32, (left > 10000 : U32), 10000, left))
        Sd.Sd.notify("WATCHDOG=1")
        sleep_fed(p, Bool.pick(U32, (left > 10000 : U32), (left - 10000 : U32), 0))

# Across sessions: the backoff step, the process's life, the config, the plays left waiting.
type Loop is Data:
  Loop{step: Nat, life: App.Life, conf: C.Conf, held: List<&2, Core.Pending>}

def again.ended(e: App.Ended, +step: Nat, life: App.Life, +conf: C.Conf) -> IO(Loop):
  match e:
    case App.Ended{+up, +why, left}:
      +next = Core.backoff.next(step, up)
      do IO<Loop>:
        IO.print("session ended: " ++ why ++ "; next in " ++ U32.show(Core.backoff.wait(next))
          ++ " ms")
        sleep_fed(7n, Core.backoff.wait(next))
        return Loop{next, App.life.ended(life, why), conf, left}

def again.step(l: Loop) -> IO(Loop):
  match l:
    case Loop{+step, life, +conf, held}:
      +l1 = App.life.begin(life)
      do IO<Loop>:
        e : App.Ended <- App.session(conf, l1, held)
        again.ended(e, step, l1, conf)

def again.live(l: Loop) -> Rn.Next<Loop>:
  Rn.Go{l}

def problems.print(ps: List<&2, C.Problem>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case p <> t:
      do IO<Unit>:
        IO.print(C.problem.text(p))
        problems.print(t)

def run(+conf: C.Conf, +started: U32) -> IO(Unit):
  do IO<Unit>:
    IO.print("music-assistant-mqtt " ++ version() ++ ": " ++ C.summary(conf))
    l : Loop <- Rn.Run.forever(~Loop, ~again.live, ~again.step,
      Loop{0n, App.Life{version(), started, 0, ""}, conf, Nil{}})
    return Unit{}

def start.if_ok(fatal: Bool, +conf: C.Conf) -> IO(Unit):
  match fatal:
    case True{}:
      do IO<Unit>:
        IO.print("music-assistant-mqtt: can't start without those")
        IO.exit(2)
    case False{}:
      do IO<Unit>:
        u : U32 <- Ck.Clock.unix()
        run(conf, u)

def start(r: C.Read) -> IO(Unit):
  match r:
    case C.Read{+conf, +ps}:
      do IO<Unit>:
        problems.print(ps)
        start.if_ok(C.fatal(ps), conf)

def load.got(+path: String, p: File & Result<&1, &1, U32 & String, B.Bytes>) -> IO(Unit):
  (f, r) = p
  match r:
    case Done{+bs}:
      do IO<Unit>:
        File.close(f)
        start(C.parse(bs))
    case Fail{_}:
      do IO<Unit>:
        File.close(f)
        IO.print("config " ++ path ++ ": unreadable")
        IO.exit(2)

def load(+path: String, r: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match r:
    case Done{f}:
      do IO<Unit>:
        p : File & Result<&1, &1, U32 & String, B.Bytes> <- File.read_bytes(f, max_config())
        load.got(path, p)
    case Fail{_}:
      do IO<Unit>:
        IO.print("config " ++ path ++ ": not found")
        IO.exit(2)

# The config path: the first argument (args[0] is the program).
def config_path(args: List<&1, String>) -> String:
  match args:
    case Nil{}:
      "/etc/music-assistant-mqtt.conf"
    case _ <> t:
      match t:
        case Nil{}:
          "/etc/music-assistant-mqtt.conf"
        case a <> _:
          a

def main.with(+path: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    load(path, r)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    main.with(config_path(args))
