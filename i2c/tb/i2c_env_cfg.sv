// ----------------------------------------------------------------------------
// i2c_env_cfg.sv : test settings for the I2C bench
// ----------------------------------------------------------------------------
class i2c_env_cfg extends uvm_object;

  apb_agent_cfg apb_cfg;
  i2c_agent_cfg i2c_cfg;
  bit           has_scoreboard = 1'b1;
  bit           has_coverage   = 1'b1;
  int unsigned  num_txns       = 15;    // transactions per phase, +NUM_TXNS=<n>

  `uvm_object_utils(i2c_env_cfg)

  function new(string name = "i2c_env_cfg");
    super.new(name);
    apb_cfg = apb_agent_cfg::type_id::create("apb_cfg");
    i2c_cfg = i2c_agent_cfg::type_id::create("i2c_cfg");
  endfunction

endclass
