class_name Main
extends Node2D

# App shell: sizes the window, shows the menu, and swaps in whichever game was
# picked. Games are independent Node2Ds that draw themselves and emit
# exit_to_menu when the player backs out.

# The default shape. A game may report a different one from design_size(), and
# the shell resizes the window and the stretch base to match - which is how the
# card games get to be landscape without disturbing the portrait ones.
const DESIGN_SIZE := Vector2(600, 760)

# Each game is a scene so sprites, audio and effects have somewhere to live
# later without restructuring.
const MENU_SCENE := preload("res://menu.tscn")
const GAMES := {
	"marathon": preload("res://game.tscn"),
	"sprint": preload("res://game.tscn"),
	"ultra": preload("res://game.tscn"),
	"pills": preload("res://pills.tscn"),
	"mondrian": preload("res://mondrian.tscn"),
	"snake": preload("res://snake.tscn"),
	"doubles": preload("res://doubles.tscn"),
	"linkup.easy": preload("res://linkup.tscn"),
	"linkup.normal": preload("res://linkup.tscn"),
	"linkup.hard": preload("res://linkup.tscn"),
	"gridlock": preload("res://gridlock.tscn"),
	"shapes": preload("res://shapes.tscn"),
	"pyramid": preload("res://pyramid.tscn"),
	"decant": preload("res://decant.tscn"),
	"fence": preload("res://fence.tscn"),
}

var screen: Node2D = null


func _ready() -> void:
	_fit_window_to_screen(DESIGN_SIZE)
	# Skip the menu when asked: godot --path . -- --game=mondrian
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game="):
			var id := arg.trim_prefix("--game=")
			if GAMES.has(id):
				_start(id)
				return
			push_warning("Unknown game id: %s" % id)
	_show_menu()


func _fit_window_to_screen(design: Vector2) -> void:
	# Scale the window up to fill most of the usable screen area while keeping
	# the design aspect. Stretch mode "canvas_items" scales the drawing.
	var screen_id := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen_id)
	# On hiDPI displays the usable rect is reported in physical pixels while
	# window size/position are in logical points, so convert first.
	var dpi_scale: float = maxf(DisplayServer.screen_get_scale(screen_id), 1.0)
	var avail := Vector2(usable.size) / dpi_scale
	var origin := Vector2(usable.position) / dpi_scale

	# Leave room for the title bar, then take essentially all the height that
	# remains - the design is portrait, so height is always the binding limit.
	var room := Vector2(avail.x * 0.94, (avail.y - 34.0) * 0.99)
	var factor: float = min(room.x / design.x, room.y / design.y)
	factor = max(factor, 1.0)
	var size := Vector2i(design * factor)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(Vector2i(origin + (avail - Vector2(size)) * 0.5))


func _unhandled_input(event: InputEvent) -> void:
	# Fullscreen is the quickest way to make it bigger still.
	if event is InputEventKey and event.pressed and not event.echo:
		var code := (event as InputEventKey).physical_keycode
		if code == KEY_F or code == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()


func _swap(next: Node2D) -> void:
	if screen != null:
		screen.queue_free()
	screen = next

	var design := DESIGN_SIZE
	if next.has_method("design_size"):
		design = next.design_size()
	if Vector2(get_window().content_scale_size) != design:
		get_window().content_scale_size = Vector2i(design)
		_fit_window_to_screen(design)

	add_child(next)


func _show_menu() -> void:
	var menu := MENU_SCENE.instantiate()
	menu.chosen.connect(_start)
	_swap(menu)


func _start(id: String) -> void:
	var game: Node2D = GAMES[id].instantiate()
	if game is Game:
		game.mode = id
	elif game is Linkup:
		game.difficulty = id.split(".")[1]
	game.exit_to_menu.connect(_show_menu)
	_swap(game)
