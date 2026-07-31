# Snackbox

A small collection of casual games built in Godot 4. GDScript only, no external
assets — every board, piece, virus and panel is drawn procedurally.

## Running

Open the folder as a project in Godot 4.4+ and press F5, or:

```sh
task run                       # run it
task test                      # play every game headlessly, check invariants
task install                   # build and drop Snackbox.app in /Applications
task --list                    # everything else
```

Jump straight into a game while developing:

```sh
task run -- --game=landgrab
```

## The games

### Blockfall

Falling blocks. SRS rotation with the full wall-kick tables, 7-bag randomizer,
hold, ghost piece, lock delay with move resets, and DAS/ARR repeat.

| Mode | Goal |
| --- | --- |
| Marathon | Endless. Speed climbs every 10 lines. |
| Sprint | Clear 40 lines as fast as possible. |
| Ultra | Score as much as you can in 2 minutes. |

Controls: `← →` move, `↓` soft drop, `Space` hard drop, `↑`/`X` rotate cw,
`Z` rotate ccw, `C` hold, `P` pause, `R` restart, `Esc` menu.

### Pill Doctor

Drop two-tone pills into the bottle and line up four or more of a colour to wipe
them out. Clearing a match drops whatever was resting on it, which can set off
chains. Clear every virus to advance; each level adds viruses and stacks them
higher.

Controls: `← →` move, `↓` soft drop, `Space` hard drop, `↑`/`X` rotate cw,
`Z` rotate ccw, `P` pause, `R` restart, `Esc` menu.

### Landgrab

Qix style area claiming. Hold a direction to cut into open space, then get back
to solid ground to seal the cut. Any pocket the drifters aren't in becomes
yours. Claim 75% to clear the level. Getting clipped while exposed — on your
trail or at its tip — costs a life.

Controls: `← → ↑ ↓` move, `R` restart, `Esc` menu.

## Layout

| File | Purpose |
| --- | --- |
| `main.gd` / `main.tscn` | App shell: window sizing, menu, screen swapping |
| `menu.gd` / `menu.tscn` | Game picker |
| `blocks.gd` | Shared palette and drawing helpers |
| `game.gd` / `game.tscn` | Blockfall (all three modes) |
| `pills.gd` / `pills.tscn` | Pill Doctor |
| `landgrab.gd` / `landgrab.tscn` | Landgrab |
| `tests/smoke.gd` | Headless test suite |
| `Taskfile.yml` | Run, test, build, install |

Each game is an independent scene that draws itself and emits `exit_to_menu`.
They share the drawing helpers in `blocks.gd` and nothing else — the boards and
rules have little in common, and forcing a shared abstraction would cost more
than it saves. Adding a game means dropping in a scene, adding a row to
`Menu.ENTRIES`, and an entry in `Main.GAMES`.

## Tests

`task test` drives every game with a fixed timestep and random input for
thousands of simulated frames, checking invariants continuously: pieces never
overlap the stack, pill halves always keep a matching partner, virus counters
match the board, the player never stands on unclaimed space. It also runs
deterministic scenarios for pill clears, chains, and sealing a Landgrab pocket.

## License

MIT — see [LICENSE](LICENSE).
