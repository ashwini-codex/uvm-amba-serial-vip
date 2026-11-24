// ----------------------------------------------------------------------------
// spi_driver.sv : reactive SPI slave. Holds one response item, waits for the
// DUT to assert CS, then shifts miso_data out MSB first on the mode's shift edge.
// ----------------------------------------------------------------------------
class spi_driver extends uvm_driver #(spi_seq_item);

  `uvm_component_utils(spi_driver)

  spi_agent_cfg  cfg;
  virtual spi_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.miso <= 1'b0;
    wait (vif.rst_n === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      respond(req);
      seq_item_port.item_done();
    end
  endtask

  protected task respond(spi_seq_item tr);
    bit          cpha;
    bit          prev_sclk;
    bit          leading, shift_edge;
    int          idx;
    int unsigned edges;

    // Start from an idle bus, then wait for CS to assert.
    while (vif.drv_cb.cs_n !== 1'b1) @(vif.drv_cb);
    while (vif.drv_cb.cs_n !== 1'b0) @(vif.drv_cb);

    cpha      = cfg.cpha;
    prev_sclk = vif.drv_cb.sclk;
    edges     = 0;
    idx       = 7;
    if (!cpha) begin                 // CPHA=0: first bit must be out before the first edge
      vif.drv_cb.miso <= tr.miso_data[7];
      idx = 6;
    end

    forever begin
      @(vif.drv_cb);
      if (vif.drv_cb.cs_n === 1'b1) break;
      if (vif.drv_cb.sclk !== prev_sclk) begin
        leading    = (edges % 2 == 0);
        shift_edge = cpha ? leading : !leading;
        if (shift_edge && idx >= 0) begin
          vif.drv_cb.miso <= tr.miso_data[idx];
          idx--;
        end
        edges++;
        prev_sclk = vif.drv_cb.sclk;
      end
    end
    `uvm_info("SPI_DRV", $sformatf("answered 0x%02h", tr.miso_data), UVM_HIGH)
  endtask

endclass
