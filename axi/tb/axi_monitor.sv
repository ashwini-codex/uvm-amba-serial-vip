// ============================================================================
// axi_monitor.sv  --  passive AXI4 monitor
//
// Samples all five channels on every clock through mon_cb and assembles
//   write transactions = AW + W beats + B   (published at the B handshake)
//   read  transactions = AR + R beats       (published at the RLAST handshake)
// It also records how many cycles each VALID waited for READY.
// Assumes in-order responses (one outstanding write and one outstanding
// read, as with axi_mem).
// ============================================================================
class axi_monitor extends uvm_monitor;

  `uvm_component_utils(axi_monitor)

  virtual axi_if vif;
  uvm_analysis_port #(axi_seq_item) ap;

  // write assembly
  axi_seq_item aw_q[$];          // accepted AW, waiting for W and B
  axi_seq_item wb_q[$];          // completed W bursts (data/strb/waits only)
  bit [31:0]   w_data_q[$];
  bit [3:0]    w_strb_q[$];
  int unsigned w_wait_q[$];
  // read assembly
  axi_seq_item ar_q[$];
  bit [31:0]   r_data_q[$];
  axi_resp_e   r_resp_q[$];
  bit [3:0]    r_id_q[$];
  int unsigned r_wait_q[$];
  // running VALID && !READY counters
  int unsigned aw_wait, w_wait, b_wait, ar_wait, r_wait;

  int unsigned n_wr, n_rd;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual axi_if 'vif' not found in uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    flush();
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.aresetn !== 1'b1) begin
        flush();
        continue;
      end
      sample_aw();
      sample_w();
      sample_b();
      sample_ar();
      sample_r();
    end
  endtask

  function void flush();
    aw_q.delete();  wb_q.delete();
    w_data_q.delete(); w_strb_q.delete(); w_wait_q.delete();
    ar_q.delete();
    r_data_q.delete(); r_resp_q.delete(); r_id_q.delete(); r_wait_q.delete();
    aw_wait = 0; w_wait = 0; b_wait = 0; ar_wait = 0; r_wait = 0;
  endfunction

  // ---------------- AW ----------------
  function void sample_aw();
    axi_seq_item t;
    if (vif.mon_cb.awvalid !== 1'b1) return;
    if (vif.mon_cb.awready === 1'b1) begin
      t = axi_seq_item::type_id::create("mon_wr");
      t.rw        = AXI_WRITE;
      t.id        = vif.mon_cb.awid;
      t.addr      = vif.mon_cb.awaddr;
      t.len       = vif.mon_cb.awlen;
      t.size      = vif.mon_cb.awsize;
      t.burst     = axi_burst_e'(vif.mon_cb.awburst);
      t.addr_wait = aw_wait;
      aw_wait     = 0;
      aw_q.push_back(t);
    end else begin
      aw_wait++;
    end
  endfunction

  // ---------------- W ----------------
  function void sample_w();
    axi_seq_item wb;
    if (vif.mon_cb.wvalid !== 1'b1) return;
    if (vif.mon_cb.wready !== 1'b1) begin
      w_wait++;
      return;
    end
    w_data_q.push_back(vif.mon_cb.wdata);
    w_strb_q.push_back(vif.mon_cb.wstrb);
    w_wait_q.push_back(w_wait);
    w_wait = 0;
    if (vif.mon_cb.wlast === 1'b1) begin
      wb = axi_seq_item::type_id::create("mon_wbeats");
      wb.data      = new[w_data_q.size()];
      wb.strb      = new[w_strb_q.size()];
      wb.data_wait = new[w_wait_q.size()];
      foreach (w_data_q[i]) begin
        wb.data[i]      = w_data_q[i];
        wb.strb[i]      = w_strb_q[i];
        wb.data_wait[i] = w_wait_q[i];
      end
      wb_q.push_back(wb);
      w_data_q.delete(); w_strb_q.delete(); w_wait_q.delete();
    end
  endfunction

  // ---------------- B ----------------
  function void sample_b();
    axi_seq_item t, wb;
    if (vif.mon_cb.bvalid !== 1'b1) return;
    if (vif.mon_cb.bready !== 1'b1) begin
      b_wait++;
      return;
    end
    if (aw_q.size() == 0 || wb_q.size() == 0) begin
      `uvm_error("MON", $sformatf("B handshake (BID=%0h) with no complete AW+W burst outstanding (AW=%0d, W=%0d)",
                                  vif.mon_cb.bid, aw_q.size(), wb_q.size()))
      b_wait = 0;
      return;
    end
    t  = aw_q.pop_front();
    wb = wb_q.pop_front();
    t.data      = wb.data;
    t.strb      = wb.strb;
    t.data_wait = wb.data_wait;
    t.bresp     = axi_resp_e'(vif.mon_cb.bresp);
    t.bid       = vif.mon_cb.bid;
    t.resp_wait = b_wait;
    b_wait      = 0;
    n_wr++;
    `uvm_info("MON", {"write ", t.convert2string()}, UVM_HIGH)
    ap.write(t);
  endfunction

  // ---------------- AR ----------------
  function void sample_ar();
    axi_seq_item t;
    if (vif.mon_cb.arvalid !== 1'b1) return;
    if (vif.mon_cb.arready === 1'b1) begin
      t = axi_seq_item::type_id::create("mon_rd");
      t.rw        = AXI_READ;
      t.id        = vif.mon_cb.arid;
      t.addr      = vif.mon_cb.araddr;
      t.len       = vif.mon_cb.arlen;
      t.size      = vif.mon_cb.arsize;
      t.burst     = axi_burst_e'(vif.mon_cb.arburst);
      t.addr_wait = ar_wait;
      ar_wait     = 0;
      ar_q.push_back(t);
    end else begin
      ar_wait++;
    end
  endfunction

  // ---------------- R ----------------
  function void sample_r();
    axi_seq_item t;
    if (vif.mon_cb.rvalid !== 1'b1) return;
    if (vif.mon_cb.rready !== 1'b1) begin
      r_wait++;
      return;
    end
    if (ar_q.size() == 0) begin
      `uvm_error("MON", $sformatf("R handshake (RID=%0h) with no AR outstanding", vif.mon_cb.rid))
      r_wait = 0;
      return;
    end
    r_data_q.push_back(vif.mon_cb.rdata);
    r_resp_q.push_back(axi_resp_e'(vif.mon_cb.rresp));
    r_id_q.push_back(vif.mon_cb.rid);
    r_wait_q.push_back(r_wait);
    r_wait = 0;
    if (vif.mon_cb.rlast === 1'b1) begin
      t = ar_q.pop_front();
      t.data      = new[r_data_q.size()];
      t.rresp     = new[r_resp_q.size()];
      t.rid       = new[r_id_q.size()];
      t.data_wait = new[r_wait_q.size()];
      foreach (r_data_q[i]) begin
        t.data[i]      = r_data_q[i];
        t.rresp[i]     = r_resp_q[i];
        t.rid[i]       = r_id_q[i];
        t.data_wait[i] = r_wait_q[i];
      end
      r_data_q.delete(); r_resp_q.delete(); r_id_q.delete(); r_wait_q.delete();
      n_rd++;
      `uvm_info("MON", {"read ", t.convert2string()}, UVM_HIGH)
      ap.write(t);
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("MON", $sformatf("observed %0d writes, %0d reads", n_wr, n_rd), UVM_LOW)
    if (aw_q.size() || wb_q.size() || ar_q.size())
      `uvm_warning("MON", $sformatf("incomplete at end of test: AW=%0d W=%0d AR=%0d",
                                    aw_q.size(), wb_q.size(), ar_q.size()))
  endfunction

endclass
