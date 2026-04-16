<div align="center">

<h1>⏰ ChronoCore</h1>

<p><strong>Professional BCD Alarm Clock · SystemVerilog RTL · FPGA-Ready</strong></p>

[![Language](https://img.shields.io/badge/Language-SystemVerilog-blue?style=flat-square&logo=verilog)](https://en.wikipedia.org/wiki/SystemVerilog)
[![Standard](https://img.shields.io/badge/Standard-IEEE%201800--2012-orange?style=flat-square)](https://ieeexplore.ieee.org/document/6469140)
[![Simulator](https://img.shields.io/badge/Simulator-Icarus%20Verilog-green?style=flat-square)](https://bleyer.org/icarus/)
[![Lint](https://img.shields.io/badge/Lint-Verilator-red?style=flat-square)](https://www.veripool.org/verilator)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

<br/>

> A fully modular, synthesisable BCD alarm clock redesigned from the ground up  
> using professional RTL practices — FSM-controlled, single-clock-domain,  
> edge-triggered, and extensively verified with SVA assertions and coverage.

<br/>

</div>

---

## ✨ Highlights

| | Feature | Detail |
|---|---|---|
| 🔒 | **No Race Conditions** | 5-state Moore FSM — only one mode active per clock edge |
| ⚡ | **FPGA-Safe Clocking** | Clock-enable `tick_1s` instead of a derived `reg`-based clock |
| 🎯 | **Single-Shot Alarm** | Edge-triggered (`match && !prev_match`) — fires exactly once at HH:MM:00 |
| 🔔 | **Dual Alarm Slots** | Two independent alarm channels, selectable at runtime |
| 💤 | **Snooze** | Advances active alarm +5 minutes with hour/midnight rollover |
| 🔇 | **Auto-Silence** | Alarm auto-stops after configurable timeout (default 60 s) |
| 🎵 | **Buzzer Pattern** | Beep-beep-pause pattern — not a constant HIGH signal |
| 🕐 | **AM/PM Mode** | 12 h / 24 h display switchable at runtime; dedicated PM flag output |
| ✅ | **Input Validation** | Invalid BCD (e.g. hour = 29) clamped on load — no illegal states |
| 🧪 | **15 Test Cases** | Full testbench with SVA assertions, coverage groups, and watchdog |

---

## 🏗️ Architecture

```
alarm_clock_top.sv  ◄─── FPGA Wrapper (50 MHz, debounced buttons)
│
└── alarm_clock_core.sv  ◄─── RTL Sub-top (DUT)
    │
    ├── clk_enable_gen.sv    1-second clock-enable pulse (no derived clock)
    ├── time_counter.sv      HH:MM:SS binary counter with validated BCD load
    ├── alarm_slot.sv (×2)   Alarm register + edge-triggered comparator
    ├── buzzer_ctrl.sv       Beep pattern generator + auto-silence timer
    ├── control_fsm.sv       5-state Moore FSM with registered outputs
    └── debounce.sv          Two-stage synchroniser + stability counter
```

### FSM State Diagram

```
                   btn_load_time
       ┌──── NORMAL ──────────────────► LOAD_TIME
       │       │  ▲                          │
       │       │  └──────── release ─────────┘
       │       │
       │       │ btn_load_alarm
       │       ├────────────────────────► LOAD_ALARM
       │       │  ▲                          │
       │       │  └──────── release ─────────┘
       │       │
       │       │ trigger_0 || trigger_1
       │       └───────────────────────► ALARM_RING
       │                                    │    │
       │              btn_stop / timeout ◄──┘    │ btn_snooze
       │                                         ▼
       └──────────────────────────────── SNOOZE_SET (1 cycle)
```

---

## 📁 Repository Layout

```
ChronoCore/
├── rtl/
│   ├── clk_enable_gen.sv       # tick_1s CE — no derived clock registers
│   ├── time_counter.sv         # HH:MM:SS binary counter with BCD load
│   ├── alarm_slot.sv           # Alarm register, edge detector, snooze
│   ├── buzzer_ctrl.sv          # Beep-beep pattern + auto-silence
│   ├── control_fsm.sv          # Moore FSM (5 states, registered outputs)
│   ├── alarm_clock_core.sv     # RTL integration: AM/PM, dual alarms, BCD out
│   ├── debounce.sv             # Sync + stability-counter debouncer
│   └── alarm_clock_top.sv      # FPGA top-level (50 MHz board)
│
├── tb/
│   └── alarm_clock_tb.sv       # 15 TCs · 6 SVA props · 5 cover groups
│
├── sim/                        # Build outputs (generated)
├── Makefile
└── README.md
```

---

## 🔌 Interface — `alarm_clock_core`

<details>
<summary><strong>Inputs</strong> (click to expand)</summary>

| Signal | Width | Description |
|---|---|---|
| `clk` | 1 | Master clock (`CLK_DIV` Hz for 1 s tick) |
| `reset_n` | 1 | Active-low synchronous reset |
| `btn_load_time` | 1 | Hold HIGH → enter `LOAD_TIME` state |
| `btn_load_alarm` | 1 | Hold HIGH → enter `LOAD_ALARM` state |
| `sel_alarm` | 1 | `0` = configure slot 0 · `1` = configure slot 1 |
| `btn_alarm_en_0` | 1 | Level — arm alarm slot 0 |
| `btn_alarm_en_1` | 1 | Level — arm alarm slot 1 |
| `btn_stop` | 1 | Pulse — stop ringing alarm |
| `btn_snooze` | 1 | Pulse — snooze active alarm (+`SNOOZE_MIN` min) |
| `mode_12h` | 1 | `0` = 24 h display · `1` = 12 h display |
| `H_in1[1:0]` | 2 | Hours tens digit (BCD 0–2) |
| `H_in0[3:0]` | 4 | Hours units digit (BCD 0–9) |
| `M_in1[3:0]` | 4 | Minutes tens digit (BCD 0–5) |
| `M_in0[3:0]` | 4 | Minutes units digit (BCD 0–9) |

</details>

<details>
<summary><strong>Outputs</strong> (click to expand)</summary>

| Signal | Width | Description |
|---|---|---|
| `H_out1[1:0]` | 2 | Display hours tens digit |
| `H_out0[3:0]` | 4 | Display hours units digit |
| `M_out1[3:0]` | 4 | Display minutes tens digit |
| `M_out0[3:0]` | 4 | Display minutes units digit |
| `S_out1[3:0]` | 4 | Display seconds tens digit |
| `S_out0[3:0]` | 4 | Display seconds units digit |
| `pm_flag` | 1 | HIGH = PM (valid only in 12 h mode) |
| `buzzer_out` | 1 | Patterned buzzer signal |
| `alarm_armed[1:0]` | 2 | Armed status per slot |

</details>

---

## 🚀 Quick Start

### Prerequisites

- [Icarus Verilog](https://bleyer.org/icarus/) — simulation
- [GTKWave](https://gtkwave.sourceforge.net/) — waveform viewer *(optional)*
- [Verilator](https://www.veripool.org/verilator) — static analysis *(optional)*

### Run Simulation

```bash
# Clone
git clone https://github.com/Sk4saurav/ChronoCore.git
cd ChronoCore

# Compile + run all 15 test cases
make sim

# View waveforms
make wave

# Static lint (Verilator)
make lint
```

### Expected Output

```
=== TC01: Reset Behaviour ===
  [PASS] H = 00 after reset
  [PASS] M = 00 after reset
  [PASS] S = 00 after reset
  [PASS] buzzer_out = 0 after reset
...
=== TC15: Buzzer Pattern ===
  [PASS] Buzzer OFF during silence phase (cnt >= BEEP_ON)
  [PASS] Buzzer ON again after full cycle

========================================
 Coverage summary:
   FSM States:       100.0%
   FSM Transitions:  100.0%
   Alarm Slots:      100.0%
   Hour Corners:     100.0%
   BCD Validation:   100.0%
========================================
 TESTS: 15 passed, 0 failed
========================================
 ALL TESTS PASSED
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|---|---|---|
| `CLK_DIV` | `10` | Master clock frequency in Hz (cycles per second) |
| `MAX_HOUR` | `23` | Maximum hour value |
| `MAX_MIN` | `59` | Maximum minute value |
| `MAX_SEC` | `59` | Maximum second value |
| `SNOOZE_MIN` | `5` | Minutes added per snooze press |
| `BEEP_PATTERN_LEN` | `5` | Buzzer cycle length in ticks |
| `BEEP_ON_TICKS` | `2` | ON ticks per buzzer cycle |
| `ALARM_TIMEOUT` | `60` | Seconds before auto-silence |

---

## 🧪 Verification

### SVA Assertions

| Property | Checks |
|---|---|
| `p_hour_range` | `cur_hour` ∈ [0, 23] at all times |
| `p_min_range` | `cur_min` ∈ [0, 59] at all times |
| `p_sec_range` | `cur_sec` ∈ [0, 59] at all times |
| `p_no_double_load` | `load_time` and `load_alarm` never simultaneously HIGH |
| `p_buzzer_gated` | `buzzer_out` can only be HIGH when `alarm_ring` is active |
| `p_buzzer_reset` | `buzzer_out` cleared within 1 cycle of reset |

### Functional Coverage

| Group | Bins |
|---|---|
| `cg_fsm_states` | All 5 FSM states visited |
| `cg_fsm_transitions` | NORMAL→RING, RING→STOP, RING→SNOOZE, SNOOZE→NORMAL |
| `cg_alarm_slots` | Both slot 0 and slot 1 triggered independently |
| `cg_hour_corners` | Midnight (0), Noon (12), Max (23) |
| `cg_bcd_validation` | Valid BCD, invalid BCD exercised |

---

## 🔧 RTL Best Practices Applied

- **Single clock domain** — `tick_1s` CE replaces the original `reg clk_1s` derived clock
- **Synchronous reset** — active-low, registered throughout; no mixed async/sync
- **Moore FSM** — registered outputs eliminate combinational glitches on control signals
- **Non-blocking only in `always_ff`** — no delta-cycle race conditions
- **`default_nettype none`** — catches undeclared wires at compile time
- **`unique case`** — prevents inferred priority encoder inside FSM
- **Zero magic numbers** — every constant is a named `parameter`

---

## 📖 Background

This project is a professional redesign of a student BCD alarm clock, addressing
six critical RTL flaws identified during code review:

| Original Issue | Fix |
|---|---|
| `LD_time` + `LD_alarm` race (both could fire simultaneously) | **FSM** — mutually exclusive states |
| Derived `reg clk_1s` — FPGA timing violation | **Clock-enable** `tick_1s` — single clock domain |
| Level-triggered alarm — fires for full 60 s | **Edge detection** — single-shot at HH:MM:00 |
| No BCD input validation — hour = 29 accepted | **Clamp** in `validated_hour()` / `validated_min()` |
| `STOP_al` required level-hold | **FSM exit** on pulse |
| No button debouncing | **`debounce.sv`** — 2-stage sync + stability counter |

---

<div align="center">

Made with precision · SystemVerilog IEEE 1800-2012

</div>
