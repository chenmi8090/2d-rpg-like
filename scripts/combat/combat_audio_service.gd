class_name CombatAudioService
extends Node2D

const EVENT_RELEASE := &"release"
const EVENT_IMPACT := &"impact"
const EVENT_HURT := &"hurt"
const EVENT_DEATH := &"death"
const FALLBACK_CUE_ID := &"combat_audio_fallback"

@export_range(1, 64, 1) var pool_size := 12
@export var test_mode := false
@export var fallback_cue: AudioCueDefinition

var event_log: Array[Dictionary] = []

var _players: Array[AudioStreamPlayer2D] = []
var _active_by_cue: Dictionary = {}
var _active_by_owner_cue: Dictionary = {}
var _cooldowns: Dictionary = {}
var _owner_tokens: Dictionary = {}
var _owner_cleanup_connected: Dictionary = {}
var _sequence := 0


func _ready() -> void:
	_build_pool()


func request_attack_release(profile: CombatAttackAudioProfile, owner: Node, position: Vector2) -> bool:
	var cue := profile.release_cue if profile != null else null
	return _play_cue(cue, owner, position, EVENT_RELEASE)


func request_attack_impact(profile: CombatAttackAudioProfile, owner: Node, position: Vector2, is_critical := false) -> bool:
	var cue := profile.cue_for_impact(is_critical) if profile != null else null
	return _play_cue(cue, owner, position, EVENT_IMPACT, {&"is_critical": is_critical})


func request_hurt(profile: ActorAudioProfile, owner: Node, position: Vector2, heavy := false) -> bool:
	var cue := profile.cue_for_hurt(heavy) if profile != null else null
	return _play_cue(cue, owner, position, EVENT_HURT, {&"heavy": heavy})


func request_death(profile: ActorAudioProfile, owner: Node, position: Vector2) -> bool:
	var cue := profile.death_cue if profile != null else null
	return _play_cue(cue, owner, position, EVENT_DEATH)


func cleanup_owner(owner: Node) -> void:
	if owner == null:
		return
	var token := _owner_token(owner)
	for player in _players:
		if player.get_meta(&"combat_audio_owner_token", 0) == token:
			player.stop()
			_on_player_finished(player)
	_owner_tokens.erase(owner)
	_owner_cleanup_connected.erase(token)


func clear_event_log() -> void:
	event_log.clear()


func _build_pool() -> void:
	if not _players.is_empty():
		return
	for index in pool_size:
		var player := AudioStreamPlayer2D.new()
		player.name = "CombatAudioPlayer%d" % index
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_players.append(player)


func _play_cue(cue: AudioCueDefinition, owner: Node, position: Vector2, event_type: StringName, extra: Dictionary = {}) -> bool:
	_build_pool()
	if cue == null or not cue.is_valid():
		cue = fallback_cue
	if cue == null or not cue.is_valid():
		_log_event(event_type, FALLBACK_CUE_ID, owner, false, "missing_cue", extra)
		return false
	if _is_on_cooldown(cue):
		_log_event(event_type, cue.cue_id, owner, false, "cooldown", extra)
		return false
	var owner_token := _owner_token(owner)
	if _active_count(_active_by_cue, cue.cue_id) >= cue.max_concurrent_global:
		_log_event(event_type, cue.cue_id, owner, false, "global_concurrency", extra)
		return false
	var owner_key := _owner_cue_key(owner_token, cue.cue_id)
	if _active_count(_active_by_owner_cue, owner_key) >= cue.max_concurrent_per_owner:
		_log_event(event_type, cue.cue_id, owner, false, "owner_concurrency", extra)
		return false
	var stream := _variant_for(cue, owner_token)
	if stream == null:
		_log_event(event_type, cue.cue_id, owner, false, "missing_stream", extra)
		return false
	var player := _available_player()
	if player == null:
		_log_event(event_type, cue.cue_id, owner, false, "pool_exhausted", extra)
		return false
	_sequence += 1
	player.stream = stream
	player.global_position = position
	player.volume_db = cue.volume_db
	player.pitch_scale = _pitch_for(cue, owner_token)
	player.set_meta(&"combat_audio_cue_id", cue.cue_id)
	player.set_meta(&"combat_audio_owner_token", owner_token)
	_increment_active(_active_by_cue, cue.cue_id)
	_increment_active(_active_by_owner_cue, owner_key)
	_cooldowns[cue.cue_id] = Time.get_ticks_msec() * 0.001 + cue.cooldown_time
	_connect_owner_cleanup(owner, owner_token)
	_log_event(event_type, cue.cue_id, owner, true, "", extra)
	if test_mode:
		_on_player_finished(player)
	else:
		player.play()
	return true


func _available_player() -> AudioStreamPlayer2D:
	for player in _players:
		if not player.playing and not bool(player.get_meta(&"combat_audio_active", false)):
			player.set_meta(&"combat_audio_active", true)
			return player
	return null


func _on_player_finished(player: AudioStreamPlayer2D) -> void:
	if player == null:
		return
	var cue_id: StringName = player.get_meta(&"combat_audio_cue_id", &"")
	var owner_token := int(player.get_meta(&"combat_audio_owner_token", 0))
	if cue_id != &"":
		_decrement_active(_active_by_cue, cue_id)
		_decrement_active(_active_by_owner_cue, _owner_cue_key(owner_token, cue_id))
	player.remove_meta(&"combat_audio_cue_id")
	player.remove_meta(&"combat_audio_owner_token")
	player.set_meta(&"combat_audio_active", false)
	player.stream = null


func _variant_for(cue: AudioCueDefinition, owner_token: int) -> AudioStream:
	if cue.streams.is_empty():
		return null
	var index := _deterministic_index(cue.cue_id, owner_token, cue.streams.size())
	return cue.streams[index]


func _pitch_for(cue: AudioCueDefinition, owner_token: int) -> float:
	var variance := maxf(cue.pitch_variance, 0.0)
	if variance == 0.0:
		return cue.base_pitch
	var bucket := _stable_hash("%s:%d:%d:pitch" % [String(cue.cue_id), owner_token, _sequence]) % 10001
	var unit := float(bucket) / 10000.0
	return maxf(0.01, cue.base_pitch + lerpf(-variance, variance, unit))


func _deterministic_index(cue_id: StringName, owner_token: int, count: int) -> int:
	if count <= 1:
		return 0
	return _stable_hash("%s:%d:%d" % [String(cue_id), owner_token, _sequence]) % count


func _stable_hash(value: String) -> int:
	var hash := 2166136261
	for index in value.length():
		hash = int((hash ^ value.unicode_at(index)) * 16777619) & 0x7fffffff
	return hash


func _is_on_cooldown(cue: AudioCueDefinition) -> bool:
	if cue.cooldown_time <= 0.0:
		return false
	return Time.get_ticks_msec() * 0.001 < float(_cooldowns.get(cue.cue_id, -1.0))


func _owner_token(owner: Node) -> int:
	if owner == null or not is_instance_valid(owner):
		return 0
	if not _owner_tokens.has(owner):
		_owner_tokens[owner] = owner.get_instance_id()
	return int(_owner_tokens[owner])


func _connect_owner_cleanup(owner: Node, owner_token: int) -> void:
	if owner == null or not is_instance_valid(owner) or _owner_cleanup_connected.has(owner_token):
		return
	owner.tree_exited.connect(cleanup_owner.bind(owner), CONNECT_ONE_SHOT)
	_owner_cleanup_connected[owner_token] = true


func _owner_cue_key(owner_token: int, cue_id: StringName) -> String:
	return "%d:%s" % [owner_token, String(cue_id)]


func _active_count(table: Dictionary, key: Variant) -> int:
	return int(table.get(key, 0))


func _increment_active(table: Dictionary, key: Variant) -> void:
	table[key] = _active_count(table, key) + 1


func _decrement_active(table: Dictionary, key: Variant) -> void:
	var count := _active_count(table, key) - 1
	if count <= 0:
		table.erase(key)
	else:
		table[key] = count


func _log_event(event_type: StringName, cue_id: StringName, owner: Node, accepted: bool, reason: String, extra: Dictionary) -> void:
	var entry := {
		&"event": event_type,
		&"cue_id": cue_id,
		&"owner_id": owner.get_instance_id() if owner != null and is_instance_valid(owner) else 0,
		&"accepted": accepted,
		&"reason": reason,
		&"time": Time.get_ticks_msec() * 0.001,
	}
	for key in extra:
		entry[key] = extra[key]
	event_log.append(entry)
