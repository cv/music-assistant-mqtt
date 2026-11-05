# Writing readable Bend here

The code is read far more often than it is written, mostly by someone who
doesn't have the whole bridge in their head. These rules make the common cases
read the same way everywhere. They never trump correctness: the proof gate,
the simulator and the wire bytes stay exactly as they are.

## Types say what a value is

- **Byte strings are `B.Bytes`** (`Bytes` inside `lib/wire/bytes.bend`), never
  `List<&2, U32>`. Lists of other things stay `List<&2, X>`.
- **No number codes.** A value that means one of a few things is an enum:

  ```bend
  type Phase is Data:
    Connecting{}
    Authenticating{}
    Live{}
  ```

  not `phase: U32` with "0: connecting, 1: authenticating, 2: live" in a comment. A constructor
  match also reduces in proofs, where a U32 literal match gets stuck.
- **Numbers that must stay numbers** (limits, ports, protocol constants) get a
  named constant next to their meaning: `def max_depth() -> U32: 64`,
  and every use goes through the name.
- **A flag argument that picks one of several fields** (`set(4, …)`) becomes
  one function per field (`with_online(c)`).

## Records

- **At most about 5 fields.** A bigger state is a record of named parts
  (`Core{session, players, lookups, heart}`), each a small record. A step that
  changes one part rebuilds only that part.
- **Accessors live next to the type**, one getter (`core.conf(c)`) and, where
  needed, one setter (`core.with_conf(c, x)`) per field. Elsewhere, use them
  instead of positional patterns like `Core{_, _, conf, _, _}`.
  A function that genuinely needs several fields at once may match the record
  itself; then bind every field by its full name.

## Names

- **Module aliases are words**: `Core`, `Conf`, `Topics`, `Health`, `Ma`,
  `Players`. The well-known one-letter ones stay: `B` (bytes), `M` (mqtt),
  `W` (websocket), `J` (json). The `lib/net` effects keep theirs (`Net.connect` …).
- **Helpers name the decision they make.** `match` only takes parameters, so
  branching on a computed value needs a helper; name it for the question:
  - `<f>.if_<condition>(b: Bool, …)`: a `Bool` dispatch
    (`long.if_too_big`, `head.if_long`);
  - `<f>.on_<thing>(m: Maybe/Result/…, …)`: a dispatch on a parsed or looked-up
    value (`decode.on_len`);
  - `<f>.loop(…)`: the recursion behind `<f>`, with its accumulators.
  Not `.k`, `.k2`, `.go`. Put the helper right above the function it serves.
- **Fields and parameters have full names** (`seconds_played`, `lookups`,
  `stack`); one or two letters are fine only for a local binding whose
  meaning is obvious from the line (`x <> t`, `b` for the byte being read,
  `ws` for the wanted paths, which are used everywhere).
- Constructors of an event or action type say what happened or what to do
  (`IMaDown`, `ToMq`): keep that style.

## Expressions

- **Lines stay under 100 characters.** Break calls one argument per line, or
  name the pieces with lets (`+topic = …`).
- **Say the rule, not the encoding.** A chain of `Bool.or(U32.is_eq(b, 45), …)`
  becomes a `match` or a named predicate (`is_number_byte(b)`); nested
  `or_else(look(…), or_else(look(…), …))` becomes a list of fallbacks or a
  named helper per step.
- `Bool.and` / `Bool.or` / `Bool.pick` evaluate both sides. In hot paths
  (the WebSocket decoder, the JSON scanner, `B.beq`) keep the matching helpers
  that stop early.

## Comments

- Every module opens with what it is for and what it is not.
- Every type gets a line per field that isn't obvious.
- Every exported def gets one line saying what it gives, in the domain's words
  ("the topic a player's state goes to: …"), not how.
- A proof gets a line with its idea ("induction on xs: run is a fold, so the
  head byte's step is the same either way"), not a restatement of its type.

## Proofs

- A lemma that holds for any element type is written once, with a type
  parameter, in `proofs/common.bend` (`app_nil`, `app_assoc`, `and_true`), not
  copied per type.
- Long equations are broken over lines, and a repeated big term gets a name (a
  def that returns it) so the statement fits on a screen.
- The law statements in `laws/` are the specification: renaming what they
  mention is fine, changing what they say is not. The law count never drops.

## Changing code for readability

- Behaviour stays the same: the same bytes on the wire, the same logs, the same
  topics. `bend PROOF.bend`, `progs/sim_core.bend` and the pinned payloads must
  not change.
- One idea per commit.
