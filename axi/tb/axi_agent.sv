// ============================================================================
// axi_agent.sv  --  AXI4 master agent: sequencer + driver (active) + monitor
// ============================================================================
class axi_agent extends uvm_agent;

  `uvm_component_utils(axi_agent)

  axi_env_cfg   cfg;
  axi_sequencer sqr;
  axi_driver    drv;
  axi_monitor   mon;
  uvm_analysis_port #(axi_seq_item) ap;   // re-exports the monitor's port

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "axi_env_cfg 'cfg' not found in uvm_config_db")
    is_active = cfg.is_active;
    ap  = new("ap", this);
    mon = axi_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = axi_sequencer::type_id::create("sqr", this);
      drv = axi_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(ap);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass
