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
	var first_profile_path := "%s/%s.json" % [TEST_ROOT, String(first.profile_id)]
	var first_profile := _read_json_file(first_profile_path)
	_expect(int(first_profile.get("version", 0)) == 5, "新角色档案使用 v5 存档结构")
	var first_skills := first_profile.get("skills", {}) as Dictionary
	_expect(int(first_skills.get("unspent_points", -1)) == 0, "新角色技能点从零开始")
	_expect(
		first_skills.get("ranks", null) is Dictionary
		and (first_skills.get("ranks", {}) as Dictionary).is_empty(),
		"新角色所有技能等级从零开始"
	)
	var first_quickbar := first_profile.get("skill_quickbar", {}) as Dictionary
	_expect(
		first_quickbar.get("slots", []) is Array
		and (first_quickbar.get("slots", []) as Array) == ["", ""],
		"新角色创建独立主动技能快捷栏"
	)
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
	_expect(player.get_skill_points() == player.get_level() - 1, "真实升级按实际提升等级数授予技能点")
	var learned_result := player.increase_skill_rank(&"blade_wave")
	_expect(learned_result.ok, "第一角色可以消耗技能点学习所属主动技能")
	_expect(player.set_skill_quickbar_slot(0, &"blade_wave").ok, "已学习主动技能可以保存到快捷栏")
	player.collect_material(&"stardust_fragment", 7)
	var staff := DefinitionRegistry.get_equipment(&"star_staff")
	player.collect_equipment(player.create_template_equipment(staff))
	player.collect_equipment(player.create_template_equipment(staff))
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
	_expect(second_player.get_skill_points() == 0, "第二角色技能点与第一角色隔离")
	_expect(second_player.get_skill_rank(&"blade_wave") == 0, "第二角色不会继承第一角色技能等级")
	_expect(second_player.get_skill_quickbar() == [&"", &""], "第二角色不会继承第一角色技能快捷栏")
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
	_expect(reloaded_player.get_skill_rank(&"blade_wave") == 1, "技能等级完成 JSON 往返")
	_expect(reloaded_player.get_skill_quickbar()[0] == &"blade_wave", "技能快捷栏完成 JSON 往返")
	_expect(reloaded_player.get_skill_points() == first_level_after_save - 2, "未消耗技能点完成 JSON 往返")
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
	var recovered_profile := _read_json_file(backup_path)
	_expect((recovered_profile.get("skills", {}) as Dictionary).has("ranks"), "备份恢复保留技能进度子树")
	_expect((recovered_profile.get("skill_quickbar", {}) as Dictionary).has("slots"), "备份恢复保留技能快捷栏子树")

	var legacy_profile := {
		"version": 2,
		"profile_id": String(first.profile_id),
		"slot": 0,
		"name": "小明",
		"profession_id": "traveler",
		"progression": {"level": 20, "experience": 0},
		"materials": {},
		"equipment": {},
		"skills": {"unspent_points": 99, "ranks": {"blade_wave": 5}},
		"skill_quickbar": {"slots": ["blade_wave"]},
		"location": {},
	}
	var legacy_file := FileAccess.open(profile_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy_profile))
	legacy_file.close()
	var migrated: Dictionary = session.continue_character(0)
	_expect(migrated.ok, "v2 角色档案可以迁移到 v5")
	var migrated_player := player_scene.instantiate() as Player
	root.add_child(migrated_player)
	await process_frame
	var migrated_level := TestLevelStub.new()
	root.add_child(migrated_level)
	_expect(session.bind_level(migrated_level, migrated_player).ok, "迁移后的角色档案可以应用到玩家")
	_expect(migrated_player.get_level() == 20, "旧档迁移保留已有角色等级")
	_expect(migrated_player.get_skill_points() == 19, "旧档迁移按历史角色等级补发技能点")
	_expect(migrated_player.get_skill_rank(&"blade_wave") == 0, "旧档迁移不保留 v3 之前伪造的技能等级")
	_expect(migrated_player.get_skill_quickbar() == [&"", &""], "旧档迁移创建空主动技能快捷栏")
	_expect(session.save_now(&"migration_test").ok, "历史等级补点结果可以保存")
	session.unbind_level(migrated_level)
	migrated_player.queue_free()
	migrated_level.queue_free()
	await process_frame

	_expect(session.continue_character(0).ok, "历史等级补点后的档案可以再次读取")
	var migrated_reload_player := player_scene.instantiate() as Player
	root.add_child(migrated_reload_player)
	await process_frame
	var migrated_reload_level := TestLevelStub.new()
	root.add_child(migrated_reload_level)
	_expect(
		session.bind_level(migrated_reload_level, migrated_reload_player).ok,
		"历史等级补点后的档案可以再次应用"
	)
	_expect(
		migrated_reload_player.get_skill_points() == 19,
		"历史等级技能点只补发一次"
	)
	session.unbind_level(migrated_reload_level)
	migrated_reload_player.queue_free()
	migrated_reload_level.queue_free()
	await process_frame

	var v3_profile := legacy_profile.duplicate(true)
	v3_profile["version"] = 3
	v3_profile["skills"] = {
		"unspent_points": 2,
		"ranks": {
			"blade_wave": 2,
			"power_strike": 1,
		},
	}
	v3_profile["skill_quickbar"] = {"slots": ["blade_wave", "power_strike"]}
	var v3_file := FileAccess.open(profile_path, FileAccess.WRITE)
	v3_file.store_string(JSON.stringify(v3_profile))
	v3_file.close()
	_expect(session.continue_character(0).ok, "v3 技能档案可以迁移到 v5")
	var v3_player := player_scene.instantiate() as Player
	root.add_child(v3_player)
	await process_frame
	var v3_level := TestLevelStub.new()
	root.add_child(v3_level)
	_expect(session.bind_level(v3_level, v3_player).ok, "v3 技能档案可以应用到玩家")
	_expect(v3_player.get_skill_rank(&"blade_wave") == 2, "v3 迁移保留有效技能等级")
	_expect(v3_player.get_skill_rank(&"power_strike") == 1, "v3 迁移保留第二项有效技能等级")
	_expect(v3_player.get_skill_points() == 16, "v3 迁移只补足尚未计入的历史等级点数")
	_expect(
		v3_player.get_skill_quickbar() == [&"blade_wave", &"power_strike"],
		"v3 迁移保留有效主动技能快捷栏"
	)
	session.unbind_level(v3_level)
	v3_player.queue_free()
	v3_level.queue_free()
	await process_frame

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


class TestLevelStub:
	extends Node

	func get_area_id() -> StringName:
		return &"test_level"

	func get_safe_spawn_position(spawn_id: StringName) -> Vector2:
		return Vector2(80.0, 550.0) if spawn_id == &"start" else Vector2.INF

	func is_combat_active() -> bool:
		return false
