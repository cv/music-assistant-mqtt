import Base
import ../lib/wire/bytes.bend as B
import ../lib/bridge/topics.bend as T
import ../laws/topics.bend as Lt
import ./common.bend as Pc
# Proofs of laws/topics.bend. The examples compute; names_never_rename goes by cases on whether
# the player was known: a known one leaves the table as it is, a new one is put first, where
# looking its id up finds it (beq_refl), so learning it again leaves the table as it is.

def Lt.slug_examples():
  {==}

def Lt.names_clash_gets_id_suffix():
  {==}

def Lt.topics_examples():
  {==}

def Lt.state_payload():
  {==}

def Lt.played_payload():
  {==}

# A table whose first entry is id finds it there.
def found_first(+id: B.Bytes, +x: B.Bytes, +ns: T.Names)
    -> {T.level.of(T.Named{id, x} <> ns, id) == Some{x} : Maybe<&2, B.Bytes>}:
  %Equal.sym(Bool, B.beq(id, id), True{}, Pc.beq_refl(id)) :
    {T.level.loop(T.Named{id, x} <> ns, id, _) == Some{x} : Maybe<&2, B.Bytes>}
  {==}

# A table where id has a level comes back from learn unchanged.
def known_stays(+ns: T.Names, +id: B.Bytes, +name: B.Bytes, +l: B.Bytes,
    +h: {T.level.of(ns, id) == Some{l} : Maybe<&2, B.Bytes>})
    -> {T.learn(ns, id, name) == ns : T.Names}:
  %Equal.sym(Maybe<&2, B.Bytes>, T.level.of(ns, id), Some{l}, h) :
    {T.learn.on(_, ns, id, name) == ns : T.Names}
  {==}

# Whichever level a new player got, it is first in the table, so learning it again is no change.
def new_stays(b1: Bool, b2: Bool, b3: Bool, +ns: T.Names, +id: B.Bytes, +base: B.Bytes,
    +alt: B.Bytes, +last: B.Bytes, +later: B.Bytes)
    -> {T.learn(T.learn.new(b1, b2, b3, ns, id, base, alt, last), id, later)
        == T.learn.new(b1, b2, b3, ns, id, base, alt, last) : T.Names}:
  match b1:
    case True{}:
      known_stays(T.Named{id, base} <> ns, id, later, base, found_first(id, base, ns))
    case False{}:
      match b2:
        case True{}:
          known_stays(T.Named{id, alt} <> ns, id, later, alt, found_first(id, alt, ns))
        case False{}:
          match b3:
            case True{}:
              known_stays(T.Named{id, last} <> ns, id, later, last, found_first(id, last, ns))
            case False{}:
              known_stays(T.Named{id, Nil{}} <> ns, id, later, Nil{}, found_first(id, Nil{}, ns))

# By cases on the player's level before: m, with h: level.of(names, id) == m.
def stays_on(+m: Maybe<&2, B.Bytes>, +names: T.Names, +id: B.Bytes, +first: B.Bytes,
    +later: B.Bytes, +h: {T.level.of(names, id) == m : Maybe<&2, B.Bytes>})
    -> {T.learn(T.learn(names, id, first), id, later) == T.learn(names, id, first) : T.Names}:
  match m:
    case Some{l}:
      %Equal.sym(T.Names, T.learn(names, id, first), names, known_stays(names, id, first, l, h)) :
        {T.learn(_, id, later) == _ : T.Names}
      known_stays(names, id, later, l, h)
    case None{}:
      %Equal.sym(Maybe<&2, B.Bytes>, T.level.of(names, id), None{}, h) :
        {T.learn(T.learn.on(_, names, id, first), id, later)
          == T.learn.on(_, names, id, first) : T.Names}
      new_stays(Bool.not(T.taken(names, T.candidate(first, id))),
        Bool.not(T.taken(names, B.cat(T.candidate(first, id), 95 <> T.slug(T.last4(id))))),
        Bool.not(T.taken(names, T.or_player(T.slug(id)))),
        names, id, T.candidate(first, id),
        B.cat(T.candidate(first, id), 95 <> T.slug(T.last4(id))), T.or_player(T.slug(id)), later)

def Lt.names_never_rename(names, id, first, later):
  stays_on(T.level.of(names, id), names, id, first, later, {==})

def Lt.names_all_taken():
  {==}

# A level that isn't taken (free: Bool.not(taken(names, l)) == True), put first, keeps a unique
# table unique: the empty level by its definition, any other because it isn't taken.
def first_unique(+l: B.Bytes, +names: T.Names, +id: B.Bytes,
    +free: {Bool.not(T.taken(names, l)) == True{} : Bool}, +hu: {T.unique(names) == True{} : Bool})
    -> {T.unique(T.Named{id, l} <> names) == True{} : Bool}:
  match l:
    case Nil{}:
      %Equal.sym(Bool, T.unique(names), True{}, hu) :
        {Bool.and(True{}, _) == True{} : Bool}
      {==}
    case x <> xs:
      %Equal.sym(Bool, Bool.not(T.taken(names, x <> xs)), True{}, free) :
        {Bool.and(_, T.unique(names)) == True{} : Bool}
      %Equal.sym(Bool, T.unique(names), True{}, hu) :
        {Bool.and(True{}, _) == True{} : Bool}
      {==}

# The empty level keeps any unique table unique.
def empty_unique(+names: T.Names, +id: B.Bytes, +hu: {T.unique(names) == True{} : Bool})
    -> {T.unique(T.Named{id, Nil{}} <> names) == True{} : Bool}:
  %Equal.sym(Bool, T.unique(names), True{}, hu) :
    {Bool.and(True{}, _) == True{} : Bool}
  {==}

# Each branch of learn.new puts first a level its check found free, or the empty one.
def new_unique(b1: Bool, b2: Bool, b3: Bool, +names: T.Names, +id: B.Bytes, +base: B.Bytes,
    +alt: B.Bytes, +last: B.Bytes,
    +h1: {Bool.not(T.taken(names, base)) == b1 : Bool},
    +h2: {Bool.not(T.taken(names, alt)) == b2 : Bool},
    +h3: {Bool.not(T.taken(names, last)) == b3 : Bool},
    +hu: {T.unique(names) == True{} : Bool})
    -> {T.unique(T.learn.new(b1, b2, b3, names, id, base, alt, last)) == True{} : Bool}:
  match b1:
    case True{}:
      first_unique(base, names, id, h1, hu)
    case False{}:
      match b2:
        case True{}:
          first_unique(alt, names, id, h2, hu)
        case False{}:
          match b3:
            case True{}:
              first_unique(last, names, id, h3, hu)
            case False{}:
              empty_unique(names, id, hu)

# By cases on the player's level before (m, with h: level.of(names, id) == m).
def unique_on(+m: Maybe<&2, B.Bytes>, +names: T.Names, +id: B.Bytes, +name: B.Bytes,
    +h: {T.level.of(names, id) == m : Maybe<&2, B.Bytes>}, +hu: {T.unique(names) == True{} : Bool})
    -> {T.unique(T.learn(names, id, name)) == True{} : Bool}:
  match m:
    case Some{l}:
      %Equal.sym(T.Names, T.learn(names, id, name), names, known_stays(names, id, name, l, h)) :
        {T.unique(_) == True{} : Bool}
      hu
    case None{}:
      %Equal.sym(Maybe<&2, B.Bytes>, T.level.of(names, id), None{}, h) :
        {T.unique(T.learn.on(_, names, id, name)) == True{} : Bool}
      new_unique(Bool.not(T.taken(names, T.candidate(name, id))),
        Bool.not(T.taken(names, B.cat(T.candidate(name, id), 95 <> T.slug(T.last4(id))))),
        Bool.not(T.taken(names, T.or_player(T.slug(id)))),
        names, id, T.candidate(name, id),
        B.cat(T.candidate(name, id), 95 <> T.slug(T.last4(id))), T.or_player(T.slug(id)),
        {==}, {==}, {==}, hu)

def Lt.names_unique(names, id, name, h):
  unique_on(T.level.of(names, id), names, id, name, {==}, h)
