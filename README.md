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

It runs as a container beside Music Assistant (host network). Make a long-lived token in Music
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
`tools/deploy.sh HOST` builds the linux/arm64 binary and starts it there with
[`deploy/compose.yaml`](deploy/compose.yaml): about 1 MB of memory, two threads.

Building needs [Bend](https://github.com/HigherOrderCO/bend) and Docker (for the cross-compile):
`tools/cross-build.sh mam.bend out/mam`.

## How it is made

It's written in Bend, with laws its checker proves: `bend PROOF.bend` checks all 83. The wire
formats are pinned to bytes real peers sent or accepted (RFC 6455's examples, Music Assistant's
messages). Others hold for every input:
- however a socket splits the stream, the decoders read the same;
- a learned player is never renamed;
- the config's summary never shows a secret;
- an ended session does nothing more.

The WebSocket client and the JSON scanner read one byte at a time and keep only the values they
need, so a large message costs no memory. [`AGENTS.md`](AGENTS.md) describes the design and
[`STYLE.md`](STYLE.md) the code's conventions.

## License

MIT
