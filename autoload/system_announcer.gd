extends Node
## The System AI's voice: converts gameplay events into pop-up notification
## boxes (rendered by NotificationBox). It is contractually snarky.

const LEVEL_UP_LINES := [
	"You are now level %d. The audience applauds. Some of it ironically.",
	"Level %d achieved. Your parents would be proud. They can't see you.",
	"Level %d! Statistically, you should already be dead.",
	"Level %d. The System has updated your actuarial tables.",
]

const FLOOR_LINES := [
	"Welcome to Floor %d. Amenities: monsters. Checkout: mandatory.",
	"Floor %d. The management accepts no liability for anything, ever.",
	"Now arriving: Floor %d. Please keep limbs inside your body.",
	"Floor %d. It gets worse from here. That's a promise, not a warning.",
]


func _ready() -> void:
	Events.level_up.connect(_on_level_up)
	Events.floor_changed.connect(_on_floor_changed)
	Events.player_died.connect(_on_player_died)
	Events.race_class_completed.connect(func() -> void:
		Events.announce.emit("NEW YOU", "Race and class installed. Side effects include everything."))
	Events.borough_boss_killed.connect(func() -> void:
		Events.announce.emit("REGIME CHANGE", "A borough boss has been deleted. The stairwell is legally yours."))
	Events.all_bosses_cleared.connect(func() -> void:
		Events.announce.emit("HOSTILE TAKEOVER", "Every neighbourhood boss on this floor is dead. The System is updating the org chart."))
	Events.crush_survived.connect(func() -> void:
		Events.announce.emit("STILL ALIVE", "The ceiling is embarrassed. The viewers are delighted."))
	Events.achievement_unlocked.connect(func(_id: StringName, title: String, description: String) -> void:
		Events.announce.emit("ACHIEVEMENT UNLOCKED", "%s — %s" % [title, description]))


func _on_level_up(level: int) -> void:
	Events.announce.emit("LEVEL UP",
		LEVEL_UP_LINES[randi() % LEVEL_UP_LINES.size()] % level
		+ "\n+2 stat points banked. Spend them in a Safe Room.")


func _on_floor_changed(floor_number: int) -> void:
	Events.announce.emit("FLOOR %d" % floor_number, FLOOR_LINES[randi() % FLOOR_LINES.size()] % floor_number)


func _on_player_died() -> void:
	Events.announce.emit("CRAWLER TERMINATED", Flavor.eulogy())
