// ----------------------------------------------------------------------------
// spi_pkg.sv : SPI slave agent + SPI bench (APB-controlled SPI master DUT)
// Compile apb_if.sv, spi_if.sv and apb_agent_pkg.sv first.
// ----------------------------------------------------------------------------
package spi_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_agent_pkg::*;

  // DUT register map
  localparam bit [31:0] SPI_CTRL   = 32'h00;
  localparam bit [31:0] SPI_CLKDIV = 32'h04;
  localparam bit [31:0] SPI_TXDATA = 32'h08;
  localparam bit [31:0] SPI_RXDATA = 32'h0C;
  localparam bit [31:0] SPI_STATUS = 32'h10;

  `uvm_analysis_imp_decl(_apb)
  `uvm_analysis_imp_decl(_spi)

  // SPI agent
  `include "spi_seq_item.sv"
  `include "spi_agent_cfg.sv"
  `include "spi_driver.sv"
  `include "spi_monitor.sv"
  `include "spi_agent.sv"
  `include "spi_seqs.sv"

  // Bench
  `include "spi_env_cfg.sv"
  `include "spi_scoreboard.sv"
  `include "spi_coverage.sv"
  `include "spi_vsequencer.sv"
  `include "spi_env.sv"
  `include "spi_vseqs.sv"
  `include "spi_tests.sv"

endpackage
