// =============================================================================
// alarm_clock_tb.sv — Comprehensive SystemVerilog Testbench
// =============================================================================
//
// Test coverage (6 test cases + waveform dump):
//   TC1  Reset behaviour — all outputs zero after reset
//   TC2  Invalid BCD input clamping (29 hours, 75 minutes → clamped to 23, 59)
//   TC3  Normal timekeeping — seconds roll over correctly
//   TC4  23:59:50 → 00:00:00 midnight rollover
//   TC5  Alarm trigger (edge-triggered — fires once at HH:MM:00)
//   TC6  STOP alarm — alarm_out deasserts after btn_stop pulse
//   TC7  Snooze — alarm time advances +5 minutes
//   TC8  Simultaneous load_time + load_alarm (FSM resolves via priority)
//   TC9  Alarm does NOT re-trigger within same minute after STOP
//
// Simulation clock: 10 Hz (CLK_DIV=10) — each second = 10 clock cycles.
// Total sim time: ~= 15 simulated minutes (fast).
// =============================================================================

`timescale 1ns / 1ps
`define SIMULATION   // enable assertions inside DUT

module alarm_clock_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam real CLK_PERIOD_NS = 100.0;   // 10 Hz → 100 ns period
    localparam int  CLK_DIV       = 10;       // 10 cycles per second (sim speed)

    // -------------------------------------------------------------------------
    // Signal declarations
    // -------------------------------------------------------------------------
    logic        clk;
    logic        reset_n;
    logic        btn_load_time, btn_load_alarm;
    logic        btn_alarm_en, btn_stop, btn_snooze;
    logic [1:0]  H_in1;
    logic [3:0]  H_in0, M_in1, M_in0;

    logic [1:0]  H_out1;
    logic [3:0]  H_out0, M_out1, M_out0, S_out1, S_out0;
    logic        alarm_out;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    alarm_clock_sv #(
        .CLK_DIV (CLK_DIV),
        .MAX_HOUR(23),
        .MAX_MIN (59),
        .MAX_SEC (59)
    ) dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .btn_load_time  (btn_load_time),
        .btn_load_alarm (btn_load_alarm),
        .btn_alarm_en   (btn_alarm_en),
        .btn_stop       (btn_stop),
        .btn_snooze     (btn_snooze),
        .H_in1          (H_in1),
        .H_in0          (H_in0),
        .M_in1          (M_in1),
        .M_in0          (M_in0),
        .H_out1         (H_out1),
        .H_out0         (H_out0),
        .M_out1         (M_out1),
        .M_out0         (M_out0),
        .S_out1         (S_out1),
        .S_out0         (S_out0),
        .alarm_out      (alarm_out)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

    // -------------------------------------------------------------------------
    // Waveform Dump (view in GTKWave or ModelSim)
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("alarm_clock.vcd");
        $dumpvars(0, alarm_clock_tb);
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------

    // Advance N simulated seconds (N * CLK_DIV clock edges)
    task automatic tick(input int unsigned n_seconds);
        repeat (n_seconds * CLK_DIV) @(posedge clk);
    endtask

    // Apply synchronous reset
    task automatic do_reset();
        reset_n = 1'b0;
        tick(2);
        reset_n = 1'b1;
        @(posedge clk);
    endtask

    // Load time — hold btn_load_time for 1 second
    task automatic load_time(
        input logic [1:0] h1, input logic [3:0] h0,
        input logic [3:0] m1, input logic [3:0] m0
    );
        H_in1 = h1; H_in0 = h0; M_in1 = m1; M_in0 = m0;
        btn_load_time = 1'b1;
        tick(1);
        btn_load_time = 1'b0;
        @(posedge clk);
    endtask

    // Load alarm — hold btn_load_alarm for 1 second
    task automatic load_alarm(
        input logic [1:0] h1, input logic [3:0] h0,
        input logic [3:0] m1, input logic [3:0] m0
    );
        H_in1 = h1; H_in0 = h0; M_in1 = m1; M_in0 = m0;
        btn_load_alarm = 1'b1;
        tick(1);
        btn_load_alarm = 1'b0;
        @(posedge clk);
    endtask

    // Wait for alarm to ring with a timeout (prevents infinite hang)
    task automatic wait_alarm_timeout(input int unsigned timeout_sec);
        int unsigned waited;
        waited = 0;
        while (!alarm_out && waited < timeout_sec * CLK_DIV) begin
            @(posedge clk);
            waited++;
        end
        if (!alarm_out)
            $error("[TIMEOUT] Alarm never triggered after %0d seconds", timeout_sec);
    endtask

    // Convenience display of current time
    task automatic show_time(input string label);
        $display("[%0t] %s  Current: %0d%0d:%0d%0d:%0d%0d  alarm_out=%b",
                 $time, label,
                 H_out1, H_out0, M_out1, M_out0, S_out1, S_out0,
                 alarm_out);
    endtask

    // -------------------------------------------------------------------------
    // Test Variables
    // -------------------------------------------------------------------------
    int unsigned test_num;
    int unsigned pass_cnt, fail_cnt;

    task automatic check(
        input string name,
        input logic  cond
    );
        if (cond) begin
            $display("  [PASS] %s", name);
            pass_cnt++;
        end else begin
            $error("  [FAIL] %s", name);
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // Initialise all inputs
        {btn_load_time, btn_load_alarm, btn_alarm_en, btn_stop, btn_snooze} = '0;
        {H_in1, H_in0, M_in1, M_in0} = '0;
        reset_n  = 1'b1;
        pass_cnt = 0;
        fail_cnt = 0;

        // =====================================================================
        // TC1 — Reset Behaviour
        // =====================================================================
        $display("\n=== TC1: Reset Behaviour ===");
        do_reset();
        tick(1);
        check("Hour  = 0 after reset", H_out1 == 0 && H_out0 == 0);
        check("Min   = 0 after reset", M_out1 == 0 && M_out0 == 0);
        check("Sec   = 0 after reset", S_out1 == 0 && S_out0 == 0);
        check("Alarm = 0 after reset", alarm_out == 1'b0);

        // =====================================================================
        // TC2 — Invalid BCD Input Clamping
        // =====================================================================
        $display("\n=== TC2: Invalid BCD Input Clamping ===");
        do_reset();
        load_time(2'b10, 4'd9, 4'd7, 4'd5);   // 29 hours, 75 minutes (INVALID)
        tick(1);
        // Should be clamped to 23:59
        check("Invalid hour clamped to 23",
              H_out1 == 2'd2 && H_out0 == 4'd3);
        check("Invalid min  clamped to 59",
              M_out1 == 4'd5 && M_out0 == 4'd9);

        // =====================================================================
        // TC3 — Normal Timekeeping (seconds increment, roll at 59)
        // =====================================================================
        $display("\n=== TC3: Normal Timekeeping ===");
        do_reset();
        load_time(2'b0, 4'd1, 4'd0, 4'd0);    // set 01:00:00
        tick(5);
        show_time("after 5 sec");
        check("Second = 5 after 5 ticks",
              S_out1 == 4'd0 && S_out0 == 4'd5);

        tick(55);
        show_time("after 60 sec total");
        check("Minute rolled from 00 to 01",
              M_out1 == 4'd0 && M_out0 == 4'd1);
        check("Second reset to 00 on rollover",
              S_out1 == 4'd0 && S_out0 == 4'd0);

        // =====================================================================
        // TC4 — Midnight Rollover (23:59:50 → 00:00:00)
        // =====================================================================
        $display("\n=== TC4: Midnight Rollover ===");
        do_reset();
        load_time(2'b10, 4'd3, 4'd5, 4'd9);   // set 23:59:00
        tick(65);                               // advance 65 seconds beyond 23:59:00
        show_time("after 65 sec from 23:59:00");
        check("Hour rolled to 00",
              H_out1 == 2'd0 && H_out0 == 4'd0);
        check("Minute rolled to 00",
              M_out1 == 4'd0 && M_out0 == 4'd0);
        check("Second = 05",
              S_out1 == 4'd0 && S_out0 == 4'd5);

        // =====================================================================
        // TC5 — Alarm Trigger (edge-triggered, single-shot at HH:MM:00)
        // =====================================================================
        $display("\n=== TC5: Alarm Edge-Triggered Trigger ===");
        do_reset();
        load_time(2'b0, 4'd1, 4'd0, 4'd0);    // time  = 01:00:00
        load_alarm(2'b0, 4'd1, 4'd0, 4'd1);   // alarm = 01:01:00
        btn_alarm_en = 1'b1;
        wait_alarm_timeout(70);                 // should fire within 60 + margin
        check("Alarm triggered at 01:01:00", alarm_out == 1'b1);
        show_time("at alarm trigger");

        // =====================================================================
        // TC6 — STOP Alarm
        // =====================================================================
        $display("\n=== TC6: STOP Alarm ===");
        btn_stop = 1'b1; tick(1); btn_stop = 1'b0;
        @(posedge clk);
        check("Alarm deasserted after STOP", alarm_out == 1'b0);

        // =====================================================================
        // TC7 — Alarm Does NOT Re-Trigger Within Same Minute After STOP
        // =====================================================================
        $display("\n=== TC7: No Re-Trigger Within Same Minute ===");
        tick(30);   // advance 30 more seconds — still within alarm minute
        check("Alarm stays LOW within same minute",
              alarm_out == 1'b0);

        // =====================================================================
        // TC8 — Snooze (+5 minutes)
        // =====================================================================
        $display("\n=== TC8: Snooze ===");
        do_reset();
        load_time(2'b0, 4'd2, 4'd0, 4'd0);     // time  = 02:00:00
        load_alarm(2'b0, 4'd2, 4'd0, 4'd1);    // alarm = 02:01:00
        btn_alarm_en = 1'b1;
        wait_alarm_timeout(70);                  // wait for first ring
        check("First alarm ring at 02:01:00", alarm_out == 1'b1);
        btn_snooze = 1'b1; tick(1); btn_snooze = 1'b0; // hit snooze
        @(posedge clk);
        check("Alarm cleared after snooze", alarm_out == 1'b0);
        // Now alarm should fire at 02:06:00 (5 min later)
        wait_alarm_timeout(310);                 // 5 min = 300 sec + margin
        check("Snooze alarm triggered at 02:06:00", alarm_out == 1'b1);
        btn_stop = 1'b1; tick(1); btn_stop = 1'b0;

        // =====================================================================
        // TC9 — FSM Priority: load_time takes precedence if load_alarm also HIGH
        // =====================================================================
        $display("\n=== TC9: FSM Priority (simultaneous inputs) ===");
        do_reset();
        // Both buttons high — FSM enters LOAD_TIME first (btn_load_time has
        // priority in our comb logic). btn_load_alarm is ignored this cycle.
        H_in1 = 2'b0; H_in0 = 4'd5; M_in1 = 4'd3; M_in0 = 4'd0;
        btn_load_time  = 1'b1;
        btn_load_alarm = 1'b1;
        tick(1);
        btn_load_time  = 1'b0;
        btn_load_alarm = 1'b0;
        @(posedge clk);
        check("Simultaneous inputs: time loaded without undefined state",
              H_out1 == 2'd0 && H_out0 == 4'd5);

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n========================================");
        $display(" TEST RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("========================================");
        if (fail_cnt == 0)
            $display(" ALL TESTS PASSED ");
        else
            $display(" SOME TESTS FAILED — review errors above");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Simulation Watchdog (global timeout — prevents infinite hang)
    // -------------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD_NS * CLK_DIV * 3600 * 1.0);   // 1 simulated hour max
        $display("[WATCHDOG] Simulation exceeded 1 simulated hour — aborting");
        $finish;
    end

endmodule
