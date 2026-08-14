class_name UIStyle
extends RefCounted

const TEXT_PRIMARY := Color("edf4ef")
const TEXT_MUTED := Color("a8bbb7")
const TEXT_DISABLED := Color("70817f")
const TEXT_WARNING := Color("f0c66c")
const TEXT_DANGER := Color("ff816f")
const TEXT_SUCCESS := Color("8fd3a2")
const ACCENT := Color("e2b957")
const ACCENT_SOFT := Color("6f623b")
const PAGE_BG := Color("0b1720")
const PANEL_BG := Color("101f29e8")
const PANEL_BG_ELEVATED := Color("172b35f7")
const PANEL_BORDER := Color("42606a")
const HEADER_BG := Color("1d3b43")
const DETAIL_BG := Color("12242df5")
const SLOT_BG := Color("152831")
const SLOT_SELECTED := Color("334b4e")
const SLOT_HOVER := Color("243b43")
const BAR_HEALTH := Color("58b86b")
const BAR_HEALTH_BACK := Color("351d24f2")
const BAR_EXPERIENCE := Color("559ddd")
const BAR_EXPERIENCE_BACK := Color("172334f2")


static func style_box(
	background: Color,
	border: Color = Color.TRANSPARENT,
	border_width := 0,
	corner_radius := 6,
	content_margin := 0.0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin
	return style


static func panel_style() -> StyleBoxFlat:
	return style_box(PANEL_BG, PANEL_BORDER, 1, 8)


static func elevated_panel_style() -> StyleBoxFlat:
	return style_box(PANEL_BG_ELEVATED, PANEL_BORDER, 1, 8)


static func panel_header_style() -> StyleBoxFlat:
	return style_box(HEADER_BG, ACCENT_SOFT, 1, 6)


static func detail_panel_style() -> StyleBoxFlat:
	return style_box(DETAIL_BG, Color("36515a"), 1, 6)


static func modal_scrim_style() -> StyleBoxFlat:
	return style_box(Color("05090dcc"), Color.TRANSPARENT, 0, 0)


static func modal_panel_style() -> StyleBoxFlat:
	return style_box(PANEL_BG_ELEVATED, ACCENT_SOFT, 2, 10, 4.0)


static func button_style() -> StyleBoxFlat:
	return style_box(Color("1b313b"), Color("46616a"), 1, 5, 7.0)


static func button_hover_style() -> StyleBoxFlat:
	return style_box(Color("29454e"), Color("789097"), 1, 5, 7.0)


static func button_pressed_style() -> StyleBoxFlat:
	return style_box(Color("10242d"), ACCENT, 2, 5, 7.0)


static func button_disabled_style() -> StyleBoxFlat:
	return style_box(Color("17242a"), Color("304148"), 1, 5, 7.0)


static func primary_button_style() -> StyleBoxFlat:
	return style_box(Color("765f2b"), ACCENT, 1, 5, 7.0)


static func primary_button_hover_style() -> StyleBoxFlat:
	return style_box(Color("927638"), Color("f2d17c"), 1, 5, 7.0)


static func danger_button_style() -> StyleBoxFlat:
	return style_box(Color("572a2c"), Color("a95450"), 1, 5, 7.0)


static func danger_button_hover_style() -> StyleBoxFlat:
	return style_box(Color("753537"), TEXT_DANGER, 1, 5, 7.0)


static func slot_style() -> StyleBoxFlat:
	return style_box(SLOT_BG, Color("354e57"), 1, 5, 5.0)


static func slot_hover_style() -> StyleBoxFlat:
	return style_box(SLOT_HOVER, Color("708991"), 1, 5, 5.0)


static func slot_selected_style() -> StyleBoxFlat:
	return style_box(SLOT_SELECTED, ACCENT, 2, 5, 5.0)


static func apply_button(button: Button, role: StringName = &"default") -> void:
	var normal := button_style()
	var hover := button_hover_style()
	if role == &"primary":
		normal = primary_button_style()
		hover = primary_button_hover_style()
	elif role == &"danger":
		normal = danger_button_style()
		hover = danger_button_hover_style()
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", button_pressed_style())
	button.add_theme_stylebox_override("disabled", button_disabled_style())
	button.add_theme_stylebox_override("focus", slot_selected_style())
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", ACCENT)
	button.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	button.add_theme_font_size_override("font_size", 16)


static func apply_runtime_row(button: Button, selected: bool, text_color := TEXT_PRIMARY) -> void:
	apply_button(button)
	button.add_theme_stylebox_override("normal", slot_selected_style() if selected else slot_style())
	button.add_theme_color_override("font_color", ACCENT if selected else text_color)


static func apply_backpack_slot(button: Button, selected: bool, quality_color: Color) -> void:
	apply_runtime_row(button, selected, quality_color)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_outline_color", Color("071015"))
	button.add_theme_constant_override("outline_size", 2)


static func apply_panel_container(panel: PanelContainer, elevated := false) -> void:
	panel.add_theme_stylebox_override("panel", elevated_panel_style() if elevated else panel_style())


static func apply_line_edit(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override("normal", style_box(Color("0f2029"), PANEL_BORDER, 1, 5, 8.0))
	line_edit.add_theme_stylebox_override("focus", style_box(Color("142832"), ACCENT, 2, 5, 8.0))
	line_edit.add_theme_color_override("font_color", TEXT_PRIMARY)
	line_edit.add_theme_color_override("font_placeholder_color", TEXT_DISABLED)
	line_edit.add_theme_color_override("caret_color", ACCENT)
	line_edit.add_theme_font_size_override("font_size", 16)


static func apply_option_button(option_button: OptionButton) -> void:
	apply_button(option_button)


static func apply_message(label: Label, failed: bool) -> void:
	label.modulate = TEXT_DANGER if failed else TEXT_SUCCESS
