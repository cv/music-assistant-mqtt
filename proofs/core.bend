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
import ./common.bend as Pc
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
    +held: List<&2, K.Pending>,
    +id: B.Bytes, ids: Model.Ids)
    -> {Nat.is_lt(Lk.played.count(K.out.actions(K.answered.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), id, ids))), 2n)
        == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{pd}:
      %Equal.sym(Nat, Lk.played.count(K.publish.play.acts(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), pd, ids)), 1n,
          acts_one(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), pd, ids)) :
        {Nat.is_lt(_, 2n) == True{} : Bool}
      {==}

def Lk.plays_answer_publishes_at_most_one(conf, n, up, clock, names, known, pending, plays, held, id, ids):
  answer_one.on(K.pending.find(pending, id, K.pending.head(pending, id)), conf, n, up, clock, names,
    known, pending, plays, held, id, ids)

def twice.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32,
    +held: List<&2, K.Pending>,
    +id: B.Bytes, ids1: Model.Ids, ids2: Model.Ids,
    +h: {K.pending.find(pending, id, K.pending.head(pending, id)) == m : Maybe<&2, K.Pending>})
    -> {K.out.actions(K.answered(K.out.core(K.answered.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), id, ids1)), id, ids2))
        == Nil{} : List<&2, K.Action>}:
  match m:
    case None{}:
      %Equal.sym(Maybe<&2, K.Pending>, K.pending.find(pending, id, K.pending.head(pending, id)),
          None{}, h) :
        {K.out.actions(K.answered.on(_, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), id, ids2)) == Nil{} : List<&2, K.Action>}
      {==}
    case Some{pd}:
      %Equal.sym(Maybe<&2, K.Pending>,
          K.pending.find(K.pending.drop(pending, id), id,
            K.pending.head(K.pending.drop(pending, id), id)), None{},
          Lk.plays_gone_once_answered(pending, id)) :
        {K.out.actions(K.answered.on(_, Lk.live.at(conf, n, up, clock, names, known,
          K.pending.drop(pending, id), (plays + 1 : U32), held), id, ids2)) == Nil{} : List<&2, K.Action>}
      {==}

def Lk.plays_answered_twice_is_silent(conf, n, up, clock, names, known, pending, plays, held, id, ids1,
    ids2):
  twice.on(K.pending.find(pending, id, K.pending.head(pending, id)), conf, n, up, clock, names,
    known, pending, plays, held, id, ids1, ids2, {==})

def expire_one.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32,
    +held: List<&2, K.Pending>)
    -> {Nat.is_lt(Lk.played.count(K.out.actions(K.expire.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held)))), 2n) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{+pd}:
      %Equal.sym(Nat, Lk.played.count(K.publish.play.acts(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), pd, K.no_ids())), 1n,
          acts_one(names, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), pd, K.no_ids())) :
        {Nat.is_lt(_, 2n) == True{} : Bool}
      {==}

def Lk.plays_expiry_publishes_at_most_one(conf, n, up, clock, names, known, pending, plays, held, now):
  expire_one.on(K.expired(pending, now), conf, n, up, clock, names, known, pending, plays, held)

def late_ok.on(m: Maybe<&2, K.Pending>, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock,
    +names: T.Names, +known: List<&2, K.Known>, +pending: List<&2, K.Pending>, +plays: U32,
    +held: List<&2, K.Pending>,
    ids: Model.Ids)
    -> {Lk.late.on(m, Lk.live.at(conf, n, up, clock, names, known, pending, plays, held), ids) == Nil{} : List<&2, K.Action>}:
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
          K.pending.drop(pending, B.utf8(U32.show(K.pending.id(pd)))), (plays + 1 : U32), held),
          B.utf8(U32.show(K.pending.id(pd))), ids)) == Nil{} : List<&2, K.Action>}
      {==}

def Lk.plays_late_answer_is_silent(conf, n, up, clock, names, known, pending, plays, held, now, ids):
  late_ok.on(K.expired(pending, now), conf, n, up, clock, names, known, pending, plays, held, ids)

def Lk.plays_final_report_goes_pending(conf, n, up, clock, names, known, pending, plays, held, ms, unix,
    item, secs, fully, player):
  {==}

def Lk.plays_progress_report_does_nothing(c, t, item, secs, fully, player):
  {==}

# No play from nowhere
# --------------------
# A player's state is retained, so it isn't a play; a final report only asks for a lookup; with
# no play pending an answer finds nothing and nothing can expire.

def app_none(xs: List<&2, K.Action>, +ys: List<&2, K.Action>,
    +hx: {Lk.played.any(xs) == False{} : Bool}, +hy: {Lk.played.any(ys) == False{} : Bool})
    -> {Lk.played.any(List.append(&2, K.Action, xs, ys)) == False{} : Bool}:
  match xs:
    case Nil{}:
      hy
    case +x <> +t:
      %Equal.sym(Bool, Lk.played.is(x), False{}, Pc.or_false_l(Lk.played.is(x), Lk.played.any(t), hx)) :
        {Bool.or(_, Lk.played.any(List.append(&2, K.Action, t, ys))) == False{} : Bool}
      app_none(t, ys, Pc.or_false_r(Lk.played.is(x), Lk.played.any(t), hx), hy)

def if_new_none(same: Bool, b: K.Book, +c: K.Core, +id: B.Bytes, +level: B.Bytes, +state: B.Bytes)
    -> {Lk.played.any(K.out.actions(K.publish.if_new(same, b, c, id, level, state))) == False{}
        : Bool}:
  match same:
    case True{}:
      {==}
    case False{}:
      match b:
        case K.Book{w, x, y, z, h}:
          {==}

def pl_none(b: K.Book, +c: K.Core, +id: B.Bytes, +p: Model.Player)
    -> {Lk.played.any(K.out.actions(K.publish.learned(b, c, id, p))) == False{} : Bool}:
  match b:
    case K.Book{+names, +known, +pending, +plays, +held}:
      if_new_none(Bool.or(List.is_empty(&2, U32,
            K.level.on(T.level.of(T.learn(names, id, K.player.name(p)), id), id)),
          K.known.same(known, id, T.state(p))),
        K.Book{T.learn(names, id, K.player.name(p)), known, pending, plays, held}, c, id,
        K.level.on(T.level.of(T.learn(names, id, K.player.name(p)), id), id), T.state(p))

def pp_none(ps: List<&2, Model.Player>, +c: K.Core)
    -> {Lk.played.any(K.out.actions(K.players.publish(ps, c))) == False{} : Bool}:
  match ps:
    case Nil{}:
      {==}
    case +p <> +t:
      app_none(K.out.actions(K.publish.player(c, p)),
        K.out.actions(K.players.publish(t, K.out.core(K.publish.player(c, p)))),
        pl_none(K.core.book(c), c, K.player.id(p), p),
        pp_none(t, K.out.core(K.publish.player(c, p))))

def relook_add_none(b: K.Book, +c: K.Core, +play: Model.Play, +unix: U32, +ms: U32)
    -> {Lk.played.any(K.out.actions(K.relook.add(b, c, play, unix, ms))) == False{} : Bool}:
  match b:
    case K.Book{w, x, y, z, h}:
      {==}

def relook_one_none(h: K.Pending, +c: K.Core, +ms: U32)
    -> {Lk.played.any(K.out.actions(K.relook.one(h, c, ms))) == False{} : Bool}:
  match h:
    case K.Pending{i, +play, +unix, s}:
      relook_add_none(K.core.book(c), c, play, unix, ms)

# Carried plays are only looked up again: no play.
def relook_none(hs: List<&2, K.Pending>, +c: K.Core, +ms: U32)
    -> {Lk.played.any(K.out.actions(K.relook(hs, c, ms))) == False{} : Bool}:
  match hs:
    case Nil{}:
      {==}
    case +h <> +t:
      app_none(K.out.actions(K.relook.one(h, c, ms)),
        K.out.actions(K.relook(t, K.out.core(K.relook.one(h, c, ms)), ms)),
        relook_one_none(h, c, ms), relook_none(t, K.out.core(K.relook.one(h, c, ms)), ms))

def live_none(+c: K.Core, +t: K.Time, +ps: List<&2, Model.Player>)
    -> {Lk.played.any(K.out.actions(K.live(c, t, ps))) == False{} : Bool}:
  app_none(K.out.actions(K.players.publish(ps, K.with.up(K.with.phase(c, K.Live{})))),
    K.out.actions(K.relook(
      K.book.held(K.core.book(K.out.core(K.players.publish(ps, K.with.up(K.with.phase(c,
        K.Live{})))))),
      K.with.held(K.out.core(K.players.publish(ps, K.with.up(K.with.phase(c, K.Live{})))), Nil{}),
      K.time.ms(t))),
    pp_none(ps, K.with.up(K.with.phase(c, K.Live{}))),
    relook_none(
      K.book.held(K.core.book(K.out.core(K.players.publish(ps, K.with.up(K.with.phase(c,
        K.Live{})))))),
      K.with.held(K.out.core(K.players.publish(ps, K.with.up(K.with.phase(c, K.Live{})))), Nil{}),
      K.time.ms(t)))

def connack_none(ok: Bool, ph: K.Phase, +code: U32, +c: K.Core, +t: K.Time)
    -> {Lk.played.any(K.out.actions(K.connack.on(ok, ph, code, c, t))) == False{} : Bool}:
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

def mq_none(+c: K.Core, +t: K.Time, p: M.Packet)
    -> {Lk.played.any(K.out.actions(K.mq(c, t, p))) == False{} : Bool}:
  match p:
    case M.Connect{a, b, cc, d, e, f}:
      {==}
    case M.ConnAck{pr, +code}:
      connack_none(U32.is_eq(code, 0), K.core.phase(c), code, c, t)
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

def played_none(final: Bool, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock, +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +ph: K.Phase, +ms: U32, +u: U32, +p: Model.Play)
    -> {Lk.played.any(K.out.actions(K.played.if(final, Lk.idle.at(conf, ph, n, up, clock, names, known, plays, held), K.Time{ms, u}, p))) == False{}
        : Bool}:
  match final:
    case True{}:
      {==}
    case False{}:
      {==}

def happened_none(upd: Bool, ply: Bool, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock, +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +ph: K.Phase, +ms: U32, +u: U32, +caps: Model.Caps)
    -> {Lk.played.any(K.out.actions(K.happened(upd, ply, Lk.idle.at(conf, ph, n, up, clock, names, known, plays, held), K.Time{ms, u}, caps)))
        == False{} : Bool}:
  match upd:
    case True{}:
      pl_none(K.core.book(Lk.idle.at(conf, ph, n, up, clock, names, known, plays, held)), Lk.idle.at(conf, ph, n, up, clock, names, known, plays, held),
        K.player.id(Model.player(caps, Model.at(["data"]))), Model.player(caps, Model.at(["data"])))
    case False{}:
      match ply:
        case True{}:
          played_none(K.play.final(Model.play(caps)), conf, n, up, clock, names, known, plays, held, ph,
            ms, u, Model.play(caps))
        case False{}:
          {==}

def list_none(mine: Bool, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock, +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +id: B.Bytes, +ms: U32, +u: U32, +caps: Model.Caps)
    -> {Lk.played.any(K.out.actions(K.reply.list(mine, id, Lk.idle.at(conf, K.Listing{}, n, up, clock, names, known, plays, held), K.Time{ms, u},
        caps))) == False{} : Bool}:
  match mine:
    case True{}:
      live_none(Lk.idle.at(conf, K.Listing{}, n, up, clock, names, known, plays, held), K.Time{ms, u}, Model.players(caps))
    case False{}:
      {==}

def refused_none(mine: Bool, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock, +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +id: B.Bytes, d: B.Bytes)
    -> {Lk.played.any(K.out.actions(K.refused.list(mine, id, d, Lk.idle.at(conf, K.Listing{}, n, up, clock, names, known, plays, held)))) == False{}
        : Bool}:
  match mine:
    case True{}:
      {==}
    case False{}:
      {==}

def msg_none_listing(m: Model.Msg, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock, +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +ms: U32, +u: U32, +caps: Model.Caps)
    -> {Lk.played.any(K.out.actions(K.message.on(m, K.Listing{}, Lk.idle.at(conf, K.Listing{}, n, up, clock, names, known, plays, held), K.Time{ms, u},
        caps))) == False{} : Bool}:
  match m:
    case Model.Hello{v}:
      {==}
    case Model.Reply{+id}:
      list_none(K.is.text(id, "2"), conf, n, up, clock, names, known, plays, held, id, ms, u, caps)
    case Model.Refused{+id, code, +d}:
      refused_none(K.is.text(id, "2"), conf, n, up, clock, names, known, plays, held, id, d)
    case Model.Happened{+ev, o}:
      happened_none(Bool.or(K.is.text(ev, "player_updated"), K.is.text(ev, "player_added")),
        K.is.text(ev, "media_item_played"), conf, n, up, clock, names, known, plays, held, K.Listing{},
        ms, u, caps)
    case Model.Unknown{}:
      {==}

def msg_none_live(m: Model.Msg, +conf: C.Conf, +n: U32, +up: Bool, +clock: K.Clock, +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +ms: U32, +u: U32, +caps: Model.Caps)
    -> {Lk.played.any(K.out.actions(K.message.on(m, K.Live{}, Lk.idle.at(conf, K.Live{}, n, up, clock, names, known, plays, held), K.Time{ms, u},
        caps))) == False{} : Bool}:
  match m:
    case Model.Hello{v}:
      {==}
    case Model.Reply{id}:
      {==}
    case Model.Refused{id, code, d}:
      {==}
    case Model.Happened{+ev, o}:
      happened_none(Bool.or(K.is.text(ev, "player_updated"), K.is.text(ev, "player_added")),
        K.is.text(ev, "media_item_played"), conf, n, up, clock, names, known, plays, held, K.Live{},
        ms, u, caps)
    case Model.Unknown{}:
      {==}

def tick_none(b1: Bool, b2: Bool, b3: Bool, b4: Bool, b5: Bool, live: Bool, +conf: C.Conf, +n: U32,
    +up: Bool, +w: U32, +x: U32, +y: U32, +z: U32, +names: T.Names, +known: List<&2, K.Known>,
    +plays: U32, +held: List<&2, K.Pending>, +ph: K.Phase,
    +now: U32)
    -> {Lk.played.any(K.out.actions(K.tick.if(b1, b2, b3, b4, b5, live, Lk.idle.at(conf, ph, n, up, K.Clock{w, x, y, z}, names, known, plays, held), now)))
        == False{} : Bool}:
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
                      match live:
                        case True{}:
                          {==}
                        case False{}:
                          {==}
                    case False{}:
                      match live:
                        case True{}:
                          {==}
                        case False{}:
                          {==}
                case False{}:
                  match b5:
                    case True{}:
                      match live:
                        case True{}:
                          {==}
                        case False{}:
                          {==}
                    case False{}:
                      match live:
                        case True{}:
                          {==}
                        case False{}:
                          {==}

def event_none_listing(+conf: C.Conf, +n: U32, +up: Bool, +a: U32, +b: U32, +cc: U32, +d: U32,
    +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +ms: U32, +u: U32, ev: K.Input)
    -> {Lk.played.any(K.out.actions(K.event(Lk.idle.at(conf, K.Listing{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev))) == False{} : Bool}:
  match ev:
    case K.MqPacket{p}:
      mq_none(K.with.mq_heard(Lk.idle.at(conf, K.Listing{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), ms), K.Time{ms, u}, p)
    case K.MqLost{}:
      {==}
    case K.MaHeard{h}:
      match h:
        case L.Opened{}:
          {==}
        case L.Message{+caps}:
          msg_none_listing(Model.classify(caps), conf, n, up, K.Clock{a, b, ms, d}, names, known, plays, held, ms,
            u, caps)
        case L.Garbled{}:
          {==}
        case L.Pinged{x}:
          {==}
        case L.Lost{w}:
          {==}
    case K.Tick{}:
      tick_none(
        Bool.and(Bool.not(K.broker.up(K.Listing{})),
          Bool.and(K.since(ms, a, K.connect_wait()), Bool.not(K.is.over(K.Listing{})))),
        Bool.and(K.broker.up(K.Listing{}), K.since(ms, a, K.broker_quiet())),
        Bool.and(K.broker.up(K.Listing{}), K.since(ms, cc, K.ma_quiet())),
        Bool.and(K.broker.up(K.Listing{}), K.since(ms, b, K.ping_every())),
        Bool.and(K.is.live(K.Listing{}), K.since(ms, d, K.report_every())), K.is.live(K.Listing{}),
        conf, n, up, a, b, cc, d, names, known, plays, held, K.Listing{}, ms)

def Lk.plays_none_from_nowhere_listing(conf, n, up, clock, names, known, plays, held, t, ev):
  match clock:
    case K.Clock{+a, +b, +cc, +d}:
      match t:
        case K.Time{+ms, +u}:
          %Equal.sym(List<&2, K.Action>,
              K.out.actions(K.sent(K.event(Lk.idle.at(conf, K.Listing{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev), ms)),
              K.out.actions(K.event(Lk.idle.at(conf, K.Listing{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev)),
              sent_keeps(K.event(Lk.idle.at(conf, K.Listing{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev), ms)) :
            {Lk.played.any(_) == False{} : Bool}
          event_none_listing(conf, n, up, a, b, cc, d, names, known, plays, held, ms, u, ev)

def event_none_live(+conf: C.Conf, +n: U32, +up: Bool, +a: U32, +b: U32, +cc: U32, +d: U32,
    +names: T.Names, +known: List<&2, K.Known>, +plays: U32,
    +held: List<&2, K.Pending>, +ms: U32, +u: U32, ev: K.Input)
    -> {Lk.played.any(K.out.actions(K.event(Lk.idle.at(conf, K.Live{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev))) == False{} : Bool}:
  match ev:
    case K.MqPacket{p}:
      mq_none(K.with.mq_heard(Lk.idle.at(conf, K.Live{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), ms), K.Time{ms, u}, p)
    case K.MqLost{}:
      {==}
    case K.MaHeard{h}:
      match h:
        case L.Opened{}:
          {==}
        case L.Message{+caps}:
          msg_none_live(Model.classify(caps), conf, n, up, K.Clock{a, b, ms, d}, names, known, plays, held, ms,
            u, caps)
        case L.Garbled{}:
          {==}
        case L.Pinged{x}:
          {==}
        case L.Lost{w}:
          {==}
    case K.Tick{}:
      tick_none(
        Bool.and(Bool.not(K.broker.up(K.Live{})),
          Bool.and(K.since(ms, a, K.connect_wait()), Bool.not(K.is.over(K.Live{})))),
        Bool.and(K.broker.up(K.Live{}), K.since(ms, a, K.broker_quiet())),
        Bool.and(K.broker.up(K.Live{}), K.since(ms, cc, K.ma_quiet())),
        Bool.and(K.broker.up(K.Live{}), K.since(ms, b, K.ping_every())),
        Bool.and(K.is.live(K.Live{}), K.since(ms, d, K.report_every())), K.is.live(K.Live{}),
        conf, n, up, a, b, cc, d, names, known, plays, held, K.Live{}, ms)

def Lk.plays_none_from_nowhere_live(conf, n, up, clock, names, known, plays, held, t, ev):
  match clock:
    case K.Clock{+a, +b, +cc, +d}:
      match t:
        case K.Time{+ms, +u}:
          %Equal.sym(List<&2, K.Action>,
              K.out.actions(K.sent(K.event(Lk.idle.at(conf, K.Live{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev), ms)),
              K.out.actions(K.event(Lk.idle.at(conf, K.Live{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev)),
              sent_keeps(K.event(Lk.idle.at(conf, K.Live{}, n, up, K.Clock{a, b, cc, d}, names, known, plays, held), K.Time{ms, u}, ev), ms)) :
            {Lk.played.any(_) == False{} : Bool}
          event_none_live(conf, n, up, a, b, cc, d, names, known, plays, held, ms, u, ev)
