// =============================================================================
// Module  : debounce
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/debounce.sv
// =============================================================================
// Description:
//   Two-stage synchroniser + stability counter debouncer.
//
//   Physical buttons produce noisy signals due to mechanical contact bounce.
//   Without debouncing, a single button press can appear as many rising edges
//   on a fast FPGA clock — causing multiple unintended LD_time / LD_alarm
//   loads.  This module suppresses that bounce.
//
//   Algorithm:
//     1. Two-stage FF synchroniser eliminates metastability from async inputs.
//     2. When the synchronised signal differs from the current stable value,
//        the counter is reset.
//     3. Only when the signal stays constant for STABLE_COUNT consecutive
//        clock cycles does btn_clean update to the new value.
//
// Parameters:
//   STABLE_COUNT — clock cycles required for stability (default 1_000_000
//                  = 20 ms at 50 MHz.  Use 2 for 10 Hz simulation.)
//
// Ports:
//   clk       in  1  master clock
//   reset_n   in  1  active-low synchronous reset
//   btn_raw   in  1  raw input from physical pin
//   btn_clean out 1  debounced, synchronised output
// =============================================================================

`default_nettype none

module debounce #(
    parameter int unsigned STABLE_COUNT = 1_000_000
)(
    input  logic clk,
    input  logic reset_n,
    input  logic btn_raw,
    output logic btn_clean
);

    // -------------------------------------------------------------------------
    // Two-stage synchroniser (CDC / metastability mitigation)
    // -------------------------------------------------------------------------
    logic sync0, sync1;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
        end else begin
            sync0 <= btn_raw;
            sync1 <= sync0;
        end
    end

    // -------------------------------------------------------------------------
    // Stability Counter
    // -------------------------------------------------------------------------
    logic [$clog2(STABLE_COUNT+1)-1:0] cnt;
    logic stable_val;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cnt        <= '0;
            stable_val <= 1'b0;
            btn_clean  <= 1'b0;
        end else begin
            if (sync1 != stable_val) begin
                // Input changed — restart stability counter
                cnt        <= '0;
                stable_val <= sync1;
            end else if (cnt == STABLE_COUNT[$clog2(STABLE_COUNT+1)-1:0]) begin
                // Stable for required duration — propagate to output
                btn_clean <= stable_val;
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
