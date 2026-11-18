extends RefCounted
## Deterministic, energy-conserving transfer between linked cells.

const MAX_LINK_FLOW: float = 0.1

## v0.14.1：diagnostics 可选输出只记录每条连接实际转移量，供生态报告显示；
## 不参与 deltas 计算、不写细胞状态、不进确定性 hash。传空 Dictionary 时零额外分配。
static func redistribute_link_energy(cells: RefCounted, transfer_rates: PackedFloat32Array, dt: float, diagnostics: Dictionary = {}) -> bool:
	if cells == null or dt < 0.0:
		return false
	var count: int = int(cells.call("size"))
	if transfer_rates.size() != count:
		return false
	var energies: PackedFloat32Array = cells.get("cell_energy")
	var alive: PackedByteArray = cells.get("cell_alive")
	var org_ids: PackedInt32Array = cells.get("cell_org_id")
	var link_a: PackedInt32Array = cells.get("link_cell_a")
	var link_b: PackedInt32Array = cells.get("link_cell_b")
	var deltas: PackedFloat64Array = PackedFloat64Array()
	var outgoing: PackedFloat64Array = PackedFloat64Array()
	deltas.resize(count)
	outgoing.resize(count)
	var transfer_from: PackedInt32Array = PackedInt32Array()
	var transfer_to: PackedInt32Array = PackedInt32Array()
	var transfer_amounts: PackedFloat64Array = PackedFloat64Array()
	var track_flow: bool = not diagnostics.is_empty()
	var link_out: PackedFloat64Array = PackedFloat64Array()
	var link_in: PackedFloat64Array = PackedFloat64Array()
	if track_flow:
		link_out.resize(count)
		link_in.resize(count)
	for link_index in range(link_a.size()):
		var a: int = link_a[link_index]
		var b: int = link_b[link_index]
		if a < 0 or b < 0 or a >= count or b >= count:
			return false
		if alive[a] == 0 or alive[b] == 0 or org_ids[a] != org_ids[b]:
			return false
		var flow: float = clampf(transfer_rates[b] * energies[a] - transfer_rates[a] * energies[b], -MAX_LINK_FLOW, MAX_LINK_FLOW)
		var amount: float = flow * dt
		if amount == 0.0:
			continue
		var donor: int = a if amount > 0.0 else b
		var receiver: int = b if amount > 0.0 else a
		var requested: float = absf(amount)
		transfer_from.append(donor)
		transfer_to.append(receiver)
		transfer_amounts.append(requested)
		outgoing[donor] += requested
	for transfer_index in range(transfer_amounts.size()):
		var donor: int = transfer_from[transfer_index]
		var receiver: int = transfer_to[transfer_index]
		var scale: float = minf(1.0, energies[donor] / outgoing[donor])
		var amount: float = transfer_amounts[transfer_index] * scale
		deltas[donor] -= amount
		deltas[receiver] += amount
		if track_flow:
			link_out[donor] += amount
			link_in[receiver] += amount
	for cell_index in range(count):
		if alive[cell_index] != 0:
			energies[cell_index] += float(deltas[cell_index])
	cells.set("cell_energy", energies)
	if track_flow:
		diagnostics["link_out"] = link_out
		diagnostics["link_in"] = link_in
	return true
