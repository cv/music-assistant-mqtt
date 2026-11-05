import Base
# Byte strings and the pure encodings built on them: integers, UTF-8, a reader
# monad for binary formats, base64, hex and equality. No I/O here; the
# formats themselves (MQTT, WebSocket, JSON) live in their own modules.

# A byte string: a list of U32 values, each in 0..255. Encoders here only emit
# values in that range; readers mask what they read.
def Bytes() -> Data:
  List<&2, U32>

# The two byte strings one after the other.
def cat(+a: Bytes, +b: Bytes) -> Bytes:
  List.append(&2, U32, a, b)

# Big-endian 16-bit integer.
def u16(+n: U32) -> Bytes:
  [((n >> 8n) .&. 255 : U32), (n .&. 255 : U32)]

# Big-endian 32-bit integer.
def u32(+n: U32) -> Bytes:
  [(n >> 24n : U32), ((n >> 16n) .&. 255 : U32), ((n >> 8n) .&. 255 : U32),
   (n .&. 255 : U32)]

# UTF-8
# -----

# The bytes of one code point; one_byte, two_bytes, three_bytes: whether it
# fits in that many (below 0x80, 0x800, 0x10000).
def utf8_char.if_fits(one_byte: Bool, two_bytes: Bool, three_bytes: Bool, +c: U32) -> Bytes:
  match one_byte:
    case True{}:
      [c]
    case False{}:
      match two_bytes:
        case True{}:
          [(192 .|. (c >> 6n) : U32), (128 .|. (c .&. 63) : U32)]
        case False{}:
          match three_bytes:
            case True{}:
              [(224 .|. (c >> 12n) : U32), (128 .|. ((c >> 6n) .&. 63) : U32),
               (128 .|. (c .&. 63) : U32)]
            case False{}:
              [(240 .|. ((c >> 18n) .&. 7) : U32), (128 .|. ((c >> 12n) .&. 63) : U32),
               (128 .|. ((c >> 6n) .&. 63) : U32), (128 .|. (c .&. 63) : U32)]

# The UTF-8 bytes of one code point.
def utf8_char(+c: U32) -> Bytes:
  utf8_char.if_fits((c < 128 : U32), (c < 2048 : U32), (c < 65536 : U32), c)

# The UTF-8 bytes of a string.
def utf8(s: String) -> Bytes:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      cat(utf8_char(c), utf8(t))

# Reader
# ------
# A cursor over a byte list. Reading past the end answers 0 and clears `ok`,
# so a decoder reads a whole structure and checks `ok` once at the end.

type Cur is Data:
  # ok: nothing was read past the end so far
  # bs: the bytes not read yet
  Cur{ok: Bool, bs: Bytes}

# The reader monad over Cur, for `do Rd<A>:` blocks.
def Rd(-A: Type) -> Type:
  Cur -> A & Cur

def Rd.pure(-A: Type, x: A) -> Rd(A):
  c => (x, c)

# The second reader, given what the first one read.
def Rd.bind.then(-A: Type, -B: Type, f: A -> Rd(B), r: A & Cur) -> B & Cur:
  (a, c) = r
  f(a)(c)

def Rd.bind(-A: Type, -B: Type, m: Rd(A), f: A -> Rd(B)) -> Rd(B):
  c => Rd.bind.then(A, B, f, m(c))

# Runs a reader over the given bytes.
def Rd.run(-A: Type, m: Rd(A), bs: Bytes) -> A & Cur:
  m(Cur{True{}, bs})

def u8.read(c: Cur) -> U32 & Cur:
  match c:
    case Cur{ok, Nil{}}:
      ({0 : U32}, Cur{False{}, Nil{}})
    case Cur{ok, h <> t}:
      ((h .&. 255 : U32), Cur{ok, t})

# One byte.
def u8_r() -> Rd(U32):
  c => u8.read(c)

def u16.join(+hi: U32, +lo: U32) -> U32:
  ((hi << 8n) .|. lo : U32)

# A big-endian 16-bit integer.
def u16_r() -> Rd(U32):
  do Rd<U32>:
    hi : U32 <- u8_r()
    lo : U32 <- u8_r()
    return u16.join(hi, lo)

# The next n bytes.
def take_r(n: Nat) -> Rd(Bytes):
  match n:
    case 0n:
      Rd.pure(Bytes, Nil{})
    case 1n+p:
      do Rd<Bytes>:
        b : U32 <- u8_r()
        bs : Bytes <- take_r(p)
        return b <> bs

def rest.read(c: Cur) -> Bytes & Cur:
  match c:
    case Cur{ok, bs}:
      (bs, Cur{ok, Nil{}})

# Everything left.
def rest_r() -> Rd(Bytes):
  c => rest.read(c)

# A u16 length, then that many bytes.
def bin_r() -> Rd(Bytes):
  do Rd<Bytes>:
    n : U32 <- u16_r()
    bs : Bytes <- take_r(U32.to_nat(n))
    return bs

# A finished read: Some when nothing was read past the end.
def Rd.ok(-A: Type, r: A & Cur) -> Maybe<&1, A>:
  (a, c) = r
  Cur{ok, _} = c
  match ok:
    case True{}:
      Some{a}
    case False{}:
      None{}

def u32.join(+hi: U32, +lo: U32) -> U32:
  ((hi << 16n) .|. lo : U32)

# A big-endian 32-bit integer.
def u32_r() -> Rd(U32):
  do Rd<U32>:
    hi : U32 <- u16_r()
    lo : U32 <- u16_r()
    return u32.join(hi, lo)

# UTF-8 decoding
# --------------
# Bytes are classified first, so the decoder recurses on the token list alone.
# Malformed input never fails: stray continuation bytes are skipped and a
# truncated sequence at the end is dropped.

# A byte's role in UTF-8, with its payload bits.
type Tok is Data:
  Asc{v: U32}
  # need: how many continuation bytes follow
  Lead{need: Nat, v: U32}
  Cont{v: U32}

# The token of a byte; ascii, cont, lead2, lead3: whether it is below 0x80,
# 0xC0, 0xE0, 0xF0.
def tok.if_below(ascii: Bool, cont: Bool, lead2: Bool, lead3: Bool, +x: U32) -> Tok:
  match ascii:
    case True{}:
      Asc{x}
    case False{}:
      match cont:
        case True{}:
          Cont{(x .&. 63 : U32)}
        case False{}:
          match lead2:
            case True{}:
              Lead{1n, (x .&. 31 : U32)}
            case False{}:
              match lead3:
                case True{}:
                  Lead{2n, (x .&. 15 : U32)}
                case False{}:
                  Lead{3n, (x .&. 7 : U32)}

def tok(+b: U32) -> Tok:
  +x = (b .&. 255 : U32)
  tok.if_below((x < 128 : U32), (x < 192 : U32), (x < 224 : U32), (x < 240 : U32), x)

def toks(bs: Bytes) -> List<&2, Tok>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      tok(b) <> toks(t)

# need: continuation bytes still expected; acc: the code point's bits so far.
def from_toks(ts: List<&2, Tok>, need: Nat, +acc: U32) -> String:
  match ts:
    case Nil{}:
      SNil{}
    case Asc{v} <> t:
      SCon{Chr{v}, from_toks(t, 0n, 0)}
    case Lead{n, v} <> t:
      from_toks(t, n, v)
    case Cont{+v} <> t:
      match need:
        case 0n:
          from_toks(t, 0n, 0)
        case 1n+r:
          match r:
            case 0n:
              SCon{Chr{((acc << 6n) .|. v : U32)}, from_toks(t, 0n, 0)}
            case 1n+s:
              from_toks(t, 1n+s, ((acc << 6n) .|. v : U32))

# The text of UTF-8 bytes (bad bytes dropped).
def from_utf8(bs: Bytes) -> String:
  from_toks(toks(bs), 0n, 0)

# Base64 (RFC 4648, with padding)
# -------------------------------

# upper, lower, digit, plus: whether the value is below 26, 52, 62, or is 62.
def b64c.if_range(upper: Bool, lower: Bool, digit: Bool, plus: Bool, +v: U32) -> U32:
  match upper:
    case True{}:
      (65 + v : U32)
    case False{}:
      match lower:
        case True{}:
          (71 + v : U32)
        case False{}:
          match digit:
            case True{}:
              (v - 4 : U32)
            case False{}:
              match plus:
                case True{}:
                  43
                case False{}:
                  47

# The character for a 6-bit value.
def b64c(+v: U32) -> U32:
  +x = (v .&. 63 : U32)
  b64c.if_range((x < 26 : U32), (x < 52 : U32), (x < 62 : U32), U32.is_eq(x, 62), x)

# The base64 text of bytes, padded with '='.
def b64e(bs: Bytes) -> Bytes:
  match bs:
    case +a <> +b <> +c <> t:
      b64c((a >> 2n : U32)) <> b64c((((a .&. 3) << 4n) .|. (b >> 4n) : U32))
        <> b64c((((b .&. 15) << 2n) .|. (c >> 6n) : U32)) <> b64c(c) <> b64e(t)
    case +a <> +b <> Nil{}:
      [b64c((a >> 2n : U32)), b64c((((a .&. 3) << 4n) .|. (b >> 4n) : U32)),
       b64c(((b .&. 15) << 2n : U32)), 61]
    case +a <> Nil{}:
      [b64c((a >> 2n : U32)), b64c(((a .&. 3) << 4n : U32)), 61, 61]
    case Nil{}:
      Nil{}

# upper, lower, digit: whether c is 'A'..'Z', 'a'..'z', '0'..'9'.
def b64v.if_range(upper: Bool, lower: Bool, digit: Bool, +c: U32) -> U32:
  match upper:
    case True{}:
      (c - 65 : U32)
    case False{}:
      match lower:
        case True{}:
          (c - 71 : U32)
        case False{}:
          match digit:
            case True{}:
              (c + 4 : U32)
            case False{}:
              match c:
                case 43:
                  62
                case 47:
                  63
                case _:
                  64

# The 6-bit value of a character; 64 for '=' and anything not in the alphabet.
def b64v(+c: U32) -> U32:
  b64v.if_range(
    Bool.and((c >= 65 : U32), (c <= 90 : U32)),
    Bool.and((c >= 97 : U32), (c <= 122 : U32)),
    Bool.and((c >= 48 : U32), (c <= 57 : U32)),
    c)

def b64vs(cs: Bytes) -> Bytes:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      b64v(c) <> b64vs(t)

def b64d.first(+a: U32, +b: U32) -> U32:
  (((a << 2n) .|. (b >> 4n)) .&. 255 : U32)

def b64d.second(+b: U32, +c: U32) -> U32:
  ((((b .&. 15) << 4n) .|. (c >> 2n)) .&. 255 : U32)

def b64d.third(+c: U32, d: U32) -> U32:
  ((((c .&. 3) << 6n) .|. d) .&. 255 : U32)

# The bytes of one group of four values a, b, c, d; pad_c, pad_d: whether c or
# d is padding (64).
def b64d.group(pad_c: Bool, pad_d: Bool, +a: U32, +b: U32, +c: U32, +d: U32) -> Bytes:
  match pad_c:
    case True{}:
      [b64d.first(a, b)]
    case False{}:
      match pad_d:
        case True{}:
          [b64d.first(a, b), b64d.second(b, c)]
        case False{}:
          [b64d.first(a, b), b64d.second(b, c), b64d.third(c, d)]

def b64d.loop(vs: Bytes) -> Bytes:
  match vs:
    case +a <> +b <> +c <> +d <> t:
      cat(b64d.group(U32.is_eq(c, 64), U32.is_eq(d, 64), a, b, c, d), b64d.loop(t))
    case _:
      Nil{}

# Decodes base64 text; a short final group is dropped.
def b64d(cs: Bytes) -> Bytes:
  b64d.loop(b64vs(cs))

# Hex
# ---

def hex.digit(+v: U32) -> Char:
  Char.from_u32(Bool.pick(U32, (v < 10 : U32), (48 + v : U32), (87 + v : U32)))

# The last n hex digits of x.
def hex.loop(n: Nat, +x: U32) -> String:
  match n:
    case 0n:
      ""
    case 1n+p:
      hex.loop(p, (x >> 4n : U32)) ++ SCon{hex.digit((x .&. 15 : U32)), SNil{}}

# Eight lowercase hex digits.
def hex(+x: U32) -> String:
  hex.loop(8n, x)

# Equality
# --------
# Byte-list equality that stops at the first difference: whether the heads
# are equal is worked out by the caller (`heads`) and passed as a Bool, so no
# work is spent past the first difference (Bool.and would compare it all).

# Whether both lists have a first byte, and it is the same.
def heads(a: Bytes, b: Bytes) -> Bool:
  match a b:
    case Con{x, _} Con{y, _}:
      U32.is_eq(x, y)
    case _ _:
      False{}

# The recursion behind beq; eq: heads(a, b).
def beq.loop(+a: Bytes, +b: Bytes, eq: Bool) -> Bool:
  match a b:
    case Nil{} Nil{}:
      True{}
    case Con{_, xs} Con{_, ys}:
      match eq:
        case True{}:
          beq.loop(xs, ys, heads(xs, ys))
        case False{}:
          False{}
    case _ _:
      False{}

# Whether two byte strings are equal.
def beq(+a: Bytes, +b: Bytes) -> Bool:
  beq.loop(a, b, heads(a, b))

# Pieces gathered newest first, joined in order.
def flat(pieces: List<&2, Bytes>) -> Bytes:
  List.concat(&2, U32, List.reverse(&2, Bytes, pieces))
