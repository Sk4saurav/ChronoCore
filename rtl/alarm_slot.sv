// =============================================================================
// Module  : alarm_slot
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/alarm_slot.sv
// =============================================================================
// Description:
//   One independent alarm slot.  Stores an alarm time (HH:MM), compares it
//   to the current time, and produces a single-cycle trigger pulse at the
//   exact second the alarm fires (edge-triggered, not level-sensitive).
//
//   Key design decisions:
//   (A) Edge detection (trigger = match && !prev_match):
//       The original design asserted Alarm HIGH for the ENTIRE matching minute
//       (60 consecutive clock edges).  This implementation fires a single-cycle
//       pulse at HH:MM:00 and never reasserts until the alarm is re-armed.
//
//   (B) Snooze adds SNOOZE_MIN minutes to the stored alarm time.
//       Overflow into the next hour (and midnight wrap) is handled correctly.
//
//   (C) This module is instantiated twice in alarm_clock_core for two
//       independent alarm slots.
//
// Parameters:
//   MAX_HOUR   — maximum hour value (23)
//   MAX_MIN    — maximum minute value (59)
//   SNOOZE_MIN — minutes added per snooze press (default 5)
//
// Ports:
//   clk         in  1  master clock
//   reset_n     in  1  active-low synchronous reset
//   load        in  1  single-cycle: save H_in/M_in as alarm time
//   arm         in  1  level: alarm comparison enabled when HIGH
//   snooze      in  1  single-cycle: advance alarm_min by SNOOZE_MIN
//   H_in1       in  2  alarm-hours tens digit   (BCD)
//   H_in0       in  4  alarm-hours units digit  (BCD)
//   M_in1       in  4  alarm-minutes tens digit (BCD)
//   M_in0       in  4  alarm-minutes units digit(BCD)
//   cur_hour    in  5  current time hour   (binary)
//   cur_min     in  6  current time minute (binary)
//   cur_sec     in  6  current time second (binary)
//   trigger     out 1  single-cycle HIGH pulse when alarm fires
//   armed       out 1  reflects arm input (pipe-friendly)
//   alm_hour    out 5  stored alarm hour   (for snooze display / debug)
//   alm_min     out 6  stored alarm minute (for snooze display / debug)
// =============================================================================

`default_nettype none

module alarm_slot #(
    parameter int unsigned MAX_HOUR   = 23,
    parameter int unsigned MAX_MIN    = 59,
    parameter int unsigned SNOOZE_MIN = 5
)(
    input  logic        clk,
    input  logic        reset_n,
    // Control
    input  logic        load,
    input  logic        arm,
    input  logic        snooze,
    // Alarm time BCD input
    input  logic [1:0]  H_in1,
    input  logic [3:0]  H_in0,
    input  logic [3:0]  M_in1,
    input  logic [3:0]  M_in0,
    // Current time (binary, from time_counter)
    input  logic [4:0]  cur_hour,
    input  logic [5:0]  cur_min,
    input  logic [5:0]  cur_sec,
    // Outputs
    output logic        trigger,
    output logic        armed,
    output logic [4:0]  alm_hour,
    output logic [5:0]  alm_min
);

    // -------------------------------------------------------------------------
    // BCD validation helpers
    // -------------------------------------------------------------------------
    function automatic logic [4:0] validated_hour(
        input logic [1:0] h1, input logic [3:0] h0
    );
        logic [5:0] raw;
        raw = ({4'b0, h1} * 6'd10) + {2'b0, h0};
        return (raw > MAX_HOUR[5:0]) ? MAX_HOUR[4:0] : raw[4:0];
    endfunction

    function automatic logic [5:0] validated_min(
        input logic [3:0] m1, input logic [3:0] m0
    );
        logic [6:0] raw;
        raw = ({3'b0, m1} * 7'd10) + {3'b0, m0};
        return (raw > MAX_MIN[6:0]) ? MAX_MIN[5:0] : raw[5:0];
    endfunction

    // -------------------------------------------------------------------------
    // Alarm Time Storage
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            alm_hour <= '0;
            alm_min  <= '0;
        end else if (load) begin
            alm_hour <= validated_hour(H_in1, H_in0);
            alm_min  <= validated_min(M_in1, M_in0);
        end else if (snooze) begin
            // Add SNOOZE_MIN minutes with hour and midnight rollover
            if ({1'b0, alm_min} + SNOOZE_MIN[5:0] > MAX_MIN[5:0]) begin
                alm_min  <= ({1'b0, alm_min} + SNOOZE_MIN[5:0]) - (MAX_MIN[5:0] + 1'b1);
                alm_hour <= (alm_hour == MAX_HOUR[4:0]) ? '0 : alm_hour + 1'b1;
            end else begin
                alm_min  <= alm_min + SNOOZE_MIN[5:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Arm Register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!reset_n) armed <= 1'b0;
        else          armed <= arm;
    end

    // -------------------------------------------------------------------------
    // Match Detection & Edge Trigger
    // -------------------------------------------------------------------------
    // Match fires at the exact second boundary (cur_sec == 0) of the alarm
    // minute.  Comparing seconds prevents a 60-second-long trigger window.
    logic match, prev_match;

    assign match = armed &&
                   (cur_hour == alm_hour) &&
                   (cur_min  == alm_min)  &&
                   (cur_sec  == '0);

    always_ff @(posedge clk) begin
        if (!reset_n) prev_match <= 1'b0;
        else          prev_match <= match;
    end

    // Single-cycle rising-edge pulse
    assign trigger = match && !prev_match;

endmodule

`default_nettype wire
