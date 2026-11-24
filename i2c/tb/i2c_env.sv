// ----------------------------------------------------------------------------
// i2c_env.sv : APB agent + I2C slave agent + scoreboard + coverage + vsequencer
// ----------------------------------------------------------------------------
class i2c_env extends uvm_env;

  `uvm_component_utils(i2c_env)

  i2c_env_cfg    cfg;
  apb_agent      apb_agt;
  i2c_agent      i2c_agt;
  i2c_scoreboard sb;
  i2c_coverage   cov;
  i2c_vsequencer vsqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(i2c_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("I2C_ENV", "no i2c_env_cfg in config_db (key \"cfg\")")

    uvm_config_db #(apb_agent_cfg)::set(this, "apb_agt*", "apb_cfg", cfg.apb_cfg);
    uvm_config_db #(i2c_agent_cfg)::set(this, "i2c_agt*", "i2c_cfg", cfg.i2c_cfg);

    apb_agt = apb_agent::type_id::create("apb_agt", this);
    i2c_agt = i2c_agent::type_id::create("i2c_agt", this);
    vsqr    = i2c_vsequencer::type_id::create("vsqr", this);
    if (cfg.has_scoreboard) sb  = i2c_scoreboard::type_id::create("sb", this);
    if (cfg.has_coverage)   cov = i2c_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    vsqr.apb_sqr = apb_agt.sqr;
    vsqr.i2c_sqr = i2c_agt.sqr;
    vsqr.cfg     = cfg;
    if (cfg.has_scoreboard) begin
      apb_agt.ap.connect(sb.apb_imp);
      i2c_agt.ap.connect(sb.i2c_imp);
    end
    if (cfg.has_coverage) begin
      apb_agt.ap.connect(cov.apb_imp);
      i2c_agt.ap.connect(cov.i2c_imp);
    end
  endfunction

endclass
