// ============================================================================
// axi_tests.sv  --  directed and random tests
//
//   axi_single_test  single-beat writes + readback
//   axi_burst_test   len x size x burst sweep, then each burst type at random
//   axi_rand_test    long random mix (5% out of range) + strobed writes;
//                    the one-run coverage-closure test
//   axi_err_test     out-of-range / alias checks, then a 30% error random mix
// ============================================================================

class axi_single_test extends axi_base_test;
  `uvm_component_utils(axi_single_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_cfg(axi_env_cfg c);
    c.num_txns = 100;
  endfunction

  virtual task run_seqs();
    axi_single_beat_seq seq;
    seq = axi_single_beat_seq::type_id::create("seq");
    seq.start(env.agt.sqr);
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_burst_test extends axi_base_test;
  `uvm_component_utils(axi_burst_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_cfg(axi_env_cfg c);
    c.num_txns = 40;
  endfunction

  virtual task run_seqs();
    axi_len_size_sweep_seq sweep;
    axi_burst_type_seq     bseq;
    axi_burst_e            kinds[3];
    kinds[0] = AXI_FIXED;
    kinds[1] = AXI_INCR;
    kinds[2] = AXI_WRAP;

    sweep = axi_len_size_sweep_seq::type_id::create("sweep");
    sweep.start(env.agt.sqr);

    foreach (kinds[k]) begin
      bseq = axi_burst_type_seq::type_id::create($sformatf("bseq_%s", kinds[k].name()));
      bseq.burst_kind = kinds[k];
      bseq.start(env.agt.sqr);
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_rand_test extends axi_base_test;
  `uvm_component_utils(axi_rand_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_cfg(axi_env_cfg c);
    c.num_txns = 1500;
    c.err_pct  = 5;
  endfunction

  virtual task run_seqs();
    axi_rand_mix_seq mix;
    axi_strobe_seq   strb;
    mix = axi_rand_mix_seq::type_id::create("mix");
    mix.start(env.agt.sqr);
    strb = axi_strobe_seq::type_id::create("strb");
    strb.n_txns = 100;
    strb.start(env.agt.sqr);
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_err_test extends axi_base_test;
  `uvm_component_utils(axi_err_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void configure_cfg(axi_env_cfg c);
    c.num_txns = 100;
    c.err_pct  = 30;
  endfunction

  virtual task run_seqs();
    axi_err_seq      eseq;
    axi_rand_mix_seq mix;
    eseq = axi_err_seq::type_id::create("eseq");
    eseq.start(env.agt.sqr);
    mix = axi_rand_mix_seq::type_id::create("mix");
    mix.n_txns = 300;
    mix.start(env.agt.sqr);
  endtask
endclass
