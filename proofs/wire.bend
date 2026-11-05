import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M
import ../laws/wire.bend as Lw
import ./common.bend as Pc

# Proofs of laws/wire.bend

# The number of bytes (a name for the term these proofs repeat).
def size(xs: B.Bytes) -> Nat:
  List.length(&2, U32, xs)

# Whether a decoded length leaves at most n bytes (true when it decoded none).
def rest_at_most(l: M.Len, +n: Nat) -> Bool:
  match l:
    case M.LGot{_, rest}:
      Nat.is_le(List.length(&2, U32, rest), n)
    case _:
      True{}

# Whether it leaves fewer than n bytes (true when it decoded none).
def rest_below(l: M.Len, +n: Nat) -> Bool:
  match l:
    case M.LGot{_, rest}:
      Nat.is_lt(List.length(&2, U32, rest), n)
    case _:
      True{}

# By cases on p; each case computes.
def le_one(p: Nat) -> {Nat.is_le(1n, 1n+p) == True{} : Bool}:
  match p:
    case 0n:
      {==}
    case 1n+q:
      {==}

# Induction on the fuel: each step emits one byte and spends one unit.
def Lw.rlen_bounded(fuel, small, n):
  match fuel:
    case 0n:
      {==}
    case 1n+p:
      match small:
        case True{}:
          le_one(p)
        case False{}:
          Lw.rlen_bounded(p, ((n >> 7n) < 128 : U32), (n >> 7n : U32))

# By computation: both sides reduce to the same value.
def Lw.rlen_max():
  {==}

# By computation: both sides reduce to the same value.
def Lw.publish_roundtrip():
  {==}

# By computation: both sides reduce to the same value.
def Lw.decode_keeps_rest():
  {==}

# By computation: both sides reduce to the same value.
def Lw.decode_partial():
  {==}

# By computation: both sides reduce to the same value.
def Lw.utf8_roundtrip():
  {==}

# By computation: both sides reduce to the same value.
def Lw.utf8_lenient():
  {==}

# By computation: both sides reduce to the same value.
def Lw.b64_known():
  {==}

# By computation: both sides reduce to the same value.
def Lw.b64_roundtrip():
  {==}

# By computation: both sides reduce to the same value.

# By computation: both sides reduce to the same value.

# By computation: both sides reduce to the same value.

# By computation: both sides reduce to the same value.

# By computation: both sides reduce to the same value.

# By computation: both sides reduce to the same value.
def Lw.rlen_boundaries():
  {==}

# By computation: both sides reduce to the same value.
def Lw.broker_packets_roundtrip():
  {==}

# By computation: both sides reduce to the same value.
def Lw.long_publish_roundtrip():
  {==}

# By computation: both sides reduce to the same value.
def Lw.b64_rfc4648():
  {==}

# By computation: both sides reduce to the same value.
def Lw.b64_rfc4648_decode():
  {==}

# By computation: both sides reduce to the same value.
def Lw.b64_all_edges():
  {==}

# By computation: both sides reduce to the same value.
def Lw.utf8_boundaries():
  {==}

# By computation: both sides reduce to the same value.
def Lw.utf8_bad_bytes():
  {==}

# Induction on n and the bytes together.
def Lw.at_least_is_length_check(n, xs):
  match n:
    case 0n:
      match xs:
        case Nil{}:
          {==}
        case x <> t:
          {==}
    case 1n+p:
      match xs:
        case Nil{}:
          {==}
        case x <> t:
          Lw.at_least_is_length_check(p, t)

# Rewrite the length, then the size check, to what the law assumes.
def Lw.mqtt_oversized_refused(hdr, t, n, rest, hl, h):
  %Equal.sym(M.Len, M.len(t), M.LGot{n, rest}, hl) :
    {M.decode.on_len(_, hdr) == M.Bad{} : M.Decoded}
  %Equal.sym(Bool, U32.is_le(n, M.max_packet()), False{}, h) :
    {M.decode.if_allowed(_, hdr, n, rest) == M.Bad{} : M.Decoded}
  {==}

# The buffer bound
# ----------------

# A motive that tells More from the other results.
def dmore(d: M.Decoded) -> Type:
  match d:
    case M.More{}:
      Unit
    case _:
      Empty

# Bad is not More: rewrite dmore(More) into dmore(Bad).
def not_more_bad(e: {M.Bad{} == M.More{} : M.Decoded}) -> Empty:
  %Equal.sym(M.Decoded, M.Bad{}, M.More{}, e) : dmore(_)
  Unit{}

# Got is not More, the same way.
def not_more_got(+p: M.Packet, +r: B.Bytes, e: {M.Got{p, r} == M.More{} : M.Decoded}) -> Empty:
  %Equal.sym(M.Decoded, M.Got{p, r}, M.More{}, e) : dmore(_)
  Unit{}

# Only More with the buffer not over the cap gives More; the other cases
# contradict the hypothesis.
def verdict_more(d: M.Decoded, over: Bool,
  h: {M.verdict.on_decoded(d, over) == M.More{} : M.Decoded}) -> {over == False{} : Bool}:
  match d:
    case M.More{}:
      match over:
        case True{}:
          Pc.ex_falso({True{} == False{} : Bool}, not_more_bad(h))
        case False{}:
          {==}
    case M.Bad{}:
      Pc.ex_falso({over == False{} : Bool}, not_more_bad(h))
    case M.Got{p, r}:
      Pc.ex_falso({over == False{} : Bool}, not_more_got(p, r, h))

# verdict_more on the decode and the cap test.
def Lw.mqtt_buffer_bounded(buf, h):
  verdict_more(M.decode(buf), M.over_cap(buf), h)

# Order on Nat
# ------------

# By induction on n.
def le_refl(+n: Nat) -> {Nat.is_le(n, n) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      le_refl(p)

# By induction on n.
def le_succ(+n: Nat) -> {Nat.is_le(n, 1n+n) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      le_succ(p)

# By induction on a, b and c together.
def le_trans(+a: Nat, +b: Nat, +c: Nat,
  h1: {Nat.is_le(a, b) == True{} : Bool},
  h2: {Nat.is_le(b, c) == True{} : Bool}) -> {Nat.is_le(a, c) == True{} : Bool}:
  match a:
    case 0n:
      match c:
        case 0n:
          {==}
        case 1n+q:
          {==}
    case 1n+x:
      match b:
        case 0n:
          Pc.ex_falso({Nat.is_le(1n+x, c) == True{} : Bool}, Pc.absurd_ft(h1))
        case 1n+y:
          match c:
            case 0n:
              Pc.ex_falso({Nat.is_le(1n+x, 0n) == True{} : Bool}, Pc.absurd_ft(h2))
            case 1n+z:
              le_trans(x, y, z, h1, h2)

# By induction on a and b together.
def le_lt_succ(+a: Nat, +b: Nat,
  h: {Nat.is_le(a, b) == True{} : Bool}) -> {Nat.is_lt(a, 1n+b) == True{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+x:
      match b:
        case 0n:
          Pc.ex_falso({Nat.is_lt(1n+x, 1n) == True{} : Bool}, Pc.absurd_ft(h))
        case 1n+y:
          le_lt_succ(x, y, h)

# Dropping bytes never makes a list longer.
def drop_le(+xs: B.Bytes, +k: Nat)
    -> {Nat.is_le(size(List.drop(&2, U32, xs, k)), size(xs)) == True{} : Bool}:
  match xs:
    case Nil{}:
      {==}
    case +x <> +t:
      match k:
        case 0n:
          le_refl(1n+size(t))
        case 1n+p:
          le_trans(size(List.drop(&2, U32, t, p)), size(t), 1n+size(t),
            drop_le(t, p), le_succ(size(t)))

# Decoding makes progress
# -----------------------
# rest_at_most(l, n): the bytes after a decoded length are at most n. Each step
# of the unrolled length decoder (M.len.if_last<k>, M.len.byte<k>) keeps it,
# weakening by one per byte read.

# A rest within n is within n + 1: le_trans with le_succ.
def weaken(+l: M.Len, +n: Nat,
  h: {rest_at_most(l, n) == True{} : Bool}) -> {rest_at_most(l, 1n+n) == True{} : Bool}:
  match l:
    case M.LGot{x, +rest}:
      le_trans(size(rest), n, 1n+n, h, le_succ(n))
    case M.LMore{}:
      {==}
    case M.LBad{}:
      {==}

# By cases on last: the rest is t (le_refl), or there is none (too long a length).
def last3_l(last: Bool, +n: U32, +t: B.Bytes)
    -> {rest_at_most(M.len.if_last3(last, n, t), size(t)) == True{} : Bool}:
  match last:
    case True{}:
      le_refl(size(t))
    case False{}:
      {==}

# By cases on bs: a byte read leaves at most the rest after it (last3_l, weakened).
def byte3_l(+acc: U32, +bs: B.Bytes)
    -> {rest_at_most(M.len.byte3(acc, bs), size(bs)) == True{} : Bool}:
  match bs:
    case Nil{}:
      {==}
    case +b <> +t:
      +n = (acc .|. ((b .&. 127) << 21n) : U32)
      weaken(M.len.if_last3((b < 128 : U32), n, t), size(t), last3_l((b < 128 : U32), n, t))

# By cases on last: the rest is t (le_refl), or what the next byte leaves (byte3_l).
def last2_l(last: Bool, +n: U32, +t: B.Bytes)
    -> {rest_at_most(M.len.if_last2(last, n, t), size(t)) == True{} : Bool}:
  match last:
    case True{}:
      le_refl(size(t))
    case False{}:
      byte3_l(n, t)

# By cases on bs: a byte read leaves at most the rest after it (last2_l, weakened).
def byte2_l(+acc: U32, +bs: B.Bytes)
    -> {rest_at_most(M.len.byte2(acc, bs), size(bs)) == True{} : Bool}:
  match bs:
    case Nil{}:
      {==}
    case +b <> +t:
      +n = (acc .|. ((b .&. 127) << 14n) : U32)
      weaken(M.len.if_last2((b < 128 : U32), n, t), size(t), last2_l((b < 128 : U32), n, t))

# By cases on last: the rest is t (le_refl), or what the next byte leaves (byte2_l).
def last1_l(last: Bool, +n: U32, +t: B.Bytes)
    -> {rest_at_most(M.len.if_last1(last, n, t), size(t)) == True{} : Bool}:
  match last:
    case True{}:
      le_refl(size(t))
    case False{}:
      byte2_l(n, t)

# By cases on bs: a byte read leaves at most the rest after it (last1_l, weakened).
def byte1_l(+acc: U32, +bs: B.Bytes)
    -> {rest_at_most(M.len.byte1(acc, bs), size(bs)) == True{} : Bool}:
  match bs:
    case Nil{}:
      {==}
    case +b <> +t:
      +n = (acc .|. ((b .&. 127) << 7n) : U32)
      weaken(M.len.if_last1((b < 128 : U32), n, t), size(t), last1_l((b < 128 : U32), n, t))

# By cases on last: the rest is t (le_refl), or what the next byte leaves (byte1_l).
def last0_l(last: Bool, +n: U32, +t: B.Bytes)
    -> {rest_at_most(M.len.if_last0(last, n, t), size(t)) == True{} : Bool}:
  match last:
    case True{}:
      le_refl(size(t))
    case False{}:
      byte1_l(n, t)

# The length's first byte is read, then last0_l, weakened by one.
def top_l(+t: B.Bytes) -> {rest_at_most(M.len(t), size(t)) == True{} : Bool}:
  match t:
    case Nil{}:
      {==}
    case +b <> +r:
      weaken(M.len.if_last0((b < 128 : U32), (b .&. 127 : U32), r), size(r),
        last0_l((b < 128 : U32), (b .&. 127 : U32), r))

# Then down the decoder (M.decode.on_len, .if_allowed, .if_enough,
# .on_reader, .on_packet): what is handed back is the rest after the body,
# shorter than the buffer.

# By cases on the packet: a decoded one leaves rest2, shorter than n.
def on_packet_p(m: Maybe<&1, M.Packet>, +rest2: B.Bytes, +n: Nat,
  h: {Nat.is_lt(size(rest2), n) == True{} : Bool})
    -> {Lw.progress(M.decode.on_packet(m, rest2), n) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{p}:
      h

# By cases on the reader: on_packet_p on what it read.
def on_reader_p(r: Maybe<&1, B.Rd(M.Packet)>, body: B.Bytes, +rest2: B.Bytes, +n: Nat,
  h: {Nat.is_lt(size(rest2), n) == True{} : Bool})
    -> {Lw.progress(M.decode.on_reader(r, body, rest2), n) == True{} : Bool}:
  match r:
    case None{}:
      {==}
    case Some{rd}:
      on_packet_p(B.Rd.ok(M.Packet, B.Rd.run(M.Packet, rd, body)), rest2, n, h)

# By cases on enough: a whole packet goes to on_reader_p.
def if_enough_p(enough: Bool, +hdr: U32, +k: Nat, +rest: B.Bytes, +n: Nat,
  h: {Nat.is_lt(size(List.drop(&2, U32, rest, k)), n) == True{} : Bool})
    -> {Lw.progress(M.decode.if_enough(enough, hdr, k, rest), n) == True{} : Bool}:
  match enough:
    case False{}:
      {==}
    case True{}:
      on_reader_p(M.body_r((hdr >> 4n : U32), (hdr .&. 15 : U32)),
        List.take(&2, U32, rest, k), List.drop(&2, U32, rest, k), n, h)

# By cases on ok: an allowed length goes to if_enough_p.
def if_allowed_p(ok: Bool, +hdr: U32, +nn: U32, +rest: B.Bytes, +t: B.Bytes,
  hr: {Nat.is_le(size(rest), size(t)) == True{} : Bool})
    -> {Lw.progress(M.decode.if_allowed(ok, hdr, nn, rest), 1n+size(t)) == True{} : Bool}:
  match ok:
    case False{}:
      {==}
    case True{}:
      +k = U32.to_nat(nn)
      +after = List.drop(&2, U32, rest, k)
      if_enough_p(M.at_least(k, rest), hdr, k, rest, 1n+size(t),
        le_lt_succ(size(after), size(t),
          le_trans(size(after), size(rest), size(t), drop_le(rest, k), hr)))

# By cases on the length: a decoded one goes to if_allowed_p.
def on_len_p(+l: M.Len, +hdr: U32, +t: B.Bytes,
  hl: {rest_at_most(l, size(t)) == True{} : Bool})
    -> {Lw.progress(M.decode.on_len(l, hdr), 1n+size(t)) == True{} : Bool}:
  match l:
    case M.LMore{}:
      {==}
    case M.LBad{}:
      {==}
    case M.LGot{+nn, +rest}:
      if_allowed_p(U32.is_le(nn, M.max_packet()), hdr, nn, rest, t, hl)

# The length decoder keeps lprop (top_l); the rest follows down the decoder.
def Lw.mqtt_decode_progress(buf):
  match buf:
    case Nil{}:
      {==}
    case +hdr <> +t:
      on_len_p(M.len(t), hdr, t, top_l(t))

# Two bytes a packet
# ------------------
# The same walk with rest_below (the rest is shorter than the bytes after the
# header byte), so a packet takes at least two bytes.

# A rest within n is below n + 1: le_lt_succ.
def lift2(+l: M.Len, +n: Nat,
  h: {rest_at_most(l, n) == True{} : Bool}) -> {rest_below(l, 1n+n) == True{} : Bool}:
  match l:
    case M.LGot{+nn, +rest}:
      le_lt_succ(size(rest), n, h)
    case M.LMore{}:
      {==}
    case M.LBad{}:
      {==}

# As top_l, with lift2: the rest is below the bytes after the header.
def top_l2(+t: B.Bytes) -> {rest_below(M.len(t), size(t)) == True{} : Bool}:
  match t:
    case Nil{}:
      {==}
    case +b <> +r:
      lift2(M.len.if_last0((b < 128 : U32), (b .&. 127 : U32), r), size(r),
        last0_l((b < 128 : U32), (b .&. 127 : U32), r))

# By cases on q; each case computes.
def le_zero(+q: Nat) -> {Nat.is_le(0n, q) == True{} : Bool}:
  match q:
    case 0n:
      {==}
    case 1n+r:
      {==}

# By induction on a and b together.
def lt_le_succ(+a: Nat, +b: Nat,
  h: {Nat.is_lt(a, b) == True{} : Bool}) -> {Nat.is_le(1n+a, b) == True{} : Bool}:
  match a:
    case 0n:
      match b:
        case 0n:
          Pc.ex_falso({Nat.is_le(1n, 0n) == True{} : Bool}, Pc.absurd_ft(h))
        case 1n+q:
          le_zero(q)
    case 1n+a2:
      match b:
        case 0n:
          Pc.ex_falso({Nat.is_le(1n+1n+a2, 0n) == True{} : Bool}, Pc.absurd_ft(h))
        case 1n+b2:
          lt_le_succ(a2, b2, h)

# By induction on a, b and c together.
def le_lt_trans(+a: Nat, +b: Nat, +c: Nat,
  h1: {Nat.is_le(a, b) == True{} : Bool},
  h2: {Nat.is_lt(b, c) == True{} : Bool}) -> {Nat.is_lt(a, c) == True{} : Bool}:
  match a:
    case 0n:
      match b:
        case 0n:
          match c:
            case 0n:
              Pc.ex_falso({Nat.is_lt(0n, 0n) == True{} : Bool}, Pc.absurd_ft(h2))
            case 1n+c2:
              {==}
        case 1n+b2:
          match c:
            case 0n:
              Pc.ex_falso({Nat.is_lt(0n, 0n) == True{} : Bool}, Pc.absurd_ft(h2))
            case 1n+c2:
              {==}
    case 1n+a2:
      match b:
        case 0n:
          Pc.ex_falso({Nat.is_lt(1n+a2, c) == True{} : Bool}, Pc.absurd_ft(h1))
        case 1n+b2:
          match c:
            case 0n:
              Pc.ex_falso({Nat.is_lt(1n+a2, 0n) == True{} : Bool}, Pc.absurd_ft(h2))
            case 1n+c2:
              le_lt_trans(a2, b2, c2, h1, h2)

# By cases on the packet: a decoded one used at least two bytes.
def on_packet_q(m: Maybe<&1, M.Packet>, +rest2: B.Bytes, +n: Nat,
  h: {Nat.is_le(Nat.add(2n, size(rest2)), n) == True{} : Bool})
    -> {Lw.progress2(M.decode.on_packet(m, rest2), n) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{p}:
      h

# By cases on the reader: on_packet_q on what it read.
def on_reader_q(r: Maybe<&1, B.Rd(M.Packet)>, body: B.Bytes, +rest2: B.Bytes, +n: Nat,
  h: {Nat.is_le(Nat.add(2n, size(rest2)), n) == True{} : Bool})
    -> {Lw.progress2(M.decode.on_reader(r, body, rest2), n) == True{} : Bool}:
  match r:
    case None{}:
      {==}
    case Some{rd}:
      on_packet_q(B.Rd.ok(M.Packet, B.Rd.run(M.Packet, rd, body)), rest2, n, h)

# By cases on enough: a whole packet goes to on_reader_q.
def if_enough_q(enough: Bool, +hdr: U32, +k: Nat, +rest: B.Bytes, +n: Nat,
  h: {Nat.is_le(Nat.add(2n, size(List.drop(&2, U32, rest, k))), n) == True{} : Bool})
    -> {Lw.progress2(M.decode.if_enough(enough, hdr, k, rest), n) == True{} : Bool}:
  match enough:
    case False{}:
      {==}
    case True{}:
      on_reader_q(M.body_r((hdr >> 4n : U32), (hdr .&. 15 : U32)),
        List.take(&2, U32, rest, k), List.drop(&2, U32, rest, k), n, h)

# By cases on ok: an allowed length goes to if_enough_q.
def if_allowed_q(ok: Bool, +hdr: U32, +nn: U32, +rest: B.Bytes, +t: B.Bytes,
  hr: {Nat.is_lt(size(rest), size(t)) == True{} : Bool})
    -> {Lw.progress2(M.decode.if_allowed(ok, hdr, nn, rest), 1n+size(t)) == True{} : Bool}:
  match ok:
    case False{}:
      {==}
    case True{}:
      +k = U32.to_nat(nn)
      +after = List.drop(&2, U32, rest, k)
      if_enough_q(M.at_least(k, rest), hdr, k, rest, 1n+size(t),
        lt_le_succ(size(after), size(t),
          le_lt_trans(size(after), size(rest), size(t), drop_le(rest, k), hr)))

# By cases on the length: a decoded one goes to if_allowed_q.
def on_len_q(+l: M.Len, +hdr: U32, +t: B.Bytes,
  hl: {rest_below(l, size(t)) == True{} : Bool})
    -> {Lw.progress2(M.decode.on_len(l, hdr), 1n+size(t)) == True{} : Bool}:
  match l:
    case M.LMore{}:
      {==}
    case M.LBad{}:
      {==}
    case M.LGot{+nn, +rest}:
      if_allowed_q(U32.is_le(nn, M.max_packet()), hdr, nn, rest, t, hl)

# By cases on buf: a header byte, then on_len_q with top_l2.
def Lw.mqtt_decode_consumes_two(buf):
  match buf:
    case Nil{}:
      {==}
    case +hdr <> +t:
      on_len_q(M.len(t), hdr, t, top_l2(t))
