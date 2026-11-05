import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/ma/link.bend as L
import ../lib/bridge/conf.bend as C
import ../lib/bridge/topics.bend as T
import ../lib/bridge/core.bend as K
# Laws of the bridge's decisions (lib/bridge/core.bend).

def u(s: String) -> B.Bytes:
  B.utf8(s)

def conf() -> C.Conf:
  C.read.conf(C.parse(u("ma_token tok\nmqtt_host broker\nmqtt_user music\nmqtt_password pw\n")))

def t(+ms: U32) -> K.Time:
  K.Time{ms, (1793864368 + ms / 1000 : U32)}

def msg(s: String) -> K.Input:
  K.MaHeard{L.Message{Model.read(u(s))}}

def retained(r: Bool) -> String:
  match r:
    case True{}:
      " (r) "
    case False{}:
      " "

def show(a: K.Action) -> String:
  match a:
    case K.ToMq{p}:
      match p:
        case M.Publish{_, _, r, topic, _, payload}:
          "pub " ++ topic ++ retained(r) ++ B.from_utf8(payload)
        case M.Connect{client, _, _, _, _, _}:
          "connect " ++ client
        case M.PingReq{}:
          "pingreq"
        case M.Disconnect{}:
          "disconnect"
        case _:
          "mq?"
    case K.OpenMa{}:
      "open ma"
    case K.ToMa{+id, c}:
      "ma " ++ B.from_utf8(Api.encode(id, c))
    case K.PongMa{p}:
      "pong " ++ B.from_utf8(p)
    case K.Append{l}:
      "append " ++ B.from_utf8(l)
    case K.Report{}:
      "report"
    case K.Log{l}:
      "log " ++ l
    case K.Ended{w}:
      "ended " ++ w

def shows(acts: List<&2, K.Action>) -> String:
  match acts:
    case Nil{}:
      ""
    case a <> rest:
      show(a) ++ " | " ++ shows(rest)

type Ev is Data:
  Ev{at: K.Time, input: K.Input}

def run(steps: List<&2, Ev>, c: K.Core, acc: List<&2, String>) -> List<&2, String>:
  match steps:
    case Nil{}:
      List.reverse(&2, String, acc)
    case s <> rest:
      match s:
        case Ev{tm, ev}:
          +o = K.step(c, tm, ev)
          run(rest, K.out.core(o), shows(K.out.actions(o)) <> acc)


def session.on(o: K.Out) -> List<&2, String>:
  match o:
    case K.Out{c, acts}:
      shows(acts) <> run([
        Ev{t(100), K.MqPacket{M.ConnAck{False{}, 0}}},
        Ev{t(200), K.MaHeard{L.Opened{}}},
        Ev{t(300), msg("{\"server_id\": \"x\", \"server_version\": \"2.10.9\"}")},
        Ev{t(400), msg("{\"message_id\": \"1\", \"result\": {\"authenticated\": true}}")},
        Ev{t(500), msg("{\"message_id\": \"2\", \"result\": [{\"player_id\": \"P1\", \"name\": \"Living Room\", \"available\": true, \"playback_state\": \"playing\", \"current_media\": {\"uri\": \"library://track/1\", \"title\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"duration\": 200}, \"active_source\": \"P1\", \"synced_to\": null, \"volume_level\": 9}]}")},
        Ev{t(600), msg("{\"event\": \"player_updated\", \"object_id\": \"P1\", \"data\": {\"player_id\": \"P1\", \"name\": \"Living Room\", \"available\": true, \"playback_state\": \"playing\", \"current_media\": {\"uri\": \"library://track/1\", \"title\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"duration\": 200}, \"active_source\": \"P1\", \"synced_to\": null, \"volume_level\": 9}}")},
        Ev{t(700), msg("{\"event\": \"media_item_played\", \"object_id\": \"library://track/1\", \"data\": {\"uri\": \"library://track/1\", \"name\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"duration\": 200, \"seconds_played\": 120, \"fully_played\": false, \"is_playing\": true, \"player_id\": \"P1\"}}")},
        Ev{t(800), msg("{\"event\": \"media_item_played\", \"object_id\": \"library://track/1\", \"data\": {\"uri\": \"library://track/1\", \"name\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"duration\": 200, \"seconds_played\": 195, \"fully_played\": true, \"is_playing\": false, \"player_id\": \"P1\"}}")},
        Ev{t(900), msg("{\"message_id\": \"3\", \"result\": {\"external_ids\": [[\"isrc\", \"US0000000001\"]], \"provider_mappings\": [{\"provider_domain\": \"apple_music\", \"item_id\": \"111\"}]}}")},
        Ev{t(1000), K.MaHeard{L.Pinged{u("hi")}}},
        Ev{t(10600), K.Tick{}},
        Ev{t(31000), K.Tick{}},
        Ev{t(40000), K.MqLost{}},
        Ev{t(41000), K.Tick{}}], c, Nil{})


# A whole session, as the core decides it: log in to the broker; open Music Assistant once the
# broker accepts; log in on its hello; list the players once logged in; go live (online, every
# player's state); a repeated state publishes nothing, an in-progress play report does nothing,
# a final one looks its item up and the answer publishes the play (and appends it); a ping gets
# its pong; the first report 10 s after going live; a broker ping after 30 s of sending nothing;
# a lost broker ends the session, and nothing happens after the end.
law core_session:
  {session.on(K.start(conf(), t(0)))
    == ["connect music-assistant-mqtt | ",
     "open ma | ",
     "",
     "log Music Assistant 2.10.9 | ma {\"message_id\":\"1\",\"command\":\"au"
       ++ "th\",\"args\":{\"token\":\"tok\"}} | ",
     "ma {\"message_id\":\"2\",\"command\":\"players/all\",\"args\":{}} | ",
     "log live: 1 players | pub music/status (r) online | pub music/living_r"
       ++ "oom/state (r) {\"name\":\"Living Room\",\"state\":\"playing\",\"availa"
       ++ "ble\":true,\"source\":\"P1\",\"synced_to\":null,\"volume\":9,\"title\""
       ++ ":\"Song\",\"artist\":\"Band\",\"album\":\"LP\",\"uri\":\"library://tra"
       ++ "ck/1\",\"duration\":200} | ",
     "",
     "",
     "ma {\"message_id\":\"3\",\"command\":\"music/item_by_uri\",\"args\":{\""
       ++ "uri\":\"library://track/1\"}} | ",
     "pub music/played {\"at\":1793864368,\"player\":\"living_room\",\"playe"
       ++ "r_id\":\"P1\",\"uri\":\"library://track/1\",\"name\":\"Song\",\"artist"
       ++ "\":\"Band\",\"album\":\"LP\",\"duration\":200,\"seconds_played\":195,\""
       ++ "fully_played\":true,\"ids\":{\"apple_music\":\"111\",\"spotify\":null}"
       ++ ",\"isrc\":\"US0000000001\"} | append {\"at\":1793864368,\"player\":\"l"
       ++ "iving_room\",\"player_id\":\"P1\",\"uri\":\"library://track/1\",\"name"
       ++ "\":\"Song\",\"artist\":\"Band\",\"album\":\"LP\",\"duration\":200,\"se"
       ++ "conds_played\":195,\"fully_played\":true,\"ids\":{\"apple_music\":\"11"
       ++ "1\",\"spotify\":null},\"isrc\":\"US0000000001\"}\n | ",
     "pong hi | ",
     "report | ",
     "pingreq | ",
     "log lost the broker | ended lost the broker | ",
     ""]
    : List<&2, String>}

def live(conf: C.Conf, +n: U32, up: Bool, clock: K.Clock, book: K.Book) -> K.Core:
  K.Core{conf, K.Session{K.Live{}, n, up}, clock, book}

# For every core and input: an ended session does nothing and stays as it is.
law core_over_is_silent:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +book: K.Book
  for t: K.Time
  for ev: K.Input
  {K.step(K.Core{conf, K.Session{K.Over{}, n, up}, clock, book}, t, ev)
    == K.Out{K.Core{conf, K.Session{K.Over{}, n, up}, clock, book}, Nil{}} : K.Out}

# For every live core: Music Assistant's ping gets its pong, and nothing else.
law core_ping_answered:
  for conf: C.Conf
  for n: U32
  for up: Bool
  for clock: K.Clock
  for book: K.Book
  for t: K.Time
  for +p: B.Bytes
  {K.out.actions(K.step(live(conf, n, up, clock, book), t, K.MaHeard{L.Pinged{p}}))
    == [K.PongMa{p}] : List<&2, K.Action>}

# For every live core: a lost broker ends the session (nothing to say offline through).
law core_lost_broker_ends:
  for conf: C.Conf
  for n: U32
  for up: Bool
  for clock: K.Clock
  for book: K.Book
  for t: K.Time
  {K.out.actions(K.step(live(conf, n, up, clock, book), t, K.MqLost{}))
    == [K.Log{"lost the broker"}, K.Ended{"lost the broker"}] : List<&2, K.Action>}

# For every live core: a lost Music Assistant link says offline, disconnects and ends.
law core_lost_ma_says_offline:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +book: K.Book
  for t: K.Time
  for +why: String
  {K.out.actions(K.step(live(conf, n, up, clock, book), t, K.MaHeard{L.Lost{why}}))
    == [K.status(live(conf, n, up, clock, book), "offline"), K.ToMq{M.Disconnect{}},
        K.Log{"Music Assistant: " ++ why}, K.Ended{"Music Assistant: " ++ why}]
    : List<&2, K.Action>}

# The reconnect waits: 1 s after a session that went live; otherwise doubling, at most 60 s.
law backoff_ladder:
  {[K.backoff.wait(0n), K.backoff.wait(K.backoff.next(0n, False{})),
    K.backoff.wait(K.backoff.next(1n, False{})), K.backoff.wait(K.backoff.next(5n, False{})),
    K.backoff.wait(K.backoff.next(6n, False{})), K.backoff.wait(K.backoff.next(40n, False{})),
    K.backoff.wait(K.backoff.next(40n, True{}))]
    == [1000, 2000, 4000, 60000, 60000, 60000, 1000] : List<&2, U32>}

# For every step: a wait is between 1 and 60 s.
law backoff_bounded:
  for s: Nat
  {Bool.and((K.backoff.wait(s) >= 1000 : U32), (K.backoff.wait(s) <= 60000 : U32)) == True{}
    : Bool}

# Before going live
# ----------------

# Whether an action publishes anything but the offline status (a player's state, a play, a report).
def data.is(a: K.Action) -> Bool:
  match a:
    case K.ToMq{p}:
      match p:
        case M.Publish{_, _, _, _, _, payload}:
          Bool.not(B.beq(payload, B.utf8("offline")))
        case _:
          False{}
    case _:
      False{}

def data.in(as: List<&2, K.Action>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case a <> t:
      Bool.or(data.is(a), data.in(t))

def at(conf: C.Conf, ph: K.Phase, +n: U32, up: Bool, clock: K.Clock, book: K.Book) -> K.Core:
  K.Core{conf, K.Session{ph, n, up}, clock, book}

# For every core and input: until the broker accepted the login, Music Assistant said hello and
# took the token, nothing is published but the offline status (whatever either side sends).
law core_quiet_connecting:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +book: K.Book
  for +t: K.Time
  for +ev: K.Input
  {data.in(K.out.actions(K.step(at(conf, K.Connecting{}, n, up, clock, book), t, ev))) == False{}
    : Bool}

law core_quiet_opening:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +book: K.Book
  for +t: K.Time
  for +ev: K.Input
  {data.in(K.out.actions(K.step(at(conf, K.Opening{}, n, up, clock, book), t, ev))) == False{}
    : Bool}

law core_quiet_logging_in:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +book: K.Book
  for +t: K.Time
  for +ev: K.Input
  {data.in(K.out.actions(K.step(at(conf, K.LoggingIn{}, n, up, clock, book), t, ev))) == False{}
    : Bool}

# Plays: each final report is published once
# -------------------------------------------
# A play is the only publish that isn't retained. A final report goes pending with one lookup; the
# lookup's answer (or refusal, or its expiry) publishes it once and takes it out of the book, so a
# second answer, or a late one after the expiry, finds nothing.

def played.is(a: K.Action) -> Bool:
  match a:
    case K.ToMq{p}:
      match p:
        case M.Publish{_, _, retain, _, _, _}:
          Bool.not(retain)
        case _:
          False{}
    case _:
      False{}

def played.add(one: Bool, n: Nat) -> Nat:
  match one:
    case True{}:
      1n+n
    case False{}:
      n

# How many plays the actions publish.
def played.count(as: List<&2, K.Action>) -> Nat:
  match as:
    case Nil{}:
      0n
    case a <> t:
      played.add(played.is(a), played.count(t))

def live.at(conf: C.Conf, +n: U32, up: Bool, clock: K.Clock, names: T.Names,
    known: List<&2, K.Known>, pending: List<&2, K.Pending>, +plays: U32) -> K.Core:
  K.Core{conf, K.Session{K.Live{}, n, up}, clock, K.Book{names, known, pending, plays}}

# For every pending list and id: once the plays answering an id are dropped, none answers it.
law plays_gone_once_answered:
  for +ps: List<&2, K.Pending>
  for +id: B.Bytes
  {K.pending.find(K.pending.drop(ps, id), id, K.pending.head(K.pending.drop(ps, id), id))
    == None{} : Maybe<&2, K.Pending>}

# For every book and answer: at most one play is published.
law plays_answer_publishes_at_most_one:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +names: T.Names
  for +known: List<&2, K.Known>
  for +pending: List<&2, K.Pending>
  for +plays: U32
  for +id: B.Bytes
  for ids: Model.Ids
  {Nat.is_lt(played.count(K.out.actions(
      K.answered(live.at(conf, n, up, clock, names, known, pending, plays), id, ids))), 2n)
    == True{} : Bool}

# For every book and id: a second answer under the same id publishes nothing.
law plays_answered_twice_is_silent:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +names: T.Names
  for +known: List<&2, K.Known>
  for +pending: List<&2, K.Pending>
  for +plays: U32
  for +id: B.Bytes
  for ids1: Model.Ids
  for ids2: Model.Ids
  {K.out.actions(K.answered(K.out.core(
      K.answered(live.at(conf, n, up, clock, names, known, pending, plays), id, ids1)), id, ids2))
    == Nil{} : List<&2, K.Action>}

# For every book and time: an expiry publishes at most one play.
law plays_expiry_publishes_at_most_one:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +names: T.Names
  for +known: List<&2, K.Known>
  for +pending: List<&2, K.Pending>
  for +plays: U32
  for +now: U32
  {Nat.is_lt(played.count(K.out.actions(K.routine.expire(True{},
      live.at(conf, n, up, clock, names, known, pending, plays), now))), 2n) == True{} : Bool}

# The answer that comes after its play expired (its own id bytes): nothing, when one expired.
def late.on(m: Maybe<&2, K.Pending>, +c: K.Core, ids: Model.Ids) -> List<&2, K.Action>:
  match m:
    case None{}:
      Nil{}
    case Some{+pd}:
      K.out.actions(K.answered(K.out.core(K.expire.on(Some{pd}, c)),
        B.utf8(U32.show(K.pending.id(pd))), ids))

law plays_late_answer_is_silent:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +names: T.Names
  for +known: List<&2, K.Known>
  for +pending: List<&2, K.Pending>
  for +plays: U32
  for +now: U32
  for ids: Model.Ids
  {late.on(K.expired(pending, now), live.at(conf, n, up, clock, names, known, pending, plays), ids)
    == Nil{} : List<&2, K.Action>}

# For every live core and final report: it goes pending under the next id, with one lookup.
law plays_final_report_goes_pending:
  for +conf: C.Conf
  for +n: U32
  for +up: Bool
  for +clock: K.Clock
  for +names: T.Names
  for +known: List<&2, K.Known>
  for +pending: List<&2, K.Pending>
  for +plays: U32
  for +ms: U32
  for +unix: U32
  for +item: Model.Media
  for +secs: U32
  for +fully: Bool
  for +player: B.Bytes
  {K.played(live.at(conf, n, up, clock, names, known, pending, plays), K.Time{ms, unix},
      Model.Play{item, secs, fully, True{}, player})
    == K.Out{live.at(conf, (n + 1 : U32), up, clock, names, known,
          K.Pending{n, Model.Play{item, secs, fully, True{}, player}, unix, ms} <> pending, plays),
        [K.ToMa{n, Api.Lookup{K.play.uri(Model.Play{item, secs, fully, True{}, player})}}]}
    : K.Out}

# For every core and report still playing: nothing.
law plays_progress_report_does_nothing:
  for +c: K.Core
  for t: K.Time
  for item: Model.Media
  for secs: U32
  for fully: Bool
  for player: B.Bytes
  {K.played(c, t, Model.Play{item, secs, fully, False{}, player}) == K.Out{c, Nil{}} : K.Out}
