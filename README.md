# Cold Aisle

A first-person horror game set in a data centre at night. You are the only technician on the night shift at Halden DC-3, and the door log starts recording what you do before you do it. About twenty minutes, five acts, three endings. Godot 4.7, Compatibility renderer, exported for the web.

## Play

Open the folder in Godot 4.7 and press Play, or from a terminal:

    godot --path .

Controls: click to capture the mouse, WASD to move, Shift to jog, Ctrl to crouch, F for the torch, E to use things and badge doors, Q for the handheld, Tab (or R) to turn its page, 1 to 5 to set the pixel size, F3 for frame stats, Esc to pause. While paused, `[` `]` change look speed and `-` `=` change volume.

Progress is saved at the start of each act.

## Web build

    godot --headless --export-release "Web" build/web/index.html

The build is single-threaded, so it needs no special server headers. Zip the contents of `build/web` to upload to itch.io.

## Layout

- `scripts/main.gd` is the frame: the low-resolution SubViewport and its lens, the HUD, input, title, pause, endings.
- `scripts/build.gd` assembles the whole building in code: corridor, five small rooms, two data halls, Cage 7, the chiller plant and the crawl space under the floor. Each room is drawn a second time upside down under a partly transparent floor, which is where the reflections come from.
- `scripts/story.gd` runs the night: tickets, the door log and its predictions, which doors the badge opens, the events, the three endings, checkpoints.
- `scripts/door.gd`, `player.gd`, `figure.gd`, `handheld.gd`, `terminal.gd`, `cctv.gd`, `sound.gd` are what their names say.
- `shaders/rack_front.gdshader` draws every rack LED procedurally. `floor.gdshader` is the tile floor, `post.gdshader` the lens, `cage_mesh.gdshader` the wire of Cage 7, `cctv.gdshader` the security monitors.
- `audio/` is synthesised by `tools/gen_audio.py` (numpy and ffmpeg). Nothing is sampled.

## Tests

Everything after `--` goes to the game:

    godot --path . -- --autotest=comply     # plays the whole night to an ending: comply, defy or stay
    godot --path . -- --walktest            # walks through every door and the crawl space with real collision
    godot --path . -- --act=4 --at=18.4,0.02,3,3.14 --torch --out=still.png

On a machine with no display, put `xvfb-run -a` in front and add `--rendering-driver opengl3`.

Fonts: IBM Plex Mono, SIL Open Font License (see `fonts/LICENSE-IBM-Plex.txt`).
