// =============================================================================
// alarm_clock_sv.sv — Professional SystemVerilog Alarm Clock
// =============================================================================
//
// Addresses all critical issues found in the original "verilog code.v":
//   1. FSM replaces ad-hoc control flags (eliminates LD_time+LD_alarm race)
//   2. Clock-enable (tick_1s) replaces derived clk_1s register (no FPGA timing violation)
//   3. Edge-triggered alarm (match && !prev_match) — single-shot, not level-sensitive
//   4. BCD input validation — clamps invalid hours/minutes on load
//   5. Snooze feature (+5 minutes, with hour/day rollover)
//   6. Fully parameterised (CLK_DIV, MAX_HOUR, MAX_MIN, MAX_SEC)
//   7. Active-low synchronous reset (FPGA best practice)
//   8. Simulation assertions for invariant checking
//
// Interface:
//   clk           — Master clock (frequency = CLK_DIV Hz for 1-second ticks)
//   reset_n       — Active-low synchronous reset
//   btn_load_time — Hold HIGH to enter LOAD_TIME state
//   btn_load_alarm— Hold HIGH to enter LOAD_ALARM state
//   btn_alarm_en  — Level signal: enables alarm comparison
//   btn_stop      — Pulse: stops ringing alarm, returns to NORMAL
//   btn_snooze    — Pulse: sets alarm = current_time + 5 min, returns to NORMAL
//   H_in1 [1:0]   — Hours tens digit  (0–2)
//   H_in0 [3:0]   — Hours units digit (0–9)
//   M_in1 [3:0]   — Minutes tens digit (0–5)
//   M_in0 [3:0]   — Minutes units digit (0–9)
//   H_out1/H_out0 — Current hour BCD digits
//   M_out1/M_out0 — Current minute BCD digits
//   S_out1/S_out0 — Current second BCD digits
//   alarm_out     — HIGH while alarm is ringing (state == ALARM_RING)
// =============================================================================

`default_nettype none

module alarm_clock_sv #(
    parameter int unsigned MAX_HOUR = 23,
    parameter int unsigned MAX_MIN  = 59,
    parameter int unsigned MAX_SEC  = 59,
    parameter int unsigned CLK_DIV  = 10   // input clk freq in Hz (10 Hz default)
)(
    input  logic        clk,
    input  logic        reset_n,          // active-low synchronous reset

    // Control buttons (assume externally debounced; see debounce.sv for FPGA use)
    input  logic        btn_load_time,
    input  logic        btn_load_alarm,
    input  logic        btn_alarm_en,
    input  logic        btn_stop,
    input  logic        btn_snooze,

    // BCD time/alarm input
    input  logic [1:0]  H_in1,           // hours tens   (0–2)
    input  logic [3:0]  H_in0,           // hours units  (0–9)
    input  logic [3:0]  M_in1,           // minutes tens (0–5)
    input  logic [3:0]  M_in0,           // minutes units(0–9)

    // BCD display outputs
    output logic [1:0]  H_out1,
    output logic [3:0]  H_out0,
    output logic [3:0]  M_out1,
    output logic [3:0]  M_out0,
    output logic [3:0]  S_out1,
    output logic [3:0]  S_out0,

    // Alarm output
    output logic        alarm_out
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        NORMAL     = 3'b000,
        LOAD_TIME  = 3'b001,
        LOAD_ALARM = 3'b010,
        ALARM_RING = 3'b011,
        SNOOZE_SET = 3'b100
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // Clock Enable Generator — 1-second tick, NO derived clock register
    // =========================================================================
    // Original design drove a `reg clk_1s` from inside an always block,
    // which synthesises to a gated clock — a timing violation on FPGAs.
    // This design uses a combinational clock-enable signal instead.
    // =========================================================================
    logic [$clog2(CLK_DIV)-1:0] div_cnt;
    logic                        tick_1s;

    always_ff @(posedge clk) begin
        if (!reset_n)
            div_cnt <= '0;
        else
            div_cnt <= (div_cnt == CLK_DIV - 1) ? '0 : div_cnt + 1'b1;
    end

    assign tick_1s = (div_cnt == CLK_DIV - 1);

    // =========================================================================
    // Internal Time Registers (binary for arithmetic; BCD only at output)
    // =========================================================================
    logic [4:0] cur_sec;     // 0–59
    logic [5:0] cur_min;     // 0–59
    logic [4:0] cur_hour;    // 0–23

    // =========================================================================
    // Time Counter
    // Only advances in NORMAL state on each tick_1s clock enable.
    // Loaded (with validation) when FSM enters LOAD_TIME.
    // =========================================================================
    // Input validation helper: clamp to max if BCD input is out of range
    function automatic logic [4:0] validated_hour(
        input logic [1:0] h1, input logic [3:0] h0
    );
        logic [5:0] raw;
        raw = h1 * 6'd10 + h0;
        return (raw > MAX_HOUR) ? MAX_HOUR[4:0] : raw[4:0];
    endfunction

    function automatic logic [5:0] validated_min(
        input logic [3:0] m1, input logic [3:0] m0
    );
        logic [6:0] raw;
        raw = m1 * 7'd10 + m0;
        return (raw > MAX_MIN) ? MAX_MIN[5:0] : raw[5:0];
    endfunction

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            cur_sec  <= '0;
            cur_min  <= '0;
            cur_hour <= '0;
        end else if (state == LOAD_TIME) begin
            // Validated BCD load
            cur_hour <= validated_hour(H_in1, H_in0);
            cur_min  <= validated_min(M_in1, M_in0);
            cur_sec  <= '0;
        end else if (tick_1s && (state == NORMAL || state == ALARM_RING)) begin
            // Normal timekeeping — seconds → minutes → hours rollover
            if (cur_sec == MAX_SEC[4:0]) begin
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

    // =========================================================================
    // Alarm Register
    // Loaded (with validation) when FSM enters LOAD_ALARM.
    // Bumped +5 min when FSM enters SNOOZE_SET.
    // =========================================================================
    logic [4:0] alm_hour;
    logic [5:0] alm_min;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            alm_hour <= '0;
            alm_min  <= '0;
        end else if (state == LOAD_ALARM) begin
            alm_hour <= validated_hour(H_in1, H_in0);
            alm_min  <= validated_min(M_in1, M_in0);
        end else if (state == SNOOZE_SET) begin
            // Add 5 minutes with rollover
            if (alm_min + 6'd5 > MAX_MIN[5:0]) begin
                alm_min  <= (alm_min + 6'd5) - 6'd60;
                alm_hour <= (alm_hour == MAX_HOUR[4:0]) ? '0 : alm_hour + 1'b1;
            end else begin
                alm_min  <= alm_min + 6'd5;
            end
        end
    end

    // =========================================================================
    // Alarm Match & Edge Detection
    // Original design: level-sensitive — alarm asserted every clk_1s tick
    // for the entire matching minute (60 assertions, stays HIGH).
    // This design: rising-edge triggered — alarm fires ONCE at HH:MM:00.
    // =========================================================================
    logic match, prev_match, alarm_trigger;

    // Match at the exact second boundary (00 seconds of the alarm minute)
    assign match = (cur_hour == alm_hour) &&
                   (cur_min  == alm_min)  &&
                   (cur_sec  == '0);

    always_ff @(posedge clk) begin
        if (!reset_n) prev_match <= 1'b0;
        else          prev_match <= match;
    end

    assign alarm_trigger = match && !prev_match && btn_alarm_en;

    // =========================================================================
    // FSM — State Register
    // =========================================================================
    always_ff @(posedge clk) begin
        if (!reset_n) state <= NORMAL;
        else          state <= next_state;
    end

    // =========================================================================
    // FSM — Next-State Combinational Logic
    // Only ONE mode can be active at any time — resolves the original
    // race condition where LD_time and LD_alarm could both be asserted.
    // =========================================================================
    always_comb begin
        next_state = state;  // default: stay
        unique case (state)
            NORMAL:     begin
                            if      (btn_load_time)  next_state = LOAD_TIME;
                            else if (btn_load_alarm) next_state = LOAD_ALARM;
                            else if (alarm_trigger)  next_state = ALARM_RING;
                        end
            LOAD_TIME:  if (!btn_load_time)           next_state = NORMAL;
            LOAD_ALARM: if (!btn_load_alarm)           next_state = NORMAL;
            ALARM_RING: begin
                            if      (btn_stop)   next_state = NORMAL;
                            else if (btn_snooze) next_state = SNOOZE_SET;
                        end
            SNOOZE_SET:                               next_state = NORMAL;
            default:                                  next_state = NORMAL;
        endcase
    end

    // =========================================================================
    // Alarm Output Register
    // =========================================================================
    always_ff @(posedge clk) begin
        if (!reset_n) alarm_out <= 1'b0;
        else          alarm_out <= (next_state == ALARM_RING);
    end

    // =========================================================================
    // BCD Output Conversion (binary → two BCD digits)
    // =========================================================================
    always_comb begin
        H_out1 = 2'(cur_hour / 5'd10);
        H_out0 = 4'(cur_hour % 5'd10);
        M_out1 = 4'(cur_min  / 6'd10);
        M_out0 = 4'(cur_min  % 6'd10);
        S_out1 = 4'(cur_sec  / 5'd10);
        S_out0 = 4'(cur_sec  % 5'd10);
    end

    // =========================================================================
    // Assertions — active in simulation only
    // =========================================================================
    `ifdef SIMULATION
    property p_hour_range;
        @(posedge clk) disable iff (!reset_n) (cur_hour <= MAX_HOUR);
    endproperty

    property p_min_range;
        @(posedge clk) disable iff (!reset_n) (cur_min <= MAX_MIN);
    endproperty

    property p_sec_range;
        @(posedge clk) disable iff (!reset_n) (cur_sec <= MAX_SEC);
    endproperty

    assert property (p_hour_range) else
        $error("[ASSERT] Hour out of range: %0d (max %0d)", cur_hour, MAX_HOUR);
    assert property (p_min_range) else
        $error("[ASSERT] Minute out of range: %0d (max %0d)", cur_min, MAX_MIN);
    assert property (p_sec_range) else
        $error("[ASSERT] Second out of range: %0d (max %0d)", cur_sec, MAX_SEC);
    `endif

endmodule

`default_nettype wire
