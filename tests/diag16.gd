extends SceneTree

func _initialize() -> void:
	var files := [
		"res://scripts/world/grassland.gd",
		"res://scripts/world/stalagmite.gd",
		"res://scripts/combat/combatant.gd",
	]
	for f in files:
		var s = load(f)
		if s == null:
			print("LOAD_FAIL ", f)
		else:
			var err = s.reload()
			print("RELOAD %s -> %s" % [f, err])
	quit(0)