#include "imc_serial.h"
#include "xil_io.h"

enum {
    REG_CONTROL = 0x00u, REG_STATUS = 0x04u, REG_COMMAND = 0x08u,
    REG_ERROR = 0x0Cu, REG_ROW_MASK = 0x10u, REG_SWITCH_CTRL = 0x1Cu,
    REG_DAC_A_CODE = 0x20u, REG_DAC_B_CODE = 0x24u,
    REG_PULSE_CYCLES = 0x28u, REG_ADC_CHANNEL = 0x30u,
    REG_DAC_CHANNEL = 0x34u, REG_RESET_PULSE_CYCLES = 0x38u,
    REG_ADC_RESULT = 0x60u, REG_DESIGN_ID = 0xFCu
};
enum {
    CMD_SAFE_INIT = 0x01u, CMD_SHIFT_ROWS = 0x02u,
    CMD_DAC_WRITE = 0x03u, CMD_ADC_READ = 0x04u,
    CMD_SET_SWITCHES = 0x05u, CMD_INTEGRATOR_RESET = 0x06u,
    CMD_DELAY = 0x07u, CMD_ADC_PROBE = 0x08u, CMD_SAFE_STATE = 0x7Fu
};
enum {
    CTRL_START = 1u, CTRL_CLEAR_DONE = 2u,
    CTRL_SOFT_RESET = 4u, CTRL_ABORT = 8u
};

static uint32_t rd(const imc_device_t *dev, uint32_t offset)
{
    return Xil_In32((UINTPTR)(dev->base + offset));
}

static void wr(const imc_device_t *dev, uint32_t offset, uint32_t value)
{
    Xil_Out32((UINTPTR)(dev->base + offset), value);
}

void imc_device_init(imc_device_t *dev, uintptr_t axi_base, uint32_t poll_limit)
{
    if (dev != 0) {
        dev->base = axi_base;
        dev->poll_limit = poll_limit;
        dev->switch_shadow = 0;
    }
}

uint32_t imc_design_id(const imc_device_t *dev) { return rd(dev, REG_DESIGN_ID); }
uint32_t imc_status(const imc_device_t *dev) { return rd(dev, REG_STATUS); }
uint8_t imc_error_code(const imc_device_t *dev) { return (uint8_t)rd(dev, REG_ERROR); }

int imc_wait_initialized(const imc_device_t *dev)
{
    uint32_t i;
    if (dev == 0 || dev->poll_limit == 0) return IMC_BAD_ARG;
    for (i = 0; i < dev->poll_limit; ++i) {
        uint32_t status = rd(dev, REG_STATUS);
        if ((status & (IMC_STATUS_BUSY | IMC_STATUS_INITIALIZED)) ==
            IMC_STATUS_INITIALIZED) return IMC_OK;
    }
    return IMC_TIMEOUT;
}

void imc_clear_done(const imc_device_t *dev)
{
    wr(dev, REG_CONTROL, CTRL_CLEAR_DONE);
}

static int run_command(imc_device_t *dev, uint32_t command)
{
    uint32_t i, status;
    if (dev == 0 || dev->poll_limit == 0) return IMC_BAD_ARG;
    status = rd(dev, REG_STATUS);
    if (status & IMC_STATUS_BUSY) return IMC_BUSY;
    if (!(status & IMC_STATUS_INITIALIZED)) return IMC_DEVICE_ERROR;
    imc_clear_done(dev);
    wr(dev, REG_COMMAND, command);
    wr(dev, REG_CONTROL, CTRL_START);
    for (i = 0; i < dev->poll_limit; ++i) {
        status = rd(dev, REG_STATUS);
        if (status & IMC_STATUS_ERROR) return IMC_DEVICE_ERROR;
        if ((status & (IMC_STATUS_DONE | IMC_STATUS_BUSY)) == IMC_STATUS_DONE)
            return IMC_OK;
    }
    return IMC_TIMEOUT;
}

static int restart(imc_device_t *dev, uint32_t control)
{
    if (dev == 0 || dev->poll_limit == 0) return IMC_BAD_ARG;
    wr(dev, REG_CONTROL, control);
    dev->switch_shadow = 0;
    return imc_wait_initialized(dev);
}

int imc_abort(imc_device_t *dev) { return restart(dev, CTRL_ABORT); }
int imc_soft_reset(imc_device_t *dev) { return restart(dev, CTRL_SOFT_RESET); }
int imc_safe_init(imc_device_t *dev)
{
    int rc = run_command(dev, CMD_SAFE_INIT);
    if (rc == IMC_OK) dev->switch_shadow = 0;
    return rc;
}
int imc_safe_state(imc_device_t *dev)
{
    int rc = run_command(dev, CMD_SAFE_STATE);
    if (rc == IMC_OK) dev->switch_shadow = 0;
    return rc;
}

int imc_shift_rows(imc_device_t *dev, uint16_t mask)
{
    if (dev == 0) return IMC_BAD_ARG;
    wr(dev, REG_ROW_MASK, mask);
    return run_command(dev, CMD_SHIFT_ROWS);
}

static int dac_write(imc_device_t *dev, uint32_t channel, uint16_t code)
{
    if (dev == 0) return IMC_BAD_ARG;
    wr(dev, REG_DAC_CHANNEL, channel);
    wr(dev, channel ? REG_DAC_B_CODE : REG_DAC_A_CODE, code);
    return run_command(dev, CMD_DAC_WRITE);
}
int imc_dac_write_a(imc_device_t *dev, uint16_t code) { return dac_write(dev, 0, code); }
int imc_dac_write_b(imc_device_t *dev, uint16_t code) { return dac_write(dev, 1, code); }

static int apply_switches(imc_device_t *dev, uint32_t requested)
{
    int rc;
    wr(dev, REG_SWITCH_CTRL, requested);
    rc = run_command(dev, CMD_SET_SWITCHES);
    if (rc == IMC_OK) dev->switch_shadow = requested;
    return rc;
}

int imc_set_routing(imc_device_t *dev, uint8_t ispp, uint8_t vp,
                    uint8_t cc_mask)
{
    if (dev == 0 || ispp > 1 || vp > 1 || cc_mask > 7) return IMC_BAD_ARG;
    return apply_switches(dev, (uint32_t)ispp | ((uint32_t)vp << 1) |
                         ((uint32_t)cc_mask << 2));
}

int imc_set_ispp(imc_device_t *dev, uint8_t level)
{
    if (dev == 0 || level > 1) return IMC_BAD_ARG;
    return apply_switches(dev, (dev->switch_shadow & ~1u) | level);
}

int imc_set_vp(imc_device_t *dev, uint8_t level)
{
    if (dev == 0 || level > 1) return IMC_BAD_ARG;
    return apply_switches(dev, (dev->switch_shadow & ~2u) | ((uint32_t)level << 1));
}

int imc_set_columns(imc_device_t *dev, uint8_t cc_mask)
{
    if (dev == 0 || cc_mask > 7) return IMC_BAD_ARG;
    return apply_switches(dev, (dev->switch_shadow & ~0x1Cu) |
                         ((uint32_t)cc_mask << 2));
}

int imc_reset_integrators(imc_device_t *dev, uint32_t cycles)
{
    if (dev == 0) return IMC_BAD_ARG;
    wr(dev, REG_RESET_PULSE_CYCLES, cycles);
    return run_command(dev, CMD_INTEGRATOR_RESET);
}

int imc_delay_cycles(imc_device_t *dev, uint32_t cycles)
{
    if (dev == 0) return IMC_BAD_ARG;
    wr(dev, REG_PULSE_CYCLES, cycles);
    return run_command(dev, CMD_DELAY);
}

int imc_adc_read(imc_device_t *dev, uint8_t channel, int16_t *raw)
{
    int rc;
    if (dev == 0 || raw == 0 || channel < 1 || channel > 4) return IMC_BAD_ARG;
    wr(dev, REG_ADC_CHANNEL, channel);
    rc = run_command(dev, CMD_ADC_READ);
    if (rc != IMC_OK) return rc;
    if (!(rd(dev, REG_STATUS) & IMC_STATUS_ADC_VALID)) return IMC_DEVICE_ERROR;
    *raw = (int16_t)(uint16_t)rd(dev, REG_ADC_RESULT);
    return IMC_OK;
}

int imc_adc_probe(imc_device_t *dev, uint16_t *config)
{
    int rc;
    if (dev == 0 || config == 0) return IMC_BAD_ARG;
    rc = run_command(dev, CMD_ADC_PROBE);
    if (rc != IMC_OK) return rc;
    if (!(rd(dev, REG_STATUS) & IMC_STATUS_ADC_VALID)) return IMC_DEVICE_ERROR;
    *config = (uint16_t)rd(dev, REG_ADC_RESULT);
    return IMC_OK;
}
