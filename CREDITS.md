# Credits and licences

Cold Aisle's code, shaders and level are original to this repository.

## Sound

Most sounds are synthesised by `tools/gen_audio.py` and belong to this project: the fan
beds, alarms, beeps, tones, the perforated-tile footsteps and the stingers.

The recorded sounds below are third-party and all released under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain dedication):
no attribution is required, and it is given here anyway. They were downloaded from
OpenGameArt and trimmed, filtered and converted by `tools/fetch_sounds.sh`.

| Files in `audio/` | Source | Author | Licence |
| --- | --- | --- | --- |
| `step_s0`–`step_s4` (footsteps), `latch`, `click_m`, `paper`, `cloth0`, `cloth1` | [50 RPG sound effects](https://opengameart.org/content/50-rpg-sound-effects) | Kenney (kenney.nl) | CC0 |
| `door`, `door_close`, `far0`, `far1` | [Sci-Fi Sounds](https://opengameart.org/content/sci-fi-sounds) | Kenney (kenney.nl) | CC0 |
| `switch` | [51 UI sound effects](https://opengameart.org/content/51-ui-sound-effects-buttons-switches-and-clicks) | Kenney (kenney.nl) | CC0 |
| `hatch`, `far2`, `far3`, `far4` | [100 CC0 metal and wood SFX](https://opengameart.org/content/100-cc0-metal-and-wood-sfx) | rubberduck | CC0 |
| `far5` | [50 RPG sound effects](https://opengameart.org/content/50-rpg-sound-effects) | Kenney (kenney.nl) | CC0 |
| `bed_deep` | [Abandoned passages (horror ambience loop)](https://opengameart.org/content/abandoned-passages-horror-ambience-loop) | congusbongus | CC0 |

The `far*` sounds are the originals with a low-pass filter and echo added, to place them
at the other end of the hall.

## Font

IBM Plex Mono, © IBM Corp., SIL Open Font License 1.1.

## Engine

Godot Engine, MIT licence.
