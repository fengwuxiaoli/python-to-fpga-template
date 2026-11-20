"""Stage 1 Python Golden Reference for the 15-Tap Symmetric FIR Canary Block.

Provides:
  - Floating-point behavioral reference (`fir_float`)
  - Bit-exact Q1.15 fixed-point reference (`fir_fixed`) matching `rtl/canary_fir_core.sv`
  - Standalone quantitative self-test (DC gain, Nyquist stopband, float vs. fixed error, saturation)
"""

from __future__ import annotations

import math

NUM_TAPS = 15
NUM_SYM_TAPS = 8

# Symmetric Q1.15 low-pass FIR taps (dc sum = 2*sum(taps[0..6]) + taps[7] = 32767)
DEFAULT_TAPS: list[int] = [-214, -327, 0, 992, 2525, 4351, 5839, 6435]

# Alternate Q1.15 symmetric taps for AXI4-Lite runtime coefficient reprogramming tests (sum = 32767)
CUSTOM_TAPS: list[int] = [0, 0, -512, 0, 2048, 4096, 6144, 9215]


def expand_symmetric_taps(sym_taps: list[int]) -> list[int]:
    """Expand 8 unique symmetric taps [h0..h7] to full 15-tap kernel [h0..h7..h0]."""
    if len(sym_taps) != NUM_SYM_TAPS:
        raise ValueError(f"Expected {NUM_SYM_TAPS} symmetric taps, got {len(sym_taps)}")
    return sym_taps[:-1] + [sym_taps[-1]] + list(reversed(sym_taps[:-1]))


def fir_float(samples: list[int], sym_taps: list[int] = DEFAULT_TAPS) -> list[float]:
    """Causal floating-point FIR reference normalized to Q1.15 scale (1.0 == 32768)."""
    kernel = [h / 32768.0 for h in expand_symmetric_taps(sym_taps)]
    delay = [0.0] * (NUM_TAPS - 1)
    outputs: list[float] = []
    for sample in samples:
        x0 = float(sample) / 32768.0
        window = [x0] + delay
        outputs.append(sum(w * h for w, h in zip(window, kernel)))
        delay = [x0] + delay[:-1]
    return outputs


def fir_fixed(
    samples: list[int],
    sym_taps: list[int] = DEFAULT_TAPS,
    initial_delay: list[int] | None = None,
) -> tuple[list[int], int]:
    """Bit-exact fixed-point 15-tap symmetric FIR matching `rtl/canary_fir_core.sv`.

    Arithmetic:
      - Pre-add symmetric pairs in 17-bit signed arithmetic
      - Multiply by 16-bit Q1.15 taps in 33-bit signed arithmetic
      - Accumulate in 36-bit signed arithmetic
      - Round half-up: `(acc + 16384) >> 15` (matches SV signed `>>> 15`)
      - Saturate to signed 16-bit [-32768, 32767]
    """
    if len(sym_taps) != NUM_SYM_TAPS:
        raise ValueError(f"Expected {NUM_SYM_TAPS} symmetric taps, got {len(sym_taps)}")

    delay = list(initial_delay) if initial_delay is not None else [0] * (NUM_TAPS - 1)
    if len(delay) != NUM_TAPS - 1:
        raise ValueError(f"Expected delay length {NUM_TAPS - 1}, got {len(delay)}")

    outputs: list[int] = []
    ovf_count = 0

    for x0 in samples:
        window = [int(x0)] + delay
        acc = sum((window[k] + window[14 - k]) * sym_taps[k] for k in range(7)) + window[7] * sym_taps[7]
        scaled = (acc + 16384) >> 15
        if scaled > 32767:
            out = 32767
            ovf_count += 1
        elif scaled < -32768:
            out = -32768
            ovf_count += 1
        else:
            out = scaled
        outputs.append(out)
        delay = [int(x0)] + delay[:-1]

    return outputs, ovf_count


def freq_response_mag_db(sym_taps: list[int], norm_freq: float) -> float:
    """Compute magnitude response in dB at normalized frequency f/fs in [0, 0.5]."""
    kernel = [h / 32768.0 for h in expand_symmetric_taps(sym_taps)]
    re = sum(h * math.cos(2.0 * math.pi * norm_freq * n) for n, h in enumerate(kernel))
    im = sum(-h * math.sin(2.0 * math.pi * norm_freq * n) for n, h in enumerate(kernel))
    mag = math.hypot(re, im)
    return 20.0 * math.log10(max(mag, 1e-12))


def main() -> int:
    dc_sum_default = 2 * sum(DEFAULT_TAPS[:-1]) + DEFAULT_TAPS[-1]
    dc_sum_custom = 2 * sum(CUSTOM_TAPS[:-1]) + CUSTOM_TAPS[-1]
    assert dc_sum_default == 32767, f"DEFAULT_TAPS DC sum={dc_sum_default}, expected 32767"
    assert dc_sum_custom == 32767, f"CUSTOM_TAPS DC sum={dc_sum_custom}, expected 32767"

    dc_db = freq_response_mag_db(DEFAULT_TAPS, 0.0)
    pass_db = freq_response_mag_db(DEFAULT_TAPS, 0.05)
    stop_db = freq_response_mag_db(DEFAULT_TAPS, 0.42)
    nyq_db = freq_response_mag_db(DEFAULT_TAPS, 0.50)

    assert abs(dc_db) < 0.01, f"DC gain off unity: {dc_db:.4f} dB"
    assert stop_db < -35.0, f"Stopband @ 0.42*fs insufficient: {stop_db:.2f} dB"
    assert nyq_db < -40.0, f"Nyquist attenuation insufficient: {nyq_db:.2f} dB"

    # Composite 256-sample test signal: impulse + low-freq tone + high-freq stopband tone
    n = 256
    stim: list[int] = []
    for i in range(n):
        if i < 32:
            stim.append(16384 if i == 0 else 0)
        else:
            val = 12000.0 * math.sin(2.0 * math.pi * 0.05 * i) + 12000.0 * math.sin(2.0 * math.pi * 0.42 * i)
            stim.append(int(round(val)))

    flt = fir_float(stim, DEFAULT_TAPS)
    fix, ovf = fir_fixed(stim, DEFAULT_TAPS)
    assert ovf == 0, f"Unexpected overflow on composite stimulus: {ovf}"

    max_err_norm = max(abs(f - (x / 32768.0)) for f, x in zip(flt, fix))
    max_err_lsb = max_err_norm * 32768.0
    assert max_err_lsb <= 0.51, f"Fixed-vs-float error exceeded 0.51 LSB: {max_err_lsb:.4f}"

    # Verify saturation clamp & overflow reporting with amplified gain
    sat_taps = [0, 0, 0, 0, 0, 0, 32767, 32767]  # 3x gain on constant full scale
    sat_out, sat_ovf = fir_fixed([32767] * 16, sat_taps)
    assert sat_ovf > 0 and max(sat_out) == 32767, "Expected saturation clamp on overdrive input"

    print(
        "[canary_fir] Stage 1 Golden Verification PASS | "
        f"DC={dc_db:+.4f} dB | Pass(0.05fs)={pass_db:+.2f} dB | "
        f"Stop(0.42fs)={stop_db:.2f} dB | Nyq={nyq_db:.2f} dB | "
        f"Float-vs-Fixed MaxErr={max_err_lsb:.4f} LSB (< 0.51) | OVF_check={sat_ovf} events"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
