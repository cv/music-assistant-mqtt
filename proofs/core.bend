import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/ma/link.bend as L
import ../lib/bridge/conf.bend as C
import ../lib/bridge/topics.bend as T
import ../lib/bridge/core.bend as K
import ../laws/core.bend as Lk
# Proofs of laws/core.bend: the session computes; the others compute once the phase is known
# (the step looks at the phase first, then the input); the backoff by cases on the step.

def Lk.core_session():
  {==}

def Lk.core_over_is_silent(conf, n, up, clock, book, t, ev):
  {==}

def Lk.core_ping_answered(conf, n, up, clock, book, t, p):
  {==}

def Lk.core_lost_broker_ends(conf, n, up, clock, book, t):
  {==}

def Lk.core_lost_ma_says_offline(conf, n, up, clock, book, t, why):
  match clock:
    case K.Clock{a, b, c, d}:
      {==}

def Lk.backoff_ladder():
  {==}

def Lk.backoff_bounded(s):
  match s:
    case 0n:
      {==}
    case 1n+a:
      match a:
        case 0n:
          {==}
        case 1n+b:
          match b:
            case 0n:
              {==}
            case 1n+c:
              match c:
                case 0n:
                  {==}
                case 1n+d:
                  match d:
                    case 0n:
                      {==}
                    case 1n+e:
                      match e:
                        case 0n:
                          {==}
                        case 1n+_:
                          {==}

# Before going live
# ----------------
# The step only adds the send time to its output, so the actions are the event's. Each input is
# then a case: the broker's answer only opens Music Assistant's link (or ends); a message, of any
# kind, either logs in, asks for the players, or ends (offline); the clock, not being live, only
# pings or ends. Events are ignored before the player list is asked for.

def sent_keeps.if(b: Bool, c: K.Core, +a: List<&2, K.Action>, +now: U32)
    -> {K.out.actions(K.sent.if(b, K.Out{c, a}, now)) == a : List<&2, K.Action>}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def sent_keeps(o: K.Out, +now: U32)
    -> {K.out.actions(K.sent(o, now)) == K.out.actions(o) : List<&2, K.Action>}:
  match o:
    case K.Out{c, +a}:
      sent_keeps.if(K.has_mq(a), c, a, now)

# The broker's answer, for any phase.
def connack_quiet(ok: Bool, ph: K.Phase, +code: U32, +c: K.Core, +t: K.Time)
    -> {Lk.data.in(K.out.actions(K.connack.on(ok, ph, code, c, t))) == False{} : Bool}:
  match ok:
    case False{}:
      {==}
    case True{}:
      match ph:
        case K.Connecting{}:
          match t:
            case K.Time{ms, u}:
              {==}
        case K.Opening{}:
          {==}
        case K.LoggingIn{}:
          {==}
        case K.Listing{}:
          {==}
        case K.Live{}:
          {==}
        case K.Over{}:
          {==}

def mq_quiet(+c: K.Core, +t: K.Time, p: M.Packet)
    -> {Lk.data.in(K.out.actions(K.mq(c, t, p))) == False{} : Bool}:
  match p:
    case M.Connect{a, b, cc, d, e, f}:
      {==}
    case M.ConnAck{pr, +code}:
      connack_quiet(U32.is_eq(code, 0), K.core.phase(c), code, c, t)
    case M.Publish{a, b, cc, d, e, f}:
      {==}
    case M.PubAck{a}:
      {==}
    case M.Subscribe{a, b}:
      {==}
    case M.SubAck{a, b}:
      {==}
    case M.PingReq{}:
      {==}
    case M.PingResp{}:
      {==}
    case M.Disconnect{}:
      {==}

# The login's answer: on to the player list, or the end.
def login_quiet(mine: Bool, ok: Bool, +c: K.Core)
    -> {Lk.data.in(K.out.actions(K.reply.login(mine, ok, c))) == False{} : Bool}:
  match mine:
    case False{}:
      {==}
    case True{}:
      match ok:
        case True{}:
          {==}
        case False{}:
          {==}

# Any message, in each early phase.
def msg_quiet_connecting(m: Model.Msg, +c: K.Core, +t: K.Time, +caps: Model.Caps)
    -> {Lk.data.in(K.out.actions(K.message.on(m, K.Connecting{}, c, t, caps))) == False{} : Bool}:
  match m:
    case Model.Hello{v}:
      {==}
    case Model.Reply{id}:
      {==}
    case Model.Refused{id, code, d}:
      {==}
    case Model.Happened{ev, o}:
      {==}
    case Model.Unknown{}:
      {==}

def msg_quiet_opening(m: Model.Msg, +c: K.Core, +t: K.Time, +caps: Model.Caps)
    -> {Lk.data.in(K.out.actions(K.message.on(m, K.Opening{}, c, t, caps))) == False{} : Bool}:
  match m:
    case Model.Hello{v}:
      {==}
    case Model.Reply{id}:
      {==}
    case Model.Refused{id, code, d}:
      {==}
    case Model.Happened{ev, o}:
      {==}
    case Model.Unknown{}:
      {==}

def msg_quiet_logging_in(m: Model.Msg, +c: K.Core, +t: K.Time, +caps: Model.Caps)
    -> {Lk.data.in(K.out.actions(K.message.on(m, K.LoggingIn{}, c, t, caps))) == False{} : Bool}:
  match m:
    case Model.Hello{v}:
      {==}
    case Model.Reply{+id}:
      login_quiet(K.is.text(id, "1"), Model.logged_in(caps), c)
    case Model.Refused{id, code, d}:
      {==}
    case Model.Happened{ev, o}:
      {==}
    case Model.Unknown{}:
      {==}

# The clock while not live: an end, or at most a ping and a report request.
def tick_quiet(b1: Bool, b2: Bool, b3: Bool, b4: Bool, b5: Bool, +c: K.Core, +now: U32)
    -> {Lk.data.in(K.out.actions(K.tick.if(b1, b2, b3, b4, b5, False{}, c, now))) == False{}
        : Bool}:
  match b1:
    case True{}:
      {==}
    case False{}:
      match b2:
        case True{}:
          {==}
        case False{}:
          match b3:
            case True{}:
              {==}
            case False{}:
              match b4:
                case True{}:
                  match b5:
                    case True{}:
                      {==}
                    case False{}:
                      {==}
                case False{}:
                  match b5:
                    case True{}:
                      {==}
                    case False{}:
                      {==}

# Every input in Connecting.
def event_quiet_connecting(+conf: C.Conf, +n: U32, +up: Bool, +a: U32, +b: U32, +cc: U32, +d: U32,
    +book: K.Book, +ms: U32, +u: U32, ev: K.Input)
    -> {Lk.data.in(K.out.actions(K.event(Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book),
        K.Time{ms, u}, ev))) == False{} : Bool}:
  match ev:
    case K.MqPacket{p}:
      mq_quiet(K.with.mq_heard(Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book), ms),
        K.Time{ms, u}, p)
    case K.MqLost{}:
      {==}
    case K.MaHeard{h}:
      match h:
        case L.Opened{}:
          {==}
        case L.Message{+caps}:
          msg_quiet_connecting(Model.classify(caps),
            K.with.ma_heard(Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book), ms),
            K.Time{ms, u}, caps)
        case L.Garbled{}:
          {==}
        case L.Pinged{x}:
          {==}
        case L.Lost{w}:
          {==}
    case K.Tick{}:
      tick_quiet(
        Bool.and(Bool.not(K.broker.up(K.Connecting{})),
          Bool.and(K.since(ms, a, K.connect_wait()), Bool.not(K.is.over(K.Connecting{})))),
        Bool.and(K.broker.up(K.Connecting{}), K.since(ms, a, K.broker_quiet())),
        Bool.and(K.broker.up(K.Connecting{}), K.since(ms, cc, K.ma_quiet())),
        Bool.and(K.broker.up(K.Connecting{}), K.since(ms, b, K.ping_every())),
        Bool.and(K.is.live(K.Connecting{}), K.since(ms, d, K.report_every())),
        Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book), ms)

def Lk.core_quiet_connecting(conf, n, up, clock, book, t, ev):
  match clock:
    case K.Clock{+a, +b, +cc, +d}:
      match t:
        case K.Time{+ms, +u}:
          %Equal.sym(List<&2, K.Action>,
              K.out.actions(K.sent(K.event(Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev), ms)),
              K.out.actions(K.event(Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev)),
              sent_keeps(K.event(Lk.at(conf, K.Connecting{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev), ms)) :
            {Lk.data.in(_) == False{} : Bool}
          event_quiet_connecting(conf, n, up, a, b, cc, d, book, ms, u, ev)

# Every input in Opening.
def event_quiet_opening(+conf: C.Conf, +n: U32, +up: Bool, +a: U32, +b: U32, +cc: U32, +d: U32,
    +book: K.Book, +ms: U32, +u: U32, ev: K.Input)
    -> {Lk.data.in(K.out.actions(K.event(Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book),
        K.Time{ms, u}, ev))) == False{} : Bool}:
  match ev:
    case K.MqPacket{p}:
      mq_quiet(K.with.mq_heard(Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book), ms),
        K.Time{ms, u}, p)
    case K.MqLost{}:
      {==}
    case K.MaHeard{h}:
      match h:
        case L.Opened{}:
          {==}
        case L.Message{+caps}:
          msg_quiet_opening(Model.classify(caps),
            K.with.ma_heard(Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book), ms),
            K.Time{ms, u}, caps)
        case L.Garbled{}:
          {==}
        case L.Pinged{x}:
          {==}
        case L.Lost{w}:
          {==}
    case K.Tick{}:
      tick_quiet(
        Bool.and(Bool.not(K.broker.up(K.Opening{})),
          Bool.and(K.since(ms, a, K.connect_wait()), Bool.not(K.is.over(K.Opening{})))),
        Bool.and(K.broker.up(K.Opening{}), K.since(ms, a, K.broker_quiet())),
        Bool.and(K.broker.up(K.Opening{}), K.since(ms, cc, K.ma_quiet())),
        Bool.and(K.broker.up(K.Opening{}), K.since(ms, b, K.ping_every())),
        Bool.and(K.is.live(K.Opening{}), K.since(ms, d, K.report_every())),
        Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book), ms)

def Lk.core_quiet_opening(conf, n, up, clock, book, t, ev):
  match clock:
    case K.Clock{+a, +b, +cc, +d}:
      match t:
        case K.Time{+ms, +u}:
          %Equal.sym(List<&2, K.Action>,
              K.out.actions(K.sent(K.event(Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev), ms)),
              K.out.actions(K.event(Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev)),
              sent_keeps(K.event(Lk.at(conf, K.Opening{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev), ms)) :
            {Lk.data.in(_) == False{} : Bool}
          event_quiet_opening(conf, n, up, a, b, cc, d, book, ms, u, ev)

# Every input in LoggingIn.
def event_quiet_logging_in(+conf: C.Conf, +n: U32, +up: Bool, +a: U32, +b: U32, +cc: U32, +d: U32,
    +book: K.Book, +ms: U32, +u: U32, ev: K.Input)
    -> {Lk.data.in(K.out.actions(K.event(Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book),
        K.Time{ms, u}, ev))) == False{} : Bool}:
  match ev:
    case K.MqPacket{p}:
      mq_quiet(K.with.mq_heard(Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book), ms),
        K.Time{ms, u}, p)
    case K.MqLost{}:
      {==}
    case K.MaHeard{h}:
      match h:
        case L.Opened{}:
          {==}
        case L.Message{+caps}:
          msg_quiet_logging_in(Model.classify(caps),
            K.with.ma_heard(Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book), ms),
            K.Time{ms, u}, caps)
        case L.Garbled{}:
          {==}
        case L.Pinged{x}:
          {==}
        case L.Lost{w}:
          {==}
    case K.Tick{}:
      tick_quiet(
        Bool.and(Bool.not(K.broker.up(K.LoggingIn{})),
          Bool.and(K.since(ms, a, K.connect_wait()), Bool.not(K.is.over(K.LoggingIn{})))),
        Bool.and(K.broker.up(K.LoggingIn{}), K.since(ms, a, K.broker_quiet())),
        Bool.and(K.broker.up(K.LoggingIn{}), K.since(ms, cc, K.ma_quiet())),
        Bool.and(K.broker.up(K.LoggingIn{}), K.since(ms, b, K.ping_every())),
        Bool.and(K.is.live(K.LoggingIn{}), K.since(ms, d, K.report_every())),
        Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book), ms)

def Lk.core_quiet_logging_in(conf, n, up, clock, book, t, ev):
  match clock:
    case K.Clock{+a, +b, +cc, +d}:
      match t:
        case K.Time{+ms, +u}:
          %Equal.sym(List<&2, K.Action>,
              K.out.actions(K.sent(K.event(Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev), ms)),
              K.out.actions(K.event(Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev)),
              sent_keeps(K.event(Lk.at(conf, K.LoggingIn{}, n, up, K.Clock{a, b, cc, d}, book),
                K.Time{ms, u}, ev), ms)) :
            {Lk.data.in(_) == False{} : Bool}
          event_quiet_logging_in(conf, n, up, a, b, cc, d, book, ms, u, ev)

# Plays: each final report is published once
# -------------------------------------------
# gone: by induction on the pending list (an answering play is dropped; past one that doesn't,
# the lookup moves on). One play's actions hold one publish that isn't retained, whatever the
# plays file. A second answer, or a late one, looks in the dropped list: gone again.

def gone.if(b: Bool, +p: K.Pending, +t: List<&2, K.Pending>, +id: B.Bytes,
    h: {K.pending.answers(p, id) == b : Bool},
    +ih: {K.pending.find(K.pending.drop(t, id), id, K.pending.head(K.pending.drop(t, id), id))
      == None{} : Maybe<&2, K.Pending>})
    -> {K.pending.find(K.pending.drop.if(b, p, K.pending.drop(t, id)), id,
          K.pending.head(K.pending.drop.if(b, p, K.pending.drop(t, id)), id))
        == None{} : Maybe<&2, K.Pending>}:
  match b:
    case True{}:
      ih
    case False{}:
      %Equal.sym(Bool, K.pending.answers(p, id), False{}, h) :
        {K.pending.find(p <> K.pending.drop(t, id), id, _) == None{} : Maybe<&2, K.Pending>}
      ih

def Lk.plays_gone_once_answered(ps, id):
  match ps:
    case Nil{}:
      {==}
    case +p <> +t:
      gone.if(K.pending.answers(p, id), p, t, id, {==}, Lk.plays_gone_once_answered(t, id))

def app_zero(b: Bool, +line: B.Bytes) -> {Lk.played.count(K.append.if(b, line)) == 0n : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def acts_one(+names: T.Names, +c: K.Core, pd: K.Pending, ids: Model.Ids)
    -> {Lk.played.count(K.publish.play.acts(names, c, pd, ids)) == 1n : Nat}:
  match pd:
    case K.Pending{i, +play, +unix, since0}:
      %Equal.sym(Nat,
          Lk.played.count(K.append.if(Bool.not(C.blank(C.out.plays(C.conf.out(K.core.conf(c))))),
            T.played(unix, K.level.on(T.level.of(names, K.play.player(play)), K.play.player(play)),
              play, ids))), 0n,
          app_zero(Bool.not(C.blank(C.out.plays(C.conf.out(K.core.conf(c))))),
            T.played(unix, K.level.on(T.level.of(names, K.play.player(play)), K.play.player(play)),
              play, ids))) :
        {Lk.played.add(True{}, _) == 1n : Nat}
      {==}

def answer_one.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32,
    +id: B.Bytes, ids: Model.Ids)
    -> {Nat.is_lt(Lk.played.count(K.out.actions(K.answered.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays), id, ids))), 2n)
        == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{pd}:
      %Equal.sym(Nat, Lk.played.count(K.publish.play.acts(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays), pd, ids)), 1n,
          acts_one(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays), pd, ids)) :
        {Nat.is_lt(_, 2n) == True{} : Bool}
      {==}

def Lk.plays_answer_publishes_at_most_one(conf, n, up, clock, names, known, pending, plays, id, ids):
  answer_one.on(K.pending.find(pending, id, K.pending.head(pending, id)), conf, n, up, clock, names,
    known, pending, plays, id, ids)

def twice.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32,
    +id: B.Bytes, ids1: Model.Ids, ids2: Model.Ids,
    +h: {K.pending.find(pending, id, K.pending.head(pending, id)) == m : Maybe<&2, K.Pending>})
    -> {K.out.actions(K.answered(K.out.core(K.answered.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays), id, ids1)), id, ids2))
        == Nil{} : List<&2, K.Action>}:
  match m:
    case None{}:
      %Equal.sym(Maybe<&2, K.Pending>, K.pending.find(pending, id, K.pending.head(pending, id)),
          None{}, h) :
        {K.out.actions(K.answered.on(_, Lk.live.at(conf, n, up, clock, names, known, pending, plays), id, ids2)) == Nil{} : List<&2, K.Action>}
      {==}
    case Some{pd}:
      %Equal.sym(Maybe<&2, K.Pending>,
          K.pending.find(K.pending.drop(pending, id), id,
            K.pending.head(K.pending.drop(pending, id), id)), None{},
          Lk.plays_gone_once_answered(pending, id)) :
        {K.out.actions(K.answered.on(_, Lk.live.at(conf, n, up, clock, names, known,
          K.pending.drop(pending, id), (plays + 1 : U32)), id, ids2)) == Nil{} : List<&2, K.Action>}
      {==}

def Lk.plays_answered_twice_is_silent(conf, n, up, clock, names, known, pending, plays, id, ids1,
    ids2):
  twice.on(K.pending.find(pending, id, K.pending.head(pending, id)), conf, n, up, clock, names,
    known, pending, plays, id, ids1, ids2, {==})

def expire_one.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32)
    -> {Nat.is_lt(Lk.played.count(K.out.actions(K.expire.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays)))), 2n) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{+pd}:
      %Equal.sym(Nat, Lk.played.count(K.publish.play.acts(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays), pd, K.no_ids())), 1n,
          acts_one(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays), pd, K.no_ids())) :
        {Nat.is_lt(_, 2n) == True{} : Bool}
      {==}

def Lk.plays_expiry_publishes_at_most_one(conf, n, up, clock, names, known, pending, plays, now):
  expire_one.on(K.expired(pending, now), conf, n, up, clock, names, known, pending, plays)

def late_ok.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32,
    ids: Model.Ids)
    -> {Lk.late.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays), ids) == Nil{} : List<&2, K.Action>}:
  match m:
    case None{}:
      {==}
    case Some{+pd}:
      %Equal.sym(Maybe<&2, K.Pending>,
          K.pending.find(K.pending.drop(pending, B.utf8(U32.show(K.pending.id(pd)))),
            B.utf8(U32.show(K.pending.id(pd))),
            K.pending.head(K.pending.drop(pending, B.utf8(U32.show(K.pending.id(pd)))),
              B.utf8(U32.show(K.pending.id(pd))))), None{},
          Lk.plays_gone_once_answered(pending, B.utf8(U32.show(K.pending.id(pd))))) :
        {K.out.actions(K.answered.on(_, Lk.live.at(conf, n, up, clock, names, known,
          K.pending.drop(pending, B.utf8(U32.show(K.pending.id(pd)))), (plays + 1 : U32)),
          B.utf8(U32.show(K.pending.id(pd))), ids)) == Nil{} : List<&2, K.Action>}
      {==}

def Lk.plays_late_answer_is_silent(conf, n, up, clock, names, known, pending, plays, now, ids):
  late_ok.on(K.expired(pending, now), conf, n, up, clock, names, known, pending, plays, ids)

def Lk.plays_final_report_goes_pending(conf, n, up, clock, names, known, pending, plays, ms, unix,
    item, secs, fully, player):
  {==}

def Lk.plays_progress_report_does_nothing(c, t, item, secs, fully, player):
  {==}
