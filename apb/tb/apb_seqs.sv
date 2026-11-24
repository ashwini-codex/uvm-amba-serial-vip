// ----------------------------------------------------------------------------
// apb_seqs.sv : constrained-random sequences for the APB memory bench
// All sequences run on the APB agent's sequencer.
// ----------------------------------------------------------------------------
class apb_mem_base_seq extends uvm_sequence #(apb_seq_item);

  `uvm_object_utils(apb_mem_base_seq)

  int unsigned num_txns  = 50;
  bit [31:0]   mem_bytes = 32'h400;

  function new(string name = "apb_mem_base_seq");
    super.new(name);
  endfunction

endclass


// Write a random word to a random valid address, then read it back.
class apb_wr_rd_seq extends apb_mem_base_seq;

  `uvm_object_utils(apb_wr_rd_seq)

  function new(string name = "apb_wr_rd_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item wr, rd;
    repeat (num_txns) begin
      wr = apb_seq_item::type_id::create("wr");
      start_item(wr);
      if (!wr.randomize() with { write == 1'b1; addr < mem_bytes; })
        `uvm_error("SEQ", "randomize failed")
      finish_item(wr);

      rd = apb_seq_item::type_id::create("rd");
      start_item(rd);
      if (!rd.randomize() with { write == 1'b0; addr == wr.addr; })
        `uvm_error("SEQ", "randomize failed")
      finish_item(rd);
    end
  endtask

endclass


// Back-to-back transfers (no idle cycles between them), mixed direction.
class apb_b2b_seq extends apb_mem_base_seq;

  `uvm_object_utils(apb_b2b_seq)

  function new(string name = "apb_b2b_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item it;
    repeat (num_txns) begin
      it = apb_seq_item::type_id::create("it");
      start_item(it);
      if (!it.randomize() with { idle_cycles == 0; addr < mem_bytes; })
        `uvm_error("SEQ", "randomize failed")
      finish_item(it);
    end
  endtask

endclass


// Fully random mix over the valid range, weighted toward reads after writes
// by keeping the address pool small so reads hit written words.
class apb_rand_seq extends apb_mem_base_seq;

  `uvm_object_utils(apb_rand_seq)

  rand bit [31:0] pool [8];

  constraint c_pool {
    foreach (pool[i]) { pool[i] < mem_bytes; pool[i][1:0] == 2'b00; }
  }

  function new(string name = "apb_rand_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item it;
    bit          ok;
    if (!this.randomize()) `uvm_error("SEQ", "pool randomize failed")
    repeat (num_txns) begin
      it = apb_seq_item::type_id::create("it");
      start_item(it);
      // Half the time pick from the small pool so reads hit written data.
      if ($urandom_range(1, 0))
        ok = it.randomize() with { addr inside {pool}; };
      else
        ok = it.randomize() with {
               addr dist { [32'h000 : 32'h0FC] :/ 30,
                           [32'h100 : 32'h2FC] :/ 30,
                           [32'h300 : 32'h3FC] :/ 30 };
               addr < mem_bytes;
             };
      if (!ok) `uvm_error("SEQ", "randomize failed")
      finish_item(it);
    end
  endtask

endclass


// Corner cases: first/last word, all-zeros/all-ones data.
class apb_corner_seq extends apb_mem_base_seq;

  `uvm_object_utils(apb_corner_seq)

  function new(string name = "apb_corner_seq");
    super.new(name);
  endfunction

  virtual task body();
    bit [31:0] addrs [2];
    bit [31:0] datas [3];
    apb_seq_item it;
    addrs = '{32'h000, mem_bytes - 4};
    datas = '{32'h0000_0000, 32'hFFFF_FFFF, 32'hA5A5_5A5A};
    foreach (addrs[a]) begin
      foreach (datas[d]) begin
        it = apb_seq_item::type_id::create("it");
        start_item(it);
        if (!it.randomize() with { write == 1'b1; addr == addrs[a]; data == datas[d]; })
          `uvm_error("SEQ", "randomize failed")
        finish_item(it);
        it = apb_seq_item::type_id::create("it");
        start_item(it);
        if (!it.randomize() with { write == 1'b0; addr == addrs[a]; })
          `uvm_error("SEQ", "randomize failed")
        finish_item(it);
      end
    end
  endtask

endclass


// Out-of-range accesses that must return PSLVERR; interleaved with valid ones.
class apb_err_seq extends apb_mem_base_seq;

  `uvm_object_utils(apb_err_seq)

  function new(string name = "apb_err_seq");
    super.new(name);
  endfunction

  virtual task body();
    apb_seq_item it;
    // The first invalid word, so the boundary bin is always hit.
    it = apb_seq_item::type_id::create("it");
    start_item(it);
    if (!it.randomize() with { addr == mem_bytes; })
      `uvm_error("SEQ", "randomize failed")
    finish_item(it);

    repeat (num_txns) begin
      it = apb_seq_item::type_id::create("it");
      start_item(it);
      if (!it.randomize() with {
            addr dist { [32'h0000_0000 : mem_bytes - 4] :/ 50,
                        [mem_bytes : 32'hFFFF_FFFC]    :/ 50 };
          })
        `uvm_error("SEQ", "randomize failed")
      finish_item(it);
    end
  endtask

endclass
