# Changelog

Each release's section is its notes on GitHub (the release workflow takes it by version).

## 0.6.1 (2026-11-10)

- Built with Bend 2.0.40, on Alpine 3.24 (zig 0.16). Bend 2.0.40's Base declares a `Lost` (a pointer
  event), so the link's end is now `Dropped`; the program behaves the same.
- Home Assistant cards (`ha/`, not in the image): the queue card's next items get a ✕ that removes one
  and adds a similar song at the end (picked like Music Assistant's Autoplay, from the queue's
  sources), a lookup box that adds a song, an artist's songs or a playlist right after the ones shown,
  and every row on two lines (the artist above the title); a new lyrics card
  (`ha/music-lyrics-card.js`): Music Assistant's lyrics for what plays, synced lines following the
  song, hidden when there are none.

## 0.6.0 (2026-11-05)

- Queue windows carry artwork: each previous play's and next item's `image` (an address a browser
  can load anywhere; empty when Music Assistant has only a local one). The queue card shows it:
  `[art] Artist - Song 01:23`, with small thumbnails from Apple's and Spotify's image servers.

## 0.5.0 (2026-11-05)

- Queue windows: `<prefix>/<player>/queue` (retained) holds each player's last 5 plays, from any
  source, with what was heard, and the next 5 items of its Music Assistant queue, with the ids to
  play one. They are asked for only when a queue's place or items change (`player_queues/all` once
  live, then `player_queues/items`: reads). A layer around the core (`top.bend`) keeps the core
  and its laws unchanged; the windows have their own (a pinned session, bounds, no needless asks).

## 0.4.0 (2026-11-05)

- The JSON scanner's limits are proven for every input: at most 64 open containers, 256 kept
  values, 4096 bytes per string being read, 64 characters per number. A byte is now a move (what
  it does) and a land (the only place containers and kept values change, each within its room);
  the counters are rooms that count down. Behaviour is unchanged (every earlier law still holds).
- Every value the scanner keeps is proven small, its path included: a string at most 4096 bytes,
  a number at most 64 characters, at most 64 levels of keys of at most 4096 bytes.

## 0.3.0 (2026-11-05)

- A tick publishes every lookup that waited too long, each once, and keeps the rest: proven
  (each due play once; what stays pending; afterwards nothing is overdue, a liveness law; a late
  answer for an expired play finds nothing). It used to take them one at a time with fuel.
- Chaos tests (`tools/chaos.py`) against a fake Music Assistant (`tools/fakema.py`): cuts,
  stalls, fragmentation, garbage, a refused token, reconnect soaks.

## 0.2.0 (2026-11-05)

- Plays survive a reconnect: those still waiting for their lookup when a session ends are looked
  up again by the next one once it is live (they were lost before). A tick now expires every
  lookup that waited too long, not just the oldest.
- A simulator for the core (`bend progs/sim_core.bend`): seeded random sessions with invariants
  checked after every step; it found the lost plays. CI runs it on every push.
- Images and binaries: built by CI from the tag, as in 0.1.0.

## 0.1.0 (2026-11-05)

The first release: Music Assistant's players and plays, published to MQTT.

- `music/<player>/state` (retained): what each player is doing: name, state, availability,
  source, group, volume, title, artist, album, uri, duration. Players found later join on their
  own; names are slugs (`living_room`), never two alike, never renamed in a session.
- `music/played`: every finished play, skips included, with when, where, how long it was heard,
  whether fully, its Apple Music and Spotify ids and its ISRC; also appended to a JSON-lines file.
- `music/status` (online / offline, the last will) and `music/$bridge/…` health reports.
- Read-only: it sends Music Assistant only its login, a request for the players and library
  lookups.
- Reconnects on its own (1 s after a session that went live, else doubling up to 60 s); pings and
  silence checks on both links.

Proven for every input (101 laws, `bend PROOF.bend`):
- only values at declared paths leave the JSON scanner, so device details, MAC and IP addresses
  can't reach a payload;
- nothing is published before the session is live;
- each finished play is published once, never twice and never without a final report;
- the config's summary never shows a secret; the decoders read the same however bytes arrive.

Images: `ghcr.io/cv/music-assistant-mqtt:0.1.0` (linux/amd64 and linux/arm64, one static binary,
under 1 MB). Binaries: `music-assistant-mqtt-linux-amd64` and `-arm64` (static, no
dependencies), with `SHA256SUMS`.
