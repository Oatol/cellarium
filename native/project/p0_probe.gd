extends SceneTree

func _initialize() -> void:
	if not ClassDB.class_exists("ExampleClass"):
		print("P0_PROBE: FAIL ExampleClass not registered")
		quit(1)
		return
	var ex = ClassDB.instantiate("ExampleClass")
	ex.call("print_type", 42)
	ex.call("print_type", "hello")
	print("P0_PROBE: OK GDExtension loaded and called on Godot 4.7.2")
	quit(0)
