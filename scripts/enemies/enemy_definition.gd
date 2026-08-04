class_name EnemyDefinition
extends Resource

@export_category("Vitals")
@export_range(1, 1000, 1) var max_health := 10

@export_category("Rewards")
@export_range(0, 100000, 1) var experience_reward := 0

@export_category("Movement")
@export_range(0.0, 1000.0, 1.0) var gravity := 1650.0
@export_range(0.0, 1000.0, 1.0) var patrol_speed := 70.0
@export_range(0.0, 1000.0, 1.0) var chase_speed := 115.0
@export_range(0.0, 1000.0, 1.0) var return_speed := 90.0
@export_range(0.0, 2000.0, 1.0) var patrol_range := 180.0
@export_range(0.0, 5.0, 0.01) var idle_time := 0.4

@export_category("Awareness")
@export var detection_size := Vector2(300.0, 110.0)
@export var detection_offset := Vector2(0.0, -38.0)
@export_range(0.0, 1000.0, 1.0) var lose_target_margin := 100.0
@export_range(0.0, 3000.0, 1.0) var leash_range := 500.0

@export_category("Chase Edge Drop")
@export var can_chase_off_edges := true
@export_range(0.0, 600.0, 1.0) var chase_edge_drop_min_target_below := 48.0

@export_category("Chase Jump")
@export var can_chase_jump := true
@export_range(0.0, 1200.0, 1.0) var jump_takeoff_speed := 620.0
@export_range(0.0, 1200.0, 1.0) var jump_air_speed := 250.0
@export_range(0.0, 4000.0, 1.0) var jump_air_acceleration := 1500.0
@export_range(0.0, 300.0, 1.0) var jump_max_rise := 112.0
@export_range(0.0, 100.0, 1.0) var jump_launch_tolerance := 8.0
@export_range(0.0, 100.0, 1.0) var jump_landing_margin := 22.0
@export_range(0.0, 5.0, 0.01) var jump_retry_delay := 0.45
@export_range(0.1, 5.0, 0.01) var jump_timeout := 1.4

@export_category("Reactions")
@export_range(0.0, 5.0, 0.01) var hit_stun_time := 0.18
@export_range(0.0, 5.0, 0.01) var hit_flash_time := 0.12
@export_range(0.0, 1000.0, 1.0) var knockback_speed := 120.0

@export_category("Geometry")
@export_range(1.0, 200.0, 1.0) var body_radius := 18.0
@export_range(1.0, 300.0, 1.0) var body_height := 60.0
@export var body_collision_offset := Vector2(0.0, -30.0)
@export var hurtbox_size := Vector2(44.0, 64.0)
@export var hurtbox_offset := Vector2(0.0, -32.0)
@export_range(1.0, 200.0, 1.0) var floor_probe_x := 20.0
@export_range(1.0, 200.0, 1.0) var wall_probe_x := 19.0
@export var wall_probe_y := -30.0

@export_category("Appearance")
@export_range(0.25, 3.0, 0.01) var visual_scale := 1.0
@export var body_color := Color("a45c88")
@export var flash_color := Color("fff1a8")
@export var trim_color := Color("493548")
@export var eye_color := Color("f4e7d3")
@export var pupil_color := Color("251f29")
@export var attack_tell_color := Color("df784f")
@export var armor_color := Color(0.0, 0.0, 0.0, 0.0)
@export var dead_color := Color("574957")

@export_category("Combat")
@export var melee_attack: EnemyMeleeAttackDefinition

@export_category("Drops")
@export var drop_rules: Array[EnemyDropRule] = []
@export var equipment_drop_rules: Array[EquipmentDropRule] = []
