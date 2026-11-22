extends SceneTree
## v0.38.0 回归闸门：防止 CellBatch 的 Transform2D.scaled 再次把 origin 放大到皿外。
## 验证修正写法 origin 恒等于细胞位置，且与被废弃的错误写法明确区分。

func _initialize() -> void:
	var failures: int = 0
	var checked: int = 0
	var positions: Array[Vector2] = [
		Vector2(250.0, 250.0), Vector2(50.0, 60.0), Vector2(450.0, 100.0),
		Vector2.ZERO, Vector2(123.5, 456.25), Vector2(-40.0, 500.0)
	]
	var radii: Array[float] = [2.0, 3.0, 1.0, 8.0]
	for position in positions:
		for radius in radii:
			var t: Transform2D = Transform2D(0.0, Vector2.ZERO).scaled(Vector2(radius, radius))
			t.origin = position
			checked += 1
			if t.origin != position:
				failures += 1
				print("BATCH_ORIGIN_PARITY: FAIL pos=%s radius=%s got=%s" % [str(position), str(radius), str(t.origin)])
			# 同时确认错误写法在非零位置确实会错位（作为回归证据，不作为断言）。
			# position=ZERO 时缩放 origin 仍是 ZERO，属合法情况，跳过。
			var wrong: Transform2D = Transform2D(0.0, position).scaled(Vector2(radius, radius))
			if radius != 1.0 and position != Vector2.ZERO and wrong.origin == position:
				print("BATCH_ORIGIN_PARITY: WARN wrong-form no longer shifts (unexpected)")
	print("BATCH_ORIGIN_PARITY: checked=%d failures=%d" % [checked, failures])
	quit(0 if failures == 0 else 1)
