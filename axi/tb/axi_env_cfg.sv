// ============================================================================
// axi_env_cfg.sv  --  environment / agent configuration object
//
// Created by the test, published with
//   uvm_config_db#(axi_env_cfg)::set(this, "env*", "cfg", cfg)
// and fetched by the env, the agent and the sequences.
// ============================================================================
class axi_env_cfg extends uvm_object;

  uvm_active_passive_enum is_active    = UVM_ACTIVE;
  bit                     has_coverage = 1'b1;
  int unsigned            num_txns     = 50;    // per sequence, unless the sequence overrides it
  int unsigned            err_pct      = 0;     // % of out-of-range txns in axi_rand_mix_seq
  bit                     zero_delay   = 1'b0;  // master drives with no VALID/READY delays
  int unsigned            mem_bytes    = AXI_MEM_BYTES;

  `uvm_object_utils(axi_env_cfg)

  function new(string name = "axi_env_cfg");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("is_active=%s has_coverage=%0b num_txns=%0d err_pct=%0d zero_delay=%0b mem_bytes=%0d",
                     is_active.name(), has_coverage, num_txns, err_pct, zero_delay, mem_bytes);
  endfunction

endclass
