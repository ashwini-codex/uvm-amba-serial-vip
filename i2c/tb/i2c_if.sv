// ----------------------------------------------------------------------------
// i2c_if.sv : open-drain I2C bus. Each side pulls a line low with its *_oe
// signal; tri1 nets act as the pull-up resistors.
//   m_* : DUT (master)       s_* : slave agent
// ----------------------------------------------------------------------------
`include "uvm_macros.svh"

interface i2c_if (input logic clk, input logic rst_n);

  import uvm_pkg::*;

  tri1  scl;
  tri1  sda;

  logic m_scl_oe;
  logic m_sda_oe;
  logic s_scl_oe = 1'b0;
  logic s_sda_oe = 1'b0;

  assign scl = (m_scl_oe || s_scl_oe) ? 1'b0 : 1'bz;
  assign sda = (m_sda_oe || s_sda_oe) ? 1'b0 : 1'bz;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    input  scl, sda;
    output s_scl_oe, s_sda_oe;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n, scl, sda, m_scl_oe, s_scl_oe;
  endclocking

  // --------------------------------------------------------------------------
  // Bit-position tracker for the SDA-stability rule. Counts SCL rising edges
  // since the last START/STOP: 1..8 data bits, 9 = ACK, then wraps to 1.
  // A START or STOP can only appear in the first SCL-high period of a byte
  // (count 1) or while the bus is idle (count 0).
  // --------------------------------------------------------------------------
  logic       scl_q, sda_q;
  logic [3:0] bitpos;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_q  <= 1'b1;
      sda_q  <= 1'b1;
      bitpos <= '0;
    end
    else begin
      scl_q <= scl;
      sda_q <= sda;
      if (scl_q && scl && (sda_q != sda))  bitpos <= '0;                         // START/STOP
      else if (!scl_q && scl)              bitpos <= (bitpos == 4'd9) ? 4'd1 : bitpos + 1'b1;
    end
  end

  a_no_x : assert property (@(posedge clk) disable iff (!rst_n) !$isunknown({scl, sda}))
    else `uvm_error("I2C_SVA", "X on SCL/SDA")

  // SDA must be stable while SCL is high, except for START and STOP.
  a_sda_stable_scl_high : assert property (@(posedge clk) disable iff (!rst_n)
    (scl && $past(scl) && $changed(sda)) |-> (bitpos <= 4'd1))
    else `uvm_error("I2C_SVA", $sformatf("SDA changed while SCL high in the middle of a byte (bit %0d)", bitpos))

  // Setup / hold: SDA never changes on the same cycle SCL changes.
  a_sda_setup : assert property (@(posedge clk) disable iff (!rst_n) $rose(scl) |-> $stable(sda))
    else `uvm_error("I2C_SVA", "SDA changed together with SCL rising")
  a_sda_hold  : assert property (@(posedge clk) disable iff (!rst_n) $fell(scl) |-> $stable(sda))
    else `uvm_error("I2C_SVA", "SDA changed together with SCL falling")

  // SCL high and low phases last at least 2 cycles.
  a_scl_min_high : assert property (@(posedge clk) disable iff (!rst_n) $rose(scl) |=> scl)
    else `uvm_error("I2C_SVA", "SCL high pulse shorter than 2 cycles")
  a_scl_min_low  : assert property (@(posedge clk) disable iff (!rst_n) $fell(scl) |=> !scl)
    else `uvm_error("I2C_SVA", "SCL low pulse shorter than 2 cycles")

  // The slave may only move SDA while SCL is low.
  a_slave_sda_scl_low : assert property (@(posedge clk) disable iff (!rst_n)
    $changed(s_sda_oe) |-> !scl)
    else `uvm_error("I2C_SVA", "slave changed SDA while SCL high")

  c_start         : cover property (@(posedge clk) disable iff (!rst_n) scl && $past(scl) && $fell(sda));
  c_stop          : cover property (@(posedge clk) disable iff (!rst_n) scl && $past(scl) && $rose(sda));
  c_clock_stretch : cover property (@(posedge clk) disable iff (!rst_n) !m_scl_oe && s_scl_oe);

endinterface
