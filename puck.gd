class_name Puck
extends Node2D

# Table duel in the spirit of Shufflepuck Cafe: slide the puck past the
# opponent's mallet to the back wall. The whole back edge is the goal, so
# defence is entirely about where your mallet is. Beat an opponent and the next
# one sits down; each is faster and reads the puck better.
#
# Mouse or arrow keys - whichever you touched last wins.

signal exit_to_menu

const TABLE := Rect2(80, 120, 440, 540)
const PUCK_R := 13.0
const MALLET_R := 30.0

const MAX_SPEED := 780.0
const MIN_SPEED := 90.0
const FRICTION := 0.35            # velocity lost per second, proportionally
const TRANSFER := 0.55            # how much mallet motion the puck takes on
const GOALS_TO_WIN := 7
const SERVE_PAUSE := 0.9
const KEY_SPEED := 460.0

const PLAYING := 0
const SERVING := 1
const WON := 2
const LOST := 3

# The regulars. Each tracks the puck a little better than the last, and each
# has a face and a mouth on it. "quirk" drives a small behavioural tic so they
# don't all just play the same game faster.
const OPPONENTS := [
	{
		"name": "DOUG", "title": "NIGHT MANAGER", "quirk": "yawns",
		"speed": 210.0, "error": 62.0, "aggression": 0.30,
		"face": "sleepy", "hue": Color("6fae4f"),
		"taunts": ["is my shift over", "oh. your serve", "mmhm"],
		"wins": ["...did i win", "great. bed"],
		"loses": ["fair enough", "i was asleep"],
	},
	{
		"name": "PRINCESS BRENDA", "title": "TABLE 4 REGULAR", "quirk": "gloats",
		"speed": 268.0, "error": 46.0, "aggression": 0.44,
		"face": "smug", "hue": Color("d46fb0"),
		"taunts": ["daddy owns this cafe", "try not to cry", "cute mallet"],
		"wins": ["obviously", "i'll be at the bar"],
		"loses": ["the table is crooked", "rematch. now."],
	},
	{
		"name": "GARY THE THUMB", "title": "BANNED FROM 6 CAFES", "quirk": "slams",
		"speed": 322.0, "error": 32.0, "aggression": 0.64,
		"face": "brute", "hue": Color("e0803a"),
		"taunts": ["one thumb. still beat you", "i dent tables", "hnngh"],
		"wins": ["thumb wins again", "who's next"],
		"loses": ["that thing was rigged", "my thumb slipped"],
	},
	{
		"name": "MX. VOID", "title": "NOT FROM AROUND HERE", "quirk": "phases",
		"speed": 378.0, "error": 21.0, "aggression": 0.74,
		"face": "alien", "hue": Color("8f5fc0"),
		"taunts": ["your puck is very linear", "i have nine elbows", "beep"],
		"wins": ["consumed", "your table is noted"],
		"loses": ["impossible. i am geometry", "recalculating"],
	},
	{
		"name": "THE MOP", "title": "JUST WORKS HERE", "quirk": "wall",
		"speed": 442.0, "error": 12.0, "aggression": 0.88,
		"face": "mop", "hue": Color("4f9fd4"),
		"taunts": ["...", "(it says nothing)", "*damp*"],
		"wins": ["*squeak*", "..."],
		"loses": ["*it falls over*", "*puddle*"],
	},
]

var state := SERVING
var opponent := 0
var you := 0
var them := 0
var serve_timer := 0.0
var serve_to_player := true

var puck_pos := Vector2.ZERO
var puck_vel := Vector2.ZERO

var player := Vector2.ZERO
var player_prev := Vector2.ZERO
var player_vel := Vector2.ZERO

var ai := Vector2.ZERO
var ai_prev := Vector2.ZERO
var ai_vel := Vector2.ZERO
var ai_target := Vector2.ZERO

var use_mouse := false
var key_dir := Vector2.ZERO

var quip := ""
var quip_timer := 0.0
var blink_timer := 0.0
var wobble := 0.0


func _ready() -> void:
	new_game()


func new_game() -> void:
	opponent = 0
	_start_match()


func _start_match() -> void:
	you = 0
	them = 0
	state = SERVING
	serve_timer = 0.0
	serve_to_player = true
	player = Vector2(TABLE.position.x + TABLE.size.x * 0.5, TABLE.end.y - 70)
	player_prev = player
	ai = Vector2(TABLE.position.x + TABLE.size.x * 0.5, TABLE.position.y + 70)
	ai_prev = ai
	ai_target = ai
	_say(_stats().taunts)
	_serve()
	queue_redraw()


func _say(lines: Array) -> void:
	if lines.is_empty():
		return
	quip = lines[randi() % lines.size()]
	quip_timer = 3.2


func _stats() -> Dictionary:
	return OPPONENTS[min(opponent, OPPONENTS.size() - 1)]


func _serve() -> void:
	puck_pos = TABLE.position + TABLE.size * 0.5
	var toward: float = 1.0 if serve_to_player else -1.0
	puck_vel = Vector2(randf_range(-70.0, 70.0), 190.0 * toward)
	state = SERVING
	serve_timer = 0.0


func _mid_y() -> float:
	return TABLE.position.y + TABLE.size.y * 0.5


# --- Physics ------------------------------------------------------------------

func _clamp_mallet(p: Vector2, top: float, bottom: float) -> Vector2:
	return Vector2(
		clampf(p.x, TABLE.position.x + MALLET_R, TABLE.end.x - MALLET_R),
		clampf(p.y, top + MALLET_R, bottom - MALLET_R)
	)


func _bounce_walls() -> void:
	if puck_pos.x - PUCK_R < TABLE.position.x:
		puck_pos.x = TABLE.position.x + PUCK_R
		puck_vel.x = absf(puck_vel.x)
	elif puck_pos.x + PUCK_R > TABLE.end.x:
		puck_pos.x = TABLE.end.x - PUCK_R
		puck_vel.x = -absf(puck_vel.x)


func _hit(mallet: Vector2, mallet_vel: Vector2) -> void:
	var delta := puck_pos - mallet
	var dist := delta.length()
	var reach := MALLET_R + PUCK_R
	if dist > reach or dist == 0.0:
		return

	var normal := delta / dist
	puck_pos = mallet + normal * reach          # push clear so it can't stick
	puck_vel = puck_vel.bounce(normal) + mallet_vel * TRANSFER

	# Always send it away from the mallet, so a slow puck can't dribble through.
	if puck_vel.dot(normal) < MIN_SPEED:
		puck_vel += normal * MIN_SPEED
	puck_vel = puck_vel.limit_length(MAX_SPEED)


func _step_physics(delta: float) -> void:
	# Substep so a fast puck can't tunnel through a mallet or a wall.
	var steps: int = clampi(int(puck_vel.length() * delta / 6.0) + 1, 1, 12)
	var dt := delta / float(steps)

	for _i in steps:
		puck_pos += puck_vel * dt
		_bounce_walls()
		_hit(player, player_vel)
		_hit(ai, ai_vel)

		if puck_pos.y - PUCK_R <= TABLE.position.y:
			_goal(true)
			return
		if puck_pos.y + PUCK_R >= TABLE.end.y:
			_goal(false)
			return

	puck_vel = puck_vel.lerp(Vector2.ZERO, clampf(FRICTION * delta, 0.0, 1.0))


func _goal(scored_by_player: bool) -> void:
	if scored_by_player:
		you += 1
	else:
		them += 1
	serve_to_player = not scored_by_player

	if you >= GOALS_TO_WIN:
		state = WON
		_say(_stats().loses)
		Scores.submit_high("puck", opponent + 1)
	elif them >= GOALS_TO_WIN:
		state = LOST
		_say(_stats().wins)
	else:
		if not scored_by_player:
			_say(_stats().taunts)
		_serve()
	queue_redraw()


# --- Opponent -----------------------------------------------------------------

func _think(delta: float) -> void:
	var s := _stats()
	var home := Vector2(TABLE.position.x + TABLE.size.x * 0.5, TABLE.position.y + 70)

	if puck_vel.y < 0.0 and puck_pos.y < _mid_y() + 60.0:
		# Puck is coming: meet it, with a wobble so it isn't a perfect wall.
		var aim_x: float = puck_pos.x + randf_range(-s.error, s.error)
		var push: float = lerpf(0.0, 46.0, s.aggression)
		ai_target = Vector2(aim_x, puck_pos.y - push)

		match s.quirk:
			"yawns":
				# Doug nods off and stops tracking for a moment.
				if fmod(wobble, 4.2) < 0.9:
					ai_target = ai
			"slams":
				# Gary lunges rather than meeting it politely.
				ai_target.y = puck_pos.y - 60.0
			"phases":
				# Mx. Void drifts sideways in a way no elbow explains.
				ai_target.x += sin(wobble * 3.1) * 26.0
			"wall":
				# The Mop simply is where the puck will be.
				ai_target.x = puck_pos.x
	else:
		ai_target = home
		if s.quirk == "gloats" and puck_vel.y > 0.0:
			# Brenda swans about admiring herself instead of resetting.
			ai_target.x += sin(wobble * 1.6) * 70.0

	ai_target = _clamp_mallet(ai_target, TABLE.position.y, _mid_y())
	var step: float = s.speed * delta
	ai = ai.move_toward(ai_target, step)


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		use_mouse = true
		return
	if not (event is InputEventKey) or event.echo:
		return
	var k := event as InputEventKey
	var code := k.physical_keycode

	if k.pressed:
		match code:
			KEY_ESCAPE:
				exit_to_menu.emit()
				return
			KEY_R:
				new_game()
				return
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if state == WON:
					opponent += 1
					if opponent >= OPPONENTS.size():
						opponent = 0        # roster cleared; round again
					_start_match()
				elif state == LOST:
					new_game()
				return

	var pressed := k.pressed
	match code:
		KEY_LEFT, KEY_A:
			key_dir.x = -1.0 if pressed else 0.0
			use_mouse = false
		KEY_RIGHT, KEY_D:
			key_dir.x = 1.0 if pressed else 0.0
			use_mouse = false
		KEY_UP, KEY_W:
			key_dir.y = -1.0 if pressed else 0.0
			use_mouse = false
		KEY_DOWN, KEY_S:
			key_dir.y = 1.0 if pressed else 0.0
			use_mouse = false


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	wobble += delta
	blink_timer += delta
	quip_timer = maxf(quip_timer - delta, 0.0)

	if state == WON or state == LOST:
		queue_redraw()
		return

	# Mallets: remember where they were so their motion can drive the puck.
	player_prev = player
	ai_prev = ai

	if use_mouse:
		player = get_local_mouse_position()
	elif key_dir != Vector2.ZERO:
		player += key_dir.normalized() * KEY_SPEED * delta
	player = _clamp_mallet(player, _mid_y(), TABLE.end.y)

	if delta > 0.0:
		player_vel = (player - player_prev) / delta

	_think(delta)
	if delta > 0.0:
		ai_vel = (ai - ai_prev) / delta

	if state == SERVING:
		serve_timer += delta
		if serve_timer >= SERVE_PAUSE:
			state = PLAYING
		queue_redraw()
		return

	_step_physics(delta)
	queue_redraw()


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	var mid := _mid_y()

	draw_rect(TABLE, Blocks.PAPER_SUNK)

	# Centre line and face-off circle
	Blocks.rule(self, Vector2(TABLE.position.x, mid), TABLE.size.x, Blocks.INK_FAINT, 1.0)
	draw_arc(Vector2(TABLE.position.x + TABLE.size.x * 0.5, mid), 62.0, 0.0, TAU, 48, Blocks.INK_FAINT, 1.0)

	# Both back walls are goals - mark them in the accent.
	Blocks.rule(self, Vector2(TABLE.position.x, TABLE.position.y - 3), TABLE.size.x, Blocks.RED, 3.0)
	Blocks.rule(self, Vector2(TABLE.position.x, TABLE.end.y), TABLE.size.x, Blocks.RED, 3.0)
	Blocks.outline(self, TABLE, Blocks.INK, 1.0)

	# Puck and mallets
	draw_circle(puck_pos, PUCK_R, Blocks.INK)
	_draw_face(ai, _stats())
	draw_circle(player, MALLET_R, Blocks.INK)
	draw_circle(player, MALLET_R * 0.42, Blocks.PAPER_SUNK)

	_draw_bubble()
	_draw_hud()

	if state == WON:
		var last := opponent >= OPPONENTS.size() - 1
		Blocks.banner(self, Main.DESIGN_SIZE.x, "YOU WIN",
			"ROSTER CLEARED - ENTER TO GO AGAIN" if last else "ENTER TO FACE %s" % OPPONENTS[opponent + 1].name)
	elif state == LOST:
		Blocks.banner(self, Main.DESIGN_SIZE.x, "YOU LOSE", "ENTER TO PLAY AGAIN        ESC FOR MENU")


func _draw_face(at: Vector2, s: Dictionary) -> void:
	# The opponent's mallet is their face. Each one is drawn from circles and
	# rectangles - no assets, same as everything else here.
	var hue: Color = s.hue
	draw_circle(at, MALLET_R, hue)

	# Blink every few seconds, and squeeze the eyes when they're losing.
	var blinking := fmod(blink_timer, 3.6) < 0.14
	var eye_y := at.y - 5.0
	var eye_dx := 11.0
	var eye_r := 6.0
	var pupil := Blocks.PAPER_SUNK

	match s.face:
		"sleepy":
			eye_r = 5.0
			blinking = blinking or fmod(blink_timer, 5.0) < 1.4   # nodding off
		"smug":
			eye_y -= 1.0
		"brute":
			eye_dx = 9.0
			eye_r = 5.0
		"alien":
			eye_dx = 13.0
			eye_r = 7.5
		"mop":
			eye_dx = 8.0
			eye_r = 4.0

	if blinking:
		draw_rect(Rect2(at.x - eye_dx - eye_r, eye_y - 1.0, eye_r * 2.0, 2.0), pupil)
		draw_rect(Rect2(at.x + eye_dx - eye_r, eye_y - 1.0, eye_r * 2.0, 2.0), pupil)
	else:
		draw_circle(Vector2(at.x - eye_dx, eye_y), eye_r, Blocks.INK)
		draw_circle(Vector2(at.x + eye_dx, eye_y), eye_r, pupil)
		draw_circle(Vector2(at.x + eye_dx, eye_y), eye_r, Blocks.INK)
		draw_circle(Vector2(at.x - eye_dx, eye_y), eye_r * 0.45, pupil)
		draw_circle(Vector2(at.x + eye_dx, eye_y), eye_r * 0.45, pupil)

	# Mouth: a line, a grin or a grimace depending on who is winning.
	var mouth_y := at.y + 12.0
	if them > you:
		draw_arc(Vector2(at.x, mouth_y - 5.0), 8.0, 0.2, PI - 0.2, 12, pupil, 2.0)
	elif you > them:
		draw_arc(Vector2(at.x, mouth_y + 5.0), 8.0, PI + 0.2, TAU - 0.2, 12, pupil, 2.0)
	else:
		draw_rect(Rect2(at.x - 7.0, mouth_y - 1.0, 14.0, 2.0), pupil)

	# A couple of identifying bits so they read apart at a glance.
	match s.face:
		"smug":
			draw_rect(Rect2(at.x - 16.0, at.y - 26.0, 32.0, 3.0), pupil)      # tiara bar
			draw_circle(Vector2(at.x, at.y - 30.0), 4.0, pupil)
		"brute":
			draw_circle(Vector2(at.x + MALLET_R - 4.0, at.y + 6.0), 7.0, hue.lightened(0.3))
		"alien":
			draw_arc(at, MALLET_R + 6.0, PI * 1.15, PI * 1.85, 16, hue, 2.0)
			draw_circle(Vector2(at.x, at.y - MALLET_R - 6.0), 3.5, hue)
		"mop":
			for i in 7:
				var fx: float = at.x - 21.0 + i * 7.0
				draw_rect(Rect2(fx, at.y - MALLET_R - 9.0, 3.0, 12.0), hue)
		"sleepy":
			Blocks.text(self, Vector2(at.x + MALLET_R - 2.0, at.y - MALLET_R + 2.0), "z", 14, hue.lightened(0.4))


func _draw_bubble() -> void:
	if quip_timer <= 0.0 or quip == "":
		return
	var f := Blocks.font()
	var w: float = f.get_string_size(quip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22.0
	var h := 30.0
	var x: float = clampf(ai.x - w * 0.5, TABLE.position.x + 6.0, TABLE.end.x - w - 6.0)
	var y: float = ai.y + MALLET_R + 12.0

	draw_rect(Rect2(x, y, w, h), Blocks.INK)
	# Little tail pointing back at whoever said it.
	var tip: float = clampf(ai.x, x + 10.0, x + w - 10.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(tip - 6.0, y), Vector2(tip + 6.0, y), Vector2(tip, y - 7.0)
	]), Blocks.INK)
	draw_string(f, Vector2(x + 11.0, y + 20.0), quip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Blocks.PAPER)


func _draw_hud() -> void:
	var x := TABLE.position.x

	Blocks.tracked(self, Vector2(x, 44), "NOW PLAYING", 11, Blocks.INK_MID)
	Blocks.text(self, Vector2(x, 76), _stats().name, 26, Blocks.INK)
	Blocks.tracked(self, Vector2(x, 92), _stats().title, 10, Blocks.INK_FAINT)
	Blocks.rule(self, Vector2(x, 102), TABLE.size.x, Blocks.RED, 3.0)

	Blocks.stat(self, Vector2(x + 250, 44), "YOU", str(you), 26)
	Blocks.stat(self, Vector2(x + 330, 44), "THEM", str(them), 26)
	if Scores.has("puck"):
		Blocks.stat(self, Vector2(x + 400, 44), "BEST", str(int(Scores.get_best("puck"))), 26)

	Blocks.rule(self, Vector2(x, 686), TABLE.size.x, Blocks.INK, 1.0)
	var cy := 706.0
	for line in [
		"MOUSE OR ARROWS  MOVE YOUR MALLET        FIRST TO %d GOALS" % GOALS_TO_WIN,
		"THE WHOLE BACK WALL IS THE GOAL - KEEP IT COVERED",
		"R  RESTART        ESC  MENU",
	]:
		Blocks.tracked(self, Vector2(x, cy), line, 10, Blocks.INK_FAINT)
		cy += 16
