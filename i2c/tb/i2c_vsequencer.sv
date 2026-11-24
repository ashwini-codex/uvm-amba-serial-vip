// ----------------------------------------------------------------------------
// i2c_vsequencer.sv : virtual sequencer holding the APB and I2C sequencers
// ----------------------------------------------------------------------------
class i2c_vsequencer extends uvm_sequencer;

  `uvm_component_utils(i2c_vsequencer)

  apb_sequencer apb_sqr;
  i2c_sequencer i2c_sqr;
  i2c_env_cfg   cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
