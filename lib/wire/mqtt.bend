import Base
import ./bytes.bend as B
# MQTT 3.1.1 packets, client side: encode what a client sends, decode what a
# broker sends (bounded: a packet over 64 KiB is refused, and every decoded
# packet takes bytes off the buffer). No sockets here: lib/app/readers.bend
# feeds the decoder, lib/app/main.bend sends the encodings.
# http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html

# The last will: what the broker publishes when the client goes away.
type Will is Data:
  Will{topic: String, payload: B.Bytes, qos: U32, retain: Bool}

type Packet is Data:
  # clean: clean session; user, pass: the login; will: the last will
  Connect{client: String, keepalive: U32, clean: Bool, user: Maybe<&2, String>,
    pass: Maybe<&2, String>, will: Maybe<&2, Will>}
  # present: the broker kept a session; code: 0 accepted, else why refused
  ConnAck{present: Bool, code: U32}
  # pid: the packet id (QoS 1 and 2 only; 0 otherwise)
  Publish{dup: Bool, qos: U32, retain: Bool, topic: String, pid: U32,
    payload: B.Bytes}
  PubAck{pid: U32}
  Subscribe{pid: U32, topics: List<&2, Sub>}
  # codes: one per filter, the QoS granted or 128 (refused)
  SubAck{pid: U32, codes: B.Bytes}
  PingReq{}
  PingResp{}
  Disconnect{}

# One topic filter of a SUBSCRIBE, with the QoS asked for.
type Sub is Data:
  Sub{filter: String, qos: U32}

# Fixed headers
# -------------
# A packet's first byte: its type in the high 4 bits, flags in the low 4.

def hdr.connect() -> U32:
  16

def hdr.connack() -> U32:
  32

# PUBLISH (3); its flags are dup (8), QoS (bits 1-2) and retain (1).
def hdr.publish() -> U32:
  48

def hdr.puback() -> U32:
  64

# SUBSCRIBE (8), with the flags the spec requires (2).
def hdr.subscribe() -> U32:
  130

def hdr.suback() -> U32:
  144

def hdr.pingreq() -> U32:
  192

def hdr.pingresp() -> U32:
  208

def hdr.disconnect() -> U32:
  224

# Encoding
# --------

# v when b holds, else 0: a flag bit.
def bit(b: Bool, v: U32) -> U32:
  match b:
    case True{}:
      v
    case False{}:
      0

# Remaining Length: 7 bits per byte, low group first, at most fuel bytes;
# small: whether n fits in this byte (n < 128).
def rlen.loop(fuel: Nat, small: Bool, +n: U32) -> B.Bytes:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      match small:
        case True{}:
          [n]
        case False{}:
          +m = (n >> 7n : U32)
          ((n .&. 127) .|. 128 : U32) <> rlen.loop(p, (m < 128 : U32), m)

# The Remaining Length of a packet body of n bytes (1 to 4 bytes).
def rlen(+n: U32) -> B.Bytes:
  rlen.loop(4n, (n < 128 : U32), n)

# A u16 length, then the bytes.
def bin(+bs: B.Bytes) -> B.Bytes:
  B.cat(B.u16(U32.from_nat(List.length(&2, U32, bs))), bs)

# A UTF-8 string with its length.
def str(s: String) -> B.Bytes:
  bin(B.utf8(s))

# A whole packet: its first byte, the body's length, the body.
def frame(first: U32, +body: B.Bytes) -> B.Bytes:
  first <> B.cat(rlen(U32.from_nat(List.length(&2, U32, body))), body)

def opt_flag(m: Maybe<&2, String>, v: U32) -> U32:
  match m:
    case None{}:
      0
    case Some{_}:
      v

def opt_str(m: Maybe<&2, String>) -> B.Bytes:
  match m:
    case None{}:
      Nil{}
    case Some{s}:
      str(s)

# CONNECT's flags for a will: will (4), its QoS (bits 3-4), its retain (32).
def will_flags(w: Maybe<&2, Will>) -> U32:
  match w:
    case None{}:
      0
    case Some{Will{_, _, q, r}}:
      ((4 .|. (q << 3n)) .|. bit(r, 32) : U32)

def will_bytes(w: Maybe<&2, Will>) -> B.Bytes:
  match w:
    case None{}:
      Nil{}
    case Some{Will{t, p, _, _}}:
      B.cat(str(t), bin(p))

def subs(ts: List<&2, Sub>) -> B.Bytes:
  match ts:
    case Nil{}:
      Nil{}
    case Sub{f, q} <> t:
      B.cat(B.cat(str(f), [q]), subs(t))

# The packet id, which only QoS 1 and 2 publishes carry.
def pid_for(qos: U32, +pid: U32) -> B.Bytes:
  match qos:
    case 0:
      Nil{}
    case _:
      B.u16(pid)

# CONNECT's flags: user (128), password (64), the will's, clean session (2).
def connect_flags(+user: Maybe<&2, String>, +pass: Maybe<&2, String>,
  +will: Maybe<&2, Will>, clean: Bool) -> U32:
  +login = (opt_flag(user, 128) .|. opt_flag(pass, 64) : U32)
  ((login .|. will_flags(will)) .|. bit(clean, 2) : U32)

# A retained QoS 0 publish to a topic given as bytes (what M.encode gives for
# Publish{False, 0, True, topic, 0, payload}, without the text round trip).
def publish_retained(+topic: B.Bytes, payload: B.Bytes) -> B.Bytes:
  frame((hdr.publish() .|. 1 : U32), List.concat(&2, U32, [bin(topic), Nil{}, payload]))

# The bytes of a packet.
def encode(p: Packet) -> B.Bytes:
  match p:
    case Connect{client, keepalive, clean, +user, +pass, +will}:
      +flags = connect_flags(user, pass, will, clean)
      frame(hdr.connect(), List.concat(&2, U32,
        [str("MQTT"), [4, flags], B.u16(keepalive), str(client),
         will_bytes(will), opt_str(user), opt_str(pass)]))
    case ConnAck{present, code}:
      frame(hdr.connack(), [bit(present, 1), code])
    case Publish{dup, +qos, retain, topic, pid, payload}:
      +flags = (bit(dup, 8) .|. ((qos << 1n) .|. bit(retain, 1)) : U32)
      frame((hdr.publish() .|. flags : U32),
        List.concat(&2, U32, [str(topic), pid_for(qos, pid), payload]))
    case PubAck{pid}:
      frame(hdr.puback(), B.u16(pid))
    case Subscribe{pid, ts}:
      frame(hdr.subscribe(), B.cat(B.u16(pid), subs(ts)))
    case SubAck{pid, codes}:
      frame(hdr.suback(), B.cat(B.u16(pid), codes))
    case PingReq{}:
      [hdr.pingreq(), 0]
    case PingResp{}:
      [hdr.pingresp(), 0]
    case Disconnect{}:
      [hdr.disconnect(), 0]

# Decoding
# --------

# What the front of a byte stream holds: not a whole packet yet, garbage, or a
# packet and the bytes after it.
type Decoded is Data:
  More{}
  Bad{}
  Got{pkt: Packet, rest: B.Bytes}

# The same for a Remaining Length: n, and the bytes after it.
type Len is Data:
  LMore{}
  LBad{}
  LGot{n: U32, rest: B.Bytes}

# The Remaining Length, unrolled: byte k (from 0) carries bits 7k..7k+6, and
# len.if_last<k> decides, once byte k is read (last: its top bit is clear),
# whether the length ends there. A fourth byte that isn't the last is bad.
def len.if_last3(last: Bool, +n: U32, t: B.Bytes) -> Len:
  match last:
    case True{}:
      LGot{n, t}
    case False{}:
      LBad{}

def len.byte3(+acc: U32, bs: B.Bytes) -> Len:
  match bs:
    case Nil{}:
      LMore{}
    case +b <> t:
      len.if_last3((b < 128 : U32), (acc .|. ((b .&. 127) << 21n) : U32), t)

def len.if_last2(last: Bool, +n: U32, t: B.Bytes) -> Len:
  match last:
    case True{}:
      LGot{n, t}
    case False{}:
      len.byte3(n, t)

def len.byte2(+acc: U32, bs: B.Bytes) -> Len:
  match bs:
    case Nil{}:
      LMore{}
    case +b <> t:
      len.if_last2((b < 128 : U32), (acc .|. ((b .&. 127) << 14n) : U32), t)

def len.if_last1(last: Bool, +n: U32, t: B.Bytes) -> Len:
  match last:
    case True{}:
      LGot{n, t}
    case False{}:
      len.byte2(n, t)

def len.byte1(+acc: U32, bs: B.Bytes) -> Len:
  match bs:
    case Nil{}:
      LMore{}
    case +b <> t:
      len.if_last1((b < 128 : U32), (acc .|. ((b .&. 127) << 7n) : U32), t)

def len.if_last0(last: Bool, +n: U32, t: B.Bytes) -> Len:
  match last:
    case True{}:
      LGot{n, t}
    case False{}:
      len.byte1(n, t)

# The Remaining Length at the front of the bytes after a packet's first byte.
def len(bs: B.Bytes) -> Len:
  match bs:
    case Nil{}:
      LMore{}
    case +b <> t:
      len.if_last0((b < 128 : U32), (b .&. 127 : U32), t)

def is_set(+x: U32, m: U32) -> Bool:
  U32.is_ne((x .&. m : U32), 0)

def pid_r(qos: U32) -> B.Rd(U32):
  match qos:
    case 0:
      B.Rd.pure(U32, 0)
    case _:
      B.u16_r()

def connack_r() -> B.Rd(Packet):
  do B.Rd<Packet>:
    a : U32 <- B.u8_r()
    c : U32 <- B.u8_r()
    return ConnAck{is_set(a, 1), c}

def publish_r(+flags: U32) -> B.Rd(Packet):
  +qos = ((flags >> 1n) .&. 3 : U32)
  do B.Rd<Packet>:
    topic : B.Bytes <- B.bin_r()
    pid : U32 <- pid_r(qos)
    payload : B.Bytes <- B.rest_r()
    return Publish{is_set(flags, 8), qos, is_set(flags, 1), B.from_utf8(topic), pid, payload}

def puback_r() -> B.Rd(Packet):
  do B.Rd<Packet>:
    pid : U32 <- B.u16_r()
    return PubAck{pid}

def suback_r() -> B.Rd(Packet):
  do B.Rd<Packet>:
    pid : U32 <- B.u16_r()
    codes : B.Bytes <- B.rest_r()
    return SubAck{pid, codes}

# The body's reader for a packet type (the first byte's high 4 bits); only the
# packets a client receives.
def body_r(typ: U32, +flags: U32) -> Maybe<&1, B.Rd(Packet)>:
  match typ:
    # CONNACK
    case 2:
      Some{connack_r()}
    # PUBLISH
    case 3:
      Some{publish_r(flags)}
    # PUBACK
    case 4:
      Some{puback_r()}
    # SUBACK
    case 9:
      Some{suback_r()}
    # PINGREQ
    case 12:
      Some{B.Rd.pure(Packet, PingReq{})}
    # PINGRESP
    case 13:
      Some{B.Rd.pure(Packet, PingResp{})}
    # DISCONNECT
    case 14:
      Some{B.Rd.pure(Packet, Disconnect{})}
    case _:
      None{}

def decode.on_packet(m: Maybe<&1, Packet>, rest: B.Bytes) -> Decoded:
  match m:
    case None{}:
      Bad{}
    case Some{p}:
      Got{p, rest}

def decode.on_reader(r: Maybe<&1, B.Rd(Packet)>, body: B.Bytes, rest: B.Bytes) -> Decoded:
  match r:
    case None{}:
      Bad{}
    case Some{rd}:
      decode.on_packet(B.Rd.ok(Packet, B.Rd.run(Packet, rd, body)), rest)

# Whether xs has at least n bytes, looking at no more than n of them (a packet's
# size, not the whole buffer's, so a burst of packets decodes in linear time).
def at_least(n: Nat, xs: B.Bytes) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      match xs:
        case Nil{}:
          False{}
        case _ <> t:
          at_least(p, t)

# enough: whether the n bytes of the body have arrived.
def decode.if_enough(enough: Bool, +hdr: U32, +n: Nat, +rest: B.Bytes) -> Decoded:
  match enough:
    case False{}:
      More{}
    case True{}:
      decode.on_reader(body_r((hdr >> 4n : U32), (hdr .&. 15 : U32)),
        List.take(&2, U32, rest, n), List.drop(&2, U32, rest, n))

# The largest packet accepted (64 KiB; the bridge's own are a few hundred
# bytes). A larger one is refused (Bad: the connection is dropped) instead of
# buffered, so a broker can't make the bridge hold an unbounded amount.
def max_packet() -> U32:
  65536

# ok: whether the declared length is within max_packet.
def decode.if_allowed(ok: Bool, +hdr: U32, +n: U32, +rest: B.Bytes) -> Decoded:
  match ok:
    case True{}:
      decode.if_enough(at_least(U32.to_nat(n), rest), hdr, U32.to_nat(n), rest)
    case False{}:
      Bad{}

def decode.on_len(l: Len, +hdr: U32) -> Decoded:
  match l:
    case LMore{}:
      More{}
    case LBad{}:
      Bad{}
    case LGot{+n, +rest}:
      decode.if_allowed(U32.is_le(n, max_packet()), hdr, n, rest)

# Splits one packet off the front of a byte stream.
def decode(buf: B.Bytes) -> Decoded:
  match buf:
    case Nil{}:
      More{}
    case hdr <> t:
      decode.on_len(len(t), hdr)

# What a reader does with its buffer: decode, but give up on a buffer that
# waits for more beyond the largest packet plus its header (5 bytes), so the
# bytes held stay bounded whatever arrives.
def cap() -> U32:
  65541

# Whether the buffer holds more than cap().
def over_cap(+buf: B.Bytes) -> Bool:
  (U32.from_nat(List.length(&2, U32, buf)) > cap() : U32)

def verdict.on_decoded(d: Decoded, over: Bool) -> Decoded:
  match d:
    case More{}:
      match over:
        case True{}:
          Bad{}
        case False{}:
          More{}
    case other:
      other

# decode, refusing a buffer over cap() that still waits for more.
def verdict(+buf: B.Bytes) -> Decoded:
  verdict.on_decoded(decode(buf), over_cap(buf))
