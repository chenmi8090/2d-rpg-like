class_name GroundedEnemyController
extends CharacterBody2D

signal drop_requested(enemy: GroundedEnemyController, drop_rules: Array[EnemyDropRule])
signal equipment_drop_requested(enemy: GroundedEnemyController, drop_rules: Array[EquipmentDropRule])
signal defeated(enemy: GroundedEnemyController, source: Node)

enum State {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	RETURN_HOME,
	HIT,
	DEAD,
	JUMP_CHASE,
}

@export var definition: EnemyDefinition
@export var target_path: NodePath
@export var start_facing_direction := -1.0

var current_state := State.IDLE
var _health := 1
var _spawn_position := Vector2.ZERO
var _patrol_left_x := 0.0
var _patrol_right_x := 0.0
var _facing_direction := -1.0
var _idle_timer := 0.0
var _hit_stun_timer := 0.0
var _hit_flash_timer := 0.0
var _attack_elapsed := 0.0
var _attack_cooldown_timer := 0.0
var _attack_hitbox_active := false
var _target_acquired := false
var _drops_emitted := false
var _defeated_emitted := false
var _death_pending := false
var _lethal_source: Node
var _edge_drop_committed := false
var _edge_drop_direction := 0.0
var _platform_navigation: PlatformNavigationRegistry
var _last_target_surface_id: StringName = &""
var _jump_from_surface_id: StringName = &""
var _jump_to_surface_id: StringName = &""
var _jump_launch_x := 0.0
var _jump_landing_x := 0.0
var _jump_direction := 0.0
var _jump_elapsed := 0.0
var _jump_retry_timer := 0.0
var _jump_became_airborne := false
var _target: Node2D

@onready var _body_collision: CollisionShape2D = $BodyCollision
@onready var _hurtbox: Hurtbox = $EnemyHurtbox
@onready var _hurtbox_collision: CollisionShape2D = $EnemyHurtbox/CollisionShape2D
@onready var _attack_hitbox: AttackHitbox = $EnemyAttack
@onready var _attack_collision: CollisionShape2D = $EnemyAttack/CollisionShape2D
@onready var _left_floor_probe: RayCast2D = $LeftFloorProbe
@onready var _right_floor_probe: RayCast2D = $RightFloorProbe
@onready var _left_wall_probe: RayCast2D = $LeftWallProbe
@onready var _right_wall_probe: RayCast2D = $RightWallProbe


func _ready() -> void:
	_spawn_position = global_position
	_resolve_target()
	_configure_from_definition()
	reset()


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	if current_state == State.DEAD:
		return

	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y += _gravity() * delta

	match current_state:
		State.IDLE:
			_update_idle(delta)
		State.PATROL:
			_update_patrol()
		State.CHASE:
			_update_chase()
		State.ATTACK:
			_update_attack(delta)
		State.RETURN_HOME:
			_update_return_home()
		State.HIT:
			_update_hit(delta)
		State.JUMP_CHASE:
			_update_jump_chase(delta)

	move_and_slide()
	if current_state == State.JUMP_CHASE:
		if not is_on_floor():
			_jump_became_airborne = true
		elif _jump_became_airborne:
			if _landed_on_jump_target_surface():
				_finish_jump_chase()
			else:
				_fail_jump_chase()
	if _edge_drop_committed and not was_on_floor and is_on_floor():
		_clear_edge_drop_commitment()


func set_target(target: Node2D) -> void:
	_target = target


func is_engaged_with_target() -> bool:
	if not visible or _target == null or not is_instance_valid(_target):
		return false
	return current_state in [State.CHASE, State.ATTACK, State.HIT, State.JUMP_CHASE]


func _resolve_target() -> void:
	if _target != null and is_instance_valid(_target):
		return
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		_target = get_tree().get_first_node_in_group("player") as Node2D


func _configure_from_definition() -> void:
	if definition == null:
		push_warning("Grounded enemy has no EnemyDefinition; using safe fallbacks.")
		return

	_localize_collision_shape(_body_collision)
	_localize_collision_shape(_hurtbox_collision)
	_localize_collision_shape(_attack_collision)

	if _body_collision.shape is CapsuleShape2D:
		var body_shape := _body_collision.shape as CapsuleShape2D
		body_shape.radius = maxf(definition.body_radius, 1.0)
		body_shape.height = maxf(definition.body_height, body_shape.radius * 2.0)
	_body_collision.position = definition.body_collision_offset

	if _hurtbox_collision.shape is RectangleShape2D:
		var hurtbox_shape := _hurtbox_collision.shape as RectangleShape2D
		hurtbox_shape.size = Vector2(maxf(definition.hurtbox_size.x, 1.0), maxf(definition.hurtbox_size.y, 1.0))
	_hurtbox.position = definition.hurtbox_offset

	var attack := definition.melee_attack
	if attack != null and _attack_collision.shape is RectangleShape2D:
		var attack_shape := _attack_collision.shape as RectangleShape2D
		attack_shape.size = Vector2(maxf(attack.hitbox_size.x, 1.0), maxf(attack.hitbox_size.y, 1.0))

	_left_floor_probe.position.x = -maxf(definition.floor_probe_x, 1.0)
	_right_floor_probe.position.x = maxf(definition.floor_probe_x, 1.0)
	_left_wall_probe.position = Vector2(-maxf(definition.wall_probe_x, 1.0), definition.wall_probe_y)
	_right_wall_probe.position = Vector2(maxf(definition.wall_probe_x, 1.0), definition.wall_probe_y)


func _localize_collision_shape(collision: CollisionShape2D) -> void:
	if collision.shape != null:
		collision.shape = collision.shape.duplicate()


func _update_timers(delta: float) -> void:
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	_jump_retry_timer = maxf(_jump_retry_timer - delta, 0.0)
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		queue_redraw()


func _update_idle(delta: float) -> void:
	velocity.x = 0.0
	if _can_detect_target():
		_target_acquired = true
		current_state = State.CHASE
		return
	_idle_timer = maxf(_idle_timer - delta, 0.0)
	if _idle_timer == 0.0 and is_on_floor():
		current_state = State.PATROL


func _update_patrol() -> void:
	if _can_detect_target():
		_target_acquired = true
		current_state = State.CHASE
		return
	if _at_patrol_bound() or not _has_ground_ahead() or _has_wall_ahead():
		_turn_around()
		return
	velocity.x = _facing_direction * _patrol_speed()


func _update_chase() -> void:
	if not _target_is_on_current_map():
		_target_acquired = false
		_clear_edge_drop_commitment()
		_clear_jump_chase()
		current_state = State.RETURN_HOME
		return

	if _edge_drop_committed:
		_facing_direction = _edge_drop_direction
		velocity.x = _edge_drop_direction * _chase_speed()
		return

	if _update_platform_jump_route():
		return

	_face_target()
	if is_on_floor() and _target_on_same_surface() and _target_in_attack_range() and _attack_cooldown_timer == 0.0 and _attack_definition() != null:
		_start_attack()
		return
	if _has_wall_ahead():
		velocity.x = 0.0
		return
	if not _has_ground_ahead():
		if _can_commit_chase_edge_drop():
			_commit_chase_edge_drop()
		else:
			velocity.x = 0.0
		return
	velocity.x = _facing_direction * _chase_speed()


func _can_commit_chase_edge_drop() -> bool:
	if definition == null or not definition.can_chase_off_edges or not is_on_floor():
		return false
	if _target == null or not is_instance_valid(_target) or _has_wall_ahead():
		return false
	return _target_navigation_position().y - _navigation_feet_position().y >= maxf(definition.chase_edge_drop_min_target_below, 0.0)


func _commit_chase_edge_drop() -> void:
	_edge_drop_committed = true
	_edge_drop_direction = _facing_direction
	velocity.x = _edge_drop_direction * _chase_speed()


func _clear_edge_drop_commitment() -> void:
	_edge_drop_committed = false
	_edge_drop_direction = 0.0


func _resolve_platform_navigation() -> void:
	if _platform_navigation != null and is_instance_valid(_platform_navigation):
		return
	_platform_navigation = get_tree().get_first_node_in_group("platform_navigation_registry") as PlatformNavigationRegistry


func _navigation_feet_position() -> Vector2:
	return global_position


func _target_navigation_position() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		return global_position
	if _target.has_method("get_navigation_feet_position"):
		return _target.call("get_navigation_feet_position") as Vector2
	return _target.global_position


func _current_navigation_surface() -> PlatformNavigationSurface:
	_resolve_platform_navigation()
	if _platform_navigation == null:
		return null
	return _platform_navigation.get_surface_at_position(_navigation_feet_position(), 0.0, 20.0)


func _target_navigation_surface() -> PlatformNavigationSurface:
	_resolve_platform_navigation()
	if _platform_navigation == null or _target == null or not is_instance_valid(_target):
		_last_target_surface_id = &""
		return null
	if _target is CharacterBody2D and (_target as CharacterBody2D).is_on_floor():
		var surface := _platform_navigation.get_surface_at_position(_target_navigation_position(), 0.0, 24.0)
		if surface == null:
			_last_target_surface_id = &""
			return null
		_last_target_surface_id = surface.id
	if _last_target_surface_id == &"":
		return null
	var cached_surface := _platform_navigation.get_surface(_last_target_surface_id)
	if cached_surface == null:
		_last_target_surface_id = &""
	return cached_surface


func _target_on_same_surface() -> bool:
	var current_surface := _current_navigation_surface()
	var target_surface := _target_navigation_surface()
	if current_surface == null or target_surface == null:
		return absf(_target_navigation_position().y - _navigation_feet_position().y) <= 28.0
	return current_surface.id == target_surface.id


func _update_platform_jump_route() -> bool:
	if definition == null or not definition.can_chase_jump or not is_on_floor() or _jump_retry_timer > 0.0:
		return false
	var current_surface := _current_navigation_surface()
	var target_surface := _target_navigation_surface()
	if current_surface == null or target_surface == null or current_surface.id == target_surface.id:
		return false
	var margin := maxf(definition.jump_landing_margin, definition.body_radius + 2.0)
	var route := _platform_navigation.find_nearest_route(current_surface.id, target_surface.id, global_position.x, _target_navigation_position().x, margin)
	var surface_ids: Array = route.get("surface_ids", [])
	if surface_ids.size() < 2:
		return false
	var next_surface := _platform_navigation.get_surface(StringName(surface_ids[1]))
	if next_surface == null:
		return false
	if next_surface.top_y < current_surface.top_y - 8.0:
		return _prepare_platform_jump(current_surface, next_surface)
	return _follow_downward_route(current_surface, next_surface, route)


func _prepare_platform_jump(current_surface: PlatformNavigationSurface, next_surface: PlatformNavigationSurface) -> bool:
	var rise := current_surface.top_y - next_surface.top_y
	if rise <= 0.0 or rise > maxf(definition.jump_max_rise, 0.0):
		return false
	var margin := maxf(definition.jump_landing_margin, definition.body_radius + 2.0)
	var overlap_left := maxf(current_surface.left_x + margin, next_surface.left_x + margin)
	var overlap_right := minf(current_surface.right_x - margin, next_surface.right_x - margin)
	if overlap_left <= overlap_right:
		_jump_launch_x = clampf(global_position.x, overlap_left, overlap_right)
		_jump_landing_x = _jump_launch_x
		_jump_direction = signf(_jump_landing_x - global_position.x)
	else:
		_jump_direction = 1.0 if next_surface.center_x() > current_surface.center_x() else -1.0
		if _jump_direction > 0.0:
			_jump_launch_x = current_surface.right_x - margin
			_jump_landing_x = next_surface.left_x + margin
		else:
			_jump_launch_x = current_surface.left_x + margin
			_jump_landing_x = next_surface.right_x - margin
	_jump_from_surface_id = current_surface.id
	_jump_to_surface_id = next_surface.id

	var launch_delta := _jump_launch_x - global_position.x
	if absf(launch_delta) > maxf(definition.jump_launch_tolerance, 1.0):
		_facing_direction = signf(launch_delta)
		if _has_wall_ahead() or not _has_ground_ahead():
			velocity.x = 0.0
			return true
		velocity.x = _facing_direction * _chase_speed()
		queue_redraw()
		return true
	_start_platform_jump()
	return true


func _start_platform_jump() -> void:
	_cancel_attack()
	_clear_edge_drop_commitment()
	global_position.x = _jump_launch_x
	_jump_direction = signf(_jump_landing_x - _jump_launch_x)
	if _jump_direction != 0.0:
		_facing_direction = _jump_direction
	velocity.x = _jump_direction * maxf(definition.jump_air_speed, 0.0)
	velocity.y = -maxf(definition.jump_takeoff_speed, 0.0)
	_jump_elapsed = 0.0
	_jump_became_airborne = false
	current_state = State.JUMP_CHASE
	queue_redraw()


func _update_jump_chase(delta: float) -> void:
	_jump_elapsed += delta
	var landing_delta := _jump_landing_x - global_position.x
	if absf(landing_delta) <= 6.0:
		velocity.x = move_toward(velocity.x, 0.0, maxf(definition.jump_air_acceleration, 0.0) * delta)
	else:
		var desired_direction := signf(landing_delta)
		velocity.x = move_toward(velocity.x, desired_direction * maxf(definition.jump_air_speed, 0.0), maxf(definition.jump_air_acceleration, 0.0) * delta)
	if _jump_elapsed >= maxf(definition.jump_timeout, 0.1):
		_fail_jump_chase()


func _landed_on_jump_target_surface() -> bool:
	if _jump_to_surface_id == &"":
		return true
	var landed_surface := _current_navigation_surface()
	return landed_surface != null and landed_surface.id == _jump_to_surface_id


func _finish_jump_chase() -> void:
	_clear_jump_chase(false)
	_jump_retry_timer = maxf(definition.jump_retry_delay, 0.0)
	current_state = State.CHASE if _target_is_on_current_map() else State.RETURN_HOME


func _fail_jump_chase() -> void:
	_clear_jump_chase(false)
	_jump_retry_timer = maxf(definition.jump_retry_delay, 0.0)
	current_state = State.CHASE if _target_is_on_current_map() else State.RETURN_HOME


func _clear_jump_chase(clear_retry := true) -> void:
	_jump_from_surface_id = &""
	_jump_to_surface_id = &""
	_jump_launch_x = 0.0
	_jump_landing_x = 0.0
	_jump_direction = 0.0
	_jump_elapsed = 0.0
	_jump_became_airborne = false
	if clear_retry:
		_jump_retry_timer = 0.0


func _follow_downward_route(_current_surface: PlatformNavigationSurface, _next_surface: PlatformNavigationSurface, route: Dictionary) -> bool:
	var transition_x := float(route.get("first_transition_x", global_position.x))
	var drop_direction := float(route.get("first_direction", 0.0))
	var transition_delta := transition_x - global_position.x
	if absf(transition_delta) > maxf(definition.jump_launch_tolerance, 1.0):
		_facing_direction = signf(transition_delta)
	elif drop_direction != 0.0:
		_facing_direction = drop_direction
	else:
		_facing_direction = signf(_target_navigation_position().x - global_position.x)
	if _facing_direction == 0.0:
		return false
	queue_redraw()
	if _has_wall_ahead():
		velocity.x = 0.0
		return true
	if not _has_ground_ahead():
		_edge_drop_committed = true
		_edge_drop_direction = _facing_direction
		velocity.x = _edge_drop_direction * _chase_speed()
		return true
	velocity.x = _facing_direction * _chase_speed()
	return true


func _start_attack() -> void:
	current_state = State.ATTACK
	velocity.x = 0.0
	_attack_elapsed = 0.0
	_attack_hitbox_active = false
	_position_attack_hitbox()
	queue_redraw()


func _update_attack(delta: float) -> void:
	velocity.x = 0.0
	var attack := _attack_definition()
	if attack == null:
		current_state = State.CHASE
		return

	_attack_elapsed += delta
	var active_start := maxf(attack.windup_time, 0.0)
	var active_end := active_start + maxf(attack.active_time, 0.01)
	var total_duration := active_end + maxf(attack.recovery_time, 0.0)
	var should_be_active := _attack_elapsed >= active_start and _attack_elapsed < active_end

	if should_be_active and not _attack_hitbox_active:
		_attack_hitbox.activate(maxi(attack.damage, 1), self, _facing_direction)
		_attack_hitbox_active = true
	elif not should_be_active and _attack_hitbox_active:
		_attack_hitbox.deactivate()
		_attack_hitbox_active = false

	if _attack_elapsed >= total_duration:
		_cancel_attack()
		_attack_cooldown_timer = maxf(attack.cooldown_time, 0.0)
		current_state = State.CHASE if _target_is_on_current_map() else State.RETURN_HOME


func _update_return_home() -> void:
	if _target_acquired and _target_is_on_current_map():
		current_state = State.CHASE
		return
	var home_delta := _spawn_position.x - global_position.x
	if absf(home_delta) <= 6.0:
		global_position.x = _spawn_position.x
		velocity.x = 0.0
		_idle_timer = _idle_time()
		current_state = State.IDLE
		return
	_facing_direction = signf(home_delta)
	if not _has_ground_ahead() or _has_wall_ahead():
		velocity.x = 0.0
		_idle_timer = _idle_time()
		current_state = State.IDLE
		return
	velocity.x = _facing_direction * _return_speed()
	queue_redraw()


func _update_hit(delta: float) -> void:
	_hit_stun_timer = maxf(_hit_stun_timer - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, _knockback_speed() * 4.0 * delta)
	if _hit_stun_timer == 0.0:
		if _death_pending or _health <= 0:
			_enter_dead()
		elif _target_acquired and _target_is_on_current_map():
			current_state = State.CHASE
		elif absf(global_position.x - _spawn_position.x) > _patrol_range():
			current_state = State.RETURN_HOME
		else:
			_idle_timer = _idle_time()
			current_state = State.IDLE


func _can_detect_target() -> bool:
	return _target_in_detection(false)


func _can_keep_target() -> bool:
	return _target_in_detection(true)


func _target_in_detection(expanded: bool) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var size := definition.detection_size if definition != null else Vector2(300.0, 110.0)
	if expanded:
		var margin := definition.lose_target_margin if definition != null else 100.0
		size += Vector2(margin * 2.0, margin)
	var offset := definition.detection_offset if definition != null else Vector2(0.0, -38.0)
	var center := global_position + offset
	return Rect2(center - size * 0.5, size).has_point(_target.global_position)


func _target_is_on_current_map() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_inside_tree() and _target.get_tree() == get_tree()


func _target_in_attack_range() -> bool:
	if _target == null:
		return false
	var attack := _attack_definition()
	if attack == null:
		return false
	var target_position := _target_navigation_position()
	return absf(target_position.x - global_position.x) <= maxf(attack.engage_range, 1.0) and absf(target_position.y - _navigation_feet_position().y) <= 80.0


func _outside_leash() -> bool:
	var leash := definition.leash_range if definition != null else 500.0
	return absf(global_position.x - _spawn_position.x) > maxf(leash, 1.0)


func _face_target() -> void:
	if _target == null or _edge_drop_committed:
		return
	var horizontal_delta := _target.global_position.x - global_position.x
	if absf(horizontal_delta) < 8.0:
		return
	var direction := signf(horizontal_delta)
	if direction != 0.0 and direction != _facing_direction:
		_facing_direction = direction
		queue_redraw()


func _position_attack_hitbox() -> void:
	var attack := _attack_definition()
	if attack == null:
		return
	_attack_hitbox.position = Vector2(absf(attack.hitbox_offset.x) * _facing_direction, attack.hitbox_offset.y)


func _at_patrol_bound() -> bool:
	return global_position.x >= _patrol_right_x if _facing_direction > 0.0 else global_position.x <= _patrol_left_x


func _has_ground_ahead() -> bool:
	return _right_floor_probe.is_colliding() if _facing_direction > 0.0 else _left_floor_probe.is_colliding()


func _has_wall_ahead() -> bool:
	return _right_wall_probe.is_colliding() if _facing_direction > 0.0 else _left_wall_probe.is_colliding()


func _turn_around() -> void:
	_facing_direction *= -1.0
	velocity.x = 0.0
	_idle_timer = _idle_time()
	current_state = State.IDLE
	queue_redraw()


func _resolve_player_source(source: Node, visited: Dictionary = {}, depth := 0) -> Player:
	if source == null or not is_instance_valid(source) or depth > 6 or visited.has(source):
		return null
	visited[source] = true
	if source is Player:
		var direct_player := source as Player
		return direct_player if direct_player.is_inside_tree() and direct_player.get_tree() == get_tree() else null
	if source.has_method("get_credit_owner"):
		var credit_owner := source.get_credit_owner() as Node
		var credited_player := _resolve_player_source(credit_owner, visited, depth + 1)
		if credited_player != null:
			return credited_player
	if source.has_method("get_source"):
		var nested_source := source.get_source() as Node
		return _resolve_player_source(nested_source, visited, depth + 1)
	return null


func receive_hit(amount: int, source: Node, hit_direction: float) -> bool:
	if current_state == State.DEAD or _death_pending:
		return false
	var attacking_player := _resolve_player_source(source)
	if attacking_player != null:
		_target = attacking_player
		_target_acquired = true
		_last_target_surface_id = &""
	_clear_edge_drop_commitment()
	_clear_jump_chase()
	_cancel_attack()
	_health = maxi(_health - amount, 0)
	_hit_flash_timer = _hit_flash_time()
	_hit_stun_timer = _hit_stun_time()
	velocity.x = signf(hit_direction) * _knockback_speed()
	if _health <= 0:
		_death_pending = true
		_lethal_source = source
	current_state = State.HIT
	queue_redraw()
	return true


func _cancel_attack() -> void:
	_attack_hitbox.deactivate()
	_attack_hitbox_active = false
	_attack_elapsed = 0.0


func _enter_dead() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	_clear_edge_drop_commitment()
	_clear_jump_chase()
	_cancel_attack()
	_hurtbox.enabled = false
	_body_collision.set_deferred("disabled", true)
	_hurtbox_collision.set_deferred("disabled", true)
	if not _drops_emitted:
		_drops_emitted = true
		if definition != null and not definition.drop_rules.is_empty():
			drop_requested.emit(self, definition.drop_rules)
		if definition != null and not definition.equipment_drop_rules.is_empty():
			equipment_drop_requested.emit(self, definition.equipment_drop_rules)
	if not _defeated_emitted:
		_defeated_emitted = true
		defeated.emit(self, _lethal_source)
	queue_redraw()


func reset() -> void:
	visible = true
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_health = _max_health()
	_facing_direction = signf(start_facing_direction) if start_facing_direction != 0.0 else -1.0
	_patrol_left_x = _spawn_position.x - _patrol_range()
	_patrol_right_x = _spawn_position.x + _patrol_range()
	_idle_timer = _idle_time()
	_hit_stun_timer = 0.0
	_hit_flash_timer = 0.0
	_attack_cooldown_timer = 0.0
	_target_acquired = false
	_drops_emitted = false
	_defeated_emitted = false
	_death_pending = false
	_lethal_source = null
	_clear_edge_drop_commitment()
	_clear_jump_chase()
	_last_target_surface_id = &""
	_cancel_attack()
	current_state = State.IDLE
	_hurtbox.enabled = true
	_body_collision.set_deferred("disabled", false)
	_hurtbox_collision.set_deferred("disabled", false)
	queue_redraw()


func _attack_definition() -> EnemyMeleeAttackDefinition:
	return definition.melee_attack if definition != null else null


func _max_health() -> int:
	return maxi(definition.max_health, 1) if definition != null else 10


func _gravity() -> float:
	return maxf(definition.gravity, 0.0) if definition != null else 1650.0


func _patrol_speed() -> float:
	return maxf(definition.patrol_speed, 0.0) if definition != null else 70.0


func _chase_speed() -> float:
	return maxf(definition.chase_speed, 0.0) if definition != null else 115.0


func _return_speed() -> float:
	return maxf(definition.return_speed, 0.0) if definition != null else 90.0


func _patrol_range() -> float:
	return maxf(definition.patrol_range, 0.0) if definition != null else 180.0


func _idle_time() -> float:
	return maxf(definition.idle_time, 0.0) if definition != null else 0.4


func _hit_stun_time() -> float:
	return maxf(definition.hit_stun_time, 0.0) if definition != null else 0.18


func _hit_flash_time() -> float:
	return maxf(definition.hit_flash_time, 0.0) if definition != null else 0.12


func _knockback_speed() -> float:
	return maxf(definition.knockback_speed, 0.0) if definition != null else 120.0


func _draw() -> void:
	_draw_health_bar()
	if current_state == State.DEAD:
		_draw_dead_body()
	else:
		_draw_live_body()


func _draw_health_bar() -> void:
	var ratio := float(_health) / float(_max_health())
	var scale := _visual_scale()
	var bar_width := 54.0 * scale
	var bar_y := -86.0 * scale
	draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width, 8.0), Color("301d24"), true)
	draw_rect(Rect2(-bar_width * 0.5 + 2.0, bar_y + 2.0, (bar_width - 4.0) * ratio, 4.0), Color("74c365"), true)


func _draw_live_body() -> void:
	var scale := _visual_scale()
	var body_color := _flash_color() if _hit_flash_timer > 0.0 else _body_color()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale, scale))
	draw_rect(Rect2(-21, -58, 42, 48), body_color, true)
	draw_circle(Vector2(0, -60), 19.0, body_color)
	draw_rect(Rect2(-19, -10, 14, 10), _trim_color(), true)
	draw_rect(Rect2(5, -10, 14, 10), _trim_color(), true)
	if _armor_color().a > 0.0:
		draw_rect(Rect2(-23, -53, 46, 22), _armor_color(), true)
		draw_rect(Rect2(-17, -76, 34, 10), _armor_color(), true)
		draw_line(Vector2(0, -53), Vector2(0, -31), _trim_color(), 3.0)
	draw_circle(Vector2(7 * _facing_direction, -63), 3.0, _eye_color())
	draw_circle(Vector2(8 * _facing_direction, -63), 1.4, _pupil_color())
	if current_state == State.ATTACK:
		var attack_x := 30.0 * _facing_direction
		draw_circle(Vector2(attack_x, -34), 9.0, _attack_tell_color())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_dead_body() -> void:
	var scale := _visual_scale()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale, scale))
	draw_rect(Rect2(-30, -18, 60, 18), _dead_color(), true)
	draw_circle(Vector2(20 * _facing_direction, -18), 13.0, _dead_color())
	if _armor_color().a > 0.0:
		draw_rect(Rect2(-20, -21, 36, 9), _armor_color(), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _visual_scale() -> float:
	return maxf(definition.visual_scale, 0.25) if definition != null else 1.0


func _body_color() -> Color:
	return definition.body_color if definition != null else Color("a45c88")


func _flash_color() -> Color:
	return definition.flash_color if definition != null else Color("fff1a8")


func _trim_color() -> Color:
	return definition.trim_color if definition != null else Color("493548")


func _eye_color() -> Color:
	return definition.eye_color if definition != null else Color("f4e7d3")


func _pupil_color() -> Color:
	return definition.pupil_color if definition != null else Color("251f29")


func _attack_tell_color() -> Color:
	return definition.attack_tell_color if definition != null else Color("df784f")


func _armor_color() -> Color:
	return definition.armor_color if definition != null else Color(0.0, 0.0, 0.0, 0.0)


func _dead_color() -> Color:
	return definition.dead_color if definition != null else Color("574957")
