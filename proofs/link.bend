import Base
import ../lib/wire/bytes.bend as B
import ../lib/ma/link.bend as L
import ../laws/link.bend as Ll
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
