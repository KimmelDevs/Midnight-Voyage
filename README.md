# Midnight-Voyage

Isometric pixel-art café sim built in Godot 4.7: serve food, unlock recipes, and summon staff from the gacha.

- Open `project.godot` in Godot 4.7 and press Play.
- Art: ChatGPT-generated sheets in `art_src/`, cleaned to grid-true pixel art with `tools/pixelize.py`.

## Battles (Magical Encounter Board)
- 3 crew vs up to 3 enemies, auto-battle (speed toggle 1x/2x). The café pauses while you fight.
- Combat stats derive from the same TEC/AGI/END/HOS/FOC + level the café uses (`GS.combat_stats`).
- Content lives in `scripts/battle/battle_db.gd`: character kits (AbilityData effect lists), enemies, encounters, meal buffs.
- Pack meals from unlocked recipes; one meal is eaten per battle and buffs the team by its star tier.
- Rewards: coins, crew XP, Golden Sugar (next dish +1 star), Training Manuals (+XP), tickets, a recipe unlock (boss).
- Test flags: `-- --test-save --demo-battle [--demo-meal] [--demo-return]`, `--demo-boss`, `--demo-board`, `--demo-prepare`.

## Airship systems (Phase 1)
- Ship panel (sidebar "Ship"): Hull HP, Aether fuel tank, engine condition, ship stats, upgrades
  (Skyheart Core, Aether Tank, Reinforced Hull, Stabilizer Runes, Cargo Hold), anchorage supplies.
- Crew stations (travel shift, separate from café roles): Pilot (AGI+FOC), Engineer (TEC+END),
  Quartermaster (FOC+END). Performance = 0.65 primary + 0.35 secondary + 1.5 mastery; capped bonuses.
- Night "Set Sail": Sky Routes leave and return to the home anchorage (islands come later).
  Fuel is paid at departure; hazards hit the hull; ambushes use the auto-battler.
- Rules live in `scripts/ship/` (ShipData, ShipStats, VoyageManager); state in `GS.airship`.
- Font: Pixel Operator (CC0) in `assets/fonts/`, drawn at native 8 px / 16 px titles.
- Test flags: `-- --test-save --demo-ship`, `--demo-voyage [--demo-routes] [--demo-ambush] [--demo-return]`.

## Level editor

Open `scenes/level_editor.tscn` in Godot and press F6 (Run Current Scene).
Pick a piece from the palette (Floors, Furniture, Walls, Ship, Island) and build on the iso grid.

- Left click / drag: place. Right click / drag: erase.
- R: rotate (furniture turns, walls/hull/cliffs move to the next tile edge, free pieces mirror).
- G: grid. Tab: hide palette. WASD or middle-drag: pan. Wheel: zoom.
- Save writes `scenes/levels/<name>.tscn` (a normal scene you can open or instance) and `<name>.json` (pick it in the drop-down and click Load to keep editing).
