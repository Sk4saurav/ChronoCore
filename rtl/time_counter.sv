// =============================================================================
// Module  : time_counter
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/time_counter.sv
// =============================================================================
// Description:
//   24-hour HH:MM:SS counter with synchronous load, BCD input validation,
//   and clock-enable-based timekeeping (no derived clocks).
//
//   Internal representation is binary (not BCD) for compact arithmetic.
//   BCD conversion for display outputs is done in alarm_clock_core.
//
//   Input validation:
//     If the user provides an out-of-range BCD value on H_in / M_in the
//     counter clamps to MAX_HOUR / MAX_MIN rather than storing an illegal
//     state.  This prevents hour=29 or minute=75 from ever entering the FSM.
//
// Parameters:
//   MAX_HOUR  — maximum hour value (23 for 24-h mode, 11 for 12-h arithmetic)
//   MAX_MIN   — maximum minute value (59)
//   MAX_SEC   — maximum second value (59)
//
// Ports:
//   clk          in  1       master clock
//   reset_n      in  1       active-low synchronous reset (clears to 00:00:00)
//   tick_1s      in  1       clock-enable: advance counter by 1 second
//   load_time    in  1       load H_in/M_in into counter (single-cycle pulse)
//   H_in1        in  2       hours tens digit   (BCD, 0–2)
//   H_in0        in  4       hours units digit  (BCD, 0–9)
//   M_in1        in  4       minutes tens digit (BCD, 0–5)
//   M_in0        in  4       minutes units digit(BCD, 0–9)
//   cur_hour     out 5       current hour   (binary, 0–23)
//   cur_min      out 6       current minute (binary, 0–59)
//   cur_sec      out 6       current second (binary, 0–59)
// =============================================================================

`default_nettype none

module time_counter #(
    parameter int unsigned MAX_HOUR = 23,
    parameter int unsigned MAX_MIN  = 59,
    parameter int unsigned MAX_SEC  = 59
)(
    input  logic        clk,
    input  logic        reset_n,
    input  logic        tick_1s,
    input  logic        load_time,    // single-cycle: load H_in/M_in this cycle
    input  logic [1:0]  H_in1,
    input  logic [3:0]  H_in0,
    input  logic [3:0]  M_in1,
    input  logic [3:0]  M_in0,
    output logic [4:0]  cur_hour,
    output logic [5:0]  cur_min,
    output logic [5:0]  cur_sec
);

    // -------------------------------------------------------------------------
    // BCD validation helpers (functions, not tasks — purely combinational)
    // -------------------------------------------------------------------------
    function automatic logic [4:0] validated_hour(
        input logic [1:0] h1,
        input logic [3:0] h0
    );
        logic [5:0] raw;
        raw = ({4'b0, h1} * 6'd10) + {2'b0, h0};
        return (raw > MAX_HOUR[5:0]) ? MAX_HOUR[4:0] : raw[4:0];
    endfunction

    function automatic logic [5:0] validated_min(
        input logic [3:0] m1,
        input logic [3:0] m0
    );
        logic [6:0] raw;
        raw = ({3'b0, m1} * 7'd10) + {3'b0, m0};
        return (raw > MAX_MIN[6:0]) ? MAX_MIN[5:0] : raw[5:0];
    endfunction

    // -------------------------------------------------------------------------
    // Counter Registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cur_sec  <= '0;
            cur_min  <= '0;
            cur_hour <= '0;
        end else if (load_time) begin
            // Validated load — invalid BCD is silently clamped
            cur_hour <= validated_hour(H_in1, H_in0);
            cur_min  <= validated_min(M_in1, M_in0);
            cur_sec  <= '0;
        end else if (tick_1s) begin
            // Normal timekeeping: seconds → minutes → hours chain
            if (cur_sec == MAX_SEC[5:0]) begin
                cur_sec <= '0;
                if (cur_min == MAX_MIN[5:0]) begin
                    cur_min  <= '0;
                    cur_hour <= (cur_hour == MAX_HOUR[4:0]) ? '0 : cur_hour + 1'b1;
                end else begin
                    cur_min <= cur_min + 1'b1;
                end
            end else begin
                cur_sec <= cur_sec + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
