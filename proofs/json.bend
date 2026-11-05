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

def mv.ok(mv: J.Move) -> Bool:
  match mv:
    case J.Breaks{_}:
      True{}
    case J.Goes{m, _, _}:
      Lj.mode.ok(m)

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
def value_ok(keep: Bool, +stack: List<&2, J.Frame>, v: J.Val) -> {mv.ok(J.value(keep, stack, v)) == True{} : Bool}:
  match stack:
    case Nil{}:
      {==}
    case _ <> _:
      {==}

def named_ok(name: B.Bytes, stack: List<&2, J.Frame>) -> {mv.ok(J.named(name, stack)) == True{} : Bool}:
  match stack:
    case Nil{}:
      {==}
    case _ <> _:
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

def open_ok(f: J.Frame, +m: J.Mode, deep: Bool, +h: {Lj.mode.ok(m) == True{} : Bool})
    -> {mv.ok(J.open(f, m, deep)) == True{} : Bool}:
  match deep:
    case True{}:
      {==}
    case False{}:
      h

def begin_ok(+ws: J.Wants, ch: J.Ch, +b: U32, +m: J.Mode, +stack: List<&2, J.Frame>, +deep: Bool,
    +h: {Lj.mode.ok(m) == True{} : Bool}) -> {mv.ok(J.begin(ws, ch, b, m, stack, deep)) == True{} : Bool}:
  match ch:
    case J.Space{}:
      h
    case J.LBrace{}:
      open_ok(J.InObj{Nil{}}, J.KeyOrEnd{}, deep, {==})
    case J.RBrace{}:
      {==}
    case J.LBracket{}:
      open_ok(J.InArr{0}, J.ArrStart{}, deep, {==})
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
def end_flushed_ok(t: J.Txt, +stack: List<&2, J.Frame>) -> {mv.ok(J.text.end.flushed(t, stack)) == True{} : Bool}:
  match t:
    case J.Txt{key, keep, acc, _, _}:
      match key:
        case True{}:
          named_ok(List.reverse(&2, U32, acc), stack)
        case False{}:
          value_ok(keep, stack, J.Str{List.reverse(&2, U32, acc)})

def text_kind_ok(q: Bool, bs: Bool, ctl: Bool, +t: J.Txt, +b: U32, +stack: List<&2, J.Frame>,
    +h: {Lj.txt.ok(t) == True{} : Bool}) -> {mv.ok(J.text.byte.if_kind(q, bs, ctl, t, b, stack)) == True{} : Bool}:
  match q:
    case True{}:
      end_flushed_ok(J.txt.flush(t), stack)
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
def resume_on_ok(mv: J.Move, cap: Maybe<&2, J.Cap>, +h: {mv.ok(mv) == True{} : Bool})
    -> {mv.ok(J.resume.on(mv, cap)) == True{} : Bool}:
  match mv:
    case J.Breaks{_}:
      {==}
    case J.Goes{m, op, c2}:
      h

def resume_ok(+ws: J.Wants, first: J.Move, +b: U32, +stack: List<&2, J.Frame>, +deep: Bool)
    -> {mv.ok(J.resume(ws, first, b, stack, deep)) == True{} : Bool}:
  match first:
    case J.Breaks{_}:
      {==}
    case J.Goes{+m, _, +cap}:
      resume_on_ok(J.structural(ws, m, J.classify(b), b, stack, deep), cap,
        structural_ok(ws, m, J.classify(b), b, stack, deep))

def num_on_ok(more: Bool, room: Nat, +ws: J.Wants, +acc: B.Bytes, +b: U32,
    +stack: List<&2, J.Frame>, +deep: Bool,
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
        deep)

def word_on_ok(ok: Bool, rest: B.Bytes, val: J.Val, +ws: J.Wants, +stack: List<&2, J.Frame>)
    -> {mv.ok(J.word.on(ok, rest, val, ws, stack)) == True{} : Bool}:
  match ok:
    case False{}:
      {==}
    case True{}:
      match rest:
        case Nil{}:
          value_ok(J.wanted(ws, stack), stack, val)
        case _ <> _:
          {==}

def word_byte_ok(+ws: J.Wants, rest: B.Bytes, val: J.Val, +b: U32, +stack: List<&2, J.Frame>)
    -> {mv.ok(J.word.byte(ws, rest, val, b, stack)) == True{} : Bool}:
  match rest:
    case Nil{}:
      {==}
    case x <> xs:
      word_on_ok(U32.is_eq(b, x), xs, val, ws, stack)

# Every move keeps the buffers within their room, and land keeps the move's mode.
def move_ok(+ws: J.Wants, mode: J.Mode, +stack: List<&2, J.Frame>, +deep: Bool, +b: U32,
    +h: {Lj.mode.ok(mode) == True{} : Bool}) -> {mv.ok(J.move(ws, mode, stack, deep, b)) == True{} : Bool}:
  match mode:
    case J.InString{+t}:
      text_kind_ok(U32.is_eq(b, 34), U32.is_eq(b, 92), (b < 32 : U32), t, b, stack, h)
    case J.InEscape{+t}:
      esc_on_ok(U32.is_eq(b, 117), J.unescape(b), t, h)
    case J.InHex{+t, digits, +code}:
      hex_byte_ok(t, digits, code, b, h)
    case J.InNumber{+acc, +room}:
      num_on_ok(J.is_number_byte(b), room, ws, acc, b, stack, deep, h)
    case J.InWord{rest, val}:
      word_byte_ok(ws, rest, val, b, stack)
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

def push_mode_ok(st: J.Stack, f: J.Frame, +m: J.Mode, k: J.Kept, +h: {Lj.mode.ok(m) == True{} : Bool})
    -> {Lj.mode.ok(J.scan.mode(J.stack.push(st, f, m, k))) == True{} : Bool}:
  match st:
    case J.Stack{fs, room}:
      match room:
        case 0n:
          {==}
        case 1n+r:
          h

def land_mode_ok(+st: J.Stack, +k: J.Kept, mv: J.Move, +h: {mv.ok(mv) == True{} : Bool})
    -> {Lj.mode.ok(J.scan.mode(J.land(st, k, mv))) == True{} : Bool}:
  match mv:
    case J.Breaks{_}:
      {==}
    case J.Goes{+m, op, +cap}:
      match op:
        case J.Stay{}:
          h
        case J.Push{f}:
          push_mode_ok(st, f, m, J.kept.add(cap, k), h)
        case J.Pop{}:
          h
        case J.Top{f}:
          h

def step_mode_ok(+ws: J.Wants, +s: J.Scan, +b: U32,
    +h: {Lj.mode.ok(J.scan.mode(s)) == True{} : Bool})
    -> {Lj.mode.ok(J.scan.mode(J.step(ws, s, b))) == True{} : Bool}:
  match s:
    case J.Scan{+mode, +st, +k}:
      land_mode_ok(st, k, J.move(ws, mode, J.stack.frames(st), J.stack.full(st), b),
        move_ok(ws, mode, J.stack.frames(st), J.stack.full(st), b, h))

def run_mode_ok(bs: B.Bytes, +ws: J.Wants, +s: J.Scan,
    +h: {Lj.mode.ok(J.scan.mode(s)) == True{} : Bool})
    -> {Lj.mode.ok(J.scan.mode(J.run(bs, ws, s))) == True{} : Bool}:
  match bs:
    case Nil{}:
      h
    case +b <> t:
      run_mode_ok(t, ws, J.step(ws, s, b), step_mode_ok(ws, s, b, h))

def Lj.json_buffers_bounded(ws, bs):
  run_mode_ok(bs, ws, J.start(), {==})
