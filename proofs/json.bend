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

# Memory
# ------
# land is the only place the containers and the kept values change; each change it can make keeps
# size == limit (Pc.add_succ moves a unit between the list and its room), and a step is land.

def kept_add_ok(cap: Maybe<&2, J.Cap>, k: J.Kept, +h: {Lj.kept.size(k) == J.max_caps() : Nat})
    -> {Lj.kept.size(J.kept.add(cap, k)) == J.max_caps() : Nat}:
  match cap:
    case None{}:
      h
    case Some{c}:
      match k:
        case J.Kept{+cs, room}:
          match room:
            case 0n:
              h
            case 1n+r:
              %Pc.add_succ(List.length(&2, J.Cap, cs), r) : {_ == J.max_caps() : Nat}
              h

def push_stack_ok(st: J.Stack, f: J.Frame, m: J.Mode, k: J.Kept,
    +h: {Lj.stack.size(st) == J.max_depth() : Nat})
    -> {Lj.stack.size(J.scan.stack(J.stack.push(st, f, m, k))) == J.max_depth() : Nat}:
  match st:
    case J.Stack{+fs, room}:
      match room:
        case 0n:
          {==}
        case 1n+r:
          %Pc.add_succ(List.length(&2, J.Frame, fs), r) : {_ == J.max_depth() : Nat}
          h

def push_kept_ok(st: J.Stack, f: J.Frame, m: J.Mode, k: J.Kept,
    +h: {Lj.kept.size(k) == J.max_caps() : Nat})
    -> {Lj.kept.size(J.scan.kept(J.stack.push(st, f, m, k))) == J.max_caps() : Nat}:
  match st:
    case J.Stack{fs, room}:
      match room:
        case 0n:
          {==}
        case 1n+r:
          h

def pop_ok(st: J.Stack, +h: {Lj.stack.size(st) == J.max_depth() : Nat})
    -> {Lj.stack.size(J.stack.pop(st)) == J.max_depth() : Nat}:
  match st:
    case J.Stack{fs, +room}:
      match fs:
        case Nil{}:
          h
        case _ <> +rest:
          %Equal.sym(Nat, Nat.add(List.length(&2, J.Frame, rest), 1n+room),
              1n+Nat.add(List.length(&2, J.Frame, rest), room),
              Pc.add_succ(List.length(&2, J.Frame, rest), room)) :
            {_ == J.max_depth() : Nat}
          h

def top_ok(st: J.Stack, f: J.Frame, +h: {Lj.stack.size(st) == J.max_depth() : Nat})
    -> {Lj.stack.size(J.stack.top(st, f)) == J.max_depth() : Nat}:
  match st:
    case J.Stack{fs, room}:
      match fs:
        case Nil{}:
          h
        case _ <> rest:
          h

def land_stack_ok(+st: J.Stack, +k: J.Kept, mv: J.Move,
    +h: {Lj.stack.size(st) == J.max_depth() : Nat})
    -> {Lj.stack.size(J.scan.stack(J.land(st, k, mv))) == J.max_depth() : Nat}:
  match mv:
    case J.Breaks{why}:
      {==}
    case J.Goes{m, op, cap}:
      match op:
        case J.Stay{}:
          h
        case J.Push{f}:
          push_stack_ok(st, f, m, J.kept.add(cap, k), h)
        case J.Pop{}:
          pop_ok(st, h)
        case J.Top{f}:
          top_ok(st, f, h)

def land_kept_ok(+st: J.Stack, +k: J.Kept, mv: J.Move,
    +h: {Lj.kept.size(k) == J.max_caps() : Nat})
    -> {Lj.kept.size(J.scan.kept(J.land(st, k, mv))) == J.max_caps() : Nat}:
  match mv:
    case J.Breaks{why}:
      {==}
    case J.Goes{m, op, +cap}:
      match op:
        case J.Stay{}:
          kept_add_ok(cap, k, h)
        case J.Push{f}:
          push_kept_ok(st, f, m, J.kept.add(cap, k), kept_add_ok(cap, k, h))
        case J.Pop{}:
          kept_add_ok(cap, k, h)
        case J.Top{f}:
          kept_add_ok(cap, k, h)

def step_stack_ok(+ws: J.Wants, +s: J.Scan, +b: U32,
    +h: {Lj.stack.size(J.scan.stack(s)) == J.max_depth() : Nat})
    -> {Lj.stack.size(J.scan.stack(J.step(ws, s, b))) == J.max_depth() : Nat}:
  match s:
    case J.Scan{mode, +st, +k}:
      land_stack_ok(st, k, J.move(ws, mode, J.stack.frames(st), J.stack.full(st), b), h)

def step_kept_ok(+ws: J.Wants, +s: J.Scan, +b: U32,
    +h: {Lj.kept.size(J.scan.kept(s)) == J.max_caps() : Nat})
    -> {Lj.kept.size(J.scan.kept(J.step(ws, s, b))) == J.max_caps() : Nat}:
  match s:
    case J.Scan{mode, +st, +k}:
      land_kept_ok(st, k, J.move(ws, mode, J.stack.frames(st), J.stack.full(st), b), h)

def run_stack_ok(bs: B.Bytes, +ws: J.Wants, +s: J.Scan,
    +h: {Lj.stack.size(J.scan.stack(s)) == J.max_depth() : Nat})
    -> {Lj.stack.size(J.scan.stack(J.run(bs, ws, s))) == J.max_depth() : Nat}:
  match bs:
    case Nil{}:
      h
    case +b <> t:
      run_stack_ok(t, ws, J.step(ws, s, b), step_stack_ok(ws, s, b, h))

def run_kept_ok(bs: B.Bytes, +ws: J.Wants, +s: J.Scan,
    +h: {Lj.kept.size(J.scan.kept(s)) == J.max_caps() : Nat})
    -> {Lj.kept.size(J.scan.kept(J.run(bs, ws, s))) == J.max_caps() : Nat}:
  match bs:
    case Nil{}:
      h
    case +b <> t:
      run_kept_ok(t, ws, J.step(ws, s, b), step_kept_ok(ws, s, b, h))

def Lj.json_depth_bounded(ws, bs):
  run_stack_ok(bs, ws, J.start(), {==})

def Lj.json_kept_bounded(ws, bs):
  run_kept_ok(bs, ws, J.start(), {==})
