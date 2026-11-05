import Base
import ../lib/wire/bytes.bend as B
import ../lib/bridge/conf.bend as C
# Laws of the config file (lib/bridge/conf.bend).

def u(s: String) -> B.Bytes:
  B.utf8(s)

def texts(ps: List<&2, C.Problem>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      C.problem.text(p) <> texts(t)

# Comments, a blank line, a CRLF line, a password with spaces and #, and four mistakes.
def sample() -> B.Bytes:
  u("# a sample\n\nma_host 10.0.0.5\nma_port 8095\nma_token abc.def\nmqtt_host broker.local\r\n"
    ++ "mqtt_user music\nmqtt_password p a#ss  word \ntopic_prefix home/music\nmqtt_port 99999\n"
    ++ "client_id two words\nwhat_is this\nplays_file off\ntopic_prefix +bad\n")

# Every value as written; each mistake is reported by its line and changes nothing.
law conf_sample:
  {C.read.conf(C.parse(sample()))
    == C.Conf{C.Ma{"10.0.0.5", 8095, "abc.def"},
         C.Mq{"broker.local", 1883, "music", "p a#ss  word", "music-assistant-mqtt"},
         C.Out{"home/music", ""}} : C.Conf}

law conf_sample_problems:
  {texts(C.read.problems(C.parse(sample())))
    == ["config line 10: a port is a number in 1..65535", "config line 11: one value expected",
        "config line 12: unknown key",
        "config line 14: a topic prefix is not empty, has no + or #, and doesn't start or end with /"]
    : List<&2, String>}

# An empty file gives the defaults, and the bridge refuses to start without a broker or a token.
law conf_empty:
  {(C.read.conf(C.parse(Nil{})), texts(C.read.problems(C.parse(Nil{}))),
     C.fatal(C.read.problems(C.parse(Nil{}))))
    == (C.defaults(), ["config: mqtt_host is required", "config: ma_token is required"], True{})
    : C.Conf & List<&2, String> & Bool}

law conf_summary:
  {C.summary(C.read.conf(C.parse(sample())))
    == "Music Assistant 10.0.0.5:8095, broker music@broker.local:1883 as music-assistant-mqtt, "
      ++ "topics under home/music/, plays file off" : String}

# For every config and secrets: the summary is the same whatever the token and the password.
law conf_summary_hides_secrets:
  for c: C.Conf
  for t1: String
  for p1: String
  for t2: String
  for p2: String
  {C.summary(C.with_secrets(c, t1, p1)) == C.summary(C.with_secrets(c, t2, p2)) : String}
