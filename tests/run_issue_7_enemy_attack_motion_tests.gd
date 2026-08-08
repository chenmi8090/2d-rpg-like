extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/patrol_enemy.tscn")
const GRUNT_DEFINITION := preload("res://resources/enemies/patrol_grunt_definition.tres")
const HEAVY_DEFINITION := preload("res://resources/enemies/heavy_guard_definition.tres")
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0

var _failures: Array[String] = []
var _test_root: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_neutral_pose_and_natural_reset()
	await _test_continuous_phase_progress_and_retraction()
	await _test_left_right_mirroring_at_comparable_progress()
	await _test_heavy_motion_amplitude_and_timing()
	await _test_interruption_cleanup_all_phases()
	await _test_death_reset_target_and_respawn_cleanup()
	await _test_collision_geometry_unchanged_by_visual_motion()
	await _test_existing_hitbox_timing_and_damage()
	_release_inputs()

	if _failures.is_empty():
		print("Issue #7 enemy attack motion tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_neutral_pose_and_natural_reset() -> void:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var enemy := _spawn_enemy(GRUNT_DEFINITION, 1.0)
	await _wait_until_grounded(enemy)
	var neutral := enemy.get_attack_visual_pose()
	_expect(enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE, "敌人初始没有攻击阶段")
	_expect(float(neutral["phase_progress"]) == 0.0 and float(neutral["total_progress"]) == 0.0, "中立姿势报告零进度")
	_expect(float(neutral["amplitude"]) == 0.0, "中立姿势不带攻击幅度")
	_expect(_approximately_vec(neutral["body_offset"], Vector2.ZERO), "中立姿势身体没有攻击偏移")
	_expect(_approximately_vec(neutral["head_offset"], Vector2.ZERO), "中立姿势头部没有攻击偏移")
	_expect(float(neutral["arm_extension"]) == 0.0, "中立姿势手臂没有攻击伸展")
	_expect(float(neutral["tell_alpha"]) == 0.0 and float(neutral["motion_alpha"]) == 0.0, "中立姿势没有攻击提示或挥击残影")

	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	enemy.set_target(player)
	await _settle_player(player)
	_expect(await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP), "敌人进入攻击以验证自然回中")
	_expect(await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.NONE, 120), "自然攻击结束后清理攻击阶段")
	var reset_pose := enemy.get_attack_visual_pose()
	_expect(float(reset_pose["phase_progress"]) == 0.0 and float(reset_pose["total_progress"]) == 0.0, "自然攻击结束后进度回到零")
	_expect(float(reset_pose["amplitude"]) == 0.0 and float(reset_pose["arm_extension"]) == 0.0, "自然攻击结束后恢复中立攻击姿势")
	_expect(_approximately_vec(reset_pose["front_hand"], neutral["front_hand"]), "自然攻击结束后前手回到中立位置")
	await _destroy_world()


func _test_continuous_phase_progress_and_retraction() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var enemy := actors.enemy as GroundedEnemyController
	_expect(await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP), "连续进度测试进入前摇")
	var startup_a := enemy.get_attack_visual_pose()
	await _physics_frames(5)
	var startup_b := enemy.get_attack_visual_pose()
	_expect(enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.STARTUP, "前摇采样保持在前摇阶段")
	_expect(_progress_in_unit(startup_a) and _progress_in_unit(startup_b), "前摇姿势进度归一化在 0..1")
	_expect(float(startup_b["phase_progress"]) > float(startup_a["phase_progress"]), "前摇阶段进度连续递增")
	_expect(float(startup_b["total_progress"]) > float(startup_a["total_progress"]), "总攻击进度在前摇阶段递增")

	_expect(await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE), "连续进度测试进入生效")
	var active_a := enemy.get_attack_visual_pose()
	await _physics_frames(2)
	var active_b := enemy.get_attack_visual_pose()
	_expect(_progress_in_unit(active_a) and _progress_in_unit(active_b), "生效姿势进度归一化在 0..1")
	_expect(float(active_b["phase_progress"]) >= float(active_a["phase_progress"]), "生效阶段进度不倒退")
	_expect(float(active_b["total_progress"]) > float(active_a["total_progress"]), "总攻击进度在生效阶段递增")
	_expect(float(active_b["arm_extension"]) > float(startup_b["arm_extension"]), "生效阶段手臂伸展大于前摇")

	_expect(await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.RECOVERY), "连续进度测试进入恢复")
	var recovery_a := enemy.get_attack_visual_pose()
	await _physics_frames(8)
	var recovery_b := enemy.get_attack_visual_pose()
	_expect(_progress_in_unit(recovery_a) and _progress_in_unit(recovery_b), "恢复姿势进度归一化在 0..1")
	_expect(float(recovery_b["phase_progress"]) > float(recovery_a["phase_progress"]), "恢复阶段进度连续递增")
	_expect(float(recovery_b["arm_extension"]) < float(recovery_a["arm_extension"]), "恢复阶段手臂自然回收")
	_expect(_hand_forward_distance(recovery_b) < _hand_forward_distance(recovery_a), "恢复阶段拳头向中立位置回收")
	await _destroy_world()


func _test_left_right_mirroring_at_comparable_progress() -> void:
	var right_actors := await _create_combat_world(GRUNT_DEFINITION, 1.0, 48.0)
	var right_enemy := right_actors.enemy as GroundedEnemyController
	_expect(await _wait_for_phase(right_enemy, GroundedEnemyController.AttackPhase.ACTIVE), "右向敌人进入攻击生效")
	await _physics_frames(1)
	var right_pose := right_enemy.get_attack_visual_pose()
	await _destroy_world()

	var left_actors := await _create_combat_world(GRUNT_DEFINITION, -1.0, -48.0)
	var left_enemy := left_actors.enemy as GroundedEnemyController
	_expect(await _wait_for_phase(left_enemy, GroundedEnemyController.AttackPhase.ACTIVE), "左向敌人进入攻击生效")
	await _physics_frames(1)
	var left_pose := left_enemy.get_attack_visual_pose()
	await _destroy_world()

	_expect(float(right_pose["facing_direction"]) == 1.0 and float(left_pose["facing_direction"]) == -1.0, "左右测试采样到相反朝向")
	_expect(absf(float(right_pose["phase_progress"]) - float(left_pose["phase_progress"])) <= 0.08, "左右姿势在相近进度采样")
	_expect(_mirrors(right_pose["front_hand"], left_pose["front_hand"], 1.0), "前手位置左右镜像")
	_expect(_mirrors(right_pose["front_elbow"], left_pose["front_elbow"], 1.0), "前肘位置左右镜像")
	_expect(_mirrors(right_pose["body_offset"], left_pose["body_offset"], 1.0), "身体偏移左右镜像")
	_expect(absf(float(right_pose["arm_extension"]) - float(left_pose["arm_extension"])) <= 0.05, "左右手臂伸展幅度一致")


func _test_heavy_motion_amplitude_and_timing() -> void:
	var grunt := await _sample_first_active_pose(GRUNT_DEFINITION)
	var heavy := await _sample_first_active_pose(HEAVY_DEFINITION)
	_expect(float(heavy.pose["amplitude"]) > float(grunt.pose["amplitude"]), "重型守卫攻击动作幅度大于巡逻敌人")
	_expect(heavy.startup_frames >= grunt.startup_frames + 12, "重型守卫前摇时间长于巡逻敌人")
	_expect(heavy.total_frames > grunt.total_frames + 20, "重型守卫完整攻击时序长于巡逻敌人")


func _test_interruption_cleanup_all_phases() -> void:
	await _assert_interruption_cleans_pose(GroundedEnemyController.AttackPhase.STARTUP, "前摇")
	await _assert_interruption_cleans_pose(GroundedEnemyController.AttackPhase.ACTIVE, "生效")
	await _assert_interruption_cleans_pose(GroundedEnemyController.AttackPhase.RECOVERY, "恢复")


func _test_death_reset_target_and_respawn_cleanup() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	enemy.receive_hit(999, player, -1.0)
	_expect(await _wait_for_state(enemy, GroundedEnemyController.State.DEAD), "死亡清理测试进入死亡状态")
	_assert_neutral_clean(enemy.get_attack_visual_pose(), "死亡")
	await _destroy_world()

	actors = await _create_combat_world(GRUNT_DEFINITION)
	enemy = actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE)
	enemy.reset()
	_expect(enemy.current_state == GroundedEnemyController.State.IDLE, "reset 后回到空闲状态")
	_assert_neutral_clean(enemy.get_attack_visual_pose(), "reset")
	await _destroy_world()

	actors = await _create_combat_world(GRUNT_DEFINITION)
	player = actors.player as Player
	enemy = actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	player.queue_free()
	await process_frame
	await _physics_frames(2)
	_expect(enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE, "目标失效清理攻击阶段")
	_assert_neutral_clean(enemy.get_attack_visual_pose(), "目标失效")
	await _destroy_world()

	await _assert_encounter_respawn_pose_cleanup()


func _test_collision_geometry_unchanged_by_visual_motion() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var enemy := actors.enemy as GroundedEnemyController
	var baseline := enemy.get_attack_hitbox_geometry()
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	_assert_same_geometry(baseline, enemy.get_attack_hitbox_geometry(), "前摇")
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE)
	var active_geometry := enemy.get_attack_hitbox_geometry()
	_expect(bool(active_geometry["active"]), "生效阶段仍然开启真实攻击 Hitbox")
	_assert_same_geometry(baseline, active_geometry, "生效")
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.RECOVERY)
	_assert_same_geometry(baseline, enemy.get_attack_hitbox_geometry(), "恢复")
	await _destroy_world()


func _test_existing_hitbox_timing_and_damage() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	var health_before := player.get_health()
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	await _physics_frames(12)
	_expect(player.get_health() == health_before, "Issue #7 动作不改变前摇无伤害时机")
	_expect(not enemy.is_attack_hitbox_active(), "Issue #7 动作不提前开启攻击 Hitbox")
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE)
	_expect(enemy.is_attack_hitbox_active(), "Issue #7 动作保留生效阶段 Hitbox 开启")
	await _physics_frames(3)
	_expect(player.get_health() == health_before - GRUNT_DEFINITION.melee_attack.damage, "Issue #7 动作保留既有攻击伤害数值")
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.RECOVERY)
	var recovery_health := player.get_health()
	await _physics_frames(8)
	_expect(player.get_health() == recovery_health, "Issue #7 动作不在恢复阶段追加伤害")
	_expect(not enemy.is_attack_hitbox_active(), "Issue #7 动作保留恢复阶段 Hitbox 关闭")
	await _destroy_world()


func _assert_interruption_cleans_pose(phase: int, label: String) -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, phase)
	var pose_before := enemy.get_attack_visual_pose()
	_expect(float(pose_before["amplitude"]) > 0.0, "%s 阶段中断前有攻击动作" % label)
	enemy.receive_hit(1, player, -1.0)
	_expect(enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE, "%s 阶段受击清理攻击阶段" % label)
	_expect(not enemy.is_attack_hitbox_active(), "%s 阶段受击关闭攻击 Hitbox" % label)
	_assert_neutral_clean(enemy.get_attack_visual_pose(), "%s 阶段受击" % label)
	await _destroy_world()


func _assert_encounter_respawn_pose_cleanup() -> void:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	var enemies := Node2D.new()
	enemies.name = "Enemies"
	_test_root.add_child(enemies)
	var manager := EncounterManager.new()
	manager.name = "EncounterManager"
	manager.enemy_scene = ENEMY_SCENE
	manager.target_path = NodePath("../Player")
	manager.enemies_container_path = NodePath("../Enemies")
	var spawn := EnemySpawnDefinition.new()
	spawn.enemy_definition = GRUNT_DEFINITION
	spawn.local_position = Vector2(0.0, FLOOR_Y)
	spawn.facing_direction = 1.0
	spawn.respawn_delay = 0.08
	var group := EnemyGroupDefinition.new()
	group.spawns = [spawn]
	var encounter := EncounterDefinition.new()
	encounter.groups = [group]
	manager.encounter_definition = encounter
	_test_root.add_child(manager)

	await _settle_player(player)
	_expect(await _wait_for_encounter_capacity(manager, 1), "遭遇生成真实敌人用于重生动作清理测试")
	var owned := manager.get_owned_enemies()
	var enemy := owned[0] as GroundedEnemyController if not owned.is_empty() else null
	if enemy == null:
		await _destroy_world()
		return
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	enemy.receive_hit(999, player, -1.0)
	await _wait_for_state(enemy, GroundedEnemyController.State.DEAD)
	_assert_neutral_clean(enemy.get_attack_visual_pose(), "遭遇死亡")
	_expect(await _wait_for_alive_count(manager, 0), "遭遇敌人死亡后离开存活计数")
	_expect(await _wait_for_alive_count(manager, 1, 90), "遭遇敌人按配置重生")
	_assert_neutral_clean(enemy.get_attack_visual_pose(), "遭遇重生")
	await _destroy_world()


func _sample_first_active_pose(definition: EnemyDefinition) -> Dictionary:
	var actors := await _create_combat_world(definition)
	var enemy := actors.enemy as GroundedEnemyController
	var startup_frames := 0
	if not await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP):
		await _destroy_world()
		return {"pose": {}, "startup_frames": -1, "total_frames": -1}
	while startup_frames < 160 and enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.STARTUP:
		await physics_frame
		startup_frames += 1
	var pose := enemy.get_attack_visual_pose()
	var total_frames := startup_frames
	while total_frames < 260 and enemy.get_attack_phase() != GroundedEnemyController.AttackPhase.NONE:
		await physics_frame
		total_frames += 1
	await _destroy_world()
	return {"pose": pose, "startup_frames": startup_frames, "total_frames": total_frames}


func _create_combat_world(definition: EnemyDefinition, facing := 1.0, player_x := 48.0) -> Dictionary:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(player_x, PLAYER_FLOOR_POSITION_Y))
	var enemy := _spawn_enemy(definition, facing)
	enemy.set_target(player)
	await _settle_player(player)
	await _wait_until_grounded(enemy)
	return {"player": player, "enemy": enemy}


func _spawn_enemy(definition: EnemyDefinition, facing := 1.0) -> GroundedEnemyController:
	var enemy := ENEMY_SCENE.instantiate() as GroundedEnemyController
	enemy.definition = definition
	enemy.global_position = Vector2(0.0, FLOOR_Y)
	enemy.start_facing_direction = facing
	enemy.target_path = NodePath()
	_test_root.add_child(enemy)
	return enemy


func _create_world() -> void:
	_release_inputs()
	_test_root = Node2D.new()
	root.add_child(_test_root)


func _spawn_player(position: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player"
	_test_root.add_child(player)
	player.global_position = position
	return player


func _add_platform(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_test_root.add_child(body)
	return body


func _settle_player(player: Player) -> void:
	await _wait_until_grounded(player)
	await _physics_frames(2)


func _wait_until_grounded(body: CharacterBody2D, maximum_frames := 120) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if body.is_on_floor():
			return true
	_expect(false, "角色或敌人在预期时间内接触地面")
	return false


func _wait_for_phase(enemy: GroundedEnemyController, phase: int, maximum_frames := 140) -> bool:
	for _frame in maximum_frames:
		if enemy.get_attack_phase() == phase:
			return true
		await physics_frame
	_expect(false, "敌人在预期时间内进入攻击阶段 %d" % phase)
	return false


func _wait_for_state(enemy: GroundedEnemyController, state: int, maximum_frames := 140) -> bool:
	for _frame in maximum_frames:
		if enemy.current_state == state:
			return true
		await physics_frame
	_expect(false, "敌人在预期时间内进入状态 %d" % state)
	return false


func _wait_for_encounter_capacity(manager: EncounterManager, capacity: int, maximum_frames := 60) -> bool:
	for _frame in maximum_frames:
		if manager.get_capacity() == capacity:
			return true
		await process_frame
	return false


func _wait_for_alive_count(manager: EncounterManager, count: int, maximum_frames := 60) -> bool:
	for _frame in maximum_frames:
		if manager.get_alive_count() == count:
			return true
		await process_frame
	return false


func _physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


func _destroy_world() -> void:
	_release_inputs()
	if _test_root != null and is_instance_valid(_test_root):
		_test_root.queue_free()
	await process_frame
	_test_root = null


func _release_inputs() -> void:
	for action in GameSession.GAMEPLAY_INPUT_ACTIONS:
		Input.action_release(action)
	Input.flush_buffered_events()


func _progress_in_unit(pose: Dictionary) -> bool:
	return float(pose["phase_progress"]) >= 0.0 and float(pose["phase_progress"]) <= 1.0 and float(pose["total_progress"]) >= 0.0 and float(pose["total_progress"]) <= 1.0


func _hand_forward_distance(pose: Dictionary) -> float:
	return (pose["front_hand"] as Vector2).x * float(pose["facing_direction"])


func _approximately_vec(a: Variant, b: Vector2, epsilon := 0.02) -> bool:
	return (a as Vector2).distance_to(b) <= epsilon


func _mirrors(right: Variant, left: Variant, epsilon := 0.75) -> bool:
	var r := right as Vector2
	var l := left as Vector2
	return absf(r.x + l.x) <= epsilon and absf(r.y - l.y) <= epsilon


func _assert_neutral_clean(pose: Dictionary, context: String) -> void:
	_expect(float(pose["phase_progress"]) == 0.0 and float(pose["total_progress"]) == 0.0, "%s 后攻击进度归零" % context)
	_expect(float(pose["amplitude"]) == 0.0, "%s 后攻击幅度归零" % context)
	_expect(float(pose["arm_extension"]) == 0.0, "%s 后手臂伸展归零" % context)
	_expect(_approximately_vec(pose["body_offset"], Vector2.ZERO), "%s 后身体偏移清理" % context)
	_expect(_approximately_vec(pose["head_offset"], Vector2.ZERO), "%s 后头部偏移清理" % context)
	_expect(float(pose["tell_alpha"]) == 0.0 and float(pose["motion_alpha"]) == 0.0, "%s 后攻击提示透明度清理" % context)


func _assert_same_geometry(expected: Dictionary, actual: Dictionary, context: String) -> void:
	_expect(_approximately_vec(actual["position"], expected["position"], 0.01), "%s 阶段视觉动作不移动真实攻击 Hitbox" % context)
	_expect(_approximately_vec(actual["rectangle_size"], expected["rectangle_size"], 0.01), "%s 阶段视觉动作不改变真实攻击 Hitbox 尺寸" % context)
	_expect(float(actual["facing_direction"]) == float(expected["facing_direction"]), "%s 阶段视觉动作不改变真实攻击朝向几何" % context)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
