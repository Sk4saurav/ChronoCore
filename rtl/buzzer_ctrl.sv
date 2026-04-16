// =============================================================================
// Module  : buzzer_ctrl
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/buzzer_ctrl.sv
// =============================================================================
// Description:
//   Converts a continuous alarm_ring signal into a patterned buzzer output.
//   Instead of driving a constant HIGH (which would be an annoying, undifferent-
//   iated tone), this module generates a repeating beep-beep-pause pattern.
//
//   Default pattern (with tick_1s every 1 second):
//     Cycle length: PATTERN_LEN ticks  (default 5 = 5 seconds)
//     ON ticks    : BEEP_ON_TICKS      (default 2 = beep for 2 s)
//     OFF ticks   : PATTERN_LEN - BEEP_ON_TICKS (3 = silent for 3 s)
//
//   Pattern timeline: |BEEP|BEEP|   silence   |BEEP|BEEP|...
//
//   Auto-silence:
//     If alarm_ring stays HIGH for TIMEOUT_TICKS consecutive ticks without
//     btn_stop being pressed, timeout_flag is raised so the FSM can
//     autonomously return to NORMAL state.  This prevents the buzzer from
//     ringing forever if the user is away.
//
// Parameters:
//   PATTERN_LEN    — total cycle length in ticks (default 5)
//   BEEP_ON_TICKS  — number of ON ticks per cycle (default 2)
//   TIMEOUT_TICKS  — ticks before timeout_flag asserts (default 60 = 1 min)
//
// Ports:
//   clk           in  1  master clock
//   reset_n       in  1  active-low synchronous reset
//   tick_1s       in  1  clock-enable (1-second pulse)
//   alarm_ring    in  1  HIGH while alarm is ringing (from FSM)
//   buzzer_out    out 1  patterned buzzer signal (connect to speaker/LED)
//   timeout_flag  out 1  HIGH when alarm has been ringing for TIMEOUT_TICKS
// =============================================================================

`default_nettype none

module buzzer_ctrl #(
    parameter int unsigned PATTERN_LEN   = 5,   // ticks per full beep cycle
    parameter int unsigned BEEP_ON_TICKS = 2,   // ticks buzzer is ON per cycle
    parameter int unsigned TIMEOUT_TICKS = 60   // auto-silence after N ticks
)(
    input  logic clk,
    input  logic reset_n,
    input  logic tick_1s,
    input  logic alarm_ring,
    output logic buzzer_out,
    output logic timeout_flag
);

    // -------------------------------------------------------------------------
    // Beep Pattern Counter
    // Cycles 0 → PATTERN_LEN-1 on each tick_1s when alarm_ring is HIGH.
    // Resets when alarm_ring goes LOW.
    // -------------------------------------------------------------------------
    logic [$clog2(PATTERN_LEN)-1:0] pattern_cnt;

    always_ff @(posedge clk) begin
        if (!reset_n || !alarm_ring)
            pattern_cnt <= '0;
        else if (tick_1s)
            pattern_cnt <= (pattern_cnt == PATTERN_LEN[$clog2(PATTERN_LEN)-1:0] - 1'b1)
                           ? '0 : pattern_cnt + 1'b1;
    end

    // Buzzer ON during first BEEP_ON_TICKS ticks of each pattern cycle
    assign buzzer_out = alarm_ring && (pattern_cnt < BEEP_ON_TICKS[$clog2(PATTERN_LEN)-1:0]);

    // -------------------------------------------------------------------------
    // Auto-Silence (timeout) Counter
    // -------------------------------------------------------------------------
    logic [$clog2(TIMEOUT_TICKS+1)-1:0] timeout_cnt;

    always_ff @(posedge clk) begin
        if (!reset_n || !alarm_ring)
            timeout_cnt <= '0;
        else if (tick_1s && !timeout_flag)
            timeout_cnt <= timeout_cnt + 1'b1;
    end

    assign timeout_flag = (timeout_cnt == TIMEOUT_TICKS[$clog2(TIMEOUT_TICKS+1)-1:0]);

endmodule

`default_nettype wire
