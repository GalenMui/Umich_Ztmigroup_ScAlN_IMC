#!/usr/bin/env python3
"""Check the supplied V1.2 J5 map and uniqueness of selected package pins."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
constraints = root / "constraints"
mapping = """H19 H20 E18 F18 F17 G17 C17 C18 G19 F19 E20 E19 D22 C22 B22 B21
B17 B16 A17 A16 D20 C20 B15 C15 D17 D16 D15 E15 D18 C19 E16 F16 G15 G16""".split()
signals = """sr_data sr_clk sr_latch sr_oe_n dac_mosi dac_sclk dac_cs_n
dac_reset_n adc_scl adc_sda ispp vp cc1 cc2 cc3 integrator_reset1
integrator_reset2 integrator_reset3 board_control timing_pulse""".split()
pattern = re.compile(
    r"set_property -dict \{PACKAGE_PIN (\w+) IOSTANDARD LVCMOS33\} "
    r"\[get_ports (\w+)\]"
)
assigned = {}
headers = {}
for xdc in constraints.glob("*v12*.xdc"):
    contents = xdc.read_text()
    for pin, port in pattern.findall(contents):
        assert port not in assigned, f"duplicate port assignment: {port}"
        assigned[port] = pin
    if xdc.name == "smart_zynq_sl_v12_j5.xdc":
        for index, header in re.findall(r"J5\[(\d+)\], header (\d+)", contents):
            headers[int(index)] = int(header)
for index, port in enumerate(signals):
    assert assigned.get(port) == mapping[index], (
        f"J5[{index}] {port}: expected {mapping[index]}, got {assigned.get(port)}"
    )
    assert headers.get(index) == index + 7, (
        f"J5[{index}] must be physical header pin {index + 7}"
    )
assert len(set(assigned.values())) == len(assigned), "duplicate package pin"
assert assigned.get("UART_1_0_txd") == "L17"
assert assigned.get("UART_1_0_rxd") == "M17"
base = (constraints / "smart_zynq_sl_v12_base.xdc").read_text()
assert "create_clock -name clk_50 -period 20.000" in base
assert "PACKAGE_PIN M19 IOSTANDARD LVCMOS33" in base
print("PASS: V1.2 J5 assignments, unique pins, UART, 50 MHz clock")
