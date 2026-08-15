class_name SkillDragButton
extends Button

var skill_id: StringName = &""
var drag_enabled := false
var drag_label := ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_enabled or skill_id == &"":
		return null
	var preview := Label.new()
	preview.text = drag_label
	preview.add_theme_font_size_override("font_size", 14)
	preview.add_theme_color_override("font_color", Color("fff0ad"))
	set_drag_preview(preview)
	return {
		"kind": &"skill_quickbar",
		"skill_id": skill_id,
		"source_slot": -1,
	}
