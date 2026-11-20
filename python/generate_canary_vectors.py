"""Generate deterministic $readmemh vectors for the 15-tap canary FIR."""

from __future__ import annotations

import math
from pathlib import Path

from canary_fir_golden import CUSTOM_TAPS, DEFAULT_TAPS, fir_fixed


def write_hex16(path: Path, values: list[int]) -> None:
    """Write signed 16-bit values as 4-digit two's-complement hex lines."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for v in values:
            fh.write(f"{v & 0xFFFF:04X}\n")


def build_stimulus(num_samples: int = 256) -> list[int]:
    """Deterministic 256-sample Q1.15 stimulus covering impulse, two-tone, and rails."""
    stim: list[int] = []
    for i in range(num_samples):
        if i == 0:
            stim.append(16384)
        elif i < 32:
            stim.append(0)
        elif i < 192:
            val = 12000.0 * math.sin(2.0 * math.pi * 0.05 * i) + 12000.0 * math.sin(2.0 * math.pi * 0.42 * i)
            stim.append(int(round(val)))
        else:
            stim.append(28000 if (i % 2 == 0) else -28000)
    return stim


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    vec_dir = repo / "test_vectors"

    stim = build_stimulus(256)
    exp_default, ovf_def = fir_fixed(stim, DEFAULT_TAPS)
    exp_custom, ovf_cust = fir_fixed(stim, CUSTOM_TAPS)

    if ovf_def != 0 or ovf_cust != 0:
        raise RuntimeError(f"Unexpected overflow in canary vectors: default={ovf_def}, custom={ovf_cust}")

    files = {
        vec_dir / "canary_coeffs_default.mem": DEFAULT_TAPS,
        vec_dir / "canary_coeffs_custom.mem": CUSTOM_TAPS,
        vec_dir / "canary_stim.mem": stim,
        vec_dir / "canary_exp_default.mem": exp_default,
        vec_dir / "canary_exp_custom.mem": exp_custom,
    }
    for path, vals in files.items():
        write_hex16(path, vals)
        print(f"WROTE {path} ({len(vals)} words)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
