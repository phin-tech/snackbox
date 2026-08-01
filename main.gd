class_name Main
extends Node2D

# App shell: sizes the window, shows the menu, and swaps in whichever game was
# picked. Games are independent Node2Ds that draw themselves and emit
# exit_to_menu when the player backs out.

const DESIGN_SIZE := Vector2(600, 760)

# Each game is a scene so sprites, audio and effects have somewhere to live
# later without restructuring.
const MENU_SCENE := preload("res://menu.tscn")
const GAMES := {
	"marathon": preload("res://game.tscn"),
	"sprint": preload("res://game.tscn"),
	"ultra": preload("res://game.tscn"),
	"pills": preload("res://pills.tscn"),
	"landgrab": preload("res://landgrab.tscn"),
	"snake": preload("res://snake.tscn"),
	"doubles": preload("res://doubles.tscn"),
}

var screen: Node2D = null


func _ready() -> void:
	_fit_window_to_screen()
	# Skip the menu when asked: godot --path . -- --game=landgrab
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			var id := arg.trim_prefix("--game=")
			if GAMES.has(id):
				_start(id)
				return
			push_warning("Unknown game id: %s" % id)
	_show_menu()


func _fit_window_to_screen() -> void:
	# Scale the window up to fill most of the usable screen area while keeping
	# the design aspect. Stretch mode "canvas_items" scales the drawing.
	var screen_id := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen_id)
	# On hiDPI displays the usable rect is reported in physical pixels while
	# window size/position are in logical points, so convert first.
	var dpi_scale: float = maxf(DisplayServer.screen_get_scale(screen_id), 1.0)
	var avail := Vector2(usable.size) / dpi_scale
	var origin := Vector2(usable.position) / dpi_scale

	var factor: float = min(avail.x * 0.92 / DESIGN_SIZE.x, avail.y * 0.94 / DESIGN_SIZE.y)
	factor = max(factor, 1.0)
	var size := Vector2i(DESIGN_SIZE * factor)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(Vector2i(origin + (avail - Vector2(size)) * 0.5))


func _swap(next: Node2D) -> void:
	if screen != null:
		screen.queue_free()
	screen = next
	add_child(next)


func _show_menu() -> void:
	var menu := MENU_SCENE.instantiate()
	menu.chosen.connect(_start)
	_swap(menu)


func _start(id: String) -> void:
	var game: Node2D = GAMES[id].instantiate()
	if game is Game:
		game.mode = id
	game.exit_to_menu.connect(_show_menu)
	_swap(game)
