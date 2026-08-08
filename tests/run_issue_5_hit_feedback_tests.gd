extends SceneTree

const GAME_SESSION_SCRIPT := preload("res://scripts/services/game_session.gd")
const GAMEPLAY_INPUT_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"interact_up",
	&"interact_down",
	&"jump",
	&"light_attack",
	&"heavy_attack",
	&"toggle_attributes",
	&"toggle_backpack",
	&"reset",
]
const SAVE_VERSION := 1
const DEFAULT_AREA_ID := &"test_level"
const DEFAULT_SPAWN_ID := &"start"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/patrol_enemy.tscn")
const STAR_STAFF := preload("res://resources/equipment/star_staff.tres")
const GRUNT_DEFINITION := preload("res://resources/enemies/patrol_grunt_definition.tres")
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0

class CombatTarget:
	extends Node2D

	var accepts_hits := true
	var hit_count := 0
	var last_source: Node
	var last_direction := 0.0

	func receive_hit(_amount: int, source: Node, hit_direction: float) -> bool:
		if not accepts_hits:
			return false
		hit_count += 1
		last_source = source
		last_direction = hit_direction
		return true


var _failures: Array[String] = []
var _test_root: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_game_session()
	await _test_sword_feedback_acceptance_and_rejection()
	await _test_light_heavy_feedback_differentiation()
	await _test_delayed_staff_projectile_feedback()
	await _test_rejected_then_accepted_projectile_feedback()
	await _test_player_hurt_feedback_acceptance_and_invulnerability_rejection()
	await _test_player_cleanup_on_death_respawn_and_save_snapshot()
	await _test_enemy_hurt_flash_expiry_death_reset_and_respawn_cleanup()
	_release_inputs()

	if _failures.is_empty():
		print("Issue #5 hit feedback tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_sword_feedback_acceptance_and_rejection() -> void:
	var player := await _create_grounded_player()
	var rejected := _add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0), false)
	Input.action_press(&"light_attack")
	await _physics_frames(18)
	Input.action_release(&"light_attack")
	_expect(rejected.hit_count == 0, "拒绝剑击的目标不会记录命中")
	_expect(not _player_attack_feedback_active(player), "被拒绝的剑击不会触发攻击反馈")
	await _destroy_world()

	player = await _create_grounded_player()
	var accepted := _add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	var confirmations := 0
	player.attack_hit_confirmed.connect(func(_type: int, _profile: StringName) -> void: confirmations += 1)
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON) != null, "玩家拥有测试近战武器")
	Input.action_press(&"light_attack")
	await _physics_frames(6)
	_expect(player.current_state == Player.State.ATTACK, "玩家进入轻剑攻击状态")
	var accepted_recorded := accepted.receive_hit(1, player, 1.0)
	_expect(accepted_recorded, "测试目标接受剑击")
	player.call("_on_attack_hit_confirmed", null, 1, player, 1.0)
	await process_frame
	Input.action_release(&"light_attack")
	_expect(accepted_recorded, "被接受的剑击目标确认接收命中")
	_expect(_player_attack_feedback_active(player), "被接受的剑击触发攻击闪光反馈")
	await _destroy_world()


func _test_light_heavy_feedback_differentiation() -> void:
	var player := await _create_grounded_player()
	_add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	Input.action_press(&"light_attack")
	await _physics_frames(6)
	player.call("_on_attack_hit_confirmed", null, 1, player, 1.0)
	Input.action_release(&"light_attack")
	var light_remaining := _player_attack_feedback_remaining(player)
	var light_intensity := _player_attack_feedback_intensity(player)
	await _destroy_world()

	player = await _create_grounded_player()
	_add_target(Vector2(65.0, PLAYER_FLOOR_POSITION_Y - 18.0))
	Input.action_press(&"heavy_attack")
	await _physics_frames(6)
	player.call("_on_attack_hit_confirmed", null, 1, player, 1.0)
	Input.action_release(&"heavy_attack")
	var heavy_remaining := _player_attack_feedback_remaining(player)
	var heavy_intensity := _player_attack_feedback_intensity(player)
	_expect(heavy_remaining > light_remaining, "重剑命中反馈持续时间长于轻剑")
	_expect(heavy_intensity > light_intensity, "重剑命中反馈强度高于轻剑")
	await _destroy_world()


func _test_delayed_staff_projectile_feedback() -> void:
	var player := await _create_grounded_player()
	_expect(player.equip_item(STAR_STAFF), "测试玩家可装备星辉法杖")
	var delayed_target := _add_target(Vector2(330.0, PLAYER_FLOOR_POSITION_Y - 30.0))
	Input.action_press(&"light_attack")
	await _physics_frames(28)
	Input.action_release(&"light_attack")
	_expect(player.current_state == Player.State.IDLE, "投射物命中前施法动作已经结束")
	_expect(not _player_attack_feedback_active(player), "投射物命中前不会提前显示命中反馈")
	_expect(delayed_target.receive_hit(1, player, 1.0), "延迟法杖投射物命中远处目标")
	player.call("_on_projectile_hit_confirmed", null, 1, player, 1.0, Player.AttackType.LIGHT, &"staff_light")
	_expect(_player_attack_feedback_active(player), "延迟投射物被接受后仍触发施法者反馈")
	await _destroy_world()


func _test_rejected_then_accepted_projectile_feedback() -> void:
	var player := await _create_grounded_player()
	player.equip_item(STAR_STAFF)
	var rejected := _add_target(Vector2(120.0, PLAYER_FLOOR_POSITION_Y - 30.0), false)
	var accepted := _add_target(Vector2(210.0, PLAYER_FLOOR_POSITION_Y - 30.0))
	Input.action_press(&"light_attack")
	await _physics_frames(24)
	Input.action_release(&"light_attack")
	_expect(not rejected.receive_hit(1, player, 1.0), "投射物经过拒绝目标时不会造成伤害")
	_expect(not _player_attack_feedback_active(player), "投射物被拒绝时不触发反馈")
	_expect(accepted.receive_hit(1, player, 1.0), "同一投射物穿过拒绝目标后命中接受目标")
	player.call("_on_projectile_hit_confirmed", null, 1, player, 1.0, Player.AttackType.LIGHT, &"staff_light")
	_expect(accepted.hit_count == 1, "同一投射物穿过拒绝目标后命中接受目标")
	_expect(_player_attack_feedback_active(player), "投射物后续命中接受目标才触发反馈")
	await _destroy_world()


func _test_player_hurt_feedback_acceptance_and_invulnerability_rejection() -> void:
	var player := await _create_grounded_player()
	var health_before := player.get_health()
	_expect(player.receive_hit(1, player, -1.0), "玩家可接受首次受击")
	_expect(player.get_health() < health_before, "玩家首次受击扣除生命")
	_expect(player.is_hurt_feedback_active(), "玩家首次受击触发受伤反馈")
	var remaining_before_rejected := player.get_hurt_feedback_remaining()
	await process_frame
	_expect(not player.receive_hit(1, player, -1.0), "无敌期间拒绝后续受击")
	var remaining_after_rejected := player.get_hurt_feedback_remaining()
	_expect(remaining_after_rejected <= remaining_before_rejected, "无敌拒绝不会重启玩家受伤反馈计时")
	await _physics_frames(60)
	_expect(not player.is_hurt_feedback_active(), "玩家受伤反馈会自然结束")
	await _destroy_world()


func _test_player_cleanup_on_death_respawn_and_save_snapshot() -> void:
	var player := await _create_grounded_player()
	player.apply_safe_spawn(player.global_position)
	player.equip_item(STAR_STAFF)
	Input.action_press(&"light_attack")
	await _physics_frames(16)
	Input.action_release(&"light_attack")
	_expect(not _owned_projectiles(player).is_empty(), "死亡清理测试先生成投射物")
	player.receive_hit(999, player, -1.0)
	await process_frame
	_expect(player.current_state == Player.State.DEAD, "致命伤害使玩家进入死亡状态")
	_expect(_owned_projectiles(player).is_empty(), "玩家死亡清理已拥有投射物")
	_expect(not player.is_hurt_feedback_active(), "玩家死亡清理受伤反馈")
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	await _physics_frames(2)
	_expect(player.current_state == Player.State.IDLE, "手动复活恢复空闲状态")
	_expect(not player.is_hurt_feedback_active(), "手动复活后无受伤反馈残留")
	_expect(not _player_attack_feedback_active(player), "手动复活后无攻击反馈残留")
	_expect(_owned_projectiles(player).is_empty(), "手动复活后无投射物残留")

	Input.action_press(&"light_attack")
	await _physics_frames(16)
	Input.action_release(&"light_attack")
	_expect(not _owned_projectiles(player).is_empty(), "存档快照清理测试先生成投射物")
	player.receive_hit(1, player, -1.0)
	_expect(player.is_hurt_feedback_active(), "存档快照清理测试先触发受伤反馈")
	var result := player.apply_save_snapshot(_test_profile())
	await process_frame
	_expect(bool(result.ok), "测试存档快照可应用")
	_expect(player.current_state == Player.State.IDLE, "应用存档快照恢复空闲状态")
	_expect(not player.is_hurt_feedback_active(), "应用存档快照清理受伤反馈")
	_expect(not _player_attack_feedback_active(player), "应用存档快照清理攻击反馈")
	_expect(_owned_projectiles(player).is_empty(), "应用存档快照清理投射物")
	await _destroy_world()


func _test_enemy_hurt_flash_expiry_death_reset_and_respawn_cleanup() -> void:
	var actors := await _create_combat_world()
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	enemy.receive_hit(1, player, -1.0)
	_expect(enemy.is_hurt_feedback_active(), "敌人受击后触发受伤闪光")
	await _physics_frames(24)
	_expect(not enemy.is_hurt_feedback_active(), "敌人受伤闪光会按配置自然结束")
	await _wait_for_state(enemy, GroundedEnemyController.State.CHASE)
	enemy.receive_hit(999, player, -1.0)
	_expect(enemy.is_hurt_feedback_active(), "致命命中先进入受击反馈")
	_expect(await _wait_for_state(enemy, GroundedEnemyController.State.DEAD), "敌人致命受击后进入死亡状态")
	_expect(not enemy.is_hurt_feedback_active(), "敌人死亡清理受伤闪光")
	enemy.reset()
	_expect(enemy.current_state == GroundedEnemyController.State.IDLE, "敌人 reset 恢复空闲状态")
	_expect(not enemy.is_hurt_feedback_active(), "敌人 reset 清理受伤闪光")
	await _destroy_world()

	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	player = _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
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
	_expect(await _wait_for_encounter_capacity(manager, 1), "测试遭遇生成真实敌人")
	var owned := manager.get_owned_enemies()
	enemy = owned[0] if not owned.is_empty() else null
	if enemy == null:
		await _destroy_world()
		return
	enemy.receive_hit(999, player, -1.0)
	_expect(await _wait_for_state(enemy, GroundedEnemyController.State.DEAD), "遭遇敌人可被击杀")
	_expect(not enemy.is_hurt_feedback_active(), "遭遇敌人死亡清理受伤闪光")
	_expect(await _wait_for_alive_count(manager, 0), "遭遇敌人死亡后进入重生等待")
	_expect(await _wait_for_alive_count(manager, 1, 90), "遭遇敌人按配置重生")
	_expect(enemy.visible, "遭遇敌人重生后可见")
	_expect(enemy.current_state != GroundedEnemyController.State.DEAD, "遭遇敌人重生后不再死亡")
	_expect(not enemy.is_hurt_feedback_active(), "遭遇敌人重生后无旧受伤闪光残留")
	await _destroy_world()


func _ensure_game_session() -> Node:
	var existing := root.get_node_or_null("GameSession")
	if existing != null:
		return existing
	var session := GAME_SESSION_SCRIPT.new()
	session.name = "GameSession"
	root.add_child(session)
	if session.has_method("_ready"):
		session.call("_ready")
	return session


func _game_session() -> Node:
	return root.get_node("GameSession")


func _create_grounded_player() -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(0.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	return player


func _create_combat_world() -> Dictionary:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	var enemy := ENEMY_SCENE.instantiate() as GroundedEnemyController
	enemy.definition = GRUNT_DEFINITION
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


func _add_target(position: Vector2, accepts_hits := true) -> CombatTarget:
	var target := CombatTarget.new()
	target.position = position
	target.accepts_hits = accepts_hits
	_test_root.add_child(target)
	var hurtbox := Hurtbox.new()
	hurtbox.collision_layer = 16
	hurtbox.collision_mask = 8
	target.add_child(hurtbox)
	hurtbox.owner = target
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(24.0, 48.0)
	collision.shape = shape
	hurtbox.add_child(collision)
	collision.owner = target
	return target


func _owned_projectiles(player: Player) -> Array[PlayerAttackProjectile]:
	var result: Array[PlayerAttackProjectile] = []
	for node in get_nodes_in_group("player_attack_projectile"):
		if node is PlayerAttackProjectile and (node as PlayerAttackProjectile).get_source() == player:
			result.append(node as PlayerAttackProjectile)
	return result


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


func _wait_for_state(enemy: GroundedEnemyController, state: int, maximum_frames := 120) -> bool:
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


func _process_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _destroy_world() -> void:
	_release_inputs()
	if _test_root != null and is_instance_valid(_test_root):
		_test_root.queue_free()
	await process_frame
	_test_root = null


func _release_inputs() -> void:
	for action in GAMEPLAY_INPUT_ACTIONS:
		Input.action_release(action)
	Input.flush_buffered_events()


func _player_attack_feedback_active(player: Player) -> bool:
	var visual := player.get_node_or_null("Visual")
	return visual != null and float(visual.get("_attack_hit_feedback_timer")) > 0.0


func _player_attack_feedback_remaining(player: Player) -> float:
	var visual := player.get_node_or_null("Visual")
	return float(visual.get("_attack_hit_feedback_timer")) if visual != null else 0.0


func _player_attack_feedback_intensity(player: Player) -> float:
	var visual := player.get_node_or_null("Visual")
	return float(visual.get("_attack_hit_feedback_intensity")) if visual != null and _player_attack_feedback_active(player) else 0.0


func _test_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"profile_id": "issue_5_feedback_test",
		"slot": 0,
		"name": "反馈测试",
		"profession_id": "traveler",
		"created_at": 0,
		"updated_at": 0,
		"play_time_seconds": 0,
		"progression": {"level": 1, "experience": 0},
		"materials": {"stardust_fragment": 0},
		"equipment": {"equipped": {"weapon": "traveler_sword"}, "inventory": []},
		"location": {"area_id": String(DEFAULT_AREA_ID), "safe_spawn_id": String(DEFAULT_SPAWN_ID)},
		"meta": {},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
