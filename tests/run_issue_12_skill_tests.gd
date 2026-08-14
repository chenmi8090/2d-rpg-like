extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PROJECTILE_SCENE := preload("res://scenes/combat/player_attack_projectile.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_skill_definitions()
	_test_skill_progress_rules()
	await _test_player_progression_and_passives()
	await _test_active_skill_runtime()
	await _test_skill_window_ui()
	if _failures.is_empty():
		print("Issue #12 skill tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_skill_definitions() -> void:
	var seen: Dictionary = {}
	for definition in DefinitionRegistry.get_skills():
		_expect(definition != null and definition.is_valid(), "注册的技能定义必须有效")
		if definition == null:
			continue
		_expect(not seen.has(definition.id), "技能稳定 ID 不重复：%s" % definition.id)
		seen[definition.id] = true
		_expect(
			definition.get_maximum_rank() == SkillCategory.maximum_rank(definition.category),
			"技能上限由类别统一决定：%s" % definition.id
		)
		for profession_id in definition.profession_ids:
			var profession := DefinitionRegistry.get_profession(profession_id)
			_expect(
				profession != null and definition.id in profession.skill_ids,
				"技能和职业目录双向一致：%s" % definition.id
			)
	for profession in DefinitionRegistry.get_professions():
		for skill_id in profession.skill_ids:
			var definition := DefinitionRegistry.get_skill(skill_id)
			_expect(
				definition != null and profession.id in definition.profession_ids,
				"职业目录只引用所属技能：%s" % skill_id
			)
	_expect(SkillCategory.maximum_rank(SkillCategory.NORMAL_OFFENSIVE) == 5, "普通攻击技能单技能上限为 5")
	_expect(SkillCategory.maximum_rank(SkillCategory.OFFENSIVE_ULTIMATE) == 3, "攻击大招单技能上限为 3")
	_expect(SkillCategory.maximum_rank(SkillCategory.BASIC_STAT_PASSIVE) == 10, "基础属性被动单技能上限为 10")
	var invalid_passive := SkillDefinition.new()
	invalid_passive.id = &"invalid_passive"
	invalid_passive.display_name = "无效被动"
	invalid_passive.kind = SkillDefinition.Kind.PASSIVE
	invalid_passive.category = SkillCategory.BASIC_STAT_PASSIVE
	invalid_passive.profession_ids = [&"traveler"]
	invalid_passive.passive_stat_key = &"unsupported_stat"
	invalid_passive.passive_flat_bonus_per_rank = 1.0
	_expect(not invalid_passive.is_valid(), "被动技能只能修改受支持的角色属性")
	invalid_passive.passive_stat_key = PlayerStats.MAX_HEALTH
	invalid_passive.passive_flat_bonus_per_rank = 0.0
	_expect(not invalid_passive.is_valid(), "零效果被动技能定义无效")
	var invalid_projectile := SkillDefinition.new()
	invalid_projectile.id = &"invalid_projectile"
	invalid_projectile.display_name = "无效投射物"
	invalid_projectile.profession_ids = [&"traveler"]
	invalid_projectile.delivery = SkillDefinition.Delivery.PROJECTILE
	invalid_projectile.projectile_size = Vector2.ZERO
	_expect(not invalid_projectile.is_valid(), "投射物技能必须具有有效尺寸")
	var invalid_knockback := SkillDefinition.new()
	invalid_knockback.id = &"invalid_knockback"
	invalid_knockback.display_name = "无效击退"
	invalid_knockback.profession_ids = [&"traveler"]
	invalid_knockback.force_knockback = true
	invalid_knockback.minimum_knockback_speed = 0.0
	_expect(not invalid_knockback.is_valid(), "强制击退技能必须提供正数最小速度")


func _test_skill_progress_rules() -> void:
	var progress := PlayerSkillProgress.new()
	progress.initialize(0)
	_expect(not progress.get_rank_up_status(&"blade_wave", &"traveler", 1).ok, "角色等级不足时不能加点")
	_expect(not progress.get_rank_up_status(&"blade_wave", &"traveler", 2).ok, "零技能点时不能加点")
	progress.add_points(20)
	_expect(not progress.increase_rank(&"star_bolt", &"traveler", 20).ok, "不能学习其他职业技能")
	for expected_rank in range(1, 6):
		var result := progress.increase_rank(&"blade_wave", &"traveler", 20)
		_expect(result.ok and int(result.rank) == expected_rank, "普通攻击技能可以逐级提升到 5 级")
	_expect(not progress.increase_rank(&"blade_wave", &"traveler", 20).ok, "普通攻击技能不能超过 5 级")
	for expected_rank in range(1, 4):
		var result := progress.increase_rank(&"power_strike", &"traveler", 20)
		_expect(result.ok and int(result.rank) == expected_rank, "攻击大招可以逐级提升到 3 级")
	_expect(not progress.increase_rank(&"power_strike", &"traveler", 20).ok, "攻击大招不能超过 3 级")
	for expected_rank in range(1, 11):
		var result := progress.increase_rank(&"traveler_vitality", &"traveler", 20)
		_expect(result.ok and int(result.rank) == expected_rank, "基础属性被动可以逐级提升到 10 级")
	_expect(not progress.increase_rank(&"traveler_vitality", &"traveler", 20).ok, "基础属性被动不能超过 10 级")
	var restored := PlayerSkillProgress.new()
	restored.load_snapshot({
		"unspent_points": -3,
		"ranks": {
			"blade_wave": 99,
			"power_strike": 99,
			"traveler_vitality": 99,
			"star_bolt": 4,
			"unknown": 7,
		},
	}, &"traveler")
	_expect(restored.unspent_points == 0, "载入时负技能点归零")
	_expect(restored.get_rank(&"blade_wave") == 5, "载入时普通技能等级夹到 5")
	_expect(restored.get_rank(&"power_strike") == 3, "载入时大招等级夹到 3")
	_expect(restored.get_rank(&"traveler_vitality") == 10, "载入时被动等级夹到 10")
	_expect(restored.get_rank(&"star_bolt") == 0, "载入时清除错误职业技能")


func _test_player_progression_and_passives() -> void:
	var container := Node2D.new()
	root.add_child(container)
	var player := PLAYER_SCENE.instantiate() as Player
	container.add_child(player)
	await process_frame
	_expect(player.get_skill_points() == 0, "新角色初始技能点为 0")
	_expect(player.get_skill_rank(&"blade_wave") == 0, "新角色所有技能从 0 级开始")
	var old_level := player.get_level()
	player.add_experience(player.get_experience_requirement())
	_expect(player.get_level() == old_level + 1, "达到升级经验后角色实际提升一级")
	_expect(player.get_skill_points() == 1, "每次真实升级获得 1 点技能点")
	var before_max := player.get_max_health()
	var before_health := player.get_health()
	var result := player.increase_skill_rank(&"traveler_vitality")
	_expect(result.ok, "达到要求后可消耗技能点学习被动")
	_expect(player.get_skill_points() == 0, "成功加点消耗 1 点技能点")
	_expect(player.get_max_health() == before_max + 8, "生命被动按等级提高最大生命")
	_expect(player.get_health() == before_health + 8, "最大生命提高时当前生命只增加一次")
	var profile := player.get_save_snapshot()
	profile["profession_id"] = String(player.get_profession_id())
	var health_after_passive := player.get_max_health()
	_expect(player.apply_save_snapshot(profile).ok, "技能进度快照可以重新应用")
	_expect(player.get_max_health() == health_after_passive, "重复读档重建被动不会叠加")
	_expect(player.get_skill_rank(&"traveler_vitality") == 1, "读档保留角色技能等级")
	container.queue_free()
	await process_frame


func _test_active_skill_runtime() -> void:
	var container := Node2D.new()
	root.add_child(container)
	var player := PLAYER_SCENE.instantiate() as Player
	container.add_child(player)
	await process_frame
	var profile := player.get_save_snapshot()
	profile["profession_id"] = String(player.get_profession_id())
	profile["progression"] = {"level": 5, "experience": 0}
	profile["skills"] = {
		"unspent_points": 0,
		"ranks": {
			"blade_wave": 2,
			"power_strike": 1,
			"traveler_vitality": 1,
		},
	}
	profile["skill_quickbar"] = {
		"slots": ["blade_wave", "power_strike", "", "blade_wave"],
	}
	_expect(player.apply_save_snapshot(profile).ok, "可载入已学习主动技能和快捷栏")
	_expect(player.get_skill_quickbar().size() == 4, "快捷栏槽位数量可以由存档扩展")
	_expect(not player.can_cast_skill(&"star_bolt").ok, "错误职业主动技能不能施放")
	player.current_state = Player.State.JUMP
	player.velocity.y = -1.0
	_expect(not player.can_cast_skill(&"power_strike").ok, "地面限定技能在空中不能施放")
	var cast_result := player.cast_skill(&"blade_wave")
	_expect(cast_result.ok, "已学习且允许空中使用的技能可以施放")
	_expect(player.current_state == Player.State.ATTACK, "主动技能复用统一攻击状态")
	_expect(player._current_attack_type == Player.AttackType.SKILL, "主动技能具有独立攻击类型")
	_expect(player._current_skill_rank == 2, "施放快照记录当前技能等级")
	var metadata := player._current_skill_metadata()
	_expect(metadata.get("skill_id") == &"blade_wave", "技能命中 metadata 使用稳定 skill_id")
	_expect(int(metadata.get("skill_rank", 0)) == 2, "技能命中 metadata 包含真实等级")
	_expect(player.get_skill_cooldown_remaining(&"blade_wave") > 0.0, "技能冷却按稳定技能 ID 启动")
	player._cancel_attack()
	_expect(not player.cast_skill(&"blade_wave").ok, "取消施放不能绕过已启动的冷却")
	var power_strike := DefinitionRegistry.get_skill(&"power_strike")
	player.current_state = Player.State.IDLE
	player._start_skill(power_strike)
	var forced_metadata := player._current_skill_metadata()
	_expect(bool(forced_metadata.get("force_knockback", false)), "强击退技能写入强制击退 metadata")
	_expect(float(forced_metadata.get("minimum_knockback_speed", 0.0)) == 150.0, "强击退技能写入最小击退速度")
	_expect(player._phase_for_skill_elapsed(0.0, power_strike) == Player.AttackPhase.STARTUP, "技能具有通用前摇阶段")
	_expect(player._phase_for_skill_elapsed(power_strike.startup_time, power_strike) == Player.AttackPhase.ACTIVE, "技能具有通用生效阶段")
	_expect(player._phase_for_skill_elapsed(power_strike.startup_time + power_strike.active_time, power_strike) == Player.AttackPhase.RECOVERY, "技能具有通用恢复阶段")
	player._cancel_attack()
	var projectile := PROJECTILE_SCENE.instantiate() as PlayerAttackProjectile
	container.add_child(projectile)
	await process_frame
	var blade_wave := DefinitionRegistry.get_skill(&"blade_wave")
	projectile.initialize_skill(blade_wave, 12, player, 1.0, {"skill_id": &"blade_wave"})
	_expect(is_equal_approx(projectile._speed, blade_wave.projectile_speed), "技能投射物读取技能速度")
	_expect(is_equal_approx(projectile._max_distance, blade_wave.projectile_maximum_distance), "技能投射物读取技能最大距离")
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	_expect(player.get_skill_cooldown_remaining(&"blade_wave") == 0.0, "复活或手动重置清除瞬时技能冷却")
	container.queue_free()
	await process_frame


func _test_skill_window_ui() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	root.add_child(level)
	await process_frame
	var player := level.get_node("Player") as Player
	var profile := player.get_save_snapshot()
	profile["profession_id"] = "traveler"
	profile["progression"] = {"level": 5, "experience": 0}
	profile["skills"] = {
		"unspent_points": 2,
		"ranks": {},
	}
	profile["skill_quickbar"] = {"slots": ["", ""]}
	_expect(player.apply_save_snapshot(profile).ok, "技能窗口测试可以载入确定角色状态")
	level._update_skills_panel()
	var echoed_open := _key_event(KEY_P, true)
	level._unhandled_input(echoed_open)
	_expect(not level._skills_panel.visible, "键盘 echo 不会重复打开技能窗口")
	level._unhandled_input(_key_event(KEY_P))
	_expect(level._skills_panel.visible, "P 键打开技能窗口")
	_expect(not level._backpack_panel.visible and not level._attributes_panel.visible, "技能窗口与其他窗口互斥")
	_expect(player.is_gameplay_input_blocked(), "技能窗口打开时阻止玩家游戏输入")
	_expect(level._skills_list.get_child_count() == player.get_profession_skills().size(), "技能窗口显示当前职业全部技能")
	_expect(level._selected_skill_id == &"blade_wave", "技能窗口默认选择稳定技能 ID")
	_expect(level._skills_detail_text.text.contains("剑气斩"), "技能窗口显示选中技能详情")
	var points_before := player.get_skill_points()
	level._unhandled_input(_key_event(KEY_J, true))
	_expect(player.get_skill_rank(&"blade_wave") == 0 and player.get_skill_points() == points_before, "加点按键 echo 不改变角色技能状态")
	level._unhandled_input(_key_event(KEY_J))
	_expect(player.get_skill_rank(&"blade_wave") == 1, "J 键通过权威接口学习选中技能")
	_expect(player.get_skill_points() == points_before - 1, "成功学习技能消耗一点技能点")
	_expect(level._selected_skill_id == &"blade_wave", "技能窗口刷新后保持稳定选择")
	level._unhandled_input(_key_event(KEY_1, true))
	_expect(player.get_skill_quickbar()[0] == &"", "快捷栏按键 echo 不改变配置")
	level._unhandled_input(_key_event(KEY_1))
	_expect(player.get_skill_quickbar()[0] == &"blade_wave", "数字键将已学习主动技能配置到快捷栏")
	_expect(level._skills_quickbar_text.text.contains("剑气斩"), "快捷栏文本立即刷新")
	level._unhandled_input(_key_event(KEY_I))
	_expect(level._backpack_panel.visible and not level._skills_panel.visible, "I 键从技能窗口切换到背包")
	_expect(player.is_gameplay_input_blocked(), "窗口切换期间持续阻止游戏输入")
	level._unhandled_input(_key_event(KEY_E))
	_expect(level._attributes_panel.visible and not level._backpack_panel.visible, "E 键从背包切换到角色信息")
	level._unhandled_input(_key_event(KEY_ESCAPE, true))
	_expect(level._attributes_panel.visible, "Escape echo 不会关闭窗口")
	level._unhandled_input(_key_event(KEY_ESCAPE))
	_expect(not level._skills_panel.visible and not level._backpack_panel.visible and not level._attributes_panel.visible, "Escape 关闭最后一个窗口")
	_expect(not player.is_gameplay_input_blocked() and not player._input_suppressed(), "关闭最后一个窗口后立即恢复游戏输入")
	level.queue_free()
	await process_frame


func _key_event(keycode: Key, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = echo
	return event


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
