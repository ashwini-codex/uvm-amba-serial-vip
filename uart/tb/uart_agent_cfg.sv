// ----------------------------------------------------------------------------
// uart_agent_cfg.sv : UART agent settings. The virtual sequence updates the
// line settings whenever it reprograms the DUT, so driver and monitor follow.
// ----------------------------------------------------------------------------
class uart_agent_cfg extends uvm_object;

  virtual uart_if          vif;
  uvm_active_passive_enum  is_active = UVM_ACTIVE;

  int unsigned div     = 16;    // clk cycles per bit (DUT reset value)
  bit          par_en  = 1'b0;
  bit          par_odd = 1'b0;

  `uvm_object_utils(uart_agent_cfg)

  function new(string name = "uart_agent_cfg");
    super.new(name);
  endfunction

  function bit parity(bit [7:0] d);
    return (^d) ^ par_odd;
  endfunction

endclass
