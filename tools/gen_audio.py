#!/usr/bin/env python3
"""Synthesise every sound in Cold Aisle. All of it is original: filtered noise and sines.

    python3 tools/gen_audio.py        # writes audio/*.ogg (needs numpy and ffmpeg)

Loops are built in the frequency domain, so they repeat without a seam.
"""
import os, subprocess, tempfile, wave
import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
rng = np.random.default_rng(7)


def noise_loop(secs, shape):
    """Periodic noise whose spectrum is shape(freq_hz)."""
    n = int(SR * secs)
    f = np.fft.rfftfreq(n, 1 / SR)
    spec = (rng.normal(size=f.size) + 1j * rng.normal(size=f.size)) * shape(np.maximum(f, 1.0))
    spec[0] = 0
    return np.fft.irfft(spec, n)


def band(f, lo, hi, slope=2.0):
    return 1.0 / (1.0 + (lo / f) ** (2 * slope)) / (1.0 + (f / hi) ** (2 * slope))


def tone_loop(secs, freqs_amps):
    """Sines snapped to whole cycles per loop, so they also repeat cleanly."""
    n = int(SR * secs)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for hz, amp in freqs_amps:
        hz = round(hz * secs) / secs
        out += amp * np.sin(2 * np.pi * hz * t + rng.uniform(0, 6.28))
    return out


def norm(x, peak=0.7):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / decay)


def shot(secs, fn):
    n = int(SR * secs)
    t = np.arange(n) / SR
    return fn(t, n)


def filt(x, lo, hi):
    f = np.fft.rfftfreq(x.size, 1 / SR)
    return np.fft.irfft(np.fft.rfft(x) * band(np.maximum(f, 1.0), lo, hi), x.size)


def save(name, x, peak=0.7):
    x = norm(np.asarray(x, dtype=np.float64), peak)
    pcm = (x * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "3",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    L = 8.0
    # room beds: filtered air plus a low two-note hum, retuned per room
    save("bed_hall_a", noise_loop(L, lambda f: band(f, 180, 5200, 1.0) / f ** 0.35) * 1.0
         + norm(tone_loop(L, [(58, 1.0), (87, 0.6), (116, 0.25)]), 0.05), 0.6)
    save("bed_hall_b", noise_loop(L, lambda f: band(f, 70, 1600, 1.0) / f ** 0.6) * 1.0
         + norm(tone_loop(L, [(46, 1.0), (47.5, 0.9), (92, 0.4), (69, 0.5)]), 0.012), 0.6)
    save("bed_plant", noise_loop(L, lambda f: band(f, 30, 700, 1.0) / f ** 0.8) * 1.0
         + norm(tone_loop(L, [(50, 1.0), (100, 0.7), (150, 0.3), (33, 0.8)]), 0.006), 0.65)
    wind = noise_loop(L, lambda f: band(f, 60, 420, 1.5) / f ** 0.5)
    wind *= 0.6 + 0.4 * np.sin(2 * np.pi * np.arange(wind.size) / wind.size * 2)
    save("bed_plenum", wind, 0.55)
    save("bed_room", noise_loop(L, lambda f: band(f, 90, 900, 1.0) / f ** 0.9)
         + norm(tone_loop(L, [(50, 1.0), (100, 0.3)]), 0.0015), 0.35)
    # the suppression alarm: two-tone sounder
    n = int(SR * 2.0)
    t = np.arange(n) / SR
    hz = np.where((t % 1.0) < 0.5, 800.0, 970.0)
    alarm = np.sin(2 * np.pi * np.cumsum(hz) / SR)
    alarm = np.sign(alarm) * np.abs(alarm) ** 0.5
    save("alarm", filt(alarm, 300, 3000), 0.5)

    # one-shots
    def step(pitch, ring):
        def fn(t, n):
            thud = filt(rng.normal(size=n), 60, 900 * pitch) * env(n, 0.002, 0.035)
            tick = filt(rng.normal(size=n), 1500, 6000) * env(n, 0.001, 0.008) * 0.35
            return thud + tick + ring * np.sin(2 * np.pi * 410 * pitch * t) * env(n, 0.002, 0.09)
        return shot(0.3, fn)
    for i, p in enumerate([1.0, 0.9, 1.12]):
        save("step_s%d" % i, step(p, 0.0), 0.5)
        save("step_p%d" % i, step(p * 1.3, 0.25), 0.5)
    save("beep", shot(0.22, lambda t, n: np.sin(2 * np.pi * 1320 * t) * env(n, 0.003, 0.07)
                      + np.roll(np.sin(2 * np.pi * 1760 * t) * env(n, 0.003, 0.06), int(SR * 0.09))), 0.4)
    save("deny", shot(0.4, lambda t, n: np.sign(np.sin(2 * np.pi * 150 * t)) * env(n, 0.004, 0.25) * (t < 0.3)), 0.35)
    save("door", shot(0.9, lambda t, n: filt(rng.normal(size=n), 200, 1800) * np.sin(np.pi * np.minimum(t / 0.8, 1.0)) ** 2 * 0.5
                      + np.sin(2 * np.pi * (90 + 30 * t) * t) * env(n, 0.05, 0.4) * 0.5), 0.5)
    save("tone", shot(0.9, lambda t, n: np.sin(2 * np.pi * 880 * t) * env(n, 0.004, 0.18)
                      + np.roll(np.sin(2 * np.pi * 659 * t) * env(n, 0.004, 0.3), int(SR * 0.16))), 0.45)
    save("tick", shot(0.25, lambda t, n: filt(rng.normal(size=n), 900, 7000) * env(n, 0.0005, 0.006)
                      + np.sin(2 * np.pi * 120 * t) * env(n, 0.001, 0.05) * 0.6), 0.6)
    save("relay", shot(0.2, lambda t, n: filt(rng.normal(size=n), 400, 3500) * env(n, 0.0005, 0.012)), 0.5)
    save("breaker", shot(1.2, lambda t, n: filt(rng.normal(size=n), 50, 1500) * env(n, 0.001, 0.07)
                         + np.sin(2 * np.pi * 50 * t) * env(n, 0.02, 0.5) * 0.7), 0.75)
    save("swap", shot(1.6, lambda t, n: filt(rng.normal(size=n), 500, 4000) * (env(n, 0.001, 0.02)
                      + np.roll(env(n, 0.001, 0.03), int(SR * 0.7)) + np.roll(env(n, 0.001, 0.015), int(SR * 1.2)))
                      + np.sin(2 * np.pi * 300 * t) * np.roll(env(n, 0.3, 0.3), int(SR * 0.75)) * 0.1), 0.5)
    save("swell", shot(5.0, lambda t, n: (np.sin(2 * np.pi * 41 * t) + 0.5 * np.sin(2 * np.pi * 61.5 * t))
                       * np.sin(np.pi * t / 5.0) ** 2), 0.8)
    save("chord", shot(12.0, lambda t, n: sum(a * np.sin(2 * np.pi * hz * t + ph) for hz, a, ph in
                       [(55, 1, 0), (82.4, .7, 1), (110, .5, 2), (164.8, .35, 3), (196, .25, 4), (329.6, .12, 5)])
                       * np.minimum(t / 3.0, 1.0) * np.minimum((12.0 - t) / 4.0, 1.0)), 0.6)
    save("thump", shot(1.5, lambda t, n: np.sin(2 * np.pi * (70 * np.exp(-t * 6) + 30) * t) * env(n, 0.003, 0.35)
                       + filt(rng.normal(size=n), 40, 300) * env(n, 0.002, 0.2) * 0.6), 0.85)
    save("tile", shot(0.9, lambda t, n: filt(rng.normal(size=n), 150, 2500) * env(n, 0.2, 0.15) * 0.6
                      + np.roll(filt(rng.normal(size=n), 80, 1200) * env(n, 0.001, 0.05), int(SR * 0.55))), 0.6)
    save("powerdown", shot(4.0, lambda t, n: np.sin(2 * np.pi * np.cumsum(220 * np.exp(-t * 1.1) + 20) / SR)
                           * np.exp(-t * 0.9) + filt(rng.normal(size=n), 100, 3000) * np.exp(-t * 1.6) * 0.8), 0.8)
    save("chime", shot(2.2, lambda t, n: np.sin(2 * np.pi * 587 * t) * env(n, 0.005, 0.6)
                       + np.roll(np.sin(2 * np.pi * 440 * t) * env(n, 0.005, 0.8), int(SR * 0.5))), 0.35)
    save("stall", shot(2.4, lambda t, n: np.sin(2 * np.pi * np.cumsum(140 * np.exp(-t * 1.4) + 24) / SR) * env(n, 0.05, 0.9)
                       + filt(rng.normal(size=n), 80, 900) * np.exp(-t * 1.8) * 0.7), 0.6)
    save("static", noise_loop(1.0, lambda f: band(f, 800, 9000, 1.0)), 0.3)
    print("wrote", len(os.listdir(OUT)), "files to audio/")


if __name__ == "__main__":
    main()
