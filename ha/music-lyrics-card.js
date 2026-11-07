// music-lyrics-card: the lyrics of the song a Music Assistant player is playing, for Home Assistant
// dashboards. Synced lyrics (LRC) follow the song: the current line is highlighted and kept in
// view, and a tap on a line seeks there; plain lyrics scroll by hand.
//
//   type: custom:music-lyrics-card
//   entities:                       # Music Assistant's players; the first one playing (else paused)
//     - media_player.ma_living_room #   is shown
//     - media_player.ma_move_2
//   height: 420                     # the lyrics' height in px (default 420)
//   title: Lyrics                   # the heading above the card (default Lyrics; "" for none)
//   icon: mdi:microphone-variant    # its icon
//
// The card hides itself, heading included, while the song has no lyrics (or nothing plays): a
// section holding only this card disappears with it. In the dashboard editor it always shows.
//
// The lyrics come from Music Assistant's metadata providers (LRCLIB, Genius, ...): the card reads
// the track (rest_command.ma_get_track, from the player's media_content_id) and asks for its lyrics
// (rest_command.ma_track_lyrics, Music Assistant's metadata/get_track_lyrics), once per song while
// the page is open.

const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

// "[mm:ss.xx] text" lines (several stamps per line allowed), sorted by time; [] when none.
const parseLrc = (lrc) => {
  const out = [];
  for (const raw of String(lrc || "").split(/\r?\n/)) {
    const stamps = [...raw.matchAll(/\[(\d+):(\d+(?:[.:]\d+)?)\]/g)];
    if (!stamps.length) continue;
    const text = raw.replace(/\[[^\]]*\]/g, "").trim();
    for (const m of stamps) out.push({ t: Number(m[1]) * 60 + Number(m[2].replace(":", ".")), text });
  }
  return out.sort((a, b) => a.t - b.t);
};

// Lyrics per track uri, shared by every card on the page: a promise of { plain, synced }.
const cache = new Map();

class MusicLyricsCard extends HTMLElement {
  setConfig(config) {
    const entities = config.entities || (config.entity ? [config.entity] : []);
    if (!entities.length) throw new Error("entities (Music Assistant media players) are required");
    this._config = { height: 420, ...config, entities };
    this._uri = null;
    this._lyrics = null;
    this._line = -1;
    this._userScroll = 0;
    if (!this._root) this._build();
  }

  _build() {
    this._root = this.attachShadow({ mode: "open" });
    this._root.innerHTML = `
      <style>
        ha-card { overflow: hidden; }
        /* like a heading card, above the card */
        .title { display: flex; align-items: center; gap: 8px; padding: 2px 4px 10px;
          font-size: var(--ha-font-size-l, 16px); line-height: 24px; color: var(--primary-text-color); }
        .title ha-icon { --mdc-icon-size: 18px; color: var(--primary-text-color); }
        .title[hidden] { display: none; }
        .head { padding: 12px 16px 4px; color: var(--secondary-text-color); font-size: 0.9em;
          white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .body { overflow-y: auto; padding: 8px 16px 24px; position: relative;
          -webkit-mask-image: linear-gradient(transparent 0, #000 24px, #000 calc(100% - 32px), transparent);
          mask-image: linear-gradient(transparent 0, #000 24px, #000 calc(100% - 32px), transparent); }
        /* one weight for every line (a bold one would reflow): the current line stands out by its
           brightness and a slight zoom, eased in and out */
        .line { padding: 5px 4% 5px 0; font-size: 1.15em; line-height: 1.4; font-weight: 500;
          color: var(--primary-text-color); opacity: 0.32; transform-origin: left center;
          transition: opacity 0.7s ease, transform 0.7s cubic-bezier(0.2, 0.7, 0.2, 1);
          cursor: pointer; border-radius: 6px; will-change: opacity, transform; }
        .line.past { opacity: 0.22; }
        .line.next { opacity: 0.5; }
        .line.now { opacity: 1; transform: scale(1.035); }
        /* with Reduce Motion on, no zoom: only the brightness changes (the glide stays: it is slow) */
        @media (prefers-reduced-motion: reduce) { .line, .line.now { transform: none; } }
        .line.gap { min-height: 0.8em; }
        .line:hover { background: var(--secondary-background-color); }
        .plain { white-space: pre-wrap; font-size: 1.05em; line-height: 1.5; color: var(--primary-text-color); }
        .note { padding: 16px; color: var(--secondary-text-color); font-size: 0.95em; }
        .foot { padding: 0 16px 10px; font-size: 0.75em; color: var(--secondary-text-color); opacity: 0.7; }
      </style>
      <div class="title"><ha-icon></ha-icon><span></span></div>
      <ha-card>
        <div class="head"></div>
        <div class="body"></div>
        <div class="foot"></div>
      </ha-card>`;
    this._head = this._root.querySelector(".head");
    this._body = this._root.querySelector(".body");
    this._foot = this._root.querySelector(".foot");
    this._body.style.height = this._config.height + "px";
    const title = this._config.title ?? "Lyrics";
    const tEl = this._root.querySelector(".title");
    tEl.hidden = !title;
    tEl.querySelector("span").textContent = title;
    tEl.querySelector("ha-icon").setAttribute("icon", this._config.icon || "mdi:microphone-variant");
    this._show(false);
    // a hand scroll pauses following the song for a few seconds
    for (const ev of ["wheel", "touchstart", "pointerdown"]) {
      this._body.addEventListener(ev, () => {
        this._userScroll = Date.now();
        this._anim = null;
      }, { passive: true });
    }
    this._body.addEventListener("click", (e) => this._seek(e));
  }

  connectedCallback() {
    if (!this._timer) this._timer = setInterval(() => this._tick(), 250);
  }

  disconnectedCallback() {
    clearInterval(this._timer);
    this._timer = null;
  }

  // The player shown: the first playing one, else the first paused one.
  _pick() {
    const st = (e) => this._hass && this._hass.states[e];
    return this._config.entities.find((e) => st(e) && st(e).state === "playing")
      || this._config.entities.find((e) => st(e) && st(e).state === "paused") || null;
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const e = this._pick();
    this._entity = e;
    const st = e ? hass.states[e] : null;
    const a = (st && st.attributes) || {};
    const uri = st ? a.media_content_id || null : null;
    const label = a.media_artist ? a.media_artist + " - " + (a.media_title || "") : a.media_title || "";
    this._head.textContent = label;
    if (uri === this._uri) return;
    this._uri = uri;
    this._lyrics = null;
    this._line = -1;
    if (!uri) return this._note(st ? "Not a Music Assistant song" : "Nothing playing");
    if (!/^[^:]+:\/\/track\//.test(uri)) return this._note("No lyrics for this source");
    this._note("Looking for lyrics…");
    this._load(uri).then((lyrics) => {
      if (this._uri !== uri) return;
      this._lyrics = lyrics;
      this._render();
    });
  }

  _load(uri) {
    if (!cache.has(uri)) {
      const m = /^([^:]+):\/\/track\/(.+)$/.exec(uri);
      const p = (async () => {
        const track = await this._ma("ma_get_track", { provider: m[1], item_id: m[2] });
        const r = await this._ma("ma_track_lyrics", { track });
        const [plain, lrc] = Array.isArray(r) ? r : [null, null];
        return { plain: String(plain || "").trim(), synced: parseLrc(lrc) };
      })().catch((err) => {
        console.warn("music-lyrics-card: lyrics for", uri, "failed:", err);
        cache.delete(uri);
        return { plain: "", synced: [], failed: true };
      });
      cache.set(uri, p);
    }
    return cache.get(uri);
  }

  async _ma(service, data) {
    const r = await this._hass.callWS({
      type: "call_service", domain: "rest_command", service, service_data: data, return_response: true,
    });
    const res = (r && r.response) || {};
    if (res.status !== 200) throw new Error(service + ": status " + res.status);
    return res.content;
  }

  // Shows or hides the whole card (as HA's own cards do: the section hides when nothing is left).
  _show(visible) {
    visible = visible || !!this.preview;
    if (visible === !this.hidden) return;
    this.style.display = visible ? "" : "none";
    this.toggleAttribute("hidden", !visible);
    this.dispatchEvent(new CustomEvent("card-visibility-changed", {
      detail: { value: visible }, bubbles: true, composed: true,
    }));
  }

  // No lyrics to show: the card hides (the text shows only in the dashboard editor).
  _note(text) {
    this._body.innerHTML = '<div class="note">' + esc(text) + "</div>";
    this._foot.textContent = "";
    this._show(false);
  }

  _render() {
    const l = this._lyrics;
    if (l.synced.length) {
      this._body.innerHTML = l.synced.map((x, i) =>
        '<div class="line' + (x.text ? "" : " gap") + '" data-i="' + i + '">' + esc(x.text) + "</div>").join("");
      this._foot.textContent = "Synced lyrics · tap a line to go there";
      this._body.scrollTop = 0;
      this._show(true);
      this._tick();
    } else if (l.plain) {
      this._body.innerHTML = '<div class="plain">' + esc(l.plain) + "</div>";
      this._foot.textContent = "Lyrics (not synced)";
      this._body.scrollTop = 0;
      this._show(true);
    } else {
      this._note(l.failed ? "Couldn't load the lyrics" : "No lyrics found (an instrumental?)");
    }
  }

  // The song's position now, in seconds.
  _position() {
    const st = this._entity && this._hass && this._hass.states[this._entity];
    if (!st) return 0;
    const a = st.attributes;
    let pos = Number(a.media_position) || 0;
    if (st.state === "playing" && a.media_position_updated_at) {
      pos += (Date.now() - new Date(a.media_position_updated_at).getTime()) / 1000;
    }
    return pos;
  }

  _tick() {
    const l = this._lyrics;
    if (!l || !l.synced.length || !this._body) return;
    const pos = this._position() + 0.3;
    let i = -1;
    for (let k = 0; k < l.synced.length && l.synced[k].t <= pos; k++) i = k;
    if (i === this._line) return;
    this._line = i;
    const rows = this._body.querySelectorAll(".line");
    rows.forEach((r, k) => {
      r.classList.toggle("now", k === i);
      r.classList.toggle("past", k < i);
      r.classList.toggle("next", k === i + 1);
    });
    if (i >= 0 && Date.now() - this._userScroll > 6000) {
      const row = rows[i];
      const top = row.offsetTop - this._body.clientHeight / 3;
      this._glide(Math.max(0, top));
    }
  }

  // Scrolls the lyrics to top with an ease-in-out over about a second (a hand scroll stops it).
  // Also with Reduce Motion on: a jump per line read as jerky, and the glide is slow and short.
  _glide(top) {
    const body = this._body;
    const from = body.scrollTop;
    const to = Math.min(top, body.scrollHeight - body.clientHeight);
    if (Math.abs(to - from) < 1) return;

    const start = performance.now();
    const ms = Math.min(1100, 500 + Math.abs(to - from) * 2);
    const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
    const anim = {};
    this._anim = anim;
    const step = (now) => {
      if (this._anim !== anim) return;
      const t = Math.min(1, (now - start) / ms);
      body.scrollTop = from + (to - from) * ease(t);
      if (t < 1) requestAnimationFrame(step);
      else this._anim = null;
    };
    requestAnimationFrame(step);
  }

  _seek(e) {
    const row = e.composedPath().find((el) => el.classList && el.classList.contains("line"));
    const l = this._lyrics;
    if (!row || !l || !l.synced.length || !this._entity) return;
    const x = l.synced[Number(row.dataset.i)];
    if (!x) return;
    this._userScroll = 0;
    this._hass.callService("media_player", "media_seek", { entity_id: this._entity, seek_position: Math.max(0, x.t - 0.2) });
  }

  getCardSize() {
    return Math.ceil(this._config.height / 50) + 2;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }
}

customElements.define("music-lyrics-card", MusicLyricsCard);
window.customCards = window.customCards || [];
window.customCards.push({
  type: "music-lyrics-card",
  name: "Music lyrics",
  description: "The lyrics of what a Music Assistant player plays (synced ones follow the song).",
});
