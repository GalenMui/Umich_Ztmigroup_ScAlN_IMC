#ifndef IMC_SERIAL_H
#define IMC_SERIAL_H

#include <stdint.h>

/* Pass the AXI base from the generated platform address map at runtime.
 * poll_limit counts MMIO reads, not microseconds; zero is invalid. */
typedef struct {
    uintptr_t base;
    uint32_t poll_limit;
    uint32_t switch_shadow;
} imc_device_t;

enum {
    IMC_OK = 0,
    IMC_BAD_ARG = -1,
    IMC_TIMEOUT = -2,
    IMC_DEVICE_ERROR = -3,
    IMC_BUSY = -4
};

enum {
    IMC_STATUS_BUSY = 1u << 0,
    IMC_STATUS_DONE = 1u << 1,
    IMC_STATUS_ERROR = 1u << 2,
    IMC_STATUS_ADC_VALID = 1u << 3,
    IMC_STATUS_INITIALIZED = 1u << 4
};

void imc_device_init(imc_device_t *dev, uintptr_t axi_base, uint32_t poll_limit);
uint32_t imc_design_id(const imc_device_t *dev);
uint32_t imc_status(const imc_device_t *dev);
uint8_t imc_error_code(const imc_device_t *dev);
int imc_wait_initialized(const imc_device_t *dev);
void imc_clear_done(const imc_device_t *dev);
int imc_abort(imc_device_t *dev);
int imc_soft_reset(imc_device_t *dev);
int imc_safe_init(imc_device_t *dev);
int imc_safe_state(imc_device_t *dev);
int imc_shift_rows(imc_device_t *dev, uint16_t mask);
int imc_dac_write_a(imc_device_t *dev, uint16_t code);
int imc_dac_write_b(imc_device_t *dev, uint16_t code);
int imc_set_routing(imc_device_t *dev, uint8_t ispp, uint8_t vp,
                    uint8_t cc_mask);
int imc_set_ispp(imc_device_t *dev, uint8_t level);
int imc_set_vp(imc_device_t *dev, uint8_t level);
int imc_set_columns(imc_device_t *dev, uint8_t cc_mask);
/* cycles=0 selects the firmware-compatible 1 ms pulse. */
int imc_reset_integrators(imc_device_t *dev, uint32_t cycles);
int imc_delay_cycles(imc_device_t *dev, uint32_t cycles);
/* Channel 1..4 maps to ADS1115 AIN0..AIN3. Result is signed raw counts. */
int imc_adc_read(imc_device_t *dev, uint8_t channel, int16_t *raw);
/* Reads ADS1115 config register, matching the Teensy startup presence probe. */
int imc_adc_probe(imc_device_t *dev, uint16_t *config);

#endif
