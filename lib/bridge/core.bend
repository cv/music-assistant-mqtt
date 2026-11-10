import Base
import ../wire/bytes.bend as B
import ../wire/mqtt.bend as M
import ../ma/api.bend as Api
import ../ma/model.bend as Model
import ../ma/link.bend as L
import ./conf.bend as C
import ./topics.bend as T
# The bridge's decisions as one pure step: a core, the time and an event give the next core and
# what to do. The I/O shell (lib/app) carries the actions out and feeds the events in; the rules
# here are covered by laws (laws/core.bend) and by progs/sim_core.bend.

# The time as the shell reads it: milliseconds for intervals (U32, wrapping every 49 days, which
# differences don't mind) and Unix seconds for the plays' timestamps.
type Time is Data:
  Time{ms: U32, unix: U32}

type Input is Data:
  MqPacket{p: M.Packet}
  MqLost{}
  MaHeard{h: L.Heard}
  Tick{}

# What to do. ToMa carries one of Api's commands, and Api has only three (log in, list the players,
# look an item up): no action can control a player.
type Action is Data:
  ToMq{p: M.Packet}
  OpenMa{}
  ToMa{id: U32, c: Api.Command}
  PongMa{payload: B.Bytes}
  Append{line: B.Bytes}
  Report{}
  Log{line: String}
  Ended{why: String}

# Connecting: waiting for the broker's answer; Opening: Music Assistant's link opening, waiting
# for its hello; LoggingIn: auth sent; Listing: players/all sent; Live; Over: does nothing more.
type Phase is Data:
  Connecting{}
  Opening{}
  LoggingIn{}
  Listing{}
  Live{}
  Over{}

# next: the next message id (1 and 2 are the login and the player list); up: it went live.
type Session is Data:
  Session{phase: Phase, next: U32, up: Bool}

# When we last heard from and sent to the broker, last heard from Music Assistant, last reported.
type Clock is Data:
  Clock{mq_heard: U32, mq_sent: U32, ma_heard: U32, report: U32}

# A player and the state last published for it.
type Known is Data:
  Known{id: B.Bytes, state: B.Bytes}

# A play waiting for its library lookup (id: the lookup's message id; unix: when it was heard).
type Pending is Data:
  Pending{id: U32, play: Model.Play, unix: U32, since: U32}

# held: plays carried from the last session (their lookups never answered), looked up again once
# this one is live.
type Book is Data:
  Book{names: T.Names, known: List<&2, Known>, pending: List<&2, Pending>, plays: U32,
    held: List<&2, Pending>}

type Core is Data:
  Core{conf: C.Conf, session: Session, clock: Clock, book: Book}

type Out is Data:
  Out{core: Core, actions: List<&2, Action>}

# Limits (ms)
def connect_wait() -> U32:
  10000

def ping_every() -> U32:
  30000

def broker_quiet() -> U32:
  90000

def ma_quiet() -> U32:
  60000

def lookup_wait() -> U32:
  10000

def report_every() -> U32:
  60000

# The first report comes this long after going live.
def first_report() -> U32:
  10000

# Accessors
# ---------

def core.conf(c: Core) -> C.Conf:
  match c:
    case Core{conf, _, _, _}:
      conf

def core.session(c: Core) -> Session:
  match c:
    case Core{_, s, _, _}:
      s

def core.clock(c: Core) -> Clock:
  match c:
    case Core{_, _, k, _}:
      k

def core.book(c: Core) -> Book:
  match c:
    case Core{_, _, _, b}:
      b

def core.phase(c: Core) -> Phase:
  match c:
    case Core{_, s, _, _}:
      match s:
        case Session{p, _, _}:
          p

def core.next(c: Core) -> U32:
  match c:
    case Core{_, s, _, _}:
      match s:
        case Session{_, n, _}:
          n

# Whether this session went live (the reconnect backoff restarts after one that did).
def core.up(c: Core) -> Bool:
  match c:
    case Core{_, s, _, _}:
      match s:
        case Session{_, _, u}:
          u

def core.plays(c: Core) -> U32:
  match c:
    case Core{_, _, _, b}:
      match b:
        case Book{_, _, _, n, _}:
          n

def core.players(c: Core) -> Nat:
  match c:
    case Core{_, _, _, b}:
      match b:
        case Book{_, known, _, _, _}:
          List.length(&2, Known, known)

def core.prefix(c: Core) -> String:
  C.out.prefix(C.conf.out(core.conf(c)))

def with.session(c: Core, s: Session) -> Core:
  match c:
    case Core{conf, _, k, b}:
      Core{conf, s, k, b}

def with.clock(c: Core, k: Clock) -> Core:
  match c:
    case Core{conf, s, _, b}:
      Core{conf, s, k, b}

def with.book(c: Core, b: Book) -> Core:
  match c:
    case Core{conf, s, k, _}:
      Core{conf, s, k, b}

def with.phase(c: Core, p: Phase) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match s:
        case Session{_, n, u}:
          Core{conf, Session{p, n, u}, k, b}

def with.next(c: Core, +n: U32) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match s:
        case Session{p, _, u}:
          Core{conf, Session{p, n, u}, k, b}

def with.up(c: Core) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match s:
        case Session{p, n, _}:
          Core{conf, Session{p, n, True{}}, k, b}

def with.mq_heard(c: Core, +t: U32) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match k:
        case Clock{_, ms, ma, r}:
          Core{conf, s, Clock{t, ms, ma, r}, b}

def with.mq_sent(c: Core, +t: U32) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match k:
        case Clock{mh, _, ma, r}:
          Core{conf, s, Clock{mh, t, ma, r}, b}

def with.ma_heard(c: Core, +t: U32) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match k:
        case Clock{mh, ms, _, r}:
          Core{conf, s, Clock{mh, ms, t, r}, b}

def with.report(c: Core, +t: U32) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match k:
        case Clock{mh, ms, ma, _}:
          Core{conf, s, Clock{mh, ms, ma, t}, b}

# Starting and ending
# -------------------

def login.user.if_blank(blank: Bool, s: String) -> Maybe<&2, String>:
  match blank:
    case True{}:
      None{}
    case False{}:
      Some{s}

def login.user(+s: String) -> Maybe<&2, String>:
  login.user.if_blank(C.blank(s), s)

def status(+c: Core, payload: String) -> Action:
  ToMq{M.Publish{False{}, 0, True{}, T.topic.status(core.prefix(c)), 0, B.utf8(payload)}}

# The broker login, with "offline" as the will.
def connect(+conf: C.Conf) -> M.Packet:
  +mq = C.conf.mq(conf)
  M.Connect{C.mq.client(mq), 60, True{}, login.user(C.mq.user(mq)), login.user(C.mq.password(mq)),
    Some{M.Will{T.topic.status(C.out.prefix(C.conf.out(conf))), B.utf8("offline"), 0, True{}}}}

# A new session: log in to the broker (held: the plays the last one left waiting).
def start(+conf: C.Conf, +t: Time, held: List<&2, Pending>) -> Out:
  match t:
    case Time{ms, _}:
      Out{Core{conf, Session{Connecting{}, 3, False{}}, Clock{ms, ms, ms, ms},
        Book{Nil{}, Nil{}, Nil{}, 0, held}}, [ToMq{connect(conf)}]}

# The session ends: say offline and disconnect when the broker still listens, then close.
def finish(+c: Core, +why: String, connected: Bool) -> Out:
  match connected:
    case True{}:
      Out{with.phase(c, Over{}), [status(c, "offline"), ToMq{M.Disconnect{}}, Log{why}, Ended{why}]}
    case False{}:
      Out{with.phase(c, Over{}), [Log{why}, Ended{why}]}

# The reconnect backoff: 1 s after a session that went live, else doubling up to 60 s.
def backoff.wait(step: Nat) -> U32:
  match step:
    case 0n:
      1000
    case 1n+a:
      match a:
        case 0n:
          2000
        case 1n+b:
          match b:
            case 0n:
              4000
            case 1n+c:
              match c:
                case 0n:
                  8000
                case 1n+d:
                  match d:
                    case 0n:
                      16000
                    case 1n+e:
                      match e:
                        case 0n:
                          32000
                        case 1n+_:
                          60000

def backoff.cap(over: Bool, +step: Nat) -> Nat:
  match over:
    case True{}:
      6n
    case False{}:
      1n+step

def backoff.next(+step: Nat, up: Bool) -> Nat:
  match up:
    case True{}:
      0n
    case False{}:
      backoff.cap(Nat.is_gt(step, 5n), step)

# The broker
# ----------

# Its answer to the login: accepted (in Connecting) opens Music Assistant's link.
def connack.on(ok: Bool, ph: Phase, +code: U32, +c: Core, +t: Time) -> Out:
  match ok:
    case False{}:
      finish(c, "the broker refused the login (code " ++ U32.show(code) ++ ")", False{})
    case True{}:
      match ph:
        case Connecting{}:
          match t:
            case Time{ms, _}:
              Out{with.ma_heard(with.phase(c, Opening{}), ms), [OpenMa{}]}
        case _:
          Out{c, Nil{}}

def mq(+c: Core, +t: Time, p: M.Packet) -> Out:
  match p:
    case M.ConnAck{_, +code}:
      connack.on(U32.is_eq(code, 0), core.phase(c), code, c, t)
    case _:
      Out{c, Nil{}}

# Players
# -------

def known.same(ks: List<&2, Known>, +id: B.Bytes, +state: B.Bytes) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case k <> t:
      match k:
        case Known{kid, ks2}:
          Bool.or(Bool.and(B.beq(kid, id), B.beq(ks2, state)), known.same(t, id, state))

def known.drop.if(same: Bool, kid: B.Bytes, st: B.Bytes, rest: List<&2, Known>)
    -> List<&2, Known>:
  match same:
    case True{}:
      rest
    case False{}:
      Known{kid, st} <> rest

def known.drop(ks: List<&2, Known>, +id: B.Bytes) -> List<&2, Known>:
  match ks:
    case Nil{}:
      Nil{}
    case k <> t:
      match k:
        case Known{+kid, st}:
          known.drop.if(B.beq(kid, id), kid, st, known.drop(t, id))

# A player's topic level (learned names never change; an unknown id is its slug).
def level.on(m: Maybe<&2, B.Bytes>, +id: B.Bytes) -> B.Bytes:
  match m:
    case Some{l}:
      l
    case None{}:
      T.or_player(T.slug(id))

def player.id(p: Model.Player) -> B.Bytes:
  match p:
    case Model.Player{id, _, _, _}:
      id

def player.name(p: Model.Player) -> B.Bytes:
  match p:
    case Model.Player{_, name, _, _}:
      name

def out.core(o: Out) -> Core:
  match o:
    case Out{c, _}:
      c

def out.actions(o: Out) -> List<&2, Action>:
  match o:
    case Out{_, a}:
      a

def time.ms(t: Time) -> U32:
  match t:
    case Time{ms, _}:
      ms

# The player's state, published (retained) when it differs from what was last published (same:
# it doesn't, or the player has no level to publish under).
def publish.if_new(same: Bool, b: Book, +c: Core, +id: B.Bytes, +level: B.Bytes, +state: B.Bytes)
    -> Out:
  match same:
    case True{}:
      Out{with.book(c, b), Nil{}}
    case False{}:
      match b:
        case Book{names, known, pending, plays, held}:
          Out{with.book(c, Book{names, Known{id, state} <> known.drop(known, id), pending, plays,
            held}),
            [ToMq{M.Publish{False{}, 0, True{}, T.topic.state(core.prefix(c), level), 0, state}}]}

def publish.learned(b: Book, +c: Core, +id: B.Bytes, +p: Model.Player) -> Out:
  match b:
    case Book{names, +known, pending, plays, held}:
      +names2 = T.learn(names, id, player.name(p))
      +state = T.state(p)
      +level = level.on(T.level.of(names2, id), id)
      publish.if_new(Bool.or(List.is_empty(&2, U32, level), known.same(known, id, state)),
        Book{names2, known, pending, plays, held}, c, id, level, state)

# A player heard of: learn its name, publish its state if it changed.
def publish.player(+c: Core, +p: Model.Player) -> Out:
  publish.learned(core.book(c), c, player.id(p), p)

# Every player published in turn (each one's actions, then the rest's).
def players.publish(ps: List<&2, Model.Player>, +c: Core) -> Out:
  match ps:
    case Nil{}:
      Out{c, Nil{}}
    case p <> t:
      +o = publish.player(c, p)
      +rest = players.publish(t, out.core(o))
      Out{out.core(rest), List.append(&2, Action, out.actions(o), out.actions(rest))}

# Plays
# -----

def play.final(p: Model.Play) -> Bool:
  match p:
    case Model.Play{_, _, _, f, _}:
      f

def play.uri(p: Model.Play) -> B.Bytes:
  match p:
    case Model.Play{item, _, _, _, _}:
      match item:
        case Model.Media{uri, _, _, _, _}:
          uri

def play.player(p: Model.Play) -> B.Bytes:
  match p:
    case Model.Play{_, _, _, _, player}:
      player

def pending.id(p: Pending) -> U32:
  match p:
    case Pending{id, _, _, _}:
      id

# A final report: look its item up (the play is published when the answer comes, or without
# ids after lookup_wait).
def played.lookup(b: Book, +c: Core, +t: Time, +p: Model.Play) -> Out:
  match b:
    case Book{names, known, pending, plays, held}:
      match t:
        case Time{ms, unix}:
          +id = core.next(c)
          Out{with.next(with.book(c, Book{names, known, Pending{id, p, unix, ms} <> pending, plays,
            held}),
            (id + 1 : U32)), [ToMa{id, Api.Lookup{play.uri(p)}}]}

def played.if(final: Bool, +c: Core, +t: Time, +p: Model.Play) -> Out:
  match final:
    case False{}:
      Out{c, Nil{}}
    case True{}:
      played.lookup(core.book(c), c, t, p)

# A play report: only the final one (not is_playing) counts.
def played(+c: Core, +t: Time, +p: Model.Play) -> Out:
  played.if(play.final(p), c, t, p)

def append.if(on: Bool, +line: B.Bytes) -> List<&2, Action>:
  match on:
    case True{}:
      [Append{B.cat(line, [10])}]
    case False{}:
      Nil{}

# A play's publish, not retained (and its line for the plays file when there is one).
def publish.play.acts(names: T.Names, +c: Core, pd: Pending, ids: Model.Ids) -> List<&2, Action>:
  match pd:
    case Pending{_, +play, +unix, _}:
      +line = T.played(unix, level.on(T.level.of(names, play.player(play)), play.player(play)),
        play, ids)
      ToMq{M.Publish{False{}, 0, False{}, T.topic.played(core.prefix(c)), 0, line}}
        <> append.if(Bool.not(C.blank(C.out.plays(C.conf.out(core.conf(c))))), line)

# A play published, with these ids, and counted (the count doesn't depend on the play).
def publish.play(b: Book, +c: Core, pd: Pending, ids: Model.Ids) -> Out:
  match b:
    case Book{+names, known, pending, plays, held}:
      Out{with.book(c, Book{names, known, pending, (plays + 1 : U32), held}),
        publish.play.acts(names, c, pd, ids)}

# Whether a pending play is the one a reply with these id bytes answers.
def pending.answers(+p: Pending, +id: B.Bytes) -> Bool:
  B.beq(B.utf8(U32.show(pending.id(p))), id)

def pending.drop.if(same: Bool, p: Pending, rest: List<&2, Pending>) -> List<&2, Pending>:
  match same:
    case True{}:
      rest
    case False{}:
      p <> rest

# The pending plays without any a reply with these id bytes answers.
def pending.drop(ps: List<&2, Pending>, +id: B.Bytes) -> List<&2, Pending>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      pending.drop.if(pending.answers(p, id), p, pending.drop(t, id))

def pending.head(+ps: List<&2, Pending>, +id: B.Bytes) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case p <> _:
      pending.answers(p, id)

# The play a reply with these id bytes answers (hit: the first one does).
def pending.find(+ps: List<&2, Pending>, +id: B.Bytes, hit: Bool) -> Maybe<&2, Pending>:
  match ps:
    case Nil{}:
      None{}
    case p <> t:
      match hit:
        case True{}:
          Some{p}
        case False{}:
          pending.find(t, id, pending.head(t, id))

# The play answered under these id bytes: out of the book (with any other answering them) and
# published.
def answered.take(b: Book, +c: Core, +pd: Pending, +id: B.Bytes, ids: Model.Ids) -> Out:
  match b:
    case Book{names, known, pending, plays, held}:
      publish.play(Book{names, known, pending.drop(pending, id), plays, held}, c, pd, ids)

def answered.on(m: Maybe<&2, Pending>, +c: Core, +id: B.Bytes, ids: Model.Ids) -> Out:
  match m:
    case None{}:
      Out{c, Nil{}}
    case Some{pd}:
      answered.take(core.book(c), c, pd, id, ids)

def book.pending(b: Book) -> List<&2, Pending>:
  match b:
    case Book{_, _, p, _, _}:
      p

# A lookup's answer (or refusal: ids empty) publishes its play.
def answered(+c: Core, +id: B.Bytes, ids: Model.Ids) -> Out:
  +ps = book.pending(core.book(c))
  answered.on(pending.find(ps, id, pending.head(ps, id)), c, id, ids)

def no_ids() -> Model.Ids:
  Model.Ids{Nil{}, Nil{}, Nil{}}

def book.held(b: Book) -> List<&2, Pending>:
  match b:
    case Book{_, _, _, _, h}:
      h

def with.held(c: Core, h: List<&2, Pending>) -> Core:
  match c:
    case Core{conf, s, k, b}:
      match b:
        case Book{names, known, pending, plays, _}:
          Core{conf, s, k, Book{names, known, pending, plays, h}}

# What a session that ends now leaves waiting: its pending plays, and those still held.
def core.left(c: Core) -> List<&2, Pending>:
  match c:
    case Core{_, _, _, b}:
      match b:
        case Book{_, _, pending, _, held}:
          List.append(&2, Pending, pending, held)

# Carried plays
# -------------

def relook.add(b: Book, +c: Core, +play: Model.Play, +unix: U32, +ms: U32) -> Out:
  match b:
    case Book{names, known, pending, plays, held}:
      +id = core.next(c)
      Out{with.next(with.book(c, Book{names, known, Pending{id, play, unix, ms} <> pending, plays,
        held}), (id + 1 : U32)), [ToMa{id, Api.Lookup{play.uri(play)}}]}

def relook.one(h: Pending, +c: Core, +ms: U32) -> Out:
  match h:
    case Pending{_, +play, +unix, _}:
      relook.add(core.book(c), c, play, unix, ms)

# The plays carried from the last session, looked up again under new ids (pending from now on,
# with the time they were heard).
def relook(hs: List<&2, Pending>, +c: Core, +ms: U32) -> Out:
  match hs:
    case Nil{}:
      Out{c, Nil{}}
    case h <> t:
      +o = relook.one(h, c, ms)
      +rest = relook(t, out.core(o), ms)
      Out{out.core(rest), List.append(&2, Action, out.actions(o), out.actions(rest))}

# The player list arrived: live, every player published, online; the carried plays looked up.
def live(+c: Core, +t: Time, +ps: List<&2, Model.Player>) -> Out:
  +o = players.publish(ps, with.up(with.phase(c, Live{})))
  +r = relook(book.held(core.book(out.core(o))), with.held(out.core(o), Nil{}), time.ms(t))
  Out{with.report(out.core(r), (time.ms(t) - (report_every() - first_report()) : U32)),
    Log{"live: " ++ Nat.show(List.length(&2, Model.Player, ps)) ++ " players"}
      <> status(c, "online") <> List.append(&2, Action, out.actions(o), out.actions(r))}

# Music Assistant
# ---------------

def is.text(+bs: B.Bytes, s: String) -> Bool:
  B.beq(bs, B.utf8(s))

def reply.login(mine: Bool, ok: Bool, +c: Core) -> Out:
  match mine:
    case False{}:
      Out{c, Nil{}}
    case True{}:
      match ok:
        case True{}:
          Out{with.phase(c, Listing{}), [ToMa{2, Api.ListPlayers{}}]}
        case False{}:
          finish(c, "Music Assistant didn't accept the token", True{})

def reply.list(mine: Bool, +id: B.Bytes, +c: Core, +t: Time, +caps: Model.Caps) -> Out:
  match mine:
    case True{}:
      live(c, t, Model.players(caps))
    case False{}:
      answered(c, id, Model.ids(caps))

def refused.list(mine: Bool, +id: B.Bytes, details: B.Bytes, +c: Core) -> Out:
  match mine:
    case True{}:
      finish(c, "Music Assistant refused the player list: " ++ B.from_utf8(details), True{})
    case False{}:
      answered(c, id, no_ids())

def happened(updated: Bool, play: Bool, +c: Core, +t: Time, +caps: Model.Caps) -> Out:
  match updated:
    case True{}:
      publish.player(c, Model.player(caps, Model.at(["data"])))
    case False{}:
      match play:
        case True{}:
          played(c, t, Model.play(caps))
        case False{}:
          Out{c, Nil{}}

def message.on(m: Model.Msg, ph: Phase, +c: Core, +t: Time, +caps: Model.Caps) -> Out:
  match m:
    case Model.Hello{v}:
      match ph:
        case Opening{}:
          Out{with.phase(c, LoggingIn{}), [Log{"Music Assistant " ++ B.from_utf8(v)},
            ToMa{1, Api.Login{C.ma.token(C.conf.ma(core.conf(c)))}}]}
        case _:
          Out{c, Nil{}}
    case Model.Reply{+id}:
      match ph:
        case LoggingIn{}:
          reply.login(is.text(id, "1"), Model.logged_in(caps), c)
        case Listing{}:
          reply.list(is.text(id, "2"), id, c, t, caps)
        case Live{}:
          answered(c, id, Model.ids(caps))
        case _:
          Out{c, Nil{}}
    case Model.Refused{+id, _, details}:
      match ph:
        case LoggingIn{}:
          finish(c, "Music Assistant refused the login: " ++ B.from_utf8(details), True{})
        case Listing{}:
          refused.list(is.text(id, "2"), id, details, c)
        case Live{}:
          answered(c, id, no_ids())
        case _:
          Out{c, Nil{}}
    case Model.Happened{+ev, _}:
      match ph:
        case Listing{}:
          happened(Bool.or(is.text(ev, "player_updated"), is.text(ev, "player_added")),
            is.text(ev, "media_item_played"), c, t, caps)
        case Live{}:
          happened(Bool.or(is.text(ev, "player_updated"), is.text(ev, "player_added")),
            is.text(ev, "media_item_played"), c, t, caps)
        case _:
          Out{c, Nil{}}
    case Model.Unknown{}:
      Out{c, Nil{}}

def ma.on(h: L.Heard, +c2: Core, +t: Time) -> Out:
  match h:
    case L.Opened{}:
      Out{c2, Nil{}}
    case L.Message{+caps}:
      message.on(Model.classify(caps), core.phase(c2), c2, t, caps)
    case L.Garbled{}:
      Out{c2, [Log{"Music Assistant sent a message that isn't JSON"}]}
    case L.Pinged{p}:
      Out{c2, [PongMa{p}]}
    case L.Dropped{why}:
      finish(c2, "Music Assistant: " ++ why, True{})

# What Music Assistant's link heard (anything counts as hearing from it).
def ma(+c: Core, +t: Time, h: L.Heard) -> Out:
  ma.on(h, with.ma_heard(c, time.ms(t)), t)

# The clock
# ---------

# Whether the broker accepted us (and we haven't ended).
def broker.up(ph: Phase) -> Bool:
  match ph:
    case Connecting{}:
      False{}
    case Over{}:
      False{}
    case _:
      True{}

def is.live(ph: Phase) -> Bool:
  match ph:
    case Live{}:
      True{}
    case _:
      False{}

def is.over(ph: Phase) -> Bool:
  match ph:
    case Over{}:
      True{}
    case _:
      False{}

def since(+now: U32, +then: U32, +limit: U32) -> Bool:
  ((now - then : U32) >= limit : U32)

def expired.if(due: Bool, p: Pending, rest: Maybe<&2, Pending>) -> Maybe<&2, Pending>:
  match due:
    case True{}:
      Some{p}
    case False{}:
      rest

# A lookup that waited too long, if any.
def expired(ps: List<&2, Pending>, +now: U32) -> Maybe<&2, Pending>:
  match ps:
    case Nil{}:
      None{}
    case +p <> t:
      match p:
        case Pending{_, _, _, +since0}:
          expired.if(since(now, since0, lookup_wait()), p, expired(t, now))

def actions.then(o: Out, before: List<&2, Action>) -> Out:
  match o:
    case Out{c, a}:
      Out{c, List.append(&2, Action, before, a)}

def routine.ping(ping: Bool, +c: Core, +now: U32) -> Core:
  match ping:
    case True{}:
      with.mq_sent(c, now)
    case False{}:
      c

def routine.report(report: Bool, +c: Core, +now: U32) -> Core:
  match report:
    case True{}:
      with.report(c, now)
    case False{}:
      c

def routine.ping.acts(ping: Bool) -> List<&2, Action>:
  match ping:
    case True{}:
      [ToMq{M.PingReq{}}]
    case False{}:
      Nil{}

def routine.report.acts(report: Bool) -> List<&2, Action>:
  match report:
    case True{}:
      [Report{}]
    case False{}:
      Nil{}

# The pending plays split by whether their lookup waited too long.
type Split is Data:
  Split{due: List<&2, Pending>, kept: List<&2, Pending>}

def split.due(s: Split) -> List<&2, Pending>:
  match s:
    case Split{d, _}:
      d

def split.kept(s: Split) -> List<&2, Pending>:
  match s:
    case Split{_, k}:
      k

def split.if(due: Bool, p: Pending, +s: Split) -> Split:
  match due:
    case True{}:
      Split{p <> split.due(s), split.kept(s)}
    case False{}:
      Split{split.due(s), p <> split.kept(s)}

def split(ps: List<&2, Pending>, +now: U32) -> Split:
  match ps:
    case Nil{}:
      Split{Nil{}, Nil{}}
    case +p <> t:
      match p:
        case Pending{_, _, _, +since0}:
          split.if(since(now, since0, lookup_wait()), p, split(t, now))

# The id bytes a reply to this play's lookup carries.
def pending.idb(+p: Pending) -> B.Bytes:
  B.utf8(U32.show(pending.id(p)))

# The plays without any answering these plays' ids.
def drop.all(ds: List<&2, Pending>, +ps: List<&2, Pending>) -> List<&2, Pending>:
  match ds:
    case Nil{}:
      ps
    case +d <> t:
      drop.all(t, pending.drop(ps, pending.idb(d)))

# Each of these plays published, without ids, once.
def expire.dues(ds: List<&2, Pending>, +c: Core) -> Out:
  match ds:
    case Nil{}:
      Out{c, Nil{}}
    case +d <> t:
      +o = publish.play(core.book(c), c, d, no_ids())
      +rest = expire.dues(t, out.core(o))
      Out{out.core(rest), List.append(&2, Action, out.actions(o), out.actions(rest))}

# Every lookup that waited too long: its play published without ids, and out of the book (with
# any other answering its id), so a late answer finds nothing and nothing overdue is left.
def expire.book(b: Book, +c: Core, +now: U32) -> Out:
  match b:
    case Book{names, known, +pending, plays, held}:
      +sp = split(pending, now)
      expire.dues(split.due(sp),
        with.book(c, Book{names, known, drop.all(split.due(sp), split.kept(sp)), plays, held}))

def routine.expire(live: Bool, +c: Core, +now: U32) -> Out:
  match live:
    case True{}:
      expire.book(core.book(c), c, now)
    case False{}:
      Out{c, Nil{}}

def routine(+ping: Bool, +report: Bool, live: Bool, +c: Core, +now: U32) -> Out:
  +c1 = routine.ping(ping, c, now)
  +c2 = routine.report(report, c1, now)
  +before = List.append(&2, Action, routine.ping.acts(ping), routine.report.acts(report))
  actions.then(routine.expire(live, c2, now), before)

# The checks, in order: no answer to the login, a quiet broker, a quiet Music Assistant.
def tick.if(no_answer: Bool, broker_gone: Bool, ma_gone: Bool, ping: Bool, report: Bool,
    live: Bool, +c: Core, +now: U32) -> Out:
  match no_answer:
    case True{}:
      finish(c, "the broker didn't answer the login", False{})
    case False{}:
      match broker_gone:
        case True{}:
          finish(c, "the broker went quiet", False{})
        case False{}:
          match ma_gone:
            case True{}:
              finish(c, "Music Assistant went quiet", True{})
            case False{}:
              routine(ping, report, live, c, now)

def tick.on(k: Clock, +ph: Phase, +c: Core, +now: U32) -> Out:
  match k:
    case Clock{+mh, +ms, +mah, +rep}:
      +up = broker.up(ph)
      tick.if(Bool.and(Bool.not(up), Bool.and(since(now, mh, connect_wait()),
          Bool.not(is.over(ph)))),
        Bool.and(up, since(now, mh, broker_quiet())),
        Bool.and(up, since(now, mah, ma_quiet())),
        Bool.and(up, since(now, ms, ping_every())),
        Bool.and(is.live(ph), since(now, rep, report_every())), is.live(ph), c, now)

# The step
# --------

def has_mq(acts: List<&2, Action>) -> Bool:
  match acts:
    case Nil{}:
      False{}
    case a <> t:
      match a:
        case ToMq{_}:
          True{}
        case _:
          has_mq(t)

def sent.if(any: Bool, o: Out, +now: U32) -> Out:
  match any:
    case True{}:
      match o:
        case Out{c, a}:
          Out{with.mq_sent(c, now), a}
    case False{}:
      o

def sent(+o: Out, +now: U32) -> Out:
  sent.if(has_mq(out.actions(o)), o, now)

def event(+c: Core, +t: Time, ev: Input) -> Out:
  match ev:
    case MqPacket{p}:
      mq(with.mq_heard(c, time.ms(t)), t, p)
    case MqLost{}:
      finish(c, "lost the broker", False{})
    case MaHeard{h}:
      ma(c, t, h)
    case Tick{}:
      tick.on(core.clock(c), core.phase(c), c, time.ms(t))

def step.on(ph: Phase, +c: Core, +t: Time, ev: Input) -> Out:
  match ph:
    case Over{}:
      Out{c, Nil{}}
    case _:
      sent(event(c, t, ev), time.ms(t))

# The core after an event at time t, and what to do. An ended session does nothing more.
def step(+c: Core, +t: Time, ev: Input) -> Out:
  step.on(core.phase(c), c, t, ev)
