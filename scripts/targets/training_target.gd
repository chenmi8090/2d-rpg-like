extends Node2D

@export var flash_time := 0.12

var _hit_count := 0
var _flash_timer := 0.0
var _hit_direction := 1.0

@onready var _label: Label = $HitCountLabel


func _ready() -> void:
	_update_label()
	queue_redraw()


func _process(delta: float) -> void:
	if _flash_timer <= 0.0:
		return
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	queue_redraw()


func receive_hit(amount: int, _source: Node, hit_direction: float) -> void:
	_hit_count += amount
	_flash_timer = flash_time
	_hit_direction = hit_direction
	_update_label()
	queue_redraw()


func reset() -> void:
	_hit_count = 0
	_flash_timer = 0.0
	_update_label()
	queue_redraw()


func _update_label() -> void:
	_label.text = "命中：%d" % _hit_count


func _draw() -> void:
	var hit_offset := Vector2(_hit_direction * 5.0, 0.0) if _flash_timer > 0.0 else Vector2.ZERO
	var body_color := Color("fff06a") if _flash_timer > 0.0 else Color("8dbf62")
	draw_rect(Rect2(hit_offset + Vector2(-22, -72), Vector2(44, 72)), body_color, true)
	draw_circle(hit_offset + Vector2(0, -50), 13.0, Color("c94f4f"))
	draw_circle(hit_offset + Vector2(0, -50), 7.0, Color("f4d35e"))
	draw_rect(Rect2(-6, 0, 12, 28), Color("6d4c35"), true)
	draw_rect(Rect2(-28, 26, 56, 10), Color("6d4c35"), true)
