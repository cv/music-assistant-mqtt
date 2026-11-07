// music-queue-card: a player's queue window for Home Assistant dashboards.
//
//   type: custom:music-queue-card
//   entity: media_player.living_room         # the player shown in the middle (its media control)
//   player: media_player.ma_living_room      # Music Assistant's player, for replaying (default: entity)
//   queue: sensor.living_room_queue          # its window, from music-assistant-mqtt
//   previous: 4                              # how many of the last plays to show (at most 5)
//   next: 5                                  # how many of the next items to show (at most 5)
//
// The window comes from music-assistant-mqtt's <prefix>/<player>/queue topic, as an MQTT sensor's
// attributes: "previous" (the last plays, oldest first) and "next" (the queue's next items). A tap
// on a previous play plays it again now (music_assistant.play_media); a tap on a next item jumps to
// it (rest_command.ma_play_queue_item, which calls Music Assistant's player_queues/play_index with
// the item's id, so nothing in between is played or counted as a skip). A next item's ✕ removes it
// from the queue (rest_command.ma_delete_queue_item) and adds a similar song at the end instead,
// picked the way Music Assistant's Autoplay picks its songs: up to 5 random songs of the queue's
// sources (the playlists, albums or artists it was started from; rest_command.ma_get_queue,
// ma_source_tracks), else the song playing now, each asked for similar songs
// (rest_command.ma_similar_tracks); the first one not already queued nor just played, under 20
// minutes, goes at the end (rest_command.ma_add_to_queue). Autoplay's own seeds (the last 10 things
// queued by hand) aren't in Music Assistant's API: a queue built item by item shows few sources.

const length = (s) => {
  s = Math.max(0, Math.round(Number(s) || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = String(s % 60).padStart(2, "0");
  return h ? h + ":" + String(m).padStart(2, "0") + ":" + ss : String(m).padStart(2, "0") + ":" + ss;
};

// A small version of an artwork address (Apple's and Spotify's image servers serve any size;
// 96 px and 64 px instead of 600-1000 px), or nothing for an address a browser couldn't load
// everywhere (only https: an http image is blocked on an https dashboard).
const thumb = (u) => {
  u = String(u || "");
  if (!u.startsWith("https://")) return "";
  if (u.includes("mzstatic.com/")) return u.replace(/\/\d+x\d+[a-z]*\.(jpg|jpeg|png|webp)$/i, "/96x96bb.jpg");
  if (u.includes("i.scdn.co/image/ab67616d0000b273")) return u.replace("ab67616d0000b273", "ab67616d00004851");
  return u;
};

const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

class MusicQueueCard extends HTMLElement {
  setConfig(config) {
    if (!config.entity) throw new Error("entity (a media_player) is required");
    if (!config.queue) throw new Error("queue (the window's sensor) is required");
    this._config = { previous: 4, next: 5, ...config };
    this._key = null;
    this._pending = null;
    if (!this._root) this._build();
  }

  _build() {
    this._root = this.attachShadow({ mode: "open" });
    this._root.innerHTML = `
      <style>
        ha-card { overflow: hidden; }
        .list { padding: 4px 0; }
        .row {
          display: flex; align-items: center; gap: 12px; padding: 6px 16px;
          cursor: pointer; border-radius: 8px; margin: 0 4px;
          color: var(--primary-text-color); line-height: 1.3;
        }
        .row:hover { background: var(--secondary-background-color); }
        .row:focus-visible { outline: 2px solid var(--primary-color); }
        .prev .row { color: var(--secondary-text-color); }
        .time {
          font-variant-numeric: tabular-nums; flex: none; min-width: 3.2em; text-align: right;
          color: var(--secondary-text-color); font-size: 0.9em;
        }
        .art {
          flex: none; width: 40px; height: 40px; border-radius: 4px; object-fit: cover;
          background: var(--secondary-background-color); display: flex; align-items: center;
          justify-content: center; color: var(--secondary-text-color); font-size: 18px;
        }
        .prev .art { opacity: 0.75; }
        .name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .note { flex: none; font-size: 0.8em; color: var(--secondary-text-color); opacity: 0.8; }
        .starting { opacity: 0.6; }
        .del {
          flex: none; border: none; background: none; cursor: pointer; padding: 4px 6px;
          margin: -4px -8px -4px 0; border-radius: 50%; font-size: 1em; line-height: 1;
          color: var(--secondary-text-color); opacity: 0.6;
        }
        .del:hover, .del:focus-visible { opacity: 1; background: var(--divider-color); }
        .empty { padding: 6px 16px; color: var(--secondary-text-color); font-size: 0.9em; }
        .player { padding: 0; }
        .player > * { --ha-card-border-width: 0; --ha-card-box-shadow: none; }
      </style>
      <ha-card>
        <div class="list prev"></div>
        <div class="player"></div>
        <div class="list next"></div>
      </ha-card>`;
    this._prevEl = this._root.querySelector(".prev");
    this._nextEl = this._root.querySelector(".next");
    this._playerEl = this._root.querySelector(".player");
    this._root.addEventListener("click", (e) => this._tap(e));
    this._root.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") this._tap(e);
    });
  }

  async _player() {
    if (this._media || this._mediaLoading) return;
    this._mediaLoading = true;
    const helpers = await window.loadCardHelpers();
    this._media = await helpers.createCardElement({ type: "media-control", entity: this._config.entity });
    this._media.hass = this._hass;
    this._playerEl.appendChild(this._media);
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    this._player();
    if (this._media) this._media.hass = hass;
    const st = hass.states[this._config.queue];
    const a = (st && st.attributes) || {};
    const key = JSON.stringify([a.previous, a.next, a.index]);
    if (key === this._key) return;
    this._key = key;
    this._pending = null;
    this._window = a;
    this._render();
  }

  _render() {
    const a = this._window || {};
    const prev = (a.previous || []).slice(-this._config.previous);
    const next = (a.next || []).slice(0, this._config.next);
    this._prevEl.innerHTML = prev.map((p, i) => {
      const skipped = Number(p.seconds) < 30 && Number(p.seconds) < Number(p.duration) - 10;
      return this._row("p", i, p.image, p.duration, (p.artist ? p.artist + " - " : "") + p.title,
        skipped ? "skipped" : "");
    }).join("");
    this._nextEl.innerHTML = next.length
      ? next.map((n, i) => this._row("n", i, n.image, n.duration, n.name, "")).join("")
      : '<div class="empty">Nothing queued next</div>';
    this._prev = prev;
    this._next = next;
  }

  // [art] Artist - Song (note) 01:23
  _row(kind, i, image, duration, name, note) {
    const starting = this._pending === kind + i;
    const removing = kind === "n" && this._pending === "d" + i;
    const src = thumb(image);
    const art = src
      ? '<img class="art" alt="" loading="lazy" src="' + esc(src) + '" onerror="this.replaceWith(Object.assign(document.createElement(\'div\'), {className: \'art\', textContent: \'♪\'}))">'
      : '<div class="art">♪</div>';
    const n = starting ? "starting…" : removing ? "removing…" : note;
    const del = kind === "n" && !removing
      ? '<button class="del" data-del="' + i + '" title="Remove, and add a similar song at the end" aria-label="Remove">✕</button>'
      : "";
    return '<div class="row' + (starting || removing ? " starting" : "") + '" role="button" tabindex="0" data-kind="'
      + kind + '" data-i="' + i + '">' + art + '<span class="name">' + esc(name) + "</span>"
      + (n ? '<span class="note">' + esc(n) + "</span>" : "") + '<span class="time">'
      + length(duration) + "</span>" + del + "</div>";
  }

  _tap(e) {
    const path = e.composedPath();
    const del = path.find((el) => el.classList && el.classList.contains("del"));
    if (del && this._hass) {
      e.preventDefault();
      e.stopPropagation();
      this._remove(Number(del.dataset.del));
      return;
    }
    const row = path.find((el) => el.classList && el.classList.contains("row"));
    if (!row || !this._hass) return;
    e.preventDefault();
    const i = Number(row.dataset.i);
    if (row.dataset.kind === "p") {
      const p = this._prev[i];
      if (!p || !p.uri) return;
      this._hass.callService("music_assistant", "play_media", {
        entity_id: this._config.player || this._config.entity, media_id: p.uri, media_type: "track", enqueue: "play",
      });
    } else {
      const n = this._next[i];
      if (!n || !n.id || !this._window.queue) return;
      this._hass.callService("rest_command", "ma_play_queue_item", { queue: this._window.queue, item: n.id });
    }
    this._pending = row.dataset.kind + i;
    this._render();
  }

  // A rest_command's answer (Music Assistant's result), or an error for a refused call.
  async _ma(service, data) {
    const r = await this._hass.callWS({
      type: "call_service", domain: "rest_command", service, service_data: data, return_response: true,
    });
    const res = (r && r.response) || {};
    if (res.status !== 200) throw new Error(service + ": status " + res.status);
    return res.content;
  }

  // Removes next item i, then adds a similar song at the end of the queue (removals run one at a time).
  _remove(i) {
    const n = this._next && this._next[i];
    const queue = this._window && this._window.queue;
    if (!n || !n.id || !queue) return;
    this._pending = "d" + i;
    this._render();
    const prev = (this._window.previous || []).map((p) => p.title);
    const index = Number(this._window.index) || 0;
    this._chain = (this._chain || Promise.resolve()).then(async () => {
      try {
        await this._ma("ma_delete_queue_item", { queue, item: n.id });
        const uri = await this._replacement(queue, index, n, prev);
        if (uri) await this._ma("ma_add_to_queue", { queue, uri });
        else console.info("music-queue-card: no similar song to add for", n.name);
      } catch (err) {
        console.warn("music-queue-card: removing", n.name, "failed:", err);
        this._pending = null;
        this._render();
      }
    });
  }

  // A song for the end of the queue, like Autoplay's: similar to up to 5 random songs of the queue's
  // sources (else the song playing now, then the queue's last one), not already in the queue (from
  // the current one on) nor just played, under 20 minutes; its uri, or null.
  async _replacement(queue, index, removed, prev) {
    const key = (t) => String(t || "").toLowerCase().replace(/\s*[([][^)\]]*[)\]]/g, "").trim();
    const title = (name) => String(name || "").split(" - ").slice(1).join(" - ") || name;
    const shuffle = (xs) => {
      xs = xs.slice();
      for (let i = xs.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [xs[i], xs[j]] = [xs[j], xs[i]];
      }
      return xs;
    };
    const quiet = async (service, data) => {
      try {
        return await this._ma(service, data);
      } catch (err) {
        console.warn("music-queue-card:", service, "failed:", err);
        return null;
      }
    };
    const list = (x) => (Array.isArray(x) ? x : []);
    const items = list(await quiet("ma_queue_items", { queue, offset: index, limit: 100 }));
    const taken = new Set([removed.name, ...prev].map((t) => key(title(t))));
    for (const it of items) taken.add(key((it.media_item && it.media_item.name) || title(it.name)));
    for (const t of prev) taken.add(key(t));
    // The seeds: songs of the queue's sources, as Autoplay samples them.
    const q = (await quiet("ma_get_queue", { queue })) || {};
    let bases = [];
    for (const s of shuffle(list(q.sources))) {
      if (s.media_type === "track") {
        if (s.uri) bases.push({ uri: s.uri, name: s.name });
      } else if (["playlist", "album", "artist"].includes(s.media_type)) {
        const tracks = list(await quiet("ma_source_tracks", {
          media_type: s.media_type, item_id: s.item_id, provider: s.provider,
        }));
        bases.push(...tracks.filter((t) => t && t.uri).map((t) => ({ uri: t.uri, name: t.name })));
      }
    }
    bases = shuffle(bases).slice(0, 5);
    const current = q.current_item && q.current_item.media_item;
    const last = items.length ? items[items.length - 1].media_item : null;
    for (const t of [current, last]) {
      if (t && t.uri && !bases.some((b) => b.uri === t.uri)) bases.push({ uri: t.uri, name: t.name });
    }
    for (const base of bases) {
      const m = /^([^:]+):\/\/track\/(.+)$/.exec(String(base.uri || ""));
      if (!m) continue;
      const similar = list(await quiet("ma_similar_tracks", { provider: m[1], item_id: m[2] }));
      for (const s of similar) {
        if (!s || !s.uri || s.uri === base.uri || key(s.name) === key(base.name)) continue;
        if (taken.has(key(s.name)) || Number(s.duration) > 20 * 60) continue;
        return s.uri;
      }
    }
    return null;
  }

  getCardSize() {
    return 4 + (this._config ? this._config.previous + this._config.next : 9) / 2;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }
}

customElements.define("music-queue-card", MusicQueueCard);
window.customCards = window.customCards || [];
window.customCards.push({
  type: "music-queue-card",
  name: "Music queue",
  description: "A player's last plays, its media control and its next items (music-assistant-mqtt).",
});
