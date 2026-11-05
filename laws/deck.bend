import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/ma/link.bend as L
import ../lib/bridge/conf.bend as C
import ../lib/bridge/core.bend as K
import ../lib/bridge/deck.bend as D
import ../lib/bridge/top.bend as Tp
# Laws of the queue windows (lib/bridge/deck.bend) and the bridge's step around the core
# (lib/bridge/top.bend).

def u(s: String) -> B.Bytes:
  B.utf8(s)

def conf() -> C.Conf:
  C.read.conf(C.parse(u("ma_token tok\nmqtt_host broker\n")))

def t(+ms: U32) -> K.Time:
  K.Time{ms, (1793864368 + ms / 1000 : U32)}

def msg(s: String) -> K.Input:
  K.MaHeard{L.Message{Model.read(u(s))}}

def show(a: K.Action) -> String:
  match a:
    case K.ToMq{p}:
      match p:
        case M.Publish{_, _, _, topic, _, payload}:
          "pub " ++ topic ++ " " ++ B.from_utf8(payload)
        case _:
          "mq"
    case K.ToMa{+id, c}:
      "ma " ++ B.from_utf8(Api.encode(id, c))
    case K.Log{l}:
      "log " ++ l
    case _:
      "other"

def shows(acts: List<&2, K.Action>) -> String:
  match acts:
    case Nil{}:
      ""
    case a <> rest:
      show(a) ++ " | " ++ shows(rest)

type Ev is Data:
  Ev{at: K.Time, input: K.Input}

def run(steps: List<&2, Ev>, c: Tp.Top, acc: List<&2, String>) -> List<&2, String>:
  match steps:
    case Nil{}:
      List.reverse(&2, String, acc)
    case s <> rest:
      match s:
        case Ev{tm, ev}:
          +o = Tp.step(c, tm, ev)
          run(rest, Tp.out.top(o), shows(Tp.out.actions(o)) <> acc)

def session.on(o: Tp.Out) -> List<&2, String>:
  match o:
    case Tp.Out{c, _}:
      run([
        Ev{t(100), K.MqPacket{M.ConnAck{False{}, 0}}},
        Ev{t(200), K.MaHeard{L.Opened{}}},
        Ev{t(500), msg("{\"server_id\": \"x\", \"server_version\": \"2.10.9\"}")},
        Ev{t(600), msg("{\"message_id\": \"1\", \"result\": {\"authenticated\": true}}")},
        Ev{t(700), msg("{\"message_id\": \"2\", \"result\": [{\"player_id\": \"RINCON_00000000"
          ++ "0001400\", \"name\": \"Living Room\", \"available\": true, \"playback_"
          ++ "state\": \"playing\", \"current_media\": {\"uri\": \"library://track/1"
          ++ "\", \"title\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"du"
          ++ "ration\": 200}, \"active_source\": \"RINCON_000000000001400\", \"synce"
          ++ "d_to\": null, \"volume_level\": 9}, {\"player_id\": \"RINCON_000000000"
          ++ "002400\", \"name\": \"Move 2\", \"available\": true, \"playback_state\""
          ++ ": \"idle\", \"current_media\": null, \"active_source\": null, \"synced"
          ++ "_to\": null, \"volume_level\": 2}]}")},
        Ev{t(800), msg("{\"message_id\": \"2147483648\", \"result\": [{\"queue_id\": \"RINCON_"
          ++ "000000000002400\", \"active\": false, \"display_name\": \"Move 2\", \""
          ++ "available\": true, \"items\": 0, \"shuffle_enabled\": false, \"current"
          ++ "_index\": null, \"state\": \"idle\", \"elapsed_time\": 0.0}, {\"queue_"
          ++ "id\": \"RINCON_000000000001400\", \"active\": true, \"display_name\": "
          ++ "\"Living Room\", \"available\": true, \"items\": 253, \"shuffle_enable"
          ++ "d\": false, \"current_index\": 242, \"state\": \"playing\", \"elapsed_"
          ++ "time\": 210.1787032146454}]}")},
        Ev{t(900), msg("{\"message_id\": \"2147483649\", \"result\": [{\"queue_id\": \"RINCON_"
          ++ "000000000001400\", \"queue_item_id\": \"000000000000000000000000000001"
          ++ "6e\", \"name\": \"Celso Fonseca - Bom Sinal\", \"duration\": 310, \"so"
          ++ "rt_index\": 0, \"streamdetails\": {\"provider\": \"apple_music--0001\""
          ++ ", \"item_id\": \"1443343841\"}, \"media_item\": {\"item_id\": \"1125\""
          ++ ", \"provider\": \"library\", \"name\": \"Bom Sinal\", \"uri\": \"libra"
          ++ "ry://track/1125\", \"duration\": 310, \"artists\": [{\"name\": \"Celso"
          ++ " Fonseca\", \"uri\": \"library://artist/162\"}]}, \"image\": {\"type\""
          ++ ": \"thumb\", \"path\": \"https://example.com/cover.jpg\", \"remotely_a"
          ++ "ccessible\": true}, \"index\": 0, \"available\": true}, {\"queue_id\":"
          ++ " \"RINCON_000000000001400\", \"queue_item_id\": \"00000000000000000000"
          ++ "00000000018f\", \"name\": \"Vulfpeck - Welcome to Vulf Records\", \"du"
          ++ "ration\": 163, \"sort_index\": 1, \"streamdetails\": {\"provider\": \""
          ++ "apple_music--0001\", \"item_id\": \"1877221221\"}, \"media_item\": {\""
          ++ "item_id\": \"10648\", \"provider\": \"library\", \"name\": \"Welcome t"
          ++ "o Vulf Records\", \"uri\": \"library://track/10648\", \"duration\": 16"
          ++ "3, \"artists\": [{\"name\": \"Vulfpeck\", \"uri\": \"library://artist/"
          ++ "953\"}]}, \"image\": {\"type\": \"thumb\", \"path\": \"https://example"
          ++ ".com/cover.jpg\", \"remotely_accessible\": true}, \"index\": 0, \"avai"
          ++ "lable\": true}]}")},
        Ev{t(1000), msg("{\"event\": \"queue_updated\", \"object_id\": \"RINCON_000000000001400"
          ++ "\", \"data\": {\"queue_id\": \"RINCON_000000000001400\", \"active\": t"
          ++ "rue, \"display_name\": \"Living Room\", \"available\": true, \"items\""
          ++ ": 253, \"shuffle_enabled\": false, \"current_index\": 243, \"state\": "
          ++ "\"playing\", \"elapsed_time\": 3.129477867701697, \"current_item\": {\""
          ++ "queue_item_id\": \"000000000000000000000000000002d9\", \"name\": \"Pan"
          ++ "orama do Choro/Izaías Bueno de Almeida - Sorvete de Jabuticaba\", \"du"
          ++ "ration\": 189}}}")},
        Ev{t(1100), msg("{\"event\": \"media_item_played\", \"object_id\": \"library://track/1\""
          ++ ", \"data\": {\"uri\": \"library://track/1\", \"name\": \"Song\", \"art"
          ++ "ist\": \"Band\", \"album\": \"LP\", \"duration\": 200, \"seconds_playe"
          ++ "d\": 12, \"fully_played\": false, \"is_playing\": false, \"player_id\""
          ++ ": \"RINCON_000000000001400\"}}")}], c, Nil{})


# A session with the queue windows: once live, the queue list is asked for with the deck's own
# message ids (from 2^31); a queue with nothing after its current item shows an empty window and
# asks nothing, the other asks for its next 5 and shows them when they come; a queue_updated at a
# new place asks again; a finished play (12 s heard) joins its player's previous ones, beside the
# core's own lookup (id 3).
law top_session:
  {session.on(Tp.start(conf(), t(0), Nil{}, Nil{}))
    == ["other | ",
     "",
     "log Music Assistant 2.10.9 | ma {\"message_id\":\"1\",\"command\":\"au"
       ++ "th\",\"args\":{\"token\":\"tok\"}} | ",
     "ma {\"message_id\":\"2\",\"command\":\"players/all\",\"args\":{}} | ",
     "log live: 2 players | pub music/status online | pub music/living_room/"
       ++ "state {\"name\":\"Living Room\",\"state\":\"playing\",\"available\":tr"
       ++ "ue,\"source\":\"RINCON_000000000001400\",\"synced_to\":null,\"volume\""
       ++ ":9,\"title\":\"Song\",\"artist\":\"Band\",\"album\":\"LP\",\"uri\":\"l"
       ++ "ibrary://track/1\",\"duration\":200} | pub music/move_2/state {\"name\""
       ++ ":\"Move 2\",\"state\":\"idle\",\"available\":true,\"source\":null,\"sy"
       ++ "nced_to\":null,\"volume\":2,\"title\":null,\"artist\":null,\"album\":n"
       ++ "ull,\"uri\":null,\"duration\":0} | ma {\"message_id\":\"2147483648\",\""
       ++ "command\":\"player_queues/all\",\"args\":{}} | ",
     "ma {\"message_id\":\"2147483649\",\"command\":\"player_queues/items\","
       ++ "\"args\":{\"queue_id\":\"RINCON_000000000001400\",\"limit\":5,\"offset"
       ++ "\":243}} | pub music/move_2/queue {\"previous\":[],\"next\":[],\"queue"
       ++ "\":\"RINCON_000000000002400\",\"index\":0} | ",
     "pub music/living_room/queue {\"previous\":[],\"next\":[{\"id\":\"00000"
       ++ "00000000000000000000000016e\",\"name\":\"Celso Fonseca - Bom Sinal\",\""
       ++ "duration\":310,\"uri\":\"library://track/1125\"},{\"id\":\"00000000000"
       ++ "00000000000000000018f\",\"name\":\"Vulfpeck - Welcome to Vulf Records\""
       ++ ",\"duration\":163,\"uri\":\"library://track/10648\"}],\"queue\":\"RINC"
       ++ "ON_000000000001400\",\"index\":242} | ",
     "ma {\"message_id\":\"2147483650\",\"command\":\"player_queues/items\","
       ++ "\"args\":{\"queue_id\":\"RINCON_000000000001400\",\"limit\":5,\"offset"
       ++ "\":244}} | ",
     "ma {\"message_id\":\"3\",\"command\":\"music/item_by_uri\",\"args\":{\""
       ++ "uri\":\"library://track/1\"}} | pub music/living_room/queue {\"previou"
       ++ "s\":[{\"artist\":\"Band\",\"title\":\"Song\",\"duration\":200,\"second"
       ++ "s\":12}],\"next\":[{\"id\":\"0000000000000000000000000000016e\",\"name"
       ++ "\":\"Celso Fonseca - Bom Sinal\",\"duration\":310,\"uri\":\"library://"
       ++ "track/1125\"},{\"id\":\"0000000000000000000000000000018f\",\"name\":\""
       ++ "Vulfpeck - Welcome to Vulf Records\",\"duration\":163,\"uri\":\"librar"
       ++ "y://track/10648\"}],\"queue\":\"RINCON_000000000001400\",\"index\":243"
       ++ "} | "]
    : List<&2, String>}

def heard.count(d: D.Deck, +player: B.Bytes) -> Nat:
  List.length(&2, D.Heard, D.recent.heard(D.recent.find(D.deck.recent(d), player)))

# For every play and deck: the player's last plays are at most window() (5).
law deck_previous_bounded:
  for p: Model.Play
  for d: D.Deck
  for n: U32
  {Nat.is_le(heard.count(D.did.deck(D.played(p, d, n)), K.play.player(p)), D.window()) == True{}
    : Bool}

# For every deck: a queue_updated at the place the queue already has asks nothing.
law deck_unchanged_asks_nothing:
  for +q: B.Bytes
  for +i: U32
  for +c: U32
  for next: List<&2, Model.Item>
  for ss: List<&2, D.Spot>
  for as: List<&2, D.Ask>
  for r: List<&2, D.Recent>
  for l: U32
  for +n: U32
  {D.did.requests(D.updated(D.Deck{D.Spot{q, i, c, next} <> ss, as, r, l}, Model.Queue{q, i, c}, n))
    == Nil{} : List<&2, D.Request>}
