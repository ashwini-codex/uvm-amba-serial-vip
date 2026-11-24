// ----------------------------------------------------------------------------
// uart_agent.sv : UART serial agent (driver on rx, monitor on tx and rx)
// ----------------------------------------------------------------------------
typedef uvm_sequencer #(uart_seq_item) uart_sequencer;

class uart_agent extends uvm_agent;

  `uvm_component_utils(uart_agent)

  uart_agent_cfg                     cfg;
  uart_sequencer                     sqr;
  uart_driver                        drv;
  uart_monitor                       mon;
  uvm_analysis_port #(uart_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(uart_agent_cfg)::get(this, "", "uart_cfg", cfg))
      `uvm_fatal("UART_AGT", "no uart_agent_cfg in config_db (key \"uart_cfg\")")
    if (cfg.vif == null)
      `uvm_fatal("UART_AGT", "uart_agent_cfg.vif is null")

    is_active = cfg.is_active;
    ap  = new("ap", this);
    mon = uart_monitor::type_id::create("mon", this);
    if (is_active == UVM_ACTIVE) begin
      sqr = uart_sequencer::type_id::create("sqr", this);
      drv = uart_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    mon.vif = cfg.vif;
    mon.cfg = cfg;
    mon.ap.connect(ap);
    if (is_active == UVM_ACTIVE) begin
      drv.vif = cfg.vif;
      drv.cfg = cfg;
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass
