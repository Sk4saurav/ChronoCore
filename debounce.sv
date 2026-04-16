// =============================================================================
// debounce.sv — Button Debouncer for FPGA targets
// =============================================================================
//
// Necessary for any physical FPGA deployment.
// Original design had no debouncing — mechanical switch bounce causes multiple
// rising edges per button press, which can corrupt LD_time / LD_alarm loads.
//
// Algorithm: synchronise input to clock domain, then require the signal to be
// stable for STABLE_COUNT consecutive clock cycles before propagating.
//
// Parameters:
//   STABLE_COUNT — number of stable clock cycles required (default 20 ms at
//                  50 MHz = 1_000_000 cycles; tune for your clock frequency)
// =============================================================================

`default_nettype none

module debounce #(
    parameter int unsigned STABLE_COUNT = 1_000_000
)(
    input  logic clk,
    input  logic reset_n,
    input  logic btn_raw,    // raw (noisy) input from physical pin
    output logic btn_clean   // debounced, synchronised output
);

    // Two-stage synchroniser (metastability mitigation)
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

    // Stability counter
    logic [$clog2(STABLE_COUNT)-1:0] cnt;
    logic stable_val;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cnt        <= '0;
            stable_val <= 1'b0;
            btn_clean  <= 1'b0;
        end else begin
            if (sync1 != stable_val) begin
                // Input changed — restart counter
                cnt <= '0;
            end else if (cnt == STABLE_COUNT - 1) begin
                // Stable for required duration — propagate
                btn_clean  <= stable_val;
            end else begin
                cnt <= cnt + 1'b1;
            end
            stable_val <= sync1;
        end
    end

endmodule

`default_nettype wire
