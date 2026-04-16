# =============================================================================
# Makefile — BCD Alarm Clock Professional RTL
# =============================================================================
# Targets:
#   sim       Compile + run all 15 testbench cases (Icarus Verilog)
#   wave      Open GTKWave after simulation
#   lint      Run Verilator lint (static analysis, no simulation)
#   clean     Remove build artefacts
#
# Prerequisites:
#   iverilog  https://bleyer.org/icarus/
#   vvp       (bundled with Icarus Verilog)
#   gtkwave   https://gtkwave.sourceforge.net/  (optional, for waveforms)
#   verilator https://www.veripool.org/verilator  (optional, for lint)
#
# Usage:
#   make sim        # compile and run all tests
#   make wave       # view waveforms in GTKWave
#   make lint       # static analysis
#   make clean      # remove build artefacts
# =============================================================================

# ---- Tools ------------------------------------------------------------------
IVERILOG  := iverilog
VVP       := vvp
GTKWAVE   := gtkwave
VERILATOR := verilator

# ---- Source files -----------------------------------------------------------
RTL_FILES := rtl/clk_enable_gen.sv   \
             rtl/time_counter.sv      \
             rtl/alarm_slot.sv        \
             rtl/buzzer_ctrl.sv       \
             rtl/control_fsm.sv      \
             rtl/alarm_clock_core.sv \
             rtl/debounce.sv         \
             rtl/alarm_clock_top.sv

TB_FILES  := tb/alarm_clock_tb.sv

# ---- Output files -----------------------------------------------------------
SIM_BIN   := sim/alarm_sim
VCD_FILE  := sim/alarm_clock.vcd

# ---- Targets ----------------------------------------------------------------
.PHONY: all sim wave lint clean

all: sim

# Create sim output directory
$(SIM_BIN): $(RTL_FILES) $(TB_FILES) | sim/
	$(IVERILOG) -g2012 -D SIMULATION \
	    -o $@ \
	    $(RTL_FILES) $(TB_FILES)

sim/: ; mkdir -p sim

sim: $(SIM_BIN)
	$(VVP) $(SIM_BIN)

wave: $(VCD_FILE)
	$(GTKWAVE) $(VCD_FILE) &

$(VCD_FILE): sim

lint:
	$(VERILATOR) --lint-only -sv --Wall \
	    $(RTL_FILES)

clean:
	rm -rf sim/
