extends Node2D

var _crouched := false
var _attacking := false
var _attack_type := 0
var _attack_weapon_type: StringName = &"sword"
var _attack_visual_key: StringName = &""
var _attack_phase := 0
var _attack_hit_feedback_timer := 0.0
var _facing_direction := 1.0

const ATTACK_PHASE_NONE := 0
const ATTACK_PHASE_STARTUP := 1
const ATTACK_PHASE_ACTIVE := 2
const ATTACK_PHASE_RECOVERY := 3
const ATTACK_HIT_FEEDBACK_TIME := 0.10


func set_attack(attacking: bool, attack_type: int, weapon_type: StringName = &"sword", visual_key: StringName = &"") -> void:
	if _attacking == attacking and _attack_type == attack_type and _attack_weapon_type == weapon_type and _attack_visual_key == visual_key:
		return
	_attacking = attacking
	_attack_type = attack_type
	_attack_weapon_type = weapon_type
	_attack_visual_key = visual_key
	if not attacking:
		_attack_phase = ATTACK_PHASE_NONE
		_attack_hit_feedback_timer = 0.0
	queue_redraw()


func set_attack_phase(phase: int) -> void:
	if _attack_phase == phase:
		return
	_attack_phase = phase
	queue_redraw()


func show_attack_hit_feedback() -> void:
	_attack_hit_feedback_timer = ATTACK_HIT_FEEDBACK_TIME
	queue_redraw()


func _process(delta: float) -> void:
	if _attack_hit_feedback_timer <= 0.0:
		return
	_attack_hit_feedback_timer = maxf(_attack_hit_feedback_timer - delta, 0.0)
	queue_redraw()


func set_facing_direction(direction: float) -> void:
	if direction == 0.0 or direction == _facing_direction:
		return
	_facing_direction = direction
	queue_redraw()


func set_crouched(crouched: bool) -> void:
	if _crouched == crouched:
		return
	_crouched = crouched
	queue_redraw()


func _draw() -> void:
	# Simple original placeholder poses keep the prototype asset-free.
	if _crouched:
		_draw_crouched()
	else:
		_draw_standing()


func _draw_standing() -> void:
	draw_circle(Vector2(0, -34), 13.0, Color("f7d9b5"))
	draw_rect(Rect2(-16, -21, 32, 34), Color("e85d4a"), true)
	draw_rect(Rect2(-15, 13, 11, 19), Color("25465f"), true)
	draw_rect(Rect2(4, 13, 11, 19), Color("25465f"), true)
	draw_rect(Rect2(-25, -17, 10, 28), Color("f7d9b5"), true)
	draw_rect(Rect2(15, -17, 10, 28), Color("f7d9b5"), true)
	if _attacking:
		_draw_attack_cue()
	draw_circle(Vector2(-5, -37), 1.8, Color("20313d"))
	draw_circle(Vector2(5, -37), 1.8, Color("20313d"))


func _draw_attack_cue() -> void:
	if _attack_weapon_type == &"staff" or _attack_visual_key == &"staff":
		_draw_staff_attack()
	else:
		_draw_sword_attack()


func _draw_sword_attack() -> void:
	var heavy := _attack_type == 1
	var direction := 1.0 if _facing_direction > 0.0 else -1.0
	var phase_scale := 0.62
	var phase_alpha := 0.48
	if _attack_phase == ATTACK_PHASE_ACTIVE:
		phase_scale = 1.0
		phase_alpha = 1.0
	elif _attack_phase == ATTACK_PHASE_RECOVERY:
		phase_scale = 0.82
		phase_alpha = 0.55
	var length := (58.0 if heavy else 42.0) * phase_scale
	var y := -17.0 if heavy else -22.0
	var hand := Vector2(18.0 * direction, -12.0)
	var tip := Vector2((18.0 + length) * direction, y)
	var blade_color := Color("fff7cf") if _attack_hit_feedback_timer > 0.0 else Color("d9edf4")
	blade_color.a = phase_alpha
	var edge_color := Color("f0b85f") if heavy else Color("c9eef5")
	edge_color.a = phase_alpha
	draw_line(hand, tip, blade_color, 7.0 if heavy else 5.0)
	draw_line(hand, tip, Color(0.44, 0.53, 0.57, phase_alpha), 2.0)
	draw_circle(tip, 7.0 if _attack_hit_feedback_timer > 0.0 else 6.0 if heavy else 4.0, edge_color)
	if _attack_phase == ATTACK_PHASE_ACTIVE:
		var arc_radius := 68.0 if heavy else 52.0
		draw_arc(hand, arc_radius, -0.75 if direction > 0.0 else PI - 0.75, 0.25 if direction > 0.0 else PI + 0.25, 12, edge_color, 4.0 if heavy else 2.5)


func _draw_staff_attack() -> void:
	var heavy := _attack_type == 1
	var direction := 1.0 if _facing_direction > 0.0 else -1.0
	var start := Vector2(13.0 * direction, 4.0)
	var tip := Vector2((52.0 if heavy else 44.0) * direction, -29.0 if heavy else -24.0)
	var phase_scale := 0.65
	var phase_alpha := 0.5
	if _attack_phase == ATTACK_PHASE_ACTIVE:
		phase_scale = 1.0
		phase_alpha = 1.0
	elif _attack_phase == ATTACK_PHASE_RECOVERY:
		phase_scale = 0.76
		phase_alpha = 0.5
	var orb_radius := (12.0 if heavy else 8.0) * phase_scale
	var orb_color := Color("fff7cf") if _attack_hit_feedback_timer > 0.0 else Color("9f6df4") if heavy else Color("58c9ef")
	orb_color.a = phase_alpha
	draw_line(start, tip, Color(0.46, 0.33, 0.24, phase_alpha), 6.0)
	draw_circle(tip, orb_radius, orb_color)
	draw_circle(tip, maxf(orb_radius * 0.42, 2.0), Color(1.0, 1.0, 1.0, phase_alpha * 0.9))
	if _attack_phase == ATTACK_PHASE_ACTIVE:
		draw_arc(tip, orb_radius + 6.0, 0.0, TAU, 16, orb_color, 2.5)


func _draw_attack_arm() -> void:
	var heavy := _attack_type == 1
	var arm_length := 42.0 if heavy else 30.0
	var arm_height := 14.0 if heavy else 10.0
	var fist_radius := 10.0 if heavy else 7.0
	var y_position := -13.0 if heavy else -18.0
	var impact_color := Color("e06b45") if heavy else Color("f7d9b5")

	if _facing_direction > 0.0:
		draw_rect(Rect2(16, y_position, arm_length, arm_height), Color("f7d9b5"), true)
		draw_circle(Vector2(19 + arm_length, y_position + arm_height / 2.0), fist_radius, impact_color)
	else:
		draw_rect(Rect2(-16 - arm_length, y_position, arm_length, arm_height), Color("f7d9b5"), true)
		draw_circle(Vector2(-19 - arm_length, y_position + arm_height / 2.0), fist_radius, impact_color)


func _draw_crouched() -> void:
	var facing := _facing_direction
	draw_circle(Vector2(8 * facing, -12), 12.0, Color("f7d9b5"))
	draw_rect(Rect2(-16, -9, 30, 24), Color("e85d4a"), true)
	if facing > 0.0:
		draw_rect(Rect2(-14, 15, 25, 10), Color("25465f"), true)
		draw_rect(Rect2(8, 23, 20, 9), Color("25465f"), true)
		draw_rect(Rect2(-23, -5, 10, 20), Color("f7d9b5"), true)
	else:
		draw_rect(Rect2(-11, 15, 25, 10), Color("25465f"), true)
		draw_rect(Rect2(-28, 23, 20, 9), Color("25465f"), true)
		draw_rect(Rect2(13, -5, 10, 20), Color("f7d9b5"), true)
	draw_circle(Vector2(11 * facing, -15), 1.8, Color("20313d"))
