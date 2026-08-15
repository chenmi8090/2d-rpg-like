extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MATERIAL_PICKUP_SCENE := preload("res://scenes/items/material_pickup.tscn")
const EQUIPMENT_PICKUP_SCENE := preload("res://scenes/items/equipment_pickup.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_stackable_inventory_and_capacity()
	await _test_backpack_drag_reordering()
	await _test_backpack_ui()
	_test_save_migration()
	if _failures.is_empty():
		print("Issue #17 categorized backpack tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_stackable_inventory_and_capacity() -> void:
	var definition := DefinitionRegistry.get_stackable_item(&"stardust_fragment")
	_expect(definition != null and definition.is_valid(), "星尘碎片具有有效通用道具定义")
	_expect(definition.category == BackpackCategory.OTHER, "星尘碎片属于其他分类")
	_expect(definition.stack_limit == 99, "星尘碎片单格上限为 99")

	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await process_frame
	for category in BackpackCategory.ALL:
		_expect(player.get_backpack_capacity(category) == 40, "%s 默认拥有 40 格" % BackpackCategory.display_name(category))
	var collected := player.collect_stackable_item(&"stardust_fragment", 120)
	_expect(collected.ok and int(collected.accepted) == 120, "通用库存可以完整接收已注册道具")
	var stacks := player.get_stackable_item_slots(BackpackCategory.OTHER)
	_expect(stacks.size() == 2, "超过单格上限后拆分到下一格")
	_expect(int(stacks[0].quantity) == 99 and int(stacks[1].quantity) == 21, "堆叠数量按上限正确拆分")
	_expect(player.get_stackable_item_quantity(&"stardust_fragment") == 120, "查询返回所有格子的总数量")
	_expect(not player.collect_stackable_item(&"unknown_item", 1).ok, "未注册道具不能进入库存")
	_expect(not player.remove_stackable_item(&"stardust_fragment", 121).ok, "数量不足时扣除失败")
	_expect(player.remove_stackable_item(&"stardust_fragment", 100).ok, "库存充足时可以安全扣除")
	stacks = player.get_stackable_item_slots(BackpackCategory.OTHER)
	_expect(stacks.size() == 1 and int(stacks[0].quantity) == 20, "扣除后释放空堆叠格")

	var fill_result := player.collect_stackable_item(&"stardust_fragment", 99 * 40)
	_expect(int(fill_result.remaining) == 20, "其他栏满时返回未接收数量")
	_expect(player.get_stackable_item_slots(BackpackCategory.OTHER).size() == 40, "其他栏最多占用当前 40 格容量")
	_expect(player.remove_stackable_item(&"stardust_fragment", 20).ok, "部分拾取测试预留单格空间")
	var pickup := MATERIAL_PICKUP_SCENE.instantiate() as MaterialPickup
	root.add_child(pickup)
	pickup.initialize(definition, 50, Vector2.ZERO)
	pickup._player = player
	pickup._collect()
	_expect(pickup.amount == 30 and pickup._active, "部分拾取后地面保留剩余数量")
	_expect(player.get_stackable_item_quantity(&"stardust_fragment") == 99 * 40, "部分拾取只收入可容纳数量")
	pickup.queue_free()

	var sword := DefinitionRegistry.get_equipment(&"traveler_sword")
	for _index in 40:
		_expect(player.collect_equipment(player.create_template_equipment(sword)), "装备栏未满时可以收取装备")
	var rejected_equipment := player.create_template_equipment(sword)
	_expect(not player.collect_equipment(rejected_equipment), "装备栏满时拒绝新装备")
	var equipment_pickup := EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	root.add_child(equipment_pickup)
	equipment_pickup.initialize(rejected_equipment, Vector2.ZERO)
	equipment_pickup._player = player
	equipment_pickup._collect()
	_expect(equipment_pickup._active and equipment_pickup.instance == rejected_equipment, "装备满包时地面拾取物保持存在")
	equipment_pickup.queue_free()
	_expect(not player.unequip_to_inventory(EquipmentSlot.WEAPON), "装备栏满时拒绝卸下已穿戴装备")
	_expect(player.get_equipped_item(EquipmentSlot.WEAPON) != null, "卸下失败时装备保持穿戴")
	var inventory_item := player.get_equipment_inventory()[0]
	_expect(player.equip_inventory_item(inventory_item.instance_id), "从满背包换装时可复用释放的格子")
	_expect(player.get_equipment_inventory().size() == 40, "满背包换装后装备数量保持稳定")
	player.queue_free()
	await process_frame


func _test_backpack_drag_reordering() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await process_frame
	var sword := DefinitionRegistry.get_equipment(&"traveler_sword")
	var first_equipment := player.create_template_equipment(sword)
	var second_equipment := player.create_template_equipment(sword)
	_expect(player.collect_equipment(first_equipment) and player.collect_equipment(second_equipment), "拖拽测试装备可以进入背包")
	_expect(player.move_equipment_inventory_slot(0, 15), "装备可以拖到指定空格")
	var equipment_slots := player.get_equipment_inventory_slots()
	_expect(equipment_slots[0] == null and equipment_slots[15] == first_equipment, "装备拖到空格后保留具体栏位")
	_expect(player.move_equipment_inventory_slot(15, 1), "装备可以与已占用栏位交换")
	equipment_slots = player.get_equipment_inventory_slots()
	_expect(equipment_slots[1] == first_equipment and equipment_slots[15] == second_equipment, "装备交换不丢失任一实例")

	player.collect_stackable_item(&"stardust_fragment", 120)
	_expect(player.move_stackable_item_slot(BackpackCategory.OTHER, 1, 12), "堆叠道具可以拖到指定空格")
	var stack_slots := player.get_stackable_item_slots(BackpackCategory.OTHER, true)
	_expect(stack_slots[1].is_empty() and int(stack_slots[12].quantity) == 21, "堆叠拖到空格后保留具体栏位")
	player.remove_stackable_item(&"stardust_fragment", 50)
	_expect(player.move_stackable_item_slot(BackpackCategory.OTHER, 12, 0), "同类堆叠可以通过拖拽合并")
	stack_slots = player.get_stackable_item_slots(BackpackCategory.OTHER, true)
	_expect(int(stack_slots[0].quantity) == 70 and stack_slots[12].is_empty(), "合并数量正确且释放来源格")
	var backpack_snapshot := player.get_backpack_snapshot()
	var saved_equipment_slots := backpack_snapshot.equipment_slots as Array
	var saved_other_slots := (backpack_snapshot.stacks as Dictionary).other as Array
	_expect(String(saved_equipment_slots[1]) == first_equipment.instance_id and String(saved_equipment_slots[15]) == second_equipment.instance_id, "装备拖拽位置写入存档快照")
	_expect(int((saved_other_slots[0] as Dictionary).quantity) == 70 and (saved_other_slots[12] as Dictionary).is_empty(), "堆叠拖拽位置写入存档快照")
	player.queue_free()
	await process_frame


func _test_backpack_ui() -> void:
	var level_scene := load("res://scenes/levels/test_level.tscn") as PackedScene
	var level := level_scene.instantiate()
	root.add_child(level)
	await process_frame
	var player := level.get_node("Player") as Player
	level._set_backpack_panel_visible(true)
	_expect(level._backpack_category == BackpackCategory.EQUIPMENT, "背包默认打开装备分类")
	_expect(level._backpack_list.get_child_count() == 40, "装备栏显示完整 40 格")
	_expect(level.get_node_or_null("Interface/BackpackPanel/EmptyText") == null, "空背包不再显示暂无文字")
	var tab_names: Array[String] = []
	for category in BackpackCategory.ALL:
		tab_names.append((level._backpack_tab_buttons[category] as Button).text)
	_expect(tab_names == ["装备", "消耗", "其他", "任务"], "四个 Tab 使用固定顺序")

	level._set_backpack_category(BackpackCategory.OTHER)
	_expect(level._backpack_list.get_child_count() == 40, "其他栏空库存仍显示完整 40 格")
	player.collect_stackable_item(&"stardust_fragment", 120)
	_expect(level._backpack_list.get_child_count() == 40, "收取道具后格子总数保持 40")
	var first_slot := level._backpack_list.get_child(0) as BackpackSlotButton
	var second_slot := level._backpack_list.get_child(1) as BackpackSlotButton
	_expect(first_slot.quantity_label.text == "99" and second_slot.quantity_label.text == "21", "每个格子显示自身堆叠数量")
	_expect(first_slot.quantity_label.anchor_top == 1.0 and first_slot.quantity_label.offset_top < 0.0, "数量覆盖层固定在左下角")
	_expect(first_slot.quantity_label.get_theme_font_size("font_size") == 11, "数量使用较小字号")

	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	level._unhandled_input(tab_event)
	_expect(level._backpack_category == BackpackCategory.QUEST, "Tab 切换到下一个分类")
	var reverse_tab := InputEventKey.new()
	reverse_tab.keycode = KEY_TAB
	reverse_tab.shift_pressed = true
	reverse_tab.pressed = true
	level._unhandled_input(reverse_tab)
	_expect(level._backpack_category == BackpackCategory.OTHER, "Shift+Tab 切换到上一个分类")
	level.queue_free()
	await process_frame


func _test_save_migration() -> void:
	var session_script := load("res://scripts/services/game_session.gd") as GDScript
	var session := session_script.new() as Node
	var legacy_profile := {
		"version": 5,
		"profile_id": "issue_17_legacy",
		"slot": 0,
		"name": "旧角色",
		"profession_id": "traveler",
		"progression": {"level": 5, "experience": 0},
		"materials": {"stardust_fragment": 250},
		"equipment": {"next_instance_serial": 1, "instances": [], "equipped": {}, "inventory": []},
		"skills": {"unspent_points": 4, "ranks": {}},
		"skill_quickbar": {"slots": ["", ""]},
		"created_at": 1,
		"updated_at": 1,
	}
	var result: Dictionary = session._normalize_profile(legacy_profile)
	_expect(result.ok, "v5 角色档案可以迁移到 v6")
	var profile := result.data as Dictionary
	_expect(int(profile.version) == 6 and not profile.has("materials"), "迁移后使用 v6 通用背包结构")
	var backpack := profile.backpack as Dictionary
	var capacities := backpack.capacities as Dictionary
	_expect(BackpackCategory.ALL.all(func(category: StringName) -> bool: return int(capacities[String(category)]) == 40), "旧角色四分类默认获得 40 格")
	var other_stacks := (backpack.stacks as Dictionary).other as Array
	_expect(other_stacks.size() == 3, "旧星尘数量按单格上限拆分")
	_expect(int(other_stacks[0].quantity) == 99 and int(other_stacks[2].quantity) == 52, "旧星尘迁移不丢失数量")

	var future_capacity_profile := profile.duplicate(true)
	(future_capacity_profile.backpack.capacities as Dictionary)["other"] = 60
	var future_result: Dictionary = session._normalize_profile(future_capacity_profile)
	_expect(future_result.ok and int(future_result.data.backpack.capacities.other) == 60, "合法扩充容量读取时不会缩回 40")
	session.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
