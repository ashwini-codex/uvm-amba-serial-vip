// ============================================================================
// axi_base_test.sv  --  base test: builds cfg + env, runs a short random mix
//
// Plusargs (override the per-test defaults):
//   +NUM_TXNS=<n>   transactions per sequence
//   +ERR_PCT=<n>    % out-of-range transactions in axi_rand_mix_seq
//   +ZERO_DELAY     master drives with no VALID/READY delays
// ============================================================================
class axi_base_test extends uvm_test;

  `uvm_component_utils(axi_base_test)

  axi_env     env;
  axi_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // derived tests set their knobs here
  virtual function void configure_cfg(axi_env_cfg c);
  endfunction

  function void build_phase(uvm_phase phase);
    int unsigned n;
    super.build_phase(phase);
    cfg = axi_env_cfg::type_id::create("cfg");
    configure_cfg(cfg);
    if ($value$plusargs("NUM_TXNS=%d", n)) cfg.num_txns = n;
    if ($value$plusargs("ERR_PCT=%d", n))  cfg.err_pct  = n;
    if ($test$plusargs("ZERO_DELAY"))      cfg.zero_delay = 1'b1;
    uvm_config_db#(axi_env_cfg)::set(this, "env*", "cfg", cfg);
    env = axi_env::type_id::create("env", this);
    uvm_root::get().set_timeout(200ms, 1);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    `uvm_info("TEST", {"cfg: ", cfg.convert2string()}, UVM_LOW)
    uvm_root::get().print_topology();
  endfunction

  // derived tests override this
  virtual task run_seqs();
    axi_rand_mix_seq seq;
    seq = axi_rand_mix_seq::type_id::create("seq");
    seq.start(env.agt.sqr);
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    run_seqs();
    #100ns;                       // let the last response reach the scoreboard
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server svr;
    int unsigned      n_err;
    super.report_phase(phase);
    svr   = uvm_report_server::get_server();
    n_err = svr.get_severity_count(UVM_ERROR) + svr.get_severity_count(UVM_FATAL);
    if (n_err == 0) begin
      `uvm_info("TEST", $sformatf("*** %s PASSED ***", get_type_name()), UVM_NONE)
    end else begin
      `uvm_info("TEST", $sformatf("*** %s FAILED: %0d UVM_ERROR/UVM_FATAL ***",
                                  get_type_name(), n_err), UVM_NONE)
    end
  endfunction

endclass
