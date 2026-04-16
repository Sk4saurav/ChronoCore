// =============================================================================
// Module  : alarm_clock_core
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/alarm_clock_core.sv
// =============================================================================
// Description:
//   Sub-top integration module.  Wires together all sub-modules:
//     clk_enable_gen  → tick_1s clock enable
//     time_counter    → HH:MM:SS binary time
//     alarm_slot (×2) → two independent alarm channels
//     buzzer_ctrl     → patterned buzzer output + auto-silence
//     control_fsm     → 5-state Moore FSM
//
//   Additionally provides:
//   (A) AM/PM conversion (mode_12h flag):
//       When mode_12h = 1, H_out1/H_out0 display in 12-hour format and
//       pm_flag is HIGH for PM hours.
//       When mode_12h = 0 (default), 24-hour display.
//
//   (B) BCD output conversion:
//       Binary cur_hour/cur_min/cur_sec are converted to two-digit BCD
//       at the output boundary only — internal arithmetic stays binary.
//
//   (C) Alarm status indicators:
//       alarm_armed[1:0] shows which slots are currently armed.
//
// Parameters (passed through to sub-modules):
//   CLK_DIV        — master clock frequency for tick_1s generation
//   MAX_HOUR/MIN/SEC
//   SNOOZE_MIN     — minutes added per snooze press
//   BEEP_PATTERN_LEN / BEEP_ON_TICKS
//   ALARM_TIMEOUT  — seconds before auto-silence
//
// Port reference: see alarm_clock_top.sv for full FPGA-level port descriptions.
// =============================================================================

`default_nettype none

// Import typedef from control_fsm — required since typedef is file-scoped.
// In a real project this would live in a package; here we re-declare for
// single-file compilation compatibility.
typedef enum logic [2:0] {
    CORE_NORMAL     = 3'b000,
    CORE_LOAD_TIME  = 3'b001,
    CORE_LOAD_ALARM = 3'b010,
    CORE_ALARM_RING = 3'b011,
    CORE_SNOOZE_SET = 3'b100
} core_state_t;

module alarm_clock_core #(
    parameter int unsigned CLK_DIV         = 10,
    parameter int unsigned MAX_HOUR        = 23,
    parameter int unsigned MAX_MIN         = 59,
    parameter int unsigned MAX_SEC         = 59,
    parameter int unsigned SNOOZE_MIN      = 5,
    parameter int unsigned BEEP_PATTERN_LEN = 5,
    parameter int unsigned BEEP_ON_TICKS   = 2,
    parameter int unsigned ALARM_TIMEOUT   = 60
)(
    input  logic        clk,
    input  logic        reset_n,

    // Control buttons (must be debounced before reaching this module)
    input  logic        btn_load_time,
    input  logic        btn_load_alarm,
    input  logic        sel_alarm,       // 0=slot0, 1=slot1
    input  logic        btn_alarm_en_0,  // arm alarm slot 0
    input  logic        btn_alarm_en_1,  // arm alarm slot 1
    input  logic        btn_stop,
    input  logic        btn_snooze,
    input  logic        mode_12h,        // 0=24h, 1=12h display

    // BCD time / alarm input (shared for both load_time and load_alarm)
    input  logic [1:0]  H_in1,
    input  logic [3:0]  H_in0,
    input  logic [3:0]  M_in1,
    input  logic [3:0]  M_in0,

    // BCD display outputs
    output logic [1:0]  H_out1,
    output logic [3:0]  H_out0,
    output logic [3:0]  M_out1,
    output logic [3:0]  M_out0,
    output logic [3:0]  S_out1,
    output logic [3:0]  S_out0,
    output logic        pm_flag,         // HIGH = PM (only valid in 12h mode)

    // Alarm outputs
    output logic        buzzer_out,      // patterned buzzer (not constant HIGH)
    output logic [1:0]  alarm_armed      // which slots are currently armed
);

    // =========================================================================
    // Internal Wires
    // =========================================================================

    // Clock enable
    logic tick_1s;

    // Current time (binary)
    logic [4:0] cur_hour;
    logic [5:0] cur_min, cur_sec;

    // FSM control outputs
    /* verilator lint_off UNUSED */
    alarm_state_t fsm_state;   // exposed for testbench coverage hierarchy access
    /* verilator lint_on UNUSED */
    logic        load_time;
    logic [1:0]  load_alarm;
    logic [1:0]  snooze;
    logic        alarm_ring;

    // Alarm slot outputs
    logic        trigger_0, trigger_1;
    logic        armed_0,   armed_1;
    logic [4:0]  alm_hour_0, alm_hour_1;   // for optional debug / display
    logic [5:0]  alm_min_0,  alm_min_1;

    // Buzzer
    logic timeout_flag;

    // PM flag logic
    logic [4:0] display_hour;

    // =========================================================================
    // Sub-module Instantiations
    // =========================================================================

    // --- Clock Enable Generator ---
    clk_enable_gen #(
        .CLK_DIV(CLK_DIV)
    ) u_clk_en (
        .clk     (clk),
        .reset_n (reset_n),
        .tick_1s (tick_1s)
    );

    // --- Time Counter ---
    time_counter #(
        .MAX_HOUR(MAX_HOUR),
        .MAX_MIN (MAX_MIN),
        .MAX_SEC (MAX_SEC)
    ) u_time (
        .clk      (clk),
        .reset_n  (reset_n),
        .tick_1s  (tick_1s),
        .load_time(load_time),
        .H_in1    (H_in1),
        .H_in0    (H_in0),
        .M_in1    (M_in1),
        .M_in0    (M_in0),
        .cur_hour (cur_hour),
        .cur_min  (cur_min),
        .cur_sec  (cur_sec)
    );

    // --- Alarm Slot 0 ---
    alarm_slot #(
        .MAX_HOUR  (MAX_HOUR),
        .MAX_MIN   (MAX_MIN),
        .SNOOZE_MIN(SNOOZE_MIN)
    ) u_slot0 (
        .clk      (clk),
        .reset_n  (reset_n),
        .load     (load_alarm[0]),
        .arm      (btn_alarm_en_0),
        .snooze   (snooze[0]),
        .H_in1    (H_in1),
        .H_in0    (H_in0),
        .M_in1    (M_in1),
        .M_in0    (M_in0),
        .cur_hour (cur_hour),
        .cur_min  (cur_min),
        .cur_sec  (cur_sec),
        .trigger  (trigger_0),
        .armed    (armed_0),
        .alm_hour (alm_hour_0),
        .alm_min  (alm_min_0)
    );

    // --- Alarm Slot 1 ---
    alarm_slot #(
        .MAX_HOUR  (MAX_HOUR),
        .MAX_MIN   (MAX_MIN),
        .SNOOZE_MIN(SNOOZE_MIN)
    ) u_slot1 (
        .clk      (clk),
        .reset_n  (reset_n),
        .load     (load_alarm[1]),
        .arm      (btn_alarm_en_1),
        .snooze   (snooze[1]),
        .H_in1    (H_in1),
        .H_in0    (H_in0),
        .M_in1    (M_in1),
        .M_in0    (M_in0),
        .cur_hour (cur_hour),
        .cur_min  (cur_min),
        .cur_sec  (cur_sec),
        .trigger  (trigger_1),
        .armed    (armed_1),
        .alm_hour (alm_hour_1),
        .alm_min  (alm_min_1)
    );

    // --- Control FSM ---
    control_fsm u_fsm (
        .clk          (clk),
        .reset_n      (reset_n),
        .btn_load_time (btn_load_time),
        .btn_load_alarm(btn_load_alarm),
        .btn_stop     (btn_stop),
        .btn_snooze   (btn_snooze),
        .trigger_0    (trigger_0),
        .trigger_1    (trigger_1),
        .timeout_flag (timeout_flag),
        .sel_alarm    (sel_alarm),
        .state        (fsm_state),
        .load_time    (load_time),
        .load_alarm   (load_alarm),
        .snooze       (snooze),
        .alarm_ring   (alarm_ring)
    );

    // --- Buzzer Controller ---
    buzzer_ctrl #(
        .PATTERN_LEN  (BEEP_PATTERN_LEN),
        .BEEP_ON_TICKS(BEEP_ON_TICKS),
        .TIMEOUT_TICKS(ALARM_TIMEOUT)
    ) u_buzzer (
        .clk         (clk),
        .reset_n     (reset_n),
        .tick_1s     (tick_1s),
        .alarm_ring  (alarm_ring),
        .buzzer_out  (buzzer_out),
        .timeout_flag(timeout_flag)
    );

    // =========================================================================
    // AM/PM Conversion & BCD Output
    // =========================================================================

    // 12-hour conversion: midnight (0) and noon (12) both display as 12
    always_comb begin
        if (mode_12h) begin
            pm_flag = (cur_hour >= 5'd12);
            if (cur_hour == 5'd0)
                display_hour = 5'd12;
            else if (cur_hour > 5'd12)
                display_hour = cur_hour - 5'd12;
            else
                display_hour = cur_hour;
        end else begin
            pm_flag      = 1'b0;
            display_hour = cur_hour;
        end
    end

    // Binary → 2-digit BCD (at output boundary only)
    assign H_out1 = 2'(display_hour / 5'd10);
    assign H_out0 = 4'(display_hour % 5'd10);
    assign M_out1 = 4'(cur_min  / 6'd10);
    assign M_out0 = 4'(cur_min  % 6'd10);
    assign S_out1 = 4'(cur_sec  / 6'd10);
    assign S_out0 = 4'(cur_sec  % 6'd10);

    // =========================================================================
    // Alarm Armed Status
    // =========================================================================
    assign alarm_armed = {armed_1, armed_0};

endmodule

`default_nettype wire
