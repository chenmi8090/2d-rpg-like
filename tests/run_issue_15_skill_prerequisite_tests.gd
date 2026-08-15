extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_registered_prerequisites()
	_test_invalid_prerequisites()
	_test_learning_and_rank_down_rules()
	_test_snapshot_compatibility()
	await _test_skill_window_layout()
	if _failures.is_empty():
		print("Issue #15 skill prerequisite tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_registered_prerequisites() -> void:
	var validation := DefinitionRegistry.validate_skills()
	_expect(bool(validation.get("ok", false)), "注册技能的前置关系完整有效")
	var power_strike := DefinitionRegistry.get_skill(&"power_strike")
	var meteor_burst := DefinitionRegistry.get_skill(&"meteor_burst")
	var traveler_vitality := DefinitionRegistry.get_skill(&"traveler_vitality")
	var astral_spirit := DefinitionRegistry.get_skill(&"astral_spirit")
	_expect(
		power_strike.prerequisite_skill_id == &"blade_wave"
		and power_strike.prerequisite_rank == 3,
		"破阵重击要求剑气斩 3 级"
	)
	_expect(
		meteor_burst.prerequisite_skill_id == &"star_bolt"
		and meteor_burst.prerequisite_rank == 3,
		"陨星爆裂要求星辉弹 3 级"
	)
	_expect(not traveler_vitality.has_prerequisite(), "旅途体魄保持独立被动")
	_expect(not astral_spirit.has_prerequisite(), "星灵感应保持独立被动")


func _test_invalid_prerequisites() -> void:
	var self_reference := _test_skill(&"self_reference", &"traveler")
	self_reference.prerequisite_skill_id = self_reference.id
	self_reference.prerequisite_rank = 1
	_expect(not self_reference.is_valid(), "技能不能把自己设为前置技能")
	var missing := _test_skill(&"missing_prerequisite", &"traveler")
	missing.prerequisite_skill_id = &"unknown_skill"
	missing.prerequisite_rank = 1
	_expect(
		not bool(DefinitionRegistry.validate_skill_prerequisite(missing).get("ok", false)),
		"不存在的前置技能不能通过校验"
	)
	var wrong_profession := _test_skill(&"wrong_profession_prerequisite", &"traveler")
	wrong_profession.prerequisite_skill_id = &"star_bolt"
	wrong_profession.prerequisite_rank = 1
	_expect(
		not bool(DefinitionRegistry.validate_skill_prerequisite(wrong_profession).get("ok", false)),
		"不能引用其他职业技能作为前置"
	)
	var excessive_rank := _test_skill(&"excessive_prerequisite_rank", &"traveler")
	excessive_rank.prerequisite_skill_id = &"blade_wave"
	excessive_rank.prerequisite_rank = 99
	_expect(
		not bool(DefinitionRegistry.validate_skill_prerequisite(excessive_rank).get("ok", false)),
		"前置等级不能超过基础技能上限"
	)


func _test_learning_and_rank_down_rules() -> void:
	var progress := PlayerSkillProgress.new()
	progress.initialize(10)
	var blocked := progress.increase_rank(&"power_strike", &"traveler", 5)
	_expect(not blocked.ok and String(blocked.message).contains("剑气斩"), "未学习基础技能时拒绝进阶技能")
	for expected_rank in range(1, 3):
		var result := progress.increase_rank(&"blade_wave", &"traveler", 5)
		_expect(result.ok and int(result.rank) == expected_rank, "剑气斩可以提升到前置等级之前")
	blocked = progress.increase_rank(&"power_strike", &"traveler", 5)
	_expect(not blocked.ok, "剑气斩 2 级仍不能学习破阵重击")
	_expect(progress.increase_rank(&"blade_wave", &"traveler", 5).ok, "剑气斩可以提升到 3 级")
	_expect(progress.increase_rank(&"power_strike", &"traveler", 5).ok, "满足前置后可以学习破阵重击")
	var points_before_blocked_down := progress.unspent_points
	blocked = progress.decrease_rank(&"blade_wave", &"traveler")
	_expect(not blocked.ok and String(blocked.message).contains("破阵重击"), "已学进阶技能时保护基础技能等级")
	_expect(progress.unspent_points == points_before_blocked_down, "失败的减点不会返还技能点")
	_expect(progress.decrease_rank(&"power_strike", &"traveler").ok, "进阶技能可以先降到零级")
	_expect(progress.decrease_rank(&"blade_wave", &"traveler").ok, "移除进阶技能后可以降低基础技能")

	var star_progress := PlayerSkillProgress.new()
	star_progress.initialize(4)
	for _rank in 3:
		_expect(star_progress.increase_rank(&"star_bolt", &"star_seeker", 5).ok, "星辉弹可以提升到 3 级")
	_expect(star_progress.increase_rank(&"meteor_burst", &"star_seeker", 5).ok, "观星者满足前置后可学习陨星爆裂")


func _test_snapshot_compatibility() -> void:
	var invalid := PlayerSkillProgress.new()
	invalid.load_snapshot({
		"unspent_points": 0,
		"ranks": {
			"blade_wave": 2,
			"power_strike": 2,
		},
	}, &"traveler")
	_expect(invalid.get_rank(&"blade_wave") == 2, "旧档保留有效基础技能等级")
	_expect(invalid.get_rank(&"power_strike") == 0, "旧档清理不满足前置的进阶技能")
	_expect(invalid.unspent_points == 2, "旧档清理进阶技能时返还全部投入点数")

	var valid := PlayerSkillProgress.new()
	valid.load_snapshot({
		"unspent_points": 1,
		"ranks": {
			"blade_wave": 3,
			"power_strike": 1,
		},
	}, &"traveler")
	_expect(valid.get_rank(&"power_strike") == 1, "满足前置的旧档进阶技能保持不变")
	_expect(valid.unspent_points == 1, "有效旧档不会重复返还技能点")


func _test_skill_window_layout() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	root.add_child(level)
	await process_frame
	var player := level.get_node("Player") as Player
	var profile := player.get_save_snapshot()
	profile["profession_id"] = "traveler"
	profile["progression"] = {"level": 5, "experience": 0}
	profile["skills"] = {"unspent_points": 4, "ranks": {}}
	profile["skill_quickbar"] = {"slots": ["", ""]}
	_expect(player.apply_save_snapshot(profile).ok, "界面测试载入确定的技能状态")
	level._update_skills_panel()
	_expect(
		level._profession_skills.map(func(definition: SkillDefinition) -> StringName: return definition.id)
		== [&"blade_wave", &"power_strike", &"traveler_vitality"],
		"技能窗口按基础主动、进阶主动、独立被动排序"
	)
	var power_row := level._skill_buttons_by_id.get(&"power_strike") as Button
	_expect(power_row != null and power_row.text.contains("└─"), "进阶技能使用轻量层级标记")
	_expect(power_row != null and power_row.text.contains("前置未满足"), "未满足前置时技能行给出状态")
	level._on_skill_pressed(&"power_strike")
	_expect(level._skills_detail_text.text.contains("剑气斩 Lv.3"), "详情区显示前置技能名称和等级")
	_expect(level._skills_detail_text.text.contains("未满足"), "详情区显示当前前置状态")
	_expect(level._skills_increase_button.disabled, "未满足前置时加号按钮禁用")
	_expect(
		level._skills_detail_text.position.y + level._skills_detail_text.size.y
		<= level._skills_increase_button.position.y,
		"技能详情与加减按钮不重叠"
	)
	for _rank in 3:
		_expect(player.increase_skill_rank(&"blade_wave").ok, "界面测试准备满足前置等级")
	level._on_skill_pressed(&"power_strike")
	_expect(level._skills_detail_text.text.contains("已满足"), "满足前置后详情状态立即刷新")
	_expect(not level._skills_increase_button.disabled, "满足前置后加号按钮启用")
	level.queue_free()
	await process_frame


func _test_skill(skill_id: StringName, profession_id: StringName) -> SkillDefinition:
	var definition := SkillDefinition.new()
	definition.id = skill_id
	definition.display_name = String(skill_id)
	definition.profession_ids = [profession_id]
	return definition


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
