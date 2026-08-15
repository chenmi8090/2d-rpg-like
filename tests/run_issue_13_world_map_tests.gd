extends SceneTree

const TEST_ROOT := "user://issue_13_tests"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_world_definitions()
	await _test_map_runtime()
	await _test_save_location_and_checkpoint()
	_clean_test_root()
	if _failures.is_empty():
		print("Issue #13 world map tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_world_definitions() -> void:
	var validation := DefinitionRegistry.validate_world()
	_expect(validation.ok, "世界图定义和场景引用必须完整有效")
	var passage := DefinitionRegistry.get_map(&"field_passage_1")
	_expect(passage != null and passage.portals.size() == 3, "野外通道-1 提供三条显式传送边")
	_expect(passage.get_portal(&"portal_a").target_map_id == &"field_passage_2", "分支 A 指向野外通道-2")
	_expect(passage.get_portal(&"portal_b").target_map_id == &"field_passage_3", "分支 B 指向野外通道-3")
	for definition in DefinitionRegistry.get_maps():
		var ids: Dictionary = {}
		for portal in definition.portals:
			_expect(not ids.has(portal.id), "每张地图内 portal_id 不重复：%s" % definition.id)
			ids[portal.id] = true
			_expect(portal.interaction_radius > 0.0, "传送门具有正数交互范围：%s" % portal.id)
	_test_new_map_platform_heights()


func _test_new_map_platform_heights() -> void:
	const FLOOR_TOP := 640.0
	const MAX_STEP_HEIGHT := 90.0
	for map_id in [&"field_passage_1", &"field_passage_2", &"field_passage_3"]:
		var definition := DefinitionRegistry.get_map(map_id)
		var packed := load(definition.scene_path) as PackedScene
		var layout := packed.instantiate()
		var previous_surface_y := FLOOR_TOP
		for rect: Rect2 in layout.get_platform_rects():
			var rise: float = previous_surface_y - rect.position.y
			_expect(rise <= MAX_STEP_HEIGHT, "%s 的连续平台高度差不超过 %.0f 像素" % [map_id, MAX_STEP_HEIGHT])
			previous_surface_y = rect.position.y
		layout.free()


func _test_map_runtime() -> void:
	var packed := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	_expect(level.get_area_id() == &"test_level", "gameplay shell 默认载入战斗试验场")
	var player := level.get_node("Player") as Player
	var old_enemies: Array[GroundedEnemyController] = level._encounter_manager.get_owned_enemies()
	var transition_result: Dictionary = level.load_world_map(&"field_passage_1", &"from_test_level")
	_expect(transition_result.ok, "切图请求成功")
	_expect(level._encounter_manager.get_capacity() == 6, "切图后只建立目标地图遭遇")
	_expect(level.get_area_id() == &"field_passage_1", "切图后当前地图 ID 更新")
	_expect(player.global_position.is_equal_approx(Vector2(100, 560)), "目标 entry 决定玩家落点")
	await process_frame
	for enemy in old_enemies:
		_expect(not is_instance_valid(enemy), "切换地图会移除来源地图怪物")
	player.global_position = Vector2(1450, 560)
	level._portal_transition_locked = false
	level._update_world_interaction()
	_expect(level._active_portal != null and level._active_portal.id == &"portal_a", "玩家进入交互范围后选择最近传送门")
	level._use_active_portal()
	_expect(level.get_area_id() == &"field_passage_2", "传送门按目标 map/entry 完成切换")
	_expect(level._portal_transition_locked, "切图后重复触发锁立即生效")
	level._update_world_interaction()
	_expect(not level._portal_transition_locked, "松开 W 后入口传送门可重新使用")
	_expect(level._active_portal != null and level._active_portal.id == &"return_field_passage_1", "目标地图入口可直接返回")
	level._use_active_portal()
	_expect(level.get_area_id() == &"field_passage_1", "可从进入的传送门返回来源地图")
	_expect(player.global_position.is_equal_approx(Vector2(1450, 560)), "返回后落在对应来源入口")
	level._show_reminder(level._world_status_text, "临时提醒", 0.01)
	await create_timer(0.02).timeout
	_expect(level._world_status_text.text.is_empty(), "提醒类文本会在限定时间后消失")
	level.queue_free()
	await process_frame


func _test_save_location_and_checkpoint() -> void:
	_clean_test_root()
	var session := root.get_node("GameSession")
	session.use_test_save_root(TEST_ROOT)
	session.set_test_disable_scene_changes(true)
	_expect(session.create_character(0, "地图测试", &"traveler").ok, "可建立地图测试角色")
	_expect(session.continue_character(0).ok, "可载入地图测试角色")
	_expect(session.set_continue_location(&"field_passage_3", &"from_field_passage_1").ok, "继续位置可独立更新")
	var before_checkpoint: Dictionary = session.get_active_world_location()
	_expect(String(before_checkpoint.continue_map_id) == "field_passage_3", "继续位置记录当前传送落点")
	_expect(session.activate_checkpoint(&"field_passage_2_center").ok, "可激活跨地图复活点")
	var after_checkpoint: Dictionary = session.get_active_world_location()
	_expect(String(after_checkpoint.continue_map_id) == "field_passage_3", "激活复活点不会覆盖继续位置")
	var respawn: Dictionary = session.get_respawn_location()
	_expect(String(respawn.map_id) == "field_passage_2" and String(respawn.entry_id) == "center_checkpoint", "死亡恢复位置来自活动复活点")
	var profile_id := String((session.get_slot(0) as Dictionary).profile_id)
	session.save_now(&"issue_13_test")
	var profile_path := "%s/%s.json" % [TEST_ROOT, profile_id]
	var profile := _read_json_file(profile_path)
	_expect(profile.has("world_location") and not profile.has("location"), "版本 5 存档只写入 world_location")
	_expect(String((profile.world_location as Dictionary).continue_map_id) == "field_passage_3", "存档保留继续位置")
	session.return_to_character_select()
	session.reset_save_root()
	session.set_test_disable_scene_changes(false)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _read_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _clean_test_root() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_directory(path.path_join(directory_name))
	DirAccess.remove_absolute(path)
