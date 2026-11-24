// ----------------------------------------------------------------------------
// spi_if.sv : SPI bus between the DUT (master) and the SPI slave agent
// ----------------------------------------------------------------------------
`include "uvm_macros.svh"

interface spi_if (input logic clk, input logic rst_n);

  import uvm_pkg::*;

  logic sclk;
  logic cs_n;
  logic mosi;
  logic miso;

  // Expected SCLK idle level; the virtual sequence updates it with CTRL.cpol.
  bit cpol_exp = 1'b0;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    input  sclk, cs_n, mosi;
    output miso;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n, sclk, cs_n, mosi, miso;
  endclocking

  a_cs_known : assert property (@(posedge clk) disable iff (!rst_n) !$isunknown(cs_n))
    else `uvm_error("SPI_SVA", "cs_n is X/Z")

  a_bus_known : assert property (@(posedge clk) disable iff (!rst_n)
    !cs_n |-> !$isunknown({sclk, mosi, miso}))
    else `uvm_error("SPI_SVA", "X/Z on sclk/mosi/miso while selected")

  // SCLK must sit at its idle level (CPOL) when CS asserts and when it releases.
  a_idle_at_cs_fall : assert property (@(posedge clk) disable iff (!rst_n)
    $fell(cs_n) |-> (sclk == cpol_exp))
    else `uvm_error("SPI_SVA", $sformatf("SCLK=%0b at CS assert, CPOL=%0b", sclk, cpol_exp))

  a_idle_at_cs_rise : assert property (@(posedge clk) disable iff (!rst_n)
    $rose(cs_n) |-> (sclk == cpol_exp))
    else `uvm_error("SPI_SVA", $sformatf("SCLK=%0b at CS release, CPOL=%0b", sclk, cpol_exp))

  // Each SCLK level lasts at least 2 clk cycles (CLKDIV >= 2).
  a_sclk_min_width : assert property (@(posedge clk) disable iff (!rst_n)
    (!cs_n && $changed(sclk)) |=> $stable(sclk))
    else `uvm_error("SPI_SVA", "SCLK pulse shorter than 2 cycles")

endinterface
