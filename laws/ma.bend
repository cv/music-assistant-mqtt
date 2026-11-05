import Base
import ../lib/wire/bytes.bend as B
import ../lib/wire/json.bend as J
import ../lib/ma/api.bend as Api
import ../lib/ma/model.bend as Model
# Laws of Music Assistant's API (lib/ma): the commands' bytes, and what real messages read as.

# Messages Music Assistant 2.10.9 sent (trimmed: large unwanted parts cut down, ids, names,
# addresses and links replaced; every wanted value kept as sent).

def sample.hello() -> B.Bytes:
  B.utf8("{\"server_id\": \"00000000000000000000000000000000\", \"server_version\": \"2."
    ++ "10.9\", \"schema_version\": 65, \"min_supported_schema_version\": 28, \"base_u"
    ++ "rl\": \"http://music-assistant.local:8095\", \"homeassistant_addon\": false, \""
    ++ "onboard_done\": true, \"name\": \"Music Assistant\", \"status\": \"running\", "
    ++ "\"internal_url\": \"http://music-assistant.local:8095\", \"external_url\": nul"
    ++ "l, \"has_remote_access\": false}")

def sample.refused_auth() -> B.Bytes:
  B.utf8("{\"message_id\": \"pre\", \"error_code\": 20, \"details\": \"Authentication is"
    ++ " required.\"}")

def sample.refused_token() -> B.Bytes:
  B.utf8("{\"message_id\": \"1\", \"error_code\": 23, \"details\": \"The access token is"
    ++ " invalid or has expired.\"}")

def sample.login() -> B.Bytes:
  B.utf8("{\"message_id\": \"2\", \"result\": {\"authenticated\": true, \"user\": {\"use"
    ++ "r_id\": \"user-0001\", \"username\": \"admin\", \"role\": \"admin\", \"enabled"
    ++ "\": true, \"created_at\": \"2026-11-05T06:11:00.816145+00:00\", \"display_name"
    ++ "\": null, \"avatar_url\": null, \"preferences\": {}, \"provider_filter\": [], "
    ++ "\"player_filter\": []}}, \"partial\": false}")

def sample.played() -> B.Bytes:
  B.utf8("{\"event\": \"media_item_played\", \"object_id\": \"library://track/9598\", \""
    ++ "data\": {\"uri\": \"library://track/9598\", \"media_type\": \"track\", \"name\""
    ++ ": \"Tell Me in a Song\", \"duration\": 224, \"seconds_played\": 150, \"fully_p"
    ++ "layed\": false, \"is_playing\": true, \"mbid\": null, \"artist\": \"Jacob Jeff"
    ++ "ries/Vulfmon\", \"artists\": [\"Jacob Jeffries\", \"Vulfmon\"], \"artist_mbids"
    ++ "\": [], \"album\": \"Here We Go Jack\", \"album_mbid\": null, \"album_artist\""
    ++ ": null, \"album_artist_mbids\": null, \"image_url\": \"https://example.com/cov"
    ++ "er.jpg\", \"version\": \"\", \"userid\": \"user-0001\", \"player_id\": \"RINCO"
    ++ "N_000000000001400\"}}")

def sample.lookup() -> B.Bytes:
  B.utf8("{\"message_id\": \"3\", \"result\": {\"item_id\": \"667\", \"provider\": \"lib"
    ++ "rary\", \"name\": \"Balanço Zona Sul\", \"version\": \"\", \"sort_name\": \"ba"
    ++ "lanco zona sul\", \"uri\": \"library://track/667\", \"external_ids\": [[\"isrc"
    ++ "\", \"BRRGE6500004\"]], \"is_playable\": true, \"media_type\": \"track\", \"pr"
    ++ "ovider_mappings\": [{\"item_id\": \"7cRrRC0BQutTT09UKpWx8C\", \"provider_domai"
    ++ "n\": \"spotify\", \"provider_instance\": \"spotify--0001\", \"available\": tru"
    ++ "e, \"in_library\": true, \"is_unique\": null, \"audio_format\": {\"content_typ"
    ++ "e\": \"aac\"}, \"url\": \"https://open.spotify.com/track/7cRrRC0BQutTT09UKpWx8"
    ++ "C\", \"details\": null}, {\"item_id\": \"1124256898\", \"provider_domain\": \""
    ++ "apple_music\", \"provider_instance\": \"apple_music--0001\", \"available\": tr"
    ++ "ue, \"in_library\": true, \"is_unique\": null, \"audio_format\": {\"content_ty"
    ++ "pe\": \"aac\"}, \"url\": \"https://music.apple.com/ca/album/balan%C3%A7o-zona-"
    ++ "sul/1124256884?i=1124256898\", \"details\": null}], \"metadata\": {\"genres\":"
    ++ " [\"Jazz\"]}, \"favorite\": true, \"position\": null, \"date_added\": \"2026-1"
    ++ "1-05T06:13:58+00:00\", \"duration\": 164, \"artists\": [{\"item_id\": \"988\","
    ++ " \"provider\": \"library\", \"name\": \"Zimbo Trio\", \"uri\": \"library://art"
    ++ "ist/988\", \"media_type\": \"artist\"}], \"last_played\": 1793862302, \"album\""
    ++ ": {\"item_id\": \"1203\", \"provider\": \"library\", \"name\": \"Zimbo Trio, V"
    ++ "ol. 2\", \"uri\": \"library://album/1203\", \"media_type\": \"album\"}, \"disc"
    ++ "_number\": 1, \"track_number\": 2, \"audio_metadata\": null}, \"partial\": fal"
    ++ "se}")

def sample.players() -> B.Bytes:
  B.utf8("{\"message_id\": \"4\", \"result\": [{\"player_id\": \"RINCON_000000000002400\""
    ++ ", \"provider\": \"sonos\", \"type\": \"player\", \"name\": \"Kitchen\", \"avai"
    ++ "lable\": true, \"device_info\": {\"model\": \"Kitchen\", \"manufacturer\": \"S"
    ++ "ONOS\", \"mac_address\": \"00:00:00:00:00:01\", \"ip_address\": \"10.0.0.20\"}"
    ++ ", \"supported_features\": [\"play_announcement\", \"seek\"], \"playback_state\""
    ++ ": \"playing\", \"elapsed_time\": 0.0007746219635009766, \"elapsed_time_last_up"
    ++ "dated\": 1793864217.9447765, \"powered\": true, \"volume_level\": 2, \"volume_"
    ++ "muted\": false, \"group_members\": [], \"static_group_members\": [], \"can_gro"
    ++ "up_with\": [], \"synced_to\": \"RINCON_000000000001400\", \"active_sound_mode\""
    ++ ": null, \"sound_mode_list\": [], \"options\": [], \"active_source\": \"RINCON_"
    ++ "000000000001400\", \"source_list\": [{\"id\": \"line_in\", \"name\": \"Line-in"
    ++ "\"}, {\"id\": \"airplay\", \"name\": \"AirPlay\"}], \"active_group\": null, \""
    ++ "current_media\": {\"uri\": \"library://track/9598\", \"media_type\": \"track\""
    ++ ", \"title\": \"Tell Me in a Song\", \"artist\": \"Jacob Jeffries/Vulfmon\", \""
    ++ "album\": \"Here We Go Jack\", \"album_artist\": null, \"image_url\": \"http://"
    ++ "music-assistant.local:8095/imageproxy/1\", \"duration\": 224, \"stream_duratio"
    ++ "n\": null, \"source_id\": \"RINCON_000000000001400\", \"queue_item_id\": \"000"
    ++ "00000000000000000000000000000\", \"custom_data\": null, \"elapsed_time\": 0, \""
    ++ "elapsed_time_last_updated\": 1793864218.4456868}, \"enabled\": true, \"hide_in"
    ++ "_ui\": false, \"private\": false, \"expose_to_ha\": true, \"icon\": \"sonos\","
    ++ " \"group_volume\": 2, \"group_volume_muted\": false, \"extra_attributes\": {},"
    ++ " \"power_control\": \"none\", \"volume_control\": \"native\", \"mute_control\""
    ++ ": \"native\", \"output_protocols\": [], \"active_output_protocol\": null, \"ne"
    ++ "eds_setup\": false, \"setup_reason\": null, \"has_setup_flow\": true, \"sleep_"
    ++ "timer_expires_at\": null, \"active_source_audio\": null, \"display_name\": \"K"
    ++ "itchen\", \"state\": \"playing\", \"group_childs\": [], \"extra_data\": {}, \""
    ++ "hide_player_in_ui\": [\"when_unavailable\", \"when_synced\", \"when_group_acti"
    ++ "ve\"]}, {\"player_id\": \"RINCON_000000000001400\", \"provider\": \"sonos\", \""
    ++ "type\": \"player\", \"name\": \"Living Room\", \"available\": true, \"device_i"
    ++ "nfo\": {\"model\": \"Beam\", \"manufacturer\": \"SONOS\", \"mac_address\": \"0"
    ++ "0:00:00:00:00:01\", \"ip_address\": \"10.0.0.20\"}, \"supported_features\": [\""
    ++ "play_announcement\", \"seek\"], \"playback_state\": \"playing\", \"elapsed_tim"
    ++ "e\": 0.0007746219635009766, \"elapsed_time_last_updated\": 1793864217.9447765,"
    ++ " \"powered\": true, \"volume_level\": 1, \"volume_muted\": false, \"group_memb"
    ++ "ers\": [\"RINCON_000000000001400\", \"RINCON_000000000002400\"], \"static_grou"
    ++ "p_members\": [], \"can_group_with\": [\"Drly190AuzsRfbVxv_Ql8-TkDylCvQ_NGDCS8H"
    ++ "FTTUo\", \"RINCON_000000000002400\"], \"synced_to\": null, \"active_sound_mode"
    ++ "\": null, \"sound_mode_list\": [], \"options\": [], \"active_source\": \"RINCO"
    ++ "N_000000000001400\", \"source_list\": [{\"id\": \"tv\", \"name\": \"TV\"}, {\""
    ++ "id\": \"airplay\", \"name\": \"AirPlay\"}], \"active_group\": null, \"current_"
    ++ "media\": {\"uri\": \"library://track/9598\", \"media_type\": \"track\", \"titl"
    ++ "e\": \"Tell Me in a Song\", \"artist\": \"Jacob Jeffries/Vulfmon\", \"album\":"
    ++ " \"Here We Go Jack\", \"album_artist\": null, \"image_url\": \"http://music-as"
    ++ "sistant.local:8095/imageproxy/1\", \"duration\": 224, \"stream_duration\": nul"
    ++ "l, \"source_id\": \"RINCON_000000000001400\", \"queue_item_id\": \"00000000000"
    ++ "000000000000000000000\", \"custom_data\": null, \"elapsed_time\": 0, \"elapsed"
    ++ "_time_last_updated\": 1793864218.4456868}, \"enabled\": true, \"hide_in_ui\": "
    ++ "false, \"private\": false, \"expose_to_ha\": true, \"icon\": \"sonos\", \"grou"
    ++ "p_volume\": 2, \"group_volume_muted\": false, \"extra_attributes\": {}, \"powe"
    ++ "r_control\": \"none\", \"volume_control\": \"native\", \"mute_control\": \"nat"
    ++ "ive\", \"output_protocols\": [], \"active_output_protocol\": \"native\", \"nee"
    ++ "ds_setup\": false, \"setup_reason\": null, \"has_setup_flow\": true, \"sleep_t"
    ++ "imer_expires_at\": null, \"active_source_audio\": null, \"display_name\": \"Li"
    ++ "ving Room\", \"state\": \"playing\", \"group_childs\": [\"RINCON_0000000000014"
    ++ "00\", \"RINCON_000000000002400\"], \"extra_data\": {}, \"hide_player_in_ui\": "
    ++ "[\"when_unavailable\", \"when_synced\", \"when_group_active\"]}], \"partial\":"
    ++ " false}")

def u(s: String) -> B.Bytes:
  B.utf8(s)

def tell_me() -> Model.Media:
  Model.Media{u("library://track/9598"), u("Tell Me in a Song"), u("Jacob Jeffries/Vulfmon"),
    u("Here We Go Jack"), 224}

# The commands
# ------------
# Only these three exist (a law in core says nothing else is ever sent).

law ma_login_bytes:
  {Api.encode(1, Api.Login{"t0ken"})
    == u("{\"message_id\":\"1\",\"command\":\"auth\",\"args\":{\"token\":\"t0ken\"}}") : B.Bytes}

law ma_players_bytes:
  {Api.encode(2, Api.ListPlayers{})
    == u("{\"message_id\":\"2\",\"command\":\"players/all\",\"args\":{}}") : B.Bytes}

law ma_lookup_bytes:
  {Api.encode(3, Api.Lookup{u("library://track/667")})
    == u("{\"message_id\":\"3\",\"command\":\"music/item_by_uri\","
      ++ "\"args\":{\"uri\":\"library://track/667\"}}")
    : B.Bytes}

# What the server's messages read as
# ----------------------------------

law ma_reads_hello:
  {Model.classify(Model.read(sample.hello())) == Model.Hello{u("2.10.9")} : Model.Msg}

law ma_reads_auth_required:
  {Model.classify(Model.read(sample.refused_auth()))
    == Model.Refused{u("pre"), 20, u("Authentication is required.")} : Model.Msg}

law ma_reads_bad_token:
  {Model.classify(Model.read(sample.refused_token()))
    == Model.Refused{u("1"), 23, u("The access token is invalid or has expired.")} : Model.Msg}

law ma_reads_login:
  {(Model.classify(Model.read(sample.login())), Model.logged_in(Model.read(sample.login())))
    == (Model.Reply{u("2")}, True{}) : Model.Msg & Bool}

law ma_reads_play_event:
  {Model.classify(Model.read(sample.played()))
    == Model.Happened{u("media_item_played"), u("library://track/9598")} : Model.Msg}

# A report in progress (is_playing true): 150 s of 224 heard, not final.
law ma_reads_play_report:
  {Model.play(Model.read(sample.played()))
    == Model.Play{tell_me(), 150, False{}, False{}, u("RINCON_000000000001400")} : Model.Play}

law ma_reads_catalog_ids:
  {Model.ids(Model.read(sample.lookup()))
    == Model.Ids{u("1124256898"), u("7cRrRC0BQutTT09UKpWx8C"), u("BRRGE6500004")} : Model.Ids}

# Both players, the first grouped with the second; device details (MAC, IP) are never kept.
law ma_reads_players:
  {Model.players(Model.read(sample.players()))
    == [Model.Player{u("RINCON_000000000002400"), u("Kitchen"),
          Model.Status{True{}, u("playing"), u("RINCON_000000000001400"),
            u("RINCON_000000000001400"), 2},
          tell_me()},
        Model.Player{u("RINCON_000000000001400"), u("Living Room"),
          Model.Status{True{}, u("playing"), u("RINCON_000000000001400"), u(""), 1},
          tell_me()}]
    : List<&2, Model.Player>}

law ma_players_drop_device_details:
  {(Model.holds(Model.read(sample.players()), u("10.0.0.20")),
    Model.holds(Model.read(sample.players()), u("00:00:00:00:00:01")))
    == (False{}, False{}) : Bool & Bool}

# For every message: the model reads only values at Api's wanted paths (no device details, MAC or
# IP addresses, artwork, metadata), whatever Music Assistant sends.
law model_reads_only_wanted:
  for +bs: B.Bytes
  {J.all.ok(Api.wants(), Model.read(bs)) == True{} : Bool}
