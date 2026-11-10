import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/ma/link.bend as L
import ../lib/bridge/conf.bend as C
import ../lib/bridge/core.bend as K
# Deterministic simulation of the bridge's decisions (lib/bridge/core.bend): random sessions of
# inputs and time, run through K.step as lib/app/main.bend runs them (a tick after any input once
# a second has passed), with invariants checked after every step against the simulation's own
# record of what happened. Pure and repeatable (a seeded xorshift).
#   bend progs/sim_core.bend

# xorshift32
def rnd.b(+x: U32) -> U32:
  ((x >> 17n) .^. x : U32)

def rnd.c(+x: U32) -> U32:
  ((x << 5n) .^. x : U32)

def rnd(+x: U32) -> U32:
  rnd.c(rnd.b(((x << 13n) .^. x : U32)))

def pick(+r: U32, +n: U32) -> U32:
  (r % n : U32)

def time.at(+ms: U32) -> K.Time:
  K.Time{ms, (1793000000 + ms / 1000 : U32)}

def conf() -> C.Conf:
  C.read.conf(C.parse(B.utf8("ma_token t\nmqtt_host b\nplays_file /p\n")))

def bump(b: Bool, +n: U32) -> U32:
  match b:
    case True{}:
      (n + 1 : U32)
    case False{}:
      n

def str.if(b: Bool, yes: String, no: String) -> String:
  match b:
    case True{}:
      yes
    case False{}:
      no

# Messages (real JSON, read by the real scanner and model)
# --------------------------------------------------------

def msg(s: String) -> K.Input:
  K.MaHeard{L.Message{Model.read(B.utf8(s))}}

def player.json(+i: U32, +r: U32) -> String:
  "{\"player_id\": \"P" ++ U32.show(i) ++ "\", \"name\": \""
    ++ str.if(U32.is_eq(i, 0), "Living Room", "Move 2") ++ "\", \"available\": true, "
    ++ "\"playback_state\": \"" ++ str.if(U32.is_eq(pick(r, 2), 0), "playing", "idle")
    ++ "\", \"current_media\": {\"uri\": \"library://track/" ++ U32.show(pick(r, 5))
    ++ "\", \"title\": \"T\", \"artist\": \"A\", \"album\": \"L\", \"duration\": 200},"
    ++ " \"active_source\": \"P0\", \"synced_to\": null, \"volume_level\": 3}"

def m.hello() -> K.Input:
  msg("{\"server_id\": \"x\", \"server_version\": \"2.10.9\"}")

def m.login(ok: Bool) -> K.Input:
  match ok:
    case True{}:
      msg("{\"message_id\": \"1\", \"result\": {\"authenticated\": true}}")
    case False{}:
      msg("{\"message_id\": \"1\", \"error_code\": 23, \"details\": \"bad token\"}")

def m.players(+r: U32) -> K.Input:
  msg("{\"message_id\": \"2\", \"result\": [" ++ player.json(0, r) ++ ", "
    ++ player.json(1, rnd(r)) ++ ", " ++ player.json(2, rnd(rnd(r))) ++ "]}")

def m.updated(+r: U32) -> K.Input:
  msg("{\"event\": \"player_updated\", \"object_id\": \"x\", \"data\": "
    ++ player.json(pick(r, 3), rnd(r)) ++ "}")

# A play report for track n (final or still playing).
def m.report(+n: U32, final: Bool) -> K.Input:
  msg("{\"event\": \"media_item_played\", \"object_id\": \"u\", \"data\": {\"uri\": "
    ++ "\"library://track/u" ++ U32.show(n) ++ "\", \"name\": \"T\", \"artist\": \"A\", "
    ++ "\"album\": \"L\", \"duration\": 200, \"seconds_played\": 100, \"fully_played\": false, "
    ++ "\"is_playing\": " ++ str.if(final, "false", "true") ++ ", \"player_id\": \"P0\"}}")

def m.answer(+id: U32) -> K.Input:
  msg("{\"message_id\": \"" ++ U32.show(id) ++ "\", \"result\": {\"external_ids\": [[\"isrc\", "
    ++ "\"X1\"]], \"provider_mappings\": [{\"provider_domain\": \"apple_music\", "
    ++ "\"item_id\": \"9\"}]}}")

def m.refusal(+id: U32) -> K.Input:
  msg("{\"message_id\": \"" ++ U32.show(id) ++ "\", \"error_code\": 999, \"details\": \"no\"}")

# How track n's uri shows in a play's payload.
def uri(+n: U32) -> B.Bytes:
  B.utf8("\"uri\":\"library://track/u" ++ U32.show(n) ++ "\"")

def starts(+hay: B.Bytes, +needle: B.Bytes) -> Bool:
  B.beq(List.take(&2, U32, hay, List.length(&2, U32, needle)), needle)

def contains(+hay: B.Bytes, +needle: B.Bytes) -> Bool:
  match hay:
    case Nil{}:
      False{}
    case _ <> t:
      Bool.or(starts(hay, needle), contains(t, needle))

# The record
# ----------

# A final report the core took: its uri, when, how often published, whether reported late.
type Open is Data:
  Open{uri: B.Bytes, at: U32, done: U32, flagged: Bool}

# Final reports open this session, the lookup ids asked for, the next track number.
type Ledger is Data:
  Ledger{open: List<&2, Open>, asked: List<&2, U32>, track: U32}

# ghost: anything done after the end; early: a publish (not the offline status) before live;
# dup: a play published twice; phantom: a play matching no final report; late: a play still not
# published 13 s after its final report while live.
type Viol is Data:
  Viol{ghost: U32, early: U32, dup: U32, phantom: U32, late: U32}

# quiet: up, and nothing sent to the broker for over 35 s; deaf: still up although the broker has
# been silent for over 95 s; unasked: a final report taken without exactly one lookup;
# unfinished: plays still waiting when a run ended (not a violation: the run stopped).
type Watch is Data:
  Watch{quiet: U32, deaf: U32, unasked: U32, unfinished: U32}

# carried: plays still waiting when their session ended (the next one looks them up again).
type Stats is Data:
  Stats{sessions: U32, finals: U32, published: U32, carried: U32, steps: U32}

# The time, when the broker was last heard and sent to, when the last tick ran.
type Clock is Data:
  Clock{now: U32, heard: U32, sent: U32, tick: U32}

type Sim is Data:
  Sim{core: K.Core, clock: Clock, ledger: Ledger, rng: U32, tally: Tally}

type Tally is Data:
  Tally{v: Viol, w: Watch, s: Stats}

# Looking at actions
# ------------------

def act.is_mq(a: K.Action) -> Bool:
  match a:
    case K.ToMq{_}:
      True{}
    case _:
      False{}

def act.is_data(a: K.Action) -> Bool:
  match a:
    case K.ToMq{p}:
      match p:
        case M.Publish{_, _, _, _, _, payload}:
          Bool.not(B.beq(payload, B.utf8("offline")))
        case _:
          False{}
    case _:
      False{}

def act.is_ended(a: K.Action) -> Bool:
  match a:
    case K.Ended{_}:
      True{}
    case _:
      False{}

def has_mq(as: List<&2, K.Action>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case a <> t:
      Bool.or(act.is_mq(a), has_mq(t))

def has_data(as: List<&2, K.Action>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case a <> t:
      Bool.or(act.is_data(a), has_data(t))

def has_ended(as: List<&2, K.Action>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case a <> t:
      Bool.or(act.is_ended(a), has_ended(t))

# The ids of the lookups asked for, in order.
def asked.of(as: List<&2, K.Action>) -> List<&2, U32>:
  match as:
    case Nil{}:
      Nil{}
    case a <> t:
      match a:
        case K.ToMa{id, c}:
          match c:
            case Api.Lookup{_}:
              id <> asked.of(t)
            case _:
              asked.of(t)
        case _:
          asked.of(t)

# The payloads of the plays published (the only publishes not retained).
def plays.of(as: List<&2, K.Action>) -> List<&2, B.Bytes>:
  match as:
    case Nil{}:
      Nil{}
    case a <> t:
      match a:
        case K.ToMq{p}:
          match p:
            case M.Publish{_, _, retain, _, _, payload}:
              match retain:
                case True{}:
                  plays.of(t)
                case False{}:
                  payload <> plays.of(t)
            case _:
              plays.of(t)
        case _:
          plays.of(t)

# Attributing plays to final reports
# ----------------------------------

def open.uri(o: Open) -> B.Bytes:
  match o:
    case Open{u, _, _, _}:
      u

def open.waiting(o: Open) -> Bool:
  match o:
    case Open{_, _, d, _}:
      U32.is_eq(d, 0)

def head.hit(+os: List<&2, Open>, +payload: B.Bytes) -> Bool:
  match os:
    case Nil{}:
      False{}
    case o <> _:
      contains(payload, open.uri(o))

# The opens after a play's payload is attributed, whether one matched, whether it was a repeat.
type Attr is Data:
  Attr{open: List<&2, Open>, matched: Bool, dup: Bool}

def attribute.keep(o: Open, a: Attr) -> Attr:
  match a:
    case Attr{rest, m, dp}:
      Attr{o <> rest, m, dp}

def attribute(+os: List<&2, Open>, +payload: B.Bytes, hit: Bool) -> Attr:
  match os:
    case Nil{}:
      Attr{Nil{}, False{}, False{}}
    case o <> t:
      match o:
        case Open{u, at, +d, fl}:
          match hit:
            case True{}:
              Attr{Open{u, at, (d + 1 : U32), fl} <> t, True{}, Bool.not(U32.is_eq(d, 0))}
            case False{}:
              attribute.keep(Open{u, at, d, fl}, attribute(t, payload, head.hit(t, payload)))

# The record and the violations while a step's plays are checked.
type Checked is Data:
  Checked{l: Ledger, v: Viol}

def play.checked(a: Attr, asked: List<&2, U32>, +track: U32, v: Viol) -> Checked:
  match a:
    case Attr{os2, m, dp}:
      match v:
        case Viol{g, e, d, ph, lt}:
          Checked{Ledger{os2, asked, track}, Viol{g, e, bump(dp, d), bump(Bool.not(m), ph), lt}}

# A play's payload checked against the record.
def play.check(+payload: B.Bytes, c: Checked) -> Checked:
  match c:
    case Checked{l, v}:
      match l:
        case Ledger{+os, asked, track}:
          play.checked(attribute(os, payload, head.hit(os, payload)), asked, track, v)

def plays.check(ps: List<&2, B.Bytes>, c: Checked) -> Checked:
  match ps:
    case Nil{}:
      c
    case p <> t:
      plays.check(t, play.check(p, c))

# The opens with the late ones flagged, and how many were newly late.
def late.due(o: Open, +now: U32) -> Bool:
  match o:
    case Open{_, at, d, fl}:
      Bool.and(Bool.and(U32.is_eq(d, 0), Bool.not(fl)), ((now - at : U32) > 13000 : U32))

def late.mark.if(due: Bool, o: Open) -> Open:
  match due:
    case True{}:
      match o:
        case Open{u, at, d, _}:
          Open{u, at, d, True{}}
    case False{}:
      o

def late.mark(os: List<&2, Open>, +now: U32) -> List<&2, Open>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      late.mark.if(late.due(o, now), o) <> late.mark(t, now)

def late.count(os: List<&2, Open>, +now: U32) -> U32:
  match os:
    case Nil{}:
      0
    case +o <> t:
      bump(late.due(o, now), late.count(t, now))

def waiting.count(os: List<&2, Open>) -> U32:
  match os:
    case Nil{}:
      0
    case +o <> t:
      bump(open.waiting(o), waiting.count(t))

# Picking inputs
# --------------

# The input, how far the clock moves (ms), whether it is a final report, whether it is the broker,
# how many quiet seconds follow (a tick each, as the main loop runs them).
type Pick is Data:
  Pick{input: K.Input, dt: U32, final: Bool, mq: Bool, idle: Nat}

def tick.pick(+r: U32) -> Pick:
  Pick{K.Tick{}, 1000, False{}, False{}, U32.to_nat(pick(r, 20))}

def ev.pick(i: K.Input, +r: U32) -> Pick:
  Pick{i, pick(r, 1500), False{}, False{}, 0n}

def mq.pick(i: K.Input, +r: U32) -> Pick:
  Pick{i, pick(r, 1500), False{}, True{}, 0n}

def nth(xs: List<&2, U32>, k: Nat, +d: U32) -> U32:
  match xs:
    case Nil{}:
      d
    case x <> t:
      match k:
        case 0n:
          x
        case 1n+p:
          nth(t, p, d)

# A recent lookup id (one of the last three asked), or one never asked.
def answer.id(+cat: U32, asked: List<&2, U32>) -> U32:
  match cat:
    case 0:
      nth(asked, 0n, 999999)
    case 1:
      nth(asked, 1n, 999999)
    case 2:
      nth(asked, 2n, 999999)
    case _:
      999999

def cat.of5(+v: U32, +a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  Bool.pick(U32, (v < a : U32), 0, Bool.pick(U32, (v < b : U32), 1,
    Bool.pick(U32, (v < c : U32), 2, Bool.pick(U32, (v < d : U32), 3, 4))))

def pick.connecting(+cat: U32, +r: U32) -> Pick:
  match cat:
    case 0:
      mq.pick(K.MqPacket{M.ConnAck{False{}, 0}}, r)
    case 1:
      mq.pick(K.MqPacket{M.ConnAck{False{}, 5}}, r)
    case 2:
      tick.pick(r)
    case _:
      ev.pick(K.MqLost{}, r)

def pick.opening(+cat: U32, +r: U32) -> Pick:
  match cat:
    case 0:
      ev.pick(K.MaHeard{L.Opened{}}, r)
    case 1:
      ev.pick(m.hello(), r)
    case 2:
      tick.pick(r)
    case 3:
      ev.pick(K.MaHeard{L.Garbled{}}, r)
    case _:
      ev.pick(K.MaHeard{L.Dropped{"cut"}}, r)

def pick.logging_in(+cat: U32, +r: U32) -> Pick:
  match cat:
    case 0:
      ev.pick(m.login(True{}), r)
    case 1:
      ev.pick(m.login(False{}), r)
    case _:
      tick.pick(r)

def pick.listing(+cat: U32, +r: U32) -> Pick:
  match cat:
    case 0:
      ev.pick(m.players(r), r)
    case 1:
      ev.pick(m.updated(r), r)
    case _:
      tick.pick(r)

def cat.live(+v: U32) -> U32:
  Bool.pick(U32, (v < 300 : U32), 0, Bool.pick(U32, (v < 500 : U32), 1,
    Bool.pick(U32, (v < 600 : U32), 2, Bool.pick(U32, (v < 700 : U32), 3,
    Bool.pick(U32, (v < 850 : U32), 4, Bool.pick(U32, (v < 880 : U32), 5,
    Bool.pick(U32, (v < 940 : U32), 6, Bool.pick(U32, (v < 980 : U32), 7,
    Bool.pick(U32, (v < 990 : U32), 8, Bool.pick(U32, (v < 995 : U32), 9, 10))))))))))

def pick.live(+cat: U32, +r: U32, asked: List<&2, U32>, +track: U32) -> Pick:
  match cat:
    case 0:
      tick.pick(r)
    case 1:
      ev.pick(m.updated(r), r)
    case 2:
      ev.pick(m.report(track, False{}), r)
    case 3:
      Pick{m.report(track, True{}), pick(r, 1500), True{}, False{}, 0n}
    case 4:
      ev.pick(m.answer(answer.id(pick(r, 4), asked)), r)
    case 5:
      ev.pick(m.refusal(answer.id(pick(r, 4), asked)), r)
    case 6:
      ev.pick(K.MaHeard{L.Pinged{B.utf8("p")}}, r)
    case 7:
      mq.pick(K.MqPacket{M.PingResp{}}, r)
    case 8:
      ev.pick(K.MaHeard{L.Garbled{}}, r)
    case 9:
      ev.pick(K.MqLost{}, r)
    case _:
      ev.pick(K.MaHeard{L.Dropped{"cut"}}, r)

# One step
# --------

# Quiet seconds: a tick each.
type Idle is Data:
  Idle{core: K.Core, now: U32, actions: List<&2, K.Action>}

def idle.run(n: Nat, +c: K.Core, +now: U32, acc: List<&2, K.Action>) -> Idle:
  match n:
    case 0n:
      Idle{c, now, acc}
    case 1n+p:
      +o = K.step(c, time.at((now + 1000 : U32)), K.Tick{})
      idle.run(p, K.out.core(o), (now + 1000 : U32), List.append(&2, K.Action, acc, K.out.actions(o)))

def tick.if(due: Bool, +c: K.Core, +t: K.Time) -> K.Out:
  match due:
    case True{}:
      K.step(c, t, K.Tick{})
    case False{}:
      K.Out{c, Nil{}}

def u32.if(b: Bool, +yes: U32, +no: U32) -> U32:
  match b:
    case True{}:
      yes
    case False{}:
      no

def opens.add(take: Bool, +track: U32, +now: U32, os: List<&2, Open>) -> List<&2, Open>:
  match take:
    case True{}:
      Open{uri(track), now, 0, False{}} <> os
    case False{}:
      os

def prepend(xs: List<&2, U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      acc
    case x <> t:
      prepend(t, x <> acc)

def late.mark.on(live: Bool, +os: List<&2, Open>, +now: U32) -> List<&2, Open>:
  match live:
    case True{}:
      late.mark(os, now)
    case False{}:
      os

# A session that ended keeps its waiting plays on record (they are carried over); its lookup ids
# are done with.
def after.ledger.end(ended: Bool, l: Ledger) -> Ledger:
  match ended:
    case True{}:
      match l:
        case Ledger{os, _, track}:
          Ledger{os, Nil{}, track}
    case False{}:
      l

# Going live again: carried plays are due from now.
def reset.at(os: List<&2, Open>, +now: U32) -> List<&2, Open>:
  match os:
    case Nil{}:
      Nil{}
    case o <> t:
      match o:
        case Open{u, at, +d, fl}:
          Open{u, u32.if(U32.is_eq(d, 0), now, at), d, fl} <> reset.at(t, now)

def reset.if(went_live: Bool, +os: List<&2, Open>, +now: U32) -> List<&2, Open>:
  match went_live:
    case True{}:
      reset.at(os, now)
    case False{}:
      os

# The record after a step's actions: plays attributed, a taken final report opened, the lookups
# asked for kept (newest first), late ones flagged; a session that ended closes its record.
def after.ledger(+as: List<&2, K.Action>, +take: Bool, +live: Bool, +ended: Bool, +now: U32,
    l: Ledger, +went_live: Bool) -> Ledger:
  match l:
    case Ledger{os, asked, +track}:
      +os1 = opens.add(take, track, now, reset.if(went_live, os, now))
      +os2 = late.mark.on(live, os1, now)
      after.ledger.end(ended, Ledger{os2, prepend(asked.of(as), asked), track})


def viol.after(v: Viol, +early: Bool, +late: U32) -> Viol:
  match v:
    case Viol{g, e, d, ph, lt}:
      Viol{g, bump(early, e), d, ph, (lt + late : U32)}

def watch.after(w: Watch, +quiet: Bool, +deaf: Bool, +unasked: Bool) -> Watch:
  match w:
    case Watch{q, d, u, n}:
      Watch{bump(quiet, q), bump(deaf, d), bump(unasked, u), n}

def stats.after(s: Stats, +ended: Bool, +take: Bool, +published: U32, +lost: U32) -> Stats:
  match s:
    case Stats{n, f, p, l, st}:
      Stats{bump(ended, n), bump(take, f), (p + published : U32), (l + lost : U32), (st + 1 : U32)}

def lost.if(ended: Bool, os: List<&2, Open>) -> U32:
  match ended:
    case True{}:
      waiting.count(os)
    case False{}:
      0

def late.if(live: Bool, os: List<&2, Open>, +now: U32) -> U32:
  match live:
    case True{}:
      late.count(os, now)
    case False{}:
      0

def ledger.opens(l: Ledger) -> List<&2, Open>:
  match l:
    case Ledger{os, _, _}:
      os

def ledger.track(l: Ledger) -> U32:
  match l:
    case Ledger{_, _, t}:
      t

def ledger.asked(l: Ledger) -> List<&2, U32>:
  match l:
    case Ledger{_, a, _}:
      a

def ledger.next(final: Bool, l: Ledger) -> Ledger:
  match final:
    case True{}:
      match l:
        case Ledger{os, asked, t}:
          Ledger{os, asked, (t + 1 : U32)}
    case False{}:
      l

# The checks of one step, once its plays are attributed (pc: the record and violations after).
def sim.after.on(clock: Clock, +l1: Ledger, v1: Viol, +as: List<&2, K.Action>, +c2: K.Core,
    +r: U32, w: Watch, st: Stats, +early: Bool, +take: Bool, +final: Bool, +was_live: Bool) -> Sim:
  match clock:
    case Clock{+now, +heard, +sent, +tick}:
      +ph2 = K.core.phase(c2)
      +alive = Bool.not(K.is.over(ph2))
      +up = K.broker.up(ph2)
      +live = K.is.live(ph2)
      +ended = has_ended(as)
      +opens = opens.add(take, ledger.track(l1), now,
        reset.if(Bool.and(live, Bool.not(was_live)), ledger.opens(l1), now))
      +quiet = Bool.and(Bool.and(alive, up), ((now - sent : U32) > 35000 : U32))
      +deaf = Bool.and(Bool.and(alive, up), ((now - heard : U32) > 95000 : U32))
      +unasked = Bool.and(take, Bool.not(U32.is_eq(U32.from_nat(List.length(&2, U32, asked.of(as))), 1)))
      Sim{c2, Clock{now, heard, sent, tick},
        ledger.next(final, after.ledger(as, take, live, ended, now, l1,
          Bool.and(live, Bool.not(was_live)))), r,
        Tally{viol.after(v1, Bool.and(early, has_data(as)), late.if(live, opens, now)),
          watch.after(w, quiet, deaf, unasked),
          stats.after(st, ended, take, U32.from_nat(List.length(&2, B.Bytes, plays.of(as))),
            lost.if(ended, opens))}}

def sim.after(pc: Checked, clock: Clock, +as: List<&2, K.Action>, +c2: K.Core, +r: U32,
    w: Watch, st: Stats, +early: Bool, +take: Bool, +final: Bool, +was_live: Bool) -> Sim:
  match pc:
    case Checked{l1, v1}:
      sim.after.on(clock, l1, v1, as, c2, r, w, st, early, take, final, was_live)

# The checks after the step's quiet seconds too.
def sim.idle(i: Idle, +ledger: Ledger, v: Viol, +mq: Bool, +heard: U32, +sent: U32, +due: Bool,
    +tick: U32, +now2: U32, +r: U32, w: Watch, st: Stats, +early: Bool, +take: Bool, +final: Bool,
    +was_live: Bool) -> Sim:
  match i:
    case Idle{c, +now3, +as}:
      sim.after(plays.check(plays.of(as), Checked{ledger, v}),
        Clock{now3, u32.if(mq, now2, heard), u32.if(has_mq(as), now3, sent),
          u32.if(Bool.or(due, Bool.not(U32.is_eq(now3, now2))), now3, tick)},
        as, c, rnd(r), w, st, early, take, final, was_live)

# One input (and the tick that follows once a second has passed) through the core.
def sim.feed.on(p: Pick, clock: Clock, tally: Tally, +core: K.Core, +ledger: Ledger, +r: U32,
    +early: Bool, +taking: Bool, +was_live: Bool) -> Sim:
  match p:
    case Pick{input, +dt, +final, +mq, idle}:
      match clock:
        case Clock{+now, +heard, +sent, +tick}:
          match tally:
            case Tally{v, w, st}:
              +now2 = (now + dt : U32)
              +t = time.at(now2)
              +o1 = K.step(core, t, input)
              +due = ((now2 - tick : U32) >= 1000 : U32)
              +o2 = tick.if(due, K.out.core(o1), t)
              +i = idle.run(idle, K.out.core(o2), now2,
                List.append(&2, K.Action, K.out.actions(o1), K.out.actions(o2)))
              sim.idle(i, ledger, v, mq, heard, sent, due, tick, now2, r, w, st, early,
                Bool.and(final, taking), final, was_live)

def sim.feed(p: Pick, clock: Clock, tally: Tally, +core: K.Core, +ledger: Ledger, +r: U32,
    +early: Bool, +taking: Bool) -> Sim:
  sim.feed.on(p, clock, tally, core, ledger, r, early, taking, K.is.live(K.core.phase(core)))

# After an end: the old core must do nothing more; a new session starts a second later.
def sim.restart(+core: K.Core, clock: Clock, ledger: Ledger, +r: U32, tally: Tally) -> Sim:
  match clock:
    case Clock{+now, _, _, _}:
      match tally:
        case Tally{v, w, st}:
          match v:
            case Viol{g, e, d, ph, lt}:
              +now2 = (now + 1000 : U32)
              +t = time.at(now2)
              +ghost = Bool.or(Bool.not(List.is_empty(&2, K.Action, K.out.actions(K.step(core, t,
                K.Tick{})))), Bool.not(List.is_empty(&2, K.Action, K.out.actions(K.step(core, t,
                m.updated(r))))))
              Sim{K.out.core(K.start(conf(), t, K.core.left(core))), Clock{now2, now2, now2, now2},
                ledger, rnd(r),
                Tally{Viol{bump(ghost, g), e, d, ph, lt}, w, st}}

def sim.step.on(ph: K.Phase, +v: U32, +core: K.Core, clock: Clock, +ledger: Ledger, +r: U32,
    tally: Tally) -> Sim:
  match ph:
    case K.Over{}:
      sim.restart(core, clock, ledger, r, tally)
    case K.Connecting{}:
      sim.feed(pick.connecting(cat.of5(v, 900, 940, 980, 1000), rnd(r)), clock, tally, core,
        ledger, r, True{}, False{})
    case K.Opening{}:
      sim.feed(pick.opening(cat.of5(v, 450, 900, 960, 980), rnd(r)), clock, tally, core, ledger, r,
        True{}, False{})
    case K.LoggingIn{}:
      sim.feed(pick.logging_in(cat.of5(v, 850, 900, 1000, 1000), rnd(r)), clock, tally, core,
        ledger, r, True{}, False{})
    case K.Listing{}:
      sim.feed(pick.listing(cat.of5(v, 800, 900, 1000, 1000), rnd(r)), clock, tally, core, ledger,
        r, False{}, True{})
    case K.Live{}:
      sim.feed(pick.live(cat.live(v), rnd(r), ledger.asked(ledger), ledger.track(ledger)), clock,
        tally, core, ledger, r, False{}, True{})

def sim.step(s: Sim) -> Sim:
  match s:
    case Sim{+core, clock, ledger, rng, tally}:
      +r = rnd(rng)
      sim.step.on(K.core.phase(core), pick(r, 1000), core, clock, ledger, r, tally)

def sim.steps(n: Nat, s: Sim) -> Sim:
  match n:
    case 0n:
      s
    case 1n+p:
      sim.steps(p, sim.step(s))

# The tally at the end of a run, with the plays still waiting then.
def sim.finish(s: Sim) -> Tally:
  match s:
    case Sim{_, _, l, _, t}:
      match t:
        case Tally{v, w, st}:
          match w:
            case Watch{q, d, u, n}:
              Tally{v, Watch{q, d, u, (n + waiting.count(ledger.opens(l)) : U32)}, st}

# A run: a fresh session at time 1e6, then its steps (sessions restart as they end).
def sim.run(+seed: U32, +steps: Nat, tally: Tally) -> Tally:
  +t = time.at(1000000)
  sim.finish(sim.steps(steps, Sim{K.out.core(K.start(conf(), t, Nil{})),
    Clock{1000000, 1000000, 1000000, 1000000}, Ledger{Nil{}, Nil{}, 0}, seed, tally}))

def sim.runs(n: Nat, +seed: U32, +steps: Nat, tally: Tally) -> Tally:
  match n:
    case 0n:
      tally
    case 1n+p:
      sim.runs(p, rnd(seed), steps, sim.run(seed, steps, tally))

def show(t: Tally) -> String:
  match t:
    case Tally{v, w, s}:
      match v:
        case Viol{g, e, d, ph, lt}:
          match w:
            case Watch{q, de, u, un}:
              match s:
                case Stats{n, f, p, l, st}:
                  U32.show(st) ++ " steps, " ++ U32.show(n) ++ " sessions ended, "
                    ++ U32.show(f) ++ " final reports, " ++ U32.show(p) ++ " plays published ("
                    ++ U32.show(l) ++ " carried over a session's end), "
                    ++ U32.show(un) ++ " still waiting when a run stopped\nviolations: ghost "
                    ++ U32.show(g) ++ ", early " ++ U32.show(e) ++ ", dup " ++ U32.show(d)
                    ++ ", phantom " ++ U32.show(ph) ++ ", late " ++ U32.show(lt) ++ ", quiet "
                    ++ U32.show(q) ++ ", deaf " ++ U32.show(de) ++ ", unasked " ++ U32.show(u)

def main() -> IO(Unit):
  IO.print(show(sim.runs(200n, 2463534242, 400n, Tally{Viol{0, 0, 0, 0, 0}, Watch{0, 0, 0, 0},
    Stats{0, 0, 0, 0, 0}})))
