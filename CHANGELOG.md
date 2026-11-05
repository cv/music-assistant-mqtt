# Changelog

Each release's section is its notes on GitHub (the release workflow takes it by version).

## 0.2.0 (unreleased)

- Plays survive a reconnect: those still waiting for their lookup when a session ends are looked
  up again by the next one once it is live (they were lost before). A tick now expires every
  lookup that waited too long, not just the oldest.
- A simulator for the core (`bend progs/sim_core.bend`): seeded random sessions with invariants
  checked after every step; it found the lost plays.

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
