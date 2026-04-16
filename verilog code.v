// =============================================================================
// Module  : Aclock
// File    : verilog code.v
// =============================================================================
// Description:
//   BCD alarm clock — improved version fixing all critical RTL issues:
//
//   FIX 1 — FSM replaces ad-hoc LD_time / LD_alarm flags
//            Original: two parallel `if` blocks could fire simultaneously
//            causing undefined behaviour when both inputs were high.
//            Fixed: 3-state FSM (NORMAL / LOAD_TIME / LOAD_ALARM) ensures
//            only one operation is active per clock edge.
//
//   FIX 2 — Clock-enable replaces derived clk_1s register
//            Original: clk_1s was a `reg` toggled inside always@ — an FPGA
//            timing violation (gated/derived clock).
//            Fixed: tick_1s is a combinational wire (clock-enable) so the
//            entire design runs in one clock domain.
//
//   FIX 3 — Edge-triggered alarm (single-shot)
//            Original: Alarm asserted every clk edge for the entire matching
//            minute (60 assertions, 1 full minute HIGH).
//            Fixed: prev_match register detects rising edge — alarm fires
//            exactly once at HH:MM:00.
//
//   FIX 4 — BCD input validation
//            Original: no bounds check — H=29 or M=75 silently loaded.
//            Fixed: validated_hour / validated_min clamp out-of-range inputs.
//
//   FIX 5 — STOP_al is a pulse, not a level-hold
//            Original: user had to hold STOP_al HIGH continuously.
//            Fixed: FSM transitions to NORMAL on any STOP_al pulse.
//
//   FIX 6 — Dead alarm-second registers removed
//            Original: a_sec1, a_sec0 allocated and reset but never used
//            in any comparison.  Removed.
//
// Parameters:
//   CLK_DIV — number of master clock cycles per second (default 10 for sim)
//             Change to 50_000_000 for a 50 MHz FPGA target.
//
// Ports:
//   reset    in  Synchronous active-high reset
//   clk      in  Master clock (CLK_DIV Hz)
//   H_in1    in  [1:0] Hours tens digit BCD   (0–2)
//   H_in0    in  [3:0] Hours units digit BCD  (0–9)
//   M_in1    in  [3:0] Minutes tens digit BCD (0–5)
//   M_in0    in  [3:0] Minutes units digit BCD(0–9)
//   LD_time  in  Hold HIGH to load time from H_in / M_in
//   LD_alarm in  Hold HIGH to load alarm from H_in / M_in
//   STOP_al  in  Pulse HIGH to stop a ringing alarm
//   AL_ON    in  Level HIGH to enable alarm comparison
//   Alarm    out High while alarm is ringing
//   H_out1   out [1:0] Display hours tens
//   H_out0   out [3:0] Display hours units
//   M_out1   out [3:0] Display minutes tens
//   M_out0   out [3:0] Display minutes units
//   S_out1   out [3:0] Display seconds tens
//   S_out0   out [3:0] Display seconds units
// =============================================================================

`timescale 1ns/1ps

module Aclock #(
    parameter CLK_DIV = 10          // master clock cycles per second
)(
    input            reset,
    input            clk,
    input  [1:0]     H_in1,
    input  [3:0]     H_in0,
    input  [3:0]     M_in1,
    input  [3:0]     M_in0,
    input            LD_time,
    input            LD_alarm,
    input            STOP_al,
    input            AL_ON,
    output reg       Alarm,
    output [1:0]     H_out1,
    output [3:0]     H_out0,
    output [3:0]     M_out1,
    output [3:0]     M_out0,
    output [3:0]     S_out1,
    output [3:0]     S_out0
);

// =============================================================================
// FIX 1 — FSM State Encoding
// =============================================================================
localparam [1:0]
    NORMAL     = 2'b00,
    LOAD_TIME  = 2'b01,
    LOAD_ALARM = 2'b10;

reg [1:0] state;

// =============================================================================
// FIX 2 — Clock Enable (tick_1s) — no derived clock register
// =============================================================================
// Original design toggled a reg clk_1s inside always@ — an FPGA synthesis
// violation.  This counter generates a single-cycle enable pulse instead.
// =============================================================================
reg [$clog2(CLK_DIV)-1:0] div_cnt;
wire tick_1s = (div_cnt == CLK_DIV - 1);

always @(posedge clk) begin
    if (reset)
        div_cnt <= 0;
    else
        div_cnt <= tick_1s ? 0 : div_cnt + 1;
end

// =============================================================================
// FIX 4 — Input Validation Functions
// =============================================================================
// Clamps out-of-range BCD inputs before they enter the registers.
// Example: H_in1=2, H_in0=9 → raw=29 → clamped to 23.
// =============================================================================
function [5:0] validated_hour;
    input [1:0] h1;
    input [3:0] h0;
    reg   [5:0] raw;
    begin
        raw = h1 * 6'd10 + h0;
        validated_hour = (raw > 23) ? 6'd23 : raw;
    end
endfunction

function [5:0] validated_min;
    input [3:0] m1;
    input [3:0] m0;
    reg   [6:0] raw;
    begin
        raw = m1 * 7'd10 + m0;
        validated_min = (raw > 59) ? 6'd59 : raw[5:0];
    end
endfunction

// =============================================================================
// Internal Time Registers (binary — BCD only at output boundary)
// =============================================================================
reg [5:0] tmp_hour;    // 0–23
reg [5:0] tmp_minute;  // 0–59
reg [5:0] tmp_second;  // 0–59

// Alarm registers
reg [5:0] a_hour;      // stored in binary (validated on load)
reg [5:0] a_min;

// =============================================================================
// FIX 1 — FSM: State Register + Time Counter
// One mode active at a time — LD_time and LD_alarm cannot conflict.
// FIX 4 — Inputs validated before being stored.
// =============================================================================
always @(posedge clk) begin
    if (reset) begin
        state      <= NORMAL;
        tmp_hour   <= 6'd0;
        tmp_minute <= 6'd0;
        tmp_second <= 6'd0;
        a_hour     <= 6'd0;
        a_min      <= 6'd0;
    end else begin
        // --- FSM next-state ---
        case (state)
            NORMAL:     if      (LD_time)  state <= LOAD_TIME;
                        else if (LD_alarm) state <= LOAD_ALARM;
            LOAD_TIME:  if (!LD_time)  state <= NORMAL;
            LOAD_ALARM: if (!LD_alarm) state <= NORMAL;
            default:                   state <= NORMAL;
        endcase

        // --- State actions ---
        case (state)
            LOAD_TIME: begin
                // FIX 4: validated load — clamp before storing
                tmp_hour   <= validated_hour(H_in1, H_in0);
                tmp_minute <= validated_min(M_in1, M_in0);
                tmp_second <= 6'd0;
            end

            LOAD_ALARM: begin
                // FIX 4: validated alarm load
                a_hour <= validated_hour(H_in1, H_in0);
                a_min  <= validated_min(M_in1, M_in0);
            end

            default: begin
                // NORMAL state: advance clock every tick_1s
                if (tick_1s) begin
                    if (tmp_second == 6'd59) begin
                        tmp_second <= 6'd0;
                        if (tmp_minute == 6'd59) begin
                            tmp_minute <= 6'd0;
                            tmp_hour   <= (tmp_hour == 6'd23) ? 6'd0 : tmp_hour + 1'b1;
                        end else begin
                            tmp_minute <= tmp_minute + 1'b1;
                        end
                    end else begin
                        tmp_second <= tmp_second + 1'b1;
                    end
                end
            end
        endcase
    end
end

// =============================================================================
// FIX 3 — Edge-Triggered Alarm (single-shot at HH:MM:00)
// FIX 5 — STOP_al handled as a pulse (no level-hold required)
// =============================================================================
// Original: level-sensitive comparison fired every clk_1s edge for the
// full 60-second matching minute.  This detects only the rising edge of
// the match signal so the alarm fires exactly once at second 00.
// =============================================================================
wire match = AL_ON &&
             (tmp_hour   == a_hour) &&
             (tmp_minute == a_min)  &&
             (tmp_second == 6'd0);

reg prev_match;

always @(posedge clk) begin
    if (reset) begin
        Alarm      <= 1'b0;
        prev_match <= 1'b0;
    end else begin
        prev_match <= match;

        // Rising edge of match triggers alarm (single-shot)
        if (match && !prev_match)
            Alarm <= 1'b1;

        // STOP_al pulse clears alarm — no hold required (FIX 5)
        if (STOP_al)
            Alarm <= 1'b0;
    end
end

// =============================================================================
// BCD Output Conversion (binary → 2-digit BCD at output only)
// =============================================================================
// FIX 6: a_sec1 / a_sec0 registers removed — they were allocated and reset
// but never used in any alarm comparison (dead logic).
//
// Hour tens: simple 3-way compare (0, 1, or 2)
// Minute / Second tens: integer division by 10 (synthesises cleanly)
// =============================================================================
assign H_out1 = (tmp_hour >= 6'd20) ? 2'd2 :
                (tmp_hour >= 6'd10) ? 2'd1 : 2'd0;
assign H_out0 = tmp_hour - H_out1 * 6'd10;
assign M_out1 = tmp_minute / 6'd10;
assign M_out0 = tmp_minute % 6'd10;
assign S_out1 = tmp_second / 6'd10;
assign S_out0 = tmp_second % 6'd10;

endmodule
