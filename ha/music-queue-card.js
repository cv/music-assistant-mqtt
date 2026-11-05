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
// the item's id, so nothing in between is played or counted as a skip).

const length = (s) => {
  s = Math.max(0, Math.round(Number(s) || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = String(s % 60).padStart(2, "0");
  return h ? h + ":" + String(m).padStart(2, "0") + ":" + ss : String(m).padStart(2, "0") + ":" + ss;
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
          display: flex; align-items: baseline; gap: 12px; padding: 6px 16px;
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
        .name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .note { flex: none; font-size: 0.8em; color: var(--secondary-text-color); opacity: 0.8; }
        .starting { opacity: 0.6; }
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
      return this._row("p", i, p.duration, (p.artist ? p.artist + " - " : "") + p.title, skipped ? "skipped" : "");
    }).join("");
    this._nextEl.innerHTML = next.length
      ? next.map((n, i) => this._row("n", i, n.duration, n.name, "")).join("")
      : '<div class="empty">Nothing queued next</div>';
    this._prev = prev;
    this._next = next;
  }

  _row(kind, i, duration, name, note) {
    const starting = this._pending === kind + i;
    return '<div class="row' + (starting ? " starting" : "") + '" role="button" tabindex="0" data-kind="' + kind
      + '" data-i="' + i + '"><span class="time">' + length(duration) + '</span><span class="name">'
      + esc(name) + "</span>" + (starting ? '<span class="note">starting…</span>' : note ? '<span class="note">'
      + esc(note) + "</span>" : "") + "</div>";
  }

  _tap(e) {
    const row = e.composedPath().find((el) => el.classList && el.classList.contains("row"));
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
