// ----------------------------------------------------------------------------
// apb_env_cfg.sv : test settings for the APB bench (set by the test,
// read by the env through uvm_config_db)
// ----------------------------------------------------------------------------
class apb_env_cfg extends uvm_object;

  apb_agent_cfg apb_cfg;
  bit           has_scoreboard = 1'b1;
  bit           has_coverage   = 1'b1;
  int unsigned  num_txns       = 200;      // override with +NUM_TXNS=<n>
  bit [31:0]    mem_bytes      = 32'h400;  // DUT size: 256 words

  `uvm_object_utils(apb_env_cfg)

  function new(string name = "apb_env_cfg");
    super.new(name);
    apb_cfg = apb_agent_cfg::type_id::create("apb_cfg");
  endfunction

endclass
