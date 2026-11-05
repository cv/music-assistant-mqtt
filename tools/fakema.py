#!/usr/bin/env python3
"""A fake Music Assistant for tests: the websocket API's handshake and frames, and the part of its
protocol the bridge uses (server info, auth, players/all, music/item_by_uri, events, pings).
Standard library only.

  tools/fakema.py [--port 18995] [--control 18997] [--token chaos-token]

Control port: one command per line, answered "ok":
  play N        a final play report (is_playing false) for track library://track/chaos-N
  drop          cut every connection
  garbage       send a text frame that isn't JSON
  hold on|off   don't answer lookups (music/item_by_uri) while on
  split on|off  send each message in several frames while on
"""
import argparse, asyncio, base64, hashlib, json, os, struct, sys, time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC11B65"

class Fake:
    def __init__(self, token):
        self.token = token
        self.conns = set()
        self.hold = False
        self.split = False
        self.lookups = 0

    def log(self, *a):
        print(time.strftime("%H:%M:%S"), *a, flush=True)

    # frames (server to client: unmasked)
    def frame(self, opcode, payload, fin=True):
        b0 = (0x80 if fin else 0) | opcode
        n = len(payload)
        if n < 126:
            head = struct.pack("!BB", b0, n)
        elif n < 65536:
            head = struct.pack("!BBH", b0, 126, n)
        else:
            head = struct.pack("!BBQ", b0, 127, n)
        return head + payload

    async def send_text(self, w, obj):
        data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        if self.split and len(data) > 3:
            k = len(data) // 3
            parts = [data[:k], data[k:2 * k], data[2 * k:]]
            w.write(self.frame(1, parts[0], False) + self.frame(0, parts[1], False)
                    + self.frame(0, parts[2], True))
        else:
            w.write(self.frame(1, data))
        await w.drain()

    async def read_frame(self, r):
        b0, b1 = await r.readexactly(2)
        op, n = b0 & 0x0F, b1 & 0x7F
        if n == 126:
            n = struct.unpack("!H", await r.readexactly(2))[0]
        elif n == 127:
            n = struct.unpack("!Q", await r.readexactly(8))[0]
        mask = await r.readexactly(4) if b1 & 0x80 else b"\0\0\0\0"
        data = bytes(c ^ mask[i % 4] for i, c in enumerate(await r.readexactly(n)))
        return bool(b0 & 0x80), op, data, bool(b1 & 0x80)

    def player(self, i, state):
        return {"player_id": f"P{i}", "provider": "fake", "name": ["Living Room", "Kitchen"][i],
                "available": True, "playback_state": state, "volume_level": 10 + i,
                "device_info": {"model": "Fake", "ip_address": "10.0.0.9",
                                "mac_address": "00:00:00:00:00:09"},
                "current_media": {"uri": "library://track/1", "title": "Song", "artist": "Band",
                                  "album": "LP", "duration": 200},
                "active_source": "P0", "synced_to": None}

    async def handle(self, r, w):
        try:
            head = await r.readuntil(b"\r\n\r\n")
        except Exception:
            w.close(); return
        key = next((l.split(b":", 1)[1].strip() for l in head.split(b"\r\n")
                    if l.lower().startswith(b"sec-websocket-key:")), None)
        if key is None:
            w.write(b"HTTP/1.1 400 Bad Request\r\n\r\n"); w.close(); return
        accept = base64.b64encode(hashlib.sha1(key + GUID.encode()).digest())
        w.write(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        self.conns.add(w)
        self.log("connected")
        await self.send_text(w, {"server_id": "fake", "server_version": "2.10.9",
                                 "schema_version": 65, "base_url": "http://fake"})
        authed = False
        pinger = asyncio.create_task(self.pings(w))
        buf = b""
        try:
            while True:
                fin, op, data, masked = await self.read_frame(r)
                if not masked:
                    self.log("unmasked client frame"); break
                if op == 9:
                    w.write(self.frame(10, data)); await w.drain(); continue
                if op == 10:
                    continue
                if op == 8:
                    break
                buf += data
                if not fin:
                    continue
                msg, buf = json.loads(buf), b""
                mid, cmd = msg.get("message_id"), msg.get("command")
                if cmd == "auth":
                    if msg.get("args", {}).get("token") == self.token:
                        authed = True
                        await self.send_text(w, {"message_id": mid, "result": {"authenticated": True}})
                    else:
                        await self.send_text(w, {"message_id": mid, "error_code": 23,
                                                 "details": "The access token is invalid or has expired."})
                elif not authed:
                    await self.send_text(w, {"message_id": mid, "error_code": 20,
                                             "details": "Authentication is required."})
                elif cmd == "players/all":
                    await self.send_text(w, {"message_id": mid,
                                             "result": [self.player(0, "playing"), self.player(1, "idle")]})
                elif cmd == "music/item_by_uri":
                    self.lookups += 1
                    if not self.hold:
                        n = msg["args"]["uri"].rsplit("-", 1)[-1]
                        await self.send_text(w, {"message_id": mid, "result": {
                            "external_ids": [["isrc", f"XX{n}"]],
                            "provider_mappings": [{"provider_domain": "apple_music", "item_id": n},
                                                  {"provider_domain": "spotify", "item_id": f"s{n}"}]}})
                else:
                    await self.send_text(w, {"message_id": mid, "error_code": 999,
                                             "details": f"unknown command {cmd}"})
        except Exception as e:
            self.log("connection ended:", type(e).__name__)
        finally:
            pinger.cancel()
            self.conns.discard(w)
            w.close()

    async def pings(self, w):
        while True:
            await asyncio.sleep(5)
            w.write(self.frame(9, b"fake")); await w.drain()

    async def play(self, n):
        ev = {"event": "media_item_played", "object_id": f"library://track/chaos-{n}", "data": {
            "uri": f"library://track/chaos-{n}", "media_type": "track", "name": f"Chaos {n}",
            "artist": "Band", "album": "LP", "duration": 200, "seconds_played": 190,
            "fully_played": True, "is_playing": False, "player_id": "P0"}}
        for w in list(self.conns):
            await self.send_text(w, ev)

    async def control(self, r, w):
        while True:
            line = await r.readline()
            if not line:
                break
            parts = line.decode().split()
            if not parts:
                continue
            cmd, arg = parts[0], (parts[1] if len(parts) > 1 else "")
            if cmd == "play":
                await self.play(arg)
            elif cmd == "drop":
                for c in list(self.conns):
                    c.transport.abort()
            elif cmd == "garbage":
                for c in list(self.conns):
                    await self.send_text(c, b"this is not json")
            elif cmd == "hold":
                self.hold = arg == "on"
            elif cmd == "split":
                self.split = arg == "on"
            elif cmd == "lookups":
                w.write(f"{self.lookups}\n".encode()); await w.drain(); continue
            self.log("control:", cmd, arg)
            w.write(b"ok\n"); await w.drain()
        w.close()

async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=18995)
    ap.add_argument("--control", type=int, default=18997)
    ap.add_argument("--token", default="chaos-token")
    a = ap.parse_args()
    f = Fake(a.token)
    s1 = await asyncio.start_server(f.handle, "127.0.0.1", a.port)
    s2 = await asyncio.start_server(f.control, "127.0.0.1", a.control)
    f.log(f"fake Music Assistant on {a.port}, control on {a.control}")
    async with s1, s2:
        await asyncio.gather(s1.serve_forever(), s2.serve_forever())

if __name__ == "__main__":
    asyncio.run(main())
