extends Node

signal index_changed
signal active_profile_changed(profile_id: String)
signal save_status_changed(message: String, failed: bool)
signal return_countdown_changed(message: String, active: bool)

const SAVE_VERSION := 6
const SKILL_ENTITLEMENT_VERSION := 4
const SLOT_COUNT := 3
const DEFAULT_SAVE_ROOT := "user://profiles"
const CHARACTER_SELECT_SCENE := "res://scenes/ui/character_select.tscn"
const CHARACTER_CREATION_SCENE := "res://scenes/ui/character_creation.tscn"
const GAMEPLAY_SCENE := "res://scenes/levels/test_level.tscn"
const DEFAULT_REGION_ID := &"first_region"
const DEFAULT_MAP_ID := &"test_level"
const DEFAULT_ENTRY_ID := &"start"
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
	&"toggle_skills",
	&"skill_slot_1",
	&"skill_slot_2",
	&"skill_slot_3",
	&"skill_slot_4",
	&"skill_slot_5",
	&"skill_slot_6",
	&"skill_slot_7",
	&"skill_slot_8",
	&"skill_slot_9",
	&"skill_slot_10",
	&"reset",
]
const DEFAULT_AREA_ID := DEFAULT_MAP_ID
const DEFAULT_SPAWN_ID := DEFAULT_ENTRY_ID
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
	var equipment := _create_starting_equipment_snapshot(profession)
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
		"backpack": _default_backpack_snapshot(),
		"skills": {
			"unspent_points": progression.starting_skill_points if progression != null else 0,
			"ranks": {},
		},
		"skill_quickbar": {"slots": ["", "", "", "", "", "", "", "", "", ""]},
		"equipment": equipment,
		"world_location": _default_world_location(),
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
		var error := get_tree().change_scene_to_file(GAMEPLAY_SCENE)
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
	var location := get_active_world_location()
	var map_id := StringName(String(location.get("continue_map_id", DEFAULT_MAP_ID)))
	var entry_id := StringName(String(location.get("continue_spawn_point_id", DEFAULT_ENTRY_ID)))
	var map_definition := DefinitionRegistry.get_map(map_id)
	if map_definition == null:
		map_definition = DefinitionRegistry.get_map(DEFAULT_MAP_ID)
		map_id = DEFAULT_MAP_ID
		entry_id = DEFAULT_ENTRY_ID
	var apply_result := player.apply_save_snapshot(_active_profile)
	if apply_result.ok and level.has_method("load_world_map"):
		apply_result = level.call("load_world_map", map_id, entry_id)
	elif apply_result.ok:
		var spawn_position := Vector2(80.0, 550.0)
		if level.has_method("get_area_id") and level.call("get_area_id") != map_id:
			map_id = DEFAULT_MAP_ID
			entry_id = DEFAULT_ENTRY_ID
		if level.has_method("get_safe_spawn_position"):
			spawn_position = level.call("get_safe_spawn_position", entry_id)
			if spawn_position == Vector2.INF:
				entry_id = DEFAULT_ENTRY_ID
				spawn_position = level.call("get_safe_spawn_position", entry_id)
		player.apply_safe_spawn(spawn_position)
	if apply_result.ok:
		set_continue_location(map_id, entry_id)
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
		_active_profile["backpack"] = snapshot.backpack
		_active_profile["equipment"] = snapshot.equipment
		_active_profile["skills"] = snapshot.skills
		_active_profile["skill_quickbar"] = snapshot.skill_quickbar
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
	if not player.stackable_inventory_changed.is_connected(_on_inventory_changed):
		player.stackable_inventory_changed.connect(_on_inventory_changed)
	if not player.skills_changed.is_connected(_on_skills_changed):
		player.skills_changed.connect(_on_skills_changed)
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
		["stackable_inventory_changed", _on_inventory_changed],
		["skills_changed", _on_skills_changed],
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


func _on_skills_changed() -> void:
	request_autosave(&"skills")


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
	profile["backpack"] = _normalize_backpack(
		profile.get("backpack", {}),
		profile.get("materials", {}),
		version
	)
	profile.erase("materials")
	profile["equipment"] = _normalize_equipment(profile.get("equipment", {}), profession_id, version)
	var normalized_inventory := (profile.equipment as Dictionary).get("inventory", []) as Array
	var backpack := profile.backpack as Dictionary
	var capacities := backpack.get("capacities", {}) as Dictionary
	capacities["equipment"] = maxi(
		maxi(
			int(capacities.get("equipment", Player.DEFAULT_BACKPACK_CAPACITY)),
			normalized_inventory.size()
		),
		Player.DEFAULT_BACKPACK_CAPACITY
	)
	backpack["capacities"] = capacities
	profile["backpack"] = backpack
	profile["skills"] = _normalize_skills(
		profile.get("skills", {}),
		profession_id,
		int((profile.get("progression", {}) as Dictionary).get("level", 1)),
		version
	)
	profile["skill_quickbar"] = _normalize_skill_quickbar(
		profile.get("skill_quickbar", {}),
		profession_id,
		profile.skills,
		version
	)
	profile["world_location"] = _normalize_world_location(
		profile.get("world_location", profile.get("location", {})),
		version
	)
	profile.erase("location")
	profile["created_at"] = int(profile.get("created_at", 0))
	profile["updated_at"] = int(profile.get("updated_at", profile.created_at))
	profile["meta"] = profile.get("meta", {}) if profile.get("meta", {}) is Dictionary else {}
	return {"ok": true, "data": profile, "message": ""}


func _normalize_progression(raw: Variant) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	return {"level": maxi(int(source.get("level", 1)), 1), "experience": maxi(int(source.get("experience", 0)), 0)}


func _default_backpack_snapshot() -> Dictionary:
	var capacities: Dictionary = {}
	var stacks: Dictionary = {}
	for category in BackpackCategory.ALL:
		capacities[String(category)] = Player.DEFAULT_BACKPACK_CAPACITY
	for category in BackpackCategory.STACKABLE:
		stacks[String(category)] = []
	return {"capacities": capacities, "equipment_slots": [], "stacks": stacks}


func _normalize_backpack(raw: Variant, legacy_materials_raw: Variant, source_version: int) -> Dictionary:
	var result := _default_backpack_snapshot()
	var capacities := result.capacities as Dictionary
	var stacks := result.stacks as Dictionary
	var source := raw as Dictionary if raw is Dictionary else {}
	if source_version >= 6:
		var raw_capacities := source.get("capacities", {}) as Dictionary
		for category in BackpackCategory.ALL:
			capacities[String(category)] = maxi(
				int(raw_capacities.get(String(category), Player.DEFAULT_BACKPACK_CAPACITY)),
				Player.DEFAULT_BACKPACK_CAPACITY
			)
		var raw_stacks := source.get("stacks", {}) as Dictionary
		var equipment_slots: Array[String] = []
		for raw_id in source.get("equipment_slots", []) as Array:
			equipment_slots.append(String(raw_id))
		result["equipment_slots"] = equipment_slots
		for category in BackpackCategory.STACKABLE:
			_normalize_stack_entries(
				raw_stacks.get(String(category), []),
				category,
				stacks[String(category)] as Array
			)
	else:
		var legacy_materials := legacy_materials_raw as Dictionary if legacy_materials_raw is Dictionary else {}
		var legacy_stardust := maxi(int(legacy_materials.get("stardust_fragment", 0)), 0)
		if legacy_stardust > 0:
			_normalize_stack_entries(
				[{"item_id": "stardust_fragment", "quantity": legacy_stardust}],
				BackpackCategory.OTHER,
				stacks[String(BackpackCategory.OTHER)] as Array
			)
	for category in BackpackCategory.STACKABLE:
		capacities[String(category)] = maxi(
			maxi(
				int(capacities[String(category)]),
				(stacks[String(category)] as Array).size()
			),
			Player.DEFAULT_BACKPACK_CAPACITY
		)
	return {"capacities": capacities, "stacks": stacks}


func _normalize_stack_entries(raw: Variant, category: StringName, output: Array) -> void:
	if not raw is Array:
		return
	for raw_stack in raw as Array:
		if not raw_stack is Dictionary:
			output.append({})
			continue
		var stack := raw_stack as Dictionary
		var item_id := StringName(String(stack.get("item_id", "")))
		var quantity := maxi(int(stack.get("quantity", 0)), 0)
		var definition := DefinitionRegistry.get_stackable_item(item_id)
		if definition == null or definition.category != category or quantity <= 0:
			output.append({})
			continue
		var remaining := quantity
		while remaining > 0:
			var added := mini(definition.stack_limit, remaining)
			output.append({"item_id": String(item_id), "quantity": added})
			remaining -= added


func _normalize_skills(
	raw: Variant,
	profession_id: StringName,
	character_level: int,
	source_version: int
) -> Dictionary:
	var preserve_existing_skills := source_version >= 3
	var source := raw as Dictionary if preserve_existing_skills and raw is Dictionary else {}
	var ranks: Dictionary = {}
	var spent_points := 0
	var raw_ranks := source.get("ranks", {}) as Dictionary
	for raw_skill_id in raw_ranks:
		var skill_id := StringName(String(raw_skill_id))
		var definition := DefinitionRegistry.get_skill(skill_id)
		if definition == null or not definition.is_available_to_profession(profession_id):
			continue
		var rank := clampi(int(raw_ranks[raw_skill_id]), 0, definition.get_maximum_rank())
		if rank > 0:
			ranks[String(skill_id)] = rank
			spent_points += rank
	var unspent_points := maxi(int(source.get("unspent_points", 0)), 0)
	if source_version < SKILL_ENTITLEMENT_VERSION:
		var progression := load(
			"res://resources/progression/default_player_progression.tres"
		) as PlayerProgressionDefinition
		var starting_level := progression.starting_level if progression != null else 1
		var starting_points := progression.starting_skill_points if progression != null else 0
		var points_per_level := progression.skill_points_per_level if progression != null else 1
		var earned_points := starting_points + maxi(
			character_level - starting_level,
			0
		) * points_per_level
		var missing_points := maxi(earned_points - unspent_points - spent_points, 0)
		unspent_points += missing_points
	return {
		"unspent_points": unspent_points,
		"ranks": ranks,
	}


func _normalize_skill_quickbar(
	raw: Variant,
	profession_id: StringName,
	skills: Dictionary,
	source_version: int
) -> Dictionary:
	var default_slots := ["", "", "", "", "", "", "", "", "", ""]
	if source_version < 3:
		return {"slots": default_slots}
	var source := raw as Dictionary if raw is Dictionary else {}
	var raw_slots := source.get("slots", []) as Array
	var slots: Array[String] = []
	var ranks := skills.get("ranks", {}) as Dictionary
	var assigned_skill_ids: Dictionary = {}
	for raw_skill_id in raw_slots:
		if slots.size() >= default_slots.size():
			break
		var skill_id := StringName(String(raw_skill_id))
		var definition := DefinitionRegistry.get_skill(skill_id)
		if (
			definition == null
			or not definition.is_active()
			or not definition.is_available_to_profession(profession_id)
			or int(ranks.get(String(skill_id), 0)) <= 0
			or assigned_skill_ids.has(skill_id)
		):
			slots.append("")
		else:
			slots.append(String(skill_id))
			assigned_skill_ids[skill_id] = true
	if slots.size() < default_slots.size():
		slots.resize(default_slots.size())
	return {"slots": slots}


func _normalize_equipment(raw: Variant, profession_id: StringName, source_version := SAVE_VERSION) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	if source_version < 2 or not source.has("instances"):
		return _migrate_legacy_equipment(source, profession_id)
	var profession := get_profession_definition(profession_id)
	var instances: Array[Dictionary] = []
	var valid_ids: Dictionary = {}
	var maximum_serial := 0
	for raw_instance in source.get("instances", []) as Array:
		var normalized := _normalize_equipment_instance(raw_instance)
		if normalized.is_empty():
			continue
		var instance_id := String(normalized.instance_id)
		if valid_ids.has(instance_id):
			continue
		valid_ids[instance_id] = normalized
		instances.append(normalized)
		maximum_serial = maxi(maximum_serial, _equipment_serial_from_id(instance_id))
	var equipped: Dictionary = {}
	var raw_equipped := source.get("equipped", {}) as Dictionary
	for slot in EquipmentSlot.ALL:
		var instance_id := String(raw_equipped.get(String(slot), ""))
		var snapshot_value: Variant = valid_ids.get(instance_id, {})
		var snapshot := snapshot_value as Dictionary if snapshot_value is Dictionary else {}
		if snapshot.is_empty():
			continue
		var definition := get_equipment_definition(StringName(String(snapshot.definition_id)))
		if definition != null and definition.slot == slot and profession.can_equip(definition):
			equipped[String(slot)] = instance_id
	var equipped_ids := equipped.values()
	var inventory: Array[String] = []
	for raw_id in source.get("inventory", []) as Array:
		var instance_id := String(raw_id)
		if valid_ids.has(instance_id) and instance_id not in equipped_ids and instance_id not in inventory:
			inventory.append(instance_id)
	var next_serial := maxi(maxi(int(source.get("next_instance_serial", 1)), maximum_serial + 1), 1)
	return {"next_instance_serial": next_serial, "instances": instances, "equipped": equipped, "inventory": inventory}


func _migrate_legacy_equipment(source: Dictionary, profession_id: StringName) -> Dictionary:
	var profession := get_profession_definition(profession_id)
	var serial := 1
	var instances: Array[Dictionary] = []
	var equipped: Dictionary = {}
	var raw_equipped := source.get("equipped", {}) as Dictionary
	for slot in EquipmentSlot.ALL:
		var definition := get_equipment_definition(StringName(String(raw_equipped.get(String(slot), ""))))
		if definition == null or definition.slot != slot or not profession.can_equip(definition):
			continue
		var snapshot := _template_instance_snapshot(definition, serial)
		serial += 1
		instances.append(snapshot)
		equipped[String(slot)] = String(snapshot.instance_id)
	var inventory: Array[String] = []
	for entry in source.get("inventory", []) as Array:
		if not entry is Dictionary:
			continue
		var definition := get_equipment_definition(StringName(String(entry.get("id", ""))))
		var count := clampi(int(entry.get("count", 0)), 0, 99)
		if definition == null:
			continue
		for _copy in count:
			var snapshot := _template_instance_snapshot(definition, serial)
			serial += 1
			instances.append(snapshot)
			inventory.append(String(snapshot.instance_id))
	return {"next_instance_serial": serial, "instances": instances, "equipped": equipped, "inventory": inventory}


func _create_starting_equipment_snapshot(profession: ProfessionDefinition) -> Dictionary:
	var serial := 1
	var instances: Array[Dictionary] = []
	var equipped: Dictionary = {}
	for definition in profession.starting_equipment:
		if definition == null or not profession.can_equip(definition):
			continue
		var snapshot := _template_instance_snapshot(definition, serial)
		serial += 1
		instances.append(snapshot)
		equipped[String(definition.slot)] = String(snapshot.instance_id)
	return {"next_instance_serial": serial, "instances": instances, "equipped": equipped, "inventory": []}


func _template_instance_snapshot(definition: EquipmentDefinition, serial: int) -> Dictionary:
	var modifiers: Array[Dictionary] = []
	for modifier in definition.get_modifiers():
		if modifier == null:
			continue
		modifiers.append({"stat_key": String(modifier.stat_key), "flat_bonus": modifier.flat_bonus, "percent_bonus": modifier.percent_bonus})
	return {
		"instance_id": "equipment_%08d" % serial,
		"definition_id": String(definition.id),
		"quality": String(EquipmentQuality.COMMON),
		"modifiers": modifiers,
	}


func _normalize_equipment_instance(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var source := raw as Dictionary
	var instance_id := String(source.get("instance_id", ""))
	var definition := get_equipment_definition(StringName(String(source.get("definition_id", ""))))
	var quality := StringName(String(source.get("quality", "")))
	if instance_id.is_empty() or definition == null or not EquipmentQuality.is_valid(quality):
		return {}
	var modifiers: Array[Dictionary] = []
	for raw_modifier in source.get("modifiers", []) as Array:
		if not raw_modifier is Dictionary:
			continue
		var stat_key := StringName(String(raw_modifier.get("stat_key", "")))
		var flat_bonus := float(raw_modifier.get("flat_bonus", 0.0))
		var percent_bonus := float(raw_modifier.get("percent_bonus", 0.0))
		if stat_key not in EquipmentLootRoller.ALLOWED_STATS or not is_finite(flat_bonus) or flat_bonus <= 0.0 or not is_zero_approx(percent_bonus):
			continue
		modifiers.append({"stat_key": String(stat_key), "flat_bonus": flat_bonus, "percent_bonus": 0.0})
	if modifiers.is_empty() and not definition.get_modifiers().is_empty():
		return {}
	return {"instance_id": instance_id, "definition_id": String(definition.id), "quality": String(quality), "modifiers": modifiers}


func _equipment_serial_from_id(instance_id: String) -> int:
	if not instance_id.begins_with("equipment_"):
		return 0
	return maxi(int(instance_id.trim_prefix("equipment_")), 0)


func _default_world_location() -> Dictionary:
	return {
		"current_region_id": String(DEFAULT_REGION_ID),
		"continue_map_id": String(DEFAULT_MAP_ID),
		"continue_spawn_point_id": String(DEFAULT_ENTRY_ID),
		"active_checkpoint_id": "",
		"activated_checkpoint_ids": [],
	}


func _normalize_world_location(raw: Variant, source_version: int) -> Dictionary:
	var source := raw as Dictionary if raw is Dictionary else {}
	var map_id := StringName(String(source.get(
		"continue_map_id",
		source.get("area_id", DEFAULT_MAP_ID)
	)))
	var entry_id := StringName(String(source.get(
		"continue_spawn_point_id",
		source.get("safe_spawn_id", DEFAULT_ENTRY_ID)
	)))
	if source_version < 5 and map_id == &"test_level" and entry_id == &"default":
		entry_id = DEFAULT_ENTRY_ID
	var map_definition := DefinitionRegistry.get_map(map_id)
	if map_definition == null or not map_definition.allow_continue:
		map_definition = DefinitionRegistry.get_map(DEFAULT_MAP_ID)
		map_id = DEFAULT_MAP_ID
	if map_definition == null:
		return _default_world_location()
	var entry := map_definition.get_entry(entry_id)
	if entry == null or not entry.allow_continue_fallback:
		entry_id = map_definition.default_entry_id
	var region_id := map_definition.region_id
	var active_checkpoint_id := StringName(String(source.get("active_checkpoint_id", "")))
	if active_checkpoint_id != &"" and DefinitionRegistry.get_checkpoint(active_checkpoint_id) == null:
		active_checkpoint_id = &""
	var activated: Array[String] = []
	var raw_activated: Variant = source.get("activated_checkpoint_ids", [])
	if raw_activated is Array:
		for raw_checkpoint_id in raw_activated as Array:
			var checkpoint_id := StringName(String(raw_checkpoint_id))
			if (
				checkpoint_id != &""
				and DefinitionRegistry.get_checkpoint(checkpoint_id) != null
				and String(checkpoint_id) not in activated
			):
				activated.append(String(checkpoint_id))
	return {
		"current_region_id": String(region_id),
		"continue_map_id": String(map_id),
		"continue_spawn_point_id": String(entry_id),
		"active_checkpoint_id": String(active_checkpoint_id),
		"activated_checkpoint_ids": activated,
	}


func get_active_world_location() -> Dictionary:
	return (_active_profile.get("world_location", _default_world_location()) as Dictionary).duplicate(true)


func get_continue_map_definition() -> MapDefinition:
	var location := get_active_world_location()
	return DefinitionRegistry.get_map(StringName(String(location.get("continue_map_id", DEFAULT_MAP_ID))))


func get_respawn_location() -> Dictionary:
	var location := get_active_world_location()
	var checkpoint_id := StringName(String(location.get("active_checkpoint_id", "")))
	var checkpoint := DefinitionRegistry.get_checkpoint(checkpoint_id)
	if checkpoint == null:
		var region := DefinitionRegistry.get_region(StringName(String(location.get(
			"current_region_id",
			DEFAULT_REGION_ID
		))))
		if region == null:
			region = DefinitionRegistry.get_region(DEFAULT_REGION_ID)
		if region != null:
			checkpoint = DefinitionRegistry.get_checkpoint(region.default_checkpoint_id)
	if checkpoint == null:
		return {"map_id": String(DEFAULT_MAP_ID), "entry_id": String(DEFAULT_ENTRY_ID)}
	return {"map_id": String(checkpoint.map_id), "entry_id": String(checkpoint.entry_id)}


func set_continue_location(map_id: StringName, entry_id: StringName) -> Dictionary:
	var map_definition := DefinitionRegistry.get_map(map_id)
	if map_definition == null or not map_definition.allow_continue:
		return _failure("目标地图无效")
	var entry := map_definition.get_entry(entry_id)
	if entry == null or not entry.allow_continue_fallback:
		return _failure("目标入口无效")
	var location := get_active_world_location()
	location["current_region_id"] = String(map_definition.region_id)
	location["continue_map_id"] = String(map_id)
	location["continue_spawn_point_id"] = String(entry_id)
	_active_profile["world_location"] = location
	return {"ok": true, "message": ""}


func activate_checkpoint(checkpoint_id: StringName) -> Dictionary:
	var checkpoint := DefinitionRegistry.get_checkpoint(checkpoint_id)
	if checkpoint == null:
		return _failure("复活点无效")
	var checkpoint_map := DefinitionRegistry.get_map(checkpoint.map_id)
	if checkpoint_map == null:
		return _failure("复活点地图无效")
	var location := get_active_world_location()
	location["current_region_id"] = String(checkpoint_map.region_id)
	if StringName(String(location.get("active_checkpoint_id", ""))) == checkpoint_id:
		return {"ok": true, "changed": false, "message": "当前复活点"}
	var activated := location.get("activated_checkpoint_ids", []) as Array
	if String(checkpoint_id) not in activated:
		activated.append(String(checkpoint_id))
	location["active_checkpoint_id"] = String(checkpoint_id)
	location["activated_checkpoint_ids"] = activated
	_active_profile["world_location"] = location
	var save_result := save_now(&"checkpoint")
	if not save_result.ok:
		return save_result
	return {"ok": true, "changed": true, "message": "复活点已激活"}


func _normalize_location(raw: Variant) -> Dictionary:
	var world := _normalize_world_location(raw, 4)
	return {
		"area_id": world.continue_map_id,
		"safe_spawn_id": world.continue_spawn_point_id,
	}


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
	var location := profile.get("world_location", _default_world_location()) as Dictionary
	return {
		"slot": int(profile.slot),
		"profile_id": String(profile.profile_id),
		"name": String(profile.name),
		"profession_id": String(profile.profession_id),
		"level": maxi(int(progression.get("level", 1)), 1),
		"area_id": String(location.get("continue_map_id", DEFAULT_MAP_ID)),
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
