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
