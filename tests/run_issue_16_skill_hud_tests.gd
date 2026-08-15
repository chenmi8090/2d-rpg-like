extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_skill_hud()
	if _failures.is_empty():
		print("Issue #16 skill HUD tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_skill_hud() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	root.add_child(level)
	await process_frame
	var player := level.get_node("Player") as Player
	var hud := level.get_node("Interface/SkillQuickbarHUD") as Control
	_expect(level.get_node_or_null("Interface/Controls") == null, "顶部常驻完整快捷键说明已移除")
	_expect(hud != null and hud.position.y <= 10.0, "技能 HUD 位于画面顶部")
	_expect(level._skill_hud_slots.size() == 10, "战斗 HUD 固定提供十个主动技能槽位")
	_expect(
		level._skill_quickbar_rows[0].get_child_count() == 5
		and level._skill_quickbar_rows[1].get_child_count() == 5,
		"快捷栏按每排五槽分为两排"
	)
	_expect(
		level._skill_hud_slots[0].key_label.text == "1"
		and level._skill_hud_slots[4].key_label.text == "5"
		and level._skill_hud_slots[5].key_label.text == "6"
		and level._skill_hud_slots[9].key_label.text == "0",
		"两排快捷键依次显示 1 至 5 与 6 至 0"
	)
	level._update_skill_quickbar_hud()
	_expect(level._skill_hud_names[0].text == "空", "空槽使用紧凑键帽文字")
	_expect(level._skill_hud_statuses[1].text == "未配置", "第二个空槽显示未配置状态")

	var profile := player.get_save_snapshot()
	profile["profession_id"] = "traveler"
	profile["progression"] = {"level": 5, "experience": 0}
	profile["skills"] = {
		"unspent_points": 0,
		"ranks": {
			"blade_wave": 3,
			"power_strike": 1,
		},
	}
	profile["skill_quickbar"] = {"slots": ["blade_wave", "power_strike"]}
	_expect(player.apply_save_snapshot(profile).ok, "HUD 测试载入两个有效主动技能")
	level._update_skill_quickbar_hud()
	_expect(level._skill_hud_names[0].text == "剑气斩", "槽位 1 显示已配置技能名称")
	_expect(level._skill_hud_names[1].text == "破阵重击", "槽位 2 显示已配置技能名称")
	_expect(level._skill_hud_statuses[0].text == "可用", "满足条件的技能显示可用")
	_expect(player.set_skill_quickbar_slot(4, &"blade_wave").ok, "同一技能可以重新绑定到新槽位")
	_expect(
		player.get_skill_quickbar()[0] == &""
		and player.get_skill_quickbar()[4] == &"blade_wave",
		"重新绑定技能时自动清除旧槽位"
	)
	_expect(player.set_skill_quickbar_slot(0, &"blade_wave").ok, "唯一绑定测试后移回第一槽")
	_expect(player.move_skill_quickbar_slot(0, 2).ok, "快捷栏槽位支持栏内交换")
	_expect(
		player.get_skill_quickbar()[0] == &""
		and player.get_skill_quickbar()[2] == &"blade_wave",
		"拖动到空槽会移动技能"
	)
	_expect(player.move_skill_quickbar_slot(2, 1).ok, "快捷栏可与已占用槽位交换")
	_expect(
		player.get_skill_quickbar()[1] == &"blade_wave"
		and player.get_skill_quickbar()[2] == &"power_strike",
		"目标有技能时交换两个槽位"
	)
	_expect(player.move_skill_quickbar_slot(1, 0).ok, "测试技能移回第一槽")

	player._skill_cooldowns[&"blade_wave"] = player._elapsed_time + 1.25
	level._update_skill_quickbar_hud()
	_expect(level._skill_hud_statuses[0].text.begins_with("冷却"), "冷却技能显示剩余秒数")
	var cooldown_style := level._skill_hud_slots[0].get_theme_stylebox("panel") as StyleBoxFlat
	_expect(cooldown_style != null and cooldown_style.bg_color == Color("252b34ee"), "冷却槽位使用灰暗状态")
	player._elapsed_time += 1.3
	level._update_skill_quickbar_hud()
	_expect(level._skill_hud_statuses[0].text == "可用", "冷却结束后槽位恢复可用")

	var staff := DefinitionRegistry.get_equipment(&"star_staff")
	_expect(player.equip_item(staff), "HUD 测试可以切换为法杖")
	level._update_skill_quickbar_hud()
	_expect(level._skill_hud_statuses[0].text == "武器不符", "武器条件不满足时显示不可用原因")
	var unavailable_style := level._skill_hud_slots[0].get_theme_stylebox("panel") as StyleBoxFlat
	_expect(unavailable_style != null and unavailable_style.bg_color == Color("33252aee"), "不可用槽位具有明确颜色状态")

	_expect(player.set_skill_quickbar_slot(1, &"").ok, "可以清空第二个快捷栏槽位")
	_expect(level._skill_hud_names[1].text == "空", "快捷栏变化后 HUD 立即刷新")
	level._on_skill_quickbar_drop(3, {
		"kind": &"skill_quickbar",
		"skill_id": &"traveler_vitality",
		"source_slot": -1,
	})
	_expect(player.get_skill_quickbar()[3] == &"", "被动技能不能拖入快捷栏")
	level._on_skill_quickbar_clear(0)
	_expect(player.get_skill_quickbar()[0] == &"", "右键清空处理移除槽位技能")
	_expect(InputMap.has_action(&"skill_slot_10"), "数字键 0 对应第十个技能槽位")
	_expect(player.set_skill_quickbar_slot(0, &"blade_wave").ok, "重置测试所需第一槽技能")

	player._skill_cooldowns[&"blade_wave"] = player._elapsed_time + 10.0
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	level._update_skill_quickbar_hud()
	_expect(player.get_skill_cooldown_remaining(&"blade_wave") == 0.0, "手动重置清理技能冷却")
	_expect(not level._skill_hud_statuses[0].text.begins_with("冷却"), "重置后 HUD 不显示过期冷却")

	_expect(level.get_node_or_null("Interface/InteractionPrompt") != null, "动态交互提示继续保留")
	_expect(level.get_node_or_null("Interface/WorldStatus") != null, "世界状态动态提示继续保留")
	_expect(level.get_node_or_null("Interface/SessionPanel/SaveStatusText") != null, "保存状态动态提示继续保留")
	level.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
