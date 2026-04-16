// =============================================================================
// Module  : control_fsm
// Project : BCD Alarm Clock — Professional RTL
// File    : rtl/control_fsm.sv
// =============================================================================
// Description:
//   Moore FSM that manages all operational modes of the alarm clock.
//   Replaces the original ad-hoc flag logic where LD_time and LD_alarm could
//   both be 1 simultaneously — causing undefined, race-prone behaviour.
//
//   By using a proper FSM, only ONE mode can be active at any clock edge.
//   Priority for simultaneous button presses (load_time beats load_alarm
//   beats alarm_detect) is encoded structurally in the next-state logic.
//
// States:
//   NORMAL      — default; clock runs, alarm comparison active
//   LOAD_TIME   — held while btn_load_time is HIGH; time_counter loads
//   LOAD_ALARM  — held while btn_load_alarm is HIGH; selected slot loads
//   ALARM_RING  — alarm is ringing; buzzer pattern active
//   SNOOZE_SET  — one-cycle transient: selected slot advances +SNOOZE_MIN
//
// Outputs (registered — Moore FSM, no glitching):
//   state         — current FSM state (exposed for testbench coverage)
//   load_time     — single-cycle: pulse to time_counter on LOAD_TIME entry
//   load_alarm[1] — single-cycle: pulse to each alarm_slot on LOAD_ALARM entry
//   snooze[1]     — single-cycle: pulse to ringing slot on SNOOZE_SET
//   alarm_ring    — HIGH in ALARM_RING state (drives buzzer_ctrl)
//
// Inputs:
//   any_trigger   — OR of both alarm slot triggers
//   timeout_flag  — auto-silence from buzzer_ctrl
//   sel_alarm     — which slot to load/snooze (0 or 1)
//   ring_slot     — which slot triggered (latched internally)
//
// =============================================================================

`default_nettype none

// State type declared as a package-free typedef for compatibility
// (No package used to keep single-file compilation easy)
typedef enum logic [2:0] {
    NORMAL     = 3'b000,
    LOAD_TIME  = 3'b001,
    LOAD_ALARM = 3'b010,
    ALARM_RING = 3'b011,
    SNOOZE_SET = 3'b100
} alarm_state_t;

module control_fsm (
    input  logic          clk,
    input  logic          reset_n,
    // Buttons (debounced)
    input  logic          btn_load_time,
    input  logic          btn_load_alarm,
    input  logic          btn_stop,
    input  logic          btn_snooze,
    // Alarm signals
    input  logic          trigger_0,     // trigger from slot 0
    input  logic          trigger_1,     // trigger from slot 1
    input  logic          timeout_flag,  // auto-silence
    input  logic          sel_alarm,     // 0=slot0, 1=slot1 for load/snooze
    // FSM outputs
    output alarm_state_t  state,
    output logic          load_time,     // single-cycle pulse
    output logic [1:0]    load_alarm,    // [0]=slot0, [1]=slot1, single-cycle
    output logic [1:0]    snooze,        // [0]=slot0, [1]=slot1, single-cycle
    output logic          alarm_ring     // level: HIGH in ALARM_RING
);

    alarm_state_t next_state;
    logic         ring_slot;    // which slot is currently ringing

    // -------------------------------------------------------------------------
    // State Register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!reset_n) state <= NORMAL;
        else          state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Ring Slot Latch (captures which alarm triggered when entering ALARM_RING)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!reset_n)
            ring_slot <= 1'b0;
        else if (state == NORMAL && (trigger_0 || trigger_1))
            ring_slot <= trigger_1;  // 1 if slot1 fired, 0 if slot0 fired
    end

    // -------------------------------------------------------------------------
    // Next-State Logic (combinational)
    // Priority: LOAD_TIME > LOAD_ALARM > ALARM_RING (natural engineering priority)
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = state;
        unique case (state)
            NORMAL: begin
                if      (btn_load_time)             next_state = LOAD_TIME;
                else if (btn_load_alarm)             next_state = LOAD_ALARM;
                else if (trigger_0 || trigger_1)    next_state = ALARM_RING;
            end
            LOAD_TIME:  if (!btn_load_time)          next_state = NORMAL;
            LOAD_ALARM: if (!btn_load_alarm)          next_state = NORMAL;
            ALARM_RING: begin
                if      (btn_stop || timeout_flag)   next_state = NORMAL;
                else if (btn_snooze)                 next_state = SNOOZE_SET;
            end
            SNOOZE_SET:                              next_state = NORMAL;
            default:                                 next_state = NORMAL;
        endcase
    end

    // -------------------------------------------------------------------------
    // Output Logic (registered Moore outputs — no combinational glitches)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            load_time  <= 1'b0;
            load_alarm <= 2'b00;
            snooze     <= 2'b00;
            alarm_ring <= 1'b0;
        end else begin
            // Default: deassert all pulses
            load_time  <= 1'b0;
            load_alarm <= 2'b00;
            snooze     <= 2'b00;
            alarm_ring <= (next_state == ALARM_RING);

            // Single-cycle pulses on state transitions
            // load_time: assert for 1 cycle when entering LOAD_TIME
            if (state == NORMAL && next_state == LOAD_TIME)
                load_time <= 1'b1;

            // load_alarm[sel_alarm]: assert for 1 cycle when entering LOAD_ALARM
            if (state == NORMAL && next_state == LOAD_ALARM)
                load_alarm[sel_alarm] <= 1'b1;

            // snooze[ring_slot]: assert for 1 cycle in SNOOZE_SET
            if (state == SNOOZE_SET)
                snooze[ring_slot] <= 1'b1;
        end
    end

endmodule

`default_nettype wire
