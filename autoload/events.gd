extends Node
## Global signal bus. The message log subscribes to `message`; later a
## System AI announcer autoload can also subscribe and inject snark.

signal message(text: String, category: StringName)
signal player_died
signal level_up(new_level: int)
signal floor_changed(floor_number: int)
signal hud_refresh

## Structured gameplay events — achievements and quests subscribe to these
signal run_started
signal enemy_killed(def_id: StringName, is_boss: bool)
signal all_bosses_cleared
signal borough_boss_killed
signal box_opened(tier: int)
signal item_equipped(item: ItemData)
signal item_bought(cha: int)
signal item_sold
signal descended(turns_remaining: int)
signal crush_survived
signal race_class_completed
signal achievement_unlocked(id: StringName, title: String, description: String)

## The System's voice: pop-up notification boxes (see NotificationBox)
signal announce(title: String, body: String)
signal viewers_changed(count: int)

## Message categories double as log colors: &"combat", &"loot", &"system", &"info"


func _ready() -> void:
	_register_inputs()


func msg(text: String, category: StringName = &"info") -> void:
	message.emit(text, category)


## Input actions are registered in code so the whole input map lives in one
## readable place instead of serialized InputEventKey blobs in project.godot.
func _register_inputs() -> void:
	var actions := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"wait": [KEY_PERIOD],
		"attack": [KEY_SPACE, KEY_J],
		"interact": [KEY_E, KEY_ENTER],
		"inventory": [KEY_I, KEY_TAB],
		"ability": [KEY_Q],
		"map": [KEY_M],
		"achievements": [KEY_V],
		"toggle_pace": [KEY_T],
	}
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
