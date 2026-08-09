extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/patrol_enemy.tscn")
const EQUIPMENT_PICKUP_SCENE := preload("res://scenes/items/equipment_pickup.tscn")
const GRUNT := preload("res://resources/enemies/patrol_grunt_definition.tres")
const HEAVY := preload("res://resources/enemies/heavy_guard_definition.tres")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_quality_rules_and_rolls()
	_test_backpack_grid_structure()
	_test_legacy_equipment_migration()
	await _test_individual_inventory_and_equipping()
	await _test_pickup_lifetime_and_collection()
	await _test_level_drop_boundaries_and_placement()
	await _test_enemy_drop_once_per_death()
	if _failures.is_empty():
		print("Issue #10 equipment loot tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_quality_rules_and_rolls() -> void:
	_expect(EquipmentQuality.ALL.size() == 3, "装备具有普通、优秀和稀有三个品质")
	var grunt_rule := GRUNT.equipment_drop_rules[0]
	var heavy_rule := HEAVY.equipment_drop_rules[0]
	_expect(heavy_rule.uncommon_weight > grunt_rule.uncommon_weight, "重型敌人具有更高优秀品质权重")
	_expect(heavy_rule.rare_weight > grunt_rule.rare_weight, "重型敌人具有更高稀有品质权重")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var definition := DefinitionRegistry.get_equipment(&"tempered_sword")
	for quality in EquipmentQuality.ALL:
		var item := EquipmentLootRoller.create_instance(definition, quality, "test_%s" % quality, rng)
		_expect(item.is_valid(), "每个品质都能生成有效装备实例")
		for modifier in item.get_modifiers():
			_expect(EquipmentLootRoller.is_valid_rolled_modifier(modifier), "随机属性均为允许的正向有界属性")
	_expect(EquipmentLootRoller.roll_quality(rng, 10.0, 0.0, 0.0) == EquipmentQuality.COMMON, "单一普通权重只生成普通品质")
	_expect(EquipmentLootRoller.roll_quality(rng, 0.0, 10.0, 0.0) == EquipmentQuality.UNCOMMON, "单一优秀权重只生成优秀品质")
	_expect(EquipmentLootRoller.roll_quality(rng, 0.0, 0.0, 10.0) == EquipmentQuality.RARE, "强制稀有权重只生成稀有品质")
	_expect(EquipmentLootRoller.roll_quality(rng, 0.0, 0.0, 0.0) == EquipmentQuality.COMMON, "全零品质权重安全回退普通品质")
	_expect(EquipmentLootRoller.roll_quality(rng, -1.0, -2.0, -3.0) == EquipmentQuality.COMMON, "负品质权重按零处理")
	var averages: Dictionary = {}
	for quality in EquipmentQuality.ALL:
		var values: Array[float] = []
		var total := 0.0
		for index in 64:
			var item := EquipmentLootRoller.create_instance(definition, quality, "sample_%s_%d" % [quality, index], rng)
			var rolled := item.get_modifiers()[0].flat_bonus
			values.append(rolled)
			total += rolled
		averages[quality] = total / float(values.size())
		var unique_values: Dictionary = {}
		for value in values:
			unique_values[value] = true
		_expect(unique_values.size() > 1, "同品质装备在固定样本内具有实际属性变化")
	_expect(float(averages[EquipmentQuality.RARE]) > float(averages[EquipmentQuality.UNCOMMON]), "稀有装备平均属性高于优秀装备")
	_expect(float(averages[EquipmentQuality.UNCOMMON]) > float(averages[EquipmentQuality.COMMON]), "优秀装备平均属性高于普通装备")
	var first := EquipmentLootRoller.create_instance(definition, EquipmentQuality.COMMON, "independent_a", rng)
	var second := EquipmentLootRoller.create_instance(definition, EquipmentQuality.COMMON, "independent_b", rng)
	var second_value := second.modifiers[0].flat_bonus
	first.modifiers[0].flat_bonus += 100.0
	_expect(is_equal_approx(second.modifiers[0].flat_bonus, second_value), "不同装备实例不共享可变属性资源")


func _test_backpack_grid_structure() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	var scroll := level.get_node("Interface/BackpackPanel/ItemScroll") as ScrollContainer
	var grid := level.get_node("Interface/BackpackPanel/ItemScroll/ItemList") as GridContainer
	_expect(scroll != null and grid != null, "背包使用垂直滚动容器和网格容器")
	_expect(grid.columns == 10, "背包网格每行固定十个装备格")
	_expect(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "背包禁用水平滚动")
	level.free()


func _test_legacy_equipment_migration() -> void:
	var session_script := load("res://scripts/services/game_session.gd") as GDScript
	var session := session_script.new() as Node
	var migrated: Dictionary = session._normalize_equipment({
		"equipped": {String(EquipmentSlot.WEAPON): "traveler_sword"},
		"inventory": [{"id": "star_staff", "count": 2}],
	}, &"traveler", 1)
	var instances := migrated.get("instances", []) as Array
	var inventory := migrated.get("inventory", []) as Array
	_expect(instances.size() == 3, "旧版计数装备迁移为独立装备实例")
	_expect(inventory.size() == 2 and inventory[0] != inventory[1], "旧版同模板装备生成不同实例 ID")
	_expect(int(migrated.get("next_instance_serial", 0)) == 4, "旧版装备迁移正确推进实例序号")
	session.free()


func _test_individual_inventory_and_equipping() -> void:
	var root_node := Node2D.new()
	root.add_child(root_node)
	var player := PLAYER_SCENE.instantiate() as Player
	root_node.add_child(player)
	await process_frame
	var definition := DefinitionRegistry.get_equipment(&"tempered_sword")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var common := EquipmentLootRoller.create_instance(definition, EquipmentQuality.COMMON, "loot_common", rng)
	var rare := EquipmentLootRoller.create_instance(definition, EquipmentQuality.RARE, "loot_rare", rng)
	_expect(player.collect_equipment(common), "玩家可以收集具体装备实例")
	_expect(player.collect_equipment(rare), "相同模板的不同实例可以分别收集")
	_expect(player.get_equipment_inventory().size() == 2, "相同装备模板不会合并为数量")
	_expect(common.quality != rare.quality and common.instance_id != rare.instance_id, "相同模板保留各自品质和实例 ID")
	_expect(not player.collect_equipment(rare), "相同实例不能重复收集")
	var previous := player.get_equipped_item(EquipmentSlot.WEAPON)
	_expect(player.equip_inventory_item(rare.instance_id), "可以装备精确选中的装备实例")
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON).instance_id == rare.instance_id, "装备栏保存选中的具体实例")
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON).quality == EquipmentQuality.RARE, "装备后保留选中实例品质")
	_expect(previous in player.get_equipment_inventory(), "被替换装备完整返回背包")
	var snapshot := player.get_save_snapshot()
	var restored := PLAYER_SCENE.instantiate() as Player
	root_node.add_child(restored)
	await process_frame
	var profile := snapshot.duplicate(true)
	profile["profession_id"] = String(player.get_profession_id())
	_expect(restored.apply_save_snapshot(profile).ok, "装备实例存档可以重新应用")
	var restored_rare := restored.get_equipped_item(EquipmentSlot.WEAPON)
	_expect(restored_rare != null and restored_rare.instance_id == rare.instance_id, "读档保留已装备实例 ID")
	_expect(restored_rare != null and restored_rare.quality == rare.quality, "读档保留已装备实例品质")
	_expect(restored_rare != null and restored_rare.to_snapshot() == rare.to_snapshot(), "读档完整保留已装备实例定义、品质和随机属性")
	var direct := EquipmentLootRoller.create_instance(definition, EquipmentQuality.UNCOMMON, "direct_equip", rng)
	var equipped_before_direct := player.get_equipped_item(EquipmentSlot.WEAPON)
	_expect(player.equip_item(direct), "兼容装备 API 可以直接装备具体实例")
	_expect(equipped_before_direct in player.get_equipment_inventory(), "兼容装备 API 将被替换的精确实例返回背包")
	_expect(direct not in player.get_equipment_inventory(), "直接装备的实例不会同时留在背包")
	var bow := player.create_template_equipment(DefinitionRegistry.get_equipment(&"hunter_bow"))
	player.collect_equipment(bow)
	_expect(not player.equip_inventory_item(bow.instance_id), "职业限制阻止装备不允许的武器")
	_expect(bow in player.get_equipment_inventory(), "无法装备的物品保留在背包")
	root_node.queue_free()
	await process_frame


func _test_pickup_lifetime_and_collection() -> void:
	var root_node := Node2D.new()
	root.add_child(root_node)
	var player := PLAYER_SCENE.instantiate() as Player
	root_node.add_child(player)
	player.global_position = Vector2.ZERO
	var pickup := EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	root_node.add_child(pickup)
	pickup.global_position = Vector2.ZERO
	pickup.pop_delay = 0.0
	pickup.lifetime = 1.0
	var item := player.create_template_equipment(DefinitionRegistry.get_equipment(&"star_staff"))
	pickup.initialize(item, Vector2.ZERO)
	await physics_frame
	await physics_frame
	_expect(player.has_equipment_instance(item.instance_id), "靠近装备掉落物后收集具体实例")
	_expect(not is_instance_valid(pickup) or pickup.is_queued_for_deletion(), "拾取后掉落节点正确清理")
	var duplicate_item := player.create_template_equipment(DefinitionRegistry.get_equipment(&"star_staff"))
	player.collect_equipment(duplicate_item)
	var rejected_pickup := EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	root_node.add_child(rejected_pickup)
	rejected_pickup.global_position = player.global_position
	rejected_pickup.pop_delay = 0.0
	rejected_pickup.initialize(duplicate_item, Vector2.ZERO)
	await physics_frame
	await physics_frame
	_expect(is_instance_valid(rejected_pickup) and not rejected_pickup.is_queued_for_deletion(), "收集失败时装备掉落物不会消失")
	_expect(rejected_pickup.visible, "收集失败后装备掉落物保持可见")
	var timeout_pickup := EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	root_node.add_child(timeout_pickup)
	timeout_pickup.global_position = Vector2(1000.0, 0.0)
	timeout_pickup.lifetime = 0.03
	timeout_pickup.initialize(player.create_template_equipment(DefinitionRegistry.get_equipment(&"iron_guard_coat")), Vector2.ZERO)
	await physics_frame
	await physics_frame
	await physics_frame
	_expect(not is_instance_valid(timeout_pickup) or timeout_pickup.is_queued_for_deletion(), "未拾取装备超过生命周期后自动清理")
	root_node.queue_free()
	await process_frame


func _test_level_drop_boundaries_and_placement() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	root.add_child(level)
	await process_frame
	var definition := DefinitionRegistry.get_equipment(&"tempered_sword")
	var rule := EquipmentDropRule.new()
	rule.equipment = definition
	rule.common_weight = 1.0
	rule.uncommon_weight = 0.0
	rule.rare_weight = 0.0
	rule.chance = 0.0
	_expect(level._roll_equipment_drop(rule) == null, "零概率装备规则必不生成掉落")
	rule.chance = 1.0
	var guaranteed := level._roll_equipment_drop(rule) as EquipmentInstance
	_expect(guaranteed != null and guaranteed.quality == EquipmentQuality.COMMON, "满概率装备规则必生成指定品质掉落")
	var platform_origin := Vector2(372.0, 554.0)
	var position := level._equipment_drop_position(platform_origin) as Vector2
	_expect(is_equal_approx(position.x, 394.0), "平台边缘掉落位置夹取到安全横向范围")
	_expect(is_equal_approx(position.y, 520.0), "平台掉落从可行走表面上方生成")
	var drops := level.get_node("Drops") as Node2D
	level._spawn_equipment_pickup(guaranteed, platform_origin, 0, 1)
	_expect(drops.get_child_count() == 1, "装备规则通过关卡链路生成实际拾取节点")
	var pickup := drops.get_child(0) as EquipmentPickup
	_expect(pickup != null and pickup.instance == guaranteed, "世界拾取节点保留生成的精确装备实例")
	var player := level.get_node("Player") as Player
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	await process_frame
	_expect(drops.get_child_count() == 0, "玩家手动重置会清理所有场上装备掉落")
	var seen_ids: Dictionary = {guaranteed.instance_id: true}
	for index in 24:
		var repeated := level._roll_equipment_drop(rule) as EquipmentInstance
		if repeated != null:
			seen_ids[repeated.instance_id] = true
			level._spawn_equipment_pickup(repeated, platform_origin, index, 24)
		level._clear_drops()
		await process_frame
		_expect(drops.get_child_count() == 0, "重复刷取清理后不累积掉落节点")
	_expect(seen_ids.size() == 25, "重复刷取为每件装备生成唯一实例 ID")
	level.queue_free()
	await process_frame


func _test_enemy_drop_once_per_death() -> void:
	_expect(not GRUNT.equipment_drop_rules.is_empty(), "普通敌人配置了装备掉落规则")
	_expect(not HEAVY.equipment_drop_rules.is_empty(), "重型敌人配置了装备掉落规则")
	var grunt_probability := _combined_drop_probability(GRUNT.equipment_drop_rules)
	var heavy_probability := _combined_drop_probability(HEAVY.equipment_drop_rules)
	_expect(heavy_probability > grunt_probability, "重型敌人的预期装备掉落概率高于普通敌人")
	var root_node := Node2D.new()
	root.add_child(root_node)
	var player := PLAYER_SCENE.instantiate() as Player
	root_node.add_child(player)
	var enemy := ENEMY_SCENE.instantiate() as GroundedEnemyController
	enemy.definition = GRUNT
	root_node.add_child(enemy)
	await process_frame
	var emission_count := [0]
	enemy.equipment_drop_requested.connect(func(_enemy: GroundedEnemyController, _rules: Array[EquipmentDropRule]) -> void: emission_count[0] += 1)
	_expect(enemy.receive_hit(1, player, -1.0), "敌人可以通过真实受击链路受到非致命伤害")
	await physics_frame
	_expect(emission_count[0] == 0, "非致命受击不会请求装备掉落")
	_expect(enemy.receive_hit(999, player, -1.0), "敌人可以通过真实受击链路受到致命伤害")
	_expect(await _wait_for_state(enemy, GroundedEnemyController.State.DEAD), "敌人完成真实死亡流程")
	_expect(emission_count[0] == 1, "同一次真实死亡只请求一次装备掉落")
	enemy._enter_dead()
	_expect(emission_count[0] == 1, "重复死亡通知不会重复请求装备掉落")
	enemy.reset()
	_expect(enemy.receive_hit(999, player, -1.0), "敌人重置后可再次受到致命伤害")
	_expect(await _wait_for_state(enemy, GroundedEnemyController.State.DEAD), "敌人重置后再次完成死亡流程")
	_expect(emission_count[0] == 2, "敌人重置后再次死亡会请求新一轮装备掉落")
	root_node.queue_free()
	await process_frame


func _wait_for_state(enemy: GroundedEnemyController, expected: GroundedEnemyController.State, frame_limit := 120) -> bool:
	for _frame in frame_limit:
		if enemy.current_state == expected:
			return true
		await physics_frame
	return enemy.current_state == expected


func _combined_drop_probability(rules: Array[EquipmentDropRule]) -> float:
	var miss_probability := 1.0
	for rule in rules:
		if rule != null:
			miss_probability *= 1.0 - clampf(rule.chance, 0.0, 1.0)
	return 1.0 - miss_probability


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
