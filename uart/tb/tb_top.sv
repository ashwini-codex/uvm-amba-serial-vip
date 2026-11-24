// ----------------------------------------------------------------------------
// tb_top.sv : UART bench top (testbench.sv on EDA Playground)
// Default test is uart_full_test; override with +UVM_TESTNAME=<test>.
// ----------------------------------------------------------------------------
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "apb_if.sv"
`include "uart_if.sv"
`include "apb_agent_pkg.sv"
`include "uart_pkg.sv"

module tb_top;

  import uvm_pkg::*;
  import apb_agent_pkg::*;
  import uart_pkg::*;

  logic PCLK    = 1'b0;
  logic PRESETn = 1'b0;

  always #5 PCLK = ~PCLK;

  initial begin
    PRESETn = 1'b0;
    repeat (5) @(posedge PCLK);
    PRESETn <= 1'b1;
  end

  apb_if  apb_vif  (.PCLK(PCLK), .PRESETn(PRESETn));
  uart_if uart_vif (.clk(PCLK),  .rst_n(PRESETn));

  apb_uart dut (
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
    .uart_tx (uart_vif.tx),
    .uart_rx (uart_vif.rx)
  );

  initial begin
    uvm_config_db #(virtual apb_if )::set(null, "uvm_test_top", "apb_vif",  apb_vif);
    uvm_config_db #(virtual uart_if)::set(null, "uvm_test_top", "uart_vif", uart_vif);
    run_test("uart_full_test");
  end

  // Waveforms only when asked for (+DUMP): long runs make large VCDs.
  initial begin
    if ($test$plusargs("DUMP")) begin
      $dumpfile("dump.vcd");
      $dumpvars(0, tb_top);
    end
  end

endmodule
