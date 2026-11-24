// ----------------------------------------------------------------------------
// spi_env_cfg.sv : test settings for the SPI bench
// ----------------------------------------------------------------------------
class spi_env_cfg extends uvm_object;

  apb_agent_cfg apb_cfg;
  spi_agent_cfg spi_cfg;
  bit           has_scoreboard = 1'b1;
  bit           has_coverage   = 1'b1;
  int unsigned  num_txns       = 25;    // transfers per phase, +NUM_TXNS=<n>

  `uvm_object_utils(spi_env_cfg)

  function new(string name = "spi_env_cfg");
    super.new(name);
    apb_cfg = apb_agent_cfg::type_id::create("apb_cfg");
    spi_cfg = spi_agent_cfg::type_id::create("spi_cfg");
  endfunction

endclass
