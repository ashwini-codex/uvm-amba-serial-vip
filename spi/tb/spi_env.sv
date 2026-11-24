// ----------------------------------------------------------------------------
// spi_env.sv : APB agent + SPI slave agent + scoreboard + coverage + vsequencer
// ----------------------------------------------------------------------------
class spi_env extends uvm_env;

  `uvm_component_utils(spi_env)

  spi_env_cfg    cfg;
  apb_agent      apb_agt;
  spi_agent      spi_agt;
  spi_scoreboard sb;
  spi_coverage   cov;
  spi_vsequencer vsqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(spi_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SPI_ENV", "no spi_env_cfg in config_db (key \"cfg\")")

    uvm_config_db #(apb_agent_cfg)::set(this, "apb_agt*", "apb_cfg", cfg.apb_cfg);
    uvm_config_db #(spi_agent_cfg)::set(this, "spi_agt*", "spi_cfg", cfg.spi_cfg);

    apb_agt = apb_agent::type_id::create("apb_agt", this);
    spi_agt = spi_agent::type_id::create("spi_agt", this);
    vsqr    = spi_vsequencer::type_id::create("vsqr", this);
    if (cfg.has_scoreboard) sb  = spi_scoreboard::type_id::create("sb", this);
    if (cfg.has_coverage)   cov = spi_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    vsqr.apb_sqr = apb_agt.sqr;
    vsqr.spi_sqr = spi_agt.sqr;
    vsqr.cfg     = cfg;
    if (cfg.has_scoreboard) begin
      apb_agt.ap.connect(sb.apb_imp);
      spi_agt.ap.connect(sb.spi_imp);
    end
    if (cfg.has_coverage) begin
      apb_agt.ap.connect(cov.apb_imp);
      spi_agt.ap.connect(cov.spi_imp);
    end
  endfunction

endclass
