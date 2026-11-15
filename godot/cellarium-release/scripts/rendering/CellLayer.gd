extends "res://scripts/rendering/CellariumView.gd"

@export var cell_radius: float = 5.0

func _draw() -> void:
	draw_cells_layer(cell_radius)
