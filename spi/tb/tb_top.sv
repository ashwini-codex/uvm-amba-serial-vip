// ----------------------------------------------------------------------------
// tb_top.sv : SPI bench top (testbench.sv on EDA Playground)
// Default test is spi_full_test; override with +UVM_TESTNAME=<test>.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "apb_if.sv"
`include "spi_if.sv"
`include "apb_agent_pkg.sv"
`include "spi_pkg.sv"

module tb_top;

  import uvm_pkg::*;
  import apb_agent_pkg::*;
  import spi_pkg::*;

  logic PCLK    = 1'b0;
  logic PRESETn = 1'b0;

  always #5 PCLK = ~PCLK;

  initial begin
    PRESETn = 1'b0;
    repeat (5) @(posedge PCLK);
    PRESETn <= 1'b1;
  end

  apb_if apb_vif (.PCLK(PCLK), .PRESETn(PRESETn));
  spi_if spi_vif (.clk(PCLK),  .rst_n(PRESETn));

  apb_spi_master dut (
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
    .sclk    (spi_vif.sclk),
    .cs_n    (spi_vif.cs_n),
    .mosi    (spi_vif.mosi),
    .miso    (spi_vif.miso)
  );

  initial begin
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top", "apb_vif", apb_vif);
    uvm_config_db #(virtual spi_if)::set(null, "uvm_test_top", "spi_vif", spi_vif);
    run_test("spi_full_test");
  end

  // Waveforms only when asked for (+DUMP): long runs make large VCDs.
  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
