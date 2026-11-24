// ----------------------------------------------------------------------------
// i2c_agent_cfg.sv : I2C slave agent settings
// ----------------------------------------------------------------------------
class i2c_agent_cfg extends uvm_object;

  virtual i2c_if           vif;
  uvm_active_passive_enum  is_active  = UVM_ACTIVE;
  bit [6:0]                slave_addr = I2C_SLV_ADDR;

  `uvm_object_utils(i2c_agent_cfg)

  function new(string name = "i2c_agent_cfg");
    super.new(name);
  endfunction

endclass
