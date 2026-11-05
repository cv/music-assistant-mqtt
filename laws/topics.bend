import Base
import ../lib/wire/bytes.bend as B
import ../lib/ma/model.bend as Model
import ../lib/bridge/topics.bend as T
import ./ma.bend as Lma
# Laws of topics and payloads (lib/bridge/topics.bend).

def u(s: String) -> B.Bytes:
  B.utf8(s)

def first_player(ps: List<&2, Model.Player>) -> Model.Player:
  match ps:
    case Nil{}:
      Model.Player{Nil{}, Nil{}, Model.Status{False{}, Nil{}, Nil{}, Nil{}, 0},
        Model.Media{Nil{}, Nil{}, Nil{}, Nil{}, 0}}
    case p <> _:
      p

# Slugs: lowercase, single underscores, nothing that isn't a letter or a digit.
law slug_examples:
  {[T.slug(u("Living Room")), T.slug(u("  Web (Chrome on Mac) ")),
    T.slug(u("Caf\u{e9} \u{dc}n\u{ef}code")), T.slug(u("///+#"))]
    == [u("living_room"), u("web_chrome_on_mac"), u("caf_n_code"), u("")] : List<&2, B.Bytes>}

def two() -> T.Names:
  T.learn(T.learn(Nil{}, u("RINCON_000000000001400"), u("Living Room")),
    u("RINCON_000000000002400"), u("Living Room"))

# A name another player has gets the id's last 4 characters.
law names_clash_gets_id_suffix:
  {two() == [T.Named{u("RINCON_000000000002400"), u("living_room_2400")},
    T.Named{u("RINCON_000000000001400"), u("living_room")}] : T.Names}

# Learning a player again, under any name, changes nothing: no one is ever renamed in a session.
law names_never_rename:
  for +names: T.Names
  for +id: B.Bytes
  for +first: B.Bytes
  for +later: B.Bytes
  {T.learn(T.learn(names, id, first), id, later) == T.learn(names, id, first) : T.Names}

# For every table whose levels are unique: learning any player keeps them unique, so no two
# players ever publish to the same topic.
law names_unique:
  for +names: T.Names
  for +id: B.Bytes
  for +name: B.Bytes
  for +h: {T.unique(names) == True{} : Bool}
  {T.unique(T.learn(names, id, name)) == True{} : Bool}

# Two ids alike once slugged (case, - and _), both named "Lamp": the second gets the id's last 4;
# a third, whose every candidate is taken, is known with no level (nothing is published for it).
def lamps() -> T.Names:
  T.learn(T.learn(T.learn(T.learn(Nil{}, u("ab_cd"), u("ab cd")), u("Ab-Cd"), u("ab cd")),
    u("x_cd"), u("ab")), u("aB_cD"), u("ab cd"))

law names_all_taken:
  {lamps() == [T.Named{u("aB_cD"), Nil{}}, T.Named{u("x_cd"), u("ab")},
    T.Named{u("Ab-Cd"), u("ab_cd_b_cd")}, T.Named{u("ab_cd"), u("ab_cd")}] : T.Names}

law topics_examples:
  {[T.topic.status("music"), T.topic.state("music", u("living_room")), T.topic.played("music"),
    T.topic.health("music", "uptime_s")]
    == ["music/status", "music/living_room/state", "music/played", "music/$bridge/uptime_s"]
    : List<&2, String>}

# A player's state, from the players/all sample: no device details, no elapsed time.
law state_payload:
  {T.state(first_player(Model.players(Model.read(Lma.sample.players()))))
    == u("{\"name\":\"Kitchen\",\"state\":\"playing\",\"available\":true,\"source\":\""
      ++ "RINCON_000000000001400\",\"synced_to\":\"RINCON_000000000001400\",\"volume\""
      ++ ":2,\"title\":\"Tell Me in a Song\",\"artist\":\"Jacob Jeffries/Vulfmon\",\"a"
      ++ "lbum\":\"Here We Go Jack\",\"uri\":\"library://track/9598\",\"duration\":224"
      ++ "}") : B.Bytes}

# A play with its catalog ids.
law played_payload:
  {T.played(1793864368, u("living_room"), Model.play(Model.read(Lma.sample.played())),
      Model.ids(Model.read(Lma.sample.lookup())))
    == u("{\"at\":1793864368,\"player\":\"living_room\",\"player_id\":\"RINCON_0000000"
      ++ "00001400\",\"uri\":\"library://track/9598\",\"name\":\"Tell Me in a Song\",\""
      ++ "artist\":\"Jacob Jeffries/Vulfmon\",\"album\":\"Here We Go Jack\",\"duration"
      ++ "\":224,\"seconds_played\":150,\"fully_played\":false,\"ids\":{\"apple_music\""
      ++ ":\"1124256898\",\"spotify\":\"7cRrRC0BQutTT09UKpWx8C\"},\"isrc\":\"BRRGE6500"
      ++ "004\"}") : B.Bytes}
