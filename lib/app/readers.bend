import Base
import ../net/run.bend as Rn
import ../wire/bytes.bend as B
import ../wire/mqtt.bend as M
import ../ma/api.bend as Api
import ../ma/link.bend as L
# The readers: one blocks on the broker's socket, one on Music Assistant's. They only read,
# decode and pass on, over one channel; the main loop (main.bend) owns the write sides. A reader
# ends when its socket does (the main loop shuts the sockets down at a session's end).

type Ev is Data:
  EvMq{pkt: M.Packet}
  EvMqDown{}
  EvMa{heard: List<&2, L.Heard>}
  EvMaDown{}

# The link is gone: the socket closes and the main loop hears it.
def link_down(s: Socket, +events: Chan(Ev), ev: Ev) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    x : Result<&1, &1, Ev, Unit> <- Chan.send(Ev, events, ev)
    return Unit{}

# Music Assistant's reader
# ------------------------

# Its socket, the link (decoder and scanner), the events channel.
type MaReader is Type:
  MaUp{sock: Socket, link: L.Link, events: Chan(Ev)}
  MaOver{}

def ma_reader.sent(x: Result<&1, &1, Ev, Unit>, s: Socket, link: L.Link, events: Chan(Ev))
    -> IO(MaReader):
  match x:
    case Done{_}:
      IO.pure(MaReader, MaUp{s, link, events})
    case Fail{_}:
      do IO<MaReader>:
        Socket.close(s)
        return MaOver{}

# What a read said goes over in one event (nothing when it said nothing).
def ma_reader.pass(heard: List<&2, L.Heard>, s: Socket, link: L.Link, +events: Chan(Ev))
    -> IO(MaReader):
  match heard:
    case Nil{}:
      IO.pure(MaReader, MaUp{s, link, events})
    case h <> t:
      do IO<MaReader>:
        x : Result<&1, &1, Ev, Unit> <- Chan.send(Ev, events, EvMa{h <> t})
        ma_reader.sent(x, s, link, events)

def ma_reader.fed(f: L.Fed, s: Socket, +events: Chan(Ev)) -> IO(MaReader):
  match f:
    case L.Fed{link, heard}:
      ma_reader.pass(heard, s, link, events)

def ma_reader.got(q: Socket & Result<&1, &1, U32 & String, Maybe<&1, B.Bytes>>, link: L.Link,
    +events: Chan(Ev)) -> IO(MaReader):
  (s, r) = q
  match r:
    case Done{Some{bs}}:
      ma_reader.fed(L.feed(Api.wants(), link, bs), s, events)
    case _:
      do IO<MaReader>:
        link_down(s, events, EvMaDown{})
        return MaOver{}

def ma_reader.step(st: MaReader) -> IO(MaReader):
  match st:
    case MaUp{s, link, events}:
      do IO<MaReader>:
        q : Socket & Result<&1, &1, U32 & String, Maybe<&1, B.Bytes>> <- TCP.recv_bytes(s, 8192)
        ma_reader.got(q, link, events)
    case MaOver{}:
      IO.pure(MaReader, MaOver{})

def ma_reader.live(st: MaReader) -> Rn.Next<MaReader>:
  match st:
    case MaUp{s, link, events}:
      Rn.Go{MaUp{s, link, events}}
    case MaOver{}:
      Rn.Stop{MaOver{}}

# The broker's reader
# -------------------

# Its socket, the bytes not yet decoded, the events channel.
type MqReader is Type:
  MqUp{sock: Socket, buf: B.Bytes, events: Chan(Ev)}
  MqOver{}

# After handing over a read's packets: the bytes left, or a bad packet.
type Drained is Data:
  DrainOk{buf: B.Bytes}
  DrainBad{}

# Hands every whole packet in the buffer to the main loop. A read is at most 65536 bytes and a
# packet at least 2, so 40000 steps always empty it.
def drain(fuel: Nat, d: M.Decoded, +buf: B.Bytes, +events: Chan(Ev)) -> IO(Drained):
  match fuel:
    case 0n:
      IO.pure(Drained, DrainOk{buf})
    case 1n+p:
      match d:
        case M.More{}:
          IO.pure(Drained, DrainOk{buf})
        case M.Bad{}:
          IO.pure(Drained, DrainBad{})
        case M.Got{pkt, +rest}:
          do IO<Drained>:
            x : Result<&1, &1, Ev, Unit> <- Chan.send(Ev, events, EvMq{pkt})
            drain(p, M.decode(rest), rest, events)

def mq_reader.after(d: Drained, s: Socket, +events: Chan(Ev)) -> IO(MqReader):
  match d:
    case DrainOk{buf}:
      IO.pure(MqReader, MqUp{s, buf, events})
    case DrainBad{}:
      do IO<MqReader>:
        link_down(s, events, EvMqDown{})
        return MqOver{}

def mq_reader.got(q: Socket & Result<&1, &1, U32 & String, Maybe<&1, B.Bytes>>, buf: B.Bytes,
    +events: Chan(Ev)) -> IO(MqReader):
  (s, r) = q
  match r:
    case Done{Some{bs}}:
      +all = B.cat(buf, bs)
      do IO<MqReader>:
        d : Drained <- drain(40000n, M.verdict(all), all, events)
        mq_reader.after(d, s, events)
    case _:
      do IO<MqReader>:
        link_down(s, events, EvMqDown{})
        return MqOver{}

def mq_reader.step(st: MqReader) -> IO(MqReader):
  match st:
    case MqUp{s, buf, events}:
      do IO<MqReader>:
        q : Socket & Result<&1, &1, U32 & String, Maybe<&1, B.Bytes>> <- TCP.recv_bytes(s, 8192)
        mq_reader.got(q, buf, events)
    case MqOver{}:
      IO.pure(MqReader, MqOver{})

def mq_reader.live(st: MqReader) -> Rn.Next<MqReader>:
  match st:
    case MqUp{s, buf, events}:
      Rn.Go{MqUp{s, buf, events}}
    case MqOver{}:
      Rn.Stop{MqOver{}}
