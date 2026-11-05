import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/ws.bend as W
import ../laws/ws.bend as Lws
import ./common.bend as Pc

def Lws.ws_rfc_masked_text():
  {==}

def Lws.ws_rfc_masked_pong():
  {==}

def Lws.ws_rfc_unmasked_text():
  {==}

def Lws.ws_rfc_fragmented_text():
  {==}

def Lws.ws_rfc_ping():
  {==}

def Lws.ws_rfc_pong_ignored():
  {==}

def Lws.ws_length_boundaries():
  {==}

def Lws.ws_upgrade_accepted():
  {==}

def Lws.ws_upgrade_refused():
  {==}

# The size check comes first: 8193 > 8192 whatever else the decoder holds.
def Lws.ws_upgrade_bounded(matched, status, open, b):
  {==}

def Lws.ws_masked_server_frame_refused():
  {==}

def Lws.ws_big_control_refused():
  {==}

def Lws.ws_stray_continuation_refused():
  {==}

def Lws.ws_interleaved_message_refused():
  {==}

# Induction on xs: run is a fold, so the head byte's step is the same either way.
def Lws.ws_feed_split(xs, ys, d, acc):
  match xs:
    case Nil{}:
      {==}
    case b <> t:
      +s = W.step(d, b)
      Lws.ws_feed_split(t, ys, W.stepped.dec(s), W.keep(W.stepped.out(s), acc))

# Induction on bs: a dead decoder steps to a dead decoder with nothing out.
def Lws.ws_dead_absorbs(bs, open, acc):
  match bs:
    case Nil{}:
      {==}
    case _ <> t:
      Lws.ws_dead_absorbs(t, False{}, acc)
