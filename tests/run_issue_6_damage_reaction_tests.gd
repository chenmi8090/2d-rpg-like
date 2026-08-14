extends SceneTree

const GAME_SESSION_SCRIPT := preload("res://scripts/services/game_session.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/patrol_enemy.tscn")
const GRUNT_DEFINITION := preload("res://resources/enemies/patrol_grunt_definition.tres")
const HEAVY_GUARD_DEFINITION := preload("res://resources/enemies/heavy_guard_definition.tres")
const STAR_STAFF := preload("res://resources/equipment/star_staff.tres")
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0
const DAMAGE_SCALE := 20

class MetadataTarget:
	extends Node2D

	var received_metadata: Array[Dictionary] = []
	var accept_hits := true

	func receive_hit(_amount: int, _source: Node, _hit_direction: float, metadata: Dictionary = {}) -> bool:
		received_metadata.append(metadata.duplicate(true))
		return accept_hits


class LegacyTarget:
	extends Node2D

	var hit_count := 0

	func receive_hit(_amount: int, _source: Node, _hit_direction: float) -> bool:
		hit_count += 1
		return true


var _failures: Array[String] = []
var _test_root: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_ensure_game_session()
	await _test_low_damage_reaction_does_not_interrupt_or_knock_back()
	await _test_heavy_damage_reaction_has_capped_knockback_and_protection()
	await _test_forced_minimum_knockback_metadata()
	await _test_heavy_reaction_from_critical_metadata()
	await _test_airborne_and_sprint_context_thresholds()
	await _test_enemy_attack_metadata_real_ids_noncritical()
	await _test_player_outgoing_metadata_for_melee_and_projectile()
	await _test_hurtbox_metadata_compatibility()
	await _test_damage_reaction_cleanup_on_death_respawn_and_save_snapshot()
	_release_inputs()

	if _failures.is_empty():
		print("Issue #6 damage reaction tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_low_damage_reaction_does_not_interrupt_or_knock_back() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	_expect(player.current_state == Player.State.ATTACK, "普通伤害测试先开始玩家攻击")
	var health_before := player.get_health()
	_expect(player.receive_hit(1, player, 1.0), "普通伤害可被玩家接受")
	_expect(player.get_health() == health_before - 1, "普通伤害扣除生命")
	_expect(player.current_state == Player.State.ATTACK, "普通伤害不打断玩家正在进行的攻击")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "低伤害命中记录为普通反应")
	_expect(player.get_last_mitigated_hit_damage() == 1, "记录减免后的普通伤害")
	_expect(is_equal_approx(player.get_last_hit_damage_ratio(), 1.0 / float(player.get_max_health())), "记录普通伤害占最大生命比例")
	_expect(is_zero_approx(player.get_hit_stun_remaining()), "普通反应不启动受击硬直")
	_expect(is_zero_approx(player.velocity.x), "普通受击不施加水平击退")
	_expect(not player.is_heavy_reaction_protected(), "普通受击不启动重反应保护")
	await _destroy_world()


func _test_heavy_damage_reaction_has_capped_knockback_and_protection() -> void:
	var player := await _create_grounded_player()
	player.damage_knockback_speed = 640.0
	player.heavy_hit_knockback_cap = 180.0
	_expect(player.receive_hit(6, player, -1.0), "超过生命比例阈值的伤害可被玩家接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "超过生命比例阈值触发重受击")
	_expect(is_equal_approx(player.velocity.x, -180.0), "重受击水平击退受上限约束")
	_expect(player.get_hit_stun_remaining() > player.hit_stun_time, "重受击使用更长硬直")
	_expect(player.is_heavy_reaction_protected(), "重受击启动连续重反应保护")
	await _physics_frames(2)
	player.set("_invulnerability_timer", 0.0)
	_expect(player.receive_hit(9999, player, 1.0), "重反应保护期间仍可受到后续伤害")
	_expect(player.current_state == Player.State.DEAD, "保护期间的致命伤害仍然致死")
	await _destroy_world()

	player = await _create_grounded_player()
	_expect(player.receive_hit(6, player, -1.0), "首个高伤害触发重反应保护")
	var protected_velocity := player.velocity.x
	player.set("_invulnerability_timer", 0.0)
	_expect(player.receive_hit(6, player, 1.0), "保护期间非致命后续伤害仍可接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "重反应保护期间后续高伤害降级为普通反应")
	_expect(is_equal_approx(player.velocity.x, protected_velocity), "保护期间降级的普通反应不新增或反转水平击退")
	var protection_seconds := player.get_heavy_reaction_protection_remaining()
	await _physics_frames(int(ceil(protection_seconds * Engine.physics_ticks_per_second)) + 4)
	_expect(not player.is_heavy_reaction_protected(), "重反应保护会按配置过期")
	player.set("_invulnerability_timer", 0.0)
	_expect(player.receive_hit(1, player, 1.0, {"is_critical": true}), "重反应保护过期后可再次接受暴击命中")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "重反应保护过期后暴击再次触发重反应")
	await _destroy_world()


func _test_forced_minimum_knockback_metadata() -> void:
	var player := await _create_grounded_player()
	player.damage_knockback_speed = 20.0
	player.heavy_hit_knockback_cap = 180.0
	_expect(
		player.receive_hit(1, player, 1.0, {
			"force_knockback": true,
			"minimum_knockback_speed": 150.0,
			"is_critical": false,
		}),
		"强制击退元数据命中可被玩家接受"
	)
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "强制击退元数据触发重受击")
	_expect(is_equal_approx(player.velocity.x, 150.0), "玩家重受击采用元数据声明的最小击退速度")
	await _destroy_world()

	player = await _create_grounded_player()
	player.damage_knockback_speed = 20.0
	player.heavy_hit_knockback_cap = 120.0
	player.receive_hit(1, player, -1.0, {
		"force_knockback": true,
		"minimum_knockback_speed": 150.0,
		"is_critical": false,
	})
	_expect(is_equal_approx(player.velocity.x, -120.0), "元数据最小击退仍遵守玩家重受击速度上限")
	await _destroy_world()


func _test_heavy_reaction_from_critical_metadata() -> void:
	var player := await _create_grounded_player()
	_expect(player.receive_hit(1, player, 1.0, {"is_critical": true, "attack_id": &"critical_test"}), "暴击元数据命中可被玩家接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "暴击元数据即使低伤害也触发重反应")
	_expect(player.velocity.x > 0.0, "暴击重反应施加水平击退")
	await _destroy_world()

	player = await _create_grounded_player()
	_expect(player.receive_hit(1, player, 1.0, {"is_critical": false, "attack_id": &"noncritical_test"}), "非暴击元数据命中可被玩家接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "显式非暴击低伤害保持普通反应")
	_expect(is_zero_approx(player.velocity.x), "显式非暴击低伤害不水平击退")
	await _destroy_world()


func _test_airborne_and_sprint_context_thresholds() -> void:
	var player := await _create_falling_player(Vector2(0.0, -40.0))
	await _physics_frames(4)
	_expect(not player.is_on_floor(), "空中反应测试玩家保持离地")
	_expect(player.receive_hit(5, player, 1.0, {"is_critical": false}), "空中伤害命中可被玩家接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "离地时达到空中阈值触发重反应")
	await _destroy_world()

	player = await _create_grounded_player()
	Input.action_press(&"move_right")
	await physics_frame
	Input.action_release(&"move_right")
	await physics_frame
	Input.action_press(&"move_right")
	await _physics_frames(14)
	_expect(player.current_state == Player.State.SPRINT and player.velocity.x >= player.sprint_speed * player.true_sprint_hit_speed_ratio, "冲刺反应测试玩家达到真实冲刺速度")
	_expect(player.receive_hit(5, player, -1.0, {"is_critical": false}), "迎面冲刺伤害命中可被玩家接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "真实冲刺迎面受击达到阈值触发重反应")
	await _destroy_world()

	player = await _create_grounded_player()
	Input.action_press(&"move_right")
	await physics_frame
	Input.action_release(&"move_right")
	await physics_frame
	Input.action_press(&"move_right")
	await _physics_frames(14)
	_expect(player.receive_hit(2, player, 1.0, {"is_critical": false}), "背向冲刺低伤害命中可被玩家接受")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "低于普通伤害阈值的非迎面冲刺受击不使用冲刺重反应规则")
	await _destroy_world()


func _test_enemy_attack_metadata_real_ids_noncritical() -> void:
	var actors := await _create_combat_world(GRUNT_DEFINITION)
	var player := actors.player as Player
	var enemy := actors.enemy as GroundedEnemyController
	var attack := enemy.call("_attack_definition") as EnemyMeleeAttackDefinition
	_expect(attack != null and attack.attack_id == &"patrol_grunt_melee", "巡逻敌人使用真实攻击 id")
	var metadata := enemy.call("_attack_metadata", attack) as Dictionary
	_expect(metadata.get("attack_id") == &"patrol_grunt_melee", "巡逻敌人攻击元数据包含真实攻击 id")
	_expect(metadata.has("is_critical") and not bool(metadata.get("is_critical")), "巡逻敌人攻击元数据显式非暴击")
	_expect(player.receive_hit(maxi(attack.damage * DAMAGE_SCALE, 1), enemy, -1.0, metadata), "真实巡逻敌人攻击元数据可传入玩家受击")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "真实巡逻敌人非暴击低伤害为普通反应")
	_expect(is_zero_approx(player.velocity.x), "真实巡逻敌人普通攻击不水平击退")
	await _destroy_world()

	actors = await _create_combat_world(HEAVY_GUARD_DEFINITION)
	enemy = actors.enemy as GroundedEnemyController
	attack = enemy.call("_attack_definition") as EnemyMeleeAttackDefinition
	metadata = enemy.call("_attack_metadata", attack) as Dictionary
	_expect(metadata.get("attack_id") == &"heavy_guard_melee", "重甲敌人攻击元数据包含真实攻击 id")
	_expect(metadata.has("is_critical") and not bool(metadata.get("is_critical")), "重甲敌人攻击元数据显式非暴击")
	await _destroy_world()


func _test_player_outgoing_metadata_for_melee_and_projectile() -> void:
	var player := await _create_grounded_player()
	var metadata := player.call("_current_attack_metadata") as Dictionary
	_expect(metadata.is_empty(), "无当前攻击时玩家攻击元数据为空")
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	metadata = player.call("_current_attack_metadata") as Dictionary
	_expect(metadata.get("attack_id") == &"sword_light", "玩家近战轻击元数据包含攻击 id")
	_expect(metadata.has("is_critical") and metadata.get("is_critical") is bool, "玩家近战轻击元数据包含可观察暴击布尔值")
	_expect(not bool(metadata.get("force_knockback", false)), "玩家轻击不强制击退")
	Input.action_release(&"light_attack")
	await _destroy_world()

	player = await _create_grounded_player()
	Input.action_press(&"heavy_attack")
	await _physics_frames(2)
	metadata = player.call("_current_attack_metadata") as Dictionary
	_expect(metadata.get("attack_id") == &"sword_heavy", "玩家近战重击元数据包含攻击 id")
	_expect(bool(metadata.get("force_knockback", false)), "玩家近战重击强制击退")
	_expect(float(metadata.get("minimum_knockback_speed", 0.0)) > 0.0, "玩家近战重击提供最小击退速度")
	Input.action_release(&"heavy_attack")
	await _destroy_world()

	player = await _create_grounded_player()
	_expect(player.equip_item(STAR_STAFF), "玩家可装备测试法杖")
	Input.action_press(&"heavy_attack")
	await _physics_frames(4)
	metadata = player.call("_current_attack_metadata") as Dictionary
	_expect(metadata.get("attack_id") == &"staff_heavy", "玩家法杖重击元数据包含攻击 id")
	_expect(bool(metadata.get("force_knockback", false)), "玩家法杖重弹强制击退")
	_expect(float(metadata.get("minimum_knockback_speed", 0.0)) > 0.0, "玩家法杖重弹保留最小击退速度")
	Input.action_release(&"heavy_attack")
	await _destroy_world()


func _test_hurtbox_metadata_compatibility() -> void:
	var target := MetadataTarget.new()
	_create_world()
	_test_root.add_child(target)
	var hurtbox := _add_hurtbox_to(target)
	var metadata := {"attack_id": &"compatibility_attack", "is_critical": true, "nested": {"safe": true}}
	_expect(hurtbox.receive_hit(1, target, 1.0, metadata), "四参数 receive_hit 目标接受带元数据命中")
	metadata["attack_id"] = &"mutated_after_hit"
	metadata["nested"]["safe"] = false
	_expect(target.received_metadata.size() == 1, "四参数目标记录一次元数据")
	_expect(target.received_metadata[0].get("attack_id") == &"compatibility_attack", "命中元数据传递时深拷贝攻击 id")
	_expect(bool((target.received_metadata[0].get("nested") as Dictionary).get("safe")), "命中元数据传递时深拷贝嵌套字典")
	await _destroy_world()

	var legacy := LegacyTarget.new()
	_create_world()
	_test_root.add_child(legacy)
	hurtbox = _add_hurtbox_to(legacy)
	_expect(hurtbox.receive_hit(1, legacy, -1.0, {"attack_id": &"legacy_safe", "is_critical": true}), "三参数旧目标仍兼容带元数据命中")
	_expect(legacy.hit_count == 1, "三参数旧目标接收一次命中")
	await _destroy_world()


func _test_damage_reaction_cleanup_on_death_respawn_and_save_snapshot() -> void:
	var player := await _create_grounded_player()
	_expect(player.receive_hit(6, player, -1.0, {"is_critical": false}), "清理测试先触发重受击")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY and player.is_heavy_reaction_protected(), "清理测试确认重反应观测状态已设置")
	player.set("_invulnerability_timer", 0.0)
	player.receive_hit(9999, player, 1.0, {"is_critical": true})
	_expect(player.current_state == Player.State.DEAD, "致命伤害使玩家死亡")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "死亡清理最近受击反应观测")
	_expect(player.get_last_mitigated_hit_damage() == 0, "死亡清理最近减免伤害观测")
	_expect(is_zero_approx(player.get_last_hit_damage_ratio()), "死亡清理最近伤害比例观测")
	_expect(not player.is_heavy_reaction_protected(), "死亡清理重反应保护")
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	_expect(player.current_state == Player.State.IDLE, "手动复活立即恢复空闲状态")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "复活后最近受击反应保持清理状态")
	_expect(not player.is_heavy_reaction_protected(), "复活后无重反应保护残留")
	player.receive_hit(6, player, -1.0, {"is_critical": false})
	_expect(player.get_last_hit_reaction() == Player.HitReaction.HEAVY, "复活后可重新触发重反应")
	var result := player.apply_save_snapshot(_test_profile())
	await process_frame
	_expect(bool(result.ok), "测试存档快照可应用")
	_expect(player.get_last_hit_reaction() == Player.HitReaction.NORMAL, "应用存档快照清理最近受击反应")
	_expect(player.get_last_mitigated_hit_damage() == 0, "应用存档快照清理最近减免伤害")
	_expect(is_zero_approx(player.get_last_hit_damage_ratio()), "应用存档快照清理伤害比例")
	_expect(not player.is_heavy_reaction_protected(), "应用存档快照清理重反应保护")
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


func _create_grounded_player() -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(0.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	return player


func _create_falling_player(position: Vector2) -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(position)
	await process_frame
	return player


func _create_combat_world(definition: EnemyDefinition) -> Dictionary:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0))
	var player := _spawn_player(Vector2(96.0, PLAYER_FLOOR_POSITION_Y))
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


func _add_hurtbox_to(target: Node2D) -> Hurtbox:
	var hurtbox := Hurtbox.new()
	target.add_child(hurtbox)
	hurtbox.owner = target
	return hurtbox


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


func _test_profile() -> Dictionary:
	return {
		"version": 1,
		"profile_id": "issue_6_damage_reaction_test",
		"slot": 0,
		"name": "伤害反应测试",
		"profession_id": "traveler",
		"created_at": 0,
		"updated_at": 0,
		"play_time_seconds": 0,
		"progression": {"level": 1, "experience": 0},
		"materials": {"stardust_fragment": 0},
		"equipment": {"equipped": {"weapon": "traveler_sword"}, "inventory": []},
		"location": {"area_id": "test_level", "safe_spawn_id": "start"},
		"meta": {},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
