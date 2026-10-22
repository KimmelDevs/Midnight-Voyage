class_name EncounterData
extends Resource
## A battle on the Magical Encounter Board.

@export var id: StringName
@export var display_name: String
@export var description := ""
@export var recommended_level := 1
## [{id = enemy id, level = int}] - up to 3, first entry stands in front.
@export var enemies: Array[Dictionary] = []
@export var coins := 0                ## bonus coins on top of per-enemy coins
@export var xp := 0                   ## bonus XP per crew member
## Random drops on victory: [{kind = "material"/"tickets"/"gems", id = "", n = 1, chance = 0.3}]
@export var drops: Array[Dictionary] = []
## Extra rewards for the first victory only (same shape; chance ignored) plus
## unlock_recipe = true to unlock one locked menu recipe.
@export var first_clear: Array[Dictionary] = []
@export var unlock_recipe := false
@export var boss := false
