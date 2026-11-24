// ----------------------------------------------------------------------------
// apb_agent_cfg.sv : per-agent settings, handed down through uvm_config_db
// ----------------------------------------------------------------------------
class apb_agent_cfg extends uvm_object;

  virtual apb_if             vif;
  uvm_active_passive_enum    is_active = UVM_ACTIVE;

  `uvm_object_utils(apb_agent_cfg)

  function new(string name = "apb_agent_cfg");
    super.new(name);
  endfunction

endclass
