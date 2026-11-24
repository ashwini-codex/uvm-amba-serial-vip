// ----------------------------------------------------------------------------
// apb_mem.sv : APB3 slave memory (DUT for the APB bench)
//   * DEPTH x 32-bit words, byte address, word aligned
//   * pseudo-random 0..3 wait states per transfer (LFSR), WAIT_EN=0 disables
//   * PSLVERR on any address >= DEPTH*4 (write dropped, read returns 0)
//
// Bug switches (compile with +define+<name>) to prove the checks work:
//   BUG_APB_ALIAS  : writes to the top quarter of memory land one quarter lower
//   BUG_APB_SLVERR : PSLVERR never asserts
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

module apb_mem #(
  parameter int DEPTH   = 256,
  parameter bit WAIT_EN = 1'b1
) (
  input  logic        PCLK,
  input  logic        PRESETn,
  input  logic [31:0] PADDR,
  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic        PWRITE,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        PSLVERR
);

  localparam int AW = $clog2(DEPTH);

  logic [31:0]   mem [DEPTH];
  logic [7:0]    lfsr;
  logic [1:0]    wait_cnt;
  logic          in_range;
  logic [AW-1:0] rd_idx;
  logic [AW-1:0] wr_idx;
  logic          access_done;

  assign in_range    = (PADDR < (DEPTH * 4));
  assign rd_idx      = PADDR[AW+1:2];
  assign access_done = PSEL && PENABLE && PREADY;

`ifdef BUG_APB_ALIAS
  assign wr_idx = (rd_idx[AW-1:AW-2] == 2'b11) ? {2'b10, rd_idx[AW-3:0]} : rd_idx;
`else
  assign wr_idx = rd_idx;
`endif

  // Wait-state generator: load a count in SETUP, count down in ACCESS.
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      lfsr     <= 8'hA5;
      wait_cnt <= '0;
    end
    else begin
      lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
      if (PSEL && !PENABLE)
        wait_cnt <= WAIT_EN ? lfsr[1:0] : 2'd0;
      else if (PSEL && PENABLE && (wait_cnt != 0))
        wait_cnt <= wait_cnt - 1'b1;
    end
  end

  assign PREADY = (wait_cnt == 0);

  // Memory write
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      for (int i = 0; i < DEPTH; i++) mem[i] <= '0;
    end
    else if (access_done && PWRITE && in_range) begin
      mem[wr_idx] <= PWDATA;
    end
  end

  // Read data and error response
  assign PRDATA = (PSEL && !PWRITE && in_range) ? mem[rd_idx] : 32'h0;

`ifdef BUG_APB_SLVERR
  assign PSLVERR = 1'b0;
`else
  assign PSLVERR = access_done && !in_range;
`endif

endmodule
