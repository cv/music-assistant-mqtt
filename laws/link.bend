import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/json.bend as J
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/ma/link.bend as L
import ./ma.bend as Lma
# Laws of the link (lib/ma/link.bend): the decoder and the scanner together.

def u(s: String) -> B.Bytes:
  B.utf8(s)

# The 101 answer Music Assistant gives the upgrade (aiohttp's headers).
def answer() -> B.Bytes:
  u("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: upgrade\r\n"
    ++ "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n")

# A server frame (unmasked) with this opcode byte and payload (under 64 KiB).
def frame.len.if_short(short: Bool, +n: U32) -> B.Bytes:
  match short:
    case True{}:
      [n]
    case False{}:
      [126, (n >> 8n : U32), (n .&. 255 : U32)]

def frame(+first: U32, +payload: B.Bytes) -> B.Bytes:
  +n = U32.from_nat(List.length(&2, U32, payload))
  first <> B.cat(frame.len.if_short((n < 126 : U32), n), payload)

def hello.heard() -> L.Heard:
  L.Message{Model.read(Lma.sample.hello())}

# The upgrade answer, then the server's hello in one text frame.
law link_reads_hello:
  {L.fed.heard(L.feed(Api.wants(), L.start(), B.cat(answer(), frame(129, Lma.sample.hello()))))
    == [L.Opened{}, hello.heard()] : List<&2, L.Heard>}

# The same hello in two fragments with a ping between them: the ping is heard first, the message
# once whole.
law link_reads_fragments:
  {L.fed.heard(L.feed(Api.wants(), L.start(), B.cat(answer(),
      B.cat(frame(1, List.take(&2, U32, Lma.sample.hello(), 100n)),
      B.cat(frame(137, u("hi")), frame(128, List.drop(&2, U32, Lma.sample.hello(), 100n)))))))
    == [L.Opened{}, L.Pinged{u("hi")}, hello.heard()] : List<&2, L.Heard>}

# A text frame that isn't JSON is heard as such, and the next one still reads.
law link_garbled_then_fine:
  {L.fed.heard(L.feed(Api.wants(), L.start(), B.cat(answer(),
      B.cat(frame(129, u("{nope")), frame(129, Lma.sample.hello())))))
    == [L.Opened{}, L.Garbled{}, hello.heard()] : List<&2, L.Heard>}

# A refused upgrade is the link's end.
law link_refused:
  {L.fed.heard(L.feed(Api.wants(), L.start(), u("HTTP/1.1 401 Unauthorized\r\n\r\n")))
    == [L.Lost{"upgrade refused: HTTP/1.1 401"}] : List<&2, L.Heard>}

# For every input: however the socket splits the bytes, the link hears the same.
law link_feed_split:
  for xs: B.Bytes
  for +ys: B.Bytes
  for +ws: J.Wants
  for +l: L.Link
  for +hs: List<&2, L.Heard>
  {L.run(B.cat(xs, ys), ws, l, hs)
    == L.run(ys, ws, L.fed.link(L.run(xs, ws, l, hs)), L.fed.heard(L.run(xs, ws, l, hs)))
    : L.Fed}
