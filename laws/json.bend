import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/json.bend as J
# The JSON scanner and writer (lib/wire/json.bend).

def k(s: String) -> J.Pat:
  J.PKey{B.utf8(s)}

def sk(s: String) -> J.Seg:
  J.SKey{B.utf8(s)}

def str(s: String) -> J.Val:
  J.Str{B.utf8(s)}

# Paths wanted by the examples.
def wants() -> J.Wants:
  [[k("event")], [k("data"), k("seconds_played")], [k("data"), k("name")],
   [k("result"), J.PAny{}, k("name")], [k("s")]]

# n opening brackets, then n closing ones.
def nest(n: Nat) -> B.Bytes:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      91 <> B.cat(nest(p), [93])

# Examples
# ========

# A play report: only the wanted values, wherever they are, nested arrays skipped.
law json_keeps_wanted:
  {J.scan(wants(), B.utf8("{\"event\": \"media_item_played\", \"data\": {\"uri\": \"x\", "
     ++ "\"artists\": [\"a\", {\"b\": [1, 2.5e3, null]}], \"name\": \"Balan\\u00e7o\", "
     ++ "\"seconds_played\": 162, \"fully_played\": true}}"))
    == Some{[J.Cap{[sk("event")], str("media_item_played")},
             J.Cap{[sk("data"), sk("name")], J.Str{[66, 97, 108, 97, 110, 195, 167, 111]}},
             J.Cap{[sk("data"), sk("seconds_played")], J.Num{B.utf8("162")}}]}
    : Maybe<&2, List<&2, J.Cap>>}

# Any index: each element's value, with its index in the path.
law json_any_index:
  {J.scan(wants(), B.utf8("{\"result\": [{\"name\": \"Living Room\", \"x\": false}, "
     ++ "{\"name\": \"Move 2\"}]}"))
    == Some{[J.Cap{[sk("result"), J.SIdx{0}, sk("name")], str("Living Room")},
             J.Cap{[sk("result"), J.SIdx{1}, sk("name")], str("Move 2")}]}
    : Maybe<&2, List<&2, J.Cap>>}

# Escapes: a surrogate pair is one code point (U+1F600), and the simple ones their bytes.
law json_escapes:
  {J.scan(wants(), B.utf8("{\"s\": \"\\ud83d\\ude00 \\\" \\n\\t\\/\"}"))
    == Some{[J.Cap{[sk("s")], J.Str{[240, 159, 152, 128, 32, 34, 32, 10, 9, 47]}}]}
    : Maybe<&2, List<&2, J.Cap>>}

# A lone surrogate becomes U+FFFD.
law json_lone_surrogate:
  {J.scan(wants(), B.utf8("{\"s\": \"\\ud83dx\"}"))
    == Some{[J.Cap{[sk("s")], J.Str{[239, 191, 189, 120]}}]} : Maybe<&2, List<&2, J.Cap>>}

# Broken documents keep nothing.
law json_refuses_broken:
  {[J.scan(wants(), B.utf8("{\"s\": [1,}")), J.scan(wants(), B.utf8("{\"s\": 1} x")),
    J.scan(wants(), B.utf8("{\"s\": tru}")), J.scan(wants(), B.utf8("{\"s\": \"a")),
    J.scan(wants(), B.utf8("{\"s\" 1}")), J.scan(wants(), B.utf8("[1]]"))]
    == [None{}, None{}, None{}, None{}, None{}, None{}] : List<&2, Maybe<&2, List<&2, J.Cap>>>}

# Nesting: 64 levels are read, 65 are refused.
law json_depth_capped:
  {[J.scan(wants(), nest(64n)), J.scan(wants(), nest(65n))] == [Some{Nil{}}, None{}]
    : List<&2, Maybe<&2, List<&2, J.Cap>>>}

# The writer escapes what JSON needs and nothing else.
law json_writes:
  {J.object([J.Field{"a", J.text("q\"\n\\")}, J.Field{"n", J.number(42)},
     J.Field{"l", J.array([J.boolean(True{}), J.null(), J.string([1, 195, 169])])}])
    == B.utf8("{\"a\":\"q\\\"\\n\\\\\",\"n\":42,\"l\":[true,null,\"\\u0001\u{e9}\"]}")
    : B.Bytes}

# For every input
# ===============

# However the bytes are split, the scanner ends the same.
law json_feed_split:
  for xs: B.Bytes
  for +ys: B.Bytes
  for +ws: J.Wants
  for s: J.Scan
  {J.run(B.cat(xs, ys), ws, s) == J.run(ys, ws, J.run(xs, ws, s)) : J.Scan}

# A broken document stays broken, whatever follows.
law json_broken_absorbs:
  for bs: B.Bytes
  for +ws: J.Wants
  for +why: String
  {J.finished(ws, J.run(bs, ws, J.broken(why))) == None{} : Maybe<&2, List<&2, J.Cap>>}

# Privacy
# -------

# For every scanner state and every set of wanted paths: whatever a document hands out is at a
# wanted path (J.finished's guard), so no other value ever leaves the scanner.
law json_finished_only_wanted:
  for +ws: J.Wants
  for s: J.Scan
  {J.caps.ok(ws, J.finished(ws, s)) == True{} : Bool}

# For every document.
law json_scan_only_wanted:
  for +ws: J.Wants
  for bs: B.Bytes
  {J.caps.ok(ws, J.scan(ws, bs)) == True{} : Bool}

# Memory
# ------
# For every wanted paths and bytes: the open containers plus the room left are max_depth (64), and
# the kept values plus the room left are max_caps (256), so a document never holds more, however
# it is built.

def stack.size(+st: J.Stack) -> Nat:
  Nat.add(List.length(&2, J.Frame, J.stack.frames(st)), J.stack.room(st))

def kept.size(+k: J.Kept) -> Nat:
  Nat.add(List.length(&2, J.Cap, J.kept.caps(k)), J.kept.room(k))

law json_depth_bounded:
  for +ws: J.Wants
  for +bs: B.Bytes
  {stack.size(J.scan.stack(J.run(bs, ws, J.start()))) == J.max_depth() : Nat}

law json_kept_bounded:
  for +ws: J.Wants
  for +bs: B.Bytes
  {kept.size(J.scan.kept(J.run(bs, ws, J.start()))) == J.max_caps() : Nat}

# For every wanted paths and bytes: a string being read holds its bytes plus its room equal to
# max_text (4096), a number its characters plus its room equal to max_number (64).
def txt.ok(t: J.Txt) -> Bool:
  match t:
    case J.Txt{_, _, acc, room, _}:
      Nat.is_eq(Nat.add(List.length(&2, U32, acc), room), J.max_text())

def mode.ok(m: J.Mode) -> Bool:
  match m:
    case J.InString{t}:
      txt.ok(t)
    case J.InEscape{t}:
      txt.ok(t)
    case J.InHex{t, _, _}:
      txt.ok(t)
    case J.InNumber{acc, room}:
      Nat.is_eq(Nat.add(List.length(&2, U32, acc), room), J.max_number())
    case _:
      True{}

law json_buffers_bounded:
  for +ws: J.Wants
  for +bs: B.Bytes
  {mode.ok(J.scan.mode(J.run(bs, ws, J.start()))) == True{} : Bool}
