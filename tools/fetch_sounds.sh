#!/bin/bash
# Fetches the recorded sounds listed in CREDITS.md (all CC0) from OpenGameArt and
# converts them into audio/. The rest of audio/ is synthesised by tools/gen_audio.py.
# usage: tools/fetch_sounds.sh   (needs curl, unzip, ffmpeg)
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
base=https://opengameart.org/sites/default/files
for f in RPGsounds_Kenney.zip sci-fi_sounds.zip UI_SFX_Set.zip 100-CC0-wood-metal-SFX.zip freezer_0.ogg; do
	[ -n "$SRC" ] && [ -f "$SRC/$f" ] && cp "$SRC/$f" "$T/" || curl -sL -A 'Mozilla/5.0' -o "$T/$f" "$base/$f"
done
for z in "$T"/*.zip; do d="${z%.zip}"; mkdir -p "$d"; unzip -qo "$z" -d "$d"; done
src() { find "$T" -name "$1" | head -1; }
# plain: trim to peak -3 dB, mono
plain() { ffmpeg -v error -y -i "$(src "$1")" -af "highpass=f=60,dynaudnorm=p=0.7:m=6,afade=t=out:st=$3:d=0.05" -ac 1 -ar 44100 -c:a libvorbis -q:a 4 "audio/$2.ogg"; }
# far: the same sound heard from the other end of the hall
far() { ffmpeg -v error -y -i "$(src "$1")" -af "apad=pad_dur=1.6,lowpass=f=1500,aecho=0.8:0.75:110|230|390:0.5|0.35|0.22,dynaudnorm=p=0.6:m=4,afade=t=out:st=$3:d=0.6" -ac 1 -ar 44100 -c:a libvorbis -q:a 3 "audio/$2.ogg"; }
plain footstep00.ogg step_s0 0.22
plain footstep01.ogg step_s1 0.25
plain footstep02.ogg step_s2 0.21
plain footstep03.ogg step_s3 0.24
plain footstep04.ogg step_s4 0.29
plain doorOpen_000.ogg door 0.48
plain doorClose_001.ogg door_close 0.48
plain switch2.wav switch 0.25
plain metalLatch.ogg latch 0.22
plain metalClick.ogg click_m 0.4
plain metal_open_01.ogg hatch 1.05
plain bookFlip1.ogg paper 0.7
plain cloth1.ogg cloth0 0.6
plain cloth2.ogg cloth1 0.36
far impactMetal_000.ogg far0 1.6
far impactMetal_002.ogg far1 1.5
far metal_sheet_03.ogg far2 1.6
far metal_falling_01.ogg far3 2.7
far metal_slam_01.ogg far4 1.6
far creak1.ogg far5 1.7
ffmpeg -v error -y -i "$T/freezer_0.ogg" -af "highpass=f=30,lowpass=f=5000" -ac 1 -ar 44100 -c:a libvorbis -q:a 3 audio/bed_deep.ogg
rm -rf "$T"
