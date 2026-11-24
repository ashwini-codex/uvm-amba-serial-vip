// ----------------------------------------------------------------------------
// uart_driver.sv : drives frames onto the DUT's rx line, with optional
// parity / framing error injection.
// ----------------------------------------------------------------------------
class uart_driver extends uvm_driver #(uart_seq_item);

  `uvm_component_utils(uart_driver)

  uart_agent_cfg  cfg;
  virtual uart_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.rx <= 1'b1;
    wait (vif.rst_n === 1'b1);
    @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(req);
      drive_frame(req);
      seq_item_port.item_done();
    end
  endtask

  protected task bit_time(bit b);
    vif.drv_cb.rx <= b;
    repeat (cfg.div) @(vif.drv_cb);
  endtask

  protected task drive_frame(uart_seq_item tr);
    bit par;
    repeat (tr.idle_bits) bit_time(1'b1);
    bit_time(1'b0);                                   // start
    for (int i = 0; i < 8; i++) bit_time(tr.data[i]); // data, LSB first
    if (cfg.par_en) begin
      par = cfg.parity(tr.data) ^ tr.inject_parity_err;
      bit_time(par);
    end
    bit_time(!tr.inject_frame_err);                   // stop
    bit_time(1'b1);                                   // always leave the line idle
    `uvm_info("UART_DRV", $sformatf("sent 0x%02h perr_inj=%0b ferr_inj=%0b",
              tr.data, tr.inject_parity_err, tr.inject_frame_err), UVM_HIGH)
  endtask

endclass
