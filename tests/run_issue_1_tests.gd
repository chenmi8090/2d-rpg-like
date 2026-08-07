extends SceneTree

const TEST_ROOT := "user://issue_1_test_profiles"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session_script := load("res://scripts/services/game_session.gd") as GDScript
	var session := session_script.new() as Node
	root.add_child(session)
	session.use_test_save_root(TEST_ROOT)
	session.set_test_disable_scene_changes(true)
	_clean_test_root()
	session.refresh_index()

	_expect(session.get_slots().size() == 3, "角色列表固定为三个栏位")
	_expect(not session.begin_character_creation(-1).ok, "拒绝无效创建栏位")
	_expect(session.begin_character_creation(0).ok, "空栏位可以进入独立创建流程")
	_expect(session.get_pending_creation_slot() == 0, "保存待创建栏位")
	session.clear_pending_creation_slot()
	_expect(session.get_pending_creation_slot() == -1, "取消创建时清除待创建栏位")
	_expect(not session.validate_character_name("A").ok, "拒绝一个字符的名称")
	_expect(session.validate_character_name("小明").ok, "接受两个中文字符")
	_expect(session.validate_character_name("小明A1").ok, "接受中文、字母和数字组合")
	_expect(not session.validate_character_name("小 明").ok, "拒绝名称中的空格")
	_expect(session.validate_character_name("  小明  ").name == "小明", "自动去除首尾空格")
	_expect(session.validate_character_name("abcdefghijkl").ok, "接受十二字符名称")
	_expect(not session.validate_character_name("abcdefghijklm").ok, "拒绝十三字符名称")

	var first: Dictionary = session.create_character(0, "小明", &"traveler")
	_expect(first.ok, "创建旅人角色")
	_expect(not session.begin_character_creation(0).ok, "已有角色的栏位不能进入创建流程")
	_expect(not session.validate_character_name("小明").ok, "拒绝重复名称")
	var second: Dictionary = session.create_character(1, "星月", &"star_seeker")
	_expect(second.ok, "创建观星者角色")
	var third: Dictionary = session.create_character(2, "Traveler3", &"traveler")
	_expect(third.ok, "创建第三个角色")
	_expect(not session.create_character(0, "第四人", &"traveler").ok, "拒绝占用已有栏位")

	var first_slot: Dictionary = session.get_slot(0)
	var second_slot: Dictionary = session.get_slot(1)
	_expect(first_slot.profession_id == "traveler", "永久记录旅人职业 ID")
	_expect(second_slot.profession_id == "star_seeker", "永久记录观星者职业 ID")
	_expect(first_slot.profile_id != second_slot.profile_id, "不同角色使用独立稳定 ID")
	Input.action_press(&"move_left")
	session.prepare_gameplay_scene_transition()
	_expect(not Input.is_action_pressed(&"move_left"), "进入游戏前释放残留的左移输入")

	var continue_result: Dictionary = session.continue_character(0)
	_expect(continue_result.ok, "读取角色档案")
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	var player := player_scene.instantiate() as Player
	root.add_child(player)
	await process_frame
	var level := TestLevelStub.new()
	root.add_child(level)
	var bind_result: Dictionary = session.bind_level(level, player)
	_expect(bind_result.ok, "将角色档案应用到玩家")
	Input.action_press(&"move_left")
	await physics_frame
	_expect(is_zero_approx(player.velocity.x), "载入后的首个物理帧忽略残留左移输入")
	Input.action_release(&"move_left")
	player.add_experience(25)
	player.collect_material(&"stardust_fragment", 7)
	var staff := DefinitionRegistry.get_equipment(&"star_staff")
	player.collect_equipment(staff, 2)
	var save_result: Dictionary = session.save_now(&"test")
	_expect(save_result.ok, "保存角色进度")
	var first_level_after_save := player.get_level()
	session.unbind_level(level)
	player.queue_free()
	level.queue_free()
	await process_frame

	_expect(session.continue_character(1).ok, "读取第二角色档案")
	var second_player := player_scene.instantiate() as Player
	root.add_child(second_player)
	await process_frame
	var second_level := TestLevelStub.new()
	root.add_child(second_level)
	_expect(session.bind_level(second_level, second_player).ok, "应用第二角色档案")
	_expect(second_player.get_level() == 1, "第二角色等级与第一角色隔离")
	_expect(second_player.get_stardust_fragments() == 0, "第二角色材料与第一角色隔离")
	_expect(second_player.get_profession_id() == &"star_seeker", "第二角色保持永久职业")
	_expect(not second_player.can_equip(DefinitionRegistry.get_equipment(&"traveler_sword")), "观星者不能装备剑")
	session.unbind_level(second_level)
	second_player.queue_free()
	second_level.queue_free()
	await process_frame

	_expect(session.continue_character(0).ok, "再次读取第一角色")
	var reloaded_player := player_scene.instantiate() as Player
	root.add_child(reloaded_player)
	await process_frame
	var reloaded_level := TestLevelStub.new()
	root.add_child(reloaded_level)
	_expect(session.bind_level(reloaded_level, reloaded_player).ok, "再次应用第一角色")
	_expect(reloaded_player.get_level() == first_level_after_save, "等级完成 JSON 往返")
	_expect(reloaded_player.get_stardust_fragments() == 7, "材料完成 JSON 往返")
	_expect(reloaded_player.get_equipment_count(staff) == 2, "装备背包完成 JSON 往返")
	session.unbind_level(reloaded_level)
	reloaded_player.queue_free()
	reloaded_level.queue_free()
	await process_frame

	_expect(not session.delete_character(1, "错误名字").ok, "错误确认名不能删除")
	_expect(session.delete_character(1, "星月").ok, "正确确认名删除角色")
	_expect(String(session.get_slot(1).profile_id).is_empty(), "删除后恢复空栏位")
	_expect(not String(session.get_slot(0).profile_id).is_empty(), "删除不影响相邻角色")

	var profile_path := "%s/%s.json" % [TEST_ROOT, String(first.profile_id)]
	var backup_path := "%s/backups/%s.json" % [TEST_ROOT, String(first.profile_id)]
	_expect(FileAccess.file_exists(backup_path), "保存时保留最近可用备份")
	var corrupt := FileAccess.open(profile_path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var recovery: Dictionary = session.continue_character(0)
	_expect(recovery.ok, "主档损坏时从备份恢复")
	_expect(String(recovery.message).contains("备份"), "备份恢复提供明确消息")

	var newer := FileAccess.open(profile_path, FileAccess.WRITE)
	newer.store_string(JSON.stringify({"version": 999, "profile_id": String(first.profile_id), "slot": 0, "name": "小明", "profession_id": "traveler"}))
	newer.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	_expect(not session.continue_character(0).ok, "拒绝无法迁移的未来版本")

	_clean_test_root()
	if _failures.is_empty():
		print("Issue #1 tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


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


class TestLevelStub:
	extends Node

	func get_area_id() -> StringName:
		return &"test_level"

	func get_safe_spawn_position(spawn_id: StringName) -> Vector2:
		return Vector2(80.0, 550.0) if spawn_id == &"start" else Vector2.INF

	func is_combat_active() -> bool:
		return false
