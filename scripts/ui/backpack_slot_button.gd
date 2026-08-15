class_name BackpackSlotButton
extends Button

var quantity_label: Label
var backpack_category: StringName = &""
var slot_index := -1
var has_item := false
var drop_handler: Callable


func _ready() -> void:
	if quantity_label != null:
		return
	quantity_label = Label.new()
	quantity_label.name = "Quantity"
	quantity_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	quantity_label.offset_left = 4.0
	quantity_label.offset_top = -18.0
	quantity_label.offset_right = 45.0
	quantity_label.offset_bottom = -2.0
	quantity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quantity_label.add_theme_font_size_override("font_size", 11)
	quantity_label.add_theme_color_override("font_color", Color.WHITE)
	quantity_label.add_theme_color_override("font_outline_color", Color("071015"))
	quantity_label.add_theme_constant_override("outline_size", 2)
	add_child(quantity_label)


func set_quantity(quantity: int) -> void:
	if quantity_label == null:
		_ready()
	quantity_label.text = str(quantity) if quantity > 0 else ""
	quantity_label.visible = quantity > 0


func configure_drag(category: StringName, index: int, occupied: bool, handler: Callable) -> void:
	backpack_category = category
	slot_index = index
	has_item = occupied
	drop_handler = handler
	mouse_default_cursor_shape = Control.CURSOR_DRAG if occupied else Control.CURSOR_ARROW


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not has_item or backpack_category.is_empty() or slot_index < 0:
		return null
	var preview := Label.new()
	preview.text = text
	preview.custom_minimum_size = custom_minimum_size
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.modulate = Color(1.0, 1.0, 1.0, 0.85)
	set_drag_preview(preview)
	return {
		"type": "backpack_slot",
		"category": String(backpack_category),
		"slot_index": slot_index,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not drop_handler.is_valid():
		return false
	var payload := data as Dictionary
	return (
		String(payload.get("type", "")) == "backpack_slot"
		and StringName(String(payload.get("category", ""))) == backpack_category
		and int(payload.get("slot_index", -1)) >= 0
		and int(payload.get("slot_index", -1)) != slot_index
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(Vector2.ZERO, data):
		return
	var payload := data as Dictionary
	drop_handler.call(int(payload.get("slot_index", -1)), slot_index)
