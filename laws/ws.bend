import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/ws.bend as W
# The WebSocket client's wire format (lib/wire/ws.bend).

# What came out of a run of bytes from a fresh decoder, oldest first.
def outs_after(d: W.Dec, bs: B.Bytes) -> List<&2, W.Out>:
  W.fed.outs(W.feed(d, bs))

def hello() -> B.Bytes:
  [72, 101, 108, 108, 111]

# Examples from RFC 6455 (section 5.7)
# ===================================

# A masked text frame of "Hello" (mask 37 fa 21 3d): our client frame, byte for byte.
law ws_rfc_masked_text:
  {W.text(939139389, B.utf8("Hello")) == [129, 133, 55, 250, 33, 61, 127, 159, 77, 81, 88] : B.Bytes}

# The masked pong with the same payload and mask.
law ws_rfc_masked_pong:
  {W.pong(939139389, hello()) == [138, 133, 55, 250, 33, 61, 127, 159, 77, 81, 88] : B.Bytes}

# An unmasked text frame of "Hello" from the server: its bytes, the last marked.
law ws_rfc_unmasked_text:
  {outs_after(W.framing(), [129, 5, 72, 101, 108, 108, 111])
    == [W.Byte{72}, W.Byte{101}, W.Byte{108}, W.Byte{108}, W.Last{111}] : List<&2, W.Out>}

# "Hel" then "lo" in two fragments: one message.
law ws_rfc_fragmented_text:
  {outs_after(W.framing(), [1, 3, 72, 101, 108, 128, 2, 108, 111])
    == [W.Byte{72}, W.Byte{101}, W.Byte{108}, W.Byte{108}, W.Last{111}] : List<&2, W.Out>}

# A ping with "Hello": to be answered with that payload.
law ws_rfc_ping:
  {outs_after(W.framing(), [137, 5, 72, 101, 108, 108, 111]) == [W.Ping{hello()}]
    : List<&2, W.Out>}

# A pong from the server needs nothing.
law ws_rfc_pong_ignored:
  {outs_after(W.framing(), [138, 5, 72, 101, 108, 108, 111]) == Nil{} : List<&2, W.Out>}

# Length encodings at their boundaries: 7 bits up to 125, 16 bits from 126, 64 from 65536.
law ws_length_boundaries:
  {[W.length(125), W.length(126), W.length(65535), W.length(65536)]
    == [[253], [254, 0, 126], [254, 255, 255], [255, 0, 0, 0, 0, 0, 1, 0, 0]]
    : List<&2, B.Bytes>}

# The upgrade
# ===========

# A 101 answer opens the stream, and frames right behind it in the same bytes are read.
law ws_upgrade_accepted:
  {outs_after(W.start(),
     B.cat(B.utf8("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n"),
       [129, 1, 123]))
    == [W.Up{}, W.Last{123}] : List<&2, W.Out>}

# Any other status is refused, with the status line in the reason.
law ws_upgrade_refused:
  {outs_after(W.start(), B.utf8("HTTP/1.1 401 Unauthorized\r\n\r\n"))
    == [W.Bad{"upgrade refused: HTTP/1.1 401"}] : List<&2, W.Out>}

# An answer whose headers pass max_head bytes is refused at the byte that passes it.
law ws_upgrade_bounded:
  for matched: U32
  for status: B.Bytes
  for open: Bool
  for b: U32
  {W.step(W.Dec{W.Head{matched, status, 8192}, open}, b) == W.dead("upgrade answer too long")
    : W.Stepped}

# Refusals
# ========

# A server must not mask its frames.
law ws_masked_server_frame_refused:
  {outs_after(W.framing(), [129, 133, 55, 250, 33, 61, 127])
    == [W.Bad{"masked frame from the server"}] : List<&2, W.Out>}

# A control frame can't carry more than 125 bytes.
law ws_big_control_refused:
  {outs_after(W.framing(), [137, 126, 0, 200])
    == [W.Bad{"control frame over 125 bytes"}] : List<&2, W.Out>}

# A continuation outside a message, and a new message inside one, are refused.
law ws_stray_continuation_refused:
  {outs_after(W.framing(), [128, 1, 65]) == [W.Bad{"unexpected frame (opcode 0)"}]
    : List<&2, W.Out>}

law ws_interleaved_message_refused:
  {outs_after(W.framing(), [1, 1, 65, 129, 1, 66])
    == [W.Byte{65}, W.Bad{"unexpected frame (opcode 1)"}] : List<&2, W.Out>}

# For every input
# ===============

# However the socket splits the bytes, the decoder ends the same and gives the same things.
law ws_feed_split:
  for xs: B.Bytes
  for +ys: B.Bytes
  for +d: W.Dec
  for +acc: List<&2, W.Out>
  {W.run(B.cat(xs, ys), d, acc)
    == W.run(ys, W.fed.dec(W.run(xs, d, acc)), W.fed.outs(W.run(xs, d, acc))) : W.Fed}

# After a refusal or a close nothing more comes out, whatever arrives.
law ws_dead_absorbs:
  for bs: B.Bytes
  for open: Bool
  for +acc: List<&2, W.Out>
  {W.fed.outs(W.run(bs, W.Dec{W.Dead{}, open}, acc)) == acc : List<&2, W.Out>}
