extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FLOOR_Y := 120.0
const PLAYER_FLOOR_POSITION_Y := 82.0

var _failures: Array[String] = []
var _test_root: Node2D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_ground_movement()
	await _test_sprint_rules()
	await _test_variable_jump()
	await _test_coyote_time()
	await _test_jump_buffer()
	await _test_air_control_and_landing()
	await _test_drop_through()
	await _test_input_safety()
	_release_inputs()
	if _failures.is_empty():
		print("Issue #2 movement tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_ground_movement() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"move_right")
	await physics_frame
	var first_speed := player.velocity.x
	_expect(first_speed > 0.0 and first_speed < player.move_speed, "地面移动从静止状态平滑加速")
	await _physics_frames(12)
	_expect(is_equal_approx(player.velocity.x, player.move_speed), "持续输入后达到行走速度")

	Input.action_release(&"move_right")
	await physics_frame
	_expect(player.velocity.x > 0.0 and player.velocity.x < player.move_speed, "松开方向后平滑减速")
	await _physics_frames(8)
	_expect(is_zero_approx(player.velocity.x), "松开方向后稳定停止")

	Input.action_press(&"move_right")
	await _physics_frames(8)
	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await _physics_frames(5)
	_expect(player.velocity.x < 0.0, "快速反向时及时穿过零速度")
	_expect(player.current_state == Player.State.WALK, "反向移动保持行走状态")
	await _destroy_world()


func _test_sprint_rules() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"move_right")
	await physics_frame
	Input.action_release(&"move_right")
	await physics_frame
	Input.action_press(&"move_right")
	await _physics_frames(12)
	_expect(player.current_state == Player.State.SPRINT, "同方向双击并按住进入冲刺")
	_expect(player.velocity.x > player.move_speed, "冲刺速度高于行走速度")

	Input.action_release(&"move_right")
	Input.action_press(&"move_left")
	await _physics_frames(8)
	_expect(player.current_state == Player.State.WALK, "冲刺反向后不会继承冲刺状态")
	_expect(player.velocity.x < 0.0 and absf(player.velocity.x) <= player.move_speed, "冲刺反向目标恢复为行走速度")
	await _destroy_world()

	player = await _create_grounded_player()
	Input.action_press(&"move_right")
	await physics_frame
	Input.action_release(&"move_right")
	await _physics_frames(20)
	Input.action_press(&"move_right")
	await _physics_frames(12)
	_expect(player.current_state == Player.State.WALK, "超过双击窗口不会进入冲刺")
	_expect(player.velocity.x <= player.move_speed, "超时双击保持行走速度")
	await _destroy_world()


func _test_variable_jump() -> void:
	var short_player := await _create_grounded_player()
	var short_start := short_player.global_position.y
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	var short_peak := await _measure_jump_peak(short_player)
	await _destroy_world()

	var long_player := await _create_grounded_player()
	var long_start := long_player.global_position.y
	Input.action_press(&"jump")
	await _physics_frames(14)
	Input.action_release(&"jump")
	var long_peak := await _measure_jump_peak(long_player)
	_expect(long_start - long_peak > short_start - short_peak + 35.0, "长按跳跃明显高于短按跳跃")
	await _wait_until_grounded(long_player)
	await _physics_frames(3)
	_expect(long_player.current_state == Player.State.IDLE, "持续按住过的跳跃不会在落地后重复触发")
	await _destroy_world()


func _test_coyote_time() -> void:
	var player := await _create_ledge_player()
	Input.action_press(&"move_right")
	await _wait_until_airborne(player)
	Input.action_press(&"jump")
	await _physics_frames(2)
	_expect(player.velocity.y < 0.0 and player.current_state == Player.State.JUMP, "离开平台边缘后可在土狼时间内起跳")
	await _destroy_world()

	player = await _create_ledge_player()
	Input.action_press(&"move_right")
	await _wait_until_airborne(player)
	await _physics_frames(10)
	Input.action_press(&"jump")
	await physics_frame
	_expect(player.velocity.y >= 0.0 and player.current_state == Player.State.FALL, "土狼时间结束后不能在空中起跳")
	await _destroy_world()


func _test_jump_buffer() -> void:
	var player := await _create_falling_player(Vector2(0.0, -5.0))
	await _physics_frames(12)
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	var buffered_jump_started := await _wait_for_upward_velocity(player, 12)
	_expect(buffered_jump_started, "落地前输入的跳跃会在落地后执行")
	await _destroy_world()

	player = await _create_falling_player(Vector2(0.0, -120.0))
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	await _physics_frames(45)
	_expect(player.is_on_floor(), "过早跳跃输入后角色正常落地")
	_expect(player.velocity.y >= 0.0 and player.current_state == Player.State.IDLE, "过期跳跃缓存不会在落地后执行")
	await _destroy_world()


func _test_air_control_and_landing() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"move_right")
	await _physics_frames(12)
	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")
	Input.action_release(&"move_right")
	var takeoff_speed := player.velocity.x
	await physics_frame
	_expect(player.velocity.x > 0.0 and player.velocity.x < takeoff_speed, "空中松开方向后保留并逐步衰减水平动量")
	Input.action_press(&"move_left")
	await _physics_frames(6)
	_expect(player.velocity.x < takeoff_speed, "空中反向输入有限地修正水平速度")
	Input.action_release(&"move_left")
	await _wait_until_grounded(player)
	await _physics_frames(3)
	_expect(player.is_on_floor() and is_zero_approx(player.velocity.y), "下落后稳定落地且垂直速度归零")
	_expect(player.current_state == Player.State.IDLE, "无方向输入落地后恢复空闲状态")
	await _destroy_world()


func _test_drop_through() -> void:
	var player := await _create_one_way_player()
	var start_y := player.global_position.y
	Input.action_press(&"interact_down")
	await physics_frame
	Input.action_press(&"jump")
	await _physics_frames(2)
	Input.action_release(&"jump")
	_expect(not player.get_collision_mask_value(3), "平台下落开始时暂时关闭单向平台碰撞")
	_expect(player.velocity.y > 0.0 and player.current_state == Player.State.FALL, "S 加 Space 从单向平台向下落")
	await _physics_frames(18)
	_expect(player.get_collision_mask_value(3), "平台下落结束后恢复单向平台碰撞")
	_expect(player.global_position.y > start_y + 15.0, "角色实际穿过当前单向平台")
	await _wait_until_grounded(player)
	Input.action_release(&"interact_down")
	await physics_frame
	Input.action_press(&"interact_down")
	await physics_frame
	Input.action_release(&"interact_down")
	Input.action_press(&"move_right")
	await _physics_frames(4)
	_expect(player.current_state == Player.State.WALK and player.velocity.x > 0.0, "下穿平台后再次下蹲仍可起身移动")
	await _destroy_world()

	player = await _create_grounded_player()
	Input.action_press(&"interact_down")
	Input.action_press(&"jump")
	await physics_frame
	_expect(player.is_on_floor() and player.current_state == Player.State.CROUCH, "S 加 Space 在普通地面只进入下蹲")
	_expect(player.velocity.y >= 0.0 and player.get_collision_mask_value(3), "普通地面不会被平台下落操作穿透")
	await _destroy_world()


func _test_input_safety() -> void:
	var player := await _create_grounded_player()
	Input.action_press(&"move_left")
	Input.action_press(&"jump")
	player.suppress_gameplay_input(0.12)
	await physics_frame
	_expect(is_zero_approx(player.velocity.x) and player.is_on_floor(), "输入屏蔽阻止残留移动与跳跃")
	Input.action_release(&"move_left")
	Input.action_release(&"jump")
	await _physics_frames(9)
	Input.action_press(&"move_left")
	await physics_frame
	_expect(player.velocity.x < 0.0, "输入屏蔽结束后新移动输入正常工作")

	player._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_expect(not Input.is_action_pressed(&"move_left"), "窗口失焦时释放游戏输入")
	await physics_frame
	_expect(is_zero_approx(player.velocity.x), "窗口失焦时清除移动状态")
	await _destroy_world()

	player = await _create_grounded_player()
	player.apply_safe_spawn(player.global_position)
	Input.action_press(&"move_right")
	await physics_frame
	Input.action_release(&"move_right")
	Input.action_press(&"jump")
	player.receive_hit(1, player, 1.0, {"is_critical": true})
	Input.action_release(&"jump")
	_expect(
		player.current_state == Player.State.HIT
		and player.velocity.x > 0.0,
		"产生击退的受击清除输入状态并施加水平后退"
	)
	await _physics_frames(18)
	_expect(player.current_state != Player.State.JUMP, "受击前的跳跃缓存不会在硬直后触发")

	Input.action_press(&"move_left")
	Input.action_press(&"jump")
	player.respawn(Player.RespawnReason.MANUAL_RESET)
	await physics_frame
	_expect(player.current_state == Player.State.IDLE and player.velocity == Vector2.ZERO, "复活后清除移动、冲刺和跳跃状态")
	_expect(player.get_collision_mask_value(3), "复活后确保单向平台碰撞已恢复")
	await _destroy_world()


func _create_grounded_player() -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0), false)
	var player := _spawn_player(Vector2(0.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	return player


func _create_ledge_player() -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(150.0, 40.0), false)
	var player := _spawn_player(Vector2(48.0, PLAYER_FLOOR_POSITION_Y))
	await _settle_player(player)
	return player


func _create_falling_player(position: Vector2) -> Player:
	_create_world()
	_add_platform(Vector2(0.0, FLOOR_Y), Vector2(1000.0, 40.0), false)
	var player := _spawn_player(position)
	await process_frame
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


func _wait_until_airborne(player: Player, maximum_frames := 60) -> bool:
	for _frame in maximum_frames:
		var was_on_floor := player.is_on_floor()
		await physics_frame
		if was_on_floor and not player.is_on_floor():
			return true
	_expect(false, "角色在预期时间内离开平台")
	return false


func _wait_for_upward_velocity(player: Player, maximum_frames: int) -> bool:
	for _frame in maximum_frames:
		await physics_frame
		if player.velocity.y < 0.0:
			return true
	return false


func _measure_jump_peak(player: Player) -> float:
	var peak := player.global_position.y
	for _frame in 90:
		await physics_frame
		peak = minf(peak, player.global_position.y)
		if player.velocity.y > 0.0:
			break
	return peak


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
