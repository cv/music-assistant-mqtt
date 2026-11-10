import Base
import ./bytes.bend as B
# JSON for the bridge. A scanner that reads a document one byte at a time and keeps only the
# scalar values at wanted paths, so a message's size never shows in memory; and a writer for the
# payloads the bridge publishes. The scanner checks the structure (brackets, commas, colons,
# strings and their escapes) and keeps a number as its text, without checking its syntax.
# No I/O, and nothing about Music Assistant: the paths it wants come from lib/ma.

# Paths and values
# ================

# A level of a value's path: an object's key, or an array's index.
type Seg is Data:
  SKey{name: B.Bytes}
  SIdx{i: U32}

# A level of a wanted path: that key, or any key or index.
type Pat is Data:
  PKey{name: B.Bytes}
  PAny{}

# The paths a scanner keeps, each level by level from the top.
def Wants() -> Data:
  List<&2, List<&2, Pat>>

# A scalar value: a string's bytes (UTF-8), a number's text, true, false, null.
type Val is Data:
  Str{bytes: B.Bytes}
  Num{text: B.Bytes}
  Yes{}
  No{}
  Null{}

# A kept value and where it was.
type Cap is Data:
  Cap{path: List<&2, Seg>, val: Val}

# Limits
# ------

# Containers nest at most this deep; deeper is broken.
def max_depth() -> Nat:
  64n

# At most this many values are kept from a document; later ones are dropped.
def max_caps() -> Nat:
  256n

# A kept string (or a key) keeps this many bytes; the rest are dropped.
def max_text() -> Nat:
  4096n

# A number has at most this many characters; longer is broken.
def max_number() -> Nat:
  64n

# The room a number has after its first character (max_number - 1).
def number.first_room() -> Nat:
  63n

# The scanner
# ===========

# The containers open around the scanner, innermost first: an object and its current key (empty
# before the first), an array and its current index.
type Frame is Data:
  InObj{key: B.Bytes}
  InArr{i: U32}

# A string being read: whether it is a key, whether its bytes are kept, the bytes so far (newest
# first) and the room left for more (acc + room = max_text), and a high surrogate waiting for its
# low half (0: none).
type Txt is Data:
  Txt{key: Bool, keep: Bool, acc: B.Bytes, room: Nat, high: U32}

# What the scanner expects next.
type Mode is Data:
  # a value
  Value{}
  # a value or ] (right after [)
  ArrStart{}
  # a key or } (right after {)
  KeyOrEnd{}
  # a key (after a comma in an object)
  KeyNext{}
  # the colon after a key
  Colon{}
  # a comma or the container's end
  After{}
  # inside a string, after its backslash, inside its \u escape (digits still to come)
  InString{t: Txt}
  InEscape{t: Txt}
  InHex{t: Txt, digits: Nat, code: U32}
  # a number's characters so far (newest first) and the room for more (acc + room = max_number)
  InNumber{acc: B.Bytes, room: Nat}
  # true, false or null: the bytes still expected, and the value
  InWord{rest: B.Bytes, val: Val}
  # the document is whole
  Whole{}
  # the document broke JSON's rules; nothing more is read
  Broken{why: String}

# The open containers (innermost first) and how many more may open: frames + room = max_depth.
type Stack is Data:
  Stack{frames: List<&2, Frame>, room: Nat}

# The values kept (newest first) and how many more may be: caps + room = max_caps.
type Kept is Data:
  Kept{caps: List<&2, Cap>, room: Nat}

# The scanner: what it expects, the open containers, the values kept. The containers and the
# values change only in land (below), which opens a container or keeps a value only while there
# is room: the laws prove both limits for every input.
type Scan is Data:
  Scan{mode: Mode, stack: Stack, kept: Kept}

def stack.empty() -> Stack:
  Stack{Nil{}, max_depth()}

def kept.empty() -> Kept:
  Kept{Nil{}, max_caps()}

# A scanner before a document.
def start() -> Scan:
  Scan{Value{}, stack.empty(), kept.empty()}

def broken(why: String) -> Scan:
  Scan{Broken{why}, stack.empty(), kept.empty()}

def scan.mode(s: Scan) -> Mode:
  match s:
    case Scan{m, _, _}:
      m

def scan.stack(s: Scan) -> Stack:
  match s:
    case Scan{_, st, _}:
      st

def scan.kept(s: Scan) -> Kept:
  match s:
    case Scan{_, _, k}:
      k

def stack.frames(st: Stack) -> List<&2, Frame>:
  match st:
    case Stack{fs, _}:
      fs

def stack.room(st: Stack) -> Nat:
  match st:
    case Stack{_, r}:
      r

def kept.caps(k: Kept) -> List<&2, Cap>:
  match k:
    case Kept{cs, _}:
      cs

def kept.room(k: Kept) -> Nat:
  match k:
    case Kept{_, r}:
      r

# Wanted paths
# ------------

def seg(f: Frame) -> Seg:
  match f:
    case InObj{k}:
      SKey{k}
    case InArr{i}:
      SIdx{i}

def path.loop(stack: List<&2, Frame>, acc: List<&2, Seg>) -> List<&2, Seg>:
  match stack:
    case Nil{}:
      acc
    case f <> t:
      path.loop(t, seg(f) <> acc)

# The path of the value the stack is at, from the top.
def path(stack: List<&2, Frame>) -> List<&2, Seg>:
  path.loop(stack, Nil{})

def fits(p: Pat, s: Seg) -> Bool:
  match p:
    case PAny{}:
      True{}
    case PKey{n}:
      match s:
        case SKey{k}:
          B.beq(n, k)
        case SIdx{_}:
          False{}

# ok, then whether these heads fit (only compared while all levels so far fit).
def fits.if(ok: Bool, x: Pat, y: Seg) -> Bool:
  match ok:
    case True{}:
      fits(x, y)
    case False{}:
      False{}

# The recursion behind matches. ok: whether the levels taken so far fit; each step compares the
# heads it takes apart, so neither list is copied.
def matches.loop(p: List<&2, Pat>, s: List<&2, Seg>, ok: Bool) -> Bool:
  match p s:
    case Nil{} Nil{}:
      ok
    case Con{x, ps} Con{y, ss}:
      matches.loop(ps, ss, fits.if(ok, x, y))
    case _ _:
      False{}

# Whether a pattern matches a path, level by level (same length).
def matches(p: List<&2, Pat>, s: List<&2, Seg>) -> Bool:
  matches.loop(p, s, True{})

# hit, else whether this pattern matches (patterns after a hit are dropped, not compared).
def matches.if(hit: Bool, p: List<&2, Pat>, +s: List<&2, Seg>) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      matches(p, s)

# The recursion behind wanted.at. hit: whether a pattern taken so far matched; the patterns are
# taken one by one (only the path is copied, once per pattern).
def wanted.loop(ws: Wants, +s: List<&2, Seg>, hit: Bool) -> Bool:
  match ws:
    case Nil{}:
      hit
    case p <> rest:
      wanted.loop(rest, s, matches.if(hit, p, s))

# Whether a value at this path is kept.
def wanted.at(+ws: Wants, +s: List<&2, Seg>) -> Bool:
  wanted.loop(ws, s, False{})

# Whether a value at this stack is kept.
def wanted(+ws: Wants, +stack: List<&2, Frame>) -> Bool:
  wanted.at(ws, path(stack))

# The guard
# ---------
# What a document hands out passes this check once more, whatever the state machine did: only
# values at wanted paths leave the scanner (the laws prove it for every input).

def cap.path(c: Cap) -> List<&2, Seg>:
  match c:
    case Cap{p, _}:
      p

def guard.if(ok: Bool, c: Cap, rest: List<&2, Cap>) -> List<&2, Cap>:
  match ok:
    case True{}:
      c <> rest
    case False{}:
      rest

# The captures at wanted paths, in order.
def guard(+ws: Wants, caps: List<&2, Cap>) -> List<&2, Cap>:
  match caps:
    case Nil{}:
      Nil{}
    case +c <> t:
      guard.if(wanted.at(ws, cap.path(c)), c, guard(ws, t))

# Whether every capture is at a wanted path.
def all.ok(+ws: Wants, caps: List<&2, Cap>) -> Bool:
  match caps:
    case Nil{}:
      True{}
    case +c <> t:
      Bool.and(wanted.at(ws, cap.path(c)), all.ok(ws, t))

def caps.ok(+ws: Wants, m: Maybe<&2, List<&2, Cap>>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{caps}:
      all.ok(ws, caps)

# The values a whole document kept, in order; None when it broke or isn't whole.
def finished(+ws: Wants, s: Scan) -> Maybe<&2, List<&2, Cap>>:
  match s:
    case Scan{mode, _, k}:
      match mode:
        case Whole{}:
          Some{guard(ws, List.reverse(&2, Cap, kept.caps(k)))}
        case _:
          None{}

# The step
# --------
# A byte is read in two parts: move says what it does (from the mode and the open containers),
# land carries it out on the containers and the kept values, within their room.

# What a byte does to the open containers: nothing, open one, close the innermost, or replace
# the innermost (its next key or index).
type Op is Data:
  Stay{}
  Push{f: Frame}
  Pop{}
  Top{f: Frame}

# A byte's effect: the next mode, what happens to the containers and a value to keep (when there
# is room); or the document breaks.
type Move is Data:
  Goes{mode: Mode, op: Op, cap: Maybe<&2, Cap>}
  Breaks{why: String}

def same(m: Mode) -> Move:
  Goes{m, Stay{}, None{}}

def stack.push(st: Stack, f: Frame, m: Mode, k: Kept) -> Scan:
  match st:
    case Stack{fs, room}:
      match room:
        case 0n:
          broken("nested deeper than 64")
        case 1n+r:
          Scan{m, Stack{f <> fs, r}, k}

def stack.pop(st: Stack) -> Stack:
  match st:
    case Stack{fs, room}:
      match fs:
        case Nil{}:
          Stack{Nil{}, room}
        case _ <> rest:
          Stack{rest, 1n+room}

def stack.top(st: Stack, f: Frame) -> Stack:
  match st:
    case Stack{fs, room}:
      match fs:
        case Nil{}:
          Stack{Nil{}, room}
        case _ <> rest:
          Stack{f <> rest, room}

# A value kept, while there is room (later ones are dropped).
def kept.add(cap: Maybe<&2, Cap>, k: Kept) -> Kept:
  match cap:
    case None{}:
      k
    case Some{c}:
      match k:
        case Kept{cs, room}:
          match room:
            case 0n:
              Kept{cs, 0n}
            case 1n+r:
              Kept{c <> cs, r}

def land.op(op: Op, m: Mode, st: Stack, k: Kept) -> Scan:
  match op:
    case Stay{}:
      Scan{m, st, k}
    case Push{f}:
      stack.push(st, f, m, k)
    case Pop{}:
      Scan{m, stack.pop(st), k}
    case Top{f}:
      Scan{m, stack.top(st, f), k}

# A move carried out: the only place the containers and the kept values change.
def land(st: Stack, k: Kept, mv: Move) -> Scan:
  match mv:
    case Breaks{why}:
      broken(why)
    case Goes{m, op, cap}:
      land.op(op, m, st, kept.add(cap, k))

# Whether no more containers may open.
def stack.full(st: Stack) -> Bool:
  match st:
    case Stack{_, room}:
      match room:
        case 0n:
          True{}
        case 1n+_:
          False{}

# Values and containers
# ---------------------

# What follows a value: the container's comma or end, or the document's end.
def after.mode(+stack: List<&2, Frame>) -> Mode:
  match stack:
    case Nil{}:
      Whole{}
    case _:
      After{}

def keep.if(keep: Bool, +stack: List<&2, Frame>, v: Val) -> Maybe<&2, Cap>:
  match keep:
    case True{}:
      Some{Cap{path(stack), v}}
    case False{}:
      None{}

# A scalar value ended; kept when keep (and land finds room).
def value(keep: Bool, +stack: List<&2, Frame>, v: Val) -> Move:
  Goes{after.mode(stack), Stay{}, keep.if(keep, stack, v)}

# A container opens: its frame goes on the stack, and m is what it expects first.
def open(f: Frame, m: Mode, deep: Bool) -> Move:
  match deep:
    case True{}:
      Breaks{"nested deeper than 64"}
    case False{}:
      Goes{m, Push{f}, None{}}

def close.on(top: Frame, object: Bool, +rest: List<&2, Frame>) -> Move:
  match top:
    case InObj{_}:
      match object:
        case True{}:
          Goes{after.mode(rest), Pop{}, None{}}
        case False{}:
          Breaks{"] closing an object"}
    case InArr{_}:
      match object:
        case True{}:
          Breaks{"} closing an array"}
        case False{}:
          Goes{after.mode(rest), Pop{}, None{}}

# A container closes (an object when object, else an array).
def close(object: Bool, stack: List<&2, Frame>) -> Move:
  match stack:
    case Nil{}:
      Breaks{"a close outside any container"}
    case top <> rest:
      close.on(top, object, rest)

# A comma: an object's next key, an array's next index.
def comma(stack: List<&2, Frame>) -> Move:
  match stack:
    case Nil{}:
      Breaks{"a comma outside any container"}
    case top <> _:
      match top:
        case InObj{_}:
          Goes{KeyNext{}, Top{InObj{Nil{}}}, None{}}
        case InArr{i}:
          Goes{Value{}, Top{InArr{(i + 1 : U32)}}, None{}}

# A key ended: it names the value that follows.
def named(name: B.Bytes, stack: List<&2, Frame>) -> Move:
  match stack:
    case Nil{}:
      Breaks{"a key outside an object"}
    case _ <> _:
      Goes{Colon{}, Top{InObj{name}}, None{}}

# Structure
# ---------

# A byte, as the structure sees it.
type Ch is Data:
  Space{}
  LBrace{}
  RBrace{}
  LBracket{}
  RBracket{}
  CommaCh{}
  ColonCh{}
  Quote{}
  NumCh{}
  TCh{}
  FCh{}
  NCh{}
  OtherCh{}

def classify(b: U32) -> Ch:
  match b:
    case 32:
      Space{}
    case 9:
      Space{}
    case 10:
      Space{}
    case 13:
      Space{}
    case 123:
      LBrace{}
    case 125:
      RBrace{}
    case 91:
      LBracket{}
    case 93:
      RBracket{}
    case 44:
      CommaCh{}
    case 58:
      ColonCh{}
    case 34:
      Quote{}
    case 45:
      NumCh{}
    case 48:
      NumCh{}
    case 49:
      NumCh{}
    case 50:
      NumCh{}
    case 51:
      NumCh{}
    case 52:
      NumCh{}
    case 53:
      NumCh{}
    case 54:
      NumCh{}
    case 55:
      NumCh{}
    case 56:
      NumCh{}
    case 57:
      NumCh{}
    case 116:
      TCh{}
    case 102:
      FCh{}
    case 110:
      NCh{}
    case _:
      OtherCh{}

# A value begins (m: the mode to stay in on a space).
def begin(+ws: Wants, ch: Ch, +b: U32, m: Mode, +stack: List<&2, Frame>, deep: Bool) -> Move:
  match ch:
    case Space{}:
      same(m)
    case LBrace{}:
      open(InObj{Nil{}}, KeyOrEnd{}, deep)
    case LBracket{}:
      open(InArr{0}, ArrStart{}, deep)
    case Quote{}:
      same(InString{Txt{False{}, wanted(ws, stack), Nil{}, max_text(), 0}})
    case NumCh{}:
      same(InNumber{[b], number.first_room()})
    case TCh{}:
      same(InWord{[114, 117, 101], Yes{}})
    case FCh{}:
      same(InWord{[97, 108, 115, 101], No{}})
    case NCh{}:
      same(InWord{[117, 108, 108], Null{}})
    case _:
      Breaks{"unexpected byte " ++ U32.show(b)}

def key.text() -> Mode:
  InString{Txt{True{}, False{}, Nil{}, max_text(), 0}}

# A byte where structure is expected (m: the mode, which isn't inside a token).
def structural(+ws: Wants, m: Mode, ch: Ch, +b: U32, +stack: List<&2, Frame>, deep: Bool)
    -> Move:
  match m:
    case ArrStart{}:
      match ch:
        case RBracket{}:
          close(False{}, stack)
        case other:
          begin(ws, other, b, ArrStart{}, stack, deep)
    case KeyOrEnd{}:
      match ch:
        case Space{}:
          same(KeyOrEnd{})
        case Quote{}:
          same(key.text())
        case RBrace{}:
          close(True{}, stack)
        case _:
          Breaks{"expected a key or }"}
    case KeyNext{}:
      match ch:
        case Space{}:
          same(KeyNext{})
        case Quote{}:
          same(key.text())
        case _:
          Breaks{"expected a key"}
    case Colon{}:
      match ch:
        case Space{}:
          same(Colon{})
        case ColonCh{}:
          same(Value{})
        case _:
          Breaks{"expected a colon"}
    case After{}:
      match ch:
        case Space{}:
          same(After{})
        case CommaCh{}:
          comma(stack)
        case RBrace{}:
          close(True{}, stack)
        case RBracket{}:
          close(False{}, stack)
        case _:
          Breaks{"expected a comma or a close"}
    case Whole{}:
      match ch:
        case Space{}:
          same(Whole{})
        case _:
          Breaks{"bytes after the document"}
    case _:
      begin(ws, ch, b, Value{}, stack, deep)

# Strings
# -------

def txt.add.if(take: Bool, room: Nat, +key: Bool, +keep: Bool, acc: B.Bytes, high: U32,
    +b: U32) -> Txt:
  match take:
    case False{}:
      Txt{key, keep, acc, room, high}
    case True{}:
      match room:
        case 0n:
          Txt{key, keep, acc, 0n, high}
        case 1n+r:
          Txt{key, keep, b <> acc, r, high}

# A string's byte, kept when the string is a key or kept, and there is room.
def txt.add(t: Txt, +b: U32) -> Txt:
  match t:
    case Txt{+key, +keep, acc, room, high}:
      txt.add.if(Bool.or(key, keep), room, key, keep, acc, high, b)

def txt.add_all(bs: B.Bytes, t: Txt) -> Txt:
  match bs:
    case Nil{}:
      t
    case b <> rest:
      txt.add_all(rest, txt.add(t, b))

def txt.with_high(t: Txt, high: U32) -> Txt:
  match t:
    case Txt{key, keep, acc, room, _}:
      Txt{key, keep, acc, room, high}

def txt.high(+t: Txt) -> U32:
  match t:
    case Txt{_, _, _, _, high}:
      high

# U+FFFD, in place of a lone surrogate.
def replacement() -> B.Bytes:
  [239, 191, 189]

def txt.flush.if_pending(pending: Bool, t: Txt) -> Txt:
  match pending:
    case True{}:
      txt.add_all(replacement(), txt.with_high(t, 0))
    case False{}:
      t

# A high surrogate that found no low half becomes U+FFFD.
def txt.flush(+t: Txt) -> Txt:
  txt.flush.if_pending(U32.is_ne(txt.high(t), 0), t)

def in_range(+x: U32, lo: U32, hi: U32) -> Bool:
  Bool.and((x >= lo : U32), (x <= hi : U32))

# A code point from \u escapes, with no high surrogate waiting.
def codepoint.alone.if_half(high: Bool, low: Bool, +t: Txt, +c: U32) -> Txt:
  match high:
    case True{}:
      txt.with_high(t, c)
    case False{}:
      match low:
        case True{}:
          txt.add_all(replacement(), t)
        case False{}:
          txt.add_all(B.utf8_char(c), t)

def codepoint.alone(+t: Txt, +c: U32) -> Txt:
  codepoint.alone.if_half(in_range(c, 55296, 56319), in_range(c, 56320, 57343), t, c)

def codepoint.if_low(low: Bool, +t: Txt, +high: U32, +c: U32) -> Txt:
  match low:
    case True{}:
      +cp = (65536 + (((high - 55296) << 10n) + (c - 56320)) : U32)
      txt.add_all(B.utf8_char(cp), txt.with_high(t, 0))
    case False{}:
      codepoint.alone(txt.flush(t), c)

# A \u escape's code point: the low half of a waiting high surrogate, or a code point alone.
def codepoint(+t: Txt, +c: U32) -> Txt:
  codepoint.if_low(Bool.and(U32.is_ne(txt.high(t), 0), in_range(c, 56320, 57343)), t,
    txt.high(t), c)

# A simple escape's byte (after the backslash), or 256 when it isn't one (\u is handled apart).
def unescape(b: U32) -> U32:
  match b:
    case 34:
      34
    case 92:
      92
    case 47:
      47
    case 98:
      8
    case 102:
      12
    case 110:
      10
    case 114:
      13
    case 116:
      9
    case _:
      256

# A hex digit's value, or 16 when it isn't one.
def hex.value.if_range(digit: Bool, lower: Bool, upper: Bool, +b: U32) -> U32:
  match digit:
    case True{}:
      (b - 48 : U32)
    case False{}:
      match lower:
        case True{}:
          (b - 87 : U32)
        case False{}:
          match upper:
            case True{}:
              (b - 55 : U32)
            case False{}:
              16

def hex.value(+b: U32) -> U32:
  hex.value.if_range(in_range(b, 48, 57), in_range(b, 97, 102), in_range(b, 65, 70), b)

def text.end.flushed(t: Txt, +stack: List<&2, Frame>) -> Move:
  match t:
    case Txt{key, keep, acc, _, _}:
      match key:
        case True{}:
          named(List.reverse(&2, U32, acc), stack)
        case False{}:
          value(keep, stack, Str{List.reverse(&2, U32, acc)})

# A string ended: a key names what follows; a value is kept or not.
def text.end(+t: Txt, +stack: List<&2, Frame>) -> Move:
  text.end.flushed(txt.flush(t), stack)

# quote, backslash, control: what the byte is.
def text.byte.if_kind(quote: Bool, backslash: Bool, control: Bool, +t: Txt, +b: U32,
    +stack: List<&2, Frame>) -> Move:
  match quote:
    case True{}:
      text.end(t, stack)
    case False{}:
      match backslash:
        case True{}:
          same(InEscape{t})
        case False{}:
          match control:
            case True{}:
              Breaks{"a control byte in a string"}
            case False{}:
              same(InString{txt.add(txt.flush(t), b)})

# A byte inside a string: its end, an escape, or one of its bytes.
def text.byte(+t: Txt, +b: U32, +stack: List<&2, Frame>) -> Move:
  text.byte.if_kind(U32.is_eq(b, 34), U32.is_eq(b, 92), (b < 32 : U32), t, b, stack)

def escape.on_simple(bad: Bool, +v: U32, +t: Txt) -> Move:
  match bad:
    case True{}:
      Breaks{"a bad escape"}
    case False{}:
      same(InString{txt.add(txt.flush(t), v)})

def escape.on(u: Bool, +v: U32, +t: Txt) -> Move:
  match u:
    case True{}:
      same(InHex{t, 4n, 0})
    case False{}:
      escape.on_simple(U32.is_eq(v, 256), v, t)

# The byte after a backslash: \u starts a code point (a waiting high surrogate stays waiting).
def escape.byte(+t: Txt, +b: U32) -> Move:
  escape.on(U32.is_eq(b, 117), unescape(b), t)

# left: the digits after this one.
def hex.next(left: Nat, +t: Txt, +code: U32) -> Move:
  match left:
    case 0n:
      same(InString{codepoint(t, code)})
    case 1n+q:
      same(InHex{t, 1n+q, code})

def hex.on(bad: Bool, +v: U32, left: Nat, +t: Txt, +code: U32) -> Move:
  match bad:
    case True{}:
      Breaks{"a bad \\u escape"}
    case False{}:
      hex.next(left, t, ((code << 4n) .|. v : U32))

# A hex digit of a \u escape.
def hex.byte(+t: Txt, digits: Nat, +code: U32, +b: U32) -> Move:
  match digits:
    case 0n:
      same(InString{codepoint(t, code)})
    case 1n+p:
      hex.on(U32.is_eq(hex.value(b), 16), hex.value(b), p, t, code)

# Numbers and words
# -----------------

def is_number_byte(+b: U32) -> Bool:
  Bool.or(in_range(b, 48, 57), Bool.or(U32.is_eq(b, 45), Bool.or(U32.is_eq(b, 43),
    Bool.or(U32.is_eq(b, 46), Bool.or(U32.is_eq(b, 101), U32.is_eq(b, 69))))))

def cap.or(a: Maybe<&2, Cap>, b: Maybe<&2, Cap>) -> Maybe<&2, Cap>:
  match a:
    case Some{c}:
      Some{c}
    case None{}:
      b

def resume.on(mv: Move, cap: Maybe<&2, Cap>) -> Move:
  match mv:
    case Breaks{why}:
      Breaks{why}
    case Goes{m, op, c2}:
      Goes{m, op, cap.or(cap, c2)}

# A byte where structure is expected, read right after a value ended (its move: first).
def resume(+ws: Wants, first: Move, +b: U32, +stack: List<&2, Frame>, deep: Bool) -> Move:
  match first:
    case Breaks{why}:
      Breaks{why}
    case Goes{m, _, cap}:
      resume.on(structural(ws, m, classify(b), b, stack, deep), cap)

# more: whether b continues the number; room: how many more characters it may have.
def number.on(more: Bool, room: Nat, +ws: Wants, acc: B.Bytes, +b: U32,
    +stack: List<&2, Frame>, deep: Bool) -> Move:
  match more:
    case True{}:
      match room:
        case 0n:
          Breaks{"a number over 64 characters"}
        case 1n+r:
          same(InNumber{b <> acc, r})
    case False{}:
      resume(ws, value(wanted(ws, stack), stack, Num{List.reverse(&2, U32, acc)}), b, stack, deep)

# A byte after a number's first: more of it, or what follows it (read as such).
def number.byte(+ws: Wants, acc: B.Bytes, room: Nat, +b: U32, +stack: List<&2, Frame>,
    deep: Bool) -> Move:
  number.on(is_number_byte(b), room, ws, acc, b, stack, deep)

def word.on(ok: Bool, rest: B.Bytes, val: Val, +ws: Wants, +stack: List<&2, Frame>) -> Move:
  match ok:
    case False{}:
      Breaks{"a bad literal"}
    case True{}:
      match rest:
        case Nil{}:
          value(wanted(ws, stack), stack, val)
        case _:
          same(InWord{rest, val})

# A byte of true, false or null.
def word.byte(+ws: Wants, rest: B.Bytes, val: Val, +b: U32, +stack: List<&2, Frame>) -> Move:
  match rest:
    case Nil{}:
      Breaks{"a bad literal"}
    case x <> xs:
      word.on(U32.is_eq(b, x), xs, val, ws, stack)

# What a byte does in this mode, with these containers open (deep: no more may open).
def move(+ws: Wants, mode: Mode, +stack: List<&2, Frame>, deep: Bool, +b: U32) -> Move:
  match mode:
    case InString{t}:
      text.byte(t, b, stack)
    case InEscape{t}:
      escape.byte(t, b)
    case InHex{t, digits, code}:
      hex.byte(t, digits, code, b)
    case InNumber{acc, room}:
      number.byte(ws, acc, room, b, stack, deep)
    case InWord{rest, val}:
      word.byte(ws, rest, val, b, stack)
    case Broken{why}:
      Breaks{why}
    case other:
      structural(ws, other, classify(b), b, stack, deep)

# The scanner after one byte.
def step(+ws: Wants, s: Scan, +b: U32) -> Scan:
  match s:
    case Scan{mode, +st, k}:
      land(st, k, move(ws, mode, stack.frames(st), stack.full(st), b))

# The scanner after a run of bytes.
def run(bs: B.Bytes, +ws: Wants, s: Scan) -> Scan:
  match bs:
    case Nil{}:
      s
    case b <> t:
      run(t, ws, step(ws, s, b))

# The values a whole document keeps, in order (None: it broke, or isn't whole).
def scan(+ws: Wants, bs: B.Bytes) -> Maybe<&2, List<&2, Cap>>:
  finished(ws, run(bs, ws, start()))

# The writer
# ==========

def hex.digit.if_digit(digit: Bool, +d: U32) -> U32:
  match digit:
    case True{}:
      (48 + d : U32)
    case False{}:
      (87 + d : U32)

def hex.digit(+d: U32) -> U32:
  hex.digit.if_digit((d < 10 : U32), d)

def esc.if_control(control: Bool, +b: U32) -> B.Bytes:
  match control:
    case True{}:
      [92, 117, 48, 48, hex.digit((b >> 4n : U32)), hex.digit((b .&. 15 : U32))]
    case False{}:
      [b]

# A string byte as JSON writes it: quote, backslash and control bytes escaped.
def esc.byte(b: U32) -> B.Bytes:
  match b:
    case 34:
      [92, 34]
    case 92:
      [92, 92]
    case 10:
      [92, 110]
    case 13:
      [92, 114]
    case 9:
      [92, 116]
    case +other:
      esc.if_control((other < 32 : U32), other)

def esc(bs: B.Bytes) -> B.Bytes:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      B.cat(esc.byte(b), esc(t))

# A JSON string of UTF-8 bytes.
def string(bs: B.Bytes) -> B.Bytes:
  34 <> B.cat(esc(bs), [34])

def text(s: String) -> B.Bytes:
  string(B.utf8(s))

def number(+n: U32) -> B.Bytes:
  B.utf8(U32.show(n))

def boolean(b: Bool) -> B.Bytes:
  match b:
    case True{}:
      B.utf8("true")
    case False{}:
      B.utf8("false")

def null() -> B.Bytes:
  B.utf8("null")

# A kept value written back as JSON.
def val(v: Val) -> B.Bytes:
  match v:
    case Str{bs}:
      string(bs)
    case Num{t}:
      t
    case Yes{}:
      B.utf8("true")
    case No{}:
      B.utf8("false")
    case Null{}:
      null()

# An object's member: its key, and its value already written as JSON.
type Field is Data:
  Field{key: String, value: B.Bytes}

def members(fs: List<&2, Field>, first: Bool) -> B.Bytes:
  match fs:
    case Nil{}:
      Nil{}
    case f <> t:
      match f:
        case Field{k, v}:
          match first:
            case True{}:
              B.cat(text(k), 58 <> B.cat(v, members(t, False{})))
            case False{}:
              44 <> B.cat(text(k), 58 <> B.cat(v, members(t, False{})))

# An object of these members, in order.
def object(fs: List<&2, Field>) -> B.Bytes:
  123 <> B.cat(members(fs, True{}), [125])

def items(xs: List<&2, B.Bytes>, first: Bool) -> B.Bytes:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      match first:
        case True{}:
          B.cat(x, items(t, False{}))
        case False{}:
          44 <> B.cat(x, items(t, False{}))

# An array of values already written as JSON.
def array(xs: List<&2, B.Bytes>) -> B.Bytes:
  91 <> B.cat(items(xs, True{}), [93])
