# Cold Aisle

A first-person horror game set in a data centre at night. Godot 4.7, Compatibility renderer, exported for the web.

Current state: **milestone 0, the look test** — one walkable aisle of Data Hall A.

## Run

Open the folder in Godot 4.7 and press Play, or from a terminal:

    godot --path .

Controls: click to capture the mouse, WASD to move, Shift to jog, Ctrl to crouch, F for the torch, F3 for frame stats, Esc to release the mouse.

## Web build

    godot --headless --export-release "Web" build/web/index.html

The build is single-threaded, so it needs no special server headers. Zip the contents of `build/web` to upload to itch.io.

## Layout

- `scripts/main.gd` assembles the aisle in code: shell, racks, overhead fibre, strip lights, mirror floor, lens and HUD.
- `scripts/player.gd` is the first-person controller.
- `shaders/rack_front.gdshader` draws every rack LED procedurally.
- `shaders/floor.gdshader` is the glossy tile floor. Reflections come from a mirrored copy of the hall under it.
- `shaders/post.gdshader` is the lens: fringing, vignette, grain, eyelid.

Fonts: IBM Plex Mono, SIL Open Font License (see `fonts/LICENSE-IBM-Plex.txt`).
