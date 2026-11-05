import Base
import ../lib/wire/bytes.bend as B
import ../lib/ma/link.bend as L
import ../lib/wire/json.bend as J
import ../lib/wire/ws.bend as W
import ../laws/link.bend as Ll
import ./common.bend as Pc
# Proofs of laws/link.bend: the examples compute; the split is induction on xs (run is a fold).

def Ll.link_reads_hello():
  {==}

def Ll.link_reads_fragments():
  {==}

def Ll.link_garbled_then_fine():
  {==}

def Ll.link_refused():
  {==}

def Ll.link_feed_split(xs, ys, ws, l, hs):
  match xs:
    case Nil{}:
      {==}
    case b <> t:
      +s = L.step(ws, l, b)
      Ll.link_feed_split(t, ys, ws, L.step.link(s), L.keep(L.step.heard(s), hs))

# Privacy: a message comes only from J.finished, whose output is all wanted (Pc.finished_ok);
# the run keeps that for every byte, and feed's reversal keeps it too.

def message_ok(+ws: J.Wants, m: Maybe<&2, List<&2, J.Cap>>, h: {J.caps.ok(ws, m) == True{} : Bool})
    -> {Ll.heard.is_ok(ws, L.message(m)) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{caps}:
      h

def on_out_ok(+ws: J.Wants, dec: W.Dec, +scan: J.Scan, o: W.Out)
    -> {Ll.heard.maybe_ok(ws, L.step.heard(L.on_out(ws, dec, scan, o))) == True{} : Bool}:
  match o:
    case W.Nothing{}:
      {==}
    case W.Up{}:
      {==}
    case W.Byte{b}:
      {==}
    case W.Last{+b}:
      message_ok(ws, J.finished(ws, J.step(ws, scan, b)), Pc.finished_ok(ws, J.step(ws, scan, b)))
    case W.End{}:
      message_ok(ws, J.finished(ws, scan), Pc.finished_ok(ws, scan))
    case W.Ping{p}:
      {==}
    case W.Closed{}:
      {==}
    case W.Bad{why}:
      {==}

def step_ok(+ws: J.Wants, l: L.Link, +b: U32)
    -> {Ll.heard.maybe_ok(ws, L.step.heard(L.step(ws, l, b))) == True{} : Bool}:
  match l:
    case L.Link{+dec, +scan}:
      on_out_ok(ws, W.stepped.dec(W.step(dec, b)), scan, W.stepped.out(W.step(dec, b)))

def cons_ok(+ws: J.Wants, +x: L.Heard, +acc: List<&2, L.Heard>,
    h1: {Ll.heard.is_ok(ws, x) == True{} : Bool}, +h2: {Ll.heard.ok(ws, acc) == True{} : Bool})
    -> {Ll.heard.ok(ws, x <> acc) == True{} : Bool}:
  %Equal.sym(Bool, Ll.heard.is_ok(ws, x), True{}, h1) :
    {Bool.and(_, Ll.heard.ok(ws, acc)) == True{} : Bool}
  h2

def keep_ok(+ws: J.Wants, m: Maybe<&2, L.Heard>, +hs: List<&2, L.Heard>,
    h1: {Ll.heard.maybe_ok(ws, m) == True{} : Bool}, +h2: {Ll.heard.ok(ws, hs) == True{} : Bool})
    -> {Ll.heard.ok(ws, L.keep(m, hs)) == True{} : Bool}:
  match m:
    case None{}:
      h2
    case Some{+x}:
      cons_ok(ws, x, hs, h1, h2)

def run_ok(bs: B.Bytes, +ws: J.Wants, +l: L.Link, +hs: List<&2, L.Heard>,
    h: {Ll.heard.ok(ws, hs) == True{} : Bool})
    -> {Ll.heard.ok(ws, L.fed.heard(L.run(bs, ws, l, hs))) == True{} : Bool}:
  match bs:
    case Nil{}:
      h
    case +b <> t:
      run_ok(t, ws, L.step.link(L.step(ws, l, b)), L.keep(L.step.heard(L.step(ws, l, b)), hs),
        keep_ok(ws, L.step.heard(L.step(ws, l, b)), hs, step_ok(ws, l, b), h))

def rev_ok(xs: List<&2, L.Heard>, +acc: List<&2, L.Heard>, +ws: J.Wants,
    +h1: {Ll.heard.ok(ws, xs) == True{} : Bool}, +h2: {Ll.heard.ok(ws, acc) == True{} : Bool})
    -> {Ll.heard.ok(ws, List.reverse.go(&2, L.Heard, xs, acc)) == True{} : Bool}:
  match xs:
    case Nil{}:
      h2
    case +x <> +t:
      rev_ok(t, x <> acc, ws, Pc.and_r(Ll.heard.is_ok(ws, x), Ll.heard.ok(ws, t), h1),
        cons_ok(ws, x, acc, Pc.and_l(Ll.heard.is_ok(ws, x), Ll.heard.ok(ws, t), h1), h2))

def done_rev(f: L.Fed)
    -> {L.fed.heard(L.feed.done(f)) == List.reverse(&2, L.Heard, L.fed.heard(f))
        : List<&2, L.Heard>}:
  match f:
    case L.Fed{l, h}:
      {==}

def Ll.link_hears_only_wanted(ws, l, bs):
  %Equal.sym(List<&2, L.Heard>, L.fed.heard(L.feed.done(L.run(bs, ws, l, Nil{}))),
      List.reverse(&2, L.Heard, L.fed.heard(L.run(bs, ws, l, Nil{}))),
      done_rev(L.run(bs, ws, l, Nil{}))) :
    {Ll.heard.ok(ws, _) == True{} : Bool}
  rev_ok(L.fed.heard(L.run(bs, ws, l, Nil{})), Nil{}, ws, run_ok(bs, ws, l, Nil{}, {==}), {==})
