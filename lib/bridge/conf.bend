import Base
import ../wire/bytes.bend as B
# The config file: one "key value" per line, # comments, read once at start. Every problem is
# reported with its line and has no effect; the token and the password are never echoed (the
# summary leaves them out, a law).

# Music Assistant: where it is and the long-lived token made in its UI.
type Ma is Data:
  Ma{host: String, port: U32, token: String}

# The broker and our login there.
type Mq is Data:
  Mq{host: String, port: U32, user: String, password: String, client: String}

# What we publish: the topic prefix, and the plays file ("" when off).
type Out is Data:
  Out{prefix: String, plays: String}

type Conf is Data:
  Conf{ma: Ma, mq: Mq, out: Out}

def defaults() -> Conf:
  Conf{Ma{"127.0.0.1", 8095, ""}, Mq{"", 1883, "", "", "music-assistant-mqtt"},
    Out{"music", "/data/plays.jsonl"}}

def conf.ma(c: Conf) -> Ma:
  match c:
    case Conf{ma, _, _}:
      ma

def conf.mq(c: Conf) -> Mq:
  match c:
    case Conf{_, mq, _}:
      mq

def conf.out(c: Conf) -> Out:
  match c:
    case Conf{_, _, out}:
      out

def ma.host(m: Ma) -> String:
  match m:
    case Ma{h, _, _}:
      h

def ma.port(m: Ma) -> U32:
  match m:
    case Ma{_, p, _}:
      p

def ma.token(m: Ma) -> String:
  match m:
    case Ma{_, _, t}:
      t

def mq.host(m: Mq) -> String:
  match m:
    case Mq{h, _, _, _, _}:
      h

def mq.port(m: Mq) -> U32:
  match m:
    case Mq{_, p, _, _, _}:
      p

def mq.user(m: Mq) -> String:
  match m:
    case Mq{_, _, u, _, _}:
      u

def mq.password(m: Mq) -> String:
  match m:
    case Mq{_, _, _, p, _}:
      p

def mq.client(m: Mq) -> String:
  match m:
    case Mq{_, _, _, _, c}:
      c

def out.prefix(o: Out) -> String:
  match o:
    case Out{p, _}:
      p

def out.plays(o: Out) -> String:
  match o:
    case Out{_, f}:
      f

# The config with these secrets (the summary law varies them).
def with_secrets(c: Conf, token: String, password: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match ma:
        case Ma{mh, mp, _}:
          match mq:
            case Mq{qh, qp, user, _, client}:
              Conf{Ma{mh, mp, token}, Mq{qh, qp, user, password, client}, out}

def plays.text.if_off(off: Bool, s: String) -> String:
  match off:
    case True{}:
      "off"
    case False{}:
      s

def plays.text(+s: String) -> String:
  plays.text.if_off(List.is_empty(&2, U32, B.utf8(s)), s)

# What the log says about the config: everything but the token and the password.
def summary(c: Conf) -> String:
  match c:
    case Conf{ma, mq, out}:
      match ma:
        case Ma{mh, mp, _}:
          match mq:
            case Mq{qh, qp, user, _, client}:
              match out:
                case Out{prefix, plays}:
                  "Music Assistant " ++ mh ++ ":" ++ U32.show(mp) ++ ", broker " ++ user ++ "@"
                    ++ qh ++ ":" ++ U32.show(qp) ++ " as " ++ client ++ ", topics under "
                    ++ prefix ++ "/, plays file " ++ plays.text(plays)

# Lines and words
# ---------------

def is_space(+b: U32) -> Bool:
  Bool.or(U32.is_eq(b, 32), Bool.or(U32.is_eq(b, 9), U32.is_eq(b, 13)))

def head.is(+bs: B.Bytes, +x: U32) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case b <> _:
      U32.is_eq(b, x)

def head.space(+bs: B.Bytes) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case b <> _:
      is_space(b)

# The lines of the file, in order (cur: the line so far, newest first; nl: bs starts with \n).
def lines.loop(+bs: B.Bytes, cur: B.Bytes, acc: List<&2, B.Bytes>, nl: Bool)
    -> List<&2, B.Bytes>:
  match bs:
    case Nil{}:
      List.reverse(&2, B.Bytes, List.reverse(&2, U32, cur) <> acc)
    case b <> t:
      match nl:
        case True{}:
          lines.loop(t, Nil{}, List.reverse(&2, U32, cur) <> acc, head.is(t, 10))
        case False{}:
          lines.loop(t, b <> cur, acc, head.is(t, 10))

def lines(+bs: B.Bytes) -> List<&2, B.Bytes>:
  lines.loop(bs, Nil{}, Nil{}, head.is(bs, 10))

# Without leading spaces (sp: bs starts with one).
def trim.loop(+bs: B.Bytes, sp: Bool) -> B.Bytes:
  match bs:
    case Nil{}:
      Nil{}
    case _ <> t:
      match sp:
        case True{}:
          trim.loop(t, head.space(t))
        case False{}:
          bs

def trim.left(+bs: B.Bytes) -> B.Bytes:
  trim.loop(bs, head.space(bs))

def trim(+bs: B.Bytes) -> B.Bytes:
  List.reverse(&2, U32, trim.left(List.reverse(&2, U32, trim.left(bs))))

# A line's first word and the rest after it (sp: bs starts with a space).
type Split is Data:
  Split{word: B.Bytes, rest: B.Bytes}

def word.loop(+bs: B.Bytes, acc: B.Bytes, sp: Bool) -> Split:
  match bs:
    case Nil{}:
      Split{List.reverse(&2, U32, acc), Nil{}}
    case b <> t:
      match sp:
        case True{}:
          Split{List.reverse(&2, U32, acc), trim(bs)}
        case False{}:
          word.loop(t, b <> acc, head.space(t))

def word(+bs: B.Bytes) -> Split:
  word.loop(bs, Nil{}, head.space(bs))

# Values
# ------

def digit(+b: U32) -> Bool:
  Bool.and((b >= 48 : U32), (b <= 57 : U32))

def port.check(fits: Bool, +n: U32) -> Maybe<&2, U32>:
  match fits:
    case True{}:
      Some{n}
    case False{}:
      None{}

# A decimal number in 1..65535 (None: anything else). ok: the bytes before bs were digits.
def port.loop(+bs: B.Bytes, +acc: U32, ok: Bool) -> Maybe<&2, U32>:
  match bs:
    case Nil{}:
      match ok:
        case True{}:
          port.check(Bool.and((acc >= 1 : U32), (acc <= 65535 : U32)), acc)
        case False{}:
          None{}
    case b <> t:
      match ok:
        case True{}:
          port.loop(t, (acc * 10 + (b - 48) : U32), Bool.and(digit(b), (acc <= 65535 : U32)))
        case False{}:
          None{}

def port(+bs: B.Bytes) -> Maybe<&2, U32>:
  port.loop(bs, 0, Bool.not(List.is_empty(&2, U32, bs)))

# Whether bs holds byte x anywhere.
def holds(bs: B.Bytes, +x: U32) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case b <> t:
      Bool.or(U32.is_eq(b, x), holds(t, x))

# A topic prefix: not empty, no + or #, not starting or ending with /.
def prefix.ok(+bs: B.Bytes) -> Bool:
  Bool.and(Bool.not(List.is_empty(&2, U32, bs)),
    Bool.and(Bool.not(Bool.or(holds(bs, 43), holds(bs, 35))),
      Bool.not(Bool.or(head.is(bs, 47), head.is(List.reverse(&2, U32, bs), 47)))))

# Keys
# ----

type Key is Data:
  MaHost{}
  MaPort{}
  MaToken{}
  MqHost{}
  MqPort{}
  MqUser{}
  MqPassword{}
  Prefix{}
  Client{}
  Plays{}
  Unknown{}

type Entry is Data:
  Entry{name: String, key: Key}

def keys() -> List<&2, Entry>:
  [Entry{"ma_host", MaHost{}}, Entry{"ma_port", MaPort{}}, Entry{"ma_token", MaToken{}},
   Entry{"mqtt_host", MqHost{}}, Entry{"mqtt_port", MqPort{}}, Entry{"mqtt_user", MqUser{}},
   Entry{"mqtt_password", MqPassword{}}, Entry{"topic_prefix", Prefix{}},
   Entry{"client_id", Client{}}, Entry{"plays_file", Plays{}}]

def entry.is(+es: List<&2, Entry>, +k: B.Bytes) -> Bool:
  match es:
    case Nil{}:
      False{}
    case e <> _:
      match e:
        case Entry{name, _}:
          B.beq(B.utf8(name), k)

# The key a name is (hit: the first entry has that name).
def key.loop(+es: List<&2, Entry>, +k: B.Bytes, hit: Bool) -> Key:
  match es:
    case Nil{}:
      Unknown{}
    case e <> t:
      match e:
        case Entry{_, key}:
          match hit:
            case True{}:
              key
            case False{}:
              key.loop(t, k, entry.is(t, k))

def key.of(+k: B.Bytes) -> Key:
  key.loop(keys(), k, entry.is(keys(), k))

# Reading
# -------

type Problem is Data:
  Problem{line: U32, what: String}

# The config so far and the problems found (newest first).
type Read is Data:
  Read{conf: Conf, problems: List<&2, Problem>}

def problem(r: Read, +line: U32, what: String) -> Read:
  match r:
    case Read{c, ps}:
      Read{c, Problem{line, what} <> ps}

# A key's value, checked: text, a port, the plays file switched off, or what is wrong with it.
type Value is Data:
  VText{s: String}
  VPort{p: U32}
  VOff{}
  VWrong{why: String}

def value.port(m: Maybe<&2, U32>) -> Value:
  match m:
    case None{}:
      VWrong{"a port is a number in 1..65535"}
    case Some{p}:
      VPort{p}

def value.prefix(ok: Bool, +v: B.Bytes) -> Value:
  match ok:
    case True{}:
      VText{B.from_utf8(v)}
    case False{}:
      VWrong{"a topic prefix is not empty, has no + or #, and doesn't start or end with /"}

def value.plays(off: Bool, +v: B.Bytes) -> Value:
  match off:
    case True{}:
      VOff{}
    case False{}:
      VText{B.from_utf8(v)}

def value(k: Key, +v: B.Bytes) -> Value:
  match k:
    case MaPort{}:
      value.port(port(v))
    case MqPort{}:
      value.port(port(v))
    case Prefix{}:
      value.prefix(prefix.ok(v), v)
    case Plays{}:
      value.plays(B.beq(v, B.utf8("off")), v)
    case _:
      VText{B.from_utf8(v)}

# One setter per field.
def with.ma_host(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match ma:
        case Ma{_, p, t}:
          Conf{Ma{x, p, t}, mq, out}

def with.ma_port(c: Conf, +x: U32) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match ma:
        case Ma{h, _, t}:
          Conf{Ma{h, x, t}, mq, out}

def with.ma_token(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match ma:
        case Ma{h, p, _}:
          Conf{Ma{h, p, x}, mq, out}

def with.mq_host(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match mq:
        case Mq{_, p, u, w, cl}:
          Conf{ma, Mq{x, p, u, w, cl}, out}

def with.mq_port(c: Conf, +x: U32) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match mq:
        case Mq{h, _, u, w, cl}:
          Conf{ma, Mq{h, x, u, w, cl}, out}

def with.mq_user(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match mq:
        case Mq{h, p, _, w, cl}:
          Conf{ma, Mq{h, p, x, w, cl}, out}

def with.mq_password(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match mq:
        case Mq{h, p, u, _, cl}:
          Conf{ma, Mq{h, p, u, x, cl}, out}

def with.mq_client(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match mq:
        case Mq{h, p, u, w, _}:
          Conf{ma, Mq{h, p, u, w, x}, out}

def with.prefix(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match out:
        case Out{_, pl}:
          Conf{ma, mq, Out{x, pl}}

def with.plays(c: Conf, x: String) -> Conf:
  match c:
    case Conf{ma, mq, out}:
      match out:
        case Out{pre, _}:
          Conf{ma, mq, Out{pre, x}}

def set.text(k: Key, c: Conf, x: String) -> Conf:
  match k:
    case MaHost{}:
      with.ma_host(c, x)
    case MaToken{}:
      with.ma_token(c, x)
    case MqHost{}:
      with.mq_host(c, x)
    case MqUser{}:
      with.mq_user(c, x)
    case MqPassword{}:
      with.mq_password(c, x)
    case Prefix{}:
      with.prefix(c, x)
    case Client{}:
      with.mq_client(c, x)
    case Plays{}:
      with.plays(c, x)
    case _:
      c

def set.port(k: Key, c: Conf, +x: U32) -> Conf:
  match k:
    case MaPort{}:
      with.ma_port(c, x)
    case _:
      with.mq_port(c, x)

# The read after a key's checked value.
def set(v: Value, k: Key, +line: U32, r: Read) -> Read:
  match v:
    case VText{x}:
      match r:
        case Read{c, ps}:
          Read{set.text(k, c, x), ps}
    case VPort{p}:
      match r:
        case Read{c, ps}:
          Read{set.port(k, c, p), ps}
    case VOff{}:
      match r:
        case Read{c, ps}:
          Read{with.plays(c, ""), ps}
    case VWrong{why}:
      problem(r, line, why)

# Lines
# -----

# A one-word value: the word, unless more follows that isn't a comment (extra), or it is
# missing (empty).
def line.word.if(extra: Bool, empty: Bool, +w: B.Bytes, +key: Key, +n: U32, r: Read) -> Read:
  match extra:
    case True{}:
      problem(r, n, "one value expected")
    case False{}:
      match empty:
        case True{}:
          problem(r, n, "a value is missing")
        case False{}:
          set(value(key, w), key, n, r)

def line.word.on(+s: Split, +key: Key, +n: U32, r: Read) -> Read:
  match s:
    case Split{w, extra}:
      line.word.if(Bool.and(Bool.not(List.is_empty(&2, U32, extra)), Bool.not(head.is(extra, 35))),
        List.is_empty(&2, U32, w), w, key, n, r)

# The password is the rest of the line: spaces and # are part of it.
def line.password.if(empty: Bool, +rest: B.Bytes, +n: U32, r: Read) -> Read:
  match empty:
    case True{}:
      problem(r, n, "a value is missing")
    case False{}:
      set(VText{B.from_utf8(rest)}, MqPassword{}, n, r)

def line.set(+key: Key, +rest: B.Bytes, +n: U32, r: Read) -> Read:
  match key:
    case Unknown{}:
      problem(r, n, "unknown key")
    case MqPassword{}:
      line.password.if(List.is_empty(&2, U32, rest), rest, n, r)
    case _:
      line.word.on(word(rest), key, n, r)

def line.kv(+s: Split, +n: U32, r: Read) -> Read:
  match s:
    case Split{k, rest}:
      line.set(key.of(k), rest, n, r)

def line.on(skip: Bool, +t: B.Bytes, +n: U32, r: Read) -> Read:
  match skip:
    case True{}:
      r
    case False{}:
      line.kv(word(t), n, r)

# One line (n: its number): blank and # lines are skipped.
def line.read(+l: B.Bytes, +n: U32, r: Read) -> Read:
  line.on(Bool.or(List.is_empty(&2, U32, trim(l)), head.is(trim(l), 35)), trim(l), n, r)

def parse.loop(ls: List<&2, B.Bytes>, +n: U32, r: Read) -> Read:
  match ls:
    case Nil{}:
      r
    case l <> t:
      parse.loop(t, (n + 1 : U32), line.read(l, n, r))

# The keys without which the bridge can't start (reported as line 0).
def required.token(no_token: Bool, r: Read) -> Read:
  match no_token:
    case True{}:
      problem(r, 0, "ma_token is required")
    case False{}:
      r

def required.if(no_host: Bool, no_token: Bool, r: Read) -> Read:
  match no_host:
    case True{}:
      required.token(no_token, problem(r, 0, "mqtt_host is required"))
    case False{}:
      required.token(no_token, r)

def blank(s: String) -> Bool:
  List.is_empty(&2, U32, B.utf8(s))

def required(+r: Read) -> Read:
  match r:
    case Read{c, _}:
      required.if(blank(mq.host(conf.mq(c))), blank(ma.token(conf.ma(c))), r)

def finish(r: Read) -> Read:
  match r:
    case Read{c, ps}:
      Read{c, List.reverse(&2, Problem, ps)}

# The config a file's bytes give, and its problems in line order.
def parse(+bs: B.Bytes) -> Read:
  finish(required(parse.loop(lines(bs), 1, Read{defaults(), Nil{}})))

def read.conf(r: Read) -> Conf:
  match r:
    case Read{c, _}:
      c

def read.problems(r: Read) -> List<&2, Problem>:
  match r:
    case Read{_, ps}:
      ps

# Whether a problem keeps the bridge from starting (a missing required key).
def fatal(ps: List<&2, Problem>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case p <> t:
      match p:
        case Problem{line, _}:
          Bool.or(U32.is_eq(line, 0), fatal(t))

# A problem as the log says it.
def problem.text.if_line(zero: Bool, +line: U32, what: String) -> String:
  match zero:
    case True{}:
      "config: " ++ what
    case False{}:
      "config line " ++ U32.show(line) ++ ": " ++ what

def problem.text(+p: Problem) -> String:
  match p:
    case Problem{line, what}:
      problem.text.if_line(U32.is_eq(line, 0), line, what)
