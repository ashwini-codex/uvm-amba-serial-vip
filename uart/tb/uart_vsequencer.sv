// ----------------------------------------------------------------------------
// uart_vsequencer.sv : virtual sequencer holding the APB and UART sequencers
// ----------------------------------------------------------------------------
class uart_vsequencer extends uvm_sequencer;

  `uvm_component_utils(uart_vsequencer)

  apb_sequencer  apb_sqr;
  uart_sequencer uart_sqr;
  uart_env_cfg   cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass
