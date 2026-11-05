import Base
import ../wire/bytes.bend as B
import ../wire/json.bend as J
import ../ma/model.bend as Model
# Where things are published and what the payloads say: player slugs, the table of names learned
# this session, the topic strings, the state and play JSON. Pure; the core decides when.

# Slugs
# -----

def slug.byte.if_class(upper: Bool, kept: Bool, +b: U32) -> U32:
  match upper:
    case True{}:
      (b + 32 : U32)
    case False{}:
      match kept:
        case True{}:
          b
        case False{}:
          0

# A name byte in a slug: letters lowercased, digits kept, anything else (spaces, punctuation,
# UTF-8 beyond ASCII) a separator (0).
def slug.byte(+b: U32) -> U32:
  slug.byte.if_class(Bool.and((b >= 65 : U32), (b <= 90 : U32)),
    Bool.or(Bool.and((b >= 97 : U32), (b <= 122 : U32)),
      Bool.and((b >= 48 : U32), (b <= 57 : U32))), b)

def slug.head(+bs: B.Bytes) -> U32:
  match bs:
    case Nil{}:
      0
    case b <> _:
      slug.byte(b)

# c: slug.head(bs), sep: whether it is a separator; gap: a separator is pending (written as one _
# before the next kept byte, so never first, last or doubled); started: a byte was written.
def slug.loop(+bs: B.Bytes, sep: Bool, +c: U32, gap: Bool, +started: Bool) -> B.Bytes:
  match bs:
    case Nil{}:
      Nil{}
    case _ <> t:
      match sep:
        case True{}:
          slug.loop(t, U32.is_eq(slug.head(t), 0), slug.head(t), started, started)
        case False{}:
          match gap:
            case True{}:
              95 <> c <> slug.loop(t, U32.is_eq(slug.head(t), 0), slug.head(t), False{}, True{})
            case False{}:
              c <> slug.loop(t, U32.is_eq(slug.head(t), 0), slug.head(t), False{}, True{})

# A name as one topic level: lowercase letters, digits and single underscores ("Living Room" is
# living_room); never / + # or empty bytes inside.
def slug(+bs: B.Bytes) -> B.Bytes:
  slug.loop(bs, U32.is_eq(slug.head(bs), 0), slug.head(bs), False{}, False{})

# Names
# -----

# A player and the topic level it got this session.
type Named is Data:
  Named{id: B.Bytes, level: B.Bytes}

def Names() -> Data:
  List<&2, Named>

def named.id(n: Named) -> B.Bytes:
  match n:
    case Named{id, _}:
      id

def named.level(n: Named) -> B.Bytes:
  match n:
    case Named{_, level}:
      level

def head.is(+names: Names, +id: B.Bytes) -> Bool:
  match names:
    case Nil{}:
      False{}
    case n <> _:
      B.beq(named.id(n), id)

# hit: head.is(names, id).
def level.loop(+names: Names, +id: B.Bytes, hit: Bool) -> Maybe<&2, B.Bytes>:
  match names:
    case Nil{}:
      None{}
    case n <> t:
      match hit:
        case True{}:
          Some{named.level(n)}
        case False{}:
          level.loop(t, id, head.is(t, id))

# The level a player got, if it has one.
def level.of(+names: Names, +id: B.Bytes) -> Maybe<&2, B.Bytes>:
  level.loop(names, id, head.is(names, id))

# Whether some player already has this level.
def taken(names: Names, +level: B.Bytes) -> Bool:
  match names:
    case Nil{}:
      False{}
    case n <> t:
      Bool.or(B.beq(named.level(n), level), taken(t, level))

def last4(+id: B.Bytes) -> B.Bytes:
  List.drop(&2, U32, id, Nat.sub(List.length(&2, U32, id), 4n))

def or_player(+s: B.Bytes) -> B.Bytes:
  match s:
    case Nil{}:
      B.utf8("player")
    case _:
      s

def candidate.on(+s: B.Bytes, +id: B.Bytes) -> B.Bytes:
  match s:
    case Nil{}:
      or_player(slug(id))
    case _:
      s

# The name's slug; the id's for a name that has none.
def candidate(+name: B.Bytes, +id: B.Bytes) -> B.Bytes:
  candidate.on(slug(name), id)

# The first candidate no one has; when all three are taken (two ids alike once slugged), an
# empty level: the player is known, so it is never renamed, but nothing is published for it.
def learn.new(base_free: Bool, alt_free: Bool, last_free: Bool, +names: Names, +id: B.Bytes,
    +base: B.Bytes, +alt: B.Bytes, +last: B.Bytes) -> Names:
  match base_free:
    case True{}:
      Named{id, base} <> names
    case False{}:
      match alt_free:
        case True{}:
          Named{id, alt} <> names
        case False{}:
          match last_free:
            case True{}:
              Named{id, last} <> names
            case False{}:
              Named{id, Nil{}} <> names

def learn.on(m: Maybe<&2, B.Bytes>, +names: Names, +id: B.Bytes, +name: B.Bytes) -> Names:
  match m:
    case Some{_}:
      names
    case None{}:
      +base = candidate(name, id)
      +alt = B.cat(base, 95 <> slug(last4(id)))
      +last = or_player(slug(id))
      learn.new(Bool.not(taken(names, base)), Bool.not(taken(names, alt)),
        Bool.not(taken(names, last)), names, id, base, alt, last)

# The table with this player in it. A player already in it keeps its level (names learned later
# never rename anyone); a new one gets its name's slug, or with the id's last 4 characters when
# that is taken, or the id's slug when that is too (all checked: no two players share a level).
def learn(+names: Names, +id: B.Bytes, +name: B.Bytes) -> Names:
  learn.on(level.of(names, id), names, id, name)

# Whether no two players share a level (empty levels, which publish nothing, aside).
def unique.entry(+l: B.Bytes, +rest: Names) -> Bool:
  match l:
    case Nil{}:
      True{}
    case _:
      Bool.not(taken(rest, l))

def unique(+names: Names) -> Bool:
  match names:
    case Nil{}:
      True{}
    case n <> t:
      Bool.and(unique.entry(named.level(n), t), unique(t))

# Topics
# ------

def topic.status(prefix: String) -> String:
  prefix ++ "/status"

def topic.state(prefix: String, level: B.Bytes) -> String:
  prefix ++ "/" ++ B.from_utf8(level) ++ "/state"

def topic.played(prefix: String) -> String:
  prefix ++ "/played"

def topic.health(prefix: String, report: String) -> String:
  prefix ++ "/$bridge/" ++ report

# Payloads
# --------

def f(k: String, v: B.Bytes) -> J.Field:
  J.Field{k, v}

# Bytes as a JSON string, or null when there are none.
def opt(bs: B.Bytes) -> B.Bytes:
  match bs:
    case Nil{}:
      J.null()
    case _:
      J.string(bs)

# A player's state: what it is, what it plays. The elapsed time is left out, so the payload
# changes only when something real does. Device details are not in Model.Player at all.
def state(p: Model.Player) -> B.Bytes:
  match p:
    case Model.Player{_, name, status, media}:
      match status:
        case Model.Status{available, playing, source, synced_to, volume}:
          match media:
            case Model.Media{uri, title, artist, album, duration}:
              J.object([f("name", J.string(name)), f("state", J.string(playing)),
                f("available", J.boolean(available)), f("source", opt(source)),
                f("synced_to", opt(synced_to)), f("volume", J.number(volume)),
                f("title", opt(title)), f("artist", opt(artist)), f("album", opt(album)),
                f("uri", opt(uri)), f("duration", J.number(duration))])

# A play: when it ended (Unix seconds), on which player, the item, how much was heard, its ids.
def played(+at: U32, level: B.Bytes, p: Model.Play, ids: Model.Ids) -> B.Bytes:
  match p:
    case Model.Play{item, seconds, fully, _, player}:
      match item:
        case Model.Media{uri, title, artist, album, duration}:
          match ids:
            case Model.Ids{apple, spotify, isrc}:
              J.object([f("at", J.number(at)), f("player", J.string(level)),
                f("player_id", J.string(player)), f("uri", J.string(uri)),
                f("name", J.string(title)), f("artist", opt(artist)), f("album", opt(album)),
                f("duration", J.number(duration)), f("seconds_played", J.number(seconds)),
                f("fully_played", J.boolean(fully)),
                f("ids", J.object([f("apple_music", opt(apple)), f("spotify", opt(spotify))])),
                f("isrc", opt(isrc))])

# The same as one line of the plays file.
def played.line(+at: U32, level: B.Bytes, p: Model.Play, ids: Model.Ids) -> B.Bytes:
  B.cat(played(at, level, p, ids), [10])
