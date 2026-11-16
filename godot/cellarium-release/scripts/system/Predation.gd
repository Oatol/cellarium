extends RefCounted
## 捕食行为闭环（v2.1 §4.3 / 阶段 3）。消费神经攻击意图 intent[2]，对邻近异种细胞捕食。
## 确定性：按 cell_index 升序遍历，邻居列表由 CellPhysics.query_neighbors 排序，低索引优先。
## 纯静态模块，RefCounted 无 class_name，调用方 preload。不直接死亡细胞，只返回事件由调用方处理。

const INTENT_OUTPUT_COUNT: int = 6
const ATTACK_INTENT_INDEX: int = 2
const DEFAULT_ATTACK_THRESHOLD: float = 0.35
const DEFAULT_REACH: float = 14.0
const DEFAULT_MAX_DRAIN: float = 0.25

## 返回捕食事件数组。每个事件：
## {predator, prey, prey_org_id, drained, gain, loss_to_detritus, position}
## drained = 从猎物抽走的能量；gain = 捕食者获得；loss = 损耗（写回环境/detritus）。
static func resolve_predation(cells: RefCounted, physics: Script, transfer_efficiency: float,
		attack_threshold: float = DEFAULT_ATTACK_THRESHOLD, reach: float = DEFAULT_REACH,
		max_drain: float = DEFAULT_MAX_DRAIN) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if cells == null or physics == null or reach <= 0.0 or max_drain <= 0.0:
		return events
	var efficiency: float = clampf(transfer_efficiency, 0.0, 1.0)
	var alive: PackedByteArray = cells.get("cell_alive")
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var intents: PackedFloat32Array = cells.get("behavior_intents")
	var pos_x: PackedFloat32Array = cells.get("cell_pos_x")
	var pos_y: PackedFloat32Array = cells.get("cell_pos_y")
	var consumed_as_prey: Dictionary = {}
	for predator in range(alive.size()):
		if alive[predator] == 0 or consumed_as_prey.has(predator):
			continue
		var intent_index: int = predator * INTENT_OUTPUT_COUNT + ATTACK_INTENT_INDEX
		if intent_index < 0 or intent_index >= intents.size():
			continue
		var attack: float = float(intents[intent_index])
		if attack < attack_threshold:
			continue
		var neighbors: Array = physics.call("query_neighbors", cells, predator)
		var prey: int = -1
		for neighbor_value in neighbors:
			var candidate: int = int(neighbor_value)
			if candidate == predator or consumed_as_prey.has(candidate) or candidate < 0 or candidate >= alive.size():
				continue
			if alive[candidate] == 0 or org_ids[candidate] == org_ids[predator]:
				continue
			var dx: float = pos_x[candidate] - pos_x[predator]
			var dy: float = pos_y[candidate] - pos_y[predator]
			if dx * dx + dy * dy <= reach * reach:
				prey = candidate
				break
		if prey < 0:
			continue
		var prey_energy: float = maxf(0.0, float(energies[prey]))
		if prey_energy <= 0.0:
			continue
		var drained: float = minf(prey_energy, max_drain * clampf(attack, 0.0, 1.0))
		if drained <= 0.0:
			continue
		var gain: float = drained * efficiency
		var loss: float = drained - gain
		energies[prey] = prey_energy - drained
		energies[predator] = float(energies[predator]) + gain
		consumed_as_prey[prey] = true
		events.append({
			"predator": predator,
			"prey": prey,
			"prey_org_id": int(org_ids[prey]),
			"drained": drained,
			"gain": gain,
			"loss_to_detritus": loss,
			"position": Vector2(pos_x[prey], pos_y[prey])
		})
	if not events.is_empty():
		cells.set("cell_energy", energies)
	return events
