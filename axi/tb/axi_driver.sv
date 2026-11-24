// ============================================================================
// axi_driver.sv  --  AXI4 master driver
//
// One burst at a time. A write drives the AW channel and the W channel in
// parallel threads (each with its own random VALID delays), then handles the
// B channel. A read drives AR, then accepts R beats with random RREADY
// delays until RLAST. Read data and responses are written back into the
// request item for debug; checking is done from the monitor's copy.
// ============================================================================
typedef uvm_sequencer #(axi_seq_item) axi_sequencer;

class axi_driver extends uvm_driver #(axi_seq_item);

  `uvm_component_utils(axi_driver)

  virtual axi_if vif;

  localparam int MAX_R_BEATS = 256;   // safety stop if RLAST never comes

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual axi_if 'vif' not found in uvm_config_db")
  endfunction

  task run_phase(uvm_phase phase);
    init_signals();
    wait (vif.aresetn === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      @(vif.drv_cb);                       // every burst starts on a clock edge
      `uvm_info("DRV", {"start ", req.convert2string()}, UVM_HIGH)
      if (req.rw == AXI_WRITE) do_write(req);
      else                     do_read(req);
      seq_item_port.item_done();
    end
  endtask

  // all master outputs idle
  task init_signals();
    vif.awvalid <= 1'b0;
    vif.awid    <= '0;
    vif.awaddr  <= '0;
    vif.awlen   <= '0;
    vif.awsize  <= '0;
    vif.awburst <= '0;
    vif.wvalid  <= 1'b0;
    vif.wdata   <= '0;
    vif.wstrb   <= '0;
    vif.wlast   <= 1'b0;
    vif.bready  <= 1'b0;
    vif.arvalid <= 1'b0;
    vif.arid    <= '0;
    vif.araddr  <= '0;
    vif.arlen   <= '0;
    vif.arsize  <= '0;
    vif.arburst <= '0;
    vif.rready  <= 1'b0;
  endtask

  // --------------------------------------------------------------------------
  // write: AW || W, then B
  // --------------------------------------------------------------------------
  task do_write(axi_seq_item t);
    fork
      drive_aw(t);
      drive_w(t);
    join
    drive_b(t);
  endtask

  task drive_aw(axi_seq_item t);
    repeat (t.addr_delay) @(vif.drv_cb);
    vif.drv_cb.awid    <= t.id;
    vif.drv_cb.awaddr  <= t.addr;
    vif.drv_cb.awlen   <= t.len;
    vif.drv_cb.awsize  <= t.size;
    vif.drv_cb.awburst <= t.burst;
    vif.drv_cb.awvalid <= 1'b1;
    do @(vif.drv_cb); while (vif.drv_cb.awready !== 1'b1);
    vif.drv_cb.awvalid <= 1'b0;
  endtask

  task drive_w(axi_seq_item t);
    for (int i = 0; i <= t.len; i++) begin
      repeat (t.data_delay[i]) @(vif.drv_cb);
      vif.drv_cb.wdata  <= t.data[i];
      vif.drv_cb.wstrb  <= t.strb[i];
      vif.drv_cb.wlast  <= (i == t.len);
      vif.drv_cb.wvalid <= 1'b1;
      do @(vif.drv_cb); while (vif.drv_cb.wready !== 1'b1);
      // keep WVALID high for a back-to-back beat, otherwise drop it
      if (i == t.len || t.data_delay[i+1] != 0) vif.drv_cb.wvalid <= 1'b0;
    end
  endtask

  task drive_b(axi_seq_item t);
    repeat (t.resp_delay) @(vif.drv_cb);
    vif.drv_cb.bready <= 1'b1;
    do @(vif.drv_cb); while (vif.drv_cb.bvalid !== 1'b1);
    t.bresp = axi_resp_e'(vif.drv_cb.bresp);
    t.bid   = vif.drv_cb.bid;
    vif.drv_cb.bready <= 1'b0;
  endtask

  // --------------------------------------------------------------------------
  // read: AR, then R beats until RLAST
  // --------------------------------------------------------------------------
  task do_read(axi_seq_item t);
    bit [31:0]   d_q[$];
    axi_resp_e   r_q[$];
    bit [3:0]    id_q[$];
    int unsigned dly;
    int unsigned beat;
    bit          last;

    // AR
    repeat (t.addr_delay) @(vif.drv_cb);
    vif.drv_cb.arid    <= t.id;
    vif.drv_cb.araddr  <= t.addr;
    vif.drv_cb.arlen   <= t.len;
    vif.drv_cb.arsize  <= t.size;
    vif.drv_cb.arburst <= t.burst;
    vif.drv_cb.arvalid <= 1'b1;
    do @(vif.drv_cb); while (vif.drv_cb.arready !== 1'b1);
    vif.drv_cb.arvalid <= 1'b0;

    // R
    beat = 0;
    last = 1'b0;
    while (!last) begin
      dly = (beat < t.data_delay.size()) ? t.data_delay[beat] : 0;
      repeat (dly) @(vif.drv_cb);
      vif.drv_cb.rready <= 1'b1;
      do @(vif.drv_cb); while (vif.drv_cb.rvalid !== 1'b1);
      d_q.push_back(vif.drv_cb.rdata);
      r_q.push_back(axi_resp_e'(vif.drv_cb.rresp));
      id_q.push_back(vif.drv_cb.rid);
      last = (vif.drv_cb.rlast === 1'b1);
      beat++;
      // keep RREADY high only if the next beat has no delay
      if (last || beat >= t.data_delay.size() || t.data_delay[beat] != 0)
        vif.drv_cb.rready <= 1'b0;
      if (!last && beat >= MAX_R_BEATS) begin
        `uvm_error("DRV", $sformatf("no RLAST after %0d beats (ARLEN=%0d), abandoning burst",
                                    beat, t.len))
        vif.drv_cb.rready <= 1'b0;
        last = 1'b1;
      end
    end

    t.data  = new[d_q.size()];
    t.rresp = new[r_q.size()];
    t.rid   = new[id_q.size()];
    foreach (d_q[i]) begin
      t.data[i]  = d_q[i];
      t.rresp[i] = r_q[i];
      t.rid[i]   = id_q[i];
    end
  endtask

endclass
