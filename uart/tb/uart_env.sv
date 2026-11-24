// ----------------------------------------------------------------------------
// uart_env.sv : APB agent + UART agent + scoreboard + coverage + virtual sequencer
// ----------------------------------------------------------------------------
class uart_env extends uvm_env;

  `uvm_component_utils(uart_env)

  uart_env_cfg    cfg;
  apb_agent       apb_agt;
  uart_agent      uart_agt;
  uart_scoreboard sb;
  uart_coverage   cov;
  uart_vsequencer vsqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("UART_ENV", "no uart_env_cfg in config_db (key \"cfg\")")

    uvm_config_db #(apb_agent_cfg)::set (this, "apb_agt*",  "apb_cfg",  cfg.apb_cfg);
    uvm_config_db #(uart_agent_cfg)::set(this, "uart_agt*", "uart_cfg", cfg.uart_cfg);

    apb_agt  = apb_agent::type_id::create("apb_agt", this);
    uart_agt = uart_agent::type_id::create("uart_agt", this);
    vsqr     = uart_vsequencer::type_id::create("vsqr", this);
    if (cfg.has_scoreboard) sb  = uart_scoreboard::type_id::create("sb", this);
    if (cfg.has_coverage)   cov = uart_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    vsqr.apb_sqr  = apb_agt.sqr;
    vsqr.uart_sqr = uart_agt.sqr;
    vsqr.cfg      = cfg;
    if (cfg.has_scoreboard) begin
      apb_agt.ap.connect(sb.apb_imp);
      uart_agt.ap.connect(sb.uart_imp);
    end
    if (cfg.has_coverage) begin
      apb_agt.ap.connect(cov.apb_imp);
      uart_agt.ap.connect(cov.uart_imp);
    end
  endfunction

endclass
