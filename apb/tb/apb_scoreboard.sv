// ----------------------------------------------------------------------------
// apb_scoreboard.sv : reference memory model.
//   writes  -> update the model
//   reads   -> compare PRDATA against the model (unwritten words read as 0)
//   PSLVERR -> must be set exactly when the address is out of range
// ----------------------------------------------------------------------------
class apb_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(apb_scoreboard)

  uvm_analysis_imp #(apb_seq_item, apb_scoreboard) imp;

  bit [31:0]  mem_bytes = 32'h400;
  bit [31:0]  ref_mem [bit [29:0]];

  int unsigned n_writes, n_reads, n_match, n_mismatch, n_err_ok, n_err_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
  endfunction

  virtual function void write(apb_seq_item tr);
    bit        in_range = (tr.addr < mem_bytes);
    bit [29:0] idx      = tr.addr[31:2];
    bit [31:0] exp;

    // Error response check
    if (tr.slverr != !in_range) begin
      n_err_bad++;
      `uvm_error("APB_SB", $sformatf("PSLVERR=%0b but address 0x%08h is %s range",
                 tr.slverr, tr.addr, in_range ? "in" : "out of"))
    end
    else if (!in_range) begin
      n_err_ok++;
    end
    if (!in_range) return;

    if (tr.write) begin
      n_writes++;
      ref_mem[idx] = tr.data;
    end
    else begin
      n_reads++;
      exp = ref_mem.exists(idx) ? ref_mem[idx] : 32'h0;
      if (tr.data === exp) begin
        n_match++;
      end
      else begin
        n_mismatch++;
        `uvm_error("APB_SB", $sformatf("read 0x%08h: got 0x%08h expected 0x%08h",
                   tr.addr, tr.data, exp))
      end
    end
  endfunction

  virtual function void check_phase(uvm_phase phase);
    if ((n_writes + n_reads + n_err_ok + n_err_bad) == 0)
      `uvm_error("APB_SB", "scoreboard saw no transactions")
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("APB_SB", $sformatf(
      "writes=%0d reads=%0d match=%0d mismatch=%0d slverr_ok=%0d slverr_bad=%0d",
      n_writes, n_reads, n_match, n_mismatch, n_err_ok, n_err_bad), UVM_LOW)
  endfunction

endclass
