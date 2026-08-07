extends Node

signal index_changed
signal active_profile_changed(profile_id: String)
signal save_status_changed(message: String, failed: bool)
signal return_countdown_changed(message: String, active: bool)

const SAVE_VERSION := 1
const SLOT_COUNT := 3
const DEFAULT_SAVE_ROOT := "user://profiles"
const CHARACTER_SELECT_SCENE := "res://scenes/ui/character_select.tscn"
const CHARACTER_CREATION_SCENE := "res://scenes/ui/character_creation.tscn"
const TEST_LEVEL_SCENE := "res://scenes/levels/test_level.tscn"
const GAMEPLAY_INPUT_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"interact_up",
	&"interact_down",
	&"jump",
	&"light_attack",
	&"heavy_attack",
	&"toggle_attributes",
	&"toggle_backpack",
	&"reset",
]
const DEFAULT_AREA_ID := &"test_level"
const DEFAULT_SPAWN_ID := &"start"
const AUTOSAVE_DELAY := 0.65
const COMBAT_RETURN_DELAY := 5.0

var save_root := DEFAULT_SAVE_ROOT

var _index: Dictionary = {}
var _active_profile: Dictionary = {}
var _active_player: Player
var _active_level: Node
var _loading_profile := false
var _autosave_generation := 0
var _pending_save_reason := &"gameplay"
var _challenge_locks: Dictionary = {}
var _return_countdown := -1.0
var _last_player_health := 0
var _session_started_msec := 0
var _pending_creation_slot := -1
var _test_disable_scene_changes := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_index()


func _process(delta: float) -> void:
	if _return_countdown < 0.0:
		return
	if _active_player == null or not is_instance_valid(_active_player):
		cancel_return_to_list("角色状态已失效，返回已中断")
		return
	if not _challenge_locks.is_empty():
		cancel_return_to_list(_challenge_lock_reason())
		return
	_return_countdown = maxf(_return_countdown - delta, 0.0)
	return_countdown_changed.emit("战斗中，正在返回角色列表... %d" % ceili(_return_countdown), true)
	if _return_countdown == 0.0:
		_return_countdown = -1.0
		_finish_return_to_list()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and has_active_profile():
		save_now(&"quit")


func use_test_save_root(path: String) -> void:
	save_root = path
	_active_profile.clear()
	_index.clear()
	refresh_index()


func reset_save_root() -> void:
	use_test_save_root(DEFAULT_SAVE_ROOT)


func set_test_disable_scene_changes(disabled: bool) -> void:
	_test_disable_scene_changes = disabled


func begin_character_creation(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return _failure("角色栏位无效")
	var slot := get_slot(slot_index)
	if not String(slot.get("profile_id", "")).is_empty():
		return _failure("该栏位已有角色")
	_pending_creation_slot = slot_index
	if not _test_disable_scene_changes:
		var error := get_tree().change_scene_to_file(CHARACTER_CREATION_SCENE)
		if error != OK:
			_pending_creation_slot = -1
			return _failure("无法打开角色创建界面")
	return {"ok": true, "message": ""}


func get_pending_creation_slot() -> int:
	return _pending_creation_slot


func clear_pending_creation_slot() -> void:
	_pending_creation_slot = -1


func return_to_character_select() -> Dictionary:
	clear_pending_creation_slot()
	_release_gui_focus(get_viewport())
	if not _test_disable_scene_changes:
		var error := get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
		if error != OK:
			return _failure("无法返回角色列表")
	return {"ok": true, "message": ""}


func prepare_gameplay_scene_transition(viewport: Viewport = null) -> void:
	_release_gui_focus(viewport)
	for action in GAMEPLAY_INPUT_ACTIONS:
		Input.action_release(action)
	Input.flush_buffered_events()


func _release_gui_focus(viewport: Viewport) -> void:
	if viewport == null:
		return
	var focus_owner := viewport.gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func refresh_index() -> Dictionary:
	_ensure_directories()
	var result := _read_json(_index_path())
	if result.ok:
		var normalized := _normalize_index(result.data)
		if normalized.ok:
			_index = normalized.data
			index_changed.emit()
			return {"ok": true, "message": ""}
	var backup := _read_json(_index_backup_path())
	if backup.ok:
		var normalized_backup := _normalize_index(backup.data)
		if normalized_backup.ok:
			_index = normalized_backup.data
			index_changed.emit()
			return {"ok": true, "message": "角色列表已从备份恢复"}
	_index = _rebuild_index_from_profiles()
	index_changed.emit()
	return {"ok": true, "message": "" if result.message == "文件不存在" else "角色列表已安全重建"}


func get_slots() -> Array[Dictionary]:
	if _index.is_empty():
		refresh_index()
	var result: Array[Dictionary] = []
	for slot in _index.get("slots", []):
		result.append((slot as Dictionary).duplicate(true))
	return result


func get_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return {}
	return (get_slots()[slot_index] as Dictionary).duplicate(true)


func has_active_profile() -> bool:
	return not String(_active_profile.get("profile_id", "")).is_empty()


func get_active_character_name() -> String:
	return String(_active_profile.get("name", ""))


func get_profession_options() -> Array[ProfessionDefinition]:
	return DefinitionRegistry.get_professions()


func get_profession_definition(profession_id: StringName) -> ProfessionDefinition:
	return DefinitionRegistry.get_profession(profession_id)


func get_equipment_definition(equipment_id: StringName) -> EquipmentDefinition:
	return DefinitionRegistry.get_equipment(equipment_id)


func validate_character_name(raw_name: String, ignored_slot := -1) -> Dictionary:
	var character_name := raw_name.strip_edges()
	if character_name.length() < 2 or character_name.length() > 12:
		return {"ok": false, "name": character_name, "message": "角色名需要 2–12 个字符"}
	for index in character_name.length():
		var code := character_name.unicode_at(index)
		var allowed := code >= 0x4E00 and code <= 0x9FFF
		allowed = allowed or code >= 48 and code <= 57
		allowed = allowed or code >= 65 and code <= 90
		allowed = allowed or code >= 97 and code <= 122
		if not allowed:
			return {"ok": false, "name": character_name, "message": "角色名只能使用中文、英文字母和数字"}
	for slot in get_slots():
		if int(slot.get("slot", -1)) == ignored_slot:
			continue
		if not String(slot.get("profile_id", "")).is_empty() and String(slot.get("name", "")) == character_name:
			return {"ok": false, "name": character_name, "message": "角色名已存在"}
	return {"ok": true, "name": character_name, "message": ""}


func create_character(slot_index: int, raw_name: String, profession_id: StringName) -> Dictionary:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return _failure("角色栏位无效")
	var slots := get_slots()
	if not String(slots[slot_index].get("profile_id", "")).is_empty():
		return _failure("该栏位已有角色")
	var name_result := validate_character_name(raw_name)
	if not name_result.ok:
		return name_result
	var profession := get_profession_definition(profession_id)
	if profession == null:
		return _failure("请选择有效职业")
	var progression := load("res://resources/progression/default_player_progression.tres") as PlayerProgressionDefinition
	var now := int(Time.get_unix_time_from_system())
	var profile_id := _generate_profile_id(slot_index, now)
	var equipped: Dictionary = {}
	for definition in profession.starting_equipment:
		if definition != null and profession.can_equip(definition):
			equipped[String(definition.slot)] = String(definition.id)
	var profile := {
		"version": SAVE_VERSION,
		"profile_id": profile_id,
		"slot": slot_index,
		"name": String(name_result.name),
		"profession_id": String(profession.id),
		"created_at": now,
		"updated_at": now,
		"play_time_seconds": 0,
		"progression": {
			"level": progression.starting_level if progression != null else 1,
			"experience": progression.starting_experience if progression != null else 0,
		},
		"materials": {"stardust_fragment": 0},
		"equipment": {"equipped": equipped, "inventory": []},
		"location": {"area_id": String(DEFAULT_AREA_ID), "safe_spawn_id": String(DEFAULT_SPAWN_ID)},
		"meta": {"last_save_reason": "creation"},
	}
	var save_result := _write_json_atomic(_profile_path(profile_id), profile, _profile_backup_path(profile_id))
	if not save_result.ok:
		return save_result
	slots[slot_index] = _slot_summary(profile)
	_index = {"version": SAVE_VERSION, "slots": slots}
	var index_result := _write_json_atomic(_index_path(), _index, _index_backup_path())
	if not index_result.ok:
		return index_result
	index_changed.emit()
	return {"ok": true, "profile_id": profile_id, "message": "角色创建成功"}


func continue_character(slot_index: int) -> Dictionary:
	var slot := get_slot(slot_index)
	var profile_id := String(slot.get("profile_id", ""))
	if profile_id.is_empty():
		return _failure("该栏位没有角色")
	var result := _load_profile(profile_id)
	if not result.ok:
		return result
	_active_profile = result.data
	active_profile_changed.emit(profile_id)
	prepare_gameplay_scene_transition(get_viewport())
	if not _test_disable_scene_changes:
		var error := get_tree().change_scene_to_file(TEST_LEVEL_SCENE)
		if error != OK:
			_active_profile.clear()
			return _failure("无法进入游戏场景")
	return {"ok": true, "message": result.message}


func delete_character(slot_index: int, confirmation_name: String) -> Dictionary:
	var slot := get_slot(slot_index)
	var profile_id := String(slot.get("profile_id", ""))
	if profile_id.is_empty():
		return _failure("该栏位没有角色")
	if confirmation_name != String(slot.get("name", "")):
		return _failure("请输入完整角色名以确认删除")
	var profile_path := _profile_path(profile_id)
	if FileAccess.file_exists(profile_path):
		var archive_path := "%s/backups/deleted_%s_%d.json" % [save_root, profile_id, int(Time.get_unix_time_from_system())]
		var archive_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(profile_path), ProjectSettings.globalize_path(archive_path))
		if archive_error != OK:
			return _failure("无法创建删除前备份")
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
		if remove_error != OK:
			return _failure("无法删除角色档案")
	var slots := get_slots()
	slots[slot_index] = _empty_slot(slot_index)
	_index = {"version": SAVE_VERSION, "slots": slots}
	var index_result := _write_json_atomic(_index_path(), _index, _index_backup_path())
	if not index_result.ok:
		return index_result
	index_changed.emit()
	return {"ok": true, "message": "角色已删除"}


func bind_level(level: Node, player: Player) -> Dictionary:
	unbind_level(_active_level)
	_active_level = level
	_active_player = player
	_session_started_msec = Time.get_ticks_msec()
	_last_player_health = player.get_health() if player != null else 0
	if not has_active_profile() or player == null:
		return {"ok": true, "message": ""}
	_loading_profile = true
	var location := _active_profile.get("location", {}) as Dictionary
	var area_id := StringName(String(location.get("area_id", DEFAULT_AREA_ID)))
	var spawn_id := StringName(String(location.get("safe_spawn_id", DEFAULT_SPAWN_ID)))
	if not level.has_method("get_area_id") or level.call("get_area_id") != area_id:
		area_id = DEFAULT_AREA_ID
		spawn_id = DEFAULT_SPAWN_ID
	var spawn_position := Vector2(80.0, 550.0)
	if level.has_method("get_safe_spawn_position"):
		spawn_position = level.call("get_safe_spawn_position", spawn_id)
		if spawn_position == Vector2.INF:
			spawn_id = DEFAULT_SPAWN_ID
			spawn_position = level.call("get_safe_spawn_position", spawn_id)
	_active_profile["location"] = {"area_id": String(area_id), "safe_spawn_id": String(spawn_id)}
	var apply_result := player.apply_save_snapshot(_active_profile)
	if apply_result.ok:
		player.apply_safe_spawn(spawn_position)
	_loading_profile = false
	if not apply_result.ok:
		return apply_result
	_connect_player_signals(player)
	_last_player_health = player.get_health()
	return {"ok": true, "message": ""}


func unbind_level(level: Node) -> void:
	if level != null and _active_level != null and level != _active_level:
		return
	_disconnect_player_signals()
	_accumulate_play_time()
	_active_level = null
	_active_player = null
	_return_countdown = -1.0


func request_autosave(reason: StringName = &"gameplay") -> void:
	if _loading_profile or not has_active_profile() or _active_player == null:
		return
	_pending_save_reason = reason
	_autosave_generation += 1
	var generation := _autosave_generation
	_autosave_after_delay(generation)


func _autosave_after_delay(generation: int) -> void:
	await get_tree().create_timer(AUTOSAVE_DELAY).timeout
	if generation == _autosave_generation:
		save_now(_pending_save_reason)


func save_now(reason: StringName = &"manual") -> Dictionary:
	if not has_active_profile():
		return _failure("当前没有活动角色")
	if _active_player != null and is_instance_valid(_active_player):
		var snapshot := _active_player.get_save_snapshot()
		_active_profile["progression"] = snapshot.progression
		_active_profile["materials"] = snapshot.materials
		_active_profile["equipment"] = snapshot.equipment
	_accumulate_play_time()
	var now := int(Time.get_unix_time_from_system())
	_active_profile["updated_at"] = now
	_active_profile["meta"] = {"last_save_reason": String(reason)}
	save_status_changed.emit("保存中...", false)
	var profile_id := String(_active_profile.profile_id)
	var profile_result := _write_json_atomic(_profile_path(profile_id), _active_profile, _profile_backup_path(profile_id))
	if not profile_result.ok:
		save_status_changed.emit("保存失败：%s" % profile_result.message, true)
		return profile_result
	var slot_index := int(_active_profile.slot)
	var slots := get_slots()
	slots[slot_index] = _slot_summary(_active_profile)
	_index = {"version": SAVE_VERSION, "slots": slots}
	var index_result := _write_json_atomic(_index_path(), _index, _index_backup_path())
	if not index_result.ok:
		save_status_changed.emit("保存失败：%s" % index_result.message, true)
		return index_result
	save_status_changed.emit("保存完成", false)
	index_changed.emit()
	return {"ok": true, "message": "保存完成"}


func request_return_to_list() -> Dictionary:
	if not _challenge_locks.is_empty():
		var reason := _challenge_lock_reason()
		return_countdown_changed.emit(reason, false)
		return _failure(reason)
	if _active_level == null or _active_player == null:
		return _failure("当前无法返回角色列表")
	if _active_level.has_method("is_combat_active") and bool(_active_level.call("is_combat_active")):
		_return_countdown = COMBAT_RETURN_DELAY
		_last_player_health = _active_player.get_health()
		return_countdown_changed.emit("战斗中，正在返回角色列表... %d" % ceili(_return_countdown), true)
		return {"ok": true, "message": ""}
	_finish_return_to_list()
	return {"ok": true, "message": ""}


func cancel_return_to_list(reason: String = "返回已中断") -> void:
	if _return_countdown < 0.0:
		return
	_return_countdown = -1.0
	return_countdown_changed.emit(reason, false)


func set_challenge_lock(lock_id: StringName, locked: bool, reason := "") -> void:
	if locked:
		_challenge_locks[lock_id] = reason
		if _return_countdown >= 0.0:
			cancel_return_to_list(_challenge_lock_reason())
	else:
		_challenge_locks.erase(lock_id)


func _finish_return_to_list() -> void:
	var result := save_now(&"return_to_list")
	if not result.ok:
		return_countdown_changed.emit("保存失败，无法安全返回", false)
		return
	_disconnect_player_signals()
	_active_level = null
	_active_player = null
	_active_profile.clear()
	active_profile_changed.emit("")
	return_countdown_changed.emit("", false)
	if not _test_disable_scene_changes:
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _connect_player_signals(player: Player) -> void:
	if not player.material_changed.is_connected(_on_material_changed):
		player.material_changed.connect(_on_material_changed)
	if not player.progression_changed.is_connected(_on_progression_changed):
		player.progression_changed.connect(_on_progression_changed)
	if not player.equipment_changed.is_connected(_on_equipment_changed):
		player.equipment_changed.connect(_on_equipment_changed)
	if not player.equipment_inventory_changed.is_connected(_on_inventory_changed):
		player.equipment_inventory_changed.connect(_on_inventory_changed)
	if not player.respawned.is_connected(_on_player_respawned):
		player.respawned.connect(_on_player_respawned)
	if not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)


func _disconnect_player_signals() -> void:
	if _active_player == null or not is_instance_valid(_active_player):
		return
	var connections := [
		["material_changed", _on_material_changed],
		["progression_changed", _on_progression_changed],
		["equipment_changed", _on_equipment_changed],
		["equipment_inventory_changed", _on_inventory_changed],
		["respawned", _on_player_respawned],
		["health_changed", _on_player_health_changed],
	]
	for connection in connections:
		var signal_value: Signal = _active_player.get(connection[0])
		if signal_value.is_connected(connection[1]):
			signal_value.disconnect(connection[1])


func _on_material_changed(_total: int) -> void:
	request_autosave(&"materials")


func _on_progression_changed(_level: int, _experience: int, _required: int, _maximum: bool) -> void:
	request_autosave(&"progression")


func _on_equipment_changed() -> void:
	request_autosave(&"equipment")


func _on_inventory_changed() -> void:
	request_autosave(&"inventory")


func _on_player_respawned(_reason: Player.RespawnReason) -> void:
	request_autosave(&"respawn")


func _on_player_health_changed(current: int, _maximum: int) -> void:
	if _return_countdown >= 0.0 and current < _last_player_health:
		cancel_return_to_list("受到攻击，返回已中断")
	_last_player_health = current


func _load_profile(profile_id: String) -> Dictionary:
	var primary := _read_json(_profile_path(profile_id))
	if primary.ok:
		var normalized := _normalize_profile(primary.data)
		if normalized.ok:
			return normalized
	var backup := _read_json(_profile_backup_path(profile_id))
	if backup.ok:
		var normalized_backup := _normalize_profile(backup.data)
		if normalized_backup.ok:
			normalized_backup["message"] = "角色档案已从备份恢复"
			return normalized_backup
	return _failure("角色档案无法读取，原文件未被覆盖")


func _normalize_index(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _failure("角色索引格式无效")
	var source := raw as Dictionary
	var version := int(source.get("version", 0))
	if version > SAVE_VERSION:
		return _failure("角色索引版本过新")
	var result_slots: Array[Dictionary] = []
	for index in SLOT_COUNT:
		result_slots.append(_empty_slot(index))
	var raw_slots_value: Variant = source.get("slots", [])
	if not raw_slots_value is Array:
		return _failure("角色索引栏位格式无效")
	var raw_slots := raw_slots_value as Array
	for raw_slot in raw_slots:
		if not raw_slot is Dictionary:
			continue
		var slot := raw_slot as Dictionary
		var slot_index := int(slot.get("slot", -1))
		if slot_index < 0 or slot_index >= SLOT_COUNT:
			continue
		result_slots[slot_index] = _normalize_slot(slot, slot_index)
	return {"ok": true, "data": {"version": SAVE_VERSION, "slots": result_slots}, "message": ""}


func _normalize_profile(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _failure("角色档案格式无效")
	var profile := (raw as Dictionary).duplicate(true)
	var version := int(profile.get("version", 0))
	if version > SAVE_VERSION:
		return _failure("角色档案版本过新")
	var profile_id := String(profile.get("profile_id", ""))
	var character_name := String(profile.get("name", ""))
	var profession_id := StringName(String(profile.get("profession_id", "")))
	var slot_index := int(profile.get("slot", -1))
	if profile_id.is_empty() or character_name.is_empty() or slot_index < 0 or slot_index >= SLOT_COUNT:
		return _failure("角色档案缺少必要信息")
	if get_profession_definition(profession_id) == null:
		return _failure("角色职业定义不存在")
	profile["version"] = SAVE_VERSION
	profile["play_time_seconds"] = maxi(int(profile.get("play_time_seconds", 0)), 0)
	profile["progression"] = _normalize_progression(profile.get("progression", {}))
	profile["materials"] = _normalize_materials(profile.get("materials", {}))
	profile["equipment"] = _normalize_equipment(profile.get("equipment", {}), profession_id)
	profile["location"] = _normalize_location(profile.get("location", {}))
	profile["created_at"] = int(profile.get("created_at", 0))
	profile["updated_at"] = int(profile.get("updated_at", profile.created_at))
	profile["meta"] = profile.get("meta", {}) if profile.get("meta", {}) is Dictionary else {}
	return {"ok": true, "data": profile, "message": ""}


func _normalize_progression(raw: Variant) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	return {"level": maxi(int(source.get("level", 1)), 1), "experience": maxi(int(source.get("experience", 0)), 0)}


func _normalize_materials(raw: Variant) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	return {"stardust_fragment": maxi(int(source.get("stardust_fragment", 0)), 0)}


func _normalize_equipment(raw: Variant, profession_id: StringName) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	var profession := get_profession_definition(profession_id)
	var equipped: Dictionary = {}
	var raw_equipped_value: Variant = source.get("equipped", {})
	var raw_equipped := raw_equipped_value as Dictionary if raw_equipped_value is Dictionary else {}
	for slot in EquipmentSlot.ALL:
		var equipment_id := StringName(String(raw_equipped.get(String(slot), "")))
		var definition := get_equipment_definition(equipment_id)
		if definition != null and definition.slot == slot and profession.can_equip(definition):
			equipped[String(slot)] = String(definition.id)
	var inventory: Array[Dictionary] = []
	var raw_inventory_value: Variant = source.get("inventory", [])
	var raw_inventory := raw_inventory_value as Array if raw_inventory_value is Array else []
	for entry in raw_inventory:
		if not entry is Dictionary:
			continue
		var equipment_id := StringName(String(entry.get("id", "")))
		var definition := get_equipment_definition(equipment_id)
		var count := maxi(int(entry.get("count", 0)), 0)
		if definition != null and count > 0:
			inventory.append({"id": String(definition.id), "count": count})
	return {"equipped": equipped, "inventory": inventory}


func _normalize_location(raw: Variant) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	var area_id := StringName(String(source.get("area_id", DEFAULT_AREA_ID)))
	var spawn_id := StringName(String(source.get("safe_spawn_id", DEFAULT_SPAWN_ID)))
	if area_id != DEFAULT_AREA_ID:
		area_id = DEFAULT_AREA_ID
		spawn_id = DEFAULT_SPAWN_ID
	if spawn_id != DEFAULT_SPAWN_ID:
		spawn_id = DEFAULT_SPAWN_ID
	return {"area_id": String(area_id), "safe_spawn_id": String(spawn_id)}


func _rebuild_index_from_profiles() -> Dictionary:
	var slots: Array[Dictionary] = []
	for index in SLOT_COUNT:
		slots.append(_empty_slot(index))
	var directory := DirAccess.open(save_root)
	if directory == null:
		return {"version": SAVE_VERSION, "slots": slots}
	for file_name in directory.get_files():
		if file_name == "index.json" or not file_name.ends_with(".json"):
			continue
		var result := _read_json("%s/%s" % [save_root, file_name])
		if not result.ok:
			continue
		var normalized := _normalize_profile(result.data)
		if not normalized.ok:
			continue
		var profile := normalized.data as Dictionary
		var slot_index := int(profile.slot)
		if String(slots[slot_index].profile_id).is_empty() or int(profile.updated_at) > int(slots[slot_index].updated_at):
			slots[slot_index] = _slot_summary(profile)
	return {"version": SAVE_VERSION, "slots": slots}


func _normalize_slot(source: Dictionary, slot_index: int) -> Dictionary:
	var profile_id := String(source.get("profile_id", ""))
	if profile_id.is_empty():
		return _empty_slot(slot_index)
	return {
		"slot": slot_index,
		"profile_id": profile_id,
		"name": String(source.get("name", "")),
		"profession_id": String(source.get("profession_id", "")),
		"level": maxi(int(source.get("level", 1)), 1),
		"area_id": String(source.get("area_id", DEFAULT_AREA_ID)),
		"play_time_seconds": maxi(int(source.get("play_time_seconds", 0)), 0),
		"created_at": int(source.get("created_at", 0)),
		"updated_at": int(source.get("updated_at", 0)),
	}


func _slot_summary(profile: Dictionary) -> Dictionary:
	var progression := profile.get("progression", {}) as Dictionary
	var location := profile.get("location", {}) as Dictionary
	return {
		"slot": int(profile.slot),
		"profile_id": String(profile.profile_id),
		"name": String(profile.name),
		"profession_id": String(profile.profession_id),
		"level": maxi(int(progression.get("level", 1)), 1),
		"area_id": String(location.get("area_id", DEFAULT_AREA_ID)),
		"play_time_seconds": maxi(int(profile.get("play_time_seconds", 0)), 0),
		"created_at": int(profile.get("created_at", 0)),
		"updated_at": int(profile.get("updated_at", 0)),
	}


func _empty_slot(slot_index: int) -> Dictionary:
	return {
		"slot": slot_index,
		"profile_id": "",
		"name": "",
		"profession_id": "",
		"level": 0,
		"area_id": "",
		"play_time_seconds": 0,
		"created_at": 0,
		"updated_at": 0,
	}


func _accumulate_play_time() -> void:
	if not has_active_profile() or _session_started_msec <= 0:
		return
	var elapsed := maxi(Time.get_ticks_msec() - _session_started_msec, 0)
	_active_profile["play_time_seconds"] = maxi(int(_active_profile.get("play_time_seconds", 0)), 0) + elapsed / 1000
	_session_started_msec = Time.get_ticks_msec()


func _challenge_lock_reason() -> String:
	for value in _challenge_locks.values():
		var reason := String(value)
		if not reason.is_empty():
			return reason
	return "特殊挑战进行中，无法返回角色列表"


func _ensure_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_root))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/backups" % save_root))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("文件不存在")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取文件")
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("JSON 格式无效")
	return {"ok": true, "data": json.data, "message": ""}


func _write_json_atomic(path: String, data: Dictionary, backup_path: String) -> Dictionary:
	_ensure_directories()
	var temp_path := "%s.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure("无法创建临时存档")
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return _failure("无法创建存档备份")
		var remove_error := DirAccess.remove_absolute(absolute_path)
		if remove_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return _failure("无法替换旧存档")
	var rename_error := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if rename_error != OK:
		return _failure("无法完成存档写入")
	return {"ok": true, "message": ""}


func _generate_profile_id(slot_index: int, unix_time: int) -> String:
	var nonce := "%s:%s:%s" % [unix_time, slot_index, Time.get_ticks_usec()]
	return "profile_%d_%s" % [unix_time, nonce.sha256_text().substr(0, 12)]


func _index_path() -> String:
	return "%s/index.json" % save_root


func _index_backup_path() -> String:
	return "%s/backups/index.json" % save_root


func _profile_path(profile_id: String) -> String:
	return "%s/%s.json" % [save_root, profile_id]


func _profile_backup_path(profile_id: String) -> String:
	return "%s/backups/%s.json" % [save_root, profile_id]


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
