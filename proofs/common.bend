import Base
import ../lib/wire/bytes.bend as B
import ../laws/wire.bend as Lw

# Lemmas and proofs that several areas use (the other proof files import this
# one, never each other). Lemmas about lists hold for any element type: pass it
# first, e.g. app_nil(Core.Do, xs).

# Contradictions
# --------------

# A motive that tells True from False.
def disc(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

# True is not False: rewrite disc(True) (Unit) into disc(False) (Empty).
def absurd_tf(e: {True{} == False{} : Bool}) -> Empty:
  %e : disc(_)
  Unit{}

# Anything follows from Empty.
def ex_falso(-P: Type, e: Empty) -> P:
  match e:

# False is not True: absurd_tf, flipped.
def absurd_ft(e: {False{} == True{} : Bool}) -> Empty:
  absurd_tf(Equal.sym(Bool, False{}, True{}, e))

# A motive that tells EQ from LT and GT.
def dcmp_eq(c: Cmp) -> Type:
  match c:
    case EQ{}:
      Unit
    case _:
      Empty

# LT is not EQ: rewrite dcmp_eq(EQ) into dcmp_eq(LT).
def lt_not_eq(e: {LT{} == EQ{} : Cmp}) -> Empty:
  %Equal.sym(Cmp, LT{}, EQ{}, e) : dcmp_eq(_)
  Unit{}

# GT is not EQ, the same way.
def gt_not_eq(e: {GT{} == EQ{} : Cmp}) -> Empty:
  %Equal.sym(Cmp, GT{}, EQ{}, e) : dcmp_eq(_)
  Unit{}

# Bool
# ----

# An and that holds has a first part that holds (a False one computes to False).
def and_l(a: Bool, +b: Bool, h: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      ex_falso({False{} == True{} : Bool}, absurd_tf(Equal.sym(Bool, False{}, True{}, h)))

# ... and a second part that holds (with a True, the and is b).
def and_r(a: Bool, +b: Bool, h: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  match a:
    case True{}:
      h
    case False{}:
      ex_falso({b == True{} : Bool}, absurd_tf(Equal.sym(Bool, False{}, True{}, h)))

# By cases on b.
def and_true(+b: Bool) -> {Bool.and(b, True{}) == b : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

# By cases on a.
def and_false(+a: Bool) -> {Bool.and(a, False{}) == False{} : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# By cases on a: both sides compute to b and c, or to False.
def and_assoc(+a: Bool, +b: Bool, +c: Bool)
    -> {Bool.and(Bool.and(a, b), c) == Bool.and(a, Bool.and(b, c)) : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# By cases on a: both sides compute to True, or to b or c.
def or_assoc(a: Bool, b: Bool, c: Bool)
    -> {Bool.or(Bool.or(a, b), c) == Bool.or(a, Bool.or(b, c)) : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# By cases on a.
def or_false(a: Bool) -> {a == Bool.or(a, False{}) : Bool}:
  match a:
    case True{}:
      {==}
    case False{}:
      {==}

# An or that fails has a first part that fails (a True one computes to True).
def or_false_l(a: Bool, +b: Bool, h: {Bool.or(a, b) == False{} : Bool})
    -> {a == False{} : Bool}:
  match a:
    case True{}:
      ex_falso({True{} == False{} : Bool}, absurd_tf(h))
    case False{}:
      {==}

# ... and a second part that fails (with a False, the or is b).
def or_false_r(a: Bool, +b: Bool, h: {Bool.or(a, b) == False{} : Bool})
    -> {b == False{} : Bool}:
  match a:
    case True{}:
      ex_falso({b == False{} : Bool}, absurd_tf(h))
    case False{}:
      h

# A pick whose condition holds gives its first value: rewrite the condition to
# True.
def pick_t(-A: Data, +b: Bool, +a: A, +d: A, h: {b == True{} : Bool})
    -> {Bool.pick(A, b, a, d) == a : A}:
  %Equal.sym(Bool, b, True{}, h) : {Bool.pick(A, _, a, d) == a : A}
  {==}

# Lists, for any element type
# ---------------------------

# Appending nothing: by induction on xs.
def app_nil(-A: Data, +xs: List<&2, A>) -> {List.append(&2, A, xs, Nil{}) == xs : List<&2, A>}:
  match xs:
    case Nil{}:
      {==}
    case +x <> +t:
      %app_nil(A, t) : {x <> List.append(&2, A, t, Nil{}) == x <> _ : List<&2, A>}
      {==}

# Appending to an append, either grouping: by induction on xs.
def app_assoc(-A: Data, +xs: List<&2, A>, +ys: List<&2, A>, +zs: List<&2, A>)
    -> {List.append(&2, A, List.append(&2, A, xs, ys), zs)
        == List.append(&2, A, xs, List.append(&2, A, ys, zs)) : List<&2, A>}:
  match xs:
    case Nil{}:
      {==}
    case +x <> +t:
      %app_assoc(A, t, ys, zs) :
        {x <> List.append(&2, A, List.append(&2, A, t, ys), zs) == x <> _ : List<&2, A>}
      {==}

# One more at the end makes the list one longer: by induction on xs.
def len_snoc(-A: Data, +xs: List<&2, A>, +x: A)
    -> {List.length(&2, A, List.append(&2, A, xs, [x])) == 1n+List.length(&2, A, xs) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case +y <> +t:
      %Equal.sym(Nat, List.length(&2, A, List.append(&2, A, t, [x])),
          1n+List.length(&2, A, t), len_snoc(A, t, x)) :
        {1n+_ == 1n+1n+List.length(&2, A, t) : Nat}
      {==}

# Nat
# ---

# Adding zero: by induction on n.
def add_zero(+n: Nat) -> {Nat.add(n, 0n) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.add(p, 0n), p, add_zero(p)) : {1n+_ == 1n+p : Nat}
      {==}

# Adding a successor: by induction on n.
def add_succ(+n: Nat, +k: Nat) -> {Nat.add(n, 1n+k) == 1n+Nat.add(n, k) : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.add(p, 1n+k), 1n+Nat.add(p, k), add_succ(p, k)) :
        {1n+_ == 1n+1n+Nat.add(p, k) : Nat}
      {==}

# Equality of words, U32s and bytes
# ---------------------------------

# A word equals itself: by induction on its bits, each comparing EQ.
def word_cmp_refl(n: Nat, +w: Word(n)) -> {Word.cmp(n, w, w) == EQ{} : Cmp}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{+b, +t}:
          match b:
            case True{}:
              %Equal.sym(Cmp, Word.cmp(p, t, t), EQ{}, word_cmp_refl(p, t)) :
                {Word.cmp.fin(True{}, True{}, _) == EQ{} : Cmp}
              {==}
            case False{}:
              %Equal.sym(Cmp, Word.cmp(p, t, t), EQ{}, word_cmp_refl(p, t)) :
                {Word.cmp.fin(False{}, False{}, _) == EQ{} : Cmp}
              {==}

# A U32 equals itself: its word does.
def u32_eq_refl(+x: U32) -> {U32.is_eq(x, x) == True{} : Bool}:
  match x:
    case U32{+w}:
      %Equal.sym(Cmp, Word.cmp(32n, w, w), EQ{}, word_cmp_refl(32n, w)) :
        {Cmp.is_eq(_) == True{} : Bool}
      {==}

# Bytes equal themselves: by induction, every head comparing equal.
def beq_loop_refl(+xs: B.Bytes) -> {B.beq.loop(xs, xs, B.heads(xs, xs)) == True{} : Bool}:
  match xs:
    case Nil{}:
      {==}
    case +x <> +t:
      %Equal.sym(Bool, U32.is_eq(x, x), True{}, u32_eq_refl(x)) :
        {B.beq.loop(x <> t, x <> t, _) == True{} : Bool}
      beq_loop_refl(t)

# B.beq is beq.loop from the first heads.
def beq_refl(+xs: B.Bytes) -> {B.beq(xs, xs) == True{} : Bool}:
  beq_loop_refl(xs)

# Bools that compare EQ are equal: by cases, LT and GT refuted.
def bool_cmp_eq(+a: Bool, +b: Bool, h: {Bool.cmp(a, b) == EQ{} : Cmp}) -> {a == b : Bool}:
  match a:
    case False{}:
      match b:
        case False{}:
          {==}
        case True{}:
          ex_falso({False{} == True{} : Bool}, lt_not_eq(h))
    case True{}:
      match b:
        case False{}:
          ex_falso({True{} == False{} : Bool}, gt_not_eq(h))
        case True{}:
          {==}

# A word comparison that ends EQ had the rest of the words compare EQ: by cases
# on that rest's result.
def fin_eq_t(+ab: Bool, +bb: Bool, +t: Cmp, h: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp})
    -> {t == EQ{} : Cmp}:
  match t:
    case LT{}:
      ex_falso({LT{} == EQ{} : Cmp}, lt_not_eq(h))
    case EQ{}:
      {==}
    case GT{}:
      ex_falso({GT{} == EQ{} : Cmp}, gt_not_eq(h))

# ... and the first bits compare EQ (with the rest EQ, the result is theirs).
def fin_eq_b(+ab: Bool, +bb: Bool, +t: Cmp, h: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp})
    -> {Bool.cmp(ab, bb) == EQ{} : Cmp}:
  match t:
    case LT{}:
      ex_falso({Bool.cmp(ab, bb) == EQ{} : Cmp}, lt_not_eq(h))
    case EQ{}:
      h
    case GT{}:
      ex_falso({Bool.cmp(ab, bb) == EQ{} : Cmp}, gt_not_eq(h))

# Words that compare EQ are equal: by induction, rewriting the first bit
# (bool_cmp_eq) and the rest.
def word_eq(+n: Nat, +a: Word(n), +b: Word(n), +h: {Word.cmp(n, a, b) == EQ{} : Cmp})
    -> {a == b : Word(n)}:
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p:
      match a b:
        case WCon{+ab, +at} WCon{+bb, +bt}:
          %bool_cmp_eq(ab, bb, fin_eq_b(ab, bb, Word.cmp(p, at, bt), h)) :
            {WCon{ab, at} == WCon{_, bt} : Word(1n+p)}
          %word_eq(p, at, bt, fin_eq_t(ab, bb, Word.cmp(p, at, bt), h)) :
            {WCon{ab, at} == WCon{ab, _} : Word(1n+p)}
          {==}

# Cmp.is_eq holds only for EQ: by cases.
def cmp_is_eq(+c: Cmp, h: {Cmp.is_eq(c) == True{} : Bool}) -> {c == EQ{} : Cmp}:
  match c:
    case LT{}:
      ex_falso({LT{} == EQ{} : Cmp}, absurd_ft(h))
    case EQ{}:
      {==}
    case GT{}:
      ex_falso({GT{} == EQ{} : Cmp}, absurd_ft(h))

# U32s U32.is_eq calls equal are equal: their words are (word_eq).
def u32_eq_sound(+x: U32, +y: U32, h: {U32.is_eq(x, y) == True{} : Bool}) -> {x == y : U32}:
  match x y:
    case U32{+a} U32{+b}:
      %word_eq(32n, a, b, cmp_is_eq(Word.cmp(32n, a, b), h)) : {U32{a} == U32{_} : U32}
      {==}

# Bytes beq.loop calls equal are equal: by induction, rewriting each head
# (u32_eq_sound) and the rest; a mismatch or a length difference gives False.
def beq_loop_sound(
    +a: B.Bytes, +b: B.Bytes, e: Bool, he: {B.heads(a, b) == e : Bool},
    h: {B.beq.loop(a, b, e) == True{} : Bool}
  ) -> {a == b : B.Bytes}:
  match a b:
    case Nil{} Nil{}:
      {==}
    case Con{+x, +xs} Con{+y, +ys}:
      match e:
        case True{}:
          %u32_eq_sound(x, y, he) : {x <> xs == _ <> ys : B.Bytes}
          %beq_loop_sound(xs, ys, B.heads(xs, ys), {==}, h) : {x <> xs == x <> _ : B.Bytes}
          {==}
        case False{}:
          ex_falso({x <> xs == y <> ys : B.Bytes}, absurd_ft(h))
    case Nil{} Con{y, ys}:
      ex_falso({Nil{} == y <> ys : B.Bytes}, absurd_ft(h))
    case Con{x, xs} Nil{}:
      ex_falso({x <> xs == Nil{} : B.Bytes}, absurd_ft(h))

# beq_loop_sound from the first heads.
def Lw.beq_sound(a, b, h):
  beq_loop_sound(a, b, B.heads(a, b), {==}, h)
