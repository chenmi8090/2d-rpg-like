extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const STAR_STAFF := preload("res://resources/equipment/star_staff.tres")
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0
const SAVE_VERSION := 1

class CombatTarget:
	extends Node2D
	var hit_count := 0
	var last_direction := 0.0
	func receive_hit(_amount: int, _source: Node, direction: float, _metadata: Dictionary = {}) -> bool:
		hit_count += 1
		last_direction = direction
		return true

var _failures: Array[String] = []
var _test_root: Node2D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_rising_and_falling_entries()
	await _test_once_per_airtime()
	await _test_air_physics()
	await _test_air_melee_hits()
	await _test_air_staff_release()
	await _test_edge_and_landing_continuity()
	await _test_cleanup()
	await _test_one_way_drop_through()
	_release_inputs()
	if _failures.is_empty():
		print("Issue #9 air and platform attack tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_rising_and_falling_entries() -> void:
	for case in [
		{ "rising": true, "action": &"light_attack", "profile": &"sword_light" },
		{ "rising": true, "action": &"heavy_attack", "profile": &"sword_heavy" },
		{ "rising": false, "action": &"light_attack", "profile": &"sword_light" },
		{ "rising": false, "action": &"heavy_attack", "profile": &"sword_heavy" },
	]:
		var player: Player
		if case.rising:
			player = await _create_grounded_player()
			Input.action_press(&"jump")
			await _physics_frames(2)
		else:
			player = await _create_falling_player(Vector2(0.0, -120.0))
		var profiles: Array[StringName] = []
		player.attack_started.connect(func(_type: int, profile: StringName) -> void: profiles.append(profile))
		Input.action_press(case.action)
		await _physics_frames(2)
		Input.action_release(case.action)
		Input.action_release(&"jump")
		_expect(player.current_state == Player.State.ATTACK, "跳跃或下落期间可以发动现有基础攻击")
		_expect(profiles == [case.profile], "空中攻击继续使用当前装备的现有攻击档案")
		await _destroy_world()

func _test_once_per_airtime() -> void:
	var player := await _create_falling_player(Vector2(0.0, -500.0))
	var started: Array[int] = []
	player.attack_started.connect(func(type: int, _profile: StringName) -> void: started.append(type))
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	await _physics_frames(28)
	Input.action_press(&"heavy_attack")
	await _physics_frames(2)
	Input.action_release(&"heavy_attack")
	_expect(started == [Player.AttackType.LIGHT], "每次离地轻重攻击共享一次资格")
	await _wait_until_grounded(player)
	Input.action_press(&"jump")
	await _physics_frames(2)
	Input.action_release(&"jump")
	Input.action_press(&"heavy_attack")
	await _physics_frames(2)
	Input.action_release(&"heavy_attack")
	_expect(started == [Player.AttackType.LIGHT, Player.AttackType.HEAVY], "落地后下一次离地恢复攻击资格")
	await _destroy_world()

func _test_air_physics() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"jump")
	await _physics_frames(3)
	var before := player.velocity.y
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	_expect(player.velocity.y > before and player.velocity.y < 0.0, "空中攻击期间垂直速度继续受重力影响")
	Input.action_release(&"jump")
	await _physics_frames(2)
	_expect(player.velocity.y >= player.jump_velocity * player.jump_cutoff_multiplier, "空中攻击期间继续应用短跳截断")
	Input.action_release(&"light_attack")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -220.0))
	player.velocity.y = player.maximum_fall_speed - 5.0
	Input.action_press(&"heavy_attack")
	await _physics_frames(3)
	Input.action_release(&"heavy_attack")
	_expect(player.velocity.y <= player.maximum_fall_speed, "空中攻击期间遵守最大下落速度")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -180.0))
	player.velocity.x = 180.0
	Input.action_press(&"move_left")
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	var first := player.velocity.x
	await _physics_frames(5)
	_expect(first > -player.move_speed and player.velocity.x < first, "空中攻击保留有限且渐进的水平控制")
	Input.action_release(&"move_left")
	Input.action_release(&"light_attack")
	await _destroy_world()

func _test_air_melee_hits() -> void:
	var player := await _create_falling_player(Vector2(0.0, -160.0))
	var target := _add_target(player.global_position + Vector2(55.0, -20.0))
	var hitbox := player.get_node("AttackHitbox") as AttackHitbox
	var collision := hitbox.get_node("CollisionShape2D") as CollisionShape2D
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	var configured_size := (collision.shape as RectangleShape2D).size
	for _frame in 18:
		target.global_position = player.global_position + Vector2(55.0, -20.0)
		await physics_frame
	_expect(target.hit_count == 1, "空中剑攻击在现有生效窗口命中且单次只命中一次")
	_expect((collision.shape as RectangleShape2D).size == configured_size, "空中规则不会改变近战 Hitbox 几何")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -160.0))
	var left := _add_target(player.global_position + Vector2(-55.0, -20.0))
	var right := _add_target(player.global_position + Vector2(55.0, -20.0))
	Input.action_press(&"move_left")
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	Input.action_release(&"move_left")
	Input.action_press(&"move_right")
	for _frame in 12:
		left.global_position = player.global_position + Vector2(-55.0, -20.0)
		right.global_position = player.global_position + Vector2(55.0, -20.0)
		await physics_frame
	_expect(left.hit_count == 1 and left.last_direction < 0.0 and right.hit_count == 0, "空中剑攻击保存开始攻击时的方向")
	Input.action_release(&"move_right")
	await _destroy_world()

func _test_air_staff_release() -> void:
	for action in [&"light_attack", &"heavy_attack"]:
		var player := await _create_falling_player(Vector2(0.0, -220.0))
		_expect(player.equip_item(STAR_STAFF), "测试角色可以装备法杖")
		Input.action_press(action)
		await _physics_frames(2)
		Input.action_release(action)
		var wait_frames := 10 if action == &"light_attack" else 22
		await _physics_frames(wait_frames)
		_expect(_owned_projectiles(player).size() == 1, "空中法杖轻重攻击各在释放时间生成一个投射物")
		var count_before_landing := _owned_projectiles(player).size()
		await _wait_until_grounded(player)
		_expect(_owned_projectiles(player).size() <= count_before_landing, "空中法杖攻击落地不会重复生成投射物")
		await _destroy_world()

func _test_edge_and_landing_continuity() -> void:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(80.0, 40.0), false)
	var player := _spawn_player(Vector2(10.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	player.move_speed = 900.0
	var started := 0
	var cancelled: Array[bool] = []
	player.attack_started.connect(func(_type: int, _profile: StringName) -> void: started += 1)
	player.attack_ended.connect(func(_type: int, _profile: StringName, was_cancelled: bool) -> void: cancelled.append(was_cancelled))
	Input.action_press(&"move_right")
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	var starts_before_edge := started
	await _wait_until_airborne(player)
	_expect(player.current_state == Player.State.ATTACK, "地面攻击离开平台后继续原计时")
	_expect(started == starts_before_edge, "离开平台不会重新开始原攻击")
	_expect(cancelled.is_empty(), "离开平台瞬间不会取消原攻击")
	_expect(bool(player.get("_air_attack_consumed")), "地面开始后离地会消耗本次离地攻击资格")
	Input.action_release(&"move_right")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -40.0))
	started = 0
	player.attack_started.connect(func(_type: int, _profile: StringName) -> void: started += 1)
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	var starts_before_landing := started
	Input.action_release(&"light_attack")
	await _wait_until_grounded(player)
	var starts_on_landing := started
	_expect(starts_before_landing == starts_on_landing, "空中攻击落地不会重新开始")
	await _physics_frames(25)
	_expect(player.current_state == Player.State.IDLE, "空中攻击落地后按原计时恢复到正确地面状态")
	await _destroy_world()

func _test_cleanup() -> void:
	var player := await _create_falling_player(Vector2(0.0, -220.0))
	var started := 0
	player.attack_started.connect(func(_type: int, _profile: StringName) -> void: started += 1)
	Input.action_press(&"heavy_attack")
	await _physics_frames(3)
	Input.action_release(&"heavy_attack")
	await _physics_frames(4)
	player.receive_hit(1, player, -1.0, {"is_critical": true})
	_expect(player.current_state == Player.State.HIT, "空中攻击受击后立即进入受击状态")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -220.0))
	player.apply_safe_spawn(Vector2(0.0, PLAYER_FLOOR_POSITION_Y))
	player.equip_item(STAR_STAFF)
	await _physics_frames(8)
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	await _physics_frames(10)
	_expect(not _owned_projectiles(player).is_empty(), "死亡清理测试先生成玩家投射物")
	player.receive_hit(999, player, -1.0)
	await process_frame
	_expect(player.current_state == Player.State.DEAD and _owned_projectiles(player).is_empty(), "死亡清理空中攻击与玩家投射物")
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	_expect(player.current_state == Player.State.IDLE, "手动重置清理空中攻击临时状态")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -220.0))
	player.equip_item(STAR_STAFF)
	Input.action_press(&"heavy_attack")
	await _physics_frames(2)
	Input.action_release(&"heavy_attack")
	var result := player.apply_save_snapshot(_test_profile())
	await process_frame
	_expect(bool(result.get("ok", false)), "测试存档快照可以应用")
	_expect(player.current_state != Player.State.ATTACK, "应用存档快照清理空中攻击状态")
	_expect(_owned_projectiles(player).is_empty(), "应用存档快照清理玩家投射物")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -220.0))
	player.equip_item(STAR_STAFF)
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	await _physics_frames(10)
	player.queue_free()
	await process_frame
	await process_frame
	_expect(get_nodes_in_group("player_attack_projectile").is_empty(), "玩家离开场景树清理拥有的攻击节点")
	await _destroy_world()

func _test_one_way_drop_through() -> void:
	var player := await _create_one_way_player()
	var start_y := player.global_position.y
	Input.action_press(&"interact_down")
	await physics_frame
	Input.action_press(&"jump")
	await _physics_frames(2)
	Input.action_release(&"jump")
	Input.action_press(&"light_attack")
	await _physics_frames(2)
	Input.action_release(&"light_attack")
	_expect(player.current_state == Player.State.ATTACK and not player.get_collision_mask_value(3), "下穿单向平台后可以攻击且碰撞保持暂时关闭")
	await _physics_frames(18)
	_expect(player.get_collision_mask_value(3) and player.global_position.y > start_y + 15.0, "空中攻击不破坏单向平台下穿与碰撞恢复")
	await _destroy_world()

func _create_grounded_player() -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0), false)
	var player := _spawn_player(Vector2(0.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	return player

func _create_falling_player(position: Vector2) -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0), false)
	var player := _spawn_player(position)
	await process_frame
	await physics_frame
	return player

func _create_one_way_player() -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0), false)
	_add_platform(Vector2(0.0, 20.0), Vector2(300.0, 20.0), true)
	var player := _spawn_player(Vector2(0.0, -80.0))
	await _wait_until_grounded(player)
	await _physics_frames(2)
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

func _add_platform(position: Vector2, size: Vector2, one_way: bool) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = 4 if one_way else 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	collision.one_way_collision = one_way
	collision.one_way_collision_margin = 12.0
	body.add_child(collision)
	_test_root.add_child(body)
	return body

func _add_target(position: Vector2) -> CombatTarget:
	var target := CombatTarget.new()
	target.global_position = position
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

func _wait_until_grounded(player: Player, maximum_frames := 180) -> bool:
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

func _test_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"profile_id": "issue_9_test",
		"slot": 0,
		"name": "空中攻击测试",
		"profession_id": "traveler",
		"created_at": 0,
		"updated_at": 0,
		"play_time_seconds": 0,
		"progression": {"level": 1, "experience": 0},
		"materials": {"stardust_fragment": 0},
		"equipment": {"equipped": {"weapon": "traveler_sword"}, "inventory": []},
		"location": {"area_id": "test_level", "safe_spawn_id": "default"},
		"meta": {},
	}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
