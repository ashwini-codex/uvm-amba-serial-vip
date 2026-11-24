// ============================================================================
// axi_env.sv  --  agent + scoreboard + coverage subscriber
// ============================================================================
class axi_env extends uvm_env;

  `uvm_component_utils(axi_env)

  axi_env_cfg    cfg;
  axi_agent      agt;
  axi_scoreboard sb;
  axi_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "axi_env_cfg 'cfg' not found in uvm_config_db")
    agt = axi_agent::type_id::create("agt", this);
    sb  = axi_scoreboard::type_id::create("sb", this);
    if (cfg.has_coverage)
      cov = axi_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.ap.connect(sb.item_imp);
    if (cfg.has_coverage)
      agt.ap.connect(cov.analysis_export);
  endfunction

endclass
