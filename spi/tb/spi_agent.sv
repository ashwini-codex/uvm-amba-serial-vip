// ----------------------------------------------------------------------------
// spi_agent.sv : SPI slave agent
// ----------------------------------------------------------------------------
typedef uvm_sequencer #(spi_seq_item) spi_sequencer;

class spi_agent extends uvm_agent;

  `uvm_component_utils(spi_agent)

  spi_agent_cfg                     cfg;
  spi_sequencer                     sqr;
  spi_driver                        drv;
  spi_monitor                       mon;
  uvm_analysis_port #(spi_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(spi_agent_cfg)::get(this, "", "spi_cfg", cfg))
      `uvm_fatal("SPI_AGT", "no spi_agent_cfg in config_db (key \"spi_cfg\")")
    if (cfg.vif == null)
      `uvm_fatal("SPI_AGT", "spi_agent_cfg.vif is null")

    is_active = cfg.is_active;
    ap  = new("ap", this);
    mon = spi_monitor::type_id::create("mon", this);
    if (is_active == UVM_ACTIVE) begin
      sqr = spi_sequencer::type_id::create("sqr", this);
      drv = spi_driver::type_id::create("drv", this);
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
