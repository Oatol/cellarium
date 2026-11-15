extends RefCounted
## Pure respiration rules from the gameplay specification.

const ANAEROBIC: int = 0
const AEROBIC: int = 1
const FACULTATIVE: int = 2
const OXYGEN_TOXICITY_THRESHOLD: float = 0.08
const ANAEROBIC_EFFICIENCY: float = 1.0
const AEROBIC_EFFICIENCY: float = 3.0
const HYPOXIC_AEROBIC_EFFICIENCY: float = 0.5
const FACULTATIVE_BUDGET_COST: int = 2

static func evaluate(respiration: int, oxygen_fraction: float, facultative_aerobic_efficiency: float = 2.0) -> Dictionary:
	if respiration < ANAEROBIC or respiration > FACULTATIVE or oxygen_fraction < 0.0 or oxygen_fraction > 1.0:
		return {"valid": false, "efficiency": 0.0, "toxic": false, "budget_cost": 0}
	if facultative_aerobic_efficiency <= ANAEROBIC_EFFICIENCY or facultative_aerobic_efficiency >= AEROBIC_EFFICIENCY:
		return {"valid": false, "efficiency": 0.0, "toxic": false, "budget_cost": 0}
	var oxygenated: bool = oxygen_fraction > OXYGEN_TOXICITY_THRESHOLD
	var efficiency: float = ANAEROBIC_EFFICIENCY
	var toxic: bool = false
	var budget_cost: int = 0
	match respiration:
		ANAEROBIC:
			toxic = oxygenated
		AEROBIC:
			efficiency = AEROBIC_EFFICIENCY if oxygenated else HYPOXIC_AEROBIC_EFFICIENCY
		FACULTATIVE:
			efficiency = facultative_aerobic_efficiency if oxygenated else ANAEROBIC_EFFICIENCY
			budget_cost = FACULTATIVE_BUDGET_COST
	return {"valid": true, "efficiency": efficiency, "toxic": toxic, "budget_cost": budget_cost}
