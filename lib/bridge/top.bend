import Base
import ../wire/bytes.bend as B
import ../wire/mqtt.bend as M
import ../ma/api.bend as Api
import ../ma/model.bend as Model
import ../ma/link.bend as L
import ./conf.bend as C
import ./topics.bend as T
import ./deck.bend as D
import ./core.bend as K
# The bridge's step: the core's (core.bend, unchanged) and beside it the queue windows (deck.bend),
# fed the same inputs. The deck asks with message ids from 2^31 up, so its replies never answer one
# of the core's (whose ids count up from 3, assumed never to reach 2^31) and the core ignores them;
# its windows are published only while the session is live, and never once it is over.

def first_id() -> U32:
  2147483648

# The core, the deck, the deck's next message id.
type Top is Data:
  Top{core: K.Core, deck: D.Deck, next: U32}

type Out is Data:
  Out{top: Top, actions: List<&2, K.Action>}

def top.core(t: Top) -> K.Core:
  match t:
    case Top{c, _, _}:
      c

# The last plays, carried to the next session.
def top.recent(t: Top) -> List<&2, D.Recent>:
  match t:
    case Top{_, d, _}:
      D.deck.recent(d)

def out.top(o: Out) -> Top:
  match o:
    case Out{t, _}:
      t

def out.actions(o: Out) -> List<&2, K.Action>:
  match o:
    case Out{_, a}:
      a

# A session's start: the core's (with the plays the last one left waiting), the last plays kept.
def start(+conf: C.Conf, +t: K.Time, held: List<&2, K.Pending>, recent: List<&2, D.Recent>) -> Out:
  +o = K.start(conf, t, held)
  Out{Top{K.out.core(o), D.fresh(recent), first_id()}, K.out.actions(o)}

# The deck's work as actions
# --------------------------

def request.act(r: D.Request) -> K.Action:
  match r:
    case D.Request{id, c}:
      K.ToMa{id, c}

def requests.acts(rs: List<&2, D.Request>) -> List<&2, K.Action>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      request.act(r) <> requests.acts(t)

# A player's window, retained under <prefix>/<player>/queue (one with no topic level has none).
def show.on(m: Maybe<&2, B.Bytes>, +prefix: String, +d: D.Deck, +id: B.Bytes) -> List<&2, K.Action>:
  match m:
    case Some{l}:
      [K.ToMq{M.Publish{False{}, 0, True{}, T.topic.queue(prefix, l), 0, D.json(d, id)}}]
    case None{}:
      Nil{}

def shows.acts(ss: List<&2, B.Bytes>, +names: T.Names, +prefix: String, +d: D.Deck)
    -> List<&2, K.Action>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      List.append(&2, K.Action, show.on(T.level.of(names, s), prefix, d, s),
        shows.acts(t, names, prefix, d))

def book.names(b: K.Book) -> T.Names:
  match b:
    case K.Book{n, _, _, _, _}:
      n

def shows.if(live: Bool, ss: List<&2, B.Bytes>, +c: K.Core, +d: D.Deck) -> List<&2, K.Action>:
  match live:
    case True{}:
      shows.acts(ss, book.names(K.core.book(c)), K.core.prefix(c), d)
    case False{}:
      Nil{}

# The requests, then (live only) the windows that changed.
def did.acts(x: D.Did, live: Bool, +c: K.Core) -> List<&2, K.Action>:
  match x:
    case D.Did{+d, _, rs, ss}:
      List.append(&2, K.Action, requests.acts(rs), shows.if(live, ss, c, d))

# What the deck makes of an input
# -------------------------------

def none(+d: D.Deck, +next: U32) -> D.Did:
  D.Did{d, next, Nil{}, Nil{}}

def reply.on(listing: Bool, ask: Bool, +d: D.Deck, +id: B.Bytes, +caps: Model.Caps, +next: U32)
    -> D.Did:
  match listing:
    case True{}:
      D.listed(d, Model.queues(caps), next)
    case False{}:
      match ask:
        case True{}:
          D.answered(d, id, Model.items(caps), next)
        case False{}:
          none(d, next)

def refused.on(mine: Bool, +d: D.Deck, +id: B.Bytes, +next: U32) -> D.Did:
  match mine:
    case True{}:
      none(D.refused(d, id), next)
    case False{}:
      none(d, next)

def played.on(final: Bool, +p: Model.Play, +image: B.Bytes, +d: D.Deck, +next: U32) -> D.Did:
  match final:
    case True{}:
      D.played(p, image, d, next)
    case False{}:
      none(d, next)

def happened.on(placed: Bool, items: Bool, play: Bool, live: Bool, +d: D.Deck, +object: B.Bytes,
    +caps: Model.Caps, +next: U32) -> D.Did:
  match placed:
    case True{}:
      match live:
        case True{}:
          D.updated(d, Model.queue(caps, Model.at(["data"])), next)
        case False{}:
          none(d, next)
    case False{}:
      match items:
        case True{}:
          match live:
            case True{}:
              D.items_changed(d, object, next)
            case False{}:
              none(d, next)
        case False{}:
          match play:
            case True{}:
              played.on(K.play.final(Model.play(caps)), Model.play(caps), Model.play.image(caps), d,
                next)
            case False{}:
              none(d, next)

def is.text(+bs: B.Bytes, s: String) -> Bool:
  B.beq(bs, B.utf8(s))

# A message, as the deck takes it: replies and refusals for its requests and queue events count
# while live; play reports from the player list on (the core's rule for events: counts).
def message.on(m: Model.Msg, live: Bool, counts: Bool, +d: D.Deck, +caps: Model.Caps,
    +next: U32) -> D.Did:
  match m:
    case Model.Reply{+id}:
      match live:
        case True{}:
          reply.on(D.answers.listing(d, id), D.answers.ask(d, id), d, id, caps, next)
        case False{}:
          none(d, next)
    case Model.Refused{+id, _, _}:
      match live:
        case True{}:
          refused.on(Bool.or(D.answers.listing(d, id), D.answers.ask(d, id)), d, id, next)
        case False{}:
          none(d, next)
    case Model.Happened{+ev, +object}:
      happened.on(is.text(ev, "queue_updated"), is.text(ev, "queue_items_updated"),
        Bool.and(is.text(ev, "media_item_played"), counts), live, d, object, caps, next)
    case _:
      none(d, next)

# Whether events count in this phase (from the player list on).
def events.count(ph: K.Phase) -> Bool:
  match ph:
    case K.Listing{}:
      True{}
    case K.Live{}:
      True{}
    case _:
      False{}

def input.on(ev: K.Input, +before: K.Phase, +d: D.Deck, +next: U32) -> D.Did:
  match ev:
    case K.MaHeard{h}:
      match h:
        case L.Message{+caps}:
          message.on(Model.classify(caps), K.is.live(before), events.count(before), d, caps, next)
        case _:
          none(d, next)
    case _:
      none(d, next)

# The deck after an input: the session just went live (ask for the queue list), it is over
# (nothing), or the input as the deck takes it in the phase it came in.
def input(went_live: Bool, over: Bool, +ev: K.Input, +before: K.Phase, +d: D.Deck, +next: U32)
    -> D.Did:
  match went_live:
    case True{}:
      D.listing(d, next)
    case False{}:
      match over:
        case True{}:
          none(d, next)
        case False{}:
          input.on(ev, before, d, next)

# The step
# --------

# The core's step, then the deck's: the core's actions first, then the deck's requests and (live
# only) its windows.
def step(t0: Top, +t: K.Time, +ev: K.Input) -> Out:
  match t0:
    case Top{+core, +deck, +next}:
      +o = K.step(core, t, ev)
      +before = K.core.phase(core)
      +after = K.core.phase(K.out.core(o))
      +x = input(Bool.and(Bool.not(K.is.live(before)), K.is.live(after)), K.is.over(after), ev,
        before, deck, next)
      Out{Top{K.out.core(o), D.did.deck(x), D.did.next(x)},
        List.append(&2, K.Action, K.out.actions(o), did.acts(x, K.is.live(after), K.out.core(o)))}
