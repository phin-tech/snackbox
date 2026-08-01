class_name Menu
extends Node2D

# Game picker. Entries are just data - adding a game means adding a row here
# and a case in main.gd.

signal chosen(id: String)

const ENTRIES := [
	{"header": "BLOCKFALL"},
	{"id": "marathon", "label": "Marathon", "desc": "Endless. Speed climbs every 10 lines."},
	{"id": "sprint", "label": "Sprint", "desc": "Clear 40 lines as fast as you can."},
	{"id": "ultra", "label": "Ultra", "desc": "Score as much as possible in 2 minutes."},
	{"header": "PILL DOCTOR"},
	{"id": "pills", "label": "Virus Clear", "desc": "Match 4 to wipe out every virus."},
	{"header": "LANDGRAB"},
	{"id": "landgrab", "label": "Claim", "desc": "Cut off territory, dodge the drifters."},
	{"header": "SNAKE"},
	{"id": "snake", "label": "Classic", "desc": "Eat, grow, don't bite yourself."},
	{"header": "DOUBLES"},
	{"id": "doubles", "label": "2048", "desc": "Slide and merge your way to 2048."},
]

var index := 1
var time := 0.0


func _ready() -> void:
	set_process(true)
	# Land on the first selectable row.
	index = _next_selectable(0, 1)


func _next_selectable(from: int, step: int) -> int:
	var i := from
	for _n in ENTRIES.size():
		i = wrapi(i + step, 0, ENTRIES.size())
		if ENTRIES[i].has("id"):
			return i
	return from


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_UP, KEY_W:
			index = _next_selectable(index, -1)
		KEY_DOWN, KEY_S:
			index = _next_selectable(index, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			chosen.emit(ENTRIES[index].id)
		KEY_1:
			chosen.emit("marathon")
		KEY_2:
			chosen.emit("sprint")
		KEY_3:
			chosen.emit("ultra")
		KEY_4:
			chosen.emit("pills")
		KEY_5:
			chosen.emit("landgrab")
		KEY_6:
			chosen.emit("snake")
		KEY_7:
			chosen.emit("doubles")


func _draw() -> void:
	var w := Main.DESIGN_SIZE.x

	# Masthead: small tracked caps over a large flush-left wordmark, then a
	# heavy red rule. Everything hangs off the same left margin.
	Blocks.tracked(self, Vector2(34, 96), "CASUAL GAMES", 12, Blocks.INK_MID)
	Blocks.text(self, Vector2(32, 156), "SNACKBOX", 54, Blocks.INK)
	Blocks.rule(self, Vector2(32, 176), w - 64, Blocks.RED, 5.0)

	var y := 232.0
	var number := 0
	for i in ENTRIES.size():
		var e: Dictionary = ENTRIES[i]
		if e.has("header"):
			y += 12
			Blocks.rule(self, Vector2(32, y - 14), w - 64, Blocks.INK, 1.0)
			Blocks.tracked(self, Vector2(32, y + 2), e.header, 11, Blocks.INK_FAINT)
			y += 22
			continue

		number += 1
		var selected := i == index
		if selected:
			draw_rect(Rect2(32, y - 19, w - 64, 28), Blocks.INK)

		var num_color: Color = Blocks.PAPER if selected else Blocks.RED
		var label_color: Color = Blocks.PAPER if selected else Blocks.INK
		Blocks.tracked(self, Vector2(40, y), "%02d" % number, 12, num_color)
		Blocks.text(self, Vector2(80, y), e.label, 20, label_color)
		y += 33

	Blocks.rule(self, Vector2(32, 648), w - 64, Blocks.INK, 1.0)
	var current: Dictionary = ENTRIES[index]
	if current.has("desc"):
		Blocks.text(self, Vector2(32, 676), current.desc, 14, Blocks.INK_MID)
	Blocks.tracked(self, Vector2(32, 712), "UP DOWN  CHOOSE", 11, Blocks.INK_FAINT)
	Blocks.tracked(self, Vector2(32, 730), "ENTER  PLAY        ESC  RETURNS HERE", 11, Blocks.INK_FAINT)
