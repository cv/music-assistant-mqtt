import Base
import ../lib/wire/bytes.bend as B
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
import ../lib/wire/json.bend as J
import ../laws/ma.bend as Lma
import ./common.bend as Pc
# Proofs of laws/ma.bend: every law is a computation on fixed bytes.

def Lma.ma_login_bytes():
  {==}

def Lma.ma_players_bytes():
  {==}

def Lma.ma_lookup_bytes():
  {==}

def Lma.ma_reads_hello():
  {==}

def Lma.ma_reads_auth_required():
  {==}

def Lma.ma_reads_bad_token():
  {==}

def Lma.ma_reads_login():
  {==}

def Lma.ma_reads_play_event():
  {==}

def Lma.ma_reads_play_report():
  {==}

def Lma.ma_reads_catalog_ids():
  {==}

def Lma.ma_reads_players():
  {==}

def Lma.ma_players_drop_device_details():
  {==}

def read_ok(m: Maybe<&2, List<&2, J.Cap>>, h: {J.caps.ok(Api.wants(), m) == True{} : Bool})
    -> {J.all.ok(Api.wants(), Model.read.on_scan(m)) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{caps}:
      h

def Lma.model_reads_only_wanted(bs):
  read_ok(J.scan(Api.wants(), bs), Pc.finished_ok(Api.wants(), J.run(bs, Api.wants(), J.start())))
