extends Node
# Dev helper: render a screen and save it to disk. Removed after use.
func _ready() -> void:
	var id := "menu"
	var out := "/tmp/shot.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--id="): id = a.trim_prefix("--id=")
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	var node: Node2D
	if id == "menu":
		node = load("res://menu.tscn").instantiate()
	else:
		node = load("res://" + ("game" if id in ["marathon","sprint","ultra"] else id) + ".tscn").instantiate()
		if node is Game: node.mode = id
	add_child(node)
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_width(), "x", img.get_height())
	get_tree().quit(0)
