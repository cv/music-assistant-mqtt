import Base
import ../net/run.bend as Rn
import ../net/net.bend as Nt
import ../net/sock.bend as Sk
import ../net/sd.bend as Sd
import ../net/clock.bend as Ck
import ../wire/bytes.bend as B
import ../wire/mqtt.bend as M
import ../wire/ws.bend as W
import ../ma/api.bend as Api
import ../ma/link.bend as L
import ../bridge/conf.bend as C
import ../bridge/core.bend as Core
import ../bridge/topics.bend as T
import ./readers.bend as R
# One session as I/O: connect the broker, start its reader, then carry out the core's steps
# (lib/bridge/core.bend) until it ends: sends, opening Music Assistant's link, the plays file, the
# health reports, the log. It decides nothing itself; what can't be decided purely (a failed
# send, a failed connect) goes back to the core as an input.

# The process's life across sessions: the version, when it started (Unix s), how many sessions
# it ran, why the last one ended.
type Life is Data:
  Life{version: String, started: U32, sessions: U32, last_end: String}

def life.begin(l: Life) -> Life:
  match l:
    case Life{v, s, n, e}:
      Life{v, s, (n + 1 : U32), e}

def life.ended(l: Life, why: String) -> Life:
  match l:
    case Life{v, s, n, _}:
      Life{v, s, n, why}

def life.last_end(l: Life) -> String:
  match l:
    case Life{_, _, _, e}:
      e

# How a session ended: whether it went live, why, and the plays it left waiting (their lookups
# never answered; the next session looks them up again).
type Ended is Data:
  Ended{up: Bool, why: String, left: List<&2, Core.Pending>}

# Music Assistant's socket, once opened.
type Ma is Type:
  MaClosed{}
  MaOpen{sock: Socket}

# inbox: inputs for the core still to run; tick: when the last tick ran (ms).
type Loop is Data:
  Loop{inbox: List<&2, Core.Input>, tick: U32}

type Main is Type:
  Main{mq: Socket, ma: Ma, events: Chan(R.Ev), core: Core.Core, life: Life, loop: Loop}

# Time
# ----

def time.of(+t: Nat, +unix: U32) -> Core.Time:
  Core.Time{U32.from_nat(t), unix}

def send_ms() -> U32:
  10000

def push(l: Loop, i: Core.Input) -> Loop:
  match l:
    case Loop{inbox, tick}:
      Loop{List.append(&2, Core.Input, inbox, [i]), tick}

# Sending
# -------

def sent.mq(p: Socket & Poll<&1, &1, Result<&1, &1, (U32 & String) & B.Bytes, Unit>, B.Bytes>,
    ma: Ma, events: Chan(R.Ev), core: Core.Core, life: Life, loop: Loop) -> IO(Main):
  (mq, r) = p
  match r:
    case Ready{Done{_}}:
      IO.pure(Main, Main{mq, ma, events, core, life, loop})
    case _:
      IO.pure(Main, Main{mq, ma, events, core, life, push(loop, Core.MqLost{})})

# Bytes to the broker; a send that fails (or takes over 10 s) loses the broker.
def send.mq(m: Main, bs: B.Bytes) -> IO(Main):
  match m:
    case Main{mq, ma, events, core, life, loop}:
      do IO<Main>:
        p : Socket & Poll<&1, &1, Result<&1, &1, (U32 & String) & B.Bytes, Unit>, B.Bytes> <-
          TCP.try_send_bytes(mq, bs, send_ms())
        sent.mq(p, ma, events, core, life, loop)

def ma.lost(why: String) -> Core.Input:
  Core.MaHeard{L.Lost{why}}

def sent.ma(p: Socket & Poll<&1, &1, Result<&1, &1, (U32 & String) & B.Bytes, Unit>, B.Bytes>,
    mq: Socket, events: Chan(R.Ev), core: Core.Core, life: Life, loop: Loop) -> IO(Main):
  (s, r) = p
  match r:
    case Ready{Done{_}}:
      IO.pure(Main, Main{mq, MaOpen{s}, events, core, life, loop})
    case _:
      IO.pure(Main, Main{mq, MaOpen{s}, events, core, life,
        push(loop, ma.lost("a send to Music Assistant failed"))})

# Bytes to Music Assistant (when its link is open).
def send.ma(m: Main, bs: B.Bytes) -> IO(Main):
  match m:
    case Main{mq, ma, events, core, life, loop}:
      match ma:
        case MaOpen{s}:
          do IO<Main>:
            p : Socket & Poll<&1, &1, Result<&1, &1, (U32 & String) & B.Bytes, Unit>, B.Bytes> <-
              TCP.try_send_bytes(s, bs, send_ms())
            sent.ma(p, mq, events, core, life, loop)
        case MaClosed{}:
          IO.pure(Main, Main{mq, MaClosed{}, events, core, life, loop})

# A text frame (a command) with a fresh mask.
def send.ma.text(m: Main, payload: B.Bytes) -> IO(Main):
  do IO<Main>:
    k : U32 <- IO.try(U32, IO.random_u32())
    send.ma(m, W.text(k, payload))

def send.ma.pong(m: Main, payload: B.Bytes) -> IO(Main):
  do IO<Main>:
    k : U32 <- IO.try(U32, IO.random_u32())
    send.ma(m, W.pong(k, payload))

# Opening Music Assistant's link
# ------------------------------

def opened.dup(p: Socket & Result<&1, &1, U32 & String, Socket>, mq: Socket, +events: Chan(R.Ev),
    +core: Core.Core, life: Life, loop: Loop) -> IO(Main):
  (s, r) = p
  match r:
    case Done{reader}:
      +ma = C.conf.ma(Core.core.conf(core))
      do IO<Main>:
        IO.spawn(R.MaReader, Rn.Run.forever(~R.MaReader, ~R.ma_reader.live, ~R.ma_reader.step,
          R.MaUp{reader, L.start(), events}))
        send.ma(Main{mq, MaOpen{s}, events, core, life, loop},
          W.upgrade(C.ma.host(ma), C.ma.port(ma), "/ws"))
    case Fail{_}:
      do IO<Main>:
        Socket.close(s)
        return Main{mq, MaClosed{}, events, core, life,
          push(loop, ma.lost("no second handle on its socket"))}

def opened(r: Result<&1, &1, U32 & String, Socket>, mq: Socket, events: Chan(R.Ev),
    core: Core.Core, life: Life, loop: Loop) -> IO(Main):
  match r:
    case Done{s}:
      do IO<Main>:
        p : Socket & Result<&1, &1, U32 & String, Socket> <- Sk.Sock.dup(s)
        opened.dup(p, mq, events, core, life, loop)
    case Fail{_}:
      IO.pure(Main, Main{mq, MaClosed{}, events, core, life,
        push(loop, ma.lost("can't connect (unreachable, or its name unknown)"))})

def shut(s: Socket) -> IO(Unit):
  do IO<Unit>:
    s : Socket <- Sk.Sock.shutdown(s)
    Socket.close(s)

def close.ma(ma: Ma) -> IO(Unit):
  match ma:
    case MaOpen{s}:
      shut(s)
    case MaClosed{}:
      IO.pure(Unit, Unit{})

def open.ma(m: Main) -> IO(Main):
  match m:
    case Main{mq, ma, events, +core, life, loop}:
      +c = C.conf.ma(Core.core.conf(core))
      do IO<Main>:
        close.ma(ma)
        r : Result<&1, &1, U32 & String, Socket> <- Nt.Net.connect(C.ma.host(c), C.ma.port(c))
        opened(r, mq, events, core, life, loop)

# The plays file
# --------------

def plays.wrote(p: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, r) = p
  match r:
    case Done{_}:
      File.close(f)
    case Fail{_}:
      do IO<Unit>:
        File.close(f)
        IO.print("plays file: can't write")

def plays.opened(r: Result<&1, &1, U32 & String, File>, line: B.Bytes) -> IO(Unit):
  match r:
    case Done{f}:
      do IO<Unit>:
        p : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, line)
        plays.wrote(p)
    case Fail{_}:
      IO.print("plays file: can't open")

def plays.append(path: String, line: B.Bytes) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "a")
    plays.opened(r, line)

# Health reports
# --------------

def digits.if_digit(digit: Bool, +c: U32, rest: B.Bytes) -> B.Bytes:
  match digit:
    case True{}:
      c <> rest
    case False{}:
      rest

# The decimal digits of a line, in order.
def digits(cs: B.Bytes) -> B.Bytes:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      digits.if_digit(Bool.and((c >= 48 : U32), (c <= 57 : U32)), c, digits(t))

def vmrss.if_found(found: Bool, +l: B.Bytes, rest: B.Bytes) -> B.Bytes:
  match found:
    case True{}:
      digits(l)
    case False{}:
      rest

def vmrss.line(ls: List<&2, B.Bytes>) -> B.Bytes:
  match ls:
    case Nil{}:
      B.utf8("unknown")
    case +l <> t:
      vmrss.if_found(B.beq(List.take(&2, U32, l, 6n), B.utf8("VmRSS:")), l, vmrss.line(t))

def mem.got(p: File & Result<&1, &1, U32 & String, B.Bytes>) -> IO(String):
  (f, r) = p
  match r:
    case Done{bs}:
      do IO<String>:
        File.close(f)
        return B.from_utf8(vmrss.line(C.lines(bs)))
    case Fail{_}:
      do IO<String>:
        File.close(f)
        return "unknown"

def mem.open(r: Result<&1, &1, U32 & String, File>) -> IO(String):
  match r:
    case Done{f}:
      do IO<String>:
        p : File & Result<&1, &1, U32 & String, B.Bytes> <- File.read_bytes(f, 4096)
        mem.got(p)
    case Fail{_}:
      IO.pure(String, "unknown")

# The memory in use, in kB, from /proc/self/status ("unknown" off Linux).
def mem_kb() -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open("/proc/self/status", "r")
    mem.open(r)

def or_none.if(blank: Bool, s: String) -> String:
  match blank:
    case True{}:
      "none"
    case False{}:
      s

def or_none(+s: String) -> String:
  or_none.if(C.blank(s), s)

def health.one(+prefix: String, name: String, value: String) -> B.Bytes:
  M.encode(M.Publish{False{}, 0, True{}, T.topic.health(prefix, name), 0, B.utf8(value)})

# The reports under <prefix>/$bridge/, retained.
def report.bytes(+core: Core.Core, l: Life, +unix: U32, mem: String) -> B.Bytes:
  match l:
    case Life{v, +started, n, e}:
      +p = Core.core.prefix(core)
      B.flat([health.one(p, "version", v),
        health.one(p, "uptime_s", U32.show((unix - started : U32))),
        health.one(p, "sessions", U32.show(n)), health.one(p, "last_end", or_none(e)),
        health.one(p, "plays", U32.show(Core.core.plays(core))),
        health.one(p, "players", Nat.show(Core.core.players(core))),
        health.one(p, "memory_kb", mem)])

def report.send(m: Main, +unix: U32, mem: String) -> IO(Main):
  match m:
    case Main{mq, ma, events, +core, +life, loop}:
      send.mq(Main{mq, ma, events, core, life, loop}, report.bytes(core, life, unix, mem))

def report(m: Main, t: Core.Time) -> IO(Main):
  match t:
    case Core.Time{_, unix}:
      do IO<Main>:
        mem : String <- mem_kb()
        report.send(m, unix, mem)

# Carrying out the core's actions
# -------------------------------

def act.append(m: Main, line: B.Bytes) -> IO(Main):
  match m:
    case Main{mq, ma, events, +core, life, loop}:
      do IO<Main>:
        plays.append(C.out.plays(C.conf.out(Core.core.conf(core))), line)
        return Main{mq, ma, events, core, life, loop}

def act.ended(m: Main, why: String) -> Main:
  match m:
    case Main{mq, ma, events, core, life, loop}:
      Main{mq, ma, events, core, life.ended(life, why), loop}

def act(m: Main, a: Core.Action, +t: Core.Time) -> IO(Main):
  match a:
    case Core.ToMq{p}:
      send.mq(m, M.encode(p))
    case Core.OpenMa{}:
      open.ma(m)
    case Core.ToMa{+id, c}:
      send.ma.text(m, Api.encode(id, c))
    case Core.PongMa{p}:
      send.ma.pong(m, p)
    case Core.Append{line}:
      act.append(m, line)
    case Core.Report{}:
      report(m, t)
    case Core.Log{l}:
      do IO<Main>:
        IO.print(l)
        return m
    case Core.Ended{why}:
      IO.pure(Main, act.ended(m, why))

def acts(as: List<&2, Core.Action>, m: Main, +t: Core.Time) -> IO(Main):
  match as:
    case Nil{}:
      IO.pure(Main, m)
    case a <> rest:
      do IO<Main>:
        m2 : Main <- act(m, a, t)
        acts(rest, m2, t)

# One input through the core, and its actions carried out.
def handle(m: Main, +t: Core.Time, i: Core.Input) -> IO(Main):
  match m:
    case Main{mq, ma, events, core, life, loop}:
      +o = Core.step(core, t, i)
      acts(Core.out.actions(o), Main{mq, ma, events, Core.out.core(o), life, loop}, t)

# The main loop
# -------------

def heard.ma(hs: List<&2, L.Heard>) -> List<&2, Core.Input>:
  match hs:
    case Nil{}:
      Nil{}
    case h <> t:
      Core.MaHeard{h} <> heard.ma(t)

# What a wait on the events channel gives the core (nothing when it timed out; a closed channel
# loses the broker).
def heard.of(r: Poll<&1, &1, Maybe<&1, R.Ev>, Unit>) -> List<&2, Core.Input>:
  match r:
    case Ready{Some{ev}}:
      match ev:
        case R.EvMq{p}:
          [Core.MqPacket{p}]
        case R.EvMqDown{}:
          [Core.MqLost{}]
        case R.EvMa{hs}:
          heard.ma(hs)
        case R.EvMaDown{}:
          [ma.lost("the link closed")]
    case Ready{None{}}:
      [Core.MqLost{}]
    case _:
      Nil{}

def heard.if_tick(due: Bool, ins: List<&2, Core.Input>, +now: U32, +tick: U32) -> Loop:
  match due:
    case True{}:
      Loop{List.append(&2, Core.Input, ins, [Core.Tick{}]), now}
    case False{}:
      Loop{ins, tick}

# The inbox after a wait: what was heard, then a tick when a second has passed since the last.
def heard(r: Poll<&1, &1, Maybe<&1, R.Ev>, Unit>, +now: U32, +tick: U32) -> Loop:
  heard.if_tick(((now - tick : U32) >= 1000 : U32), heard.of(r), now, tick)

# Runs the next input, or waits up to 1 s for one (and tells the watchdog).
def main.step(m: Main) -> IO(Main):
  match m:
    case Main{mq, ma, +events, core, life, loop}:
      match loop:
        case Loop{inbox, tick}:
          match inbox:
            case i <> rest:
              do IO<Main>:
                t : Nat <- IO.now()
                u : U32 <- Ck.Clock.unix()
                handle(Main{mq, ma, events, core, life, Loop{rest, tick}}, time.of(t, u), i)
            case Nil{}:
              do IO<Main>:
                r : Poll<&1, &1, Maybe<&1, R.Ev>, Unit> <- Chan.try_recv(R.Ev, events, 1000)
                t : Nat <- IO.now()
                Sd.Sd.notify("WATCHDOG=1")
                return Main{mq, ma, events, core, life, heard(r, U32.from_nat(t), tick)}

def main.live.if_over(over: Bool, m: Main) -> Rn.Next<Main>:
  match over:
    case True{}:
      Rn.Stop{m}
    case False{}:
      Rn.Go{m}

# The session goes on until the core ends it.
def main.live(m: Main) -> Rn.Next<Main>:
  match m:
    case Main{mq, ma, events, +core, life, loop}:
      main.live.if_over(Core.is.over(Core.core.phase(core)), Main{mq, ma, events, core, life, loop})

# The session
# -----------

# Both sockets shut (their readers end), the channel closed.
def finish(m: Main) -> IO(Ended):
  match m:
    case Main{mq, ma, events, +core, +life, _}:
      do IO<Ended>:
        shut(mq)
        close.ma(ma)
        Chan.close(R.Ev, events)
        return Ended{Core.core.up(core), life.last_end(life), Core.core.left(core)}

def session.begin(+t: Nat, +u: U32, mq: Socket, +events: Chan(R.Ev), +conf: C.Conf, life: Life,
    held: List<&2, Core.Pending>) -> IO(Ended):
  +o = Core.start(conf, time.of(t, u), held)
  do IO<Ended>:
    m : Main <- acts(Core.out.actions(o), Main{mq, MaClosed{}, events, Core.out.core(o), life,
      Loop{Nil{}, U32.from_nat(t)}}, time.of(t, u))
    m : Main <- Rn.Run.forever(~Main, ~main.live, ~main.step, m)
    finish(m)

def session.dup(p: Socket & Result<&1, &1, U32 & String, Socket>, +events: Chan(R.Ev),
    +conf: C.Conf, life: Life, held: List<&2, Core.Pending>) -> IO(Ended):
  (mq, r) = p
  match r:
    case Done{reader}:
      do IO<Ended>:
        IO.spawn(R.MqReader, Rn.Run.forever(~R.MqReader, ~R.mq_reader.live, ~R.mq_reader.step,
          R.MqUp{reader, Nil{}, events}))
        t : Nat <- IO.now()
        u : U32 <- Ck.Clock.unix()
        session.begin(t, u, mq, events, conf, life, held)
    case Fail{_}:
      do IO<Ended>:
        Socket.close(mq)
        Chan.close(R.Ev, events)
        return Ended{False{}, "no second handle on the broker's socket", held}

def session.connected(r: Result<&1, &1, U32 & String, Socket>, +events: Chan(R.Ev),
    +conf: C.Conf, life: Life, held: List<&2, Core.Pending>) -> IO(Ended):
  match r:
    case Done{mq}:
      do IO<Ended>:
        p : Socket & Result<&1, &1, U32 & String, Socket> <- Sk.Sock.dup(mq)
        session.dup(p, events, conf, life, held)
    case Fail{_}:
      do IO<Ended>:
        Chan.close(R.Ev, events)
        return Ended{False{}, "can't connect the broker (unreachable, or its name unknown)", held}

# One session, from connecting the broker to the end: whether it went live, why it ended, the plays
# it left waiting (held: those the last one left).
def session(+conf: C.Conf, life: Life, held: List<&2, Core.Pending>) -> IO(Ended):
  +mq = C.conf.mq(conf)
  do IO<Ended>:
    events : Chan(R.Ev) <- Chan.new(R.Ev, 16)
    r : Result<&1, &1, U32 & String, Socket> <- Nt.Net.connect(C.mq.host(mq), C.mq.port(mq))
    session.connected(r, events, conf, life, held)
