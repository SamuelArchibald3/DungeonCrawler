extends Node
## The cohort: the dungeon-wide roster of ~100 crawlers who all crawl the
## same floor at the same time. Records persist across floors; entities and
## controllers are transient attachments while a crawler is REAL (near the
## player). The floor lifecycle state machine also lives here.

enum FloorState { ACTIVE, GRACE, ENDED }

const COHORT_SIZE := 100

## Tests/headless modes set this (0 = player only). -1 = full cohort.
var spawn_count_override := -1

var roster: Array[CrawlerRecord] = []
var floor_state := FloorState.ACTIVE
var grace_ticks_left := 0
var death_order: Array[int] = []  # crawler ids in death sequence


## Builds the run's roster: the player as record 0 plus the NPC cohort.
func start_cohort(player_sheet: CharacterData) -> void:
	roster.clear()
	death_order.clear()
	floor_state = FloorState.ACTIVE
	grace_ticks_left = 0

	var player_rec := CrawlerRecord.make(0, player_sheet)
	player_rec.is_player = true
	player_rec.tier = CrawlerRecord.Tier.REAL
	roster.append(player_rec)

	var npc_count := COHORT_SIZE - 1 if spawn_count_override < 0 else spawn_count_override
	for i in npc_count:
		var sheet := CharGenerator.random_character()
		if randf() < 0.3:
			sheet.gain_xp(10 + randi() % 30)  # some arrive slightly seasoned
		var cr := CrawlerRecord.make(i + 1, sheet)
		var roll := randf()
		if roll < 0.10:
			cr.disposition = CrawlerRecord.Disposition.HOSTILE
		elif roll < 0.25:
			cr.disposition = CrawlerRecord.Disposition.FRIENDLY
		else:
			cr.disposition = CrawlerRecord.Disposition.WARY
		roster.append(cr)
	Events.cohort_changed.emit()


## Resets per-floor state for the survivors; desperation flips some WARY
## crawlers HOSTILE as the dungeon deepens.
func begin_floor() -> void:
	floor_state = FloorState.ACTIVE
	grace_ticks_left = 0
	for cr in roster:
		if not cr.alive:
			continue
		cr.descended = false
		cr.goal = CrawlerRecord.Goal.EXPLORE
		cr.goal_data = {}
		if not cr.is_player:
			cr.tier = CrawlerRecord.Tier.ABSTRACT
			cr.entity = null
			cr.controller = null
			if cr.disposition == CrawlerRecord.Disposition.WARY \
					and randf() < 0.04 * GameState.floor_number:
				cr.disposition = CrawlerRecord.Disposition.HOSTILE
	Events.cohort_changed.emit()


## Scatter surviving NPCs across the floor's crawler spawn points.
func assign_floor_positions(fd: FloorGenerator.FloorData) -> void:
	var spawn_index := 0
	for cr in roster:
		if cr.is_player or not cr.alive:
			continue
		if spawn_index < fd.crawler_spawns.size():
			cr.pos = fd.crawler_spawns[spawn_index]
			cr.room = fd.room_of.get(cr.pos, -1)
			spawn_index += 1
		else:
			cr.pos = fd.spawn
			cr.room = 0


## The shared floor clock hit zero: open the grace window before the floor
## force-ends.
func begin_grace() -> void:
	if floor_state != FloorState.ACTIVE:
		return
	floor_state = FloorState.GRACE
	grace_ticks_left = GameState.GRACE_TICKS
	Events.floor_state_changed.emit(floor_state)


func end_floor() -> void:
	floor_state = FloorState.ENDED
	Events.floor_state_changed.emit(floor_state)
	Events.cohort_changed.emit()


func player_record() -> CrawlerRecord:
	return roster[0] if roster.size() > 0 else null


func alive_count() -> int:
	var count := 0
	for cr in roster:
		if cr.alive:
			count += 1
	return count


func descended_count() -> int:
	var count := 0
	for cr in roster:
		if cr.alive and cr.descended:
			count += 1
	return count


func npc_records() -> Array[CrawlerRecord]:
	var out: Array[CrawlerRecord] = []
	for cr in roster:
		if not cr.is_player:
			out.append(cr)
	return out


func real_records() -> Array[CrawlerRecord]:
	var out: Array[CrawlerRecord] = []
	for cr in roster:
		if cr.alive and cr.tier == CrawlerRecord.Tier.REAL:
			out.append(cr)
	return out


func kill(cr: CrawlerRecord, cause: String, killer: CrawlerRecord = null) -> void:
	if not cr.alive:
		return
	cr.alive = false
	death_order.append(cr.id)
	if killer != null:
		killer.kills += 1
	Events.crawler_event.emit(&"died", cr, { "cause": cause, "killer": killer })
	Events.cohort_changed.emit()


func mark_descended(cr: CrawlerRecord) -> void:
	if cr.descended or not cr.alive:
		return
	cr.descended = true
	Events.crawler_event.emit(&"descended", cr, {})
	Events.cohort_changed.emit()


## Battle-royale rank: 1 = last one standing. The dead rank by death order.
func placement(cr: CrawlerRecord) -> int:
	if cr.alive:
		return alive_count()
	var index := death_order.find(cr.id)
	return roster.size() - index if index >= 0 else roster.size()
