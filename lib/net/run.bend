import Base

# Running a computation until it stops
# ====================================
#
# Every long-running computation of the bridge (the main loop, each socket's
# reader) is a state and a step: Run.forever runs the step until
# `go` says the state is done, and answers the final state. Fuel bounds the loop
# (Bend's loops must end): 1000^3 steps, decades at the bridge's pace.

type Next<-S: Type> is Type:
  Go{s: S}
  Stop{s: S}

def Run.out(~S: Type, n: Next<S>) -> S:
  match n:
    case Go{s}:
      s
    case Stop{s}:
      s

def Run.go0(~S: Type, ~go: S -> Next<S>, ~step: S -> IO(S), fuel: Nat, n: Next<S>) -> IO(Next<S>):
  match fuel:
    case 0n:
      IO.pure(Next<S>, n)
    case 1n+p:
      match n:
        case Go{s}:
          do IO<Next<S>>:
            s2 : S <- step(s)
            Run.go0(~S, ~go, ~step, p, go(s2))
        case Stop{s}:
          IO.pure(Next<S>, Stop{s})

def Run.go1(~S: Type, ~go: S -> Next<S>, ~step: S -> IO(S), fuel: Nat, n: Next<S>) -> IO(Next<S>):
  match fuel:
    case 0n:
      IO.pure(Next<S>, n)
    case 1n+p:
      match n:
        case Go{s}:
          do IO<Next<S>>:
            n2 : Next<S> <- Run.go0(~S, ~go, ~step, 1000n, Go{s})
            Run.go1(~S, ~go, ~step, p, n2)
        case Stop{s}:
          IO.pure(Next<S>, Stop{s})

def Run.go2(~S: Type, ~go: S -> Next<S>, ~step: S -> IO(S), fuel: Nat, n: Next<S>) -> IO(Next<S>):
  match fuel:
    case 0n:
      IO.pure(Next<S>, n)
    case 1n+p:
      match n:
        case Go{s}:
          do IO<Next<S>>:
            n2 : Next<S> <- Run.go1(~S, ~go, ~step, 1000n, Go{s})
            Run.go2(~S, ~go, ~step, p, n2)
        case Stop{s}:
          IO.pure(Next<S>, Stop{s})

def Run.forever(~S: Type, ~go: S -> Next<S>, ~step: S -> IO(S), s: S) -> IO(S):
  do IO<S>:
    n : Next<S> <- Run.go2(~S, ~go, ~step, 1000n, go(s))
    return Run.out(~S, n)
