// ============================================================================
// tb_top.sv  --  AXI4 bench top (testbench.sv on EDA Playground)
//
// Compile with design.sv = axi/rtl/axi_mem.sv. Select the test with
// +UVM_TESTNAME=<axi_base_test|axi_single_test|axi_burst_test|axi_rand_test|axi_err_test>.
// Add +define+DUMP to write dump.vcd.
// ============================================================================
`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "axi_if.sv"
`include "axi_pkg.sv"

module tb_top;
  import uvm_pkg::*;
  import axi_pkg::*;

  logic aclk = 1'b0;
  logic aresetn;

  always #5 aclk = ~aclk;               // 100 MHz

  initial begin
    aresetn = 1'b0;
    repeat (5) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;
  end

  axi_if vif (.aclk(aclk), .aresetn(aresetn));

  axi_mem #(
    .ADDR_W    (32),
    .DATA_W    (32),
    .ID_W      (4),
    .MEM_BYTES (AXI_MEM_BYTES)
  ) dut (
    .aclk    (aclk),
    .aresetn (aresetn),
    .awid    (vif.awid),
    .awaddr  (vif.awaddr),
    .awlen   (vif.awlen),
    .awsize  (vif.awsize),
    .awburst (vif.awburst),
    .awvalid (vif.awvalid),
    .awready (vif.awready),
    .wdata   (vif.wdata),
    .wstrb   (vif.wstrb),
    .wlast   (vif.wlast),
    .wvalid  (vif.wvalid),
    .wready  (vif.wready),
    .bid     (vif.bid),
    .bresp   (vif.bresp),
    .bvalid  (vif.bvalid),
    .bready  (vif.bready),
    .arid    (vif.arid),
    .araddr  (vif.araddr),
    .arlen   (vif.arlen),
    .arsize  (vif.arsize),
    .arburst (vif.arburst),
    .arvalid (vif.arvalid),
    .arready (vif.arready),
    .rid     (vif.rid),
    .rdata   (vif.rdata),
    .rresp   (vif.rresp),
    .rlast   (vif.rlast),
    .rvalid  (vif.rvalid),
    .rready  (vif.rready)
  );

  initial begin
    uvm_config_db#(virtual axi_if)::set(null, "*", "vif", vif);
    run_test();
  end

`ifdef DUMP
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end
`endif

endmodule
