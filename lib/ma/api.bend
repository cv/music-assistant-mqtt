import Base
import ../wire/bytes.bend as B
import ../wire/json.bend as J
# Music Assistant's websocket API as far as the bridge uses it: the commands it sends (log in, list
# the players, look an item up in the library, list the queues, read a queue's items: all reads,
# nothing that controls a player) and the paths it keeps of what the server sends (Api.wants).
# What those values mean is model.bend.

# A command to the server.
type Command is Data:
  Login{token: String}
  ListPlayers{}
  Lookup{uri: B.Bytes}
  ListQueues{}
  QueueItems{queue: B.Bytes, offset: U32, limit: U32}

def command.name(c: Command) -> String:
  match c:
    case Login{_}:
      "auth"
    case ListPlayers{}:
      "players/all"
    case Lookup{_}:
      "music/item_by_uri"
    case ListQueues{}:
      "player_queues/all"
    case QueueItems{_, _, _}:
      "player_queues/items"

def command.args(c: Command) -> List<&2, J.Field>:
  match c:
    case Login{token}:
      [J.Field{"token", J.text(token)}]
    case ListPlayers{}:
      Nil{}
    case Lookup{uri}:
      [J.Field{"uri", J.string(uri)}]
    case ListQueues{}:
      Nil{}
    case QueueItems{queue, offset, limit}:
      [J.Field{"queue_id", J.string(queue)}, J.Field{"limit", J.number(limit)},
       J.Field{"offset", J.number(offset)}]

# A command as sent: its message id (the server answers with it, as a string), name and arguments.
def encode(+id: U32, +c: Command) -> B.Bytes:
  J.object([J.Field{"message_id", J.text(U32.show(id))},
    J.Field{"command", J.text(command.name(c))},
    J.Field{"args", J.object(command.args(c))}])

# Wanted paths
# ------------

def k(s: String) -> J.Pat:
  J.PKey{B.utf8(s)}

# The prefix with each field after it, one path per field.
def paths(+prefix: List<&2, J.Pat>, fields: List<&2, String>) -> J.Wants:
  match fields:
    case Nil{}:
      Nil{}
    case f <> t:
      List.append(&2, J.Pat, prefix, [k(f)]) <> paths(prefix, t)

# What a player says about itself (in players/all's list and in player_updated events).
def player_fields() -> List<&2, String>:
  ["player_id", "name", "available", "playback_state", "active_source", "synced_to",
   "volume_level"]

# What it is playing.
def media_fields() -> List<&2, String>:
  ["uri", "title", "artist", "album", "duration"]

# A play report (media_item_played).
def play_fields() -> List<&2, String>:
  ["uri", "name", "artist", "album", "duration", "seconds_played", "fully_played", "is_playing",
   "player_id"]

# Where a queue stands (in player_queues/all's list and in queue_updated events).
def queue_fields() -> List<&2, String>:
  ["queue_id", "current_index", "items"]

# A queue item (player_queues/items' list): its id, "Artist - Title", its length.
def item_fields() -> List<&2, String>:
  ["queue_item_id", "name", "duration"]

# Every path the bridge keeps; everything else is scanned and dropped (device details, MAC and IP
# addresses, artwork, metadata: none of it is wanted, so none of it can be published).
def wants() -> J.Wants:
  List.concat(&2, List<&2, J.Pat>, [
    paths(Nil{}, ["server_version", "message_id", "error_code", "details", "event", "object_id"]),
    paths([k("result")], ["authenticated"]),
    paths([k("result"), k("provider_mappings"), J.PAny{}], ["provider_domain", "item_id"]),
    [[k("result"), k("external_ids"), J.PAny{}, J.PAny{}]],
    paths([k("result"), J.PAny{}], player_fields()),
    paths([k("result"), J.PAny{}, k("current_media")], media_fields()),
    paths([k("data")], List.append(&2, String, player_fields(), play_fields())),
    paths([k("data"), k("current_media")], media_fields()),
    paths([k("result"), J.PAny{}], List.append(&2, String, queue_fields(), item_fields())),
    paths([k("result"), J.PAny{}, k("media_item")], ["uri"]),
    paths([k("data")], queue_fields())])
