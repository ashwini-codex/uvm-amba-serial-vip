// ============================================================================
// axi_if.sv  --  AXI4 interface: signals, driver/monitor clocking blocks, SVA
//
// Assertion failures are reported through `uvm_error so they count toward
// the UVM error total and fail the test.
//
// The burst trackers used by the WLAST/RLAST/B-ordering checks assume one
// outstanding write and one outstanding read at a time (true for this master
// and for axi_mem).
// ============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"

interface axi_if (input logic aclk, input logic aresetn);
  import uvm_pkg::*;

  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;
  localparam int ID_W   = 4;
  localparam int STRB_W = DATA_W / 8;

  // write address channel
  logic [ID_W-1:0]   awid;
  logic [ADDR_W-1:0] awaddr;
  logic [7:0]        awlen;
  logic [2:0]        awsize;
  logic [1:0]        awburst;
  logic              awvalid;
  logic              awready;
  // write data channel
  logic [DATA_W-1:0] wdata;
  logic [STRB_W-1:0] wstrb;
  logic              wlast;
  logic              wvalid;
  logic              wready;
  // write response channel
  logic [ID_W-1:0]   bid;
  logic [1:0]        bresp;
  logic              bvalid;
  logic              bready;
  // read address channel
  logic [ID_W-1:0]   arid;
  logic [ADDR_W-1:0] araddr;
  logic [7:0]        arlen;
  logic [2:0]        arsize;
  logic [1:0]        arburst;
  logic              arvalid;
  logic              arready;
  // read data channel
  logic [ID_W-1:0]   rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]        rresp;
  logic              rlast;
  logic              rvalid;
  logic              rready;

  // --------------------------------------------------------------------------
  // clocking blocks
  // --------------------------------------------------------------------------
  clocking drv_cb @(posedge aclk);
    default input #1step output #1;
    output awid, awaddr, awlen, awsize, awburst, awvalid;
    input  awready;
    output wdata, wstrb, wlast, wvalid;
    input  wready;
    input  bid, bresp, bvalid;
    output bready;
    output arid, araddr, arlen, arsize, arburst, arvalid;
    input  arready;
    input  rid, rdata, rresp, rlast, rvalid;
    output rready;
  endclocking

  clocking mon_cb @(posedge aclk);
    default input #1step;
    input aresetn;
    input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
    input wdata, wstrb, wlast, wvalid, wready;
    input bid, bresp, bvalid, bready;
    input arid, araddr, arlen, arsize, arburst, arvalid, arready;
    input rid, rdata, rresp, rlast, rvalid, rready;
  endclocking

  modport drv_mp (clocking drv_cb, input aclk, input aresetn);
  modport mon_mp (clocking mon_cb, input aclk, input aresetn);

  // --------------------------------------------------------------------------
  // burst trackers for the SVA below
  // --------------------------------------------------------------------------
  logic [7:0]  wtrk_len;    // AWLEN of the burst whose W beats are in flight
  logic        wtrk_vld;    // AW accepted, last W beat not yet accepted
  logic [8:0]  wtrk_beat;   // index of the next W beat
  logic [7:0]  rtrk_len;
  logic        rtrk_vld;
  logic [8:0]  rtrk_beat;
  int unsigned w_bursts_done;   // completed W bursts (WLAST handshakes)
  int unsigned b_done;          // completed B handshakes

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      wtrk_len      <= '0;
      wtrk_vld      <= 1'b0;
      wtrk_beat     <= '0;
      rtrk_len      <= '0;
      rtrk_vld      <= 1'b0;
      rtrk_beat     <= '0;
      w_bursts_done <= 0;
      b_done        <= 0;
    end else begin
      // write side
      if (wvalid && wready)
        wtrk_beat <= wlast ? 9'd0 : wtrk_beat + 9'd1;
      if (wvalid && wready && wlast)
        w_bursts_done <= w_bursts_done + 1;
      if (bvalid && bready)
        b_done <= b_done + 1;
      if (awvalid && awready) begin
        wtrk_len <= awlen;
        wtrk_vld <= 1'b1;
      end else if (wvalid && wready && wlast) begin
        wtrk_vld <= 1'b0;
      end
      // read side
      if (rvalid && rready)
        rtrk_beat <= rlast ? 9'd0 : rtrk_beat + 9'd1;
      if (arvalid && arready) begin
        rtrk_len <= arlen;
        rtrk_vld <= 1'b1;
      end else if (rvalid && rready && rlast) begin
        rtrk_vld <= 1'b0;
      end
    end
  end

  // INCR burst crosses a 4 KB boundary?
  function automatic bit crosses_4k(logic [ADDR_W-1:0] a, logic [7:0] len,
                                    logic [2:0] size, logic [1:0] burst);
    logic [ADDR_W-1:0] nbytes, first, last;
    if (burst != 2'b01) return 1'b0;
    nbytes = 1 << size;
    first  = a & ~(nbytes - 1);
    last   = first + (len + 1) * nbytes - 1;
    return (first[ADDR_W-1:12] != last[ADDR_W-1:12]);
  endfunction

  // --------------------------------------------------------------------------
  // generic handshake properties
  // --------------------------------------------------------------------------
  property p_valid_hold(valid, ready);
    @(posedge aclk) disable iff (!aresetn)
      (valid && !ready) |=> valid;
  endproperty

  property p_payload_stable(valid, ready, payload);
    @(posedge aclk) disable iff (!aresetn)
      (valid && !ready) |=> $stable(payload);
  endproperty

  // VALID stays high until READY
  a_aw_hold: assert property (p_valid_hold(awvalid, awready))
    else `uvm_error("AXI_SVA", "AWVALID deasserted before AWREADY")
  a_w_hold:  assert property (p_valid_hold(wvalid, wready))
    else `uvm_error("AXI_SVA", "WVALID deasserted before WREADY")
  a_b_hold:  assert property (p_valid_hold(bvalid, bready))
    else `uvm_error("AXI_SVA", "BVALID deasserted before BREADY")
  a_ar_hold: assert property (p_valid_hold(arvalid, arready))
    else `uvm_error("AXI_SVA", "ARVALID deasserted before ARREADY")
  a_r_hold:  assert property (p_valid_hold(rvalid, rready))
    else `uvm_error("AXI_SVA", "RVALID deasserted before RREADY")

  // payload stable while VALID && !READY
  a_aw_stable: assert property (p_payload_stable(awvalid, awready,
                                 {awid, awaddr, awlen, awsize, awburst}))
    else `uvm_error("AXI_SVA", "AW payload changed while AWVALID && !AWREADY")
  a_w_stable:  assert property (p_payload_stable(wvalid, wready, {wdata, wstrb, wlast}))
    else `uvm_error("AXI_SVA", "W payload changed while WVALID && !WREADY")
  a_b_stable:  assert property (p_payload_stable(bvalid, bready, {bid, bresp}))
    else `uvm_error("AXI_SVA", "B payload changed while BVALID && !BREADY")
  a_ar_stable: assert property (p_payload_stable(arvalid, arready,
                                 {arid, araddr, arlen, arsize, arburst}))
    else `uvm_error("AXI_SVA", "AR payload changed while ARVALID && !ARREADY")
  a_r_stable:  assert property (p_payload_stable(rvalid, rready, {rid, rdata, rresp, rlast}))
    else `uvm_error("AXI_SVA", "R payload changed while RVALID && !RREADY")

  // control signals never X/Z out of reset
  a_ctrl_known: assert property (@(posedge aclk) disable iff (!aresetn)
      !$isunknown({awvalid, awready, wvalid, wready, bvalid, bready,
                   arvalid, arready, rvalid, rready}))
    else `uvm_error("AXI_SVA", "X/Z on a VALID or READY signal")

  a_aw_known: assert property (@(posedge aclk) disable iff (!aresetn)
      awvalid |-> !$isunknown({awid, awaddr, awlen, awsize, awburst}))
    else `uvm_error("AXI_SVA", "X/Z on AW payload while AWVALID")
  a_w_known:  assert property (@(posedge aclk) disable iff (!aresetn)
      wvalid |-> !$isunknown({wstrb, wlast}))
    else `uvm_error("AXI_SVA", "X/Z on WSTRB/WLAST while WVALID")
  a_b_known:  assert property (@(posedge aclk) disable iff (!aresetn)
      bvalid |-> !$isunknown({bid, bresp}))
    else `uvm_error("AXI_SVA", "X/Z on B payload while BVALID")
  a_ar_known: assert property (@(posedge aclk) disable iff (!aresetn)
      arvalid |-> !$isunknown({arid, araddr, arlen, arsize, arburst}))
    else `uvm_error("AXI_SVA", "X/Z on AR payload while ARVALID")
  a_r_known:  assert property (@(posedge aclk) disable iff (!aresetn)
      rvalid |-> !$isunknown({rid, rresp, rlast}))
    else `uvm_error("AXI_SVA", "X/Z on R payload while RVALID")

  // legal address-channel encodings for this 32-bit bus
  a_aw_legal: assert property (@(posedge aclk) disable iff (!aresetn)
      awvalid |-> (awburst != 2'b11) && (awsize <= 3'd2))
    else `uvm_error("AXI_SVA", "Reserved AWBURST or AWSIZE wider than the bus")
  a_ar_legal: assert property (@(posedge aclk) disable iff (!aresetn)
      arvalid |-> (arburst != 2'b11) && (arsize <= 3'd2))
    else `uvm_error("AXI_SVA", "Reserved ARBURST or ARSIZE wider than the bus")

  a_aw_wrap: assert property (@(posedge aclk) disable iff (!aresetn)
      (awvalid && awburst == 2'b10) |->
        (awlen inside {8'd1, 8'd3, 8'd7, 8'd15}) &&
        ((awaddr & ((1 << awsize) - 1)) == 0))
    else `uvm_error("AXI_SVA", "WRAP write: AWLEN not 1/3/7/15 or AWADDR not size-aligned")
  a_ar_wrap: assert property (@(posedge aclk) disable iff (!aresetn)
      (arvalid && arburst == 2'b10) |->
        (arlen inside {8'd1, 8'd3, 8'd7, 8'd15}) &&
        ((araddr & ((1 << arsize) - 1)) == 0))
    else `uvm_error("AXI_SVA", "WRAP read: ARLEN not 1/3/7/15 or ARADDR not size-aligned")

  a_aw_4k: assert property (@(posedge aclk) disable iff (!aresetn)
      awvalid |-> !crosses_4k(awaddr, awlen, awsize, awburst))
    else `uvm_error("AXI_SVA", "INCR write burst crosses a 4 KB boundary")
  a_ar_4k: assert property (@(posedge aclk) disable iff (!aresetn)
      arvalid |-> !crosses_4k(araddr, arlen, arsize, arburst))
    else `uvm_error("AXI_SVA", "INCR read burst crosses a 4 KB boundary")

  // WLAST / RLAST exactly on beat AxLEN
  a_wlast_on_len: assert property (@(posedge aclk) disable iff (!aresetn)
      (wvalid && wready && wtrk_vld) |-> (wlast == (wtrk_beat == {1'b0, wtrk_len})))
    else `uvm_error("AXI_SVA", $sformatf("WLAST=%0b on beat %0d of AWLEN=%0d",
                                         wlast, wtrk_beat, wtrk_len))
  a_rlast_on_len: assert property (@(posedge aclk) disable iff (!aresetn)
      (rvalid && rready && rtrk_vld) |-> (rlast == (rtrk_beat == {1'b0, rtrk_len})))
    else `uvm_error("AXI_SVA", $sformatf("RLAST=%0b on beat %0d of ARLEN=%0d",
                                         rlast, rtrk_beat, rtrk_len))

  // ordering
  a_b_after_wlast: assert property (@(posedge aclk) disable iff (!aresetn)
      bvalid |-> (w_bursts_done > b_done))
    else `uvm_error("AXI_SVA", "BVALID before the last W beat of the burst was accepted")
  a_r_after_ar: assert property (@(posedge aclk) disable iff (!aresetn)
      rvalid |-> rtrk_vld)
    else `uvm_error("AXI_SVA", "RVALID with no accepted AR outstanding")
  // axi_mem-specific: it only accepts W beats after the AW handshake
  a_w_after_aw: assert property (@(posedge aclk) disable iff (!aresetn)
      (wvalid && wready) |-> wtrk_vld)
    else `uvm_error("AXI_SVA", "W beat accepted with no AW outstanding")

  // --------------------------------------------------------------------------
  // protocol cover points
  // --------------------------------------------------------------------------
  c_aw_stall:   cover property (@(posedge aclk) disable iff (!aresetn)
                  (awvalid && !awready) ##1 (awvalid && awready));
  c_w_b2b:      cover property (@(posedge aclk) disable iff (!aresetn)
                  (wvalid && wready) ##1 (wvalid && wready));
  c_w_stall:    cover property (@(posedge aclk) disable iff (!aresetn)
                  (wvalid && !wready) ##1 (wvalid && wready));
  c_b_stall:    cover property (@(posedge aclk) disable iff (!aresetn)
                  (bvalid && !bready) ##1 (bvalid && bready));
  c_ar_stall:   cover property (@(posedge aclk) disable iff (!aresetn)
                  (arvalid && !arready) ##1 (arvalid && arready));
  c_r_stall:    cover property (@(posedge aclk) disable iff (!aresetn)
                  (rvalid && !rready) ##1 (rvalid && rready));
  c_wrap_write: cover property (@(posedge aclk) disable iff (!aresetn)
                  awvalid && awready && awburst == 2'b10 && awlen == 8'd15);
  c_b_slverr:   cover property (@(posedge aclk) disable iff (!aresetn)
                  bvalid && bready && bresp == 2'b10);
  c_r_slverr:   cover property (@(posedge aclk) disable iff (!aresetn)
                  rvalid && rready && rresp == 2'b10);

endinterface
