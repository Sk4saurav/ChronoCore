// =============================================================================
// alarm_clock_top.sv — Top-Level FPGA Wrapper
// =============================================================================
//
// Instantiates:
//   - debounce  (x5) for each control button
//   - alarm_clock_sv  — the core design
//
// Designed for a board with:
//   - 50 MHz system clock → CLK_DIV = 50_000_000
//   - Active-low reset button
//   - 6 BCD output ports for 7-segment display drivers (not included here)
//
// To target a 10 Hz simulation clock instead, override CLK_DIV = 10.
// =============================================================================

`default_nettype none

module alarm_clock_top #(
    parameter int unsigned CLK_FREQ_HZ  = 50_000_000,  // board clock frequency
    parameter int unsigned DEBOUNCE_MS  = 20            // debounce window in ms
)(
    input  logic        clk,
    input  logic        reset_n_raw,       // from physical reset button (noisy)

    // Raw button inputs from physical pins
    input  logic        btn_load_time_raw,
    input  logic        btn_load_alarm_raw,
    input  logic        btn_alarm_en_raw,
    input  logic        btn_stop_raw,
    input  logic        btn_snooze_raw,

    // BCD time/alarm inputs (from DIP switches or another source)
    input  logic [1:0]  H_in1,
    input  logic [3:0]  H_in0,
    input  logic [3:0]  M_in1,
    input  logic [3:0]  M_in0,

    // BCD outputs (connect to 7-segment decoders)
    output logic [1:0]  H_out1,
    output logic [3:0]  H_out0,
    output logic [3:0]  M_out1,
    output logic [3:0]  M_out0,
    output logic [3:0]  S_out1,
    output logic [3:0]  S_out0,

    output logic        alarm_out          // drive buzzer / LED
);

    localparam int unsigned STABLE_CYCLES =
        (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;   // cycles for debounce window

    // Debounced signals
    logic reset_n_db;
    logic btn_load_time_db, btn_load_alarm_db;
    logic btn_alarm_en_db, btn_stop_db, btn_snooze_db;

    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_reset (
        .clk(clk), .reset_n(1'b1),
        .btn_raw(reset_n_raw), .btn_clean(reset_n_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_load_time (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_load_time_raw), .btn_clean(btn_load_time_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_load_alarm (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_load_alarm_raw), .btn_clean(btn_load_alarm_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_alarm_en (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_alarm_en_raw), .btn_clean(btn_alarm_en_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_stop (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_stop_raw), .btn_clean(btn_stop_db)
    );
    debounce #(.STABLE_COUNT(STABLE_CYCLES)) u_deb_snooze (
        .clk(clk), .reset_n(reset_n_db),
        .btn_raw(btn_snooze_raw), .btn_clean(btn_snooze_db)
    );

    // Core alarm clock
    alarm_clock_sv #(
        .CLK_DIV(CLK_FREQ_HZ)    // 1-second tick from board frequency
    ) u_core (
        .clk           (clk),
        .reset_n       (reset_n_db),
        .btn_load_time (btn_load_time_db),
        .btn_load_alarm(btn_load_alarm_db),
        .btn_alarm_en  (btn_alarm_en_db),
        .btn_stop      (btn_stop_db),
        .btn_snooze    (btn_snooze_db),
        .H_in1         (H_in1),
        .H_in0         (H_in0),
        .M_in1         (M_in1),
        .M_in0         (M_in0),
        .H_out1        (H_out1),
        .H_out0        (H_out0),
        .M_out1        (M_out1),
        .M_out0        (M_out0),
        .S_out1        (S_out1),
        .S_out0        (S_out0),
        .alarm_out     (alarm_out)
    );

endmodule

`default_nettype wire
