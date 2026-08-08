#!/usr/bin/env python3
"""Deterministically synthesize placeholder combat sound effects.

The generator intentionally uses only the Python standard library and an explicit
small PRNG so the emitted WAV files are byte-for-byte reproducible across runs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

SAMPLE_RATE = 44_100
CHANNELS = 1
SAMPLE_WIDTH_BYTES = 2
BITS_PER_SAMPLE = 16
ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "assets" / "audio" / "combat" / "generated"
MANIFEST_PATH = OUTPUT_DIR / "manifest.json"
TAU = math.tau


class XorShift32:
    """Tiny explicit deterministic PRNG, independent of Python's random module."""

    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFF or 0x6D2B79F5

    def u32(self) -> int:
        x = self.state
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= (x >> 17) & 0xFFFFFFFF
        x ^= (x << 5) & 0xFFFFFFFF
        self.state = x & 0xFFFFFFFF
        return self.state

    def uniform(self, low: float = 0.0, high: float = 1.0) -> float:
        return low + (high - low) * (self.u32() / 0xFFFFFFFF)

    def signed(self) -> float:
        return self.uniform(-1.0, 1.0)


@dataclass(frozen=True)
class Cue:
    name: str
    duration: float
    seed: int
    family: str
    weight: float
    base_freq: float = 220.0


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def env_percussive(t: float, duration: float, attack: float, release: float, curve: float = 1.6) -> float:
    if t < attack:
        return t / max(attack, 1e-9)
    remaining = max(duration - t, 0.0)
    return (remaining / max(duration - attack, 1e-9)) ** curve if remaining < release or release >= duration else 1.0


def fade_edges(samples: list[float], fade_ms: float = 4.0) -> None:
    n = min(len(samples) // 2, max(1, int(SAMPLE_RATE * fade_ms / 1000.0)))
    for i in range(n):
        g = 0.5 - 0.5 * math.cos(math.pi * i / n)
        samples[i] *= g
        samples[-1 - i] *= g


def remove_dc(samples: list[float]) -> None:
    if not samples:
        return
    mean = sum(samples) / len(samples)
    for i, sample in enumerate(samples):
        samples[i] = sample - mean


def soft_limit(samples: list[float], drive: float = 1.35) -> None:
    norm = math.tanh(drive)
    for i, sample in enumerate(samples):
        samples[i] = math.tanh(sample * drive) / norm


def normalize_peak(samples: list[float], peak: float = 0.92) -> None:
    current = max((abs(s) for s in samples), default=0.0)
    if current <= 1e-12:
        return
    gain = peak / current
    for i, sample in enumerate(samples):
        samples[i] = clamp(sample * gain, -0.999, 0.999)


def finalize(samples: list[float]) -> list[float]:
    fade_edges(samples)
    remove_dc(samples)
    soft_limit(samples)
    normalize_peak(samples)
    fade_edges(samples)
    remove_dc(samples)
    normalize_peak(samples, 0.90)
    return samples


def burst_noise(rng: XorShift32, amount: float, color_state: list[float]) -> float:
    white = rng.signed()
    color_state[0] = color_state[0] * 0.58 + white * 0.42
    return color_state[0] * amount


def synth_release(cue: Cue) -> list[float]:
    rng = XorShift32(cue.seed)
    frames = int(round(cue.duration * SAMPLE_RATE))
    samples: list[float] = []
    phase = rng.uniform(0, TAU)
    color = [0.0]
    for i in range(frames):
        t = i / SAMPLE_RATE
        p = t / cue.duration
        sweep = cue.base_freq * (1.75 - 1.05 * p)
        phase += TAU * sweep / SAMPLE_RATE
        air_env = math.exp(-8.0 * p)
        tone_env = math.sin(math.pi * clamp(p, 0, 1)) ** 0.45
        blade = math.sin(phase) * 0.35 + math.sin(phase * 2.013) * 0.12
        air = burst_noise(rng, 0.62 * air_env, color)
        samples.append((blade * tone_env + air) * cue.weight)
    return finalize(samples)


def synth_impact(cue: Cue) -> list[float]:
    rng = XorShift32(cue.seed)
    frames = int(round(cue.duration * SAMPLE_RATE))
    samples: list[float] = []
    color = [0.0]
    phase = rng.uniform(0, TAU)
    for i in range(frames):
        t = i / SAMPLE_RATE
        p = t / cue.duration
        hit_env = math.exp(-18.0 * p)
        body_env = math.exp(-7.0 * p)
        phase += TAU * (cue.base_freq * (1.0 - 0.55 * p)) / SAMPLE_RATE
        knock = math.sin(phase) * body_env * 0.54
        crackle = burst_noise(rng, 0.82 * hit_env, color)
        transient = math.sin(TAU * (2300 + 1700 * rng.uniform()) * t) * hit_env * 0.18
        samples.append((knock + crackle + transient) * cue.weight)
    return finalize(samples)


def synth_magic_impact(cue: Cue) -> list[float]:
    rng = XorShift32(cue.seed)
    frames = int(round(cue.duration * SAMPLE_RATE))
    samples: list[float] = []
    phase1 = rng.uniform(0, TAU)
    phase2 = rng.uniform(0, TAU)
    color = [0.0]
    for i in range(frames):
        t = i / SAMPLE_RATE
        p = t / cue.duration
        shimmer_env = math.exp(-3.8 * p)
        burst_env = math.exp(-15.0 * p)
        phase1 += TAU * (cue.base_freq + 280 * math.sin(TAU * 2.1 * t)) / SAMPLE_RATE
        phase2 += TAU * (cue.base_freq * 2.52 - 190 * p) / SAMPLE_RATE
        shimmer = (math.sin(phase1) * 0.36 + math.sin(phase2) * 0.24) * shimmer_env
        burst = burst_noise(rng, 0.62 * burst_env, color)
        samples.append((shimmer + burst) * cue.weight)
    return finalize(samples)


def synth_vocal(cue: Cue) -> list[float]:
    rng = XorShift32(cue.seed)
    frames = int(round(cue.duration * SAMPLE_RATE))
    samples: list[float] = []
    phase = rng.uniform(0, TAU)
    color = [0.0]
    growl = [0.0]
    for i in range(frames):
        t = i / SAMPLE_RATE
        p = t / cue.duration
        pitch_drop = cue.base_freq * (1.16 - 0.55 * p)
        wobble = 1.0 + 0.055 * math.sin(TAU * (5.2 + cue.weight) * t)
        phase += TAU * pitch_drop * wobble / SAMPLE_RATE
        if cue.family == "death":
            env = (math.sin(math.pi * min(p, 0.85) / 0.85) ** 0.32) * math.exp(-0.7 * p)
        elif cue.family == "hurt":
            env = math.exp(-6.6 * p) * min(1.0, p / 0.025)
        else:
            env = math.exp(-5.0 * p) * min(1.0, p / 0.018)
        throat = math.sin(phase) * 0.42 + math.sin(phase * 0.5) * 0.20 + math.sin(phase * 1.97) * 0.10
        growl[0] = growl[0] * 0.72 + rng.signed() * 0.28
        breath = burst_noise(rng, 0.28, color) + growl[0] * 0.22
        samples.append((throat + breath) * env * cue.weight)
    return finalize(samples)


CUES: tuple[Cue, ...] = (
    Cue("sword_light_release", 0.180, 0x8A01_1001, "release", 0.80, 520.0),
    Cue("sword_light_impact", 0.150, 0x8A01_1002, "impact", 0.88, 185.0),
    Cue("sword_heavy_release", 0.280, 0x8A01_1003, "release", 0.92, 390.0),
    Cue("sword_heavy_impact", 0.240, 0x8A01_1004, "impact", 1.00, 130.0),
    Cue("staff_light_release", 0.170, 0x8A01_2001, "release", 0.72, 300.0),
    Cue("staff_heavy_release", 0.260, 0x8A01_2002, "release", 0.84, 235.0),
    Cue("magic_impact", 0.360, 0x8A01_3001, "magic_impact", 0.88, 460.0),
    Cue("player_normal_hurt", 0.300, 0x8A01_4001, "hurt", 0.76, 175.0),
    Cue("player_heavy_hurt", 0.440, 0x8A01_4002, "hurt", 0.90, 138.0),
    Cue("player_death", 0.760, 0x8A01_4003, "death", 0.96, 118.0),
    Cue("grunt_release", 0.230, 0x8A01_5001, "release_voice", 0.72, 125.0),
    Cue("grunt_hurt", 0.330, 0x8A01_5002, "hurt", 0.82, 110.0),
    Cue("grunt_death", 0.670, 0x8A01_5003, "death", 0.88, 88.0),
    Cue("heavy_release", 0.310, 0x8A01_6001, "release_voice", 0.88, 92.0),
    Cue("heavy_hurt", 0.480, 0x8A01_6002, "hurt", 0.95, 82.0),
    Cue("heavy_death", 0.900, 0x8A01_6003, "death", 1.00, 68.0),
)

SYNTHS: dict[str, Callable[[Cue], list[float]]] = {
    "release": synth_release,
    "impact": synth_impact,
    "magic_impact": synth_magic_impact,
    "hurt": synth_vocal,
    "death": synth_vocal,
    "release_voice": synth_vocal,
}


def samples_to_wav_bytes(samples: Iterable[float]) -> bytes:
    pcm = bytearray()
    for sample in samples:
        value = int(round(clamp(sample, -1.0, 1.0) * 32767.0))
        pcm.extend(struct.pack("<h", value))

    data = bytes(pcm)
    byte_rate = SAMPLE_RATE * CHANNELS * SAMPLE_WIDTH_BYTES
    block_align = CHANNELS * SAMPLE_WIDTH_BYTES
    riff_size = 36 + len(data)
    return b"".join(
        (
            b"RIFF",
            struct.pack("<I", riff_size),
            b"WAVE",
            b"fmt ",
            struct.pack("<IHHIIHH", 16, 1, CHANNELS, SAMPLE_RATE, byte_rate, block_align, BITS_PER_SAMPLE),
            b"data",
            struct.pack("<I", len(data)),
            data,
        )
    )


def cue_wav_bytes(cue: Cue) -> bytes:
    return samples_to_wav_bytes(SYNTHS[cue.family](cue))


def build_entries() -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for cue in CUES:
        wav_data = cue_wav_bytes(cue)
        frames = (len(wav_data) - 44) // (CHANNELS * SAMPLE_WIDTH_BYTES)
        entries.append(
            {
                "name": cue.name,
                "path": f"assets/audio/combat/generated/{cue.name}.wav",
                "sha256": hashlib.sha256(wav_data).hexdigest(),
                "format": {
                    "container": "WAV",
                    "encoding": "PCM_SIGNED",
                    "channels": CHANNELS,
                    "sample_rate_hz": SAMPLE_RATE,
                    "bits_per_sample": BITS_PER_SAMPLE,
                    "byte_order": "little_endian",
                },
                "frames": frames,
                "duration_seconds": round(frames / SAMPLE_RATE, 6),
            }
        )
    return entries


def build_manifest() -> dict[str, object]:
    return {
        "generator": "tools/generate_combat_sfx.py",
        "version": 1,
        "determinism": "xorshift32 explicit seeds, no external assets, standard library only",
        "format": {
            "container": "WAV",
            "encoding": "PCM_SIGNED",
            "channels": CHANNELS,
            "sample_rate_hz": SAMPLE_RATE,
            "bits_per_sample": BITS_PER_SAMPLE,
        },
        "cues": build_entries(),
    }


def manifest_bytes(manifest: dict[str, object]) -> bytes:
    return (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")


def write_assets() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for cue in CUES:
        (OUTPUT_DIR / f"{cue.name}.wav").write_bytes(cue_wav_bytes(cue))
    MANIFEST_PATH.write_bytes(manifest_bytes(build_manifest()))
    print(f"wrote {len(CUES)} wav files and {MANIFEST_PATH.relative_to(ROOT)}")
    return 0


def check_wav_header(path: Path, expected_frames: int) -> str | None:
    try:
        with wave.open(str(path), "rb") as handle:
            if handle.getnchannels() != CHANNELS:
                return f"{path}: expected {CHANNELS} channel, got {handle.getnchannels()}"
            if handle.getframerate() != SAMPLE_RATE:
                return f"{path}: expected {SAMPLE_RATE} Hz, got {handle.getframerate()}"
            if handle.getsampwidth() != SAMPLE_WIDTH_BYTES:
                return f"{path}: expected {SAMPLE_WIDTH_BYTES} byte samples, got {handle.getsampwidth()}"
            if handle.getnframes() != expected_frames:
                return f"{path}: expected {expected_frames} frames, got {handle.getnframes()}"
    except wave.Error as exc:
        return f"{path}: invalid wav: {exc}"
    return None


def check_assets() -> int:
    expected_manifest = build_manifest()
    expected_manifest_data = manifest_bytes(expected_manifest)
    failures: list[str] = []

    if not MANIFEST_PATH.exists():
        failures.append(f"missing {MANIFEST_PATH.relative_to(ROOT)}")
    else:
        actual_manifest_data = MANIFEST_PATH.read_bytes()
        if hashlib.sha256(actual_manifest_data).hexdigest() != hashlib.sha256(expected_manifest_data).hexdigest():
            failures.append(f"{MANIFEST_PATH.relative_to(ROOT)} differs from deterministic output")
        try:
            actual_manifest = json.loads(actual_manifest_data.decode("utf-8"))
            if actual_manifest != expected_manifest:
                failures.append(f"{MANIFEST_PATH.relative_to(ROOT)} content does not match expected manifest")
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            failures.append(f"{MANIFEST_PATH.relative_to(ROOT)} is not valid JSON: {exc}")

    entries = {entry["name"]: entry for entry in expected_manifest["cues"]}  # type: ignore[index]
    for cue in CUES:
        path = OUTPUT_DIR / f"{cue.name}.wav"
        entry = entries[cue.name]
        if not path.exists():
            failures.append(f"missing {path.relative_to(ROOT)}")
            continue
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != entry["sha256"]:
            failures.append(f"{path.relative_to(ROOT)} sha256 {digest} != {entry['sha256']}")
        header_error = check_wav_header(path, int(entry["frames"]))
        if header_error:
            failures.append(header_error)

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(f"ok: {len(CUES)} deterministic wav files and manifest verified")
    return 0


def list_cues() -> int:
    for cue in CUES:
        print(f"{cue.name}\t{cue.duration:.3f}s\t{cue.family}\tseed=0x{cue.seed:08x}")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate deterministic combat SFX WAV assets.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write WAV files and manifest")
    mode.add_argument("--check", action="store_true", help="verify files match deterministic output")
    mode.add_argument("--list", action="store_true", help="list generated cues")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.write:
        return write_assets()
    if args.check:
        return check_assets()
    return list_cues()


if __name__ == "__main__":
    raise SystemExit(main())
