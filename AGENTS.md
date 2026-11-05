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

It never sends Music Assistant anything but its login and library lookups: it can't control a
player (a law).

Status: being built (2026-11-05).

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
laws/ proofs/         the laws and their proofs by area: wire (bytes, MQTT), ws, json, ma, core
lib/
  wire/     pure encodings, no I/O
    bytes.bend   byte lists, UTF-8, base64, the Rd reader monad, beq
    mqtt.bend    MQTT 3.1.1 client packets
    ws.bend      WebSocket client (RFC 6455): the upgrade request and answer, masked client
                 frames, a streaming frame decoder (one byte at a time, bounded)
    json.bend    a streaming JSON scanner that keeps only wanted paths (bounded captures), and
                 JSON output with escaping
  net/      effects (C, in net/effs/): Net.connect (by name, 10 s), Sock.dup and
            Sock.shutdown, Sd.notify, Run.forever
  ma/       Music Assistant's API (pure)
    api.bend     the commands we send (auth, music/item_by_uri), and what a message is: server
                 info, a result, an error, an event
    model.bend   players, play reports, catalog ids, from the scanner's captures
  bridge/   the decisions (pure, covered by laws)
    conf.bend    the config file: every problem numbered by line, secrets never echoed
    topics.bend  topic names, player slugs (unique, no + # /), the payloads
    core.bend    one step: state + event → state + actions (sessions, login, lookups, publishes,
                 heartbeats, the reconnect backoff)
  app/      I/O: readers per socket feeding a channel, the main loop carrying out core's actions
progs/      sim_core.bend (random sessions through the core, invariants), smoke tests
tools/      cross-build.sh (linux/arm64 in Docker), fakema.py (a fake Music Assistant), chaos.py
deploy/     Dockerfile, an example compose.yaml, the config example
```

## How it works

### Sessions

`mam [config]` (`/etc/music-assistant-mqtt.conf` by default) reads the configuration once, then
runs sessions in a loop:

1. Connect the broker (MQTT, login, a retained `<prefix>/status offline` will) and wait up to
   10 s for it to accept; then Music Assistant (`ws://<ma_host>:<ma_port>/ws`).
2. Music Assistant sends its server info; we send `auth` with the token. After its success
   answer it streams every event.
3. Ask `players/all` once to learn every player's name and state; publish `status online` and
   each player's state.
4. Events: `player_added` / `player_updated` / `player_removed` change and republish a
   player's state when a published field changed; `media_item_played` with `is_playing` false
   is a play: look up its library item (`music/item_by_uri`) for catalog ids (Apple Music,
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
  "available", "source", "volume", "title", "artist", "album", "uri", "duration"}`. The elapsed
  time is left out, so it changes only when something real does.
- `<prefix>/played` (JSON, not retained): `{"at" (Unix s), "player", "player_id", "uri", "name",
  "artist", "album", "duration", "seconds_played", "fully_played", "ids" {"apple_music": …,
  "spotify": …}, "isrc"}`. Music Assistant calls a track fully played at 90 % or within 10 s of
  its end.
- `<prefix>/$bridge/`: `version`, `uptime_s`, `sessions`, `last_end`, `plays`,
  `memory_kb` (retained, every 60 s).
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

## Open items

- Everything above is the plan; the code is being written module by module.
