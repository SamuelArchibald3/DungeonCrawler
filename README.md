# Dungeon Crawler (working title)

A single-player, turn-based roguelike RPG prototype inspired by *Dungeon Crawler
Carl* — you play as one of the other crawlers, descending the dungeon in
parallel with Carl (who exists only in snarky news tickers). Built in Godot 4.6.

> **IP note:** fan prototype for personal use. Before any public or commercial
> release, re-theme names and flavor text (all of it lives in
> `scripts/flavor.gd` and the def tables, so this is cheap).

## Running

Open the project folder in **Godot 4.3+** and press **F5**, or from the command line:

```
godot --path . 
```

## Controls

| Key | Action |
|---|---|
| WASD / Arrows | Move (bump into enemies to attack, boxes to open) |
| Space / . | Wait a turn |
| Q | Use active ability (granted at the level-3 race/class event) |
| I / Tab | Inventory & equipment (double-click to equip/use/unequip) |
| M | Floor map (fog of war; kill a neighbourhood boss to reveal its district) |
| V | Achievement archive (persists across crawlers) |
| Esc | Close menus |

Quests: the saferoom guide (?) posts one job per floor — cull locals, evict a
boss, or open boxes. Accept it there, claim the gold there.

## The run loop

Create or roll a crawler → descend procedurally generated floors before each
one's **timer** runs out (the ceiling gets insistent) → open loot boxes
(Bronze→Platinum), equip affixed gear, collect gold → trade with the **Bopca
shopkeeper** (golden B; CHA gets you discounts) → rest in teal **saferooms**
(regen, enemies locked out; the ? guide inside explains everything) → reach
floor 3 and get your **permanent biological rebrand** in the spawn saferoom
(pick 1 of 3 races, then 1 of 3 classes, each granting stats + an ability) →
die → new crawler. Floors past 4 are a soft "you win, keep going" zone.

## Architecture notes

- Game data (grid, character, items) is pure GDScript; scenes only render it.
  One authoritative `DungeonGrid` — no physics.
- All UI is built in code (no hand-authored .tscn beyond `main.tscn`);
  placeholder art is generated at runtime (tile atlas from an `Image`,
  ASCII-style glyph labels for entities).
- Def tables live in code (`EnemyDef.all()`, `ItemDef.all()`, `RaceDef.all()`,
  `ClassDef.all()`) — convert to `.tres` in the editor later if preferred.
- `autoload/events.gd` is the global signal bus; the message log's `system`
  category is the hook where a future System AI announcer plugs in.

## Tests (headless)

```
# Procgen: 100 seeded floors must be fully connected
godot --headless --path . --script res://tests/test_procgen.gd

# Systems: loot/equip invariants, combat math, race/class event, abilities, death
godot --headless --path . -- --systest

# Chaos: 900 frames of random play, must not error
godot --headless --path . -- --autorun

# Capture UI screenshots into screenshots/
godot --path . -- --screenshots
```

## Deferred design hooks

- **System AI announcer** — subscribe to `Events.message`, rewrite/inject snark
- **Fame/viewer system** — `CHA` already biases loot rarity; extend from there
- **Real-time combat** — turn logic is isolated in `turn_manager.gd`
