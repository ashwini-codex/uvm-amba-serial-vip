// ============================================================================
// axi_mem.sv  --  AXI4 slave memory (DUT for the AXI UVM bench)
//
//   * 32-bit data, 32-bit address, 4-bit ID, 4 KB byte-addressed memory
//   * all five channels: AW, W, B, AR, R
//   * FIXED / INCR / WRAP bursts, AxLEN 0..15, AxSIZE 1/2/4 bytes
//   * WSTRB byte enables, ID echoed on BID / RID
//   * AWREADY / WREADY / ARREADY gated by a 16-bit LFSR (random back-pressure)
//   * SLVERR for any beat whose address is outside the 4 KB memory
//     (out-of-range writes are dropped, out-of-range reads return 0)
//   * one outstanding write and one outstanding read at a time; the read and
//     write paths are independent
//   * this slave accepts W beats only after the AW handshake (allowed by AXI:
//     a slave may wait for AWVALID before asserting WREADY)
//
// Bug injection (compile with +define+<name>, one at a time):
//   BUG_AXI_WRAP     write path wraps back to the start address instead of the
//                    wrap boundary
//   BUG_AXI_WSTRB    WSTRB ignored, all four byte lanes written
//   BUG_AXI_RLAST    RLAST asserted one beat early (bursts with AxLEN >= 1)
//   BUG_AXI_ID       BID / RID returned inverted instead of echoing AWID / ARID
//   BUG_AXI_RESP     OKAY returned for out-of-range addresses
//   BUG_AXI_RSTABLE  RDATA changes while RVALID is high and RREADY is low
//   BUG_AXI_FIXED    read path increments the address on FIXED bursts
// ============================================================================
`timescale 1ns/1ps

module axi_mem #(
  parameter int ADDR_W     = 32,
  parameter int DATA_W     = 32,
  parameter int ID_W       = 4,
  parameter int MEM_BYTES  = 4096,
  parameter bit RAND_READY = 1'b1     // 0: AWREADY/WREADY/ARREADY never stall
) (
  input  logic              aclk,
  input  logic              aresetn,
  // write address channel
  input  logic [ID_W-1:0]   awid,
  input  logic [ADDR_W-1:0] awaddr,
  input  logic [7:0]        awlen,
  input  logic [2:0]        awsize,
  input  logic [1:0]        awburst,
  input  logic              awvalid,
  output logic              awready,
  // write data channel
  input  logic [DATA_W-1:0]   wdata,
  input  logic [DATA_W/8-1:0] wstrb,
  input  logic                wlast,
  input  logic                wvalid,
  output logic                wready,
  // write response channel
  output logic [ID_W-1:0]   bid,
  output logic [1:0]        bresp,
  output logic              bvalid,
  input  logic              bready,
  // read address channel
  input  logic [ID_W-1:0]   arid,
  input  logic [ADDR_W-1:0] araddr,
  input  logic [7:0]        arlen,
  input  logic [2:0]        arsize,
  input  logic [1:0]        arburst,
  input  logic              arvalid,
  output logic              arready,
  // read data channel
  output logic [ID_W-1:0]   rid,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]        rresp,
  output logic              rlast,
  output logic              rvalid,
  input  logic              rready
);

  localparam int          STRB_W     = DATA_W / 8;
  localparam logic [1:0]  BURST_FIXED = 2'b00;
  localparam logic [1:0]  BURST_INCR  = 2'b01;
  localparam logic [1:0]  BURST_WRAP  = 2'b10;
  localparam logic [1:0]  RESP_OKAY   = 2'b00;
  localparam logic [1:0]  RESP_SLVERR = 2'b10;

  // --------------------------------------------------------------------------
  // storage
  // --------------------------------------------------------------------------
  logic [7:0] mem [0:MEM_BYTES-1];

  // --------------------------------------------------------------------------
  // LFSR for READY back-pressure (x^16 + x^14 + x^13 + x^11 + 1, maximal)
  // --------------------------------------------------------------------------
  logic [15:0] lfsr;
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) lfsr <= 16'hACE1;
    else          lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  // --------------------------------------------------------------------------
  // helpers
  // --------------------------------------------------------------------------
  // Next beat address. wrap_hi is the first byte past the wrap container,
  // wrap_to is where a WRAP burst continues once it reaches wrap_hi.
  function automatic logic [ADDR_W-1:0] next_addr(input logic [ADDR_W-1:0] cur,
                                                  input logic [2:0]        size,
                                                  input logic [1:0]        burst,
                                                  input logic [ADDR_W-1:0] wrap_hi,
                                                  input logic [ADDR_W-1:0] wrap_to);
    logic [ADDR_W-1:0] nbytes;
    logic [ADDR_W-1:0] nxt;
    nbytes = 1 << size;
    nxt    = (cur & ~(nbytes - 1)) + nbytes;   // aligned increment
    case (burst)
      BURST_FIXED: nxt = cur;
      BURST_WRAP : if (nxt >= wrap_hi) nxt = wrap_to;
      default    : ;                           // INCR
    endcase
    return nxt;
  endfunction

  function automatic logic [1:0] resp_for(input logic [ADDR_W-1:0] a);
`ifdef BUG_AXI_RESP
    return RESP_OKAY;
`else
    return (a >= MEM_BYTES) ? RESP_SLVERR : RESP_OKAY;
`endif
  endfunction

  // Full 32-bit word containing address a (out of range -> 0)
  function automatic logic [DATA_W-1:0] rd_word(input logic [ADDR_W-1:0] a);
    logic [DATA_W-1:0] w;
    w = '0;
    if (a < MEM_BYTES)
      for (int i = 0; i < STRB_W; i++)
        w[8*i +: 8] = mem[(a & ~(STRB_W - 1)) + i];
    return w;
  endfunction

  // Is beat number cnt the last beat of a burst of length len+1?
  function automatic logic last_flag(input logic [7:0] cnt, input logic [7:0] len);
`ifdef BUG_AXI_RLAST
    return (len == 0) ? 1'b1 : (cnt == len - 8'd1);
`else
    return (cnt == len);
`endif
  endfunction

  // ==========================================================================
  // WRITE PATH
  // ==========================================================================
  typedef enum logic [1:0] {WS_IDLE, WS_DATA, WS_RESP} wstate_t;
  wstate_t wstate;

  logic [ID_W-1:0]   w_id;
  logic [ADDR_W-1:0] w_addr, w_wrap_hi, w_wrap_to;
  logic [7:0]        w_len, w_cnt;
  logic [2:0]        w_size;
  logic [1:0]        w_burst;
  logic              w_err;

  // WRAP container for the incoming AW (only meaningful for WRAP bursts)
  logic [ADDR_W-1:0] aw_nbytes, aw_wrap_bytes, aw_wrap_lo;
  assign aw_nbytes     = 1 << awsize;
  assign aw_wrap_bytes = aw_nbytes * (awlen + 1);
  assign aw_wrap_lo    = awaddr & ~(aw_wrap_bytes - 1);

  logic [ADDR_W-1:0] w_nxt;
  logic              w_beat_oor;
  logic [STRB_W-1:0] wstrb_eff;
  logic              w_hs;

  assign w_nxt      = next_addr(w_addr, w_size, w_burst, w_wrap_hi, w_wrap_to);
  assign w_beat_oor = (w_addr >= MEM_BYTES);
  assign w_hs       = (wstate == WS_DATA) && wvalid && wready;
`ifdef BUG_AXI_WSTRB
  assign wstrb_eff  = '1;
`else
  assign wstrb_eff  = wstrb;
`endif

  assign awready = (wstate == WS_IDLE) && (!RAND_READY || lfsr[3]);
  assign wready  = (wstate == WS_DATA) && (!RAND_READY || lfsr[7]);

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      wstate    <= WS_IDLE;
      w_id      <= '0;
      w_addr    <= '0;
      w_wrap_hi <= '0;
      w_wrap_to <= '0;
      w_len     <= '0;
      w_cnt     <= '0;
      w_size    <= '0;
      w_burst   <= '0;
      w_err     <= 1'b0;
      bvalid    <= 1'b0;
      bresp     <= RESP_OKAY;
      bid       <= '0;
    end else begin
      case (wstate)
        WS_IDLE: begin
          if (awvalid && awready) begin
            w_id      <= awid;
            w_addr    <= awaddr;
            w_len     <= awlen;
            w_size    <= awsize;
            w_burst   <= awburst;
            w_cnt     <= '0;
            w_err     <= 1'b0;
            w_wrap_hi <= aw_wrap_lo + aw_wrap_bytes;
`ifdef BUG_AXI_WRAP
            w_wrap_to <= awaddr;          // BUG: wraps to start, not to boundary
`else
            w_wrap_to <= aw_wrap_lo;
`endif
            wstate    <= WS_DATA;
          end
        end
        WS_DATA: begin
          if (w_hs) begin
            w_addr <= w_nxt;
            w_cnt  <= w_cnt + 8'd1;
            if (w_beat_oor) w_err <= 1'b1;
            if (w_cnt == w_len) begin
              bvalid <= 1'b1;
`ifdef BUG_AXI_ID
              bid    <= ~w_id;
`else
              bid    <= w_id;
`endif
`ifdef BUG_AXI_RESP
              bresp  <= RESP_OKAY;
`else
              bresp  <= (w_err || w_beat_oor) ? RESP_SLVERR : RESP_OKAY;
`endif
              wstate <= WS_RESP;
            end
          end
        end
        WS_RESP: begin
          if (bready) begin
            bvalid <= 1'b0;
            wstate <= WS_IDLE;
          end
        end
        default: wstate <= WS_IDLE;
      endcase
    end
  end

  // memory write port (separate process: the only writer of mem)
  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      for (int i = 0; i < MEM_BYTES; i++) mem[i] <= 8'h00;
    end else if (w_hs && !w_beat_oor) begin
      for (int i = 0; i < STRB_W; i++)
        if (wstrb_eff[i]) mem[(w_addr & ~(STRB_W - 1)) + i] <= wdata[8*i +: 8];
    end
  end

  // ==========================================================================
  // READ PATH
  // ==========================================================================
  typedef enum logic {RS_IDLE, RS_DATA} rstate_t;
  rstate_t rstate;

  logic [ADDR_W-1:0] r_addr, r_wrap_hi, r_wrap_lo;
  logic [7:0]        r_len, r_cnt;
  logic [2:0]        r_size;
  logic [1:0]        r_burst;

  logic [ADDR_W-1:0] ar_nbytes, ar_wrap_bytes, ar_wrap_lo;
  assign ar_nbytes     = 1 << arsize;
  assign ar_wrap_bytes = ar_nbytes * (arlen + 1);
  assign ar_wrap_lo    = araddr & ~(ar_wrap_bytes - 1);

  logic [1:0]        r_burst_eff;
  logic [ADDR_W-1:0] r_nxt;
`ifdef BUG_AXI_FIXED
  assign r_burst_eff = (r_burst == BURST_FIXED) ? BURST_INCR : r_burst;
`else
  assign r_burst_eff = r_burst;
`endif
  assign r_nxt   = next_addr(r_addr, r_size, r_burst_eff, r_wrap_hi, r_wrap_lo);

  assign arready = (rstate == RS_IDLE) && (!RAND_READY || lfsr[11]);

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      rstate    <= RS_IDLE;
      r_addr    <= '0;
      r_wrap_hi <= '0;
      r_wrap_lo <= '0;
      r_len     <= '0;
      r_cnt     <= '0;
      r_size    <= '0;
      r_burst   <= '0;
      rvalid    <= 1'b0;
      rlast     <= 1'b0;
      rdata     <= '0;
      rresp     <= RESP_OKAY;
      rid       <= '0;
    end else begin
      case (rstate)
        RS_IDLE: begin
          if (arvalid && arready) begin
            r_addr    <= araddr;
            r_len     <= arlen;
            r_size    <= arsize;
            r_burst   <= arburst;
            r_cnt     <= '0;
            r_wrap_lo <= ar_wrap_lo;
            r_wrap_hi <= ar_wrap_lo + ar_wrap_bytes;
`ifdef BUG_AXI_ID
            rid       <= ~arid;
`else
            rid       <= arid;
`endif
            rvalid    <= 1'b1;
            rdata     <= rd_word(araddr);
            rresp     <= resp_for(araddr);
            rlast     <= last_flag(8'd0, arlen);
            rstate    <= RS_DATA;
          end
        end
        RS_DATA: begin
          if (rready) begin               // rvalid is always 1 in RS_DATA
            if (rlast) begin
              rvalid <= 1'b0;
              rlast  <= 1'b0;
              rstate <= RS_IDLE;
            end else begin
              r_addr <= r_nxt;
              r_cnt  <= r_cnt + 8'd1;
              rdata  <= rd_word(r_nxt);
              rresp  <= resp_for(r_nxt);
              rlast  <= last_flag(r_cnt + 8'd1, r_len);
            end
          end
`ifdef BUG_AXI_RSTABLE
          else begin
            rdata <= ~rdata;              // BUG: payload not held under stall
          end
`endif
        end
        default: rstate <= RS_IDLE;
      endcase
    end
  end

endmodule
