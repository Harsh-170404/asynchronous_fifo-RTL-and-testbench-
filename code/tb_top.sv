`timescale 1ns/1ps


// ============================================================
//  INTERFACE
// ============================================================
interface fifo_if #(parameter data_width = 8) (
    input logic wr_clk,
    input logic rd_clk
);
  logic [data_width-1:0] data_in;
  logic                  wr_en;
  logic                  wr_rst;
  logic                  fifo_full;
  logic [data_width-1:0] data_out;
  logic                  rd_en;
  logic                  rd_rst;
  logic                  fifo_empty;

  modport Tb (
    output data_in,
    output wr_en,
    output wr_rst,
    output rd_en,
    output rd_rst,
    input  fifo_full,
    input  fifo_empty,
    input  data_out,
    input  wr_clk,
    input  rd_clk
  );

  modport Dut (
    input  data_in,
    input  wr_en,
    input  wr_rst,
    input  rd_en,
    input  rd_rst,
    input  wr_clk,
    input  rd_clk,
    output fifo_full,
    output fifo_empty,
    output data_out
  );

  clocking wr_cb @(posedge wr_clk);
    default input #1step output #1;
    output data_in, wr_en, wr_rst;
    input  fifo_full;
  endclocking

  clocking rd_cb @(posedge rd_clk);
    default input #1step output #1;
    output rd_en, rd_rst;
    input  fifo_empty, data_out;
  endclocking

endinterface


// ============================================================
//  TRANSACTION
// ============================================================
class transaction;

  rand bit [7:0] data;
  rand bit       wr_en;
  rand bit       rd_en;
  bit [7:0]      expected_data;

  constraint c_at_least_one { wr_en || rd_en; }
  constraint c_no_sim       { !(wr_en && rd_en); }

  function new();
    data = 8'h00; wr_en = 0; rd_en = 0; expected_data = 8'h00;
  endfunction

  function void display(string tag = "");
    $display("[%0s] TX: wr_en=%0b  rd_en=%0b  data=0x%0h  expected=0x%0h",
             tag, wr_en, rd_en, data, expected_data);
  endfunction

  function transaction copy();
    transaction t = new();
    t.data = this.data; t.wr_en = this.wr_en;
    t.rd_en = this.rd_en; t.expected_data = this.expected_data;
    return t;
  endfunction

  function bit compare(transaction t);
    return (this.data == t.data);
  endfunction

endclass


// ============================================================
//  GENERATOR
// ============================================================
class generator;

  bit         random_mode;
  transaction user_queue[$];
  mailbox     gen2drv;
  int         num_transaction = 10;

  function new(mailbox gen2drv);
    this.gen2drv     = gen2drv;
    this.random_mode = 1;
  endfunction

  task add_user_transaction(transaction tr);
    user_queue.push_back(tr);
  endtask

  task run();
    transaction tr;
    if (random_mode) begin
      $display("[GEN] Random mode - %0d transactions", num_transaction);
      repeat (num_transaction) begin
        tr = new();
        assert (tr.randomize() with { wr_en || rd_en; })
          else $fatal(1, "[GEN] Randomization failed!");
        tr.display("GEN");
        gen2drv.put(tr);
      end
    end else begin
      $display("[GEN] User-defined mode - %0d transactions", user_queue.size());
      foreach (user_queue[i]) begin
        user_queue[i].display("GEN");
        gen2drv.put(user_queue[i]);
      end
    end
    $display("[GEN] Done.");
  endtask

endclass


// ============================================================
//  DRIVER
// ============================================================
class driver;

  virtual fifo_if.Tb vif;
  mailbox            gen2drv;

  function new(virtual fifo_if.Tb vif, mailbox gen2drv);
    this.vif = vif; this.gen2drv = gen2drv;
  endfunction

  task reset();
    $display("[DRV] Applying Reset");
    vif.wr_rst  <= 1;  vif.rd_rst  <= 1;
    vif.wr_en   <= 0;  vif.rd_en   <= 0;
    vif.data_in <= 0;
    repeat (5) @(posedge vif.wr_clk);
    vif.wr_rst <= 0;   vif.rd_rst <= 0;
    $display("[DRV] Reset released");
  endtask

task run();
  transaction tr;

  // Wait until reset is deasserted in both domains
  wait (!vif.wr_rst && !vif.rd_rst);

  forever begin
    // Get next transaction
    gen2drv.get(tr);

    fork

      // ================= WRITE =================
      if (tr.wr_en) begin
        // Align to write clocking block
        @(vif.wr_cb);

        // Assertion (reset-aware)
        assert (vif.wr_rst || !vif.wr_cb.fifo_full)
          else $error("[DRV][%0t] Write when FIFO FULL", $time);

        // Drive write
        vif.wr_cb.data_in <= tr.data;
        vif.wr_cb.wr_en   <= 1;

        // Hold for one cycle
        @(vif.wr_cb);
        vif.wr_cb.wr_en <= 0;

        $display("[DRV][%0t] WRITE data=0x%0h full=%0b",
                  $time, tr.data, vif.wr_cb.fifo_full);
      end

      // ================= READ =================
      if (tr.rd_en) begin
        // Align to read clocking block
        @(vif.rd_cb);

        // Assertion (reset-aware)
        assert (vif.rd_rst || !vif.rd_cb.fifo_empty)
          else $error("[DRV][%0t] Read when FIFO EMPTY", $time);

        // Drive read
        vif.rd_cb.rd_en <= 1;

        // Hold for one cycle
        @(vif.rd_cb);
        vif.rd_cb.rd_en <= 0;

        $display("[DRV][%0t] READ triggered empty=%0b",
                  $time, vif.rd_cb.fifo_empty);
      end

    join

  end
endtask

endclass


// ============================================================
//  MONITOR
// ============================================================
class monitor #(parameter data_width = 8);

  virtual fifo_if.Tb vif;
  mailbox            mon2scb;

  function new(virtual fifo_if.Tb vif, mailbox mon2scb);
    this.vif = vif; this.mon2scb = mon2scb;
  endfunction

  task run();
    fork monitor_write(); monitor_read(); join
  endtask

task monitor_write();
  transaction tr;

  forever begin
    @(vif.wr_cb);

    if (!vif.wr_rst && vif.wr_cb.wr_en && !vif.wr_cb.fifo_full) begin
      tr = new();
      tr.wr_en = 1;
      tr.data  = vif.wr_cb.data_in;

      mon2scb.put(tr.copy());

      $display("[MON][%0t] WRITE data=0x%0h",
                $time, tr.data);
    end
  end
endtask

task monitor_read();
  transaction tr;

  forever begin
    @(vif.rd_cb);

    if (!vif.rd_rst && vif.rd_cb.rd_en && !vif.rd_cb.fifo_empty) begin
      @(vif.rd_cb); // latency

      tr = new();
      tr.rd_en = 1;
      tr.data  = vif.rd_cb.data_out;

      mon2scb.put(tr.copy());

      $display("[MON][%0t] READ data=0x%0h",
                $time, tr.data);
    end
  end
endtask

endclass


// ============================================================
//  SCOREBOARD
// ============================================================
class scoreboard #(parameter data_width = 8);

  bit [data_width-1:0] expected_q[$];
  mailbox              mon2scb;
  int                  pass_count = 0;
  int                  fail_count = 0;
  int                  warn_count = 0;

  function new(mailbox mon2scb);
    this.mon2scb = mon2scb;
  endfunction

  task run();
    transaction tr;
    forever begin
      mon2scb.get(tr);
      if (tr.wr_en && !tr.rd_en) begin
        expected_q.push_back(tr.data);
        $display("[SCB] Write saved: 0x%0h  (depth=%0d)", tr.data, expected_q.size());
      end else if (tr.rd_en && !tr.wr_en) begin
        if (expected_q.size() > 0) begin
          bit [data_width-1:0] exp_val = expected_q.pop_front();
          if (tr.data !== exp_val) begin
            $display("[SCB][FAIL] Expected=0x%0h  Got=0x%0h", exp_val, tr.data);
            fail_count++;
          end else begin
            $display("[SCB][PASS] Read matched: 0x%0h", tr.data);
            pass_count++;
          end
        end else begin
          $display("[SCB][WARN] Underflow: read with no expected value");
          warn_count++;
        end
      end
    end
  endtask

  function void report();
    $display("─────────────────────────────────────");
    $display(" SCOREBOARD SUMMARY");
    $display("   PASS : %0d", pass_count);
    $display("   FAIL : %0d", fail_count);
    $display("   WARN : %0d", warn_count);
    $display("   STATUS: %s", (fail_count == 0) ? "** ALL TESTS PASSED **"
                                                 : "!! FAILURES DETECTED !!");
    $display("─────────────────────────────────────");
  endfunction

endclass


// ============================================================
//  ENVIRONMENT  (9 test tasks)
// ============================================================
class environment #(parameter data_width = 8,
                    parameter addr_width  = 4);

  generator               gen;
  driver                  drv;
  monitor  #(data_width)  mon;
  scoreboard#(data_width) scb;
  mailbox gen2drv, mon2scb;
  virtual fifo_if.Tb vif;

  localparam int FIFO_DEPTH = (1 << addr_width);

  function new(virtual fifo_if.Tb vif);
    this.vif = vif;
  endfunction

  function void build();
    gen2drv = new(); mon2scb = new();
    gen = new(gen2drv); drv = new(vif, gen2drv);
    mon = new(vif, mon2scb); scb = new(mon2scb);
  endfunction

  task start_monitor();
    fork mon.run(); scb.run(); join_none
  endtask

  task apply_reset(int cycles = 5);
    drv.reset();
    repeat (cycles) @(posedge vif.wr_clk);
  endtask

  // ── TEST 1: Reset Test ──────────────────────────────────
  task test_reset();
    $display("\n===== TEST 1: Reset Test =====");
    vif.wr_en <= 0; vif.rd_en <= 0; vif.data_in <= 0;
    vif.wr_rst <= 1; vif.rd_rst <= 1;
    repeat (8) @(posedge vif.wr_clk);
    assert (vif.fifo_empty === 1) else $error("[RESET] FAIL: fifo_empty not asserted during reset");
    assert (vif.fifo_full  === 0) else $error("[RESET] FAIL: fifo_full asserted during reset");
    vif.wr_rst <= 0; vif.rd_rst <= 0;
    repeat (4) @(posedge vif.wr_clk);
    assert (vif.fifo_empty === 1) else $error("[RESET] FAIL: fifo_empty not asserted after reset");
    $display("[RESET] PASS: FIFO empty after reset.");
  endtask

  // ── TEST 2: One Write then Read ─────────────────────────
  task test_one_write_read();
    transaction tr;
    $display("\n===== TEST 2: One Write then Read =====");
    apply_reset();
    gen.user_queue = {};
    tr = new(); tr.wr_en = 1; tr.rd_en = 0; tr.data = 8'hA5;
    gen.add_user_transaction(tr);
    tr = new(); tr.wr_en = 0; tr.rd_en = 1;
    gen.add_user_transaction(tr);
    gen.random_mode = 0;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (20) @(posedge vif.wr_clk);
  endtask

  // ── TEST 3: Multiple Write and Read ─────────────────────
  task test_multiple_write_read(int n = 8);
    transaction tr;
    $display("\n===== TEST 3: Multiple Write and Read (n=%0d) =====", n);
    apply_reset();
    gen.user_queue = {};
    for (int i = 0; i < n; i++) begin
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = $urandom_range(0, 255);
      gen.add_user_transaction(tr);
    end
    for (int i = 0; i < n; i++) begin
      tr = new(); tr.wr_en = 0; tr.rd_en = 1;
      gen.add_user_transaction(tr);
    end
    gen.random_mode = 0;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (50) @(posedge vif.wr_clk);
  endtask

  // ── TEST 4: Overflow Condition ───────────────────────────
  task test_overflow();
    transaction tr;
    $display("\n===== TEST 4: Overflow Condition =====");
    apply_reset();
    gen.user_queue = {};
    for (int i = 0; i < FIFO_DEPTH + 4; i++) begin
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = i[7:0];
      gen.add_user_transaction(tr);
    end
    gen.random_mode = 0;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (20) @(posedge vif.wr_clk);
    if (vif.fifo_full === 1) $display("[OVERFLOW] PASS: fifo_full asserted.");
    else                     $error  ("[OVERFLOW] FAIL: fifo_full NOT asserted.");
  endtask

  // ── TEST 5: Underflow Condition ──────────────────────────
  task test_underflow();
    transaction tr;
    $display("\n===== TEST 5: Underflow Condition =====");
    apply_reset();
    gen.user_queue = {};
    for (int i = 0; i < 4; i++) begin
      tr = new(); tr.wr_en = 0; tr.rd_en = 1;
      gen.add_user_transaction(tr);
    end
    gen.random_mode = 0;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (20) @(posedge vif.rd_clk);
    if (vif.fifo_empty === 1) $display("[UNDERFLOW] PASS: FIFO remains empty.");
    else                      $error  ("[UNDERFLOW] FAIL: fifo_empty NOT asserted.");
  endtask

  // ── TEST 6: Random Write and Read ───────────────────────
  task test_random(int n = 20);
    $display("\n===== TEST 6: Random Write and Read (n=%0d) =====", n);
    apply_reset();
    gen.random_mode     = 1;
    gen.num_transaction = n;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (60) @(posedge vif.wr_clk);
  endtask

  // ── TEST 7: Wrap-Around Test ─────────────────────────────
  task test_wrap_around();
    transaction tr;
    $display("\n===== TEST 7: Wrap-Around =====");
    apply_reset();
    gen.user_queue = {};
    for (int i = 0; i < FIFO_DEPTH; i++) begin   // fill
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = i[7:0]; gen.add_user_transaction(tr);
    end
    for (int i = 0; i < FIFO_DEPTH; i++) begin   // drain
      tr = new(); tr.wr_en = 0; tr.rd_en = 1;
      gen.add_user_transaction(tr);
    end
    for (int i = 0; i < FIFO_DEPTH; i++) begin   // re-fill (ptr wraps)
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = (8'hF0 + i[7:0]); gen.add_user_transaction(tr);
    end
    for (int i = 0; i < FIFO_DEPTH; i++) begin   // re-drain
      tr = new(); tr.wr_en = 0; tr.rd_en = 1;
      gen.add_user_transaction(tr);
    end
    gen.random_mode = 0;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (80) @(posedge vif.wr_clk);
    $display("[WRAP-AROUND] PASS: complete.");
  endtask

  // ── TEST 8: Apply Reset in the Middle ───────────────────
  task test_reset_in_middle();
    transaction tr;
    $display("\n===== TEST 8: Reset in Middle of Operation =====");
    apply_reset();
    gen.user_queue = {};
    for (int i = 0; i < FIFO_DEPTH/2; i++) begin
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = i[7:0]; gen.add_user_transaction(tr);
    end
    gen.random_mode = 0;
    start_monitor();
    fork drv.run(); join_none
    gen.run();
    repeat (10) @(posedge vif.wr_clk);
    // mid-operation reset
    $display("[RESET-MID] Asserting mid-operation reset");
    vif.wr_rst <= 1; vif.rd_rst <= 1;
    repeat (5) @(posedge vif.wr_clk);
    vif.wr_rst <= 0; vif.rd_rst <= 0;
    repeat (4) @(posedge vif.wr_clk);
    if (vif.fifo_empty === 1) $display("[RESET-MID] PASS: FIFO empty after mid-reset.");
    else                      $error  ("[RESET-MID] FAIL: fifo_empty not asserted.");
    // resume after reset
    gen.user_queue = {};
    for (int i = 0; i < 4; i++) begin
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = (8'hAA + i[7:0]); gen.add_user_transaction(tr);
    end
    for (int i = 0; i < 4; i++) begin
      tr = new(); tr.wr_en = 0; tr.rd_en = 1;
      gen.add_user_transaction(tr);
    end
    gen.run();
    repeat (30) @(posedge vif.wr_clk);
  endtask

  // ── TEST 9: Simultaneous Write and Read ─────────────────
  task test_simultaneous();
    transaction tr;
    $display("\n===== TEST 9: Simultaneous Write and Read =====");
    apply_reset();
    // pre-fill half
    gen.user_queue = {};
    for (int i = 0; i < FIFO_DEPTH/2; i++) begin
      tr = new(); tr.wr_en = 1; tr.rd_en = 0;
      tr.data = i[7:0]; gen.add_user_transaction(tr);
    end
    gen.random_mode = 0;
    fork drv.run(); join_none
    gen.run();
    repeat (20) @(posedge vif.wr_clk);
    // simultaneous wr+rd
    gen.user_queue = {};
    for (int i = 0; i < 8; i++) begin
      tr = new(); tr.wr_en = 1; tr.rd_en = 1;
      tr.data = (8'h10 + i[7:0]);
      gen.add_user_transaction(tr);
    end
    start_monitor();
    gen.run();
    repeat (50) @(posedge vif.wr_clk);
    $display("[SIMUL] Simultaneous write and read complete.");
  endtask

  // ── run_all ──────────────────────────────────────────────
  task run_all();
    build(); test_reset();
    build(); test_one_write_read();
    build(); test_multiple_write_read(8);
    build(); test_overflow();
    build(); test_underflow();
    build(); test_random(20);
    build(); test_wrap_around();
    build(); test_reset_in_middle();
    build(); test_simultaneous();
    scb.report();
  endtask

endclass


// ============================================================
//  TB_TOP
// ============================================================
module tb_top;

  parameter int DATA_WIDTH = 8;
  parameter int ADDR_WIDTH = 4;

  logic wr_clk = 0;
  logic rd_clk = 0;
  always #5  wr_clk = ~wr_clk;   // 100 MHz
  always #7  rd_clk = ~rd_clk;   //  71 MHz (async)

  fifo_if #(DATA_WIDTH) intf (
    .wr_clk (wr_clk),
    .rd_clk (rd_clk)
  );

  async_fifo #(
    .data_width (DATA_WIDTH),
    .addr_width (ADDR_WIDTH)
  ) dut (
    .data_in    (intf.data_in),
    .wr_en      (intf.wr_en),
    .wr_clk     (intf.wr_clk),
    .wr_rst     (intf.wr_rst),
    .fifo_full  (intf.fifo_full),
    .data_out   (intf.data_out),
    .rd_en      (intf.rd_en),
    .rd_clk     (intf.rd_clk),
    .rd_rst     (intf.rd_rst),
    .fifo_empty (intf.fifo_empty)
  );

  environment #(DATA_WIDTH, ADDR_WIDTH) env;

  initial begin
    $dumpfile("fifo.vcd");
    $dumpvars(0, tb_top);
  end

  initial begin
    $display("======================================");
    $display("  Async FIFO Testbench  START");
    $display("======================================");
    env = new(intf.Tb);
    env.run_all();
    $display("======================================");
    $display("  Async FIFO Testbench  DONE");
    $display("======================================");
    $finish;
  end

  initial begin
    #500_000;
    $display("[TB] TIMEOUT");
    $finish;
  end

endmodule
