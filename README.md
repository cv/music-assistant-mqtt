# music-assistant-mqtt

Publishes what [Music Assistant](https://music-assistant.io) is playing, and every play, to MQTT.

Music Assistant has no MQTT output. Its plays reach only its scrobblers, which leave out skips,
and its play log keeps one row per track. This bridge listens to Music Assistant's websocket API
and publishes:

| Topic | What | Retained |
|---|---|---|
| `music/status` | `online` / `offline` (also the last will) | yes |
| `music/<player>/state` | what the player is doing: name, state, availability, source, group, volume, title, artist, album, uri, duration | yes |
| `music/played` | a finished play, skips included: when, where, what, how long it was heard, whether fully, its catalog ids (Apple Music, Spotify) and ISRC | no |
| `music/<player>/queue` | the player's window: its last 5 plays (wherever they came from: artist, title, length, seconds heard, uri) and the next 5 items of its queue (id, "Artist - Title", length, uri), with the queue's id and position | yes |
| `music/$bridge/…` | its own health: version, uptime, sessions, why the last one ended, plays, players, memory | yes |

Every play is also appended to a JSON-lines file, the durable history:

```json
{"at":1793870455,"player":"living_room","player_id":"RINCON_…","uri":"library://track/1985",
 "name":"Cory Wong","artist":"Vulfpeck","album":"The Beautiful Game","duration":247,
 "seconds_played":5,"fully_played":false,
 "ids":{"apple_music":"1877219564","spotify":"5G8L62noXXihEkN2P2RiPW"},"isrc":"TCACS1623898"}
```

It only reads: it sends Music Assistant its login, a request for the player list and library
lookups, never a command that controls a player.

## Running it

It runs as a container beside Music Assistant (host network): `ghcr.io/cv/music-assistant-mqtt`, for
linux/amd64 and linux/arm64, one static binary in an otherwise empty image (under 1 MB). Each
[release](https://github.com/cv/music-assistant-mqtt/releases) also has the static binaries. Make a long-lived token in Music
Assistant's UI and an MQTT login that may write `music/#`, then write the config (keep it
`0600`):

```
ma_host 127.0.0.1
ma_port 8095
ma_token <token>
mqtt_host broker.local
mqtt_user music
mqtt_password <password>
plays_file /data/plays.jsonl
```

All the keys are in [`deploy/music-assistant-mqtt.conf.example`](deploy/music-assistant-mqtt.conf.example).
`tools/deploy.sh HOST VERSION` starts that release there with
[`deploy/compose.yaml`](deploy/compose.yaml): about 1 MB of memory, two threads.

Building it yourself needs [Bend](https://github.com/HigherOrderCO/bend) and Docker:
`bend mam.bend -o out/mam.c && docker build -t music-assistant-mqtt .` (the C is portable; zig
cross-compiles it, statically, for the target).

## A queue card for Home Assistant

[`ha/music-queue-card.js`](ha/music-queue-card.js) shows a player's last plays, its media control
and its next items, from `music/<player>/queue`. A tap on a previous play plays it again; a tap on a
next item jumps straight to it (nothing in between is played).

1. An MQTT sensor per player, with the window as its attributes:

   ```yaml
   mqtt:
     sensor:
       - name: "Living Room queue"
         state_topic: "music/living_room/queue"
         value_template: "{{ value_json.index }}"
         json_attributes_topic: "music/living_room/queue"
   ```

2. A REST command for the jump (a Music Assistant token in `secrets.yaml` as `"Bearer <token>"`):

   ```yaml
   rest_command:
     ma_play_queue_item:
       url: "http://127.0.0.1:8095/api"
       method: post
       headers:
         Authorization: !secret ma_queue_token
       content_type: "application/json"
       payload: >-
         {"command": "player_queues/play_index",
          "args": {"queue_id": {{ queue | tojson }}, "index": {{ item | tojson }}}}
   ```

3. The card as a dashboard resource (`/local/music-queue-card.js`, from `config/www/`), then:

   ```yaml
   type: custom:music-queue-card
   entity: media_player.living_room        # shown in the middle
   player: media_player.ma_living_room     # Music Assistant's player, to replay (default: entity)
   queue: sensor.living_room_queue
   previous: 4
   next: 5
   ```

## How it is made

It's written in Bend, with laws its checker proves: `bend PROOF.bend` checks all 110. The wire
formats are pinned to bytes real peers sent or accepted (RFC 6455's examples, Music Assistant's
messages). Others hold for every input:
- only values at the paths it declares ever leave the JSON scanner, so a device's details, MAC or
  IP address can't reach a payload;
- nothing is published before the session is live;
- each finished play is published once: never twice, and never without a final report;
- no two players share a topic;
- however a socket splits the stream, the decoders read the same;
- a learned player is never renamed;
- the config's summary never shows a secret;
- an ended session does nothing more.

The WebSocket client and the JSON scanner read one byte at a time and keep only the values they
need, so a large message costs no memory. [`AGENTS.md`](AGENTS.md) describes the design and
[`STYLE.md`](STYLE.md) the code's conventions.

## License

MIT
