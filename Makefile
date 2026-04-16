# Alarm Clock — SystemVerilog Referencing Makefile
# =============================================================================
# Targets:
#   sim      — compile and simulate (requires Icarus Verilog: iverilog / vvp)
#   wave     — open GTKWave after simulation
#   clean    — remove generated files
#
# Usage:
#   make sim       # run all testbench simulations
#   make wave      # view waveforms (GTKWave must be installed)
#   make clean     # remove build artifacts
# =============================================================================

SV_FILES = alarm_clock_sv.sv debounce.sv alarm_clock_tb.sv

SIM_BIN  = alarm_sim
VCD_FILE = alarm_clock.vcd

# Icarus Verilog — SystemVerilog mode
IVERILOG = iverilog -g2012 -D SIMULATION
VVP      = vvp

.PHONY: sim wave clean

sim: $(SIM_BIN)
	$(VVP) $(SIM_BIN)

$(SIM_BIN): $(SV_FILES)
	$(IVERILOG) -o $@ $^

wave: $(VCD_FILE)
	gtkwave $(VCD_FILE) &

$(VCD_FILE): sim

clean:
	rm -f $(SIM_BIN) $(VCD_FILE)
