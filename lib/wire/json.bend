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
def max_depth() -> U32:
  64

# At most this many values are kept from a document; later ones are dropped.
def max_caps() -> U32:
  256

# A kept string (or a key) keeps this many bytes; the rest are dropped.
def max_text() -> U32:
  4096

# A number has at most this many characters; longer is broken.
def max_number() -> U32:
  64

# The scanner
# ===========

# The containers open around the scanner, innermost first: an object and its current key (empty
# before the first), an array and its current index.
type Frame is Data:
  InObj{key: B.Bytes}
  InArr{i: U32}

# A string being read: whether it is a key, whether its bytes are kept, the bytes so far (newest
# first) and their count, and a high surrogate waiting for its low half (0: none).
type Txt is Data:
  Txt{key: Bool, keep: Bool, acc: B.Bytes, n: U32, high: U32}

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
  # a number's characters so far (newest first) and their count
  InNumber{acc: B.Bytes, n: U32}
  # true, false or null: the bytes still expected, and the value
  InWord{rest: B.Bytes, val: Val}
  # the document is whole
  Whole{}
  # the document broke JSON's rules; nothing more is read
  Broken{why: String}

# The scanner: what it expects, the open containers and how many, the values kept (newest first)
# and how many.
type Scan is Data:
  Scan{mode: Mode, stack: List<&2, Frame>, depth: U32, caps: List<&2, Cap>, ncaps: U32}

# A scanner before a document.
def start() -> Scan:
  Scan{Value{}, Nil{}, 0, Nil{}, 0}

def broken(why: String) -> Scan:
  Scan{Broken{why}, Nil{}, 0, Nil{}, 0}

# The values a whole document kept, in order; None when it broke or isn't whole.
def finished(s: Scan) -> Maybe<&2, List<&2, Cap>>:
  match s:
    case Scan{mode, _, _, caps, _}:
      match mode:
        case Whole{}:
          Some{List.reverse(&2, Cap, caps)}
        case _:
          None{}

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

# Whether both have a first level, and the pattern's fits the path's.
def heads.fit(p: List<&2, Pat>, s: List<&2, Seg>) -> Bool:
  match p s:
    case Con{x, _} Con{y, _}:
      fits(x, y)
    case _ _:
      False{}

# The recursion behind matches; ok: heads.fit(p, s).
def matches.loop(+p: List<&2, Pat>, +s: List<&2, Seg>, ok: Bool) -> Bool:
  match p s:
    case Nil{} Nil{}:
      True{}
    case Con{_, ps} Con{_, ss}:
      match ok:
        case True{}:
          matches.loop(ps, ss, heads.fit(ps, ss))
        case False{}:
          False{}
    case _ _:
      False{}

# Whether a pattern matches a path, level by level (same length).
def matches(+p: List<&2, Pat>, +s: List<&2, Seg>) -> Bool:
  matches.loop(p, s, heads.fit(p, s))

def first.hit(ws: Wants, +s: List<&2, Seg>) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case p <> _:
      matches(p, s)

# The recursion behind wanted; hit: first.hit(ws, s).
def wanted.loop(+ws: Wants, +s: List<&2, Seg>, hit: Bool) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case _ <> rest:
      match hit:
        case True{}:
          True{}
        case False{}:
          wanted.loop(rest, s, first.hit(rest, s))

# Whether a value at this stack is kept.
def wanted(+ws: Wants, +stack: List<&2, Frame>) -> Bool:
  +s = path(stack)
  wanted.loop(ws, s, first.hit(ws, s))

# Values and containers
# ---------------------

# What follows a value: the container's comma or end, or the document's end.
def after.mode(+stack: List<&2, Frame>) -> Mode:
  match stack:
    case Nil{}:
      Whole{}
    case _:
      After{}

def value.if_taken(taken: Bool, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>,
    +ncaps: U32, v: Val) -> Scan:
  match taken:
    case True{}:
      Scan{after.mode(stack), stack, depth, Cap{path(stack), v} <> caps, (ncaps + 1 : U32)}
    case False{}:
      Scan{after.mode(stack), stack, depth, caps, ncaps}

# A scalar value ended; kept when keep and there is room.
def value(keep: Bool, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32,
    v: Val) -> Scan:
  value.if_taken(Bool.and(keep, (ncaps < max_caps() : U32)), stack, depth, caps, ncaps, v)

def open.if_deep(deep: Bool, f: Frame, m: Mode, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match deep:
    case True{}:
      broken("nested deeper than 64")
    case False{}:
      Scan{m, f <> stack, (depth + 1 : U32), caps, ncaps}

# A container opens: its frame goes on the stack, and m is what it expects first.
def open(f: Frame, m: Mode, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>,
    +ncaps: U32) -> Scan:
  open.if_deep((depth >= max_depth() : U32), f, m, stack, depth, caps, ncaps)

def close.on(top: Frame, object: Bool, +rest: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>,
    +ncaps: U32) -> Scan:
  match top:
    case InObj{_}:
      match object:
        case True{}:
          Scan{after.mode(rest), rest, (depth - 1 : U32), caps, ncaps}
        case False{}:
          broken("] closing an object")
    case InArr{_}:
      match object:
        case True{}:
          broken("} closing an array")
        case False{}:
          Scan{after.mode(rest), rest, (depth - 1 : U32), caps, ncaps}

# A container closes (an object when object, else an array).
def close(object: Bool, stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32)
    -> Scan:
  match stack:
    case Nil{}:
      broken("a close outside any container")
    case top <> rest:
      close.on(top, object, rest, depth, caps, ncaps)

# A comma: an object's next key, an array's next index.
def comma(stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match stack:
    case Nil{}:
      broken("a comma outside any container")
    case top <> rest:
      match top:
        case InObj{_}:
          Scan{KeyNext{}, InObj{Nil{}} <> rest, depth, caps, ncaps}
        case InArr{i}:
          Scan{Value{}, InArr{(i + 1 : U32)} <> rest, depth, caps, ncaps}

# A key ended: it names the value that follows.
def named(name: B.Bytes, stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32)
    -> Scan:
  match stack:
    case Nil{}:
      broken("a key outside an object")
    case _ <> rest:
      Scan{Colon{}, InObj{name} <> rest, depth, caps, ncaps}

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
def begin(+ws: Wants, ch: Ch, +b: U32, m: Mode, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match ch:
    case Space{}:
      Scan{m, stack, depth, caps, ncaps}
    case LBrace{}:
      open(InObj{Nil{}}, KeyOrEnd{}, stack, depth, caps, ncaps)
    case LBracket{}:
      open(InArr{0}, ArrStart{}, stack, depth, caps, ncaps)
    case Quote{}:
      Scan{InString{Txt{False{}, wanted(ws, stack), Nil{}, 0, 0}}, stack, depth, caps, ncaps}
    case NumCh{}:
      Scan{InNumber{[b], 1}, stack, depth, caps, ncaps}
    case TCh{}:
      Scan{InWord{[114, 117, 101], Yes{}}, stack, depth, caps, ncaps}
    case FCh{}:
      Scan{InWord{[97, 108, 115, 101], No{}}, stack, depth, caps, ncaps}
    case NCh{}:
      Scan{InWord{[117, 108, 108], Null{}}, stack, depth, caps, ncaps}
    case _:
      broken("unexpected byte " ++ U32.show(b))

def key.text() -> Mode:
  InString{Txt{True{}, False{}, Nil{}, 0, 0}}

# A byte where structure is expected (m: the mode, which isn't inside a token).
def structural(+ws: Wants, m: Mode, ch: Ch, +b: U32, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match m:
    case ArrStart{}:
      match ch:
        case RBracket{}:
          close(False{}, stack, depth, caps, ncaps)
        case other:
          begin(ws, other, b, ArrStart{}, stack, depth, caps, ncaps)
    case KeyOrEnd{}:
      match ch:
        case Space{}:
          Scan{KeyOrEnd{}, stack, depth, caps, ncaps}
        case Quote{}:
          Scan{key.text(), stack, depth, caps, ncaps}
        case RBrace{}:
          close(True{}, stack, depth, caps, ncaps)
        case _:
          broken("expected a key or }")
    case KeyNext{}:
      match ch:
        case Space{}:
          Scan{KeyNext{}, stack, depth, caps, ncaps}
        case Quote{}:
          Scan{key.text(), stack, depth, caps, ncaps}
        case _:
          broken("expected a key")
    case Colon{}:
      match ch:
        case Space{}:
          Scan{Colon{}, stack, depth, caps, ncaps}
        case ColonCh{}:
          Scan{Value{}, stack, depth, caps, ncaps}
        case _:
          broken("expected a colon")
    case After{}:
      match ch:
        case Space{}:
          Scan{After{}, stack, depth, caps, ncaps}
        case CommaCh{}:
          comma(stack, depth, caps, ncaps)
        case RBrace{}:
          close(True{}, stack, depth, caps, ncaps)
        case RBracket{}:
          close(False{}, stack, depth, caps, ncaps)
        case _:
          broken("expected a comma or a close")
    case Whole{}:
      match ch:
        case Space{}:
          Scan{Whole{}, stack, depth, caps, ncaps}
        case _:
          broken("bytes after the document")
    case _:
      begin(ws, ch, b, Value{}, stack, depth, caps, ncaps)

# Strings
# -------

def txt.add.if_room(room: Bool, t: Txt, +b: U32) -> Txt:
  match room:
    case True{}:
      match t:
        case Txt{key, keep, acc, n, high}:
          Txt{key, keep, b <> acc, (n + 1 : U32), high}
    case False{}:
      t

# A string's byte, kept when the string is a key or kept, and there is room.
def txt.add(t: Txt, +b: U32) -> Txt:
  match t:
    case Txt{+key, +keep, acc, +n, high}:
      txt.add.if_room(Bool.and(Bool.or(key, keep), (n < max_text() : U32)),
        Txt{key, keep, acc, n, high}, b)

def txt.add_all(bs: B.Bytes, t: Txt) -> Txt:
  match bs:
    case Nil{}:
      t
    case b <> rest:
      txt.add_all(rest, txt.add(t, b))

def txt.with_high(t: Txt, high: U32) -> Txt:
  match t:
    case Txt{key, keep, acc, n, _}:
      Txt{key, keep, acc, n, high}

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

def text.end.flushed(t: Txt, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>,
    +ncaps: U32) -> Scan:
  match t:
    case Txt{key, keep, acc, _, _}:
      match key:
        case True{}:
          named(List.reverse(&2, U32, acc), stack, depth, caps, ncaps)
        case False{}:
          value(keep, stack, depth, caps, ncaps, Str{List.reverse(&2, U32, acc)})

# A string ended: a key names what follows; a value is kept or not.
def text.end(+t: Txt, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32)
    -> Scan:
  text.end.flushed(txt.flush(t), stack, depth, caps, ncaps)

# quote, backslash, control: what the byte is.
def text.byte.if_kind(quote: Bool, backslash: Bool, control: Bool, +t: Txt, +b: U32,
    +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match quote:
    case True{}:
      text.end(t, stack, depth, caps, ncaps)
    case False{}:
      match backslash:
        case True{}:
          Scan{InEscape{t}, stack, depth, caps, ncaps}
        case False{}:
          match control:
            case True{}:
              broken("a control byte in a string")
            case False{}:
              Scan{InString{txt.add(txt.flush(t), b)}, stack, depth, caps, ncaps}

# A byte inside a string: its end, an escape, or one of its bytes.
def text.byte(+t: Txt, +b: U32, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>,
    +ncaps: U32) -> Scan:
  text.byte.if_kind(U32.is_eq(b, 34), U32.is_eq(b, 92), (b < 32 : U32), t, b, stack, depth, caps,
    ncaps)

def escape.on_simple(bad: Bool, +v: U32, +t: Txt, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match bad:
    case True{}:
      broken("a bad escape")
    case False{}:
      Scan{InString{txt.add(txt.flush(t), v)}, stack, depth, caps, ncaps}

def escape.on(u: Bool, +v: U32, +t: Txt, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match u:
    case True{}:
      Scan{InHex{t, 4n, 0}, stack, depth, caps, ncaps}
    case False{}:
      escape.on_simple(U32.is_eq(v, 256), v, t, stack, depth, caps, ncaps)

# The byte after a backslash: \u starts a code point (a waiting high surrogate stays waiting).
def escape.byte(+t: Txt, +b: U32, +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>,
    +ncaps: U32) -> Scan:
  escape.on(U32.is_eq(b, 117), unescape(b), t, stack, depth, caps, ncaps)

# left: the digits after this one.
def hex.next(left: Nat, +t: Txt, +code: U32, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match left:
    case 0n:
      Scan{InString{codepoint(t, code)}, stack, depth, caps, ncaps}
    case 1n+q:
      Scan{InHex{t, 1n+q, code}, stack, depth, caps, ncaps}

def hex.on(bad: Bool, +v: U32, left: Nat, +t: Txt, +code: U32, +stack: List<&2, Frame>,
    +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match bad:
    case True{}:
      broken("a bad \\u escape")
    case False{}:
      hex.next(left, t, ((code << 4n) .|. v : U32), stack, depth, caps, ncaps)

# A hex digit of a \u escape.
def hex.byte(+t: Txt, digits: Nat, +code: U32, +b: U32, +stack: List<&2, Frame>, +depth: U32,
    caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match digits:
    case 0n:
      Scan{InString{codepoint(t, code)}, stack, depth, caps, ncaps}
    case 1n+p:
      hex.on(U32.is_eq(hex.value(b), 16), hex.value(b), p, t, code, stack, depth, caps, ncaps)

# Numbers and words
# -----------------

def is_number_byte(+b: U32) -> Bool:
  Bool.or(in_range(b, 48, 57), Bool.or(U32.is_eq(b, 45), Bool.or(U32.is_eq(b, 43),
    Bool.or(U32.is_eq(b, 46), Bool.or(U32.is_eq(b, 101), U32.is_eq(b, 69))))))

# A byte where structure is expected, read by a scanner that just finished a value.
def resume(+ws: Wants, s: Scan, +b: U32) -> Scan:
  match s:
    case Scan{m, +stack, +depth, caps, +ncaps}:
      structural(ws, m, classify(b), b, stack, depth, caps, ncaps)

# more: whether b continues the number; long: whether it would pass max_number.
def number.on(more: Bool, long: Bool, +ws: Wants, acc: B.Bytes, +n: U32, +b: U32,
    +stack: List<&2, Frame>, +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match more:
    case True{}:
      match long:
        case True{}:
          broken("a number over 64 characters")
        case False{}:
          Scan{InNumber{b <> acc, (n + 1 : U32)}, stack, depth, caps, ncaps}
    case False{}:
      resume(ws, value(wanted(ws, stack), stack, depth, caps, ncaps,
        Num{List.reverse(&2, U32, acc)}), b)

# A byte after a number's first: more of it, or what follows it (read as such).
def number.byte(+ws: Wants, acc: B.Bytes, +n: U32, +b: U32, +stack: List<&2, Frame>,
    +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  number.on(is_number_byte(b), (n >= max_number() : U32), ws, acc, n, b, stack, depth, caps, ncaps)

def word.on(ok: Bool, rest: B.Bytes, val: Val, +ws: Wants, +stack: List<&2, Frame>,
    +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match ok:
    case False{}:
      broken("a bad literal")
    case True{}:
      match rest:
        case Nil{}:
          value(wanted(ws, stack), stack, depth, caps, ncaps, val)
        case _:
          Scan{InWord{rest, val}, stack, depth, caps, ncaps}

# A byte of true, false or null.
def word.byte(+ws: Wants, rest: B.Bytes, val: Val, +b: U32, +stack: List<&2, Frame>,
    +depth: U32, caps: List<&2, Cap>, +ncaps: U32) -> Scan:
  match rest:
    case Nil{}:
      broken("a bad literal")
    case x <> xs:
      word.on(U32.is_eq(b, x), xs, val, ws, stack, depth, caps, ncaps)

# The scanner after one byte.
def step(+ws: Wants, s: Scan, +b: U32) -> Scan:
  match s:
    case Scan{mode, +stack, +depth, caps, +ncaps}:
      match mode:
        case InString{t}:
          text.byte(t, b, stack, depth, caps, ncaps)
        case InEscape{t}:
          escape.byte(t, b, stack, depth, caps, ncaps)
        case InHex{t, digits, code}:
          hex.byte(t, digits, code, b, stack, depth, caps, ncaps)
        case InNumber{acc, n}:
          number.byte(ws, acc, n, b, stack, depth, caps, ncaps)
        case InWord{rest, val}:
          word.byte(ws, rest, val, b, stack, depth, caps, ncaps)
        case Broken{why}:
          broken(why)
        case other:
          structural(ws, other, classify(b), b, stack, depth, caps, ncaps)

# The scanner after a run of bytes.
def run(bs: B.Bytes, +ws: Wants, s: Scan) -> Scan:
  match bs:
    case Nil{}:
      s
    case b <> t:
      run(t, ws, step(ws, s, b))

# The values a whole document keeps, in order (None: it broke, or isn't whole).
def scan(+ws: Wants, bs: B.Bytes) -> Maybe<&2, List<&2, Cap>>:
  finished(run(bs, ws, start()))

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
