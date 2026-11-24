// ----------------------------------------------------------------------------
// uart_env_cfg.sv : test settings for the UART bench
// ----------------------------------------------------------------------------
class uart_env_cfg extends uvm_object;

  apb_agent_cfg  apb_cfg;
  uart_agent_cfg uart_cfg;
  bit            has_scoreboard = 1'b1;
  bit            has_coverage   = 1'b1;
  int unsigned   num_txns       = 20;    // bytes per traffic phase, +NUM_TXNS=<n>

  `uvm_object_utils(uart_env_cfg)

  function new(string name = "uart_env_cfg");
    super.new(name);
    apb_cfg  = apb_agent_cfg::type_id::create("apb_cfg");
    uart_cfg = uart_agent_cfg::type_id::create("uart_cfg");
  endfunction

endclass
