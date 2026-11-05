import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/json.bend as J
import ../laws/json.bend as Lj
import ./common.bend as Pc

def Lj.json_keeps_wanted():
  {==}

def Lj.json_any_index():
  {==}

def Lj.json_escapes():
  {==}

def Lj.json_lone_surrogate():
  {==}

def Lj.json_refuses_broken():
  {==}

def Lj.json_depth_capped():
  {==}

def Lj.json_writes():
  {==}

# Induction on xs: run is a fold.
def Lj.json_feed_split(xs, ys, ws, s):
  match xs:
    case Nil{}:
      {==}
    case b <> t:
      Lj.json_feed_split(t, ys, ws, J.step(ws, s, b))

# Induction on bs: a broken scanner steps to the same broken scanner.
def Lj.json_broken_absorbs(bs, ws, why):
  match bs:
    case Nil{}:
      {==}
    case _ <> t:
      Lj.json_broken_absorbs(t, ws, why)

def Lj.json_finished_only_wanted(ws, s):
  Pc.finished_ok(ws, s)

def Lj.json_scan_only_wanted(ws, bs):
  Pc.finished_ok(ws, J.run(bs, ws, J.start()))
