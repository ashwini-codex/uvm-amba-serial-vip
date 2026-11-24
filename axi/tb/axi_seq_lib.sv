// ============================================================================
// axi_seq_lib.sv  --  AXI4 sequence library
//
//   axi_base_seq           cfg lookup, item factory, readback helpers
//   axi_single_beat_seq    len = 0 writes, each read back
//   axi_burst_type_seq     one burst type (knob), random len/size, read back;
//                          WRAP writes are also read back as an INCR over the
//                          whole wrap container
//   axi_len_size_sweep_seq every burst x every legal len x every size, read back
//   axi_wr_rd_seq          random write, then read back the same burst
//   axi_rand_mix_seq       random reads/writes, cfg.err_pct out of range,
//                          plus readbacks of recent writes
//   axi_strobe_seq         full-strobe write, then a random-strobe write over
//                          the same burst, then read back
//   axi_err_seq            out-of-range writes aliasing an in-range burst,
//                          SLVERR readback, alias-safety readback, OOR reads
// ============================================================================

class axi_base_seq extends uvm_sequence #(axi_seq_item);

  `uvm_object_utils(axi_base_seq)

  axi_env_cfg  cfg;
  int unsigned n_txns = 0;      // 0: use cfg.num_txns

  function new(string name = "axi_base_seq");
    super.new(name);
  endfunction

  virtual task pre_start();
    if (!uvm_config_db#(axi_env_cfg)::get(m_sequencer, "", "cfg", cfg)) begin
      `uvm_warning("SEQ", "axi_env_cfg not found for this sequencer, using defaults")
      cfg = axi_env_cfg::type_id::create("cfg");
    end
  endtask

  function int unsigned count();
    return (n_txns != 0) ? n_txns : cfg.num_txns;
  endfunction

  function axi_seq_item new_item(string name);
    axi_seq_item t;
    t = axi_seq_item::type_id::create(name);
    t.zero_delay = cfg.zero_delay;
    return t;
  endfunction

  // Read back exactly the burst that wr wrote.
  task readback(axi_seq_item wr);
    axi_seq_item rd;
    bit [31:0]   rb_addr;
    bit [7:0]    rb_len;
    bit [2:0]    rb_size;
    axi_burst_e  rb_burst;
    bit          rb_err;
    rb_addr  = wr.addr;
    rb_len   = wr.len;
    rb_size  = wr.size;
    rb_burst = wr.burst;
    rb_err   = wr.addr_err;
    rd = new_item("rd");
    start_item(rd);
    if (!rd.randomize() with { rw       == AXI_READ;
                               addr     == rb_addr;
                               len      == rb_len;
                               size     == rb_size;
                               burst    == rb_burst;
                               addr_err == rb_err; })
      `uvm_fatal("RAND", "readback randomize() failed")
    finish_item(rd);
  endtask

  // Read a WRAP burst's whole container with an INCR burst of the same
  // len/size starting at the wrap boundary. Catches wrap-address bugs that a
  // same-burst readback would hide (same wrong math on both paths).
  task readback_container(axi_seq_item wr);
    axi_seq_item rd;
    bit [31:0]   total, lower;
    bit [7:0]    rb_len;
    bit [2:0]    rb_size;
    if (wr.burst != AXI_WRAP) return;
    total   = (32'd1 << wr.size) * (wr.len + 32'd1);
    lower   = wr.addr & ~(total - 32'd1);
    rb_len  = wr.len;
    rb_size = wr.size;
    rd = new_item("rd_container");
    start_item(rd);
    if (!rd.randomize() with { rw    == AXI_READ;
                               burst == AXI_INCR;
                               addr  == lower;
                               len   == rb_len;
                               size  == rb_size; })
      `uvm_fatal("RAND", "readback_container randomize() failed")
    finish_item(rd);
  endtask

  virtual task body();
    `uvm_warning("SEQ", "axi_base_seq::body() called; it sends nothing")
  endtask

endclass

// ----------------------------------------------------------------------------
class axi_single_beat_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_beat_seq)
  function new(string name = "axi_single_beat_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item wr;
    repeat (count()) begin
      wr = new_item("wr");
      start_item(wr);
      if (!wr.randomize() with { rw == AXI_WRITE; len == 0; })
        `uvm_fatal("RAND", "single-beat randomize() failed")
      finish_item(wr);
      readback(wr);
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_burst_type_seq extends axi_base_seq;
  `uvm_object_utils(axi_burst_type_seq)
  axi_burst_e burst_kind = AXI_INCR;
  function new(string name = "axi_burst_type_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item wr;
    `uvm_info("SEQ", $sformatf("%0d %s bursts", count(), burst_kind.name()), UVM_LOW)
    repeat (count()) begin
      wr = new_item("wr");
      start_item(wr);
      if (!wr.randomize() with { rw == AXI_WRITE; burst == burst_kind; })
        `uvm_fatal("RAND", "burst-type randomize() failed")
      finish_item(wr);
      readback(wr);
      readback_container(wr);
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_len_size_sweep_seq extends axi_base_seq;
  `uvm_object_utils(axi_len_size_sweep_seq)
  function new(string name = "axi_len_size_sweep_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item wr;
    axi_burst_e  bursts[3];
    axi_burst_e  sw_burst;
    bit [2:0]    sw_size;
    bit [7:0]    sw_len;
    bursts[0] = AXI_FIXED;
    bursts[1] = AXI_INCR;
    bursts[2] = AXI_WRAP;
    foreach (bursts[b]) begin
      for (int s = 0; s <= 2; s++) begin
        for (int l = 0; l <= 15; l++) begin
          if (bursts[b] == AXI_WRAP && !(l inside {1, 3, 7, 15})) continue;
          sw_burst = bursts[b];
          sw_size  = s;
          sw_len   = l;
          wr = new_item("wr");
          start_item(wr);
          if (!wr.randomize() with { rw    == AXI_WRITE;
                                     burst == sw_burst;
                                     size  == sw_size;
                                     len   == sw_len; })
            `uvm_fatal("RAND", "sweep randomize() failed")
          finish_item(wr);
          readback(wr);
          readback_container(wr);
        end
      end
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_wr_rd_seq extends axi_base_seq;
  `uvm_object_utils(axi_wr_rd_seq)
  function new(string name = "axi_wr_rd_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item wr;
    repeat (count()) begin
      wr = new_item("wr");
      start_item(wr);
      if (!wr.randomize() with { rw == AXI_WRITE; })
        `uvm_fatal("RAND", "wr_rd randomize() failed")
      finish_item(wr);
      readback(wr);
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_rand_mix_seq extends axi_base_seq;
  `uvm_object_utils(axi_rand_mix_seq)
  int unsigned readback_pct = 25;   // % of slots spent re-reading a recent write
  function new(string name = "axi_rand_mix_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item t;
    axi_seq_item hist[$];
    bit          e;
    `uvm_info("SEQ", $sformatf("%0d random txns, err_pct=%0d", count(), cfg.err_pct), UVM_LOW)
    repeat (count()) begin
      if (hist.size() != 0 && $urandom_range(99) < readback_pct) begin
        readback(hist[$urandom_range(hist.size() - 1)]);
        continue;
      end
      e = ($urandom_range(99) < cfg.err_pct);
      t = new_item("t");
      start_item(t);
      if (!t.randomize() with { addr_err == e; })
        `uvm_fatal("RAND", "rand_mix randomize() failed")
      finish_item(t);
      if (t.rw == AXI_WRITE) begin
        hist.push_back(t);
        if (hist.size() > 64) void'(hist.pop_front());
      end
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_strobe_seq extends axi_base_seq;
  `uvm_object_utils(axi_strobe_seq)
  function new(string name = "axi_strobe_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item w_full, w_part;
    bit [31:0]   st_addr;
    bit [7:0]    st_len;
    bit [2:0]    st_size;
    axi_burst_e  st_burst;
    repeat (count()) begin
      w_full = new_item("w_full");
      start_item(w_full);
      if (!w_full.randomize() with { rw == AXI_WRITE; strb_mode == STRB_FULL; })
        `uvm_fatal("RAND", "strobe (full) randomize() failed")
      finish_item(w_full);

      st_addr  = w_full.addr;
      st_len   = w_full.len;
      st_size  = w_full.size;
      st_burst = w_full.burst;
      w_part = new_item("w_part");
      start_item(w_part);
      if (!w_part.randomize() with { rw        == AXI_WRITE;
                                     addr      == st_addr;
                                     len       == st_len;
                                     size      == st_size;
                                     burst     == st_burst;
                                     strb_mode == STRB_RANDOM; })
        `uvm_fatal("RAND", "strobe (partial) randomize() failed")
      finish_item(w_part);

      readback(w_part);   // unstrobed lanes must still hold w_full's data
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class axi_err_seq extends axi_base_seq;
  `uvm_object_utils(axi_err_seq)
  function new(string name = "axi_err_seq");
    super.new(name);
  endfunction

  virtual task body();
    axi_seq_item w_in, w_oor, r_oor;
    bit [19:0]   pg;
    bit [31:0]   al_addr;
    bit [7:0]    al_len;
    bit [2:0]    al_size;
    axi_burst_e  al_burst;
    repeat (count()) begin
      // in-range reference burst
      w_in = new_item("w_in");
      start_item(w_in);
      if (!w_in.randomize() with { rw == AXI_WRITE; addr_err == 0; strb_mode == STRB_FULL; })
        `uvm_fatal("RAND", "err (in-range) randomize() failed")
      finish_item(w_in);

      // same burst with a non-zero page number: must get SLVERR and must not
      // alias onto the in-range bytes
      pg       = $urandom_range(32'h000F_FFFF, 1);
      al_addr  = {pg, w_in.addr[11:0]};
      al_len   = w_in.len;
      al_size  = w_in.size;
      al_burst = w_in.burst;
      w_oor = new_item("w_oor");
      start_item(w_oor);
      if (!w_oor.randomize() with { rw        == AXI_WRITE;
                                    addr_err  == 1;
                                    addr      == al_addr;
                                    len       == al_len;
                                    size      == al_size;
                                    burst     == al_burst;
                                    strb_mode == STRB_FULL; })
        `uvm_fatal("RAND", "err (alias) randomize() failed")
      finish_item(w_oor);

      readback(w_oor);    // SLVERR on every beat
      readback(w_in);     // in-range data unchanged

      // independent random out-of-range read
      r_oor = new_item("r_oor");
      start_item(r_oor);
      if (!r_oor.randomize() with { rw == AXI_READ; addr_err == 1; })
        `uvm_fatal("RAND", "err (read) randomize() failed")
      finish_item(r_oor);
    end
  endtask
endclass
