class_name VoyageManager
extends Node
## Runs one Sky Route voyage: progress through segments, hazard rolls that
## damage the hull (softened by Stability), an optional ambush handled by the
## existing auto-battler, then rewards. Fuel is paid before departure so an
## event can never strand the ship mid-route.

signal progressed(frac: float)
signal logged(text: String, col: Color)
signal ambushed(encounter_id: String)
signal finished(report: Dictionary)

var route: Dictionary
var fuel_used := 0
var duration := 10.0
var t := 0.0
var running := false
var waiting := false          ## paused while an ambush battle is fought
var ambush_at := -1.0
var segment := 0
var hull_lost := 0
var won_ambush := false


func start(p_route: Dictionary, p_fuel: int) -> void:
	route = p_route
	fuel_used = p_fuel
	duration = ShipStats.voyage_seconds(int(route["segments"]))
	if randf() < float(route["ambush"]) or "--demo-ambush" in OS.get_cmdline_user_args():
		ambush_at = duration * randf_range(0.35, 0.75)
	running = true
	logged.emit("Cast off! %s - %d segments." % [route["name"], route["segments"]], Color("fff6ea"))


func _process(delta: float) -> void:
	if not running or waiting:
		return
	t += delta
	var segs := int(route["segments"])
	var now := mini(int(t / duration * segs), segs)
	while segment < now:
		segment += 1
		_segment_event()
		if not running:
			return
	if ambush_at > 0.0 and t >= ambush_at:
		ambush_at = -1.0
		waiting = true
		logged.emit("Ambush! Monsters board the deck!", Color("ff9a9a"))
		ambushed.emit(str(route["encounter"]))
		return
	progressed.emit(minf(t / duration, 1.0))
	if t >= duration:
		_finish(true)


func _segment_event() -> void:
	if randf() < 0.25 * int(route["hazard"]):
		var dmg := ShipStats.hazard_damage(int(route["hazard"]))
		_damage(dmg)
		logged.emit("Segment %d: turbulence! Hull -%d" % [segment, dmg], Color("ffb070"))
	else:
		logged.emit("Segment %d: smooth sailing." % segment, Color("bfe0ff"))


func _damage(dmg: int) -> void:
	hull_lost += dmg
	GS.airship["hull"] = maxf(1.0, float(GS.airship["hull"]) - dmg)
	if float(GS.airship["hull"]) <= 1.0:
		logged.emit("The hull can't take more - turning back!", Color("ff9a9a"))
		_finish(false)


## Called by the café after the ambush battle.
func resume(victory: bool) -> void:
	waiting = false
	won_ambush = victory
	if victory:
		logged.emit("The crew drove them off!", Color("9ef0a0"))
		return
	var dmg := 20 + ShipStats.hazard_damage(int(route["hazard"]))
	logged.emit("Defeated - the ship limps home. Hull -%d" % dmg, Color("ff9a9a"))
	_damage(dmg)
	if running:
		_finish(false)


func _finish(completed: bool) -> void:
	running = false
	var lines: Array[String] = []
	var shards := randi_range(int(route["shards"][0]), int(route["shards"][1]))
	var coins := int(route["coins"])
	var mats := int(route["mats"])
	if not completed:  # cut short: keep what was gathered so far
		var f := float(segment) / float(route["segments"])
		shards = int(shards * f * 0.5)
		coins = int(coins * f * 0.5)
		mats = 0
	if shards > 0:
		GS.add_material("aether_shards", shards)
		lines.append("Aether Shards x%d" % shards)
	if coins > 0:
		GS.add_coins(coins)
		lines.append("+%d coins" % coins)
	if mats > 0:
		GS.add_material("build_mats", mats)
		lines.append("Building Materials x%d" % mats)
	var wear := ShipStats.engine_wear(segment)
	GS.airship["engine"] = maxf(0.0, float(GS.airship["engine"]) - wear)
	GS.airship["voyages"] = int(GS.airship.get("voyages", 0)) + 1
	var crew: Array[String] = []
	for st in ShipStats.STATIONS:  # station mastery grows with every segment flown
		var k := ShipStats.station_key(st)
		if k != "":
			GS.add_mastery(k, ShipStats.STATIONS[st]["mastery"], segment * 3)
			crew.append("%s (%s)" % [GS.STAFF[k]["name"], ShipStats.STATIONS[st]["name"]])
	GS.changed.emit()
	GS.save_game()
	finished.emit({"completed": completed, "route": route, "fuel": fuel_used, "hull_lost": hull_lost,
		"wear": wear, "lines": lines, "crew": crew, "segments": segment})
