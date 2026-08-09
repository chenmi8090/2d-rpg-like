extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const STAR_STAFF := preload("res://resources/equipment/star_staff.tres")
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0

class CombatTarget:
	extends Node2D

	var accepts_hits := true
	var hit_count := 0
	var total_damage := 0
	var last_direction := 0.0
	var last_source: Node

	func receive_hit(amount: int, source: Node, hit_direction: float) -> bool:
		if not accepts_hits:
			return false
		hit_count += 1
		total_damage += amount
		last_direction = hit_direction
		last_source = source
		return true

var _failures: Array[String] = []
var _test_root: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_grounded_attack_rules()
	await _test_sword_attack_phases()
	await _test_melee_hit_rules()
	await _test_held_attack_cadence()
	await _test_staff_projectiles()
	await _test_rejected_hits()
	await _test_attack_interruptions()
	await _test_edge_and_landing_rules()
	_release_inputs()
	if _failures.is_empty():
		print("Issue #3 combat tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_grounded_attack_rules() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"interact_down")
	await _physics_frames(2)
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	_expect(player.current_state == Player.State.CROUCH, "下蹲状态不会发动地面轻攻击")
	Input.action_release(&"light_attack")
	Input.action_release(&"interact_down")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -80.0))
	var started_profiles: Array[StringName] = []
	player.attack_started.connect(func(_type: int, profile_id: StringName) -> void: started_profiles.append(profile_id))
	Input.action_press(&"heavy_attack")
	await _physics_frames(4)
	_expect(player.current_state == Player.State.ATTACK, "下落期间可以发动现有重攻击")
	_expect(started_profiles == [&"sword_heavy"], "空中重攻击继续使用当前装备的重攻击档案")
	Input.action_release(&"heavy_attack")
	await _destroy_world()


func _test_sword_attack_phases() -> void:
	var player := await _create_grounded_player()
	var target := _add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	var phases: Array[int] = []
	player.attack_phase_changed.connect(func(_type: int, phase: int) -> void: phases.append(phase))
	Input.action_press(&"light_attack")
	await _physics_frames(4)
	_expect(player.current_state == Player.State.ATTACK, "轻攻击准备阶段进入攻击状态")
	_expect(target.hit_count == 0, "轻攻击准备阶段不会提前命中")
	await _physics_frames(4)
	_expect(target.hit_count == 1, "轻攻击生效阶段命中范围内目标")
	await _physics_frames(5)
	_expect(player.current_state == Player.State.ATTACK and target.hit_count == 1, "轻攻击恢复阶段不重复命中")
	Input.action_release(&"light_attack")
	await _physics_frames(14)
	_expect(player.current_state == Player.State.IDLE, "轻攻击结束后恢复空闲状态")
	_expect(Player.AttackPhase.ACTIVE in phases and Player.AttackPhase.RECOVERY in phases, "轻攻击依次进入生效和恢复阶段")
	await _destroy_world()

	player = await _create_grounded_player()
	target = _add_target(Vector2(65.0, PLAYER_FLOOR_POSITION_Y - 18.0))
	Input.action_press(&"heavy_attack")
	await _physics_frames(12)
	_expect(target.hit_count == 0 and player.current_state == Player.State.ATTACK, "重攻击具有明显准备阶段")
	await _physics_frames(8)
	_expect(target.hit_count == 1, "重攻击在较晚的生效阶段命中")
	Input.action_release(&"heavy_attack")
	await _physics_frames(33)
	_expect(player.current_state == Player.State.IDLE and target.hit_count == 1, "重攻击恢复完成且单次只命中一次")
	await _destroy_world()


func _test_melee_hit_rules() -> void:
	var player := await _create_grounded_player()
	var first := _add_target(Vector2(50.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	var second := _add_target(Vector2(70.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	var confirmations: Array[int] = []
	player.attack_hit_confirmed.connect(func(_type: int, _profile: StringName) -> void: confirmations.append(1))
	Input.action_press(&"heavy_attack")
	await _physics_frames(24)
	await process_frame
	Input.action_release(&"heavy_attack")
	_expect(first.hit_count == 1 and second.hit_count == 1, "一次近战攻击可分别命中多个目标一次")
	_expect(confirmations.size() == 2, "每个被接受的近战命中产生一次确认")
	await _destroy_world()

	player = await _create_grounded_player()
	var right_target := _add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	var left_target := _add_target(Vector2(-55.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	Input.action_press(&"move_left")
	await _physics_frames(2)
	Input.action_press(&"light_attack")
	await _physics_frames(10)
	Input.action_release(&"light_attack")
	Input.action_release(&"move_left")
	_expect(left_target.hit_count == 1 and left_target.last_direction < 0.0, "向左攻击命中左侧并传递左方向")
	_expect(right_target.hit_count == 0, "向左攻击不会错误命中右侧目标")
	await _destroy_world()


func _test_held_attack_cadence() -> void:
	var player := await _create_grounded_player()
	var target := _add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0))
	Input.action_press(&"light_attack")
	await _physics_frames(25)
	_expect(target.hit_count == 1, "持续轻攻击不会在首轮结束前额外命中")
	await _physics_frames(15)
	_expect(target.hit_count == 2, "持续轻攻击按照轻攻击间隔发动第二次攻击")
	Input.action_release(&"light_attack")
	await _destroy_world()

	player = await _create_grounded_player()
	target = _add_target(Vector2(65.0, PLAYER_FLOOR_POSITION_Y - 18.0))
	Input.action_press(&"heavy_attack")
	await _physics_frames(58)
	_expect(target.hit_count == 1, "持续重攻击不会按照轻攻击速度重复")
	await _physics_frames(36)
	_expect(target.hit_count == 2, "持续重攻击按照较长间隔发动第二次攻击")
	Input.action_release(&"heavy_attack")
	await _destroy_world()

	player = await _create_grounded_player()
	var started: Array[int] = []
	player.attack_started.connect(func(type: int, _profile: StringName) -> void: started.append(type))
	Input.action_press(&"light_attack")
	Input.action_press(&"heavy_attack")
	await _physics_frames(85)
	Input.action_release(&"light_attack")
	Input.action_release(&"heavy_attack")
	_expect(started.size() >= 2 and started[0] == Player.AttackType.LIGHT and started[1] == Player.AttackType.HEAVY, "同时按住轻重攻击时按既有规则交替")
	await _destroy_world()


func _test_staff_projectiles() -> void:
	var player := await _create_grounded_player()
	_expect(player.equip_item(STAR_STAFF), "旅人可以装备测试法杖")
	Input.action_press(&"light_attack")
	await _physics_frames(5)
	_expect(_owned_projectiles(player).is_empty(), "法杖轻攻击准备阶段不会提前生成投射物")
	await _physics_frames(6)
	var projectiles := _owned_projectiles(player)
	_expect(projectiles.size() == 1, "法杖轻攻击在释放时机只生成一个投射物")
	var start_x := projectiles[0].global_position.x if not projectiles.is_empty() else 0.0
	await _physics_frames(3)
	projectiles = _owned_projectiles(player)
	_expect(not projectiles.is_empty() and projectiles[0].global_position.x > start_x, "向右法杖投射物向右飞行")
	Input.action_release(&"light_attack")
	await _physics_frames(65)
	_expect(_owned_projectiles(player).is_empty(), "未命中的法杖投射物按距离或寿命清理")
	await _destroy_world()

	player = await _create_grounded_player()
	player.equip_item(STAR_STAFF)
	var near_target := _add_target(Vector2(145.0, PLAYER_FLOOR_POSITION_Y - 30.0))
	var far_target := _add_target(Vector2(240.0, PLAYER_FLOOR_POSITION_Y - 30.0))
	Input.action_press(&"light_attack")
	await _physics_frames(28)
	Input.action_release(&"light_attack")
	_expect(near_target.hit_count == 1, "法杖投射物命中首个有效目标")
	_expect(far_target.hit_count == 0, "法杖投射物命中首个目标后不会继续穿透")
	_expect(_owned_projectiles(player).is_empty(), "法杖投射物命中后立即清理")
	await _destroy_world()

	player = await _create_grounded_player()
	player.equip_item(STAR_STAFF)
	var delayed_target := _add_target(Vector2(330.0, PLAYER_FLOOR_POSITION_Y - 30.0))
	var confirmed_profiles: Array[StringName] = []
	player.attack_hit_confirmed.connect(func(_type: int, profile_id: StringName) -> void: confirmed_profiles.append(profile_id))
	Input.action_press(&"light_attack")
	await _physics_frames(28)
	Input.action_release(&"light_attack")
	_expect(player.current_state == Player.State.IDLE, "法杖施法动作可在投射物命中前结束")
	await _physics_frames(25)
	_expect(delayed_target.hit_count == 1, "延迟飞行的法杖投射物仍能命中")
	_expect(confirmed_profiles == [&"staff_light"], "延迟投射物命中保留原攻击档案身份")
	await _destroy_world()


func _test_rejected_hits() -> void:
	var player := await _create_grounded_player()
	var rejected := _add_target(Vector2(55.0, PLAYER_FLOOR_POSITION_Y - 20.0), false)
	var confirmations := 0
	player.attack_hit_confirmed.connect(func(_type: int, _profile: StringName) -> void: confirmations += 1)
	Input.action_press(&"light_attack")
	await _physics_frames(14)
	Input.action_release(&"light_attack")
	_expect(rejected.hit_count == 0 and confirmations == 0, "拒绝的近战命中不会产生伤害或命中确认")
	await _destroy_world()

	player = await _create_grounded_player()
	player.equip_item(STAR_STAFF)
	rejected = _add_target(Vector2(120.0, PLAYER_FLOOR_POSITION_Y - 30.0), false)
	var accepted := _add_target(Vector2(210.0, PLAYER_FLOOR_POSITION_Y - 30.0))
	Input.action_press(&"light_attack")
	await _physics_frames(35)
	Input.action_release(&"light_attack")
	_expect(rejected.hit_count == 0, "法杖投射物不会伤害拒绝命中的目标")
	_expect(accepted.hit_count == 1, "法杖投射物穿过拒绝目标后命中首个有效目标")
	await _destroy_world()


func _test_attack_interruptions() -> void:
	var player := await _create_grounded_player()
	var target := _add_target(Vector2(65.0, PLAYER_FLOOR_POSITION_Y - 18.0))
	Input.action_press(&"heavy_attack")
	await _physics_frames(8)
	Input.action_release(&"heavy_attack")
	player.receive_hit(1, player, -1.0)
	await _physics_frames(25)
	_expect(target.hit_count == 0, "重攻击准备阶段受击后不会延迟命中")
	_expect(player.current_state != Player.State.ATTACK, "受击正确中断攻击状态")
	await _destroy_world()

	player = await _create_grounded_player()
	player.apply_safe_spawn(player.global_position)
	player.equip_item(STAR_STAFF)
	Input.action_press(&"light_attack")
	await _physics_frames(16)
	Input.action_release(&"light_attack")
	_expect(not _owned_projectiles(player).is_empty(), "复活清理测试先生成法杖投射物")
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	await _physics_frames(2)
	_expect(_owned_projectiles(player).is_empty(), "复活清理角色拥有的攻击投射物")
	_expect(player.current_state == Player.State.IDLE, "复活清理攻击阶段并恢复空闲状态")
	await _destroy_world()


func _test_edge_and_landing_rules() -> void:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(80.0, 40.0))
	var player := _spawn_player(Vector2(10.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	player.move_speed = 900.0
	var ended: Array[bool] = []
	player.attack_ended.connect(func(_type: int, _profile: StringName, cancelled: bool) -> void: ended.append(cancelled))
	Input.action_press(&"move_right")
	Input.action_press(&"heavy_attack")
	await _wait_until_airborne(player)
	await _physics_frames(20)
	_expect(player.current_state == Player.State.ATTACK, "地面攻击离开平台后继续原攻击计时")
	await _physics_frames(35)
	Input.action_release(&"move_right")
	Input.action_release(&"heavy_attack")
	_expect(player.current_state == Player.State.FALL, "平台边缘攻击自然结束后进入下落")
	_expect(ended == [false], "平台边缘不会把正常完成的攻击标记为取消")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -45.0))
	var started: Array[int] = []
	player.attack_started.connect(func(type: int, _profile: StringName) -> void: started.append(type))
	Input.action_press(&"light_attack")
	await _physics_frames(8)
	_expect(player.current_state == Player.State.ATTACK and started.size() == 1, "空中按住攻击会发动一次空中攻击")
	await _wait_until_grounded(player)
	await _physics_frames(2)
	_expect(started.size() == 1, "空中攻击落地不会重新开始同一轮输入")
	Input.action_release(&"light_attack")
	await _destroy_world()


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
	await physics_frame
	return player


func _create_world() -> void:
	_release_inputs()
	_test_root = Node2D.new()
	root.add_child(_test_root)


func _spawn_player(position: Vector2) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
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
	hurtbox.collision_mask = 0
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


func _wait_until_grounded(player: Player, maximum_frames := 120) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if player.is_on_floor():
			return true
	_expect(false, "角色在预期时间内接触地面")
	return false


func _wait_until_airborne(player: Player, maximum_frames := 90) -> bool:
	for _frame in maximum_frames:
		var was_on_floor := player.is_on_floor()
		await physics_frame
		if was_on_floor and not player.is_on_floor():
			return true
	_expect(false, "角色在预期时间内离开平台")
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
