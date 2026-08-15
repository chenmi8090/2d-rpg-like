extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GRUNT := preload("res://resources/enemies/patrol_grunt_definition.tres")
const HEAVY := preload("res://resources/enemies/heavy_guard_definition.tres")

const EXPECTED := {
	&"test_level": [7, 3],
	&"field_passage_1": [4, 2],
	&"field_passage_2": [7, 1],
	&"field_passage_3": [2, 4],
}

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definitions()
	await _test_manager_lifecycle()
	if _failures.is_empty():
		print("Issue #14 map encounter tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_definitions() -> void:
	_expect(DefinitionRegistry.validate_world().ok, "地图遭遇定义必须完整有效")
	for map_id: StringName in EXPECTED:
		var definition := DefinitionRegistry.get_map(map_id)
		_expect(definition != null and definition.encounter_definition != null, "%s 明确配置遭遇" % map_id)
		if definition == null or definition.encounter_definition == null:
			continue
		var counts := _definition_counts(definition.encounter_definition)
		var expected: Array = EXPECTED[map_id]
		_expect(counts[0] == expected[0] and counts[1] == expected[1], "%s 使用预期怪物种类与数量" % map_id)
		_expect(_spawns_fit_layout(definition), "%s 的怪物出生点位于有效地面或平台" % map_id)
	_expect(not "respawn_delay" in EnemySpawnDefinition.new(), "出生点不再配置独立重生速度")


func _test_manager_lifecycle() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player"
	world.add_child(player)
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	world.add_child(enemies)
	var manager := EncounterManager.new()
	manager.enemy_scene = load("res://scenes/enemies/patrol_enemy.tscn") as PackedScene
	manager.target_path = NodePath("../Player")
	manager.enemies_container_path = NodePath("../Enemies")
	world.add_child(manager)
	await process_frame
	_expect(manager.respawn_interval == 8.0, "所有地图使用同一死亡后重生间隔")

	var passage_2 := DefinitionRegistry.get_map(&"field_passage_2")
	manager.load_encounter(passage_2.encounter_definition)
	_expect(_manager_counts(manager) == Vector2i(7, 1), "管理器建立通道-2怪物组合")
	var old_enemy: GroundedEnemyController = manager.get_owned_enemies()[0]
	manager.respawn_interval = 0.08
	manager._on_enemy_defeated(old_enemy, player)
	_expect(manager.get_respawn_remaining(old_enemy) > 0.0, "死亡怪物独立开始统一间隔倒计时")

	var passage_3 := DefinitionRegistry.get_map(&"field_passage_3")
	manager.load_encounter(passage_3.encounter_definition)
	_expect(not manager.owns_enemy(old_enemy), "替换遭遇立即移除旧怪物所有权")
	await create_timer(0.12).timeout
	_expect(_manager_counts(manager) == Vector2i(2, 4), "旧怪物不会延迟重生到新遭遇")

	for _cycle in 2:
		manager.load_encounter(passage_2.encounter_definition)
		_expect(manager.get_capacity() == 8, "重复切换只建立一套通道-2遭遇")
		manager.load_encounter(passage_3.encounter_definition)
		_expect(manager.get_capacity() == 6, "重复切换不会累计怪物")

	manager.clear_encounter()
	_expect(manager.get_capacity() == 0 and enemies.get_child_count() == 0, "清理遭遇会立即移除所有怪物")
	world.queue_free()
	await process_frame


func _definition_counts(encounter: EncounterDefinition) -> Vector2i:
	var counts := Vector2i.ZERO
	for group in encounter.groups:
		for spawn in group.spawns:
			if spawn.enemy_definition == GRUNT:
				counts.x += 1
			elif spawn.enemy_definition == HEAVY:
				counts.y += 1
	return counts


func _manager_counts(manager: EncounterManager) -> Vector2i:
	var counts := Vector2i.ZERO
	for enemy in manager.get_owned_enemies():
		if enemy.definition == GRUNT:
			counts.x += 1
		elif enemy.definition == HEAVY:
			counts.y += 1
	return counts


func _spawns_fit_layout(definition: MapDefinition) -> bool:
	var packed := load(definition.scene_path) as PackedScene
	var layout := packed.instantiate()
	var floor_y: float = layout.get_floor_center().y - layout.get_floor_size().y * 0.5
	var platforms: Array[Rect2] = layout.get_platform_rects()
	var valid := true
	for group in definition.encounter_definition.groups:
		for spawn in group.spawns:
			var on_surface := is_equal_approx(spawn.local_position.y, floor_y)
			for rect in platforms:
				if is_equal_approx(spawn.local_position.y, rect.position.y) and spawn.local_position.x >= rect.position.x + 24.0 and spawn.local_position.x <= rect.end.x - 24.0:
					on_surface = true
			valid = valid and on_surface
	layout.free()
	return valid


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
