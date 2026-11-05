import Base
import ../lib/bridge/conf.bend as C
import ../laws/conf.bend as Lc
# Proofs of laws/conf.bend: the examples compute; the summary never looks at the secrets, so
# once the config's parts are known both sides are the same string.

def Lc.conf_sample():
  {==}

def Lc.conf_sample_problems():
  {==}

def Lc.conf_empty():
  {==}

def Lc.conf_summary():
  {==}

def Lc.conf_summary_hides_secrets(c, t1, p1, t2, p2):
  match c:
    case C.Conf{ma, mq, out}:
      match ma:
        case C.Ma{mh, mp, mt}:
          match mq:
            case C.Mq{qh, qp, qu, qw, qc}:
              match out:
                case C.Out{pre, pl}:
                  {==}
