import Base
import ../wire/bytes.bend as B
import ../wire/json.bend as J
import ./api.bend as Api
# What a message from Music Assistant says, read from the values the scanner kept (Api.wants):
# a hello, a reply to one of our commands, a refusal, or an event; and in them, players, play
# reports and the catalog ids of a library item. Missing values read as empty (or 0, or false).

def Caps() -> Data:
  List<&2, J.Cap>

def read.on_scan(m: Maybe<&2, List<&2, J.Cap>>) -> Caps:
  match m:
    case None{}:
      Nil{}
    case Some{caps}:
      caps

# The values a message keeps (none when it isn't whole JSON).
def read(bs: B.Bytes) -> Caps:
  read.on_scan(J.scan(Api.wants(), bs))

# Paths and lookups
# -----------------

def seg.eq(a: J.Seg, b: J.Seg) -> Bool:
  match a:
    case J.SKey{x}:
      match b:
        case J.SKey{y}:
          B.beq(x, y)
        case J.SIdx{_}:
          False{}
    case J.SIdx{i}:
      match b:
        case J.SKey{_}:
          False{}
        case J.SIdx{j}:
          U32.is_eq(i, j)

# eq, then whether these levels are equal (only compared while all levels so far are).
def seg.eq.if(eq: Bool, x: J.Seg, y: J.Seg) -> Bool:
  match eq:
    case True{}:
      seg.eq(x, y)
    case False{}:
      False{}

# The recursion behind segs.eq. eq: whether the levels taken so far are equal; each step compares
# the heads it takes apart, so neither path is copied.
def segs.loop(a: List<&2, J.Seg>, b: List<&2, J.Seg>, eq: Bool) -> Bool:
  match a b:
    case Nil{} Nil{}:
      eq
    case Con{x, xs} Con{y, ys}:
      segs.loop(xs, ys, seg.eq.if(eq, x, y))
    case _ _:
      False{}

def segs.eq(+a: List<&2, J.Seg>, +b: List<&2, J.Seg>) -> Bool:
  segs.loop(a, b, True{})

def cap.path(c: J.Cap) -> List<&2, J.Seg>:
  match c:
    case J.Cap{p, _}:
      p

def cap.val(c: J.Cap) -> J.Val:
  match c:
    case J.Cap{_, v}:
      v

# A kept value if its path is path.
def get.here.if(eq: Bool, v: J.Val) -> Maybe<&2, J.Val>:
  match eq:
    case True{}:
      Some{v}
    case False{}:
      None{}

def get.here(c: J.Cap, +path: List<&2, J.Seg>) -> Maybe<&2, J.Val>:
  match c:
    case J.Cap{p, v}:
      get.here.if(segs.eq(p, path), v)

# found, else the value of c if it is at path (kept values after a hit are dropped, not compared).
def get.or(found: Maybe<&2, J.Val>, c: J.Cap, +path: List<&2, J.Seg>) -> Maybe<&2, J.Val>:
  match found:
    case Some{v}:
      Some{v}
    case None{}:
      get.here(c, path)

# The recursion behind get. found: the value of a kept value taken so far whose path matched; the
# kept values are taken one by one (only the path is copied, once per value).
def get.loop(caps: Caps, +path: List<&2, J.Seg>, found: Maybe<&2, J.Val>) -> Maybe<&2, J.Val>:
  match caps:
    case Nil{}:
      found
    case c <> t:
      get.loop(t, path, get.or(found, c, path))

# The value kept at path, if any.
def get(+caps: Caps, +path: List<&2, J.Seg>) -> Maybe<&2, J.Val>:
  get.loop(caps, path, None{})

def key(s: String) -> J.Seg:
  J.SKey{B.utf8(s)}

# A path of keys.
def at(names: List<&2, String>) -> List<&2, J.Seg>:
  match names:
    case Nil{}:
      Nil{}
    case n <> t:
      key(n) <> at(t)

# The value of a field under prefix.
def field(+caps: Caps, +prefix: List<&2, J.Seg>, name: String) -> Maybe<&2, J.Val>:
  get(caps, List.append(&2, J.Seg, prefix, [key(name)]))

# Values
# ------

def text(v: J.Val) -> B.Bytes:
  match v:
    case J.Str{bs}:
      bs
    case J.Num{t}:
      t
    case _:
      Nil{}

def text.of(m: Maybe<&2, J.Val>) -> B.Bytes:
  match m:
    case None{}:
      Nil{}
    case Some{v}:
      text(v)

def is_digit_head(+bs: B.Bytes) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case b <> _:
      Bool.and((b >= 48 : U32), (b <= 57 : U32))

# digit: is_digit_head(bs). A number's whole part (seconds and volumes are whole; 2.5 reads 2).
def digits.loop(+bs: B.Bytes, +acc: U32, digit: Bool) -> U32:
  match bs:
    case Nil{}:
      acc
    case b <> t:
      match digit:
        case True{}:
          digits.loop(t, ((acc * 10) + (b - 48) : U32), is_digit_head(t))
        case False{}:
          acc

def digits(+bs: B.Bytes) -> U32:
  digits.loop(bs, 0, is_digit_head(bs))

def number.of(m: Maybe<&2, J.Val>) -> U32:
  match m:
    case Some{v}:
      match v:
        case J.Num{t}:
          digits(t)
        case _:
          0
    case None{}:
      0

def flag.of(m: Maybe<&2, J.Val>) -> Bool:
  match m:
    case Some{v}:
      match v:
        case J.Yes{}:
          True{}
        case _:
          False{}
    case None{}:
      False{}

def is_some(m: Maybe<&2, J.Val>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{_}:
      True{}

# Messages
# --------

# What a message is.
type Msg is Data:
  Hello{version: B.Bytes}                             # the server's first message
  Reply{id: B.Bytes}                                  # a result for one of our commands
  Refused{id: B.Bytes, code: U32, details: B.Bytes}   # an error for one of our commands
  Happened{event: B.Bytes, object: B.Bytes}           # an event, about object (a uri or a player)
  Unknown{}

def classify.on(event: Maybe<&2, J.Val>, error: Maybe<&2, J.Val>, id: Maybe<&2, J.Val>,
    hello: Maybe<&2, J.Val>, +caps: Caps) -> Msg:
  match event:
    case Some{e}:
      Happened{text(e), text.of(get(caps, at(["object_id"])))}
    case None{}:
      match error:
        case Some{code}:
          Refused{text.of(get(caps, at(["message_id"]))), digits(text(code)),
            text.of(get(caps, at(["details"])))}
        case None{}:
          match id:
            case Some{i}:
              Reply{text(i)}
            case None{}:
              match hello:
                case Some{v}:
                  Hello{text(v)}
                case None{}:
                  Unknown{}

def classify(+caps: Caps) -> Msg:
  classify.on(get(caps, at(["event"])), get(caps, at(["error_code"])),
    get(caps, at(["message_id"])), get(caps, at(["server_version"])), caps)

# Whether a reply says the login worked.
def logged_in(+caps: Caps) -> Bool:
  flag.of(get(caps, at(["result", "authenticated"])))

# Players and plays
# -----------------

# What is playing: a library uri, title, artist, album, duration in seconds.
type Media is Data:
  Media{uri: B.Bytes, title: B.Bytes, artist: B.Bytes, album: B.Bytes, duration: U32}

# A player's state: whether it is there, playing/paused/idle, the source it plays (its own queue
# or another), the player it follows when grouped, its volume.
type Status is Data:
  Status{available: Bool, state: B.Bytes, source: B.Bytes, synced_to: B.Bytes, volume: U32}

type Player is Data:
  Player{id: B.Bytes, name: B.Bytes, status: Status, media: Media}

# A play report: the item, seconds heard, whether it counts as fully played, whether it is final
# (the item ended or was left; otherwise a report in progress), the player.
type Play is Data:
  Play{item: Media, seconds: U32, fully: Bool, final: Bool, player: B.Bytes}

def media(+caps: Caps, +prefix: List<&2, J.Seg>) -> Media:
  +m = List.append(&2, J.Seg, prefix, [key("current_media")])
  Media{text.of(field(caps, m, "uri")), text.of(field(caps, m, "title")),
    text.of(field(caps, m, "artist")), text.of(field(caps, m, "album")),
    number.of(field(caps, m, "duration"))}

# The player described under prefix ([data] in an event, [result, i] in players/all's list).
def player(+caps: Caps, +prefix: List<&2, J.Seg>) -> Player:
  Player{text.of(field(caps, prefix, "player_id")), text.of(field(caps, prefix, "name")),
    Status{flag.of(field(caps, prefix, "available")),
      text.of(field(caps, prefix, "playback_state")),
      text.of(field(caps, prefix, "active_source")), text.of(field(caps, prefix, "synced_to")),
      number.of(field(caps, prefix, "volume_level"))},
    media(caps, prefix)}

def list.at(+i: U32) -> List<&2, J.Seg>:
  [key("result"), J.SIdx{i}]

# found: whether the list has an entry i. At most fuel players.
def players.loop(fuel: Nat, +caps: Caps, +i: U32, found: Bool) -> List<&2, Player>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      match found:
        case False{}:
          Nil{}
        case True{}:
          player(caps, list.at(i))
            <> players.loop(f, caps, (i + 1 : U32),
                 is_some(field(caps, list.at((i + 1 : U32)), "player_id")))

# The players of a players/all reply, in order (at most 256).
def players(+caps: Caps) -> List<&2, Player>:
  players.loop(256n, caps, 0, is_some(field(caps, list.at(0), "player_id")))

# The play report of a media_item_played event.
def play(+caps: Caps) -> Play:
  +d = at(["data"])
  Play{Media{text.of(field(caps, d, "uri")), text.of(field(caps, d, "name")),
      text.of(field(caps, d, "artist")), text.of(field(caps, d, "album")),
      number.of(field(caps, d, "duration"))},
    number.of(field(caps, d, "seconds_played")), flag.of(field(caps, d, "fully_played")),
    Bool.not(flag.of(field(caps, d, "is_playing"))), text.of(field(caps, d, "player_id"))}

# Queues
# ------

# Where a queue stands: its id (a player's), the current item's index, how many items it has.
type Queue is Data:
  Queue{id: B.Bytes, index: U32, count: U32}

# A queue item: its id (to play it), "Artist - Title" as Music Assistant names it, its length (s),
# its uri, its artwork's address (empty unless reachable from anywhere).
type Item is Data:
  Item{id: B.Bytes, name: B.Bytes, duration: U32, uri: B.Bytes, image: B.Bytes}

def queue(+caps: Caps, +prefix: List<&2, J.Seg>) -> Queue:
  Queue{text.of(field(caps, prefix, "queue_id")), number.of(field(caps, prefix, "current_index")),
    number.of(field(caps, prefix, "items"))}

def queues.loop(fuel: Nat, +caps: Caps, +i: U32, found: Bool) -> List<&2, Queue>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      match found:
        case False{}:
          Nil{}
        case True{}:
          queue(caps, list.at(i))
            <> queues.loop(f, caps, (i + 1 : U32),
                 is_some(field(caps, list.at((i + 1 : U32)), "queue_id")))

# The queues of a player_queues/all reply, in order (at most 256).
def queues(+caps: Caps) -> List<&2, Queue>:
  queues.loop(256n, caps, 0, is_some(field(caps, list.at(0), "queue_id")))

def image.if(remote: Bool, path: B.Bytes) -> B.Bytes:
  match remote:
    case True{}:
      path
    case False{}:
      Nil{}

def item(+caps: Caps, +prefix: List<&2, J.Seg>) -> Item:
  +img = List.append(&2, J.Seg, prefix, [key("image")])
  Item{text.of(field(caps, prefix, "queue_item_id")), text.of(field(caps, prefix, "name")),
    number.of(field(caps, prefix, "duration")),
    text.of(field(caps, List.append(&2, J.Seg, prefix, [key("media_item")]), "uri")),
    image.if(flag.of(field(caps, img, "remotely_accessible")), text.of(field(caps, img, "path")))}

def items.loop(fuel: Nat, +caps: Caps, +i: U32, found: Bool) -> List<&2, Item>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      match found:
        case False{}:
          Nil{}
        case True{}:
          item(caps, list.at(i))
            <> items.loop(f, caps, (i + 1 : U32),
                 is_some(field(caps, list.at((i + 1 : U32)), "queue_item_id")))

# The items of a player_queues/items reply, in order (at most 64).
def items(+caps: Caps) -> List<&2, Item>:
  items.loop(64n, caps, 0, is_some(field(caps, list.at(0), "queue_item_id")))

# A play report's artwork (its image_url; empty when it has none).
def play.image(+caps: Caps) -> B.Bytes:
  text.of(field(caps, at(["data"]), "image_url"))

# Catalog ids
# -----------

# A library item's ids elsewhere: Apple Music's catalog id, Spotify's, the ISRC (empty: none).
type Ids is Data:
  Ids{apple: B.Bytes, spotify: B.Bytes, isrc: B.Bytes}

# The value under base, then entry i, then the rest.
def probe(+caps: Caps, +base: List<&2, J.Seg>, +rest: List<&2, J.Seg>, +i: U32)
    -> Maybe<&2, J.Val>:
  get(caps, List.append(&2, J.Seg, base, J.SIdx{i} <> rest))

# present: whether entry i exists; hit: whether its value is want. At most fuel entries.
def find.loop(fuel: Nat, +caps: Caps, +base: List<&2, J.Seg>, +rest: List<&2, J.Seg>,
    +want: B.Bytes, +i: U32, present: Bool, hit: Bool) -> Maybe<&2, U32>:
  match fuel:
    case 0n:
      None{}
    case 1n+f:
      match present:
        case False{}:
          None{}
        case True{}:
          match hit:
            case True{}:
              Some{i}
            case False{}:
              find.loop(f, caps, base, rest, want, (i + 1 : U32),
                is_some(probe(caps, base, rest, (i + 1 : U32))),
                B.beq(text.of(probe(caps, base, rest, (i + 1 : U32))), want))

# The first entry under base whose value at rest is want.
def find(+caps: Caps, +base: List<&2, J.Seg>, +rest: List<&2, J.Seg>, +want: B.Bytes)
    -> Maybe<&2, U32>:
  find.loop(64n, caps, base, rest, want, 0, is_some(probe(caps, base, rest, 0)),
    B.beq(text.of(probe(caps, base, rest, 0)), want))

# The value at rest of entry i under base, if there is an i.
def pick(m: Maybe<&2, U32>, +caps: Caps, +base: List<&2, J.Seg>, +rest: List<&2, J.Seg>)
    -> B.Bytes:
  match m:
    case None{}:
      Nil{}
    case Some{i}:
      text.of(probe(caps, base, rest, i))

# The id a provider gives the item (provider_mappings' item_id for that provider_domain).
def mapping(+caps: Caps, domain: String) -> B.Bytes:
  +base = at(["result", "provider_mappings"])
  pick(find(caps, base, at(["provider_domain"]), B.utf8(domain)), caps, base, at(["item_id"]))

# The ids of a music/item_by_uri reply.
def ids(+caps: Caps) -> Ids:
  +base = at(["result", "external_ids"])
  Ids{mapping(caps, "apple_music"), mapping(caps, "spotify"),
    pick(find(caps, base, [J.SIdx{0}], B.utf8("isrc")), caps, base, [J.SIdx{1}])}

# Whether some kept value is exactly these bytes (laws use it: device addresses are never kept).
def holds(caps: Caps, +bs: B.Bytes) -> Bool:
  match caps:
    case Nil{}:
      False{}
    case c <> t:
      Bool.or(B.beq(text(cap.val(c)), bs), holds(t, bs))
