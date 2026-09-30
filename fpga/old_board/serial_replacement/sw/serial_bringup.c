/* Standalone Zynq PS smoke test. Build this with imc_serial.c after the
 * platform address macro has been generated. Check digital nets with analog
 * power disabled before enabling the experimental analog chain. */
#include "imc_serial.h"
#include "imc_platform.h"
#include "xil_printf.h"

int main(void)
{
    imc_device_t imc;
    static const uint16_t masks[] = {0xFFFFu, 0xFFFEu, 0xFFFDu, 0xF7FFu};
    unsigned int i;

    imc_device_init(&imc, (uintptr_t)IMC_AXI_BASEADDR, 1000000u);
    if (imc_design_id(&imc) != 0x00010001u ||
        imc_wait_initialized(&imc) != IMC_OK) {
        xil_printf("IMC AXI initialization failed\r\n");
        return 1;
    }
    for (i = 0; i < sizeof(masks) / sizeof(masks[0]); ++i) {
        if (imc_shift_rows(&imc, masks[i]) != IMC_OK) {
            xil_printf("row shift failed: %04x error=%02x\r\n",
                       (unsigned int)masks[i], (unsigned int)imc_error_code(&imc));
            return 1;
        }
    }
    if (imc_dac_write_a(&imc, 0) != IMC_OK ||
        imc_dac_write_b(&imc, 0) != IMC_OK ||
        imc_set_routing(&imc, 0, 0, 0) != IMC_OK ||
        imc_reset_integrators(&imc, 0) != IMC_OK) {
        xil_printf("digital peripheral smoke test failed: error=%02x\r\n",
                   (unsigned int)imc_error_code(&imc));
        return 1;
    }
    xil_printf("IMC digital smoke test passed\r\n");
    /* ADC reads require the fitted ADS1115 and analog input wiring. */
    return 0;
}
