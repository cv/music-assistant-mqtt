import Base
import ../wire/bytes.bend as B
import ../wire/ws.bend as W
import ../wire/json.bend as J
# The link from Music Assistant as its bytes arrive: the websocket decoder (ws.bend) feeds the
# JSON scanner (json.bend) one byte at a time, so neither a frame nor a message is ever held
# whole. What comes out: the upgrade accepted, a whole message (the values the wanted paths
# keep), a message that wasn't JSON, a ping to answer, or the link's end.

type Heard is Data:
  Opened{}
  Message{caps: List<&2, J.Cap>}
  Garbled{}
  Pinged{payload: B.Bytes}
  Dropped{why: String}

type Link is Data:
  Link{dec: W.Dec, scan: J.Scan}

# Before the upgrade answer.
def start() -> Link:
  Link{W.start(), J.start()}

# What a finished message is.
def message(m: Maybe<&2, List<&2, J.Cap>>) -> Heard:
  match m:
    case None{}:
      Garbled{}
    case Some{caps}:
      Message{caps}

type Step is Data:
  Step{link: Link, heard: Maybe<&2, Heard>}

def step.link(s: Step) -> Link:
  match s:
    case Step{l, _}:
      l

def step.heard(s: Step) -> Maybe<&2, Heard>:
  match s:
    case Step{_, h}:
      h

# The link after the decoder put out o (dec: the decoder after it).
def on_out(+ws: J.Wants, dec: W.Dec, scan: J.Scan, o: W.Out) -> Step:
  match o:
    case W.Nothing{}:
      Step{Link{dec, scan}, None{}}
    case W.Up{}:
      Step{Link{dec, scan}, Some{Opened{}}}
    case W.Byte{b}:
      Step{Link{dec, J.step(ws, scan, b)}, None{}}
    case W.Last{b}:
      Step{Link{dec, J.start()}, Some{message(J.finished(ws, J.step(ws, scan, b)))}}
    case W.End{}:
      Step{Link{dec, J.start()}, Some{message(J.finished(ws, scan))}}
    case W.Ping{p}:
      Step{Link{dec, scan}, Some{Pinged{p}}}
    case W.Closed{}:
      Step{Link{dec, scan}, Some{Dropped{"closed by Music Assistant"}}}
    case W.Bad{why}:
      Step{Link{dec, scan}, Some{Dropped{why}}}

# The link after one byte.
def step(+ws: J.Wants, l: Link, +b: U32) -> Step:
  match l:
    case Link{dec, scan}:
      +s = W.step(dec, b)
      on_out(ws, W.stepped.dec(s), scan, W.stepped.out(s))

# A run of bytes: the link after them and what was heard, newest first.
type Fed is Data:
  Fed{link: Link, heard: List<&2, Heard>}

def fed.link(f: Fed) -> Link:
  match f:
    case Fed{l, _}:
      l

def fed.heard(f: Fed) -> List<&2, Heard>:
  match f:
    case Fed{_, h}:
      h

def keep(h: Maybe<&2, Heard>, hs: List<&2, Heard>) -> List<&2, Heard>:
  match h:
    case None{}:
      hs
    case Some{x}:
      x <> hs

def run(bs: B.Bytes, +ws: J.Wants, l: Link, hs: List<&2, Heard>) -> Fed:
  match bs:
    case Nil{}:
      Fed{l, hs}
    case b <> t:
      +s = step(ws, l, b)
      run(t, ws, step.link(s), keep(step.heard(s), hs))

def feed.done(f: Fed) -> Fed:
  match f:
    case Fed{l, h}:
      Fed{l, List.reverse(&2, Heard, h)}

# What a run of bytes says, in order, and the link after it.
def feed(+ws: J.Wants, l: Link, bs: B.Bytes) -> Fed:
  feed.done(run(bs, ws, l, Nil{}))
