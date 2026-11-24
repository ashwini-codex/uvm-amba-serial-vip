// ----------------------------------------------------------------------------
// uart_if.sv : serial side of the UART (tx = DUT output, rx = DUT input)
// Bit timing is counted in clk cycles (div cycles per bit).
// ----------------------------------------------------------------------------
`include "uvm_macros.svh"

interface uart_if (input logic clk, input logic rst_n);

  import uvm_pkg::*;

  logic tx;   // driven by the DUT
  logic rx;   // driven by the UART agent

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output rx;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input rst_n, tx, rx;
  endclocking

  // Lines must never be X/Z once out of reset.
  a_tx_known : assert property (@(posedge clk) disable iff (!rst_n) !$isunknown(tx))
    else `uvm_error("UART_SVA", "tx is X/Z")
  a_rx_known : assert property (@(posedge clk) disable iff (!rst_n) !$isunknown(rx))
    else `uvm_error("UART_SVA", "rx is X/Z")

  // A start bit on tx lasts at least 2 cycles (no single-cycle glitches).
  a_tx_no_glitch : assert property (@(posedge clk) disable iff (!rst_n)
    $fell(tx) |=> !tx)
    else `uvm_error("UART_SVA", "1-cycle low glitch on tx")

endinterface
