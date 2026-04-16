// =============================================================================
// Module  : clk_enable_gen
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/clk_enable_gen.sv
// =============================================================================
// Description:
//   Generates a single-cycle clock-enable pulse (tick_1s) exactly once per
//   second from a master clock running at CLK_DIV Hz.
//
//   WHY NOT A DERIVED CLOCK:
//   Driving a register-based clk_1s from inside an always_ff block creates a
//   gated/derived clock.  On FPGAs this violates timing constraints and causes
//   synthesis warnings.  A clock-enable used as `if (tick_1s)` keeps the entire
//   design in a single clock domain — the recommended RTL practice.
//
// Parameters:
//   CLK_DIV — master clock frequency in Hz (= cycles per second).
//              Default 10 → simulation-friendly 10 Hz master clock.
//              Override to 50_000_000 for a 50 MHz FPGA target.
//
// Ports:
//   clk      in  1  master clock
//   reset_n  in  1  active-low synchronous reset
//   tick_1s  out 1  single-cycle HIGH pulse every 1 s
// =============================================================================

`default_nettype none

module clk_enable_gen #(
    parameter int unsigned CLK_DIV = 10
)(
    input  logic clk,
    input  logic reset_n,
    output logic tick_1s
);

    // Counter width: ceil(log2(CLK_DIV))
    logic [$clog2(CLK_DIV)-1:0] cnt;

    always_ff @(posedge clk) begin
        if (!reset_n)
            cnt <= '0;
        else
            cnt <= (cnt == CLK_DIV[($clog2(CLK_DIV)-1):0] - 1'b1) ? '0 : cnt + 1'b1;
    end

    // Single-cycle pulse in the last count position
    assign tick_1s = (cnt == CLK_DIV[($clog2(CLK_DIV)-1):0] - 1'b1);

endmodule

`default_nettype wire
