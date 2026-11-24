// ============================================================================
// axi_scoreboard.sv  --  reference memory model + checker
//
// Keeps a byte-addressed copy of the 4 KB memory (reset to 0, like axi_mem).
// Writes: apply WSTRB lanes at the FIXED/INCR/WRAP beat address, check BRESP
//         and BID.
// Reads:  check the beat count, RRESP and RID of every beat, and compare the
//         active byte lanes of every OKAY beat against the model.
// Out-of-range beats must return SLVERR and must not change the memory.
// ============================================================================
class axi_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(axi_scoreboard)

  uvm_analysis_imp #(axi_seq_item, axi_scoreboard) item_imp;

  bit [7:0] ref_mem [AXI_MEM_BYTES];

  // transaction-level results
  int unsigned n_wr, n_rd, n_match, n_mismatch;
  // detail counters
  int unsigned n_beats_ok, n_beats_bad;   // R data beats compared
  int unsigned n_resp_bad, n_id_bad, n_len_bad, n_strb_bad;
  int unsigned n_err_wr, n_err_rd;        // transactions that expected SLVERR

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    item_imp = new("item_imp", this);
    foreach (ref_mem[i]) ref_mem[i] = 8'h00;
  endfunction

  function void write(axi_seq_item t);
    bit ok;
    if (t.rw == AXI_WRITE) begin
      n_wr++;
      ok = check_write(t);
    end else begin
      n_rd++;
      ok = check_read(t);
    end
    if (ok) n_match++;
    else    n_mismatch++;
  endfunction

  // --------------------------------------------------------------------------
  function bit check_write(axi_seq_item t);
    bit          ok = 1'b1;
    bit          any_oor = 1'b0;
    bit [31:0]   a, word;
    bit [3:0]    m;
    axi_resp_e   exp_resp;
    int unsigned beats;

    if (t.data.size() != t.len + 1) begin
      `uvm_error("SB", $sformatf("write beat count %0d != AWLEN+1 (%0d): %s",
                                 t.data.size(), t.len + 1, t.convert2string()))
      n_len_bad++;
      ok = 1'b0;
    end
    beats = t.data.size();

    for (int unsigned n = 0; n < beats; n++) begin
      a = axi_beat_addr(t.addr, t.size, t.len, t.burst, n);
      m = axi_lane_mask(a, t.size);
      if ((t.strb[n] & ~m) != 0) begin
        `uvm_error("SB", $sformatf("W[%0d] WSTRB=%04b strobes lanes outside the beat (active %04b) at 0x%08h",
                                   n, t.strb[n], m, a))
        n_strb_bad++;
        ok = 1'b0;
      end
      if (!axi_addr_in_range(a)) begin
        any_oor = 1'b1;
        continue;                          // out of range: memory must not change
      end
      word = a & ~32'd3;
      for (int lane = 0; lane < AXI_DATA_BYTES; lane++)
        if (t.strb[n][lane]) ref_mem[word + lane] = t.data[n][8*lane +: 8];
    end

    if (any_oor) n_err_wr++;
    exp_resp = any_oor ? AXI_SLVERR : AXI_OKAY;
    if (t.bresp != exp_resp) begin
      `uvm_error("SB", $sformatf("BRESP=%s expected %s: %s",
                                 t.bresp.name(), exp_resp.name(), t.convert2string()))
      n_resp_bad++;
      ok = 1'b0;
    end
    if (t.bid != t.id) begin
      `uvm_error("SB", $sformatf("BID=%0h does not echo AWID=%0h", t.bid, t.id))
      n_id_bad++;
      ok = 1'b0;
    end
    `uvm_info("SB", {"write applied: ", t.convert2string()}, UVM_HIGH)
    return ok;
  endfunction

  // --------------------------------------------------------------------------
  function bit check_read(axi_seq_item t);
    bit          ok = 1'b1;
    bit          any_oor = 1'b0;
    bit [31:0]   a, word;
    bit [3:0]    m;
    bit [7:0]    exp_b, got_b;
    axi_resp_e   exp_resp;
    int unsigned beats;
    bit          beat_ok;

    if (t.data.size() != t.len + 1) begin
      `uvm_error("SB", $sformatf("read returned %0d beats, ARLEN+1 = %0d: %s",
                                 t.data.size(), t.len + 1, t.convert2string()))
      n_len_bad++;
      ok = 1'b0;
    end
    beats = (t.data.size() < t.len + 1) ? t.data.size() : t.len + 1;

    for (int unsigned n = 0; n < beats; n++) begin
      a        = axi_beat_addr(t.addr, t.size, t.len, t.burst, n);
      exp_resp = axi_addr_in_range(a) ? AXI_OKAY : AXI_SLVERR;
      if (exp_resp == AXI_SLVERR) any_oor = 1'b1;

      if (t.rresp[n] != exp_resp) begin
        `uvm_error("SB", $sformatf("R[%0d] addr=0x%08h RRESP=%s expected %s",
                                   n, a, t.rresp[n].name(), exp_resp.name()))
        n_resp_bad++;
        ok = 1'b0;
      end
      if (t.rid[n] != t.id) begin
        `uvm_error("SB", $sformatf("R[%0d] RID=%0h does not echo ARID=%0h", n, t.rid[n], t.id))
        n_id_bad++;
        ok = 1'b0;
      end
      if (exp_resp != AXI_OKAY) continue;  // no data check on error beats

      m       = axi_lane_mask(a, t.size);
      word    = a & ~32'd3;
      beat_ok = 1'b1;
      for (int lane = 0; lane < AXI_DATA_BYTES; lane++) begin
        if (!m[lane]) continue;
        exp_b = ref_mem[word + lane];
        got_b = t.data[n][8*lane +: 8];
        if (got_b != exp_b) begin
          `uvm_error("SB", $sformatf("R[%0d] addr=0x%08h lane %0d: got 0x%02h expected 0x%02h (id=%0h len=%0d size=%0dB burst=%s)",
                                     n, word + lane, lane, got_b, exp_b,
                                     t.id, t.len, 1 << t.size, t.burst.name()))
          beat_ok = 1'b0;
        end
      end
      if (beat_ok) n_beats_ok++;
      else begin
        n_beats_bad++;
        ok = 1'b0;
      end
    end
    if (any_oor) n_err_rd++;
    `uvm_info("SB", {"read checked: ", t.convert2string()}, UVM_HIGH)
    return ok;
  endfunction

  // --------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    string s;
    s = "\n---------------- AXI scoreboard ----------------";
    s = {s, $sformatf("\n  transactions : %0d writes, %0d reads", n_wr, n_rd)};
    s = {s, $sformatf("\n  match        : %0d", n_match)};
    s = {s, $sformatf("\n  mismatch     : %0d", n_mismatch)};
    s = {s, $sformatf("\n  R data beats : %0d ok, %0d bad", n_beats_ok, n_beats_bad)};
    s = {s, $sformatf("\n  resp errors  : %0d   id errors: %0d   len errors: %0d   strb errors: %0d",
                      n_resp_bad, n_id_bad, n_len_bad, n_strb_bad)};
    s = {s, $sformatf("\n  SLVERR txns  : %0d writes, %0d reads", n_err_wr, n_err_rd)};
    s = {s, "\n------------------------------------------------"};
    `uvm_info("SB", s, UVM_NONE)
    if (n_wr + n_rd == 0)
      `uvm_error("SB", "scoreboard saw no transactions")
    if (n_mismatch != 0)
      `uvm_error("SB", $sformatf("%0d of %0d transactions mismatched", n_mismatch, n_wr + n_rd))
  endfunction

endclass
