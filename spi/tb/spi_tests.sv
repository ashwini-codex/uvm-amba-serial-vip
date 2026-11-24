// ----------------------------------------------------------------------------
// spi_tests.sv
//   spi_base_test  - build only (slave responder running)
//   spi_mode_test  - every mode at a random divider
//   spi_rand_test  - random mode + divider, several rounds
//   spi_full_test  - registers + every mode x every divider bucket
// Plusargs: +NUM_TXNS=<n> (transfers per phase)
// ----------------------------------------------------------------------------
class spi_base_test extends uvm_test;

  `uvm_component_utils(spi_base_test)

  spi_env     env;
  spi_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = spi_env_cfg::type_id::create("cfg");
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "apb_vif", cfg.apb_cfg.vif))
      `uvm_fatal("TEST", "no virtual apb_if (key \"apb_vif\")")
    if (!uvm_config_db #(virtual spi_if)::get(this, "", "spi_vif", cfg.spi_cfg.vif))
      `uvm_fatal("TEST", "no virtual spi_if (key \"spi_vif\")")
    void'($value$plusargs("NUM_TXNS=%d", cfg.num_txns));
    uvm_config_db #(spi_env_cfg)::set(this, "env*", "cfg", cfg);
    env = spi_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    spi_rsp_seq rsp = spi_rsp_seq::type_id::create("rsp");
    phase.raise_objection(this);
    fork
      rsp.start(env.spi_agt.sqr);    // slave answers every transfer, never ends
    join_none
    run_main();
    repeat (50) @(posedge cfg.apb_cfg.vif.PCLK);
    phase.drop_objection(this);
  endtask

  virtual task run_main();
  endtask

  // mode: -1 random, else 0..3 = {cpol,cpha}; speed: -1 random, 0 = 2, 1 = 3, 2 = 4..7, 3 = 8..16
  protected task run_vseq(spi_base_vseq v, int mode = -1, int speed = -1);
    v.num_xfers = cfg.num_txns;
    if (!v.randomize() with {
          (mode >= 0) -> ({cpol, cpha} == mode[1:0]);
          (speed == 0) -> (div == 2);
          (speed == 1) -> (div == 3);
          (speed == 2) -> (div inside {[4:7]});
          (speed == 3) -> (div inside {[8:16]});
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


class spi_mode_test extends spi_base_test;
  `uvm_component_utils(spi_mode_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    spi_xfer_vseq v = spi_xfer_vseq::type_id::create("v");
    for (int m = 0; m < 4; m++) run_vseq(v, m);
  endtask
endclass


class spi_rand_test extends spi_base_test;
  `uvm_component_utils(spi_rand_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    spi_xfer_vseq v = spi_xfer_vseq::type_id::create("v");
    repeat (8) run_vseq(v);
  endtask
endclass


class spi_full_test extends spi_base_test;
  `uvm_component_utils(spi_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_main();
    spi_reg_vseq  r = spi_reg_vseq::type_id::create("r");
    spi_xfer_vseq v = spi_xfer_vseq::type_id::create("v");
    run_vseq(r);
    for (int m = 0; m < 4; m++)
      for (int s = 0; s < 4; s++)
        run_vseq(v, m, s);
  endtask
endclass
