class_name Blocks
extends RefCounted

# Shared drawing helpers and palette. Every screen draws procedurally, so these
# are static and take the CanvasItem doing the drawing.

const BG := Color("0d1018")
const GRID_LINE := Color(1, 1, 1, 0.05)
const FRAME := Color("39405c")
const TEXT := Color("f2f5ff")
const TEXT_DIM := Color("8892b0")
const TEXT_FAINT := Color("5c6584")
const ACCENT := Color("00e5ff")


static func font() -> Font:
	return ThemeDB.fallback_font


static func block(ci: CanvasItem, rect: Rect2, color: Color, alpha := 1.0) -> void:
	var c := color
	c.a *= alpha
	var r := rect.grow(-1)
	ci.draw_rect(r, c)
	# Bevel: light on top/left, dark on bottom/right.
	var light := c.lightened(0.35)
	light.a = c.a
	var dark := c.darkened(0.4)
	dark.a = c.a
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), light)
	ci.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), light)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), dark)
	ci.draw_rect(Rect2(r.position + Vector2(r.size.x - 3, 0), Vector2(3, r.size.y)), dark)


static func outline(ci: CanvasItem, rect: Rect2, color := FRAME, width := 2.0) -> void:
	ci.draw_rect(rect, color, false, width)


static func text(ci: CanvasItem, pos: Vector2, s: String, size := 16, color := TEXT) -> void:
	ci.draw_string(font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func text_centered(ci: CanvasItem, center_x: float, y: float, s: String, size := 16, color := TEXT) -> void:
	var w := font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font(), Vector2(center_x - w * 0.5, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func panel(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, BG)
	outline(ci, rect)


static func banner(ci: CanvasItem, width: float, title: String, subtitle: String) -> void:
	var h := 120.0
	var top := 300.0
	ci.draw_rect(Rect2(0, top, width, h), Color(0.02, 0.03, 0.06, 0.9))
	ci.draw_rect(Rect2(0, top, width, 3), ACCENT)
	ci.draw_rect(Rect2(0, top + h - 3, width, 3), ACCENT)
	text_centered(ci, width * 0.5, top + 55, title, 40, TEXT)
	text_centered(ci, width * 0.5, top + 90, subtitle, 16, TEXT_DIM)


static func format_time(seconds: float) -> String:
	var total := maxf(seconds, 0.0)
	var m := int(total) / 60
	var s := int(total) % 60
	var cs := int(fmod(total, 1.0) * 100.0)
	return "%d:%02d.%02d" % [m, s, cs]
