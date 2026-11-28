# Cold Aisle

A first-person horror game set in a data centre at night. You are the only technician on the night shift at Halden DC-3, and the door log starts recording what you do before you do it. About twenty minutes, five acts, three endings. Godot 4.7, Compatibility renderer, exported for the web.

## Play

Open the folder in Godot 4.7 and press Play, or from a terminal:

    godot --path .

Nothing about the controls is shown on the title. Each one is taught in play the first time it is useful, and the pause screen lists them all. For reference: click to capture the mouse, WASD to move, Shift to jog, Ctrl to crouch, F for the torch, E to use things and badge doors, Q for the handheld, Tab (or R) to turn its page, 1 to 5 to set the pixel size, F3 for frame stats, Esc to pause. While paused, `[` `]` change look speed and `-` `=` change volume. Space skips a cutscene.

On a phone or tablet the first touch switches to touch controls and asks the browser for fullscreen and landscape: drag on the left to walk, drag on the right to look, and use the round buttons for everything else. An iPhone does not let a web page go fullscreen; add the page to the home screen to get rid of the browser bars there.

Progress is saved at the start of each act.

## Web build

    godot --headless --export-release "Web" build/web/index.html

The build is single-threaded, so it needs no special server headers. Zip the contents of `build/web` to upload to itch.io.

## Layout

- `scripts/main.gd` is the frame: the low-resolution SubViewport and its lens, the HUD, input, loading, title, pause, the control hints, endings.
- `scripts/cine.gd` plays cutscenes: a list of camera moves with a caption each. The shots themselves are in `story.gd`.
- `scripts/touch.gd` is the touch screen: a floating stick, look by dragging, and buttons.
- `web/shell.html` is the page the web build loads in: the loading screen, and fullscreen on the first touch.
- `scripts/build.gd` assembles the whole building in code: corridor, five small rooms, one data hall in two zones, Cage 7, the chiller plant and the crawl space under the floor. The hall is fourteen aisles of eighty racks, about eighty by fifty-eight metres under a nine metre roof that is never lit, with a cross aisle through the middle and open floor along the far wall. Furniture and services are batched per bay by `_dress_bay` and `_dress_corridor`. Aisles are built in bays of twenty racks that are hidden when you cannot see them, and the strip lights are a small pool that follows the player, which is what keeps a building this size cheap to draw. Each room is drawn a second time upside down under a partly transparent floor, which is where the reflections come from.
- `scripts/story.gd` runs the night: tickets, the door log and its predictions, which doors the badge opens, the events, the cutscenes, the three endings, checkpoints.
- `scripts/bot.gd` is a test player that plays the night with simulated keys.
- `scripts/door.gd`, `player.gd`, `figure.gd`, `handheld.gd`, `terminal.gd`, `cctv.gd`, `sound.gd` are what their names say.
- `shaders/rack_front.gdshader` draws every rack LED procedurally. `floor.gdshader` is the tile floor, `post.gdshader` the lens, `cage_mesh.gdshader` the wire of Cage 7, `cctv.gdshader` the security monitors.
- `audio/` is synthesised by `tools/gen_audio.py` (numpy and ffmpeg). Nothing is sampled.

## Tests

Everything after `--` goes to the game:

    godot --path . -- --playtest=comply --speed=3   # a bot plays the whole night with real key presses and real walking
    godot --path . -- --autotest=comply             # the same night through the story's own calls, in about a minute
    godot --path . -- --walktest                    # walks through every door and the crawl space with real collision
    godot --path . -- --act=4 --at=18.4,0.02,3,3.14 --torch --out=still.png

The endings are `comply`, `defy` and `stay`. The same switches work in the web build as the page address, as in `index.html?playtest=defy&speed=3`; the result is printed to the console and left in `window.coldAisleTest`.

On a machine with no display, put `xvfb-run -a` in front and add `--rendering-driver opengl3`.

Fonts: IBM Plex Mono, SIL Open Font License (see `fonts/LICENSE-IBM-Plex.txt`).
