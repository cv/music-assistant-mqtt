When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

# music-assistant-mqtt

A small bridge from [Music Assistant](https://music-assistant.io) to MQTT, written in Bend and
compiled to a native binary. Music Assistant has no MQTT output: its plays reach only its
scrobblers (Last.fm, ListenBrainz, Subsonic), which drop skips, and its `playlog` table keeps one
row per track (the last play), not a history. This bridge listens to Music Assistant's websocket
API and publishes:

- what every player is doing, retained (`<prefix>/<player>/state`);
- every finished play, skips included, with how long it was heard (`<prefix>/played`), also
  appended to a JSON-lines file, the durable history;
- its own health (`<prefix>/$bridge/…`).

It never sends Music Assistant anything but its login, the player list and library lookups: it
can't control a player (the core's ToMa action carries an `Api.Command`, and Api has only those
three).

Status (2026-11-05): running beside Music Assistant 2.10.9 (Sonos, Apple Music, Spotify) as a
container (`deploy/`); 110 laws, all proven. About 1 MB of memory, 2 threads.

## Working rules

- New and changed Bend code follows `STYLE.md` (types over number codes, small records with
  accessors, helpers named for their decision, lines under 100 characters).
- `bend PROOF.bend` must print ALL PROOFS CHECK before every commit. Commit in small steps.
- Every rule worth keeping gets a law in its area's file under `laws/` (proof in the matching
  `proofs/` file); every wire format gets a law pinning bytes a real peer sent or accepted
  (Music Assistant's frames and JSON, captured; RFC 6455's examples).
- Edit a file from one call at a time: two parallel edits of the same file lose one.
- Secrets (the Music Assistant token, the MQTT password) live only in the config file, which is
  never committed and never logged (a law).

## Layout

Dependencies point down this list: a module imports only modules listed before it (and `Base`).

```
mam.bend              the program: arguments, the configuration, the reconnect loop
LAWS.bend PROOF.bend  index files importing every area under laws/ and proofs/
laws/ proofs/         the laws and their proofs by area: wire (bytes, MQTT), ws, json, ma, topics,
                      link, conf, core
lib/
  wire/     pure encodings, no I/O
    bytes.bend   byte lists, UTF-8, base64, the Rd reader monad, beq
    mqtt.bend    MQTT 3.1.1 client packets
    ws.bend      WebSocket client (RFC 6455): the upgrade request and answer, masked client
                 frames, a streaming frame decoder (one byte at a time, bounded)
    json.bend    a streaming JSON scanner that keeps only wanted paths, and JSON output with
                 escaping. A byte is a move (what it does, from the mode and the open
                 containers) and a land (the only place the containers and the kept values
                 change, each within its room): proven for every input, at most 64 open
                 containers, 256 kept values, 4096 bytes per string, 64 characters per number.
  net/      effects (C, in net/effs/): Net.connect (by name, 10 s), Sock.dup and
            Sock.shutdown, Sd.notify, Clock.unix (the wall clock), Run.forever
  ma/       Music Assistant's API (pure)
    api.bend     the three commands we send (auth, players/all, music/item_by_uri) and the paths
                 kept of what the server sends
    model.bend   what a message is (hello, reply, refusal, event) and, in it, players, play
                 reports, catalog ids
    link.bend    the websocket decoder feeding the scanner byte by byte: whole messages, pings,
                 the end
  bridge/   the decisions (pure, covered by laws)
    conf.bend    the config file: every problem numbered by line, secrets never echoed
    topics.bend  topic names, player slugs (unique, no + # /), the payloads
    deck.bend    the queue windows: each player's last plays and its queue's next items, the
                 requests they need (reads), the JSON
    top.bend     the bridge's step: the core's, and the deck fed the same inputs (its own message
                 ids from 2^31; windows published only while live)
    core.bend    one step: state + event → state + actions (sessions, login, lookups, publishes,
                 heartbeats, the reconnect backoff)
  app/      I/O
    readers.bend one reader per socket (broker, Music Assistant) feeding one channel
    main.bend    a session: connect, then carry out the core's actions until it ends (sends,
                 opening Music Assistant's link, the plays file, health reports, the log)
Dockerfile  the image: bend's C cross-compiled by zig into one static binary, FROM scratch
.github/    ci.yml (laws, build on every push), release.yml (v* tags: images to ghcr.io)
tools/      cross-build.sh (a static linux binary of any program, for tests), deploy.sh (runs a
            release image on a host with compose), fakema.py (a fake Music Assistant), chaos.py
deploy/     an example compose.yaml (the release image), the config example
```

## How it works

### Sessions

`mam [config]` (`/etc/music-assistant-mqtt.conf` by default) reads the configuration once, then
runs sessions in a loop:

1. Connect the broker (MQTT, login, a retained `<prefix>/status offline` will) and wait up to
   10 s for it to accept; then Music Assistant (`ws://<ma_host>:<ma_port>/ws`).
2. Music Assistant sends its server info; we send `auth` with the token (message id 1). After
   its success answer it streams every event (it echoes message ids as strings).
3. Ask `players/all` once (id 2) to learn every player's name and state; publish `status
   online` and each player's state.
4. Events: `player_added` / `player_updated` republish a player's state when a published field
   changed (`player_removed` is ignored for now); `media_item_played` with `is_playing` false
   is a play: look up its library item (`music/item_by_uri`, ids from 3 up) for catalog ids (Apple Music,
   Spotify, …, and the ISRC), then publish it and append it to the plays file. A lookup that
   doesn't answer within 10 s publishes the play without ids.
5. A lost link, a refused login, or silence ends the session: `status offline`, disconnect,
   both sockets shut. The next starts after a backoff (1 s after a session that came up, else
   doubling to 60 s).

### Resilience (what keeps the I/O from hanging)

- Music Assistant pings every 25 s; we answer every ping with its pong, and end the session after
  60 s without a frame from it.
- We ping the broker every 30 s and end the session after 90 s without a word from it.
- Every connect and send gives up after 10 s.
- Music Assistant drops a client 512 messages behind, so the reader never waits on the writer.

### Topics

- `<prefix>/status`: `online` / `offline` (retained; the will).
- `<prefix>/<player>/state` (retained JSON): `{"name", "state" (playing/paused/idle/off),
  "available", "source", "synced_to" (the player it is grouped under), "volume", "title",
  "artist", "album", "uri", "duration"}`; device details (MAC, IP) are never kept. The elapsed
  time is left out, so it changes only when something real does.
- `<prefix>/<player>/queue` (retained JSON): `{"previous": [last 5 plays, oldest first: "artist",
  "title", "duration", "seconds", "uri", "image"], "next": [the queue's next 5 items: "id" (to play
  it: player_queues/play_index takes it), "name" ("Artist - Title"), "duration", "uri", "image"],
  "queue", "index"}`. "image": the artwork's address (a play report's image_url; a queue item's
  image path when Music Assistant says it is remotely accessible), else empty.
  Plays come from every source; the next items from `player_queues/items` after the current index,
  asked again only when the queue's place (index or length) changes or its items do. The last plays
  survive a reconnect (in memory), not a restart.
- `<prefix>/played` (JSON, not retained): `{"at" (Unix s), "player", "player_id", "uri", "name",
  "artist", "album", "duration", "seconds_played", "fully_played", "ids" {"apple_music": …,
  "spotify": …}, "isrc"}`; `at` is the wall clock when the final report came. Music Assistant calls a track fully played at 90 % or within 10 s of
  its end.
- `<prefix>/$bridge/`: `version`, `uptime_s`, `sessions`, `last_end` (`none` at first),
  `plays`, `players`, `memory_kb` (retained, 10 s after going live, then every 60 s).
- `<player>` is the player's name as a slug (`living_room`); a clash gets the id's last 4
  characters. Names learned later join without renaming anyone; renames apply next session.

### Configuration

One `key value` per line, `#` comments:

```
ma_host <host>            # Music Assistant (127.0.0.1)
ma_port <port>            # (8095)
ma_token <token>          # a long-lived token made in Music Assistant's UI; never logged
mqtt_host <host>          # the broker (required)
mqtt_port <port>          # (1883)
mqtt_user <name>
mqtt_password <rest of the line>   # spaces and # allowed; never logged
topic_prefix <level>      # (music)
client_id <id>            # (music-assistant-mqtt)
plays_file <path>|off     # the JSON-lines history (/data/plays.jsonl)
```

## What the laws guarantee (for every input)

- Privacy: the JSON scanner hands out only values at wanted paths (a guard in `J.finished`, so it
  holds whatever the state machine does); every message the link hears, and everything the model
  reads, is at one of Api's wanted paths: no device details, MAC or IP addresses, artwork or
  metadata can reach a payload.
- Read-only: every command (the core's and the deck's) is an `Api.Command`, and Api has only reads
  (login, player list, lookup, queue list, queue items). Music Assistant's long-lived tokens expire
  after a year: renew the bridge's (and Home Assistant's, for queue taps) by 2027-11.
- Queue windows: a player's last plays are at most 5; a queue_updated at the place a queue already
  has asks nothing; the deck's requests never share an id with the core's.
- Read-only (core): the core's only command action carries an `Api.Command` (login, player list,
  lookup).
- Order: until the session is live (the broker accepted, Music Assistant said hello and took the
  token), nothing is published but the offline status, whatever either side sends; events count
  only from the player list on.
- Names: no two players share a topic level; a learned player is never renamed; one with no free
  name gets none and is never published.
- Plays, each published once: a final report goes pending under the next message id with one
  lookup (a report still playing does nothing); the lookup's answer, refusal or expiry publishes
  at most one play and takes it out of the book, so a second answer, or a late one after the
  expiry, publishes nothing; with nothing pending, no input publishes a play. (Left as an
  assumption: message ids don't wrap within a session, 2^32 lookups.) A session that ends leaves
  its waiting plays to the next (in memory), which looks them up again once live; a tick expires
  every lookup that waited too long.
- An ended session does nothing more; a lost link ends the session (offline first when the broker
  still listens); Music Assistant's pings get their pongs; the reconnect waits stay in 1..60 s.
- The config's summary never shows the token or the password.
- Bounds: the JSON scanner holds at most 64 open containers and 256 kept values, a string being
  read at most 4096 bytes, a number at most 64 characters; every value it keeps is small, its path
  included (a string at most 4096 bytes, a number at most 64 characters, at most 64 levels of keys
  of at most 4096 bytes), so what a document holds can't grow what reaches the bridge.
- The decoders read the same however the socket splits the bytes (WebSocket, JSON, MQTT).

## Testing

- `bend PROOF.bend`: every law (about 16 s).
- `bend progs/sim_core.bend`: 200 seeded random runs of 400 steps through the core (real JSON
  through the scanner and model; a tick every second, as the main loop runs them), with
  invariants checked after every step against the simulation's own record: nothing after the end,
  nothing early, no play twice or from nowhere, none late (13 s after its final report, or after
  going live again for a carried one), the broker pinged and its silence noticed, one lookup per
  final report; and no play lost (published, or still waiting when a run stops). It found that
  plays waiting for their lookup were lost when a session ended (now carried over).
- `tools/chaos.py [--build] [scenario ...]` (about 6 minutes): the program built for this machine
  against a fake Music Assistant (`tools/fakema.py`: the websocket handshake and frames, auth,
  players, lookups, events, pings, split frames, garbage on command) and a test broker, both
  behind proxies that cut, stall and fragment. Scenarios: broker restart and cut, Music
  Assistant dropped, a play waiting for its lookup at the cut (published once, with its ids, by
  the next session), garbage, split and byte-by-byte frames, a refused token (waits doubling),
  15 reconnects (memory and open files flat), Music Assistant and broker silent (noticed after
  60 s and 90 s); after each, live again and every final report published exactly once. All
  pass (2026-11-05). Runs on macOS: everything is on 127.0.0.1.
- On a Linux host next to Music Assistant: `tools/cross-build.sh mam.bend out/mam`, a throwaway
  broker (`docker run --network host eclipse-mosquitto:2` with a localhost listener), a config
  pointing at both, then `mosquitto_sub -v -t 'music/#'`.
- On macOS a freshly built binary can't reach the LAN (Local Network privacy answers `No route
  to host` without asking); loopback works, so test on Linux or through a tunnel.

## Bend notes (2.0.39)

- `match` takes only parameters or pattern-bound fields: to branch on a computed value, pass it to
  a helper def named for the decision (STYLE.md); for recursion, precompute the next decision as
  a `Bool` argument.
- No mutual recursion, and a def calls only defs above it. Loops bounded by the world count down
  a `Nat` fuel; long-running computations use `Run.forever` (lib/net/run.bend).
- Destructuring lets only on parameters / pattern variables; in a `do` block, bind the pair and
  hand it to a helper. Values bound in a `do` block can't be `+`-copied: pass them to a helper
  with `+` parameters.
- Constructors from an imported module need its alias: `M.Got{..}`.
- `A & B` is a `Type`, so a pair can't be `+`-copied; make a `Data` type instead.
- `Bool.and` / `Bool.or` / `Bool.pick` evaluate both arguments: to stop early, use a helper
  that matches.
- A U32 literal `match` stays stuck in proofs when the value is symbolic: branch on
  `U32.is_eq(x, 0)` in a helper instead, so a proof can generalize over it.
- A constructor alone in a let fails with "an annotated term (cannot infer)": write it inline or
  name it with a def.
- A local statement (a let) can't come before a `match` on a parameter: match first.
- A large Nat literal in a law makes the checker expand it: compare U32s.
- A def with `+x` can't be passed where `A -> B` is expected (e.g. `List.map`).
- Templates take top-level defs and types at compile time (`~S: Type`, `~step: S -> IO(S)`).
- Modules using foreign effects (`lib/net/*`, `lib/app/*`) fail the proof check by design: keep
  them out of the law files' imports.
- Proof technique: no tactics. To turn X into Y in a goal write `%e : P` with `e : {Y == X}`
  and `_` marking X in P. Generalize a computed `Bool` with a lemma taking `b` and
  `h : {expr == b}`, then `match b`. Prefer equations over implications for induction
  (`feed(s, xs ++ ys) == feed(feed(s, xs), ys)`). Refute with a `disc` motive and `ex_falso`.
- `Chan(A)` is `Data`; sockets are not.
- Constructor names share one space with Base's: `Text`, `Done`, `Key`, `Event` are taken.
- Match parameters in their order; a field bound by a pattern can't be matched after a later
  parameter. Termination reads the arguments left to right: put the shrinking one first.
- A pattern variable used twice needs `+` (`case Some{+l}`, `case 1n+(+p)`).
- No hex literals; bitwise and is `.&.`, shifts take a Nat (`x >> 8n`).
- `IO.now()` counts milliseconds from an arbitrary start (intervals only): dates need
  `Clock.unix`. An effect returns a number as the term itself (`return (Term)(u32)x;`).
- A program importing a law file must import its proofs too (unfilled laws are errors).

## Open items

- Not proven yet: the scanner's bounds (captures, text, depth) for every input; that every
  pending play is eventually published (each tick publishes the oldest due one).
- `player_removed`: mark the player unavailable.
- Home Assistant discovery for the players' states (sensors), optional.
