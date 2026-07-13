extends Node
## The only mutable global: state for the current run.

const FLOOR_TURN_BUDGET := 340  # tuned for 68x44 floors
const FLOOR_TURN_BONUS_PER_FLOOR := 30

var character: CharacterData
var floor_number: int = 1
var rng := RandomNumberGenerator.new()
var race_class_done := false
var run_seed: int = 0

## Floor timer: turns until this floor collapses
var floor_turns_left: int = FLOOR_TURN_BUDGET
var collapse_ticks: int = 0  # turns spent inside a collapsed floor

## Saferoom amenities purchased this run (id -> true); effects last the run
var amenities := {}

## Run summary stats
var kills: int = 0
var boxes_opened: int = 0
var best_item_name: String = ""
var best_item_rarity: int = -1


func new_run(new_character: CharacterData) -> void:
	character = new_character
	floor_number = 1
	race_class_done = false
	kills = 0
	boxes_opened = 0
	best_item_name = ""
	best_item_rarity = -1
	amenities = {}
	run_seed = randi()
	rng.seed = run_seed
	print("[GameState] Run seed: %d" % run_seed)
	start_floor_timer()
	Events.run_started.emit()


func start_floor_timer() -> void:
	floor_turns_left = FLOOR_TURN_BUDGET + (floor_number - 1) * FLOOR_TURN_BONUS_PER_FLOOR
	collapse_ticks = 0
