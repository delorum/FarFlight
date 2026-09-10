extends SceneTree

func _initialize() -> void:
	var world_script = load("res://scripts/world.gd")
	var failed := false
	var previous: Array = []
	for seed_value in range(100,120):
		var world = world_script.new(seed_value)
		var repeated = world_script.new(seed_value)
		var frequencies: Array = []
		for i in world.beacons.size():
			var frequency: int = world.beacons[i].frequency
			if frequency < 300 or frequency > 400 or frequencies.has(frequency) or frequency != repeated.beacons[i].frequency:
				push_error("Frequencies must be unique, within 300–400 kHz and seed-reproducible")
				failed = true
			frequencies.append(frequency)
		if frequencies == previous:
			push_error("Different seeds must generate different station frequencies")
			failed = true
		previous = frequencies
	print("Beacon frequencies: range, uniqueness, reproducibility and variation: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
