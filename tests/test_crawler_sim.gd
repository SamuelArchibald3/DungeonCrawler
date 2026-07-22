extends SceneTree
## Headless abstract-cohort test: no scene, no autoloads — drives whole
## floors of 100 crawlers purely through CrawlerSim + inline lifecycle.
## Verifies conservation, non-negativity, determinism, and variety.
## Run: godot --headless --path . --script res://tests/test_crawler_sim.gd

const SEEDS := 20
const COHORT := 100

var failures := 0


func _init() -> void:
	var outcomes: Array = []
	for seed_value in SEEDS:
		var floor_num := (seed_value % 4) + 1
		var a := run_floor(seed_value, floor_num)
		var b := run_floor(seed_value, floor_num)  # same seed → must match
		if a["hash"] != b["hash"]:
			print("FAIL seed %d: non-deterministic (%s vs %s)" % [seed_value, a["hash"], b["hash"]])
			failures += 1
		outcomes.append(a)

	# Variety: different seeds must not all resolve identically
	var distinct := {}
	for o in outcomes:
		distinct[o["hash"]] = true
	if distinct.size() < SEEDS / 2:
		print("FAIL: too few distinct outcomes (%d/%d) — sim may be degenerate" % [distinct.size(), SEEDS])
		failures += 1

	if failures == 0:
		print("PASS: %d cohort floors — conserved, non-negative, deterministic, varied" % SEEDS)
	else:
		print("FAILED: %d problems across cohort sim" % failures)
	quit(1 if failures > 0 else 0)


func run_floor(seed_value: int, floor_num: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sim_rng := RandomNumberGenerator.new()
	sim_rng.seed = seed_value * 7919 + floor_num
	var stat_rng := RandomNumberGenerator.new()
	stat_rng.seed = seed_value + 13

	var fd = FloorGenerator.generate(192, 128, floor_num, rng)
	var records: Array = []
	for i in COHORT:
		var sheet := CharacterData.new()
		sheet.char_name = "C%d" % i
		sheet.base_stats = CharGenerator.roll_stats(stat_rng)
		sheet.recompute_max_hp()
		sheet.hp = sheet.max_hp
		var cr := CrawlerRecord.make(i, sheet)
		cr.disposition = i % 3
		cr.room = i % fd.rooms.size()
		cr.pos = fd.rooms[cr.room].get_center()
		records.append(cr)

	var budget := 900 + (floor_num - 1) * 60
	var ctx = CrawlerSim.build_context(fd, floor_num, sim_rng, records, budget)
	var death_order: Array = []

	# Active phase
	var turns := budget
	var tick := 0
	while turns > 0:
		tick += 1
		turns -= 1
		ctx["turns_left"] = turns
		for cr in records:
			if not cr.alive or cr.descended:
				continue
			if (tick + cr.id) % CrawlerSim.SIM_PERIOD != 0:
				continue
			for ev in CrawlerSim.macro_step(cr, ctx):
				_apply(ev, death_order)
		_check_invariants(seed_value, records, ctx, false)

	# Grace: escalating crush, then force-end
	for g in 25:
		var crush := 5 * (g + 1)
		for cr in records:
			if not cr.alive or cr.descended:
				continue
			cr.sheet.hp = maxi(cr.sheet.hp - crush, 0)
			if cr.sheet.hp <= 0:
				cr.alive = false
				death_order.append(cr.id)
	for cr in records:
		if cr.alive and not cr.descended:
			cr.alive = false
			death_order.append(cr.id)

	_check_invariants(seed_value, records, ctx, true)

	# Outcome signature
	var dead := 0
	var descended := 0
	var sum_level := 0
	var sum_gold := 0
	for cr in records:
		if cr.descended:
			descended += 1
		elif not cr.alive:
			dead += 1
		sum_level += cr.sheet.level
		sum_gold += cr.sheet.gold
	var hash_str := "%d|%d|%d|%d|%s" % [dead, descended, sum_level, sum_gold, str(death_order)]
	return { "hash": hash_str, "dead": dead, "descended": descended }


func _apply(ev: Dictionary, death_order: Array) -> void:
	match ev["kind"]:
		&"died":
			var cr: CrawlerRecord = ev["cr"]
			if cr.alive:
				cr.alive = false
				death_order.append(cr.id)
		&"pvp":
			var loser: CrawlerRecord = ev["cr"]
			if loser.alive:
				loser.alive = false
				death_order.append(loser.id)
		&"descended":
			ev["cr"].descended = true
		# enemy_killed / looted: pool already decremented inside macro_step


func _check_invariants(seed_value: int, records: Array, ctx: Dictionary, ended: bool) -> void:
	var active := 0
	var dead := 0
	var descended := 0
	for cr in records:
		if cr.descended:
			descended += 1
		elif cr.alive:
			active += 1
			if cr.sheet.hp < 0:
				print("FAIL seed %d: living crawler has negative hp" % seed_value)
				failures += 1
		else:
			dead += 1
	if active + dead + descended != COHORT:
		print("FAIL seed %d: cohort not conserved (%d+%d+%d)" % [seed_value, active, dead, descended])
		failures += 1
	if ended and active != 0:
		print("FAIL seed %d: %d crawlers neither dead nor descended at floor end" % [seed_value, active])
		failures += 1
	for zone in ctx["pools"]:
		if ctx["pools"][zone]["enemies"] < 0 or ctx["pools"][zone]["boxes"] < 0:
			print("FAIL seed %d: zone pool went negative" % seed_value)
			failures += 1
			break
