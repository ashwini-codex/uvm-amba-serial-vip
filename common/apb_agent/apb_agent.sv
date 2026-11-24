// ----------------------------------------------------------------------------
// apb_agent.sv : sequencer + driver (active only) + monitor
// Reads its apb_agent_cfg (virtual interface, active/passive) from config_db.
// ----------------------------------------------------------------------------
typedef uvm_sequencer #(apb_seq_item) apb_sequencer;

class apb_agent extends uvm_agent;

  `uvm_component_utils(apb_agent)

  apb_agent_cfg                     cfg;
  apb_sequencer                     sqr;
  apb_driver                        drv;
  apb_monitor                       mon;
  uvm_analysis_port #(apb_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(apb_agent_cfg)::get(this, "", "apb_cfg", cfg))
      `uvm_fatal("APB_AGT", "no apb_agent_cfg in config_db (key \"apb_cfg\")")
    if (cfg.vif == null)
      `uvm_fatal("APB_AGT", "apb_agent_cfg.vif is null")

    is_active = cfg.is_active;
    ap  = new("ap", this);
    mon = apb_monitor::type_id::create("mon", this);
    if (is_active == UVM_ACTIVE) begin
      sqr = apb_sequencer::type_id::create("sqr", this);
      drv = apb_driver::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    mon.vif = cfg.vif;
    mon.ap.connect(ap);
    if (is_active == UVM_ACTIVE) begin
      drv.vif = cfg.vif;
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass
