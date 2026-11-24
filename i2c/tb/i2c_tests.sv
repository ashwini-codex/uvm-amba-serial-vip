// ----------------------------------------------------------------------------
// i2c_tests.sv
//   i2c_base_test   - build only (slave responder running)
//   i2c_wr_rd_test  - write blocks and read them back; slave never NACKs/stretches
//   i2c_rand_test   - random transactions, random NACK + clock stretching
//   i2c_full_test   - registers + wr/rd at every speed + random mix
// Plusargs: +NUM_TXNS=<n> (transactions per phase)
// ----------------------------------------------------------------------------
class i2c_base_test extends uvm_test;

  `uvm_component_utils(i2c_base_test)

  i2c_env     env;
  i2c_env_cfg cfg;
  i2c_rsp_seq rsp;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = i2c_env_cfg::type_id::create("cfg");
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "apb_vif", cfg.apb_cfg.vif))
      `uvm_fatal("TEST", "no virtual apb_if (key \"apb_vif\")")
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "i2c_vif", cfg.i2c_cfg.vif))
      `uvm_fatal("TEST", "no virtual i2c_if (key \"i2c_vif\")")
    void'($value$plusargs("NUM_TXNS=%d", cfg.num_txns));
    uvm_config_db #(i2c_env_cfg)::set(this, "env*", "cfg", cfg);
    env = i2c_env::type_id::create("env", this);
    rsp = i2c_rsp_seq::type_id::create("rsp");
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    fork
      rsp.start(env.i2c_agt.sqr);    // slave behaviour for every transaction
    join_none
    run_main();
    repeat (50) @(posedge cfg.apb_cfg.vif.PCLK);
    phase.drop_objection(this);
  endtask

  virtual task run_main();
  endtask

  // speed: -1 random, 0 fast (1-3), 1 mid (4-7), 2 slow (8-10)
  protected task run_vseq(i2c_base_vseq v, int speed = -1);
    v.num_txns = cfg.num_txns;
    if (!v.randomize() with {
          (speed == 0) -> div inside {[1:3]};
          (speed == 1) -> div inside {[4:7]};
          (speed == 2) -> div inside {[8:10]};
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


class i2c_wr_rd_test extends i2c_base_test;
  `uvm_component_utils(i2c_wr_rd_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rsp.allow_nack    = 1'b0;
    rsp.allow_stretch = 1'b0;
  endfunction

  virtual task run_main();
    i2c_wr_rd_vseq v = i2c_wr_rd_vseq::type_id::create("v");
    run_vseq(v);
  endtask
endclass


class i2c_rand_test extends i2c_base_test;
  `uvm_component_utils(i2c_rand_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual task run_main();
    i2c_rand_vseq v = i2c_rand_vseq::type_id::create("v");
    repeat (3) run_vseq(v);
  endtask
endclass


class i2c_full_test extends i2c_base_test;
  `uvm_component_utils(i2c_full_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual task run_main();
    i2c_reg_vseq   r  = i2c_reg_vseq::type_id::create("r");
    i2c_wr_rd_vseq wr = i2c_wr_rd_vseq::type_id::create("wr");
    i2c_rand_vseq  rn = i2c_rand_vseq::type_id::create("rn");
    run_vseq(r);
    for (int s = 0; s < 3; s++) run_vseq(wr, s);
    for (int s = 0; s < 3; s++) run_vseq(rn, s);
  endtask
endclass
