// ----------------------------------------------------------------------------
// tb_top.sv : I2C bench top (testbench.sv on EDA Playground)
// Default test is i2c_full_test; override with +UVM_TESTNAME=<test>.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "apb_if.sv"
`include "i2c_if.sv"
`include "apb_agent_pkg.sv"
`include "i2c_pkg.sv"

module tb_top;

  import uvm_pkg::*;
  import apb_agent_pkg::*;
  import i2c_pkg::*;

  logic PCLK    = 1'b0;
  logic PRESETn = 1'b0;

  always #5 PCLK = ~PCLK;

  initial begin
    PRESETn = 1'b0;
    repeat (5) @(posedge PCLK);
    PRESETn <= 1'b1;
  end

  apb_if apb_vif (.PCLK(PCLK), .PRESETn(PRESETn));
  i2c_if i2c_vif (.clk(PCLK),  .rst_n(PRESETn));

  apb_i2c_master dut (
    .PCLK    (PCLK),
    .PRESETn (PRESETn),
    .PADDR   (apb_vif.PADDR),
    .PSEL    (apb_vif.PSEL),
    .PENABLE (apb_vif.PENABLE),
    .PWRITE  (apb_vif.PWRITE),
    .PWDATA  (apb_vif.PWDATA),
    .PRDATA  (apb_vif.PRDATA),
    .PREADY  (apb_vif.PREADY),
    .PSLVERR (apb_vif.PSLVERR),
    .scl_oe  (i2c_vif.m_scl_oe),
    .sda_oe  (i2c_vif.m_sda_oe),
    .scl_i   (i2c_vif.scl),
    .sda_i   (i2c_vif.sda)
  );

  initial begin
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top", "apb_vif", apb_vif);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top", "i2c_vif", i2c_vif);
    run_test("i2c_full_test");
  end

  // Waveforms only when asked for (+DUMP): long runs make large VCDs.
  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
