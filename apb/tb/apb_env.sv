// ----------------------------------------------------------------------------
// apb_env.sv : APB agent + scoreboard + coverage
// ----------------------------------------------------------------------------
class apb_env extends uvm_env;

  `uvm_component_utils(apb_env)

  apb_env_cfg    cfg;
  apb_agent      agent;
  apb_scoreboard sb;
  apb_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(apb_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("APB_ENV", "no apb_env_cfg in config_db (key \"cfg\")")

    // Hand the agent its own config.
    uvm_config_db #(apb_agent_cfg)::set(this, "agent*", "apb_cfg", cfg.apb_cfg);
    agent = apb_agent::type_id::create("agent", this);

    if (cfg.has_scoreboard) begin
      sb = apb_scoreboard::type_id::create("sb", this);
      sb.mem_bytes = cfg.mem_bytes;
    end
    if (cfg.has_coverage)
      cov = apb_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    if (cfg.has_scoreboard) agent.ap.connect(sb.imp);
    if (cfg.has_coverage)   agent.ap.connect(cov.analysis_export);
  endfunction

endclass
