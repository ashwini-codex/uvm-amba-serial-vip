// ----------------------------------------------------------------------------
// uart_tests.sv
//   uart_base_test    - build only
//   uart_tx_test      - TX path, random line settings
//   uart_rx_test      - RX path, random line settings
//   uart_err_test     - parity / framing error injection, overrun
//   uart_full_test    - every parity mode x baud bucket, duplex + errors + regs
// Plusargs: +NUM_TXNS=<n> (bytes per phase)
// ----------------------------------------------------------------------------
class uart_base_test extends uvm_test;

  `uvm_component_utils(uart_base_test)

  uart_env     env;
  uart_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = uart_env_cfg::type_id::create("cfg");
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "apb_vif", cfg.apb_cfg.vif))
      `uvm_fatal("TEST", "no virtual apb_if (key \"apb_vif\")")
    if (!uvm_config_db #(virtual uart_if)::get(this, "", "uart_vif", cfg.uart_cfg.vif))
      `uvm_fatal("TEST", "no virtual uart_if (key \"uart_vif\")")
    void'($value$plusargs("NUM_TXNS=%d", cfg.num_txns));
    uvm_config_db #(uart_env_cfg)::set(this, "env*", "cfg", cfg);
    env = uart_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_main();
    repeat (100) @(posedge cfg.apb_cfg.vif.PCLK);
    phase.drop_objection(this);
  endtask

  virtual task run_main();
  endtask

  // Randomize and run a vseq with the given parity mode (0 none, 1 even, 2 odd)
  // and baud bucket (0 fast, 1 mid, 2 slow); -1 = random.
  protected task run_vseq(uart_base_vseq v, int mode = -1, int speed = -1);
    v.num_bytes = cfg.num_txns;
    if (!v.randomize() with {
          (mode == 0) -> (par_en == 0);
          (mode == 1) -> (par_en == 1 && par_odd == 0);
          (mode == 2) -> (par_en == 1 && par_odd == 1);
          (speed == 0) -> div inside {[4:8]};
          (speed == 1) -> div inside {[9:16]};
          (speed == 2) -> div inside {[17:40]};
        })
      `uvm_error("TEST", "vseq randomize failed")
    v.start(env.vsqr);
  endtask

  virtual function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    if (errs == 0) `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
    else           `uvm_info("TEST", $sformatf("*** TEST FAILED (%0d errors) ***", errs), UVM_NONE)
  endfunction

endclass


class uart_tx_test extends uart_base_test;
  `uvm_component_utils(uart_tx_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    uart_tx_vseq v = uart_tx_vseq::type_id::create("v");
    repeat (3) run_vseq(v);
  endtask
endclass


class uart_rx_test extends uart_base_test;
  `uvm_component_utils(uart_rx_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    uart_rx_vseq v = uart_rx_vseq::type_id::create("v");
    repeat (3) run_vseq(v);
  endtask
endclass


class uart_err_test extends uart_base_test;
  `uvm_component_utils(uart_err_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    uart_err_vseq     e = uart_err_vseq::type_id::create("e");
    uart_overrun_vseq o = uart_overrun_vseq::type_id::create("o");
    for (int m = 0; m < 3; m++) run_vseq(e, m);
    run_vseq(o);
  endtask
endclass


class uart_full_test extends uart_base_test;
  `uvm_component_utils(uart_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    uart_reg_vseq     r = uart_reg_vseq::type_id::create("r");
    uart_duplex_vseq  d = uart_duplex_vseq::type_id::create("d");
    uart_err_vseq     e = uart_err_vseq::type_id::create("e");
    uart_overrun_vseq o = uart_overrun_vseq::type_id::create("o");
    run_vseq(r);
    for (int m = 0; m < 3; m++)
      for (int s = 0; s < 3; s++)
        run_vseq(d, m, s);
    for (int m = 0; m < 3; m++) run_vseq(e, m);
    run_vseq(o);
  endtask
endclass
