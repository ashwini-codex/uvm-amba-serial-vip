// ----------------------------------------------------------------------------
// tb_top.sv : APB bench top (testbench.sv on EDA Playground)
// Default test is apb_full_test; override with +UVM_TESTNAME=<test>.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "apb_if.sv"
`include "apb_agent_pkg.sv"
`include "apb_tb_pkg.sv"

module tb_top;

  import uvm_pkg::*;
  import apb_agent_pkg::*;
  import apb_tb_pkg::*;

  logic PCLK    = 1'b0;
  logic PRESETn = 1'b0;

  always #5 PCLK = ~PCLK;   // 100 MHz

  initial begin
    PRESETn = 1'b0;
    repeat (5) @(posedge PCLK);
    PRESETn <= 1'b1;
  end

  apb_if apb_vif (.PCLK(PCLK), .PRESETn(PRESETn));

  apb_mem #(.DEPTH(256), .WAIT_EN(1'b1)) dut (
    .PCLK    (PCLK),
    .PRESETn (PRESETn),
    .PADDR   (apb_vif.PADDR),
    .PSEL    (apb_vif.PSEL),
    .PENABLE (apb_vif.PENABLE),
    .PWRITE  (apb_vif.PWRITE),
    .PWDATA  (apb_vif.PWDATA),
    .PRDATA  (apb_vif.PRDATA),
    .PREADY  (apb_vif.PREADY),
    .PSLVERR (apb_vif.PSLVERR)
  );

  initial begin
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top", "apb_vif", apb_vif);
    run_test("apb_full_test");
  end

  // Waveforms only when asked for (+DUMP): long runs make large VCDs.
  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
