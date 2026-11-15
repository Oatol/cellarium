extends Node2D

@export var center: Vector2 = Vector2(250, 250)
@export var radius: float = 240.0

func _draw() -> void:
	draw_circle(center, radius, Color("#081513"))
	draw_arc(center, radius, 0.0, TAU, 160, Color("#5ce0c0"), 1.5, true)
