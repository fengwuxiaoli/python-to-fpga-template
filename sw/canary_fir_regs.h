/* ============================================================================
 * AXI4-Lite Register Map & Helpers for Canary 15-Tap Symmetric FIR
 * Matches `rtl/canary_fir_regs.sv` and `SPEC.md` (`VERSION = 0x46495231`).
 * ============================================================================ */
#ifndef CANARY_FIR_REGS_H
#define CANARY_FIR_REGS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Address Map Geometry (8-bit byte offset, 256-byte window) */
#define CANARY_FIR_DEFAULT_BASE_ADDR   0xA0000000U
#define CANARY_FIR_ADDR_WINDOW_BYTES   0x100U

#define CANARY_FIR_REG_VERSION         0x00U
#define CANARY_FIR_REG_CTRL            0x04U
#define CANARY_FIR_REG_STATUS          0x08U
#define CANARY_FIR_REG_COEFF_BASE      0x10U
#define CANARY_FIR_REG_COEFF_STRIDE    0x04U
#define CANARY_FIR_REG_COEFF(idx)      (CANARY_FIR_REG_COEFF_BASE + ((uint32_t)(idx) << 2U))

#define CANARY_FIR_REG_COEFF0          0x10U
#define CANARY_FIR_REG_COEFF1          0x14U
#define CANARY_FIR_REG_COEFF2          0x18U
#define CANARY_FIR_REG_COEFF3          0x1CU
#define CANARY_FIR_REG_COEFF4          0x20U
#define CANARY_FIR_REG_COEFF5          0x24U
#define CANARY_FIR_REG_COEFF6          0x28U
#define CANARY_FIR_REG_COEFF7          0x2CU

/* Hardware Identity & Datapath Geometry */
#define CANARY_FIR_VERSION_EXPECTED    0x46495231U /* "FIR1" */
#define CANARY_FIR_NUM_TAPS            15U
#define CANARY_FIR_NUM_SYM_TAPS        8U
#define CANARY_FIR_FLUSH_ZEROS         14U
#define CANARY_FIR_PIPELINE_LATENCY    5U

/* Register Bit Fields */
#define CANARY_FIR_CTRL_BYPASS_EN_BIT    0U
#define CANARY_FIR_CTRL_BYPASS_EN_MASK   0x00000001U

#define CANARY_FIR_STATUS_OVF_STICKY_BIT  0U
#define CANARY_FIR_STATUS_OVF_STICKY_MASK 0x00000001U

#define CANARY_FIR_COEFF_DATA_MASK       0x0000FFFFU

/* Default Reset Q1.15 Symmetric Taps (2 * sum(h[0..6]) + h[7] = 32767) */
#define CANARY_FIR_DEFAULT_COEFFS_INIT { -214, -327, 0, 992, 2525, 4351, 5839, 6435 }

/* Pack signed 16-bit Q1.15 coefficient to sign-extended 32-bit AXI4-Lite word */
static inline uint32_t canary_fir_pack_coeff(int16_t coeff) {
    return (uint32_t)(int32_t)coeff;
}

/* Unpack signed 16-bit Q1.15 coefficient from 32-bit AXI4-Lite readback word */
static inline int16_t canary_fir_unpack_coeff(uint32_t reg_val) {
    uint32_t low16 = reg_val & CANARY_FIR_COEFF_DATA_MASK;
    if ((low16 & 0x8000U) != 0U) {
        return (int16_t)((int32_t)low16 - 65536);
    }
    return (int16_t)low16;
}

/* Full 32-bit aligned MMIO read/write (guarantees wstrb == 4'hF on COEFF writes) */
static inline uint32_t canary_fir_mmio_read32(uintptr_t base_addr, uint32_t offset) {
    volatile const uint32_t *ptr = (volatile const uint32_t *)(base_addr + (uintptr_t)offset);
    return *ptr;
}

static inline void canary_fir_mmio_write32(uintptr_t base_addr, uint32_t offset, uint32_t value) {
    volatile uint32_t *ptr = (volatile uint32_t *)(base_addr + (uintptr_t)offset);
    *ptr = value;
}

#ifdef __cplusplus
}
#endif

#endif /* CANARY_FIR_REGS_H */
