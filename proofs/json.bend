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

# Buffers
# -------
# Every Txt the scanner makes is fresh (empty, all its room) or comes from txt.add, which moves a
# unit of room into the bytes (Pc.add_succ); a number likewise; land keeps the move's mode.

def op.ok(op: J.Op) -> Bool:
  match op:
    case J.Push{f}:
      Lj.frame.ok(f)
    case J.Top{f}:
      Lj.frame.ok(f)
    case _:
      True{}

def mcap.ok(c: Maybe<&2, J.Cap>) -> Bool:
  match c:
    case None{}:
      True{}
    case Some{x}:
      Lj.cap.ok(x)

# A move keeps the buffers within their room, opens containers with small keys and keeps only
# small values (the always-true parts first, so a move that only changes the mode reduces to it).
def mv.ok(mv: J.Move) -> Bool:
  match mv:
    case J.Breaks{_}:
      True{}
    case J.Goes{m, op, cap}:
      Bool.and(Bool.and(op.ok(op), mcap.ok(cap)), Lj.mode.ok(m))

def both(+a: Bool, +b: Bool, +ha: {a == True{} : Bool}, +hb: {b == True{} : Bool})
    -> {Bool.and(a, b) == True{} : Bool}:
  %Equal.sym(Bool, a, True{}, ha) : {Bool.and(_, b) == True{} : Bool}
  hb

# Numbers: a part of a sum is at most the sum; a sum that is m bounds its parts by m.
def le_add(+a: Nat, +r: Nat) -> {Nat.is_le(a, Nat.add(a, r)) == True{} : Bool}:
  match a:
    case 0n:
      match r:
        case 0n:
          {==}
        case 1n+_:
          {==}
    case 1n+p:
      le_add(p, r)

def le_of_add_eq(+a: Nat, +r: Nat, +m: Nat, +h: {Nat.add(a, r) == m : Nat})
    -> {Nat.is_le(a, m) == True{} : Bool}:
  %h : {Nat.is_le(a, _) == True{} : Bool}
  le_add(a, r)

def le_of_is_eq(+a: Nat, +r: Nat, +m: Nat, +h: {Nat.is_eq(Nat.add(a, r), m) == True{} : Bool})
    -> {Nat.is_le(a, m) == True{} : Bool}:
  match a:
    case 0n:
      match m:
        case 0n:
          {==}
        case 1n+_:
          {==}
    case 1n+p:
      match m:
        case 0n:
          Pc.ex_falso({Nat.is_le(1n+p, 0n) == True{} : Bool}, Pc.absurd_ft(h))
        case 1n+q:
          le_of_is_eq(p, r, q, h)

# Reversing keeps the length.
def rev_go_len(+xs: B.Bytes, +acc: B.Bytes)
    -> {List.length(&2, U32, List.reverse.go(&2, U32, xs, acc))
        == Nat.add(List.length(&2, U32, xs), List.length(&2, U32, acc)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case x <> t:
      %Pc.add_succ(List.length(&2, U32, t), List.length(&2, U32, acc)) :
        {List.length(&2, U32, List.reverse.go(&2, U32, t, x <> acc)) == _ : Nat}
      rev_go_len(t, x <> acc)

def rev_len(+xs: B.Bytes)
    -> {List.length(&2, U32, List.reverse(&2, U32, xs)) == List.length(&2, U32, xs) : Nat}:
  %Pc.add_zero(List.length(&2, U32, xs)) :
    {List.length(&2, U32, List.reverse(&2, U32, xs)) == _ : Nat}
  rev_go_len(xs, Nil{})

def rev_le(+acc: B.Bytes, +m: Nat, +h: {Nat.is_le(List.length(&2, U32, acc), m) == True{} : Bool})
    -> {Nat.is_le(List.length(&2, U32, List.reverse(&2, U32, acc)), m) == True{} : Bool}:
  %Equal.sym(Nat, List.length(&2, U32, List.reverse(&2, U32, acc)), List.length(&2, U32, acc),
      rev_len(acc)) : {Nat.is_le(_, m) == True{} : Bool}
  h

# Paths: as long as the open containers, their keys theirs.
def seg_ok_of(+f: J.Frame, +h: {Lj.frame.ok(f) == True{} : Bool})
    -> {Lj.seg.ok(J.seg(f)) == True{} : Bool}:
  match f:
    case J.InObj{_}:
      h
    case J.InArr{_}:
      {==}

def ploop_segs(+fs: List<&2, J.Frame>, +acc: List<&2, J.Seg>,
    +hf: {Lj.frames.ok(fs) == True{} : Bool}, +ha: {Lj.segs.ok(acc) == True{} : Bool})
    -> {Lj.segs.ok(J.path.loop(fs, acc)) == True{} : Bool}:
  match fs:
    case Nil{}:
      ha
    case f <> t:
      ploop_segs(t, J.seg(f) <> acc, Pc.and_r(Lj.frame.ok(f), Lj.frames.ok(t), hf),
        both(Lj.seg.ok(J.seg(f)), Lj.segs.ok(acc),
          seg_ok_of(f, Pc.and_l(Lj.frame.ok(f), Lj.frames.ok(t), hf)), ha))

def ploop_len(+fs: List<&2, J.Frame>, +acc: List<&2, J.Seg>)
    -> {List.length(&2, J.Seg, J.path.loop(fs, acc))
        == Nat.add(List.length(&2, J.Frame, fs), List.length(&2, J.Seg, acc)) : Nat}:
  match fs:
    case Nil{}:
      {==}
    case f <> t:
      %Pc.add_succ(List.length(&2, J.Frame, t), List.length(&2, J.Seg, acc)) :
        {List.length(&2, J.Seg, J.path.loop(t, J.seg(f) <> acc)) == _ : Nat}
      ploop_len(t, J.seg(f) <> acc)

def plen_ok(+fs: List<&2, J.Frame>,
    +hl: {Nat.is_le(List.length(&2, J.Frame, fs), J.max_depth()) == True{} : Bool})
    -> {Nat.is_le(List.length(&2, J.Seg, J.path(fs)), J.max_depth()) == True{} : Bool}:
  %Equal.sym(Nat, List.length(&2, J.Seg, J.path(fs)), Nat.add(List.length(&2, J.Frame, fs), 0n),
      ploop_len(fs, Nil{})) : {Nat.is_le(_, J.max_depth()) == True{} : Bool}
  %Equal.sym(Nat, Nat.add(List.length(&2, J.Frame, fs), 0n), List.length(&2, J.Frame, fs),
      Pc.add_zero(List.length(&2, J.Frame, fs))) : {Nat.is_le(_, J.max_depth()) == True{} : Bool}
  hl

def path_ok(+fs: List<&2, J.Frame>,
    +hl: {Nat.is_le(List.length(&2, J.Frame, fs), J.max_depth()) == True{} : Bool},
    +hf: {Lj.frames.ok(fs) == True{} : Bool}) -> {Lj.path.ok(J.path(fs)) == True{} : Bool}:
  both(Nat.is_le(List.length(&2, J.Seg, J.path(fs)), J.max_depth()), Lj.segs.ok(J.path(fs)),
    plen_ok(fs, hl), ploop_segs(fs, Nil{}, hf, {==}))

def after_ok(+stack: List<&2, J.Frame>) -> {Lj.mode.ok(J.after.mode(stack)) == True{} : Bool}:
  match stack:
    case Nil{}:
      {==}
    case _ <> _:
      {==}

def txt_add_if_ok(take: Bool, room: Nat, +key: Bool, +keep: Bool, +acc: B.Bytes, +high: U32,
    +b: U32, +h: {Lj.txt.ok(J.Txt{key, keep, acc, room, high}) == True{} : Bool})
    -> {Lj.txt.ok(J.txt.add.if(take, room, key, keep, acc, high, b)) == True{} : Bool}:
  match take:
    case False{}:
      h
    case True{}:
      match room:
        case 0n:
          h
        case 1n+r:
          %Pc.add_succ(List.length(&2, U32, acc), r) : {Nat.is_eq(_, J.max_text()) == True{} : Bool}
          h

def txt_add_ok(t: J.Txt, +b: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.txt.add(t, b)) == True{} : Bool}:
  match t:
    case J.Txt{+key, +keep, +acc, +room, +high}:
      txt_add_if_ok(Bool.or(key, keep), room, key, keep, acc, high, b, h)

def add_all_ok(bs: B.Bytes, +t: J.Txt, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.txt.add_all(bs, t)) == True{} : Bool}:
  match bs:
    case Nil{}:
      h
    case +b <> rest:
      add_all_ok(rest, J.txt.add(t, b), txt_add_ok(t, b, h))

def with_high_ok(t: J.Txt, +hi: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.txt.with_high(t, hi)) == True{} : Bool}:
  match t:
    case J.Txt{key, keep, acc, room, high}:
      h

def flush_if_ok(p: Bool, +t: J.Txt, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.txt.flush.if_pending(p, t)) == True{} : Bool}:
  match p:
    case True{}:
      add_all_ok(J.replacement(), J.txt.with_high(t, 0), with_high_ok(t, 0, h))
    case False{}:
      h

def flush_ok(+t: J.Txt, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.txt.flush(t)) == True{} : Bool}:
  flush_if_ok(U32.is_ne(J.txt.high(t), 0), t, h)

def alone_half_ok(hi: Bool, lo: Bool, +t: J.Txt, +c: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.codepoint.alone.if_half(hi, lo, t, c)) == True{} : Bool}:
  match hi:
    case True{}:
      with_high_ok(t, c, h)
    case False{}:
      match lo:
        case True{}:
          add_all_ok(J.replacement(), t, h)
        case False{}:
          add_all_ok(B.utf8_char(c), t, h)

def alone_ok(+t: J.Txt, +c: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.codepoint.alone(t, c)) == True{} : Bool}:
  alone_half_ok(J.in_range(c, 55296, 56319), J.in_range(c, 56320, 57343), t, c, h)

def cp_low_ok(low: Bool, +t: J.Txt, +high: U32, +c: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.codepoint.if_low(low, t, high, c)) == True{} : Bool}:
  match low:
    case True{}:
      add_all_ok(B.utf8_char((65536 + (((high - 55296) << 10n) + (c - 56320)) : U32)),
        J.txt.with_high(t, 0), with_high_ok(t, 0, h))
    case False{}:
      alone_ok(J.txt.flush(t), c, flush_ok(t, h))

def codepoint_ok(+t: J.Txt, +c: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {Lj.txt.ok(J.codepoint(t, c)) == True{} : Bool}:
  cp_low_ok(Bool.and(U32.is_ne(J.txt.high(t), 0), J.in_range(c, 56320, 57343)), t, J.txt.high(t),
    c, h)

# Moves whose mode has no buffer, or a fresh one
# A value: kept with its path (small: the stack's keys are) when wanted.
def value_ok(keep: Bool, +stack: List<&2, J.Frame>, +v: J.Val,
    +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool}, +hv: {Lj.val.ok(v) == True{} : Bool})
    -> {mv.ok(J.value(keep, stack, v)) == True{} : Bool}:
  match keep:
    case True{}:
      both(Bool.and(Lj.path.ok(J.path(stack)), Lj.val.ok(v)), Lj.mode.ok(J.after.mode(stack)),
        both(Lj.path.ok(J.path(stack)), Lj.val.ok(v), hp, hv), after_ok(stack))
    case False{}:
      after_ok(stack)

def named_ok(+name: B.Bytes, stack: List<&2, J.Frame>, +hk: {Lj.key.ok(name) == True{} : Bool})
    -> {mv.ok(J.named(name, stack)) == True{} : Bool}:
  match stack:
    case Nil{}:
      {==}
    case _ <> _:
      %Equal.sym(Bool, Lj.key.ok(name), True{}, hk) :
        {Bool.and(Bool.and(_, True{}), True{}) == True{} : Bool}
      {==}

def close_on_ok(top: J.Frame, object: Bool, rest: List<&2, J.Frame>)
    -> {mv.ok(J.close.on(top, object, rest)) == True{} : Bool}:
  match top:
    case J.InObj{_}:
      match object:
        case True{}:
          match rest:
            case Nil{}:
              {==}
            case _ <> _:
              {==}
        case False{}:
          {==}
    case J.InArr{_}:
      match object:
        case True{}:
          {==}
        case False{}:
          match rest:
            case Nil{}:
              {==}
            case _ <> _:
              {==}

def close_ok(object: Bool, stack: List<&2, J.Frame>) -> {mv.ok(J.close(object, stack)) == True{} : Bool}:
  match stack:
    case Nil{}:
      {==}
    case top <> rest:
      close_on_ok(top, object, rest)

def comma_ok(stack: List<&2, J.Frame>) -> {mv.ok(J.comma(stack)) == True{} : Bool}:
  match stack:
    case Nil{}:
      {==}
    case top <> _:
      match top:
        case J.InObj{_}:
          {==}
        case J.InArr{_}:
          {==}

def open_ok(+f: J.Frame, +m: J.Mode, deep: Bool, +hf: {Lj.frame.ok(f) == True{} : Bool},
    +h: {Lj.mode.ok(m) == True{} : Bool}) -> {mv.ok(J.open(f, m, deep)) == True{} : Bool}:
  match deep:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(Bool, Lj.frame.ok(f), True{}, hf) :
        {Bool.and(Bool.and(_, True{}), Lj.mode.ok(m)) == True{} : Bool}
      h

def begin_ok(+ws: J.Wants, ch: J.Ch, +b: U32, +m: J.Mode, +stack: List<&2, J.Frame>, +deep: Bool,
    +h: {Lj.mode.ok(m) == True{} : Bool}) -> {mv.ok(J.begin(ws, ch, b, m, stack, deep)) == True{} : Bool}:
  match ch:
    case J.Space{}:
      h
    case J.LBrace{}:
      open_ok(J.InObj{Nil{}}, J.KeyOrEnd{}, deep, {==}, {==})
    case J.RBrace{}:
      {==}
    case J.LBracket{}:
      open_ok(J.InArr{0}, J.ArrStart{}, deep, {==}, {==})
    case J.RBracket{}:
      {==}
    case J.CommaCh{}:
      {==}
    case J.ColonCh{}:
      {==}
    case J.Quote{}:
      {==}
    case J.NumCh{}:
      {==}
    case J.TCh{}:
      {==}
    case J.FCh{}:
      {==}
    case J.NCh{}:
      {==}
    case J.OtherCh{}:
      {==}

def structural_ok(+ws: J.Wants, m: J.Mode, ch: J.Ch, +b: U32, +stack: List<&2, J.Frame>,
    +deep: Bool) -> {mv.ok(J.structural(ws, m, ch, b, stack, deep)) == True{} : Bool}:
  match m:
    case J.ArrStart{}:
      match ch:
        case J.Space{}:
          begin_ok(ws, J.Space{}, b, J.ArrStart{}, stack, deep, {==})
        case J.LBrace{}:
          begin_ok(ws, J.LBrace{}, b, J.ArrStart{}, stack, deep, {==})
        case J.RBrace{}:
          begin_ok(ws, J.RBrace{}, b, J.ArrStart{}, stack, deep, {==})
        case J.LBracket{}:
          begin_ok(ws, J.LBracket{}, b, J.ArrStart{}, stack, deep, {==})
        case J.RBracket{}:
          close_ok(False{}, stack)
        case J.CommaCh{}:
          begin_ok(ws, J.CommaCh{}, b, J.ArrStart{}, stack, deep, {==})
        case J.ColonCh{}:
          begin_ok(ws, J.ColonCh{}, b, J.ArrStart{}, stack, deep, {==})
        case J.Quote{}:
          begin_ok(ws, J.Quote{}, b, J.ArrStart{}, stack, deep, {==})
        case J.NumCh{}:
          begin_ok(ws, J.NumCh{}, b, J.ArrStart{}, stack, deep, {==})
        case J.TCh{}:
          begin_ok(ws, J.TCh{}, b, J.ArrStart{}, stack, deep, {==})
        case J.FCh{}:
          begin_ok(ws, J.FCh{}, b, J.ArrStart{}, stack, deep, {==})
        case J.NCh{}:
          begin_ok(ws, J.NCh{}, b, J.ArrStart{}, stack, deep, {==})
        case J.OtherCh{}:
          begin_ok(ws, J.OtherCh{}, b, J.ArrStart{}, stack, deep, {==})
    case J.KeyOrEnd{}:
      match ch:
        case J.Space{}:
          {==}
        case J.LBrace{}:
          {==}
        case J.RBrace{}:
          close_ok(True{}, stack)
        case J.LBracket{}:
          {==}
        case J.RBracket{}:
          {==}
        case J.CommaCh{}:
          {==}
        case J.ColonCh{}:
          {==}
        case J.Quote{}:
          {==}
        case J.NumCh{}:
          {==}
        case J.TCh{}:
          {==}
        case J.FCh{}:
          {==}
        case J.NCh{}:
          {==}
        case J.OtherCh{}:
          {==}
    case J.KeyNext{}:
      match ch:
        case J.Space{}:
          {==}
        case J.LBrace{}:
          {==}
        case J.RBrace{}:
          {==}
        case J.LBracket{}:
          {==}
        case J.RBracket{}:
          {==}
        case J.CommaCh{}:
          {==}
        case J.ColonCh{}:
          {==}
        case J.Quote{}:
          {==}
        case J.NumCh{}:
          {==}
        case J.TCh{}:
          {==}
        case J.FCh{}:
          {==}
        case J.NCh{}:
          {==}
        case J.OtherCh{}:
          {==}
    case J.Colon{}:
      match ch:
        case J.Space{}:
          {==}
        case J.LBrace{}:
          {==}
        case J.RBrace{}:
          {==}
        case J.LBracket{}:
          {==}
        case J.RBracket{}:
          {==}
        case J.CommaCh{}:
          {==}
        case J.ColonCh{}:
          {==}
        case J.Quote{}:
          {==}
        case J.NumCh{}:
          {==}
        case J.TCh{}:
          {==}
        case J.FCh{}:
          {==}
        case J.NCh{}:
          {==}
        case J.OtherCh{}:
          {==}
    case J.After{}:
      match ch:
        case J.Space{}:
          {==}
        case J.LBrace{}:
          {==}
        case J.RBrace{}:
          close_ok(True{}, stack)
        case J.LBracket{}:
          {==}
        case J.RBracket{}:
          close_ok(False{}, stack)
        case J.CommaCh{}:
          comma_ok(stack)
        case J.ColonCh{}:
          {==}
        case J.Quote{}:
          {==}
        case J.NumCh{}:
          {==}
        case J.TCh{}:
          {==}
        case J.FCh{}:
          {==}
        case J.NCh{}:
          {==}
        case J.OtherCh{}:
          {==}
    case J.Whole{}:
      match ch:
        case J.Space{}:
          {==}
        case J.LBrace{}:
          {==}
        case J.RBrace{}:
          {==}
        case J.LBracket{}:
          {==}
        case J.RBracket{}:
          {==}
        case J.CommaCh{}:
          {==}
        case J.ColonCh{}:
          {==}
        case J.Quote{}:
          {==}
        case J.NumCh{}:
          {==}
        case J.TCh{}:
          {==}
        case J.FCh{}:
          {==}
        case J.NCh{}:
          {==}
        case J.OtherCh{}:
          {==}
    case J.Value{}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})
    case J.InString{_}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})
    case J.InEscape{_}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})
    case J.InHex{_, _, _}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})
    case J.InNumber{_, _}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})
    case J.InWord{_, _}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})
    case J.Broken{_}:
      begin_ok(ws, ch, b, J.Value{}, stack, deep, {==})

# Moves inside a string, an escape, a \u escape
# A finished string: a key (small, from the buffer's bound) or a value.
def end_flushed_ok(+t: J.Txt, +stack: List<&2, J.Frame>,
    +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool}, +ht: {Lj.txt.ok(t) == True{} : Bool})
    -> {mv.ok(J.text.end.flushed(t, stack)) == True{} : Bool}:
  match t:
    case J.Txt{key, keep, +acc, +room, _}:
      match key:
        case True{}:
          named_ok(List.reverse(&2, U32, acc), stack, rev_le(acc, J.max_text(),
            le_of_is_eq(List.length(&2, U32, acc), room, J.max_text(), ht)))
        case False{}:
          value_ok(keep, stack, J.Str{List.reverse(&2, U32, acc)}, hp, rev_le(acc, J.max_text(),
            le_of_is_eq(List.length(&2, U32, acc), room, J.max_text(), ht)))

def text_kind_ok(q: Bool, bs: Bool, ctl: Bool, +t: J.Txt, +b: U32, +stack: List<&2, J.Frame>,
    +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool}, +h: {Lj.txt.ok(t) == True{} : Bool}) -> {mv.ok(J.text.byte.if_kind(q, bs, ctl, t, b, stack)) == True{} : Bool}:
  match q:
    case True{}:
      end_flushed_ok(J.txt.flush(t), stack, hp, flush_ok(t, h))
    case False{}:
      match bs:
        case True{}:
          h
        case False{}:
          match ctl:
            case True{}:
              {==}
            case False{}:
              txt_add_ok(J.txt.flush(t), b, flush_ok(t, h))

def esc_simple_ok(bad: Bool, +v: U32, +t: J.Txt, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {mv.ok(J.escape.on_simple(bad, v, t)) == True{} : Bool}:
  match bad:
    case True{}:
      {==}
    case False{}:
      txt_add_ok(J.txt.flush(t), v, flush_ok(t, h))

def esc_on_ok(u: Bool, +v: U32, +t: J.Txt, +h: {Lj.txt.ok(t) == True{} : Bool}) -> {mv.ok(J.escape.on(u, v, t)) == True{} : Bool}:
  match u:
    case True{}:
      h
    case False{}:
      esc_simple_ok(U32.is_eq(v, 256), v, t, h)

def hex_next_ok(left: Nat, +t: J.Txt, +code: U32, +h: {Lj.txt.ok(t) == True{} : Bool}) -> {mv.ok(J.hex.next(left, t, code)) == True{} : Bool}:
  match left:
    case 0n:
      codepoint_ok(t, code, h)
    case 1n+q:
      h

def hex_on_ok(bad: Bool, +v: U32, +left: Nat, +t: J.Txt, +code: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {mv.ok(J.hex.on(bad, v, left, t, code)) == True{} : Bool}:
  match bad:
    case True{}:
      {==}
    case False{}:
      hex_next_ok(left, t, ((code << 4n) .|. v : U32), h)

def hex_byte_ok(+t: J.Txt, digits: Nat, +code: U32, +b: U32, +h: {Lj.txt.ok(t) == True{} : Bool})
    -> {mv.ok(J.hex.byte(t, digits, code, b)) == True{} : Bool}:
  match digits:
    case 0n:
      codepoint_ok(t, code, h)
    case 1n+p:
      hex_on_ok(U32.is_eq(J.hex.value(b), 16), J.hex.value(b), p, t, code, h)

# Moves in a number or a literal
def resume_on_ok(mv: J.Move, +cap: Maybe<&2, J.Cap>, +h: {mv.ok(mv) == True{} : Bool},
    +hc: {mcap.ok(cap) == True{} : Bool}) -> {mv.ok(J.resume.on(mv, cap)) == True{} : Bool}:
  match mv:
    case J.Breaks{_}:
      {==}
    case J.Goes{+m, +op, +c2}:
      match cap:
        case None{}:
          h
        case Some{+c}:
          both(Bool.and(op.ok(op), Lj.cap.ok(c)), Lj.mode.ok(m),
            both(op.ok(op), Lj.cap.ok(c), Pc.and_l(op.ok(op), mcap.ok(c2),
              Pc.and_l(Bool.and(op.ok(op), mcap.ok(c2)), Lj.mode.ok(m), h)), hc),
            Pc.and_r(Bool.and(op.ok(op), mcap.ok(c2)), Lj.mode.ok(m), h))

def resume_ok(+ws: J.Wants, first: J.Move, +b: U32, +stack: List<&2, J.Frame>, +deep: Bool,
    +hf: {mv.ok(first) == True{} : Bool})
    -> {mv.ok(J.resume(ws, first, b, stack, deep)) == True{} : Bool}:
  match first:
    case J.Breaks{_}:
      {==}
    case J.Goes{+m, +op, +cap}:
      resume_on_ok(J.structural(ws, m, J.classify(b), b, stack, deep), cap,
        structural_ok(ws, m, J.classify(b), b, stack, deep),
        Pc.and_r(op.ok(op), mcap.ok(cap), Pc.and_l(Bool.and(op.ok(op), mcap.ok(cap)),
          Lj.mode.ok(m), hf)))

def num_on_ok(more: Bool, room: Nat, +ws: J.Wants, +acc: B.Bytes, +b: U32,
    +stack: List<&2, J.Frame>, +deep: Bool, +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool},
    +h: {Lj.mode.ok(J.InNumber{acc, room}) == True{} : Bool})
    -> {mv.ok(J.number.on(more, room, ws, acc, b, stack, deep)) == True{} : Bool}:
  match more:
    case True{}:
      match room:
        case 0n:
          {==}
        case 1n+r:
          %Pc.add_succ(List.length(&2, U32, acc), r) : {Nat.is_eq(_, J.max_number()) == True{} : Bool}
          h
    case False{}:
      resume_ok(ws, J.value(J.wanted(ws, stack), stack, J.Num{List.reverse(&2, U32, acc)}), b, stack,
        deep, value_ok(J.wanted(ws, stack), stack, J.Num{List.reverse(&2, U32, acc)}, hp,
          rev_le(acc, J.max_number(), le_of_is_eq(List.length(&2, U32, acc), room, J.max_number(), h))))

def word_on_ok(ok: Bool, rest: B.Bytes, +val: J.Val, +ws: J.Wants, +stack: List<&2, J.Frame>,
    +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool}, +h: {Lj.val.ok(val) == True{} : Bool})
    -> {mv.ok(J.word.on(ok, rest, val, ws, stack)) == True{} : Bool}:
  match ok:
    case False{}:
      {==}
    case True{}:
      match rest:
        case Nil{}:
          value_ok(J.wanted(ws, stack), stack, val, hp, h)
        case _ <> _:
          h

def word_byte_ok(+ws: J.Wants, rest: B.Bytes, +val: J.Val, +b: U32, +stack: List<&2, J.Frame>,
    +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool}, +h: {Lj.val.ok(val) == True{} : Bool})
    -> {mv.ok(J.word.byte(ws, rest, val, b, stack)) == True{} : Bool}:
  match rest:
    case Nil{}:
      {==}
    case x <> xs:
      word_on_ok(U32.is_eq(b, x), xs, val, ws, stack, hp, h)

# Every move keeps the buffers within their room, and land keeps the move's mode.
def move_ok(+ws: J.Wants, mode: J.Mode, +stack: List<&2, J.Frame>, +deep: Bool, +b: U32,
    +hp: {Lj.path.ok(J.path(stack)) == True{} : Bool}, +h: {Lj.mode.ok(mode) == True{} : Bool}) -> {mv.ok(J.move(ws, mode, stack, deep, b)) == True{} : Bool}:
  match mode:
    case J.InString{+t}:
      text_kind_ok(U32.is_eq(b, 34), U32.is_eq(b, 92), (b < 32 : U32), t, b, stack, hp, h)
    case J.InEscape{+t}:
      esc_on_ok(U32.is_eq(b, 117), J.unescape(b), t, h)
    case J.InHex{+t, digits, +code}:
      hex_byte_ok(t, digits, code, b, h)
    case J.InNumber{+acc, +room}:
      num_on_ok(J.is_number_byte(b), room, ws, acc, b, stack, deep, hp, h)
    case J.InWord{rest, +val}:
      word_byte_ok(ws, rest, val, b, stack, hp, h)
    case J.Broken{_}:
      {==}
    case J.Value{}:
      structural_ok(ws, J.Value{}, J.classify(b), b, stack, deep)
    case J.ArrStart{}:
      structural_ok(ws, J.ArrStart{}, J.classify(b), b, stack, deep)
    case J.KeyOrEnd{}:
      structural_ok(ws, J.KeyOrEnd{}, J.classify(b), b, stack, deep)
    case J.KeyNext{}:
      structural_ok(ws, J.KeyNext{}, J.classify(b), b, stack, deep)
    case J.Colon{}:
      structural_ok(ws, J.Colon{}, J.classify(b), b, stack, deep)
    case J.After{}:
      structural_ok(ws, J.After{}, J.classify(b), b, stack, deep)
    case J.Whole{}:
      structural_ok(ws, J.Whole{}, J.classify(b), b, stack, deep)

# The scan's invariant: buffers within their room, open containers with small keys, kept values
# small. land keeps it; so does every step (with the stack's size, proven above), so every run.
def inv(+s: J.Scan) -> Bool:
  Bool.and(Bool.and(Lj.mode.ok(J.scan.mode(s)), Lj.frames.ok(J.stack.frames(J.scan.stack(s)))),
    Lj.caps.ok(J.kept.caps(J.scan.kept(s))))

def kept_add_small(cap: Maybe<&2, J.Cap>, +k: J.Kept, +hcap: {mcap.ok(cap) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool})
    -> {Lj.caps.ok(J.kept.caps(J.kept.add(cap, k))) == True{} : Bool}:
  match cap:
    case None{}:
      hc
    case Some{+c}:
      match k:
        case J.Kept{+cs, room}:
          match room:
            case 0n:
              hc
            case 1n+_:
              both(Lj.cap.ok(c), Lj.caps.ok(cs), hcap, hc)

def scan_inv(+m: J.Mode, +st: J.Stack, +k: J.Kept, +hm: {Lj.mode.ok(m) == True{} : Bool},
    +hf: {Lj.frames.ok(J.stack.frames(st)) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool}) -> {inv(J.Scan{m, st, k}) == True{} : Bool}:
  both(Bool.and(Lj.mode.ok(m), Lj.frames.ok(J.stack.frames(st))), Lj.caps.ok(J.kept.caps(k)),
    both(Lj.mode.ok(m), Lj.frames.ok(J.stack.frames(st)), hm, hf), hc)

def push_inv(st: J.Stack, +f: J.Frame, +m: J.Mode, +k: J.Kept,
    +hfr: {Lj.frame.ok(f) == True{} : Bool}, +hm: {Lj.mode.ok(m) == True{} : Bool},
    +hf: {Lj.frames.ok(J.stack.frames(st)) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool})
    -> {inv(J.stack.push(st, f, m, k)) == True{} : Bool}:
  match st:
    case J.Stack{+fs, room}:
      match room:
        case 0n:
          {==}
        case 1n+r:
          scan_inv(m, J.Stack{f <> fs, r}, k, hm, both(Lj.frame.ok(f), Lj.frames.ok(fs), hfr, hf), hc)

def pop_inv(st: J.Stack, +m: J.Mode, +k: J.Kept, +hm: {Lj.mode.ok(m) == True{} : Bool},
    +hf: {Lj.frames.ok(J.stack.frames(st)) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool})
    -> {inv(J.Scan{m, J.stack.pop(st), k}) == True{} : Bool}:
  match st:
    case J.Stack{fs, +room}:
      match fs:
        case Nil{}:
          scan_inv(m, J.Stack{Nil{}, room}, k, hm, {==}, hc)
        case +x <> +rest:
          scan_inv(m, J.Stack{rest, 1n+room}, k, hm,
            Pc.and_r(Lj.frame.ok(x), Lj.frames.ok(rest), hf), hc)

def top_inv(st: J.Stack, +f: J.Frame, +m: J.Mode, +k: J.Kept,
    +hfr: {Lj.frame.ok(f) == True{} : Bool}, +hm: {Lj.mode.ok(m) == True{} : Bool},
    +hf: {Lj.frames.ok(J.stack.frames(st)) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool})
    -> {inv(J.Scan{m, J.stack.top(st, f), k}) == True{} : Bool}:
  match st:
    case J.Stack{fs, +room}:
      match fs:
        case Nil{}:
          scan_inv(m, J.Stack{Nil{}, room}, k, hm, {==}, hc)
        case +x <> +rest:
          scan_inv(m, J.Stack{f <> rest, room}, k, hm,
            both(Lj.frame.ok(f), Lj.frames.ok(rest), hfr,
              Pc.and_r(Lj.frame.ok(x), Lj.frames.ok(rest), hf)), hc)

def land_inv.op(op: J.Op, +m: J.Mode, +st: J.Stack, +k: J.Kept, +hop: {op.ok(op) == True{} : Bool},
    +hm: {Lj.mode.ok(m) == True{} : Bool},
    +hf: {Lj.frames.ok(J.stack.frames(st)) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool})
    -> {inv(J.land.op(op, m, st, k)) == True{} : Bool}:
  match op:
    case J.Stay{}:
      scan_inv(m, st, k, hm, hf, hc)
    case J.Push{+f}:
      push_inv(st, f, m, k, hop, hm, hf, hc)
    case J.Pop{}:
      pop_inv(st, m, k, hm, hf, hc)
    case J.Top{+f}:
      top_inv(st, f, m, k, hop, hm, hf, hc)

def land_inv(+st: J.Stack, +k: J.Kept, mv: J.Move, +h: {mv.ok(mv) == True{} : Bool},
    +hf: {Lj.frames.ok(J.stack.frames(st)) == True{} : Bool},
    +hc: {Lj.caps.ok(J.kept.caps(k)) == True{} : Bool})
    -> {inv(J.land(st, k, mv)) == True{} : Bool}:
  match mv:
    case J.Breaks{_}:
      {==}
    case J.Goes{+m, +op, +cap}:
      +ok = Pc.and_l(Bool.and(op.ok(op), mcap.ok(cap)), Lj.mode.ok(m), h)
      +hm = Pc.and_r(Bool.and(op.ok(op), mcap.ok(cap)), Lj.mode.ok(m), h)
      +hk = kept_add_small(cap, k, Pc.and_r(op.ok(op), mcap.ok(cap), ok), hc)
      +hop = Pc.and_l(op.ok(op), mcap.ok(cap), ok)
      land_inv.op(op, m, st, J.kept.add(cap, k), hop, hm, hf, hk)

def step_inv(+ws: J.Wants, +s: J.Scan, +b: U32,
    +hs: {Lj.stack.size(J.scan.stack(s)) == J.max_depth() : Nat}, +hi: {inv(s) == True{} : Bool})
    -> {inv(J.step(ws, s, b)) == True{} : Bool}:
  match s:
    case J.Scan{+mode, +st, +k}:
      +ab = Pc.and_l(Bool.and(Lj.mode.ok(mode), Lj.frames.ok(J.stack.frames(st))),
        Lj.caps.ok(J.kept.caps(k)), hi)
      +hf = Pc.and_r(Lj.mode.ok(mode), Lj.frames.ok(J.stack.frames(st)), ab)
      +hp = path_ok(J.stack.frames(st), le_of_add_eq(List.length(&2, J.Frame, J.stack.frames(st)),
        J.stack.room(st), J.max_depth(), hs), hf)
      land_inv(st, k, J.move(ws, mode, J.stack.frames(st), J.stack.full(st), b),
        move_ok(ws, mode, J.stack.frames(st), J.stack.full(st), b, hp,
          Pc.and_l(Lj.mode.ok(mode), Lj.frames.ok(J.stack.frames(st)), ab)),
        hf, Pc.and_r(Bool.and(Lj.mode.ok(mode), Lj.frames.ok(J.stack.frames(st))),
          Lj.caps.ok(J.kept.caps(k)), hi))

def run_inv(bs: B.Bytes, +ws: J.Wants, +s: J.Scan,
    +hs: {Lj.stack.size(J.scan.stack(s)) == J.max_depth() : Nat}, +hi: {inv(s) == True{} : Bool})
    -> {inv(J.run(bs, ws, s)) == True{} : Bool}:
  match bs:
    case Nil{}:
      hi
    case +b <> t:
      run_inv(t, ws, J.step(ws, s, b), step_stack_ok(ws, s, b, hs), step_inv(ws, s, b, hs, hi))

def Lj.json_buffers_bounded(ws, bs):
  Pc.and_l(Lj.mode.ok(J.scan.mode(J.run(bs, ws, J.start()))),
    Lj.frames.ok(J.stack.frames(J.scan.stack(J.run(bs, ws, J.start())))),
    Pc.and_l(Bool.and(Lj.mode.ok(J.scan.mode(J.run(bs, ws, J.start()))),
      Lj.frames.ok(J.stack.frames(J.scan.stack(J.run(bs, ws, J.start()))))),
      Lj.caps.ok(J.kept.caps(J.scan.kept(J.run(bs, ws, J.start())))),
      run_inv(bs, ws, J.start(), {==}, {==})))

def Lj.json_kept_small(ws, bs):
  Pc.and_r(Bool.and(Lj.mode.ok(J.scan.mode(J.run(bs, ws, J.start()))),
    Lj.frames.ok(J.stack.frames(J.scan.stack(J.run(bs, ws, J.start()))))),
    Lj.caps.ok(J.kept.caps(J.scan.kept(J.run(bs, ws, J.start())))),
    run_inv(bs, ws, J.start(), {==}, {==}))
