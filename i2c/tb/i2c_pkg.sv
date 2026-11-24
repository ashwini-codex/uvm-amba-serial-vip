// ----------------------------------------------------------------------------
// i2c_pkg.sv : I2C slave agent + I2C bench (APB-controlled I2C master DUT)
// Compile apb_if.sv, i2c_if.sv and apb_agent_pkg.sv first.
// ----------------------------------------------------------------------------
package i2c_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_agent_pkg::*;

  // DUT register map
  localparam bit [31:0] I2C_CLKDIV = 32'h00;
  localparam bit [31:0] I2C_CMD    = 32'h04;
  localparam bit [31:0] I2C_TXDATA = 32'h08;
  localparam bit [31:0] I2C_RXDATA = 32'h0C;
  localparam bit [31:0] I2C_STATUS = 32'h10;

  localparam bit [4:0] I2C_CMD_START = 5'b00001;
  localparam bit [4:0] I2C_CMD_STOP  = 5'b00010;
  localparam bit [4:0] I2C_CMD_WRITE = 5'b00100;
  localparam bit [4:0] I2C_CMD_READ  = 5'b01000;
  localparam bit [4:0] I2C_CMD_NACK  = 5'b10000;

  // Slave agent address and power-on memory contents (shared by the slave
  // model and the scoreboard's reference memory).
  localparam bit [6:0] I2C_SLV_ADDR = 7'h50;

  function automatic bit [7:0] i2c_mem_init(int unsigned i);
    return i[7:0] ^ 8'h5A;
  endfunction

  `uvm_analysis_imp_decl(_apb)
  `uvm_analysis_imp_decl(_i2c)

  // I2C agent
  `include "i2c_items.sv"
  `include "i2c_agent_cfg.sv"
  `include "i2c_slave_driver.sv"
  `include "i2c_monitor.sv"
  `include "i2c_agent.sv"
  `include "i2c_seqs.sv"

  // Bench
  `include "i2c_env_cfg.sv"
  `include "i2c_scoreboard.sv"
  `include "i2c_coverage.sv"
  `include "i2c_vsequencer.sv"
  `include "i2c_env.sv"
  `include "i2c_vseqs.sv"
  `include "i2c_tests.sv"

endpackage
