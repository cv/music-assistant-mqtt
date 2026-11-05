import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/mqtt.bend as M
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/ma/link.bend as L
import ../lib/bridge/conf.bend as C
import ../lib/bridge/core.bend as K
import ../lib/bridge/top.bend as Tp

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

def main.on(o: Tp.Out) -> List<&2, String>:
  match o:
    case Tp.Out{c, _}:
      run([
        Ev{t(100), K.MqPacket{M.ConnAck{False{}, 0}}},
        Ev{t(200), K.MaHeard{L.Opened{}}},
        Ev{t(500), msg("{\"server_id\": \"x\", \"server_version\": \"2.10.9\"}")},
        Ev{t(600), msg("{\"message_id\": \"1\", \"result\": {\"authenticated\": true}}")},
        Ev{t(700), msg("{\"message_id\": \"2\", \"result\": [{\"player_id\": \"RINCON_000000000001400\", \"name\": \"Living Room\", \"available\": true, \"playback_state\": \"playing\", \"current_media\": {\"uri\": \"library://track/1\", \"title\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"duration\": 200}, \"active_source\": \"RINCON_000000000001400\", \"synced_to\": null, \"volume_level\": 9}, {\"player_id\": \"RINCON_000000000002400\", \"name\": \"Move 2\", \"available\": true, \"playback_state\": \"idle\", \"current_media\": null, \"active_source\": null, \"synced_to\": null, \"volume_level\": 2}]}")},
        Ev{t(800), msg("{\"message_id\": \"2147483648\", \"result\": [{\"queue_id\": \"RINCON_000000000002400\", \"active\": false, \"display_name\": \"Move 2\", \"available\": true, \"items\": 0, \"shuffle_enabled\": false, \"current_index\": null, \"state\": \"idle\", \"elapsed_time\": 0.0}, {\"queue_id\": \"RINCON_000000000001400\", \"active\": true, \"display_name\": \"Living Room\", \"available\": true, \"items\": 253, \"shuffle_enabled\": false, \"current_index\": 242, \"state\": \"playing\", \"elapsed_time\": 210.1787032146454}]}")},
        Ev{t(900), msg("{\"message_id\": \"2147483649\", \"result\": [{\"queue_id\": \"RINCON_000000000001400\", \"queue_item_id\": \"0000000000000000000000000000016e\", \"name\": \"Celso Fonseca - Bom Sinal\", \"duration\": 310, \"sort_index\": 0, \"streamdetails\": {\"provider\": \"apple_music--0001\", \"item_id\": \"1443343841\"}, \"media_item\": {\"item_id\": \"1125\", \"provider\": \"library\", \"name\": \"Bom Sinal\", \"uri\": \"library://track/1125\", \"duration\": 310, \"artists\": [{\"name\": \"Celso Fonseca\", \"uri\": \"library://artist/162\"}]}, \"image\": {\"type\": \"thumb\", \"path\": \"https://example.com/cover.jpg\", \"remotely_accessible\": true}, \"index\": 0, \"available\": true}, {\"queue_id\": \"RINCON_000000000001400\", \"queue_item_id\": \"0000000000000000000000000000018f\", \"name\": \"Vulfpeck - Welcome to Vulf Records\", \"duration\": 163, \"sort_index\": 1, \"streamdetails\": {\"provider\": \"apple_music--0001\", \"item_id\": \"1877221221\"}, \"media_item\": {\"item_id\": \"10648\", \"provider\": \"library\", \"name\": \"Welcome to Vulf Records\", \"uri\": \"library://track/10648\", \"duration\": 163, \"artists\": [{\"name\": \"Vulfpeck\", \"uri\": \"library://artist/953\"}]}, \"image\": {\"type\": \"thumb\", \"path\": \"https://example.com/cover.jpg\", \"remotely_accessible\": true}, \"index\": 0, \"available\": true}]}")},
        Ev{t(1000), msg("{\"event\": \"queue_updated\", \"object_id\": \"RINCON_000000000001400\", \"data\": {\"queue_id\": \"RINCON_000000000001400\", \"active\": true, \"display_name\": \"Living Room\", \"available\": true, \"items\": 253, \"shuffle_enabled\": false, \"current_index\": 243, \"state\": \"playing\", \"elapsed_time\": 3.129477867701697, \"current_item\": {\"queue_item_id\": \"000000000000000000000000000002d9\", \"name\": \"Panorama do Choro/Izaías Bueno de Almeida - Sorvete de Jabuticaba\", \"duration\": 189}}}")},
        Ev{t(1100), msg("{\"event\": \"media_item_played\", \"object_id\": \"library://track/1\", \"data\": {\"uri\": \"library://track/1\", \"name\": \"Song\", \"artist\": \"Band\", \"album\": \"LP\", \"duration\": 200, \"seconds_played\": 12, \"fully_played\": false, \"is_playing\": false, \"player_id\": \"RINCON_000000000001400\"}}")}], c, Nil{})

def main() -> List<&2, String>:
  main.on(Tp.start(conf(), t(0), Nil{}, Nil{}))
