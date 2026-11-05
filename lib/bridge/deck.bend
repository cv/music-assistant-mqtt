import Base
import ../wire/bytes.bend as B
import ../wire/json.bend as J
import ../ma/api.bend as Api
import ../ma/model.bend as Model
# The queue window each player shows: its last plays (wherever they came from) and the next items
# of its Music Assistant queue. Pure: the core hands it what Music Assistant says and gets back the
# requests to send (reads only: player_queues/all, player_queues/items) and the players whose
# window changed; the core decides when to send and publish (never before the session is live).

# How many plays and items a window holds on each side.
def window() -> Nat:
  5n

# A play as the window shows it.
type Heard is Data:
  Heard{artist: B.Bytes, title: B.Bytes, duration: U32, seconds: U32}

# A player's last plays, newest first (at most window()).
type Recent is Data:
  Recent{player: B.Bytes, heard: List<&2, Heard>}

# A queue (a player's): where it stands and its next items (at most window()).
type Spot is Data:
  Spot{queue: B.Bytes, index: U32, count: U32, next: List<&2, Model.Item>}

# A request for a queue's items waiting for its answer: its message id, the queue, the index it was
# asked at (an answer for an older index is ignored).
type Ask is Data:
  Ask{id: U32, queue: B.Bytes, index: U32}

# listing: the message id of the player_queues/all request waiting (0: none).
type Deck is Data:
  Deck{spots: List<&2, Spot>, asks: List<&2, Ask>, recent: List<&2, Recent>, listing: U32}

# A request to send.
type Request is Data:
  Request{id: U32, c: Api.Command}

# What a change gives: the deck, the next message id, the requests, the players to republish.
type Did is Data:
  Did{deck: Deck, next: U32, requests: List<&2, Request>, shows: List<&2, B.Bytes>}

def empty() -> Deck:
  Deck{Nil{}, Nil{}, Nil{}, 0}

# A new session's deck: the last plays carried over, nothing else.
def fresh(recent: List<&2, Recent>) -> Deck:
  Deck{Nil{}, Nil{}, recent, 0}

def deck.recent(d: Deck) -> List<&2, Recent>:
  match d:
    case Deck{_, _, +r, _}:
      r

def did.deck(x: Did) -> Deck:
  match x:
    case Did{+d, _, _, _}:
      d

def did.next(x: Did) -> U32:
  match x:
    case Did{_, +n, _, _}:
      n

def did.requests(x: Did) -> List<&2, Request>:
  match x:
    case Did{_, _, +r, _}:
      r

def did.shows(x: Did) -> List<&2, B.Bytes>:
  match x:
    case Did{_, _, _, +s}:
      s

def nothing(+d: Deck, +next: U32) -> Did:
  Did{d, next, Nil{}, Nil{}}

# Lookups by id
# -------------

def spot.queue(s: Spot) -> B.Bytes:
  match s:
    case Spot{+q, _, _, _}:
      q

def spot.find.if(hit: Bool, s: Spot, rest: Maybe<&2, Spot>) -> Maybe<&2, Spot>:
  match hit:
    case True{}:
      Some{s}
    case False{}:
      rest

def spot.find(ss: List<&2, Spot>, +q: B.Bytes) -> Maybe<&2, Spot>:
  match ss:
    case Nil{}:
      None{}
    case +s <> t:
      spot.find.if(B.beq(spot.queue(s), q), s, spot.find(t, q))

def spot.drop.if(hit: Bool, s: Spot, rest: List<&2, Spot>) -> List<&2, Spot>:
  match hit:
    case True{}:
      rest
    case False{}:
      s <> rest

def spot.drop(ss: List<&2, Spot>, +q: B.Bytes) -> List<&2, Spot>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      spot.drop.if(B.beq(spot.queue(s), q), s, spot.drop(t, q))

# The spots with this one in place of any for its queue.
def spot.put(+ss: List<&2, Spot>, +s: Spot) -> List<&2, Spot>:
  s <> spot.drop(ss, spot.queue(s))

def ask.id(a: Ask) -> U32:
  match a:
    case Ask{+i, _, _}:
      i

def ask.answers(+a: Ask, +id: B.Bytes) -> Bool:
  B.beq(B.utf8(U32.show(ask.id(a))), id)

def ask.find.if(hit: Bool, a: Ask, rest: Maybe<&2, Ask>) -> Maybe<&2, Ask>:
  match hit:
    case True{}:
      Some{a}
    case False{}:
      rest

def ask.find(as: List<&2, Ask>, +id: B.Bytes) -> Maybe<&2, Ask>:
  match as:
    case Nil{}:
      None{}
    case +a <> t:
      ask.find.if(ask.answers(a, id), a, ask.find(t, id))

def ask.drop.if(hit: Bool, a: Ask, rest: List<&2, Ask>) -> List<&2, Ask>:
  match hit:
    case True{}:
      rest
    case False{}:
      a <> rest

def ask.drop(as: List<&2, Ask>, +id: B.Bytes) -> List<&2, Ask>:
  match as:
    case Nil{}:
      Nil{}
    case +a <> t:
      ask.drop.if(ask.answers(a, id), a, ask.drop(t, id))

def is.some(m: Maybe<&2, Ask>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# Whether a reply with this id answers the queue list, or a queue's items.
def answers.listing(d: Deck, +id: B.Bytes) -> Bool:
  match d:
    case Deck{_, _, _, +l}:
      Bool.and(Bool.not(U32.is_eq(l, 0)), B.beq(B.utf8(U32.show(l)), id))

def answers.ask(d: Deck, +id: B.Bytes) -> Bool:
  match d:
    case Deck{_, +as, _, _}:
      is.some(ask.find(as, id))

# Asking
# ------

# The next items after the current one.
def items.of(+q: B.Bytes, +index: U32) -> Api.Command:
  Api.QueueItems{q, (index + 1 : U32), U32.from_nat(window())}

# Ask for the queue list (when the session goes live).
def listing(d: Deck, +next: U32) -> Did:
  match d:
    case Deck{+ss, +as, +r, _}:
      Did{Deck{ss, as, r, next}, (next + 1 : U32), [Request{next, Api.ListQueues{}}], Nil{}}

def spot.next.of(m: Maybe<&2, Spot>) -> List<&2, Model.Item>:
  match m:
    case Some{+s}:
      match s:
        case Spot{_, _, _, +n}:
          n
    case None{}:
      Nil{}

def place.ask(more: Bool, +id: B.Bytes, +index: U32, +count: U32, +ss: List<&2, Spot>,
    as: List<&2, Ask>, r: List<&2, Recent>, l: U32, +next: U32) -> Did:
  match more:
    case True{}:
      Did{Deck{spot.put(ss, Spot{id, index, count, spot.next.of(spot.find(ss, id))}),
          Ask{next, id, index} <> as, r, l},
        (next + 1 : U32), [Request{next, items.of(id, index)}], Nil{}}
    case False{}:
      Did{Deck{spot.put(ss, Spot{id, index, count, Nil{}}), as, r, l}, next, Nil{}, [id]}

# A queue's new place: kept, and its items after the current one asked for when it has any (the
# next ones it shows stay until the answer); one with nothing after shows none.
def place(q: Model.Queue, d: Deck, +next: U32) -> Did:
  match q:
    case Model.Queue{+id, +index, +count}:
      match d:
        case Deck{+ss, +as, +r, +l}:
          place.ask(((index + 1 : U32) < count : U32), id, index, count, ss, as, r, l, next)

def spot.same(m: Maybe<&2, Spot>, +index: U32, +count: U32) -> Bool:
  match m:
    case Some{+s}:
      match s:
        case Spot{_, +i, +c, _}:
          Bool.and(U32.is_eq(i, index), U32.is_eq(c, count))
    case None{}:
      False{}

def updated.if(same: Bool, +d: Deck, +q: Model.Queue, +next: U32) -> Did:
  match same:
    case True{}:
      nothing(d, next)
    case False{}:
      place(q, d, next)

def deck.spots(d: Deck) -> List<&2, Spot>:
  match d:
    case Deck{+ss, _, _, _}:
      ss

def queue.id(q: Model.Queue) -> B.Bytes:
  match q:
    case Model.Queue{+i, _, _}:
      i

def queue.index(q: Model.Queue) -> U32:
  match q:
    case Model.Queue{_, +i, _}:
      i

def queue.count(q: Model.Queue) -> U32:
  match q:
    case Model.Queue{_, _, +c}:
      c

# A queue_updated event: only a changed place (index or length) asks again.
def updated(+d: Deck, +q: Model.Queue, +next: U32) -> Did:
  updated.if(spot.same(spot.find(deck.spots(d), queue.id(q)), queue.index(q), queue.count(q)),
    d, q, next)

def items_changed.on(m: Maybe<&2, Spot>, +d: Deck, +next: U32) -> Did:
  match m:
    case Some{+s}:
      match s:
        case Spot{+q, +i, +c, _}:
          place(Model.Queue{q, i, c}, d, next)
    case None{}:
      nothing(d, next)

# A queue_items_updated event (about a queue): its items again, at the place it has.
def items_changed(+d: Deck, +q: B.Bytes, +next: U32) -> Did:
  items_changed.on(spot.find(deck.spots(d), q), d, next)

def did.then(a: Did, b: Did) -> Did:
  match a:
    case Did{_, _, +ra, +sa}:
      match b:
        case Did{+d, +n, +rb, +sb}:
          Did{d, n, List.append(&2, Request, ra, rb), List.append(&2, B.Bytes, sa, sb)}

def listed.loop(qs: List<&2, Model.Queue>, +d: Deck, +next: U32) -> Did:
  match qs:
    case Nil{}:
      nothing(d, next)
    case +q <> t:
      +one = place(q, d, next)
      did.then(one, listed.loop(t, did.deck(one), did.next(one)))

def listing.done(d: Deck) -> Deck:
  match d:
    case Deck{+ss, +as, +r, _}:
      Deck{ss, as, r, 0}

# The queue list arrived: every queue placed and its items asked for.
def listed(+d: Deck, qs: List<&2, Model.Queue>, +next: U32) -> Did:
  listed.loop(qs, listing.done(d), next)

# Answers
# -------

def answered.fresh(fresh: Bool, +s: Spot, d: Deck, +next: U32) -> Did:
  match fresh:
    case False{}:
      nothing(d, next)
    case True{}:
      match d:
        case Deck{+ss, +as, +r, +l}:
          Did{Deck{spot.put(ss, s), as, r, l}, next, Nil{}, [spot.queue(s)]}

def answered.at(m: Maybe<&2, Spot>, +a: Ask, +items: List<&2, Model.Item>, +d: Deck,
    +next: U32) -> Did:
  match m:
    case None{}:
      nothing(d, next)
    case Some{+s}:
      match s:
        case Spot{+q, +i, +c, _}:
          match a:
            case Ask{_, _, +ai}:
              answered.fresh(U32.is_eq(i, ai), Spot{q, i, c, List.take(&2, Model.Item, items,
                window())}, d, next)

def ask.queue(a: Ask) -> B.Bytes:
  match a:
    case Ask{_, +q, _}:
      q

def answered.on(m: Maybe<&2, Ask>, +d: Deck, +id: B.Bytes, +items: List<&2, Model.Item>,
    +next: U32) -> Did:
  match m:
    case None{}:
      nothing(d, next)
    case Some{+a}:
      match d:
        case Deck{+ss, +as, +r, +l}:
          answered.at(spot.find(ss, ask.queue(a)), a, items, Deck{ss, ask.drop(as, id), r, l},
            next)

# A queue's items arrived: its next ones, if it is still at the place they were asked at.
def answered(+d: Deck, +id: B.Bytes, +items: List<&2, Model.Item>, +next: U32) -> Did:
  match d:
    case Deck{+ss, +as, +r, +l}:
      answered.on(ask.find(as, id), Deck{ss, as, r, l}, id, items, next)

# A refusal for one of the deck's requests: forgotten.
def refused(+d: Deck, +id: B.Bytes) -> Deck:
  match d:
    case Deck{+ss, +as, +r, +l}:
      Deck{ss, ask.drop(as, id), r, 0}

# Plays
# -----

def recent.player(r: Recent) -> B.Bytes:
  match r:
    case Recent{+p, _}:
      p

def recent.heard(m: Maybe<&2, Recent>) -> List<&2, Heard>:
  match m:
    case Some{+r}:
      match r:
        case Recent{_, +h}:
          h
    case None{}:
      Nil{}

def recent.find.if(hit: Bool, r: Recent, rest: Maybe<&2, Recent>) -> Maybe<&2, Recent>:
  match hit:
    case True{}:
      Some{r}
    case False{}:
      rest

def recent.find(rs: List<&2, Recent>, +p: B.Bytes) -> Maybe<&2, Recent>:
  match rs:
    case Nil{}:
      None{}
    case +r <> t:
      recent.find.if(B.beq(recent.player(r), p), r, recent.find(t, p))

def recent.drop.if(hit: Bool, r: Recent, rest: List<&2, Recent>) -> List<&2, Recent>:
  match hit:
    case True{}:
      rest
    case False{}:
      r <> rest

def recent.drop(rs: List<&2, Recent>, +p: B.Bytes) -> List<&2, Recent>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      recent.drop.if(B.beq(recent.player(r), p), r, recent.drop(t, p))

# A finished play (any player): first among its player's last plays, which keep window() at most.
def played(p: Model.Play, d: Deck, +next: U32) -> Did:
  match p:
    case Model.Play{+item, +seconds, _, _, +player}:
      match item:
        case Model.Media{_, +title, +artist, _, +duration}:
          match d:
            case Deck{+ss, +as, +r, +l}:
              Did{Deck{ss, as, Recent{player, List.take(&2, Heard, Heard{artist, title, duration,
                  seconds} <> recent.heard(recent.find(r, player)), window())}
                  <> recent.drop(r, player), l},
                next, Nil{}, [player]}

# The window
# ----------

def heard.json(h: Heard) -> B.Bytes:
  match h:
    case Heard{+a, +t, +d, +s}:
      J.object([J.Field{"artist", J.string(a)}, J.Field{"title", J.string(t)},
        J.Field{"duration", J.number(d)}, J.Field{"seconds", J.number(s)}])

def heard.all(hs: List<&2, Heard>) -> List<&2, B.Bytes>:
  match hs:
    case Nil{}:
      Nil{}
    case h <> t:
      heard.json(h) <> heard.all(t)

def item.json(i: Model.Item) -> B.Bytes:
  match i:
    case Model.Item{+id, +name, +d, +uri}:
      J.object([J.Field{"id", J.string(id)}, J.Field{"name", J.string(name)},
        J.Field{"duration", J.number(d)}, J.Field{"uri", J.string(uri)}])

def items.all(xs: List<&2, Model.Item>) -> List<&2, B.Bytes>:
  match xs:
    case Nil{}:
      Nil{}
    case i <> t:
      item.json(i) <> items.all(t)

def spot.index.of(m: Maybe<&2, Spot>) -> U32:
  match m:
    case Some{+s}:
      match s:
        case Spot{_, +i, _, _}:
          i
    case None{}:
      0

# A player's window as published: its last plays (oldest first), its queue's next items, the
# queue's id (to play an item) and the current index.
def json(d: Deck, +player: B.Bytes) -> B.Bytes:
  match d:
    case Deck{+ss, _, +r, _}:
      J.object([
        J.Field{"previous", J.array(heard.all(List.reverse(&2, Heard,
          recent.heard(recent.find(r, player)))))},
        J.Field{"next", J.array(items.all(spot.next.of(spot.find(ss, player))))},
        J.Field{"queue", J.string(player)},
        J.Field{"index", J.number(spot.index.of(spot.find(ss, player)))}])
