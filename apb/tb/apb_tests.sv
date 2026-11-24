// ----------------------------------------------------------------------------
// apb_tests.sv : tests for the APB memory bench
//   apb_base_test   - builds env + config, runs nothing (smoke / build check)
//   apb_rw_test     - write-then-read and corner cases
//   apb_rand_test   - random mix + back-to-back
//   apb_err_test    - out-of-range accesses (PSLVERR)
//   apb_full_test   - everything above (default regression / coverage run)
// Plusargs: +NUM_TXNS=<n>
// ----------------------------------------------------------------------------
class apb_base_test extends uvm_test;

  `uvm_component_utils(apb_base_test)

  apb_env     env;
  apb_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = apb_env_cfg::type_id::create("cfg");

    // Virtual interface from tb_top -> config object.
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "apb_vif", cfg.apb_cfg.vif))
      `uvm_fatal("TEST", "no virtual apb_if in config_db (key \"apb_vif\")")
    cfg.apb_cfg.is_active = UVM_ACTIVE;

    // Test settings from the command line.
    void'($value$plusargs("NUM_TXNS=%d", cfg.num_txns));
    configure(cfg);

    uvm_config_db #(apb_env_cfg)::set(this, "env*", "cfg", cfg);
    env = apb_env::type_id::create("env", this);
  endfunction

  // Hook for derived tests to tweak settings.
  virtual function void configure(apb_env_cfg c);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_main();
    repeat (10) @(posedge cfg.apb_cfg.vif.PCLK);
    phase.drop_objection(this);
  endtask

  virtual task run_main();
  endtask

  // Helper to start any memory sequence with the configured settings.
  protected task run_seq(apb_mem_base_seq s, int unsigned n);
    s.num_txns  = n;
    s.mem_bytes = cfg.mem_bytes;
    s.start(env.agent.sqr);
  endtask

  virtual function void report_phase(uvm_phase phase);
    uvm_report_server rs = uvm_report_server::get_server();
    int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    if (errs == 0) `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
    else           `uvm_info("TEST", $sformatf("*** TEST FAILED (%0d errors) ***", errs), UVM_NONE)
  endfunction

endclass


class apb_rw_test extends apb_base_test;
  `uvm_component_utils(apb_rw_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual task run_main();
    apb_wr_rd_seq  wr_rd  = apb_wr_rd_seq::type_id::create("wr_rd");
    apb_corner_seq corner = apb_corner_seq::type_id::create("corner");
    run_seq(corner, 0);
    run_seq(wr_rd, cfg.num_txns / 2);
  endtask
endclass


class apb_rand_test extends apb_base_test;
  `uvm_component_utils(apb_rand_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual task run_main();
    apb_rand_seq rnd = apb_rand_seq::type_id::create("rnd");
    apb_b2b_seq  b2b = apb_b2b_seq::type_id::create("b2b");
    run_seq(rnd, cfg.num_txns);
    run_seq(b2b, cfg.num_txns / 4);
  endtask
endclass


class apb_err_test extends apb_base_test;
  `uvm_component_utils(apb_err_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual task run_main();
    apb_err_seq err = apb_err_seq::type_id::create("err");
    run_seq(err, cfg.num_txns / 2);
  endtask
endclass


class apb_full_test extends apb_base_test;
  `uvm_component_utils(apb_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual task run_main();
    apb_corner_seq corner = apb_corner_seq::type_id::create("corner");
    apb_wr_rd_seq  wr_rd  = apb_wr_rd_seq::type_id::create("wr_rd");
    apb_rand_seq   rnd    = apb_rand_seq::type_id::create("rnd");
    apb_b2b_seq    b2b    = apb_b2b_seq::type_id::create("b2b");
    apb_err_seq    err    = apb_err_seq::type_id::create("err");
    run_seq(corner, 0);
    run_seq(wr_rd,  cfg.num_txns / 2);
    run_seq(rnd,    cfg.num_txns);
    run_seq(b2b,    cfg.num_txns / 4);
    run_seq(err,    cfg.num_txns / 4);
    run_seq(rnd,    cfg.num_txns / 2);
  endtask
endclass
