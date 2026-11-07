// music-queue-card: a player's queue window for Home Assistant dashboards.
//
//   type: custom:music-queue-card
//   entity: media_player.living_room         # the player shown in the middle (its media control)
//   player: media_player.ma_living_room      # Music Assistant's player, for replaying (default: entity)
//   queue: sensor.living_room_queue          # its window, from music-assistant-mqtt
//   previous: 4                              # how many of the last plays to show (at most 5)
//   next: 5                                  # how many of the next items to show (at most 5)
//   search: true                             # the lookup box under the list (default true)
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
//
// The lookup box searches Music Assistant (rest_command.ma_search_track) as you type: songs, artists
// and playlists (at most 6, 2 and 3; one row each: the library's copy first, then Apple Music's, then
// Spotify's; the best name matches first). A song goes right after the songs shown (added at the end
// with rest_command.ma_add_to_queue, then moved up with ma_move_queue_item); an artist's songs
// (shuffled, as Music Assistant plays an artist) or a playlist's go there too (added after the current
// song, then the songs shown moved ahead of them). Added songs show as more rows (up to 5, then "and
// N more added") until they come into the window.
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

// A Music Assistant track's artists ("A/B", as its queue names them) and artwork address.
const artists = (t) => (t.artists || []).map((a) => a.name).filter(Boolean).join("/");
const image = (t) => {
  const pick = (im) => (im && im.path && /^https?:/.test(im.path) ? im.path : "");
  return pick(t.image) || pick(t.album && t.album.image)
    || pick(((t.metadata && t.metadata.images) || [])[0]) || "";
};

class MusicQueueCard extends HTMLElement {
  setConfig(config) {
    if (!config.entity) throw new Error("entity (a media_player) is required");
    if (!config.queue) throw new Error("queue (the window's sensor) is required");
    this._config = { previous: 4, next: 5, search: true, ...config };
    this._key = null;
    this._pending = null;
    this._extras = this._extras || [];
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
        .search { padding: 4px 12px 12px; }
        .search[hidden] { display: none; }
        .box { position: relative; }
        .box ha-icon { position: absolute; left: 10px; top: 50%; transform: translateY(-50%);
          --mdc-icon-size: 20px; color: var(--secondary-text-color); pointer-events: none; }
        .box input { width: 100%; box-sizing: border-box; padding: 10px 12px 10px 38px;
          border-radius: 10px; border: 1px solid var(--divider-color); outline: none;
          background: var(--secondary-background-color); color: var(--primary-text-color);
          font: inherit; font-size: 0.95em; }
        .box input:focus { border-color: var(--primary-color); }
        .box input::placeholder { color: var(--secondary-text-color); }
        .results { padding-top: 4px; }
        .results .row { margin: 0; padding: 6px 4px; }
        .results .row.active { background: var(--secondary-background-color); }
        .art.round { border-radius: 50%; }
        .art ha-icon { --mdc-icon-size: 22px; color: var(--secondary-text-color); }
        .more { padding: 2px 16px 6px 68px; color: var(--secondary-text-color); font-size: 0.85em; }
        /* a song on two lines: its artist (and album) small above, its title below */
        .two { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1px; }
        .l1, .l2 { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .l1 { font-size: 0.85em; color: var(--secondary-text-color); }
        .l2 { font-size: 1em; color: var(--primary-text-color); }
        .prev .l2 { color: var(--secondary-text-color); }
        .hint { padding: 8px 4px 2px; color: var(--secondary-text-color); font-size: 0.85em; }
      </style>
      <ha-card>
        <div class="list prev"></div>
        <div class="player"></div>
        <div class="list next"></div>
        <div class="search">
          <div class="box"><ha-icon icon="mdi:magnify"></ha-icon><input type="search"
            placeholder="Add a song or an artist's song…" autocomplete="off" spellcheck="false"
            aria-label="Find a song to add after these"></div>
          <div class="results" role="listbox"></div>
        </div>
      </ha-card>`;
    this._prevEl = this._root.querySelector(".prev");
    this._nextEl = this._root.querySelector(".next");
    this._playerEl = this._root.querySelector(".player");
    this._searchEl = this._root.querySelector(".search");
    this._input = this._root.querySelector(".box input");
    this._resultsEl = this._root.querySelector(".results");
    this._searchEl.hidden = !this._config.search;
    this._results = [];
    this._active = -1;
    this._input.addEventListener("input", () => this._typed());
    this._input.addEventListener("keydown", (e) => this._keys(e));
    this._input.addEventListener("blur", () => setTimeout(() => {
      if (this._root.activeElement !== this._input) this._showResults(false);
    }, 250));
    this._input.addEventListener("focus", () => this._showResults(true));
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
    // songs added from the lookup box: dropped when the queue changes, or once they have been in
    // the window and left it (played, removed)
    if (this._window && this._window.queue !== a.queue) this._extras = [];
    const ids = new Set((a.next || []).map((n) => n.id));
    this._extras = this._extras.filter((x) => {
      if (x.adding) return true;
      if (ids.has(x.id)) x.seen = true;
      return ids.has(x.id) || !x.seen;
    });
    this._window = a;
    this._render();
  }

  _render() {
    const a = this._window || {};
    const prev = (a.previous || []).slice(-this._config.previous);
    const shown = (a.next || []).slice(0, this._config.next);
    // added songs after the window: up to 5 rows, then a line for the rest
    const added = this._extras.filter((x) => x.adding || !shown.some((n) => n.id === x.id));
    const next = shown.concat(added.slice(0, 5));
    const more = added.length - 5;
    this._prev = prev;
    this._next = next;
    this._prevEl.innerHTML = prev.map((p, i) => {
      const skipped = Number(p.seconds) < 30 && Number(p.seconds) < Number(p.duration) - 10;
      return this._row("p", i, p.image, p.duration, [p.artist || "", p.title],
        skipped ? "skipped" : "");
    }).join("");
    this._nextEl.innerHTML = next.length
      ? next.map((n, i) => this._row("n", i, n.image, n.duration, n.name, n.adding ? "adding…" : "")).join("")
        + (more > 0 ? '<div class="more">and ' + more + " more added</div>" : "")
      : '<div class="empty">Nothing queued next</div>';
  }

  // [art] artist above title (note) 01:23 [✕]; name is [artist, title] or "Artist - Title" (as Music
  // Assistant names queue items: split at the first " - ")
  _row(kind, i, image, duration, name, note) {
    const [artist, title] = Array.isArray(name) ? name
      : String(name || "").includes(" - ") ? [String(name).split(" - ")[0], String(name).split(" - ").slice(1).join(" - ")]
      : ["", String(name || "")];
    const starting = this._pending === kind + i;
    const removing = kind === "n" && this._pending === "d" + i;
    const src = thumb(image);
    const art = src
      ? '<img class="art" alt="" loading="lazy" src="' + esc(src) + '" onerror="this.replaceWith(Object.assign(document.createElement(\'div\'), {className: \'art\', textContent: \'♪\'}))">'
      : '<div class="art">♪</div>';
    const n = starting ? "starting…" : removing ? "removing…" : note;
    const del = kind === "n" && !removing && !(this._next && this._next[i] && this._next[i].adding)
      ? '<button class="del" data-del="' + i + '" title="Remove, and add a similar song at the end" aria-label="Remove">✕</button>'
      : "";
    return '<div class="row' + (starting || removing ? " starting" : "") + '" role="button" tabindex="0" data-kind="'
      + kind + '" data-i="' + i + '" title="' + esc((artist ? artist + " - " : "") + title) + '">' + art
      + '<span class="two">' + (artist ? '<span class="l1">' + esc(artist) + "</span>" : "")
      + '<span class="l2">' + esc(title) + "</span></span>"
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
    if (row.dataset.kind === "s") {
      this._choose(i);
      return;
    }
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
        this._extras = this._extras.filter((x) => x.id !== n.id);
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

  // --- the lookup box ---

  _typed() {
    clearTimeout(this._debounce);
    const q = this._input.value.trim();
    if (q.length < 2) {
      this._results = [];
      this._hint = "";
      return this._renderResults();
    }
    this._debounce = setTimeout(() => this._search(q), 300);
  }

  async _search(q) {
    const seq = (this._seq = (this._seq || 0) + 1);
    this._hint = "Searching…";
    this._renderResults();
    let found = {};
    try {
      found = (await this._ma("ma_search_track", {
        query: q, limit: 12, media_types: ["track", "artist", "playlist"],
      })) || {};
    } catch (err) {
      console.warn("music-queue-card: search failed:", err);
    }
    if (seq !== this._seq) return;   // a newer search is under way
    // one row per song, artist or playlist: the library's copy, else Apple Music's, else Spotify's
    const rank = (t) => (t.provider === "library" ? 0 : String(t.provider).startsWith("apple_music") ? 1 : 2);
    const norm = (s) => String(s || "").toLowerCase().replace(/\s*[([][^)\]]*[)\]]/g, "").trim();
    const keyOf = {
      track: (t) => norm(artists(t)) + "|" + norm(t.name),
      artist: (t) => norm(t.name),
      playlist: (t) => norm(t.name) + "|" + norm(t.owner),
    };
    const lists = { track: found.tracks || [], artist: found.artists || [], playlist: found.playlists || [] };
    const picked = [];
    for (const [type, items] of Object.entries(lists)) {
      const best = new Map();
      items.forEach((t, order) => {
        if (!t || !t.uri) return;
        const k = keyOf[type](t);
        const had = best.get(k);
        if (!had || rank(t) < rank(had.t)) best.set(k, { t, type, order: had ? had.order : order });
      });
      picked.push(...best.values());
    }
    // how well the name matches what was typed, then the library first, then the search's order;
    // at most 2 artists, 3 playlists and 6 songs, 8 rows in all
    const qn = norm(q);
    const match = (x) => {
      const n = norm(x.t.name);
      const whole = x.type === "track" ? norm(artists(x.t) + " " + x.t.name) : n;
      return n === qn ? 3 : n.startsWith(qn) ? 2 : n.includes(qn) || whole.includes(qn) ? 1 : 0;
    };
    picked.sort((x, y) => match(y) - match(x) || rank(x.t) - rank(y.t) || x.order - y.order);
    const caps = { artist: 2, playlist: 3, track: 6 };
    const seen = { artist: 0, playlist: 0, track: 0 };
    this._results = picked.filter((x) => seen[x.type]++ < caps[x.type]).slice(0, 8)
      .map((x) => Object.assign(x.t, { _type: x.type }));
    this._active = this._results.length ? 0 : -1;
    this._hint = this._results.length ? "" : "No matches";
    this._renderResults();
  }

  // A suggestion's two lines: a song's artist (and album) above its title; "Artist" or
  // "Playlist · owner" above an artist's or a playlist's name.
  _lines(t) {
    if (t._type === "artist") return ["Artist · its songs, shuffled", t.name];
    if (t._type === "playlist") return ["Playlist" + (t.owner ? " · " + t.owner : ""), t.name];
    return [artists(t) + (t.album && t.album.name ? " · " + t.album.name : ""), t.name];
  }

  _renderResults() {
    const rows = this._results.map((t, i) => {
      const src = thumb(image(t));
      const icon = t._type === "artist" ? "mdi:account-music" : t._type === "playlist" ? "mdi:playlist-music" : "";
      const art = src
        ? '<img class="art' + (t._type === "artist" ? " round" : "") + '" alt="" loading="lazy" src="' + esc(src) + '">'
        : icon ? '<div class="art"><ha-icon icon="' + icon + '"></ha-icon></div>' : '<div class="art">♪</div>';
      const [l1, l2] = this._lines(t);
      return '<div class="row' + (i === this._active ? " active" : "") + '" role="option" tabindex="0" data-kind="s" data-i="'
        + i + '" title="' + esc(l1 + " - " + l2) + '">' + art + '<span class="two"><span class="l1">'
        + esc(l1) + '</span><span class="l2">' + esc(l2) + '</span></span><span class="time">'
        + (t._type === "track" ? length(t.duration) : "") + "</span></div>";
    });
    this._resultsEl.innerHTML = rows.join("") + (this._hint ? '<div class="hint">' + esc(this._hint) + "</div>" : "");
  }

  _showResults(on) {
    this._resultsEl.style.display = on ? "" : "none";
  }

  _keys(e) {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!this._results.length) return;
      const d = e.key === "ArrowDown" ? 1 : -1;
      this._active = (this._active + d + this._results.length) % this._results.length;
      this._renderResults();
    } else if (e.key === "Enter") {
      e.preventDefault();
      e.stopPropagation();
      if (this._active >= 0) this._choose(this._active);
    } else if (e.key === "Escape") {
      this._input.value = "";
      this._typed();
    }
  }

  // Adds result i right after the songs shown: a song at the end of the queue first, then moved up;
  // an artist's or a playlist's songs right after the current one, then the songs shown moved up
  // ahead of them (a few moves however many songs came).
  _choose(i) {
    const t = this._results[i];
    const queue = this._window && this._window.queue;
    if (!t || !queue) return;
    this._input.value = "";
    this._results = [];
    this._hint = "";
    this._renderResults();
    if (t._type === "artist" || t._type === "playlist") return this._chooseMany(t, queue);
    const row = { adding: true, name: artists(t) + " - " + t.name, duration: t.duration, image: image(t), uri: t.uri };
    this._extras.push(row);
    this._render();
    this._chain = (this._chain || Promise.resolve()).then(async () => {
      try {
        await this._ma("ma_add_to_queue", { queue, uri: t.uri });
        const q = await this._ma("ma_get_queue", { queue });
        const count = Number(q && q.items) || 0;
        const cur = Number(q && q.current_index) || 0;
        // the added item: the last one with its uri, near the end
        const tail = await this._ma("ma_queue_items", { queue, offset: Math.max(0, count - 5), limit: 5 });
        let at = -1;
        (Array.isArray(tail) ? tail : []).forEach((it, k) => {
          if (it.media_item && it.media_item.uri === t.uri) at = k;
        });
        if (at < 0) throw new Error("the added song isn't at the end of the queue");
        const item = tail[at];
        const index = Math.max(0, count - 5) + at;
        // the song shown last before this one: the new one goes right after it
        const before = this._next.filter((n) => !n.adding && n.id);
        const anchor = before.length ? before[before.length - 1].id : null;
        const near = await this._ma("ma_queue_items", { queue, offset: cur, limit: 25 });
        const ai = Array.isArray(near) ? near.findIndex((it) => it.queue_item_id === anchor) : -1;
        const target = ai >= 0 ? cur + ai + 1 : cur + 1;
        if (target < index) await this._ma("ma_move_queue_item", { queue, item: item.queue_item_id, shift: target - index });
        Object.assign(row, { adding: false, id: item.queue_item_id, name: item.name || row.name,
          duration: item.duration || row.duration });
      } catch (err) {
        console.warn("music-queue-card: adding", row.name, "failed:", err);
        this._extras = this._extras.filter((x) => x !== row);
      }
      this._render();
    });
  }

  _chooseMany(t, queue) {
    const row = { adding: true, name: this._lines(t), image: image(t), uri: t.uri };
    this._extras.push(row);
    this._render();
    // the rows shown before this one, in order: they stay ahead of the new songs
    const ahead = this._next.filter((n) => !n.adding && n.id).map((n) => n.id);
    this._chain = (this._chain || Promise.resolve()).then(async () => {
      try {
        const q0 = await this._ma("ma_get_queue", { queue });
        const cur0 = Number(q0 && q0.current_index) || 0;
        const count0 = Number(q0 && q0.items) || 0;
        const old = await this._ma("ma_queue_items", { queue, offset: cur0, limit: 60 });
        const known = new Set((Array.isArray(old) ? old : []).map((it) => it.queue_item_id));
        await this._ma("ma_add_to_queue", { queue, uri: t.uri, option: "next" });
        const q = await this._ma("ma_get_queue", { queue });
        const cur = Number(q && q.current_index) || 0;
        const added = (Number(q && q.items) || 0) - count0;
        if (added <= 0) throw new Error("nothing was added");
        const near = await this._ma("ma_queue_items", { queue, offset: cur, limit: Math.min(500, added + 60) });
        const list = Array.isArray(near) ? near : [];
        const b = list.findIndex((it) => !known.has(it.queue_item_id));
        if (b < 0) throw new Error("the added songs aren't near the current one");
        let n = 0;
        while (b + n < list.length && !known.has(list[b + n].queue_item_id)) n++;
        const block = list.slice(b, b + n);
        // move the rows shown after the new songs up ahead of them, in their order
        let k = 0;
        for (const id of ahead) {
          const at = list.findIndex((it) => it.queue_item_id === id);
          if (at < b + n) continue;   // already ahead
          await this._ma("ma_move_queue_item", { queue, item: id, shift: b + k - at });
          k++;
        }
        const rows = block.map((it) => ({
          id: it.queue_item_id, name: it.name, duration: it.duration,
          image: image(it.media_item || {}) || image(it), uri: it.media_item && it.media_item.uri,
        }));
        this._extras.splice(this._extras.indexOf(row), 1, ...rows);
      } catch (err) {
        console.warn("music-queue-card: adding", t.name, "failed:", err);
        this._extras = this._extras.filter((x) => x !== row);
      }
      this._render();
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
