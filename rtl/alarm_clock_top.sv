// =============================================================================
// Module  : alarm_clock_top
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/alarm_clock_top.sv
// =============================================================================
// Description:
//   FPGA top-level wrapper.  Instantiates a debounce module for every button
//   input and connects to alarm_clock_core.
//
//   Board assumptions:
//     - System clock: CLK_FREQ_HZ (default 50_000_000 = 50 MHz)
//     - Active-low reset button
//     - BCD inputs from DIP switches (no debounce needed — slow manual inputs)
//     - 5 control buttons: load_time, load_alarm, alarm_en_0, alarm_en_1,
//                          stop, snooze, sel_alarm (switch), mode_12h (switch)
//     - 6 pairs of BCD 7-segment display pins
//     - 1 buzzer / LED output
//
//   To simulate (without FPGA), use alarm_clock_core directly with CLK_DIV=10.
//
// Parameters:
//   CLK_FREQ_HZ  — board clock frequency (used to calculate both CLK_DIV=
//                  CLK_FREQ_HZ for the core and STABLE_CYCLES for debounce)
//   DEBOUNCE_MS  — debounce window in milliseconds (default 20 ms)
// =============================================================================

`default_nettype none

module alarm_clock_top #(
    parameter int unsigned CLK_FREQ_HZ = 50_000_000,
    parameter int unsigned DEBOUNCE_MS = 20
)(
    input  logic        clk,
    input  logic        rst_n_raw,            // raw reset button

    // Raw button inputs (from physical pins)
    input  logic        btn_load_time_raw,
    input  logic        btn_load_alarm_raw,
    input  logic        btn_alarm_en_0_raw,
    input  logic        btn_alarm_en_1_raw,
    input  logic        btn_stop_raw,
    input  logic        btn_snooze_raw,

    // Switch inputs (slow — no debounce needed)
    input  logic        sw_sel_alarm,         // 0=slot0, 1=slot1
    input  logic        sw_mode_12h,          // 0=24h, 1=12h

    // BCD time/alarm inputs (DIP switches)
    input  logic [1:0]  H_in1,
    input  logic [3:0]  H_in0,
    input  logic [3:0]  M_in1,
    input  logic [3:0]  M_in0,

    // BCD display outputs (connect to 7-segment decoders)
    output logic [1:0]  H_out1,
    output logic [3:0]  H_out0,
    output logic [3:0]  M_out1,
    output logic [3:0]  M_out0,
    output logic [3:0]  S_out1,
    output logic [3:0]  S_out0,
    output logic        pm_flag,              // PM indicator LED

    // Alarm outputs
    output logic        buzzer_out,           // patterned buzzer
    output logic [1:0]  alarm_armed           // armed status LEDs
);

    // Debounce window in clock cycles
    localparam int unsigned STABLE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

    // -------------------------------------------------------------------------
    // Debounced Signals
    // -------------------------------------------------------------------------
    logic reset_n_db;
    logic btn_load_time_db, btn_load_alarm_db;
    logic btn_alarm_en_0_db, btn_alarm_en_1_db;
    logic btn_stop_db, btn_snooze_db;

    // Reset debounce (uses self-powered reset = 1'b1)
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_rst (
        .clk(clk), .reset_n(1'b1), .btn_raw(rst_n_raw), .btn_clean(reset_n_db)
    );

    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_lt (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_load_time_raw), .btn_clean(btn_load_time_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_la (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_load_alarm_raw), .btn_clean(btn_load_alarm_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_en0 (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_alarm_en_0_raw), .btn_clean(btn_alarm_en_0_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_en1 (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_alarm_en_1_raw), .btn_clean(btn_alarm_en_1_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_stop (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_stop_raw), .btn_clean(btn_stop_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_snz (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_snooze_raw), .btn_clean(btn_snooze_db)
    );

    // -------------------------------------------------------------------------
    // Core Alarm Clock
    // -------------------------------------------------------------------------
    alarm_clock_core #(
        .CLK_DIV        (CLK_FREQ_HZ),
        .MAX_HOUR       (23),
        .MAX_MIN        (59),
        .MAX_SEC        (59),
        .SNOOZE_MIN     (5),
        .BEEP_PATTERN_LEN(5),
        .BEEP_ON_TICKS  (2),
        .ALARM_TIMEOUT  (60)
    ) u_core (
        .clk            (clk),
        .reset_n        (reset_n_db),
        .btn_load_time  (btn_load_time_db),
        .btn_load_alarm (btn_load_alarm_db),
        .sel_alarm      (sw_sel_alarm),
        .btn_alarm_en_0 (btn_alarm_en_0_db),
        .btn_alarm_en_1 (btn_alarm_en_1_db),
        .btn_stop       (btn_stop_db),
        .btn_snooze     (btn_snooze_db),
        .mode_12h       (sw_mode_12h),
        .H_in1          (H_in1),
        .H_in0          (H_in0),
        .M_in1          (M_in1),
        .M_in0          (M_in0),
        .H_out1         (H_out1),
        .H_out0         (H_out0),
        .M_out1         (M_out1),
        .M_out0         (M_out0),
        .S_out1         (S_out1),
        .S_out0         (S_out0),
        .pm_flag        (pm_flag),
        .buzzer_out     (buzzer_out),
        .alarm_armed    (alarm_armed)
    );

endmodule

`default_nettype wire
