// ----------------------------------------------------------------------------
// i2c_agent.sv : I2C slave agent
// ----------------------------------------------------------------------------
typedef uvm_sequencer #(i2c_seq_item) i2c_sequencer;

class i2c_agent extends uvm_agent;

  `uvm_component_utils(i2c_agent)

  i2c_agent_cfg                     cfg;
  i2c_sequencer                     sqr;
  i2c_slave_driver                  drv;
  i2c_monitor                       mon;
  uvm_analysis_port #(i2c_bus_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(i2c_agent_cfg)::get(this, "", "i2c_cfg", cfg))
      `uvm_fatal("I2C_AGT", "no i2c_agent_cfg in config_db (key \"i2c_cfg\")")
    if (cfg.vif == null)
      `uvm_fatal("I2C_AGT", "i2c_agent_cfg.vif is null")

    is_active = cfg.is_active;
    ap  = new("ap", this);
    mon = i2c_monitor::type_id::create("mon", this);
    if (is_active == UVM_ACTIVE) begin
      sqr = i2c_sequencer::type_id::create("sqr", this);
      drv = i2c_slave_driver::type_id::create("drv", this);
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
