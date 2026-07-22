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


var _floor_deaths := 0
var _last_alive := -1


func _ready() -> void:
	Events.level_up.connect(_on_level_up)
	Events.floor_changed.connect(_on_floor_changed)
	Events.player_died.connect(_on_player_died)
	Events.crawler_event.connect(_on_crawler_event)
	Events.floor_state_changed.connect(_on_floor_state_changed)
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


func _on_floor_state_changed(state: int) -> void:
	if state == Crawlers.FloorState.ACTIVE:
		_floor_deaths = 0
		_last_alive = Crawlers.alive_count()


## Cohort notables: first blood, milestone culls, the halfway mark, your kills.
func _on_crawler_event(kind: StringName, crawler: CrawlerRecord, data: Dictionary) -> void:
	if kind != &"died":
		return
	if _last_alive < 0:
		_last_alive = Crawlers.alive_count() + 1
	_floor_deaths += 1
	var alive := Crawlers.alive_count()

	var killer: Variant = data.get("killer")
	if killer != null and killer is CrawlerRecord and (killer as CrawlerRecord).is_player:
		Events.announce.emit("CONFIRMED KILL",
			"%s falls to you. The viewers are feral." % crawler.sheet.char_name)
	elif _floor_deaths == 1:
		Events.announce.emit("FIRST BLOOD",
			"%s is first to fall this floor. %d crawlers remain." % [crawler.sheet.char_name, alive])
	elif _floor_deaths % 25 == 0:
		Events.announce.emit("THE CULLING",
			"%d dead on this floor alone. The System is thoroughly entertained." % _floor_deaths)

	var half := maxi(Crawlers.roster.size() / 2, 1)
	if _last_alive > half and alive <= half and Crawlers.roster.size() > 4:
		Events.announce.emit("HALFWAY THERE",
			"Half the cohort is gone. %d crawlers still breathing." % alive)
	_last_alive = alive
