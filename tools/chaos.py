#!/usr/bin/env python3
"""Chaos tests for the bridge: the program (built for this machine) against a fake Music Assistant
(tools/fakema.py) and a test broker, each reached through a proxy that can cut, stall and
fragment the connection. Breaks things on purpose and checks what must hold afterwards:
  - the bridge is live again and its status topic says online,
  - every final play report is published exactly once, with its catalog ids, also one that was
    waiting for its lookup when the link broke,
  - the reconnect waits stay within 1..60 s,
  - memory and open files don't grow across reconnects.

  tools/chaos.py [--build] [--list] [scenario ...]    (default: every scenario; about 6 minutes)

Needs mosquitto, mosquitto_sub and mosquitto_passwd (e.g. Homebrew's) and, with --build, bend.
Everything listens on 127.0.0.1 only.
"""
import asyncio, os, re, secrets, shutil, signal, socket, subprocess, sys, threading, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(os.environ.get("TMPDIR", "/tmp"), "mam-chaos")
BIN = os.path.join(WORK, "mam")
BROKER, BROKER_PROXY, MA, MA_PROXY, CONTROL = 18941, 18942, 18995, 18996, 18997
USER, PASSWORD, TOKEN = "music", secrets.token_hex(12), "chaos-token"
PREFIX = "chaos"

def tool(name):
    return shutil.which(name) or next((p for p in (f"/opt/homebrew/bin/{name}", f"/opt/homebrew/sbin/{name}",
                                                   f"/usr/sbin/{name}") if os.path.exists(p)), name)

def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)

class Proxy:
    """Between the bridge and a server: pass, stall (hold everything) or frag (one byte at a time)."""
    def __init__(self, listen, target):
        self.listen, self.target, self.mode, self.conns = listen, target, "pass", set()
        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()
        asyncio.run_coroutine_threadsafe(self.start(), self.loop).result()

    async def start(self):
        self.server = await asyncio.start_server(self.on_conn, "127.0.0.1", self.listen)

    async def pump(self, r, w):
        try:
            while True:
                data = await r.read(65536)
                if not data:
                    break
                while self.mode == "stall":
                    await asyncio.sleep(0.1)
                if self.mode == "frag":
                    for i in range(len(data)):
                        w.write(data[i:i + 1]); await w.drain()
                        if i % 64 == 0:
                            await asyncio.sleep(0.001)
                else:
                    w.write(data); await w.drain()
        except Exception:
            pass
        finally:
            w.close()

    async def on_conn(self, cr, cw):
        try:
            sr, sw = await asyncio.open_connection("127.0.0.1", self.target)
        except Exception:
            cw.close(); return
        self.conns |= {cw, sw}
        await asyncio.gather(self.pump(cr, sw), self.pump(sr, cw))
        self.conns -= {cw, sw}

    def cut(self):
        self.loop.call_soon_threadsafe(lambda: [w.transport.abort() for w in list(self.conns)])

class Broker:
    def __init__(self):
        self.p = None
        open(f"{WORK}/mosq.conf", "w").write(
            f"listener {BROKER} 127.0.0.1\nallow_anonymous false\npassword_file {WORK}/mosq.pw\n"
            "max_queued_messages 20000\n")
        if os.path.exists(f"{WORK}/mosq.pw"):
            os.remove(f"{WORK}/mosq.pw")
        subprocess.run([tool("mosquitto_passwd"), "-c", "-b", f"{WORK}/mosq.pw", USER, PASSWORD],
                       check=True)
        os.chmod(f"{WORK}/mosq.pw", 0o600)

    def start(self):
        self.p = subprocess.Popen([tool("mosquitto"), "-c", f"{WORK}/mosq.conf"],
                                  stdout=open(f"{WORK}/mosq.log", "a"), stderr=subprocess.STDOUT)
        time.sleep(0.5)

    def stop(self):
        if self.p:
            self.p.terminate(); self.p.wait(); self.p = None

class FakeMA:
    def __init__(self):
        self.p = subprocess.Popen([sys.executable, f"{ROOT}/tools/fakema.py", "--port", str(MA),
                                   "--control", str(CONTROL), "--token", TOKEN],
                                  stdout=open(f"{WORK}/fakema.log", "a"), stderr=subprocess.STDOUT)
        time.sleep(1.0)

    def do(self, line):
        with socket.create_connection(("127.0.0.1", CONTROL), timeout=5) as s:
            s.sendall((line + "\n").encode())
            return s.makefile().readline().strip()

    def stop(self):
        self.p.terminate(); self.p.wait()

class Bridge:
    def __init__(self, tag="bridge", token=TOKEN, prefix=PREFIX):
        self.tag = tag
        conf = f"{WORK}/{tag}.conf"
        open(conf, "w").write(
            f"ma_host 127.0.0.1\nma_port {MA_PROXY}\nma_token {token}\nmqtt_host 127.0.0.1\n"
            f"mqtt_port {BROKER_PROXY}\nmqtt_user {USER}\nmqtt_password {PASSWORD}\n"
            f"topic_prefix {prefix}\nclient_id {tag}\nplays_file {WORK}/{tag}.plays.jsonl\n")
        os.chmod(conf, 0o600)
        self.lines = []
        self.p = subprocess.Popen([BIN, conf], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  text=True, bufsize=1)
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        out = open(f"{WORK}/{self.tag}.log", "a")
        for line in self.p.stdout:
            self.lines.append((time.time(), line.rstrip("\n")))
            out.write(time.strftime("%H:%M:%S ") + line); out.flush()

    def since(self, t0, pat):
        return [l for (t, l) in self.lines if t >= t0 and re.search(pat, l)]

    def alive(self):
        return self.p.poll() is None

    def rss_kb(self):
        r = subprocess.run(["ps", "-o", "rss=", "-p", str(self.p.pid)], capture_output=True, text=True)
        return int(r.stdout.strip() or 0)

    def fds(self):
        r = subprocess.run(["lsof", "-p", str(self.p.pid)], capture_output=True, text=True)
        return max(0, len(r.stdout.splitlines()) - 1)

    def waits(self):
        return [int(m.group(1)) for (_, l) in self.lines for m in [re.search(r"next in (\d+) ms", l)] if m]

    def stop(self):
        if self.alive():
            self.p.terminate(); self.p.wait()

class Sub:
    """Everything published under the prefix, with when it arrived (straight to the broker)."""
    def __init__(self):
        self.lines, self.p = [], None

    def start(self):
        self.p = subprocess.Popen([tool("mosquitto_sub"), "-h", "127.0.0.1", "-p", str(BROKER), "-u",
                                   USER, "-P", PASSWORD, "-v", "-t", f"{PREFIX}/#"],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        threading.Thread(target=self.read, args=(self.p,), daemon=True).start()
        time.sleep(0.5)

    def read(self, p):
        for line in p.stdout:
            self.lines.append((time.time(), line.rstrip("\n")))

    def stop(self):
        if self.p:
            self.p.terminate(); self.p.wait(); self.p = None

    def plays(self, n):
        return [l for (_, l) in self.lines if l.startswith(f"{PREFIX}/played ")
                and f'"uri":"library://track/chaos-{n}"' in l]

    def status(self):
        s = [l for (_, l) in self.lines if l.startswith(f"{PREFIX}/status ")]
        return s[-1].split(" ", 1)[1] if s else None

class Run:
    def __init__(self):
        self.results, self.track = [], 0

    def check(self, sc, what, ok, detail=""):
        self.results.append((sc, what, ok, detail))
        log("PASS" if ok else "FAIL", sc + ":", what, detail)

def wait_live(br, sub, t0, limit=75):
    end = time.time() + limit
    while time.time() < end:
        if br.since(t0, r"^live: ") and sub.status() == "online":
            return time.time() - t0
        time.sleep(0.5)
    return None

def recovered(run, sc, env, t0, limit=75):
    took = wait_live(env["br"], env["sub"], t0, limit)
    run.check(sc, "live and online again", took is not None and env["br"].alive(),
              f"({took:.1f} s)" if took else "")

def plays_once(run, sc, env, n=2, wait=6):
    tracks = []
    for _ in range(n):
        run.track += 1
        tracks.append(run.track)
        env["ma"].do(f"play {run.track}")
        time.sleep(0.3)
    time.sleep(wait)
    counts = [len(env["sub"].plays(t)) for t in tracks]
    ids = all('"apple_music":"%d"' % t in (env["sub"].plays(t) or [""])[0] for t in tracks)
    run.check(sc, f"{n} final reports -> one play each, with ids", all(c == 1 for c in counts) and ids,
              f"(counts {counts})")

# Scenarios
# ---------

def sc_baseline(run, env):
    plays_once(run, "baseline", env, 3)

def sc_broker_restart(run, env):
    t0 = time.time()
    env["broker"].stop(); env["sub"].stop(); time.sleep(3)
    env["broker"].start(); env["sub"].start()
    recovered(run, "broker_restart", env, t0)
    plays_once(run, "broker_restart", env)

def sc_broker_cut(run, env):
    t0 = time.time()
    env["bp"].cut()
    recovered(run, "broker_cut", env, t0)
    plays_once(run, "broker_cut", env)

def sc_ma_drop(run, env):
    t0 = time.time()
    env["ma"].do("drop")
    recovered(run, "ma_drop", env, t0)
    plays_once(run, "ma_drop", env)

def sc_carried(run, env):
    # A final report whose lookup isn't answered, then the link breaks: the next session looks it
    # up again and publishes it once, with its ids.
    env["ma"].do("hold on")
    run.track += 1
    n = run.track
    env["ma"].do(f"play {n}")
    time.sleep(1)
    t0 = time.time()
    env["ma"].do("drop")
    env["ma"].do("hold off")
    recovered(run, "carried", env, t0)
    time.sleep(5)
    got = env["sub"].plays(n)
    run.check("carried", "a play waiting at the cut -> published once, with ids",
              len(got) == 1 and f'"apple_music":"{n}"' in got[0], f"(count {len(got)})")

def sc_garbage(run, env):
    env["ma"].do("garbage")
    time.sleep(2)
    run.check("garbage", "still live after a message that isn't JSON",
              env["br"].alive() and env["sub"].status() == "online")
    plays_once(run, "garbage", env)

def sc_split(run, env):
    env["ma"].do("split on")
    plays_once(run, "split", env)
    env["ma"].do("split off")

def sc_fragmented(run, env):
    env["bp"].mode = env["mp"].mode = "frag"
    plays_once(run, "fragmented", env, 2, 8)
    env["bp"].mode = env["mp"].mode = "pass"

def sc_ma_stall(run, env):
    # Music Assistant goes silent (nothing gets through): the session ends after 60 s.
    t0 = time.time()
    env["mp"].mode = "stall"
    time.sleep(66)
    env["mp"].mode = "pass"
    env["mp"].cut()
    ended = env["br"].since(t0, r"Music Assistant went quiet")
    run.check("ma_stall", "silence noticed", bool(ended))
    recovered(run, "ma_stall", env, t0, 100)
    plays_once(run, "ma_stall", env)

def sc_broker_stall(run, env):
    # The broker goes silent: the session ends after 90 s.
    t0 = time.time()
    env["bp"].mode = "stall"
    time.sleep(96)
    env["bp"].mode = "pass"
    env["bp"].cut()
    run.check("broker_stall", "silence noticed", bool(env["br"].since(t0, r"the broker went quiet")))
    recovered(run, "broker_stall", env, t0, 120)
    plays_once(run, "broker_stall", env)

def sc_bad_token(run, env):
    # A second bridge with a wrong token: refused, waits growing, never online.
    bad = Bridge("badtoken", token="wrong", prefix="chaos2")
    time.sleep(16)
    waits = bad.waits()
    bad.stop()
    run.check("bad_token", "refused, waits doubling", waits[:4] == [2000, 4000, 8000, 16000][:len(waits[:4])]
              and len(waits) >= 3 and bool(bad.since(0, r"refused the login|didn't accept the token")),
              f"(waits {waits})")

def sc_soak(run, env):
    br = env["br"]
    rss0, fds0 = br.rss_kb(), br.fds()
    for i in range(15):
        t0 = time.time()
        env["ma"].do("drop")
        if wait_live(br, env["sub"], t0, 30) is None:
            break
    time.sleep(2)
    rss1, fds1 = br.rss_kb(), br.fds()
    run.check("soak", "15 reconnects: memory and open files flat",
              rss1 - rss0 < 1024 and fds1 <= fds0, f"(rss {rss0} -> {rss1} kB, fds {fds0} -> {fds1})")
    plays_once(run, "soak", env)

def sc_waits(run, env):
    w = env["br"].waits()
    run.check("waits", "every reconnect wait within 1..60 s", all(1000 <= x <= 60000 for x in w),
              f"({len(w)} waits, {min(w) if w else 0}..{max(w) if w else 0} ms)")

SCENARIOS = [sc_baseline, sc_broker_restart, sc_broker_cut, sc_ma_drop, sc_carried, sc_garbage,
             sc_split, sc_fragmented, sc_bad_token, sc_soak, sc_ma_stall, sc_broker_stall, sc_waits]

def main():
    args = sys.argv[1:]
    if "--list" in args:
        print("\n".join(f.__name__[3:] for f in SCENARIOS)); return
    os.makedirs(WORK, exist_ok=True)
    if "--build" in args or not os.path.exists(BIN):
        subprocess.run(["bend", f"{ROOT}/mam.bend", "-o", BIN], check=True)
    chosen = [a for a in args if not a.startswith("--")]
    todo = [f for f in SCENARIOS if not chosen or f.__name__[3:] in chosen]
    broker, ma = Broker(), FakeMA()
    broker.start()
    env = {"broker": broker, "ma": ma, "bp": Proxy(BROKER_PROXY, BROKER), "mp": Proxy(MA_PROXY, MA),
           "sub": Sub()}
    env["sub"].start()
    run = Run()
    t0 = time.time()
    env["br"] = Bridge()
    try:
        recovered(run, "start", env, t0, 30)
        for f in todo:
            log("--", f.__name__[3:])
            f(run, env)
    finally:
        env["br"].stop(); env["sub"].stop(); ma.stop(); broker.stop()
    failed = [r for r in run.results if not r[2]]
    log(f"{len(run.results) - len(failed)}/{len(run.results)} checks passed")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
