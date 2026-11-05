import Base
import ./bytes.bend as B
# A WebSocket client's wire format (RFC 6455): the upgrade request, the frames a client sends
# (always masked), and a decoder for the server's side that takes one byte at a time, so the
# memory it holds doesn't grow with a message's size: a message's bytes come out as they arrive.
# No I/O here, and no JSON: text payloads are plain bytes to this module.

# Opcodes
# -------

def op.continuation() -> U32:
  0

def op.text() -> U32:
  1

def op.binary() -> U32:
  2

def op.close() -> U32:
  8

def op.ping() -> U32:
  9

def op.pong() -> U32:
  10

# The upgrade
# -----------

# The request's key. RFC 6455 asks for 16 random bytes in base64; the server only echoes a hash
# of it, which guards against caching proxies, not peers, so a fixed key does (RFC 6455's own).
def key() -> String:
  "dGhlIHNhbXBsZSBub25jZQ=="

# The HTTP request that opens a websocket at path on host:port.
def upgrade(host: String, +port: U32, path: String) -> B.Bytes:
  B.utf8(("GET " ++ path ++ " HTTP/1.1\r\n"
    ++ "Host: " ++ host ++ ":" ++ U32.show(port) ++ "\r\n"
    ++ "Upgrade: websocket\r\nConnection: Upgrade\r\n"
    ++ "Sec-WebSocket-Key: " ++ key() ++ "\r\n"
    ++ "Sec-WebSocket-Version: 13\r\n\r\n"))

# The status line's start that accepts the upgrade.
def accepted() -> B.Bytes:
  B.utf8("HTTP/1.1 101")

# The longest upgrade answer read (its headers); a longer one is refused.
def max_head() -> U32:
  8192

# Client frames
# -------------

# The payload xored with the key's bytes in turn (k0 first), as a client must send it.
def masked(bs: B.Bytes, +k0: U32, +k1: U32, +k2: U32, +k3: U32) -> B.Bytes:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      (b .^. k0 : U32) <> masked(t, k1, k2, k3, k0)

# The masked length bytes: 7 bits when small (below 126), else 126 and 16 bits when medium
# (below 65536), else 127 and 64 bits.
def length.if_small(small: Bool, medium: Bool, +n: U32) -> B.Bytes:
  match small:
    case True{}:
      [(128 .|. n : U32)]
    case False{}:
      match medium:
        case True{}:
          254 <> B.u16(n)
        case False{}:
          255 <> B.cat([0, 0, 0, 0], B.u32(n))

def length(+n: U32) -> B.Bytes:
  length.if_small((n < 126 : U32), (n < 65536 : U32), n)

# A whole frame with fin set, its opcode, masked with key.
def frame(+op: U32, +key: U32, +payload: B.Bytes) -> B.Bytes:
  (128 .|. op : U32) <> B.cat(length(U32.from_nat(List.length(&2, U32, payload))),
    B.cat(B.u32(key), masked(payload, (key >> 24n : U32), ((key >> 16n) .&. 255 : U32),
      ((key >> 8n) .&. 255 : U32), (key .&. 255 : U32))))

# A text message (UTF-8 bytes).
def text(+key: U32, +payload: B.Bytes) -> B.Bytes:
  frame(op.text(), key, payload)

# The answer to a ping: its payload back.
def pong(+key: U32, +payload: B.Bytes) -> B.Bytes:
  frame(op.pong(), key, payload)

# Closing our side (no status code).
def close(+key: U32) -> B.Bytes:
  frame(op.close(), key, Nil{})

# The server's side
# -----------------

# What one byte from the server gives.
type Out is Data:
  Nothing{}
  # the server accepted the upgrade (the last byte of its answer's headers)
  Up{}
  # a byte of a message (text or binary), and a message's last byte
  Byte{b: U32}
  Last{b: U32}
  # a message ended with an empty frame
  End{}
  # a ping: answer it with pong(payload)
  Ping{payload: B.Bytes}
  # the server closed the connection
  Closed{}
  # the stream broke the protocol; nothing more comes out
  Bad{why: String}

# Where the decoder is.
type Phase is Data:
  # reading the upgrade answer: how much of CRLF CRLF has matched, the answer's first bytes
  # (newest first, up to 12), its size so far
  Head{matched: U32, status: B.Bytes, size: U32}
  # a frame's first byte
  First{}
  # its second byte (mask bit and 7-bit length)
  Second{fin: Bool, op: U32}
  # the extended length's bytes still to come (need), and the length so far
  Long{fin: Bool, op: U32, need: Nat, acc: U32}
  # a data frame's payload bytes still to come
  Payload{fin: Bool, left: U32}
  # a control frame's payload: bytes still to come, the ones read (newest first)
  Control{op: U32, left: U32, acc: B.Bytes}
  # after Bad or Closed
  Dead{}

# The decoder: its phase, and whether a fragmented message is open (its last frame not yet in).
type Dec is Data:
  Dec{phase: Phase, open: Bool}

# A decoder before the upgrade answer.
def start() -> Dec:
  Dec{Head{0, Nil{}, 0}, False{}}

# A decoder past the upgrade (for frames alone, as in the laws).
def framing() -> Dec:
  Dec{First{}, False{}}

# What a byte did: the decoder after it, and what came out.
type Stepped is Data:
  Stepped{dec: Dec, out: Out}

def dead(why: String) -> Stepped:
  Stepped{Dec{Dead{}, False{}}, Bad{why}}

def is_control(+op: U32) -> Bool:
  (op > 7 : U32)

# The upgrade answer
# ------------------

# The CR LF CR LF matcher: the next count after a byte (a CR restarts at 1).
def crlf.next.if_hit(hit: Bool, cr: Bool, +matched: U32) -> U32:
  match hit:
    case True{}:
      (matched + 1 : U32)
    case False{}:
      match cr:
        case True{}:
          1
        case False{}:
          0

# The byte each matched count expects: CR at 0 and 2, LF at 1 and 3.
def crlf.wants.if_even(even: Bool) -> U32:
  match even:
    case True{}:
      13
    case False{}:
      10

def crlf.wants(+matched: U32) -> U32:
  crlf.wants.if_even(U32.is_eq((matched .&. 1 : U32), 0))

def crlf.next(+matched: U32, +b: U32) -> U32:
  crlf.next.if_hit(U32.is_eq(b, crlf.wants(matched)), U32.is_eq(b, 13), matched)

# done: whether CR LF CR LF just ended the headers; ok: whether the status line accepts.
def head.if_done(done: Bool, ok: Bool, +matched: U32, +status: B.Bytes, +size: U32,
    +open: Bool) -> Stepped:
  match done:
    case False{}:
      Stepped{Dec{Head{matched, status, size}, open}, Nothing{}}
    case True{}:
      match ok:
        case True{}:
          Stepped{Dec{First{}, False{}}, Up{}}
        case False{}:
          dead("upgrade refused: " ++ B.from_utf8(List.reverse(&2, U32, status)))

# Keeps the answer's first 12 bytes (newest first).
def head.keep.if_room(room: Bool, +status: B.Bytes, +b: U32) -> B.Bytes:
  match room:
    case True{}:
      b <> status
    case False{}:
      status

def head.keep(+status: B.Bytes, +b: U32) -> B.Bytes:
  head.keep.if_room((U32.from_nat(List.length(&2, U32, status)) < 12 : U32), status, b)

def head.with(+matched: U32, +status: B.Bytes, +size: U32, +open: Bool) -> Stepped:
  head.if_done(U32.is_eq(matched, 4), B.beq(List.reverse(&2, U32, status), accepted()), matched,
    status, size, open)

def head.if_long(long: Bool, +matched: U32, +status: B.Bytes, +size: U32, +b: U32,
    +open: Bool) -> Stepped:
  match long:
    case True{}:
      dead("upgrade answer too long")
    case False{}:
      head.with(crlf.next(matched, b), head.keep(status, b), (size + 1 : U32), open)

# Frame headers
# -------------

# Whether an opcode may start a frame now: a continuation only inside a message, text or binary
# only outside one, control frames anywhere but only whole (fin).
def first.allowed.if_kind(continuation: Bool, control: Bool, +op: U32, +fin: Bool, +open: Bool)
    -> Bool:
  match continuation:
    case True{}:
      open
    case False{}:
      match control:
        case True{}:
          Bool.and(fin, Bool.or(U32.is_eq(op, op.close()),
            Bool.or(U32.is_eq(op, op.ping()), U32.is_eq(op, op.pong()))))
        case False{}:
          Bool.and(Bool.not(open), Bool.or(U32.is_eq(op, op.text()), U32.is_eq(op, op.binary())))

def first.allowed(+op: U32, +fin: Bool, +open: Bool) -> Bool:
  first.allowed.if_kind(U32.is_eq(op, op.continuation()), is_control(op), op, fin, open)

def first.if_ok(ok: Bool, +fin: Bool, +op: U32, +open: Bool) -> Stepped:
  match ok:
    case True{}:
      Stepped{Dec{Second{fin, op}, open}, Nothing{}}
    case False{}:
      dead("unexpected frame (opcode " ++ U32.show(op) ++ ")")

def first.with(+fin: Bool, +op: U32, +rsv: U32, +open: Bool) -> Stepped:
  first.if_ok(Bool.and(U32.is_eq(rsv, 0), first.allowed(op, fin, open)), fin, op, open)

def first(+b: U32, +open: Bool) -> Stepped:
  first.with(U32.is_ne((b .&. 128 : U32), 0), (b .&. 15 : U32), (b .&. 112 : U32), open)

# Data frames
# -----------

# The payload begins (n bytes): a data frame's opens or closes the message as fin says; an
# empty one ends a message right away when fin.
def begin.data.if_empty(empty: Bool, +fin: Bool, +n: U32) -> Stepped:
  match empty:
    case True{}:
      match fin:
        case True{}:
          Stepped{Dec{First{}, False{}}, End{}}
        case False{}:
          Stepped{Dec{First{}, True{}}, Nothing{}}
    case False{}:
      Stepped{Dec{Payload{fin, n}, Bool.not(fin)}, Nothing{}}

def begin.data(+fin: Bool, +n: U32) -> Stepped:
  begin.data.if_empty(U32.is_eq(n, 0), fin, n)

# A control frame's payload is whole: a ping is answered, a pong ignored, a close ends it.
def control.done.if_kind(ping: Bool, pong: Bool, payload: B.Bytes, +open: Bool) -> Stepped:
  match ping:
    case True{}:
      Stepped{Dec{First{}, open}, Ping{payload}}
    case False{}:
      match pong:
        case True{}:
          Stepped{Dec{First{}, open}, Nothing{}}
        case False{}:
          Stepped{Dec{Dead{}, False{}}, Closed{}}

def control.done(+op: U32, payload: B.Bytes, +open: Bool) -> Stepped:
  control.done.if_kind(U32.is_eq(op, op.ping()), U32.is_eq(op, op.pong()), payload, open)

def begin.control.if_empty(empty: Bool, +op: U32, +n: U32, +open: Bool) -> Stepped:
  match empty:
    case True{}:
      control.done(op, Nil{}, open)
    case False{}:
      Stepped{Dec{Control{op, n, Nil{}}, open}, Nothing{}}

def begin.control(+op: U32, +n: U32, +open: Bool) -> Stepped:
  begin.control.if_empty(U32.is_eq(n, 0), op, n, open)

def begin.if_control(control: Bool, +fin: Bool, +op: U32, +n: U32, +open: Bool) -> Stepped:
  match control:
    case True{}:
      begin.control(op, n, open)
    case False{}:
      begin.data(fin, n)

def begin(+fin: Bool, +op: U32, +n: U32, +open: Bool) -> Stepped:
  begin.if_control(is_control(op), fin, op, n, open)

# The second byte: a masked server frame and a control payload over 125 bytes are refused; 126
# and 127 announce 2 and 8 more length bytes.
def second.on_len(sixteen: Bool, sixty_four: Bool, +fin: Bool, +op: U32, +len7: U32,
    +open: Bool) -> Stepped:
  match sixteen:
    case True{}:
      Stepped{Dec{Long{fin, op, 2n, 0}, open}, Nothing{}}
    case False{}:
      match sixty_four:
        case True{}:
          Stepped{Dec{Long{fin, op, 8n, 0}, open}, Nothing{}}
        case False{}:
          begin(fin, op, len7, open)

def second.if_refused(masked: Bool, big_control: Bool, +fin: Bool, +op: U32, +len7: U32,
    +open: Bool) -> Stepped:
  match masked:
    case True{}:
      dead("masked frame from the server")
    case False{}:
      match big_control:
        case True{}:
          dead("control frame over 125 bytes")
        case False{}:
          second.on_len(U32.is_eq(len7, 126), U32.is_eq(len7, 127), fin, op, len7, open)

def second.with(+fin: Bool, +op: U32, +masked: Bool, +len7: U32, +open: Bool) -> Stepped:
  second.if_refused(masked, Bool.and(is_control(op), (len7 > 125 : U32)), fin, op, len7, open)

def second(+fin: Bool, +op: U32, +b: U32, +open: Bool) -> Stepped:
  second.with(fin, op, U32.is_ne((b .&. 128 : U32), 0), (b .&. 127 : U32), open)

# left: the length bytes after this one; acc: the length with this byte.
def long.next(left: Nat, +fin: Bool, +op: U32, +acc: U32, +open: Bool) -> Stepped:
  match left:
    case 0n:
      begin(fin, op, acc, open)
    case 1n+q:
      Stepped{Dec{Long{fin, op, 1n+q, acc}, open}, Nothing{}}

def long.if_too_big(too_big: Bool, left: Nat, +fin: Bool, +op: U32, +acc: U32, +open: Bool)
    -> Stepped:
  match too_big:
    case True{}:
      dead("frame over 4 GiB")
    case False{}:
      long.next(left, fin, op, acc, open)

# An extended length byte; of a 64-bit length, the high four must be zero (frames past 4 GiB
# are refused).
def long.byte(+fin: Bool, +op: U32, need: Nat, +acc: U32, +b: U32, +open: Bool) -> Stepped:
  match need:
    case 0n:
      begin(fin, op, acc, open)
    case 1n+(+p):
      long.if_too_big(Bool.and(Nat.is_gt(p, 3n), U32.is_ne(b, 0)), p, fin, op,
        ((acc << 8n) .|. b : U32), open)

# A payload byte of a data frame; the frame's last one is a message's last when fin.
def payload.byte.if_last(last: Bool, +fin: Bool, +left: U32, +b: U32, +open: Bool)
    -> Stepped:
  match last:
    case True{}:
      match fin:
        case True{}:
          Stepped{Dec{First{}, False{}}, Last{b}}
        case False{}:
          Stepped{Dec{First{}, open}, Byte{b}}
    case False{}:
      Stepped{Dec{Payload{fin, (left - 1 : U32)}, open}, Byte{b}}

def payload.byte(+fin: Bool, +left: U32, +b: U32, +open: Bool) -> Stepped:
  payload.byte.if_last(U32.is_eq(left, 1), fin, left, b, open)

def control.byte.if_last(last: Bool, +op: U32, +left: U32, acc: B.Bytes, +open: Bool)
    -> Stepped:
  match last:
    case True{}:
      control.done(op, List.reverse(&2, U32, acc), open)
    case False{}:
      Stepped{Dec{Control{op, (left - 1 : U32), acc}, open}, Nothing{}}

def control.byte(+op: U32, +left: U32, acc: B.Bytes, +b: U32, +open: Bool) -> Stepped:
  control.byte.if_last(U32.is_eq(left, 1), op, left, b <> acc, open)

# The decoder after one byte from the server.
def step(d: Dec, +b: U32) -> Stepped:
  match d:
    case Dec{phase, +open}:
      match phase:
        case Head{+matched, +status, +size}:
          head.if_long((size + 1 > max_head() : U32), matched, status, size, b, open)
        case First{}:
          first(b, open)
        case Second{+fin, +op}:
          second(fin, op, b, open)
        case Long{+fin, +op, need, +acc}:
          long.byte(fin, op, need, acc, b, open)
        case Payload{+fin, +left}:
          payload.byte(fin, left, b, open)
        case Control{+op, +left, acc}:
          control.byte(op, left, acc, b, open)
        case Dead{}:
          Stepped{Dec{Dead{}, False{}}, Nothing{}}

# Many bytes
# ----------

def stepped.dec(s: Stepped) -> Dec:
  match s:
    case Stepped{d, _}:
      d

def stepped.out(s: Stepped) -> Out:
  match s:
    case Stepped{_, o}:
      o

# What a run of bytes did: the decoder after them, what came out (newest first; Nothing left
# out).
type Fed is Data:
  Fed{dec: Dec, outs: List<&2, Out>}

def fed.dec(f: Fed) -> Dec:
  match f:
    case Fed{d, _}:
      d

def fed.outs(f: Fed) -> List<&2, Out>:
  match f:
    case Fed{_, o}:
      o

def keep(o: Out, outs: List<&2, Out>) -> List<&2, Out>:
  match o:
    case Nothing{}:
      outs
    case other:
      other <> outs

# The decoder after a run of bytes, and what came out of them (newest first) on top of outs.
def run(bs: B.Bytes, d: Dec, outs: List<&2, Out>) -> Fed:
  match bs:
    case Nil{}:
      Fed{d, outs}
    case b <> t:
      +s = step(d, b)
      run(t, stepped.dec(s), keep(stepped.out(s), outs))

# The decoder after a run of bytes, and what came out of them, oldest first.
def feed(d: Dec, bs: B.Bytes) -> Fed:
  +f = run(bs, d, Nil{})
  Fed{fed.dec(f), List.reverse(&2, Out, fed.outs(f))}
