# Blockfall

A simple, colorful falling-block puzzle game built in Godot 4 (GDScript, no external assets — everything is drawn procedurally).

## Running

Open the folder as a project in Godot 4.4+ and press F5, or from the terminal:

```sh
/Applications/Godot_mono.app/Contents/MacOS/Godot --path .
```

The window sizes itself to fill most of your screen on launch and scales cleanly if you resize it.

## Controls

| Key | Action |
| --- | --- |
| ← / → | Move |
| ↓ | Soft drop |
| Space | Hard drop |
| ↑ or X | Rotate clockwise |
| Z | Rotate counter-clockwise |
| A | Rotate 180° |
| C or Shift | Hold |
| P or Esc | Pause |
| R | Restart |

## What's implemented

- Standard 10×20 playfield with a 2-row spawn buffer
- SRS rotation with the full wall-kick tables (separate table for I)
- 7-bag randomizer, 3-piece next queue, hold with one-use-per-piece lock
- Ghost piece, lock delay (0.5s, max 15 move resets), DAS/ARR horizontal repeat
- Guideline scoring (100/300/500/800 × level, +1 per soft-drop cell, +2 per hard-drop cell)
- Level up every 10 lines with an accelerating gravity curve

## Layout

| File | Purpose |
| --- | --- |
| `project.godot` | Project settings, window size, stretch mode |
| `main.tscn` | Single-node scene |
| `game.gd` | All game logic and rendering |
| `Taskfile.yml` | Run/build/export tasks (`task --list`) |

## License

MIT — see [LICENSE](LICENSE).
