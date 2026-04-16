# Alarm Clock — SystemVerilog (Professional RTL Redesign)

This branch (`feature/professional-rtl-redesign`) is a complete professional-grade
redesign of the original BCD alarm clock, addressing every critical RTL issue
found during code review.

---

## What Changed & Why

| Issue in original `verilog code.v` | Fix applied |
|---|---|
| `LD_time` + `LD_alarm` race — both flags could be 1 simultaneously → undefined | **FSM** with 5 mutually exclusive states eliminates the race |
| `clk_1s` was a `reg` driven inside `always` — derived clock triggers FPGA timing violations | Replaced with **clock-enable** `tick_1s` (combinational wire) — single clock domain throughout |
| Alarm assert every clk_1s edge for full 60-second minute (level-sensitive) | **Edge-triggered**: `match && !prev_match` fires alarm exactly once at HH:MM:00 |
| No BCD input validation — `H_in1=2, H_in0=9` → `tmp_hour=29` (invalid) | Validated on load: clamped to `MAX_HOUR`/`MAX_MIN` |
| `STOP_al` was level, must be held HIGH — no auto-clear | FSM state `ALARM_RING` exits cleanly on `btn_stop` pulse |
| No button debouncing — switch bounce causes multiple loads on FPGA | `debounce.sv` — 2-stage synchroniser + stability counter |
| Testbench had `wait(Alarm)` with no timeout — hangs forever on bugs | 9 test cases with per-test timeout + watchdog timer |
| Magic numbers (24, 59, 10) scattered through code | Fully `parameter`-ised: `MAX_HOUR`, `MAX_MIN`, `MAX_SEC`, `CLK_DIV` |

### New Features Added
- **Snooze** (`btn_snooze`): advances alarm time by +5 minutes with hour rollover
- **SystemVerilog Assertions**: `p_hour_range`, `p_min_range`, `p_sec_range` fail
  immediately on invariant violation during simulation
- **Top-level FPGA wrapper** (`alarm_clock_top.sv`): plugs debounce modules
  and scales `CLK_DIV` to the board clock frequency

---

## File Structure

```
alarm_clock_verilog/
├── alarm_clock_sv.sv    # Core design (FSM + time counter + alarm)
├── debounce.sv          # Button debouncer (required for FPGA targets)
├── alarm_clock_top.sv   # FPGA top-level wrapper (50 MHz board)
├── alarm_clock_tb.sv    # Comprehensive testbench (9 TCs, VCD output)
├── Makefile             # Icarus Verilog simulation + GTKWave
├── verilog code.v       # Original design (preserved)
└── Testbench            # Original testbench (preserved)
```

---

## FSM State Diagram

```
             btn_load_time
NORMAL ──────────────────────────► LOAD_TIME
  │  ◄──────────────── !btn_load_time ─────────┘
  │
  │  btn_load_alarm
  ├──────────────────────────────► LOAD_ALARM
  │  ◄─────────────── !btn_load_alarm ─────────┘
  │
  │  alarm_trigger (match && !prev_match && alarm_en)
  └──────────────────────────────► ALARM_RING
                                        │
                              btn_stop  │  btn_snooze
                                ┌───────┴──────────┐
                                ▼                  ▼
                              NORMAL           SNOOZE_SET ──► NORMAL
```

---

## Running Simulation

**Prerequisites:** [Icarus Verilog](https://bleyer.org/icarus/) · optional: [GTKWave](http://gtkwave.sourceforge.net/)

```bash
# Compile and run all 9 test cases
make sim

# View waveforms (GTKWave)
make wave

# Clean build artefacts
make clean
```

Expected output:
```
=== TC1: Reset Behaviour ===
  [PASS] Hour  = 0 after reset
  [PASS] Min   = 0 after reset
  ...
========================================
 TEST RESULTS: 9 passed, 0 failed
========================================
 ALL TESTS PASSED
```

---

## Architecture

```
alarm_clock_sv.sv
│
├── Clock Enable Generator   — tick_1s CE pulse every 1 s (no derived clocks)
├── Time Counter             — 5-bit hour, 6-bit min, 5-bit sec (binary)
├── Alarm Register           — stores alarm time, updates on LOAD_ALARM / SNOOZE
├── Alarm Match (combinational) + Edge Detector (FF prev_match)
├── FSM                      — NORMAL/LOAD_TIME/LOAD_ALARM/ALARM_RING/SNOOZE_SET
├── Alarm Output FF          — alarm_out HIGH only in ALARM_RING state
└── BCD Conversion           — binary → 2-digit BCD at outputs only
```

---

## Interface (alarm_clock_sv)

| Port | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Master clock (CLK_DIV Hz for 1 s ticks) |
| `reset_n` | in | 1 | Active-low synchronous reset |
| `btn_load_time` | in | 1 | Hold HIGH to load time from H/M inputs |
| `btn_load_alarm` | in | 1 | Hold HIGH to load alarm from H/M inputs |
| `btn_alarm_en` | in | 1 | Level — enables alarm comparison |
| `btn_stop` | in | 1 | Pulse — stops ringing alarm |
| `btn_snooze` | in | 1 | Pulse — snooze alarm +5 min |
| `H_in1[1:0]` | in | 2 | Hours tens digit (0–2) |
| `H_in0[3:0]` | in | 4 | Hours units digit (0–9) |
| `M_in1[3:0]` | in | 4 | Minutes tens digit (0–5) |
| `M_in0[3:0]` | in | 4 | Minutes units digit (0–9) |
| `H_out1/H_out0` | out | 2/4 | Current hour BCD digits |
| `M_out1/M_out0` | out | 4/4 | Current minute BCD digits |
| `S_out1/S_out0` | out | 4/4 | Current second BCD digits |
| `alarm_out` | out | 1 | HIGH while alarm is ringing |

---

## Original Design (preserved)

The original files are kept untouched for reference:
- [`verilog code.v`](verilog%20code.v) — original Verilog
- [`Testbench`](Testbench) — original testbench
