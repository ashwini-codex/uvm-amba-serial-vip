// ----------------------------------------------------------------------------
// spi_monitor.sv : records each CS window: MOSI/MISO bytes sampled on the
// mode's sample edge, edge count, SCLK half-period, and SCLK idle level.
// ----------------------------------------------------------------------------
class spi_monitor extends uvm_monitor;

  `uvm_component_utils(spi_monitor)

  spi_agent_cfg                     cfg;
  virtual spi_if                    vif;
  uvm_analysis_port #(spi_seq_item) ap;

  int unsigned n_seen;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    spi_seq_item tr;
    bit          prev_cs = 1'b1;
    bit          prev_sclk;
    bit          leading, sample;
    int unsigned cyc;

    wait (vif.rst_n === 1'b1);
    forever begin
      @(vif.mon_cb);
      if (!(prev_cs && vif.mon_cb.cs_n === 1'b0)) begin
        prev_cs = vif.mon_cb.cs_n;
        continue;
      end

      // CS just asserted
      tr = spi_seq_item::type_id::create("tr");
      tr.cpol     = cfg.cpol;
      tr.cpha     = cfg.cpha;
      tr.div_exp  = cfg.div;
      tr.idle_ok  = (vif.mon_cb.sclk == cfg.cpol);
      tr.half_min = '1;
      tr.half_max = 0;
      prev_sclk   = vif.mon_cb.sclk;
      cyc         = 0;

      forever begin
        @(vif.mon_cb);
        cyc++;
        if (vif.mon_cb.cs_n === 1'b1) break;
        if (vif.mon_cb.sclk !== prev_sclk) begin
          if (tr.num_edges > 0) begin
            if (cyc < tr.half_min) tr.half_min = cyc;
            if (cyc > tr.half_max) tr.half_max = cyc;
          end
          leading = (tr.num_edges % 2 == 0);
          sample  = tr.cpha ? !leading : leading;
          if (sample) begin
            tr.mosi_seen = {tr.mosi_seen[6:0], vif.mon_cb.mosi};
            tr.miso_seen = {tr.miso_seen[6:0], vif.mon_cb.miso};
          end
          tr.num_edges++;
          prev_sclk = vif.mon_cb.sclk;
          cyc       = 0;
        end
      end

      // CS released: SCLK must be back at idle level.
      if (vif.mon_cb.sclk != tr.cpol) tr.idle_ok = 1'b0;
      prev_cs = 1'b1;
      n_seen++;
      `uvm_info("SPI_MON", tr.convert2string(), UVM_MEDIUM)
      ap.write(tr);
    end
  endtask

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SPI_MON", $sformatf("observed %0d SPI transfers", n_seen), UVM_LOW)
  endfunction

endclass
