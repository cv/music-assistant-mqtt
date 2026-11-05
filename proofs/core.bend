import Base
import ../lib/bridge/core.bend as K
import ../laws/core.bend as Lk
# Proofs of laws/core.bend: the session computes; the others compute once the phase is known
# (the step looks at the phase first, then the input); the backoff by cases on the step.

def Lk.core_session():
  {==}

def Lk.core_over_is_silent(conf, n, up, clock, book, t, ev):
  {==}

def Lk.core_ping_answered(conf, n, up, clock, book, t, p):
  {==}

def Lk.core_lost_broker_ends(conf, n, up, clock, book, t):
  {==}

def Lk.core_lost_ma_says_offline(conf, n, up, clock, book, t, why):
  match clock:
    case K.Clock{a, b, c, d}:
      {==}

def Lk.backoff_ladder():
  {==}

def Lk.backoff_bounded(s):
  match s:
    case 0n:
      {==}
    case 1n+a:
      match a:
        case 0n:
          {==}
        case 1n+b:
          match b:
            case 0n:
              {==}
            case 1n+c:
              match c:
                case 0n:
                  {==}
                case 1n+d:
                  match d:
                    case 0n:
                      {==}
                    case 1n+e:
                      match e:
                        case 0n:
                          {==}
                        case 1n+_:
                          {==}
