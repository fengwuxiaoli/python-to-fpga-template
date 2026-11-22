"""AXI4-Lite register map and MMIO helper for the 15-tap Canary Symmetric FIR.

Matches `rtl/canary_fir_regs.sv`, `sw/canary_fir_regs.h`, and `SPEC.md`.
Uses Python standard library only so it runs standalone on PYNQ, Linux, or host tools.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Protocol


class MmIoDevice(Protocol):
    """Duck-typed 32-bit MMIO interface compatible with `pynq.MMIO`."""

    def read(self, offset: int) -> int: ...

    def write(self, offset: int, data: int) -> None: ...


# Address Map Geometry (8-bit byte offset, 256-byte window)
DEFAULT_BASE_ADDR: int = 0xA0000000
ADDR_WINDOW_BYTES: int = 0x100

REG_VERSION: int = 0x00
REG_CTRL: int = 0x04
REG_STATUS: int = 0x08
REG_COEFF_BASE: int = 0x10
REG_COEFF_STRIDE: int = 0x04

# Hardware Identity & Datapath Geometry
VERSION_EXPECTED: int = 0x46495231
VERSION_ASCII: str = "FIR1"
NUM_TAPS: int = 15
NUM_SYM_TAPS: int = 8
FLUSH_ZEROS: int = 14
PIPELINE_LATENCY: int = 5

# Register Bit Fields
CTRL_BYPASS_EN_BIT: int = 0
CTRL_BYPASS_EN_MASK: int = 0x00000001
STATUS_OVF_STICKY_BIT: int = 0
STATUS_OVF_STICKY_MASK: int = 0x00000001
COEFF_DATA_MASK: int = 0x0000FFFF

# Default & Alternate Q1.15 Symmetric Taps
DEFAULT_COEFFS: tuple[int, ...] = (-214, -327, 0, 992, 2525, 4351, 5839, 6435)
CUSTOM_COEFFS: tuple[int, ...] = (0, 0, -512, 0, 2048, 4096, 6144, 9215)


def coeff_offset(idx: int) -> int:
    """Return byte offset for symmetric tap `COEFF[idx]` (`0 <= idx < 8`)."""
    if not 0 <= idx < NUM_SYM_TAPS:
        raise ValueError(f"Coefficient index {idx} out of range [0, {NUM_SYM_TAPS - 1}]")
    return REG_COEFF_BASE + (idx * REG_COEFF_STRIDE)


def pack_coeff(val: int) -> int:
    """Encode signed 16-bit Q1.15 tap as sign-extended 32-bit unsigned AXI4-Lite word."""
    if not -32768 <= val <= 32767:
        raise ValueError(f"Q1.15 coefficient {val} out of signed 16-bit range [-32768, 32767]")
    return val & 0xFFFFFFFF


def unpack_coeff(reg_val: int) -> int:
    """Decode 32-bit AXI4-Lite `COEFF[k]` readback word to signed 16-bit int."""
    low16 = reg_val & COEFF_DATA_MASK
    return low16 - 0x10000 if (low16 & 0x8000) else low16


def format_version(reg_val: int) -> str:
    """Format 32-bit `VERSION` register as printable 4-byte ASCII string."""
    raw = (reg_val & 0xFFFFFFFF).to_bytes(4, byteorder="big")
    return "".join(chr(b) if 32 <= b < 127 else "?" for b in raw)


class CanaryFirMmio:
    """High-level AXI4-Lite register helper wrapping a `read`/`write` MMIO object."""

    def __init__(self, mmio: MmIoDevice) -> None:
        self._mmio = mmio

    def read_version(self) -> int:
        return self._mmio.read(REG_VERSION) & 0xFFFFFFFF

    def check_version(self) -> int:
        ver = self.read_version()
        if ver != VERSION_EXPECTED:
            raise RuntimeError(
                f"canary_fir VERSION mismatch: got 0x{ver:08X} ('{format_version(ver)}'), "
                f"expected 0x{VERSION_EXPECTED:08X} ('{VERSION_ASCII}')"
            )
        return ver

    def get_bypass(self) -> bool:
        return bool(self._mmio.read(REG_CTRL) & CTRL_BYPASS_EN_MASK)

    def set_bypass(self, enabled: bool) -> None:
        self._mmio.write(REG_CTRL, CTRL_BYPASS_EN_MASK if enabled else 0)

    def read_overflow_sticky(self) -> bool:
        return bool(self._mmio.read(REG_STATUS) & STATUS_OVF_STICKY_MASK)

    def clear_overflow_sticky(self) -> None:
        self._mmio.write(REG_STATUS, STATUS_OVF_STICKY_MASK)

    def write_coeffs(self, coeffs: Sequence[int]) -> None:
        if len(coeffs) != NUM_SYM_TAPS:
            raise ValueError(f"Expected {NUM_SYM_TAPS} symmetric coefficients, got {len(coeffs)}")
        for idx, coeff in enumerate(coeffs):
            self._mmio.write(coeff_offset(idx), pack_coeff(int(coeff)))

    def read_coeffs(self) -> list[int]:
        return [unpack_coeff(self._mmio.read(coeff_offset(idx))) for idx in range(NUM_SYM_TAPS)]


class _MockCanaryMmio:
    """In-memory behavioral register model matching `rtl/canary_fir_regs.sv`."""

    def __init__(self) -> None:
        self.regs: dict[int, int] = {
            REG_VERSION: VERSION_EXPECTED,
            REG_CTRL: 0,
            REG_STATUS: STATUS_OVF_STICKY_MASK,  # Pre-set sticky bit to test W1C clear
        }
        for idx, tap in enumerate(DEFAULT_COEFFS):
            self.regs[coeff_offset(idx)] = pack_coeff(tap)

    def read(self, offset: int) -> int:
        return self.regs.get(offset, 0) & 0xFFFFFFFF

    def write(self, offset: int, data: int) -> None:
        val = data & 0xFFFFFFFF
        if offset == REG_CTRL:
            self.regs[REG_CTRL] = val & CTRL_BYPASS_EN_MASK
        elif offset == REG_STATUS:
            if val & STATUS_OVF_STICKY_MASK:
                self.regs[REG_STATUS] = 0
        elif REG_COEFF_BASE <= offset <= coeff_offset(NUM_SYM_TAPS - 1) and (offset - REG_COEFF_BASE) % 4 == 0:
            self.regs[offset] = pack_coeff(unpack_coeff(val))


def _run_self_test() -> int:
    import sys
    from pathlib import Path

    py_dir = Path(__file__).resolve().parent.parent / "python"
    if str(py_dir) not in sys.path:
        sys.path.insert(0, str(py_dir))
    import canary_fir_golden  # noqa: E402

    # 1. Verify exact parity with Stage 1 Python golden constants
    assert NUM_TAPS == canary_fir_golden.NUM_TAPS
    assert NUM_SYM_TAPS == canary_fir_golden.NUM_SYM_TAPS
    assert list(DEFAULT_COEFFS) == canary_fir_golden.DEFAULT_TAPS
    assert list(CUSTOM_COEFFS) == canary_fir_golden.CUSTOM_TAPS

    # 2. Verify signed 16-bit Q1.15 pack/unpack round-trips and bounds checks
    for sample in (-32768, -512, -214, 0, 1, 6435, 32767):
        packed = pack_coeff(sample)
        assert unpack_coeff(packed) == sample, f"Round-trip failed for {sample}"
    assert pack_coeff(-214) == 0xFFFFFF2A
    assert format_version(VERSION_EXPECTED) == VERSION_ASCII

    for bad_val in (-32769, 32768):
        try:
            pack_coeff(bad_val)
            raise AssertionError(f"Expected ValueError for {bad_val}")
        except ValueError:
            pass

    for bad_idx in (-1, NUM_SYM_TAPS):
        try:
            coeff_offset(bad_idx)
            raise AssertionError(f"Expected ValueError for idx={bad_idx}")
        except ValueError:
            pass

    # 3. Verify mock MMIO lifecycle (VERSION, CTRL, COEFF[0..7], R/W1C STATUS)
    fir = CanaryFirMmio(_MockCanaryMmio())
    assert fir.check_version() == VERSION_EXPECTED
    assert fir.read_coeffs() == list(DEFAULT_COEFFS)
    assert not fir.get_bypass()

    fir.set_bypass(True)
    assert fir.get_bypass()
    fir.set_bypass(False)
    assert not fir.get_bypass()

    fir.write_coeffs(CUSTOM_COEFFS)
    assert fir.read_coeffs() == list(CUSTOM_COEFFS)

    assert fir.read_overflow_sticky()
    fir.clear_overflow_sticky()
    assert not fir.read_overflow_sticky()

    print(
        "[canary_fir_regs] Self-test PASS | "
        f"VERSION=0x{VERSION_EXPECTED:08X} ('{VERSION_ASCII}') | "
        f"Base=0x{DEFAULT_BASE_ADDR:08X} | Taps={NUM_SYM_TAPS} symmetric"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(_run_self_test())
