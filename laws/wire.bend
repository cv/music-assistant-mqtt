import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M

# Laws of the wire formats: MQTT, UTF-8 and base64.


# MQTT Remaining Length
# ---------------------

# The encoder never emits more bytes than its fuel, so `rlen` (fuel 4)
# always fits the 4-byte limit of MQTT 3.1.1 §2.2.3.
law rlen_bounded:
  for fuel: Nat
  for small: Bool
  for +n: U32
  {Nat.is_le(List.length(&2, U32, M.rlen.loop(fuel, small, n)), fuel) == True{} : Bool}

# The largest length MQTT allows encodes as the spec's example.
law rlen_max:
  {M.rlen(268435455) == [255, 255, 255, 127] : B.Bytes}

# MQTT packets
# ------------

# A QoS 1 retained publish with a non-ASCII topic survives a round trip.
law publish_roundtrip:
  {M.decode(M.encode(M.Publish{False{}, 1, True{}, "music/é", 7, [104, 105]}))
    == M.Got{M.Publish{False{}, 1, True{}, "music/é", 7, [104, 105]}, Nil{}} : M.Decoded}

# Bytes after a whole packet are handed back untouched.
law decode_keeps_rest:
  {M.decode([32, 2, 0, 0, 208, 0]) == M.Got{M.ConnAck{False{}, 0}, [208, 0]} : M.Decoded}

# A packet cut short asks for more bytes instead of failing.
law decode_partial:
  {M.decode([48, 200, 1, 0]) == M.More{} : M.Decoded}

# UTF-8
# -----

law utf8_roundtrip:
  {B.from_utf8(B.utf8("aé€😀")) == "aé€😀" : String}

# Malformed input is skipped, never fatal.
law utf8_lenient:
  {B.from_utf8([255, 128, 104, 105]) == "hi" : String}

# Base64
# ------

law b64_known:
  {B.b64e(B.utf8("Assistant!")) == B.utf8("QXNzaXN0YW50IQ==") : B.Bytes}

law b64_roundtrip:
  {B.from_utf8(B.b64d(B.b64e(B.utf8("Assistant!")))) == "Assistant!" : String}

# Examples from the specs
# =======================
# Byte-level round trips are costly to prove for every input in Bend, so
# these pin them down at the boundaries that matter.

# MQTT remaining length at every boundary of its 1..4 byte encoding.
law rlen_boundaries:
  {[M.rlen(127), M.rlen(128), M.rlen(16383), M.rlen(16384), M.rlen(2097151), M.rlen(2097152)]
    == [[127], [128, 1], [255, 127], [128, 128, 1], [255, 255, 127], [128, 128, 128, 1]]
    : List<&2, B.Bytes>}

# Every packet the broker sends the bridge decodes back to itself.
law broker_packets_roundtrip:
  {[M.decode(M.encode(M.ConnAck{True{}, 5})),
    M.decode(M.encode(M.Publish{False{}, 0, False{}, "a/b", 0, Nil{}})),
    M.decode(M.encode(M.PubAck{513})),
    M.decode(M.encode(M.SubAck{1, [0, 1, 128]})),
    M.decode(M.encode(M.PingResp{}))]
    == [M.Got{M.ConnAck{True{}, 5}, Nil{}},
        M.Got{M.Publish{False{}, 0, False{}, "a/b", 0, Nil{}}, Nil{}},
        M.Got{M.PubAck{513}, Nil{}},
        M.Got{M.SubAck{1, [0, 1, 128]}, Nil{}},
        M.Got{M.PingResp{}, Nil{}}] : List<&2, M.Decoded>}

def zeros(n: Nat) -> B.Bytes:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      0 <> zeros(p)

# A publish long enough for a two-byte length still round trips.
law long_publish_roundtrip:
  {M.decode(M.encode(M.Publish{False{}, 0, True{}, "t", 0, zeros(200n)}))
    == M.Got{M.Publish{False{}, 0, True{}, "t", 0, zeros(200n)}, Nil{}} : M.Decoded}

# Base64: the RFC 4648 test vectors, both ways.
law b64_rfc4648:
  {[B.b64e(B.utf8("")), B.b64e(B.utf8("f")), B.b64e(B.utf8("fo")), B.b64e(B.utf8("foo")),
    B.b64e(B.utf8("foob")), B.b64e(B.utf8("fooba")), B.b64e(B.utf8("foobar"))]
    == [B.utf8(""), B.utf8("Zg=="), B.utf8("Zm8="), B.utf8("Zm9v"),
        B.utf8("Zm9vYg=="), B.utf8("Zm9vYmE="), B.utf8("Zm9vYmFy")] : List<&2, B.Bytes>}

law b64_rfc4648_decode:
  {[B.b64d(B.utf8("Zg==")), B.b64d(B.utf8("Zm8=")), B.b64d(B.utf8("Zm9v")),
    B.b64d(B.utf8("Zm9vYg==")), B.b64d(B.utf8("Zm9vYmE=")), B.b64d(B.utf8("Zm9vYmFy"))]
    == [B.utf8("f"), B.utf8("fo"), B.utf8("foo"), B.utf8("foob"), B.utf8("fooba"),
        B.utf8("foobar")] : List<&2, B.Bytes>}

# Every byte value survives, including 0 and 255.
law b64_all_edges:
  {B.b64d(B.b64e([0, 255, 128, 127, 1, 254])) == [0, 255, 128, 127, 1, 254] : B.Bytes}

# UTF-8 at the edges of its 2, 3 and 4 byte forms survives decoding and encoding.
law utf8_boundaries:
  {[B.utf8(B.from_utf8([194, 128])), B.utf8(B.from_utf8([223, 191])),
    B.utf8(B.from_utf8([224, 160, 128])), B.utf8(B.from_utf8([239, 191, 191])),
    B.utf8(B.from_utf8([240, 144, 128, 128])), B.utf8(B.from_utf8([244, 143, 191, 191]))]
    == [[194, 128], [223, 191], [224, 160, 128], [239, 191, 191], [240, 144, 128, 128],
        [244, 143, 191, 191]] : List<&2, B.Bytes>}

# Bad bytes are dropped, never fatal: a stray continuation, a sequence cut short,
# an impossible lead byte between letters.
law utf8_bad_bytes:
  {[B.from_utf8([128]), B.from_utf8([226, 130]), B.from_utf8([104, 255, 105])]
    == ["", "", "hi"] : List<&2, String>}

# The bounded size check in MQTT decoding is the old full-length one.
law at_least_is_length_check:
  for +n: Nat
  for +xs: B.Bytes
  {M.at_least(n, xs) == Nat.is_le(n, List.length(&2, U32, xs)) : Bool}

# Networking: what a peer can make the bridge do
# ==============================================

# A packet declaring more than 64 KiB is refused, never buffered.
law mqtt_oversized_refused:
  for +hdr: U32
  for +t: B.Bytes
  for +n: U32
  for +rest: B.Bytes
  for hl: {M.len(t) == M.LGot{n, rest} : M.Len}
  for h: {U32.is_le(n, M.max_packet()) == False{} : Bool}
  {M.decode(hdr <> t) == M.Bad{} : M.Decoded}

# A reader only ever waits for more while holding no more than the largest
# packet plus its header: whatever a broker sends, the buffer stays bounded.
law mqtt_buffer_bounded:
  for +buf: B.Bytes
  for h: {M.verdict(buf) == M.More{} : M.Decoded}
  {M.over_cap(buf) == False{} : Bool}

# Every packet decoded consumes bytes: the rest handed back is shorter than the
# buffer, so a reader always moves forward and never sees a packet twice.
def progress(d: M.Decoded, +n: Nat) -> Bool:
  match d:
    case M.Got{_, r}:
      Nat.is_lt(List.length(&2, U32, r), n)
    case _:
      True{}

law mqtt_decode_progress:
  for +buf: B.Bytes
  {progress(M.decode(buf), List.length(&2, U32, buf)) == True{} : Bool}

# Byte-list equality means equal: what makes caching a lookup by its key safe.
law beq_sound:
  for +a: B.Bytes
  for +b: B.Bytes
  for h: {B.beq(a, b) == True{} : Bool}
  {a == b : B.Bytes}

# Every packet decoded takes at least two bytes off the buffer (a header byte and
# a length byte). The readers' buffers hold at most 65541 + 8192 bytes, so at
# most 36866 packets: their 40000 steps always empty a read.
def progress2(d: M.Decoded, +n: Nat) -> Bool:
  match d:
    case M.Got{_, r}:
      Nat.is_le(Nat.add(2n, List.length(&2, U32, r)), n)
    case _:
      True{}

law mqtt_decode_consumes_two:
  for +buf: B.Bytes
  {progress2(M.decode(buf), List.length(&2, U32, buf)) == True{} : Bool}
