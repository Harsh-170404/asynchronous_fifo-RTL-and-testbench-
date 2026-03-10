`timescale 1ns/1ps


// ============================================================
//  1.  SYNCHRONIZER
// ============================================================
module fifo_sync #(
    parameter int WIDTH = 5
)(
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);
  logic [WIDTH-1:0] stage1;
  always_ff @(posedge clk) begin
    if (rst) begin
      stage1 <= '0;
      q      <= '0;
    end else begin
      stage1 <= d;
      q      <= stage1;
    end
  end
endmodule


// ============================================================
//  2.  WRITE CONTROL
// ============================================================
module fifo_write_ctrl #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  wr_clk,
    input  logic                  wr_rst,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH:0]   rd_ptr_gray_sync,
    output logic [ADDR_WIDTH-1:0] wr_addr,
    output logic [ADDR_WIDTH:0]   wr_ptr_gray,
    output logic                  fifo_full
);
  localparam int PTR_W = ADDR_WIDTH + 1;
  logic [PTR_W-1:0] wr_ptr_bin;

  function automatic logic [PTR_W-1:0] b2g(input logic [PTR_W-1:0] b);
    return (b >> 1) ^ b;
  endfunction

  always_ff @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_ptr_bin  <= '0;
      wr_ptr_gray <= '0;
    end else if (wr_en && !fifo_full) begin
      wr_ptr_bin  <= wr_ptr_bin + 1'b1;
      wr_ptr_gray <= b2g(wr_ptr_bin + 1'b1);
    end
  end

  assign wr_addr   = wr_ptr_bin[ADDR_WIDTH-1:0];
  assign fifo_full = (wr_ptr_gray == {~rd_ptr_gray_sync[PTR_W-1:PTR_W-2],
                                        rd_ptr_gray_sync[PTR_W-3:0]});
endmodule


// ============================================================
//  3.  READ CONTROL
// ============================================================
module fifo_read_ctrl #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  rd_clk,
    input  logic                  rd_rst,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH:0]   wr_ptr_gray_sync,
    output logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [ADDR_WIDTH:0]   rd_ptr_gray,
    output logic                  fifo_empty
);
  localparam int PTR_W = ADDR_WIDTH + 1;
  logic [PTR_W-1:0] rd_ptr_bin;

  function automatic logic [PTR_W-1:0] b2g(input logic [PTR_W-1:0] b);
    return (b >> 1) ^ b;
  endfunction

  always_ff @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_ptr_bin  <= '0;
      rd_ptr_gray <= '0;
    end else if (rd_en && !fifo_empty) begin
      rd_ptr_bin  <= rd_ptr_bin + 1'b1;
      rd_ptr_gray <= b2g(rd_ptr_bin + 1'b1);
    end
  end

  assign rd_addr    = rd_ptr_bin[ADDR_WIDTH-1:0];
  assign fifo_empty = (rd_ptr_gray == wr_ptr_gray_sync);
endmodule


// ============================================================
//  4.  STATUS CALCULATOR  
// ============================================================
module fifo_status_calc #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic [ADDR_WIDTH:0] wr_ptr_gray,
    input  logic [ADDR_WIDTH:0] rd_ptr_gray_sync_wr,
    input  logic [ADDR_WIDTH:0] rd_ptr_gray,
    input  logic [ADDR_WIDTH:0] wr_ptr_gray_sync_rd,
    output logic                full_comb,
    output logic                empty_comb
);
  localparam int PTR_W = ADDR_WIDTH + 1;
  assign full_comb  = (wr_ptr_gray == {~rd_ptr_gray_sync_wr[PTR_W-1:PTR_W-2],
                                         rd_ptr_gray_sync_wr[PTR_W-3:0]});
  assign empty_comb = (rd_ptr_gray == wr_ptr_gray_sync_rd);
endmodule


// ============================================================
//  5.  DUAL-PORT RAM
// ============================================================
module fifo_mem #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                   wr_clk,
    input  logic                   wr_en,
    input  logic [ADDR_WIDTH-1:0]  wr_addr,
    input  logic [DATA_WIDTH-1:0]  data_in,
    input  logic                   rd_clk,
    input  logic                   rd_en,
    input  logic [ADDR_WIDTH-1:0]  rd_addr,
    output logic [DATA_WIDTH-1:0]  data_out
);
  localparam int DEPTH = (1 << ADDR_WIDTH);
  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  always_ff @(posedge wr_clk)
    if (wr_en) mem[wr_addr] <= data_in;

  always_ff @(posedge rd_clk)
    if (rd_en) data_out <= mem[rd_addr];
endmodule


// ============================================================
//  6.  ASYNC FIFO 
// ============================================================
module async_fifo #(
    parameter int data_width = 8,
    parameter int addr_width = 4
)(
    // Write domain
    input  logic [data_width-1:0] data_in,
    input  logic                  wr_en,
    input  logic                  wr_clk,
    input  logic                  wr_rst,
    output logic                  fifo_full,

    // Read domain
    output logic [data_width-1:0] data_out,
    input  logic                  rd_en,
    input  logic                  rd_clk,
    input  logic                  rd_rst,
    output logic                  fifo_empty
);

  localparam int PTR_W = addr_width + 1;

  logic [addr_width-1:0] wr_addr;
  logic [addr_width-1:0] rd_addr;
  logic [PTR_W-1:0]      wr_ptr_gray;
  logic [PTR_W-1:0]      rd_ptr_gray;
  logic [PTR_W-1:0]      wr_ptr_gray_sync_rd;
  logic [PTR_W-1:0]      rd_ptr_gray_sync_wr;
  logic                  full_comb;
  logic                  empty_comb;

  // Inst 1a - write Gray → read domain
  fifo_sync #(.WIDTH(PTR_W)) u_sync_wr2rd (
    .clk (rd_clk), .rst (rd_rst),
    .d   (wr_ptr_gray), .q (wr_ptr_gray_sync_rd)
  );

  // Inst 1b - read Gray → write domain
  fifo_sync #(.WIDTH(PTR_W)) u_sync_rd2wr (
    .clk (wr_clk), .rst (wr_rst),
    .d   (rd_ptr_gray), .q (rd_ptr_gray_sync_wr)
  );

  // Inst 2 - write control
  fifo_write_ctrl #(.ADDR_WIDTH(addr_width)) u_wr_ctrl (
    .wr_clk           (wr_clk),
    .wr_rst           (wr_rst),
    .wr_en            (wr_en),
    .rd_ptr_gray_sync (rd_ptr_gray_sync_wr),
    .wr_addr          (wr_addr),
    .wr_ptr_gray      (wr_ptr_gray),
    .fifo_full        (fifo_full)
  );

  // Inst 3 - read control
  fifo_read_ctrl #(.ADDR_WIDTH(addr_width)) u_rd_ctrl (
    .rd_clk           (rd_clk),
    .rd_rst           (rd_rst),
    .rd_en            (rd_en),
    .wr_ptr_gray_sync (wr_ptr_gray_sync_rd),
    .rd_addr          (rd_addr),
    .rd_ptr_gray      (rd_ptr_gray),
    .fifo_empty       (fifo_empty)
  );

  // Inst 4 - status calculator
  fifo_status_calc #(.ADDR_WIDTH(addr_width)) u_status (
    .wr_ptr_gray         (wr_ptr_gray),
    .rd_ptr_gray_sync_wr (rd_ptr_gray_sync_wr),
    .rd_ptr_gray         (rd_ptr_gray),
    .wr_ptr_gray_sync_rd (wr_ptr_gray_sync_rd),
    .full_comb           (full_comb),
    .empty_comb          (empty_comb)
  );

  // Inst 5 - dual-port RAM
  fifo_mem #(.DATA_WIDTH(data_width), .ADDR_WIDTH(addr_width)) u_mem (
    .wr_clk   (wr_clk),
    .wr_en    (wr_en && !fifo_full),
    .wr_addr  (wr_addr),
    .data_in  (data_in),
    .rd_clk   (rd_clk),
    .rd_en    (rd_en && !fifo_empty),
    .rd_addr  (rd_addr),
    .data_out (data_out)
  );

endmodule
