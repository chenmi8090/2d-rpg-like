class_name AudioCueDefinition
extends Resource

@export var cue_id: StringName
@export var streams: Array[AudioStream] = []
@export_range(-80.0, 24.0, 0.1) var volume_db := 0.0
@export_range(0.01, 4.0, 0.01) var base_pitch := 1.0
@export_range(0.0, 1.0, 0.001) var pitch_variance := 0.0
@export_range(0.0, 5.0, 0.01) var cooldown_time := 0.0
@export_range(1, 32, 1) var max_concurrent_global := 4
@export_range(1, 16, 1) var max_concurrent_per_owner := 1


func is_valid() -> bool:
	return cue_id != &"" and not streams.is_empty()
