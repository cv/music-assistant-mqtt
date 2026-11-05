import Base
import ../lib/wire/bytes.bend as B
import ../lib/ma/model.bend as Model
import ../lib/bridge/core.bend as K
import ../lib/bridge/deck.bend as D
import ../laws/deck.bend as Ld
import ./common.bend as Pc
# Proofs of laws/deck.bend. The session computes. A played player's list is the new one put first,
# found at once (beq_refl), and a take of window() is at most window() long. A queue already at its
# place is found at once and compares equal (u32_eq_refl), so the deck asks nothing.

def Ld.top_session():
  {==}

# Taking n is at most n long.
def take_le(-A: Data, +xs: List<&2, A>, +n: Nat)
    -> {Nat.is_le(List.length(&2, A, List.take(&2, A, xs, n)), n) == True{} : Bool}:
  match xs:
    case Nil{}:
      match n:
        case 0n:
          {==}
        case 1n+_:
          {==}
    case h <> t:
      match n:
        case 0n:
          {==}
        case 1n+p:
          take_le(A, t, p)

def Ld.deck_previous_bounded(p, img, d, n):
  match p:
    case Model.Play{item, +seconds, _, _, +player}:
      match item:
        case Model.Media{+uri, +title, +artist, _, +duration}:
          match d:
            case D.Deck{ss, as, +r, l}:
              %Equal.sym(Bool, B.beq(player, player), True{}, Pc.beq_refl(player)) :
                {Nat.is_le(List.length(&2, D.Heard, D.recent.heard(D.recent.find.if(_,
                    D.Recent{player, List.take(&2, D.Heard, D.Heard{artist, title, duration,
                      seconds, uri, img} <> D.recent.heard(D.recent.find(r, player)), D.window())},
                    D.recent.find(D.recent.drop(r, player), player)))), D.window())
                  == True{} : Bool}
              take_le(D.Heard, D.Heard{artist, title, duration, seconds, uri, img}
                <> D.recent.heard(D.recent.find(r, player)), D.window())

def Ld.deck_unchanged_asks_nothing(q, i, c, next, ss, as, r, l, n):
  %Equal.sym(Bool, B.beq(q, q), True{}, Pc.beq_refl(q)) :
    {D.did.requests(D.updated.if(D.spot.same(D.spot.find.if(_, D.Spot{q, i, c, next},
        D.spot.find(ss, q)), i, c), D.Deck{D.Spot{q, i, c, next} <> ss, as, r, l},
        Model.Queue{q, i, c}, n)) == Nil{} : List<&2, D.Request>}
  %Equal.sym(Bool, U32.is_eq(i, i), True{}, Pc.u32_eq_refl(i)) :
    {D.did.requests(D.updated.if(Bool.and(_, U32.is_eq(c, c)),
        D.Deck{D.Spot{q, i, c, next} <> ss, as, r, l}, Model.Queue{q, i, c}, n))
      == Nil{} : List<&2, D.Request>}
  %Equal.sym(Bool, U32.is_eq(c, c), True{}, Pc.u32_eq_refl(c)) :
    {D.did.requests(D.updated.if(Bool.and(True{}, _),
        D.Deck{D.Spot{q, i, c, next} <> ss, as, r, l}, Model.Queue{q, i, c}, n))
      == Nil{} : List<&2, D.Request>}
  {==}
