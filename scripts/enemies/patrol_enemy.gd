extends CharacterBody2D

enum State {
	IDLE,
	PATROL,
	HIT,
	DEAD,
}

@export var max_health := 10
@export var patrol_speed := 70.0
@export var patrol_range := 180.0
@export var gravity := 1650.0
@export var idle_time := 0.4
@export var hit_stun_time := 0.18
@export var hit_flash_time := 0.12
@export var knockback_speed := 120.0

var current_state := State.IDLE
var _health := 10
var _spawn_position := Vector2.ZERO
var _patrol_left_x := 0.0
var _patrol_right_x := 0.0
var _facing_direction := -1.0
var _idle_timer := 0.0
var _hit_stun_timer := 0.0
var _hit_flash_timer := 0.0

@onready var _body_collision: CollisionShape2D = $BodyCollision
@onready var _hurtbox: Hurtbox = $Hurtbox
@onready var _hurtbox_collision: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var _left_floor_probe: RayCast2D = $LeftFloorProbe
@onready var _right_floor_probe: RayCast2D = $RightFloorProbe
@onready var _left_wall_probe: RayCast2D = $LeftWallProbe
@onready var _right_wall_probe: RayCast2D = $RightWallProbe


func _ready() -> void:
	_spawn_position = global_position
	_patrol_left_x = _spawn_position.x - patrol_range
	_patrol_right_x = _spawn_position.x + patrol_range
	reset()


func _physics_process(delta: float) -> void:
	_update_flash(delta)
	if current_state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	match current_state:
		State.IDLE:
			_update_idle(delta)
		State.PATROL:
			_update_patrol()
		State.HIT:
			_update_hit(delta)

	move_and_slide()


func _update_idle(delta: float) -> void:
	velocity.x = 0.0
	_idle_timer = maxf(_idle_timer - delta, 0.0)
	if _idle_timer == 0.0 and is_on_floor():
		current_state = State.PATROL


func _update_patrol() -> void:
	if _at_patrol_bound() or not _has_ground_ahead() or _has_wall_ahead():
		_turn_around()
		return
	velocity.x = _facing_direction * patrol_speed


func _update_hit(delta: float) -> void:
	_hit_stun_timer = maxf(_hit_stun_timer - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, knockback_speed * 4.0 * delta)
	if _hit_stun_timer == 0.0:
		if _health <= 0:
			_enter_dead()
		else:
			_idle_timer = idle_time
			current_state = State.IDLE


func _update_flash(delta: float) -> void:
	if _hit_flash_timer <= 0.0:
		return
	_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
	queue_redraw()


func _at_patrol_bound() -> bool:
	return global_position.x >= _patrol_right_x if _facing_direction > 0.0 else global_position.x <= _patrol_left_x


func _has_ground_ahead() -> bool:
	return _right_floor_probe.is_colliding() if _facing_direction > 0.0 else _left_floor_probe.is_colliding()


func _has_wall_ahead() -> bool:
	return _right_wall_probe.is_colliding() if _facing_direction > 0.0 else _left_wall_probe.is_colliding()


func _turn_around() -> void:
	_facing_direction *= -1.0
	velocity.x = 0.0
	_idle_timer = idle_time
	current_state = State.IDLE
	queue_redraw()


func receive_hit(amount: int, _source: Node, hit_direction: float) -> void:
	if current_state == State.DEAD:
		return

	_health = maxi(_health - amount, 0)
	_hit_flash_timer = hit_flash_time
	_hit_stun_timer = hit_stun_time
	velocity.x = signf(hit_direction) * knockback_speed
	current_state = State.HIT
	queue_redraw()


func _enter_dead() -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO
	_hurtbox.enabled = false
	_body_collision.set_deferred("disabled", true)
	_hurtbox_collision.set_deferred("disabled", true)
	queue_redraw()


func reset() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_health = max_health
	_facing_direction = -1.0
	_idle_timer = idle_time
	_hit_stun_timer = 0.0
	_hit_flash_timer = 0.0
	current_state = State.IDLE
	_hurtbox.enabled = true
	_body_collision.set_deferred("disabled", false)
	_hurtbox_collision.set_deferred("disabled", false)
	queue_redraw()


func _draw() -> void:
	_draw_health_bar()
	if current_state == State.DEAD:
		_draw_dead_body()
	else:
		_draw_live_body()


func _draw_health_bar() -> void:
	var ratio := float(_health) / float(max_health)
	draw_rect(Rect2(-27, -86, 54, 8), Color("301d24"), true)
	draw_rect(Rect2(-25, -84, 50 * ratio, 4), Color("74c365"), true)


func _draw_live_body() -> void:
	var body_color := Color("fff1a8") if _hit_flash_timer > 0.0 else Color("a45c88")
	draw_rect(Rect2(-21, -58, 42, 48), body_color, true)
	draw_circle(Vector2(0, -60), 19.0, body_color)
	draw_rect(Rect2(-19, -10, 14, 10), Color("493548"), true)
	draw_rect(Rect2(5, -10, 14, 10), Color("493548"), true)
	draw_circle(Vector2(7 * _facing_direction, -63), 3.0, Color("f4e7d3"))
	draw_circle(Vector2(8 * _facing_direction, -63), 1.4, Color("251f29"))


func _draw_dead_body() -> void:
	draw_rect(Rect2(-30, -18, 60, 18), Color("574957"), true)
	draw_circle(Vector2(20 * _facing_direction, -18), 13.0, Color("574957"))
