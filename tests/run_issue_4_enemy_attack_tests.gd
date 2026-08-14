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
	await _test_grunt_attack_phases()
	await _test_definition_driven_windups()
	await _test_attack_interruptions()
	await _test_death_and_reset_cleanup()
	await _test_target_invalidation()
	await _test_local_aggro_reset()
	await _test_attack_cooldown()
	await _test_encounter_respawn_cleanup()
	_release_inputs()

	if _failures.is_empty():
		print("Issue #4 enemy attack tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_grunt_attack_phases() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	var phases: Array[int] = []
	var health_changes: Array[int] = []
	enemy.attack_phase_changed.connect(
		func(phase: int) -> void: phases.append(phase)
	)
	player.health_changed.connect(
		func(health: int, _maximum: int) -> void:
			health_changes.append(health)
	)

	_expect(
		await _wait_for_phase(
			enemy,
			GroundedEnemyController.AttackPhase.STARTUP
		),
		"巡逻敌人进入攻击时先进入前摇阶段"
	)
	var health_before := player.get_health()
	await _physics_frames(12)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.STARTUP,
		"巡逻敌人的配置前摇持续到生效边界"
	)
	_expect(
		player.get_health() == health_before and not enemy.is_attack_hitbox_active(),
		"前摇阶段没有伤害且攻击 Hitbox 保持关闭"
	)

	_expect(
		await _wait_for_phase(
			enemy,
			GroundedEnemyController.AttackPhase.ACTIVE
		),
		"前摇结束后进入攻击生效阶段"
	)
	_expect(enemy.is_attack_hitbox_active(), "生效阶段开启攻击 Hitbox")
	await _physics_frames(3)
	_expect(player.get_health() < health_before, "生效阶段能够命中范围内玩家")

	_expect(
		await _wait_for_phase(
			enemy,
			GroundedEnemyController.AttackPhase.RECOVERY
		),
		"生效结束后进入恢复阶段"
	)
	var recovery_health := player.get_health()
	_expect(not enemy.is_attack_hitbox_active(), "恢复阶段关闭攻击 Hitbox")
	await _physics_frames(8)
	_expect(
		player.get_health() == recovery_health,
		"恢复阶段不会产生额外伤害"
	)
	_expect(
		health_changes.size() == 1,
		"一次攻击激活对玩家最多造成一次伤害"
	)
	_expect(
		GroundedEnemyController.AttackPhase.ACTIVE in phases
		and GroundedEnemyController.AttackPhase.RECOVERY in phases,
		"攻击依次报告生效与恢复阶段"
	)
	await _destroy_world()


func _test_definition_driven_windups() -> void:
	var grunt_frames := await _measure_startup_frames(GRUNT_DEFINITION)
	var heavy_frames := await _measure_startup_frames(HEAVY_DEFINITION)
	_expect(grunt_frames > 0, "能够测量巡逻敌人的前摇时长")
	_expect(heavy_frames > 0, "能够测量重型守卫的前摇时长")
	_expect(
		heavy_frames >= grunt_frames + 12,
		"重型守卫使用比巡逻敌人明显更长的配置前摇"
	)


func _test_attack_interruptions() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	var health_before := player.get_health()
	_expect(enemy.receive_hit(1, player, -1.0), "低伤害命中可被敌人接受")
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.STARTUP
		and enemy.current_state == GroundedEnemyController.State.ATTACK,
		"低伤害不打断敌人前摇"
	)
	_expect(
		enemy.receive_hit(2, player, -1.0),
		"达到共享伤害比例阈值的命中可被敌人接受"
	)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"达到阈值的命中立即清理前摇和 Hitbox"
	)
	await _physics_frames(28)
	_expect(player.get_health() == health_before, "被击退中断的前摇不会留下延迟伤害")
	await _destroy_world()

	actors = await _create_combat_world(GRUNT_DEFINITION)
	player = actors.player as Player
	enemy = actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE)
	_expect(enemy.is_attack_hitbox_active(), "生效中断测试先开启 Hitbox")
	enemy.receive_hit(1, player, -1.0)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.ACTIVE
		and enemy.is_attack_hitbox_active(),
		"低伤害不关闭生效阶段 Hitbox"
	)
	enemy.receive_hit(1, player, -1.0, {"is_critical": true})
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"暴击产生击退并立即关闭生效阶段 Hitbox"
	)
	await _destroy_world()

	actors = await _create_combat_world(GRUNT_DEFINITION)
	player = actors.player as Player
	enemy = actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.RECOVERY)
	enemy.receive_hit(1, player, -1.0)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.RECOVERY,
		"低伤害不打断敌人恢复阶段"
	)
	enemy.receive_hit(
		1,
		player,
		-1.0,
		{"force_knockback": true, "minimum_knockback_speed": 80.0}
	)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active()
		and enemy.velocity.x <= -80.0,
		"强制击退清理恢复阶段并保证最小后退速度"
	)
	await _destroy_world()


func _test_death_and_reset_cleanup() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	enemy.receive_hit(999, player, -1.0)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"致命命中立即清理正在准备的攻击"
	)
	_expect(await _wait_for_state(enemy, GroundedEnemyController.State.DEAD), "敌人完成死亡流程")
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE,
		"死亡状态不保留攻击阶段"
	)
	await _destroy_world()

	actors = await _create_combat_world(GRUNT_DEFINITION)
	enemy = actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.ACTIVE)
	enemy.set_target(null)
	enemy.reset()
	_expect(enemy.current_state == GroundedEnemyController.State.IDLE, "重置后恢复空闲状态")
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"重置清理攻击阶段和 Hitbox"
	)
	await _physics_frames(2)
	await _destroy_world()


func _test_target_invalidation() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	player.queue_free()
	await process_frame
	await _physics_frames(2)
	_expect(enemy.current_state != GroundedEnemyController.State.ATTACK, "目标失效后敌人立即退出攻击状态")
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"目标失效会清理攻击提示和 Hitbox"
	)
	await _destroy_world()


func _test_local_aggro_reset() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var enemy := actors.enemy as GroundedEnemyController
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	enemy.global_position.x = 180.0
	var disengage_position := enemy.global_position
	enemy.reset_aggro_at_current_position()
	_expect(enemy.current_state == GroundedEnemyController.State.IDLE, "清除仇恨后敌人立即进入空闲状态")
	_expect(enemy.global_position.is_equal_approx(disengage_position), "清除仇恨不会把敌人传回原出生点")
	_expect(not enemy.is_engaged_with_target(), "清除仇恨后敌人不再追逐目标")
	_expect(not enemy.is_attack_hitbox_active(), "清除仇恨会关闭正在进行的攻击 Hitbox")
	await _physics_frames(4)
	_expect(absf(enemy.global_position.x - disengage_position.x) < 1.0, "丢失仇恨后敌人先在原地停留")
	await _destroy_world()


func _test_attack_cooldown() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	var startup_count := 0
	enemy.attack_phase_changed.connect(
		func(phase: int) -> void:
			if phase == GroundedEnemyController.AttackPhase.STARTUP:
				startup_count += 1
	)
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	startup_count = 1
	_expect(
		await _wait_for_phase(
			enemy,
			GroundedEnemyController.AttackPhase.NONE,
			90
		),
		"自然攻击在恢复结束后清理阶段"
	)
	var cooldown_position := enemy.global_position.x
	await _physics_frames(45)
	_expect(startup_count == 1, "自然攻击完成后的冷却阻止立即重复攻击")
	_expect(
		absf(enemy.global_position.x - cooldown_position) < 1.0
		and is_zero_approx(enemy.velocity.x)
		and enemy.global_position.x < player.global_position.x,
		"玩家仍在攻击范围内时敌人在冷却期间保持站位且不穿过玩家"
	)
	_expect(await _wait_for_startup_count(2, enemy, 80), "配置冷却结束后敌人可以再次攻击")
	await _destroy_world()


func _test_encounter_respawn_cleanup() -> void:
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
	_expect(await _wait_for_encounter_capacity(manager, 1), "测试遭遇生成一个真实地面敌人")
	var owned := manager.get_owned_enemies()
	var enemy := owned[0] if not owned.is_empty() else null
	if enemy == null:
		await _destroy_world()
		return
	await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP)
	enemy.receive_hit(999, player, -1.0)
	await _wait_for_state(enemy, GroundedEnemyController.State.DEAD)
	_expect(
		enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"遭遇中的敌人死亡时清理攻击状态"
	)
	_expect(await _wait_for_alive_count(manager, 0), "敌人死亡后进入遭遇重生等待")
	_expect(await _wait_for_alive_count(manager, 1, 90), "遭遇计时结束后重生同一敌人")
	_expect(
		enemy.visible
		and enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.NONE
		and not enemy.is_attack_hitbox_active(),
		"遭遇重生复用 reset 并清理旧攻击状态"
	)
	await _destroy_world()


func _measure_startup_frames(definition: EnemyDefinition) -> int:
	var actors := await _create_combat_world(definition)
	var enemy := actors.enemy as GroundedEnemyController
	if not await _wait_for_phase(enemy, GroundedEnemyController.AttackPhase.STARTUP):
		await _destroy_world()
		return -1
	var frames := 0
	while (
		frames < 120
		and enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.STARTUP
	):
		await physics_frame
		frames += 1
	var reached_active := enemy.get_attack_phase() == GroundedEnemyController.AttackPhase.ACTIVE
	await _destroy_world()
	return frames if reached_active else -1


func _create_combat_world(definition: EnemyDefinition) -> Dictionary:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	var enemy := ENEMY_SCENE.instantiate() as GroundedEnemyController
	enemy.definition = definition
	enemy.global_position = Vector2(0.0, FLOOR_Y)
	enemy.start_facing_direction = 1.0
	enemy.target_path = NodePath()
	enemy.set_target(player)
	_test_root.add_child(enemy)
	await _settle_player(player)
	await _wait_until_grounded(enemy)
	return {"player": player, "enemy": enemy}


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


func _wait_for_phase(
	enemy: GroundedEnemyController,
	phase: int,
	maximum_frames := 120
) -> bool:
	for _frame in maximum_frames:
		if enemy.get_attack_phase() == phase:
			return true
		await physics_frame
	_expect(false, "敌人在预期时间内进入攻击阶段 %d" % phase)
	return false


func _wait_for_state(
	enemy: GroundedEnemyController,
	state: int,
	maximum_frames := 120
) -> bool:
	for _frame in maximum_frames:
		if enemy.current_state == state:
			return true
		await physics_frame
	_expect(false, "敌人在预期时间内进入状态 %d" % state)
	return false


func _wait_for_startup_count(
	target_count: int,
	enemy: GroundedEnemyController,
	maximum_frames: int
) -> bool:
	var count := 0
	var was_startup := false
	for _frame in maximum_frames:
		var is_startup := (
			enemy.get_attack_phase()
			== GroundedEnemyController.AttackPhase.STARTUP
		)
		if is_startup and not was_startup:
			count += 1
			if count >= target_count - 1:
				return true
		was_startup = is_startup
		await physics_frame
	return false


func _wait_for_encounter_capacity(
	manager: EncounterManager,
	capacity: int,
	maximum_frames := 60
) -> bool:
	for _frame in maximum_frames:
		if manager.get_capacity() == capacity:
			return true
		await process_frame
	return false


func _wait_for_alive_count(
	manager: EncounterManager,
	count: int,
	maximum_frames := 60
) -> bool:
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
