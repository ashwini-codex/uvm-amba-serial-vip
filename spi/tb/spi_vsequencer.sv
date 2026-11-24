// ----------------------------------------------------------------------------
// spi_vsequencer.sv : virtual sequencer holding the APB and SPI sequencers
// ----------------------------------------------------------------------------
class spi_vsequencer extends uvm_sequencer;

  `uvm_component_utils(spi_vsequencer)

  apb_sequencer apb_sqr;
  spi_sequencer spi_sqr;
  spi_env_cfg   cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
