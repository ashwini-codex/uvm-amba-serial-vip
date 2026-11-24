// ----------------------------------------------------------------------------
// uart_pkg.sv : UART agent + UART bench (APB-controlled UART)
// Compile apb_if.sv, uart_if.sv and apb_agent_pkg.sv first.
// ----------------------------------------------------------------------------
package uart_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_agent_pkg::*;

  // DUT register map
  localparam bit [31:0] UART_CTRL   = 32'h00;
  localparam bit [31:0] UART_BAUD   = 32'h04;
  localparam bit [31:0] UART_TXDATA = 32'h08;
  localparam bit [31:0] UART_RXDATA = 32'h0C;
  localparam bit [31:0] UART_STATUS = 32'h10;

  `uvm_analysis_imp_decl(_apb)
  `uvm_analysis_imp_decl(_uart)

  // UART agent
  `include "uart_seq_item.sv"
  `include "uart_agent_cfg.sv"
  `include "uart_driver.sv"
  `include "uart_monitor.sv"
  `include "uart_agent.sv"
  `include "uart_seqs.sv"

  // Bench
  `include "uart_env_cfg.sv"
  `include "uart_scoreboard.sv"
  `include "uart_coverage.sv"
  `include "uart_vsequencer.sv"
  `include "uart_env.sv"
  `include "uart_vseqs.sv"
  `include "uart_tests.sv"

endpackage
