// ----------------------------------------------------------------------------
// apb_driver.sv : APB master driver (IDLE -> SETUP -> ACCESS, waits on PREADY)
// Supports back-to-back transfers when idle_cycles == 0.
// ----------------------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_seq_item);

  `uvm_component_utils(apb_driver)

  virtual apb_if vif;

  // Simulation time of the clock edge where the last transfer finished.
  // If the next item arrives in that same time step we are still on the
  // edge and can start SETUP straight away (back-to-back).
  protected time last_done_t;
  protected bit  have_done;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Idle the bus before and during reset.
    vif.PSEL    <= 1'b0;
    vif.PENABLE <= 1'b0;
    vif.PWRITE  <= 1'b0;
    vif.PADDR   <= '0;
    vif.PWDATA  <= '0;
    wait (vif.PRESETn === 1'b1);
    @(vif.drv_cb);

    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      `uvm_info("APB_DRV", req.convert2string(), UVM_HIGH)
      seq_item_port.item_done();
    end
  endtask

  protected task drive(apb_seq_item tr);
    // Re-align to a clock edge if time has moved since the last transfer.
    if (!have_done || ($time != last_done_t))
      @(vif.drv_cb);

    repeat (tr.idle_cycles) @(vif.drv_cb);

    // SETUP phase
    vif.drv_cb.PSEL    <= 1'b1;
    vif.drv_cb.PENABLE <= 1'b0;
    vif.drv_cb.PADDR   <= tr.addr;
    vif.drv_cb.PWRITE  <= tr.write;
    vif.drv_cb.PWDATA  <= tr.write ? tr.data : 32'h0;
    @(vif.drv_cb);

    // ACCESS phase
    vif.drv_cb.PENABLE <= 1'b1;
    @(vif.drv_cb);
    tr.wait_states = 0;
    while (vif.drv_cb.PREADY !== 1'b1) begin
      tr.wait_states++;
      @(vif.drv_cb);
    end

    // Transfer completed on this edge.
    if (!tr.write) tr.data = vif.drv_cb.PRDATA;
    tr.slverr = vif.drv_cb.PSLVERR;

    // Go IDLE; a back-to-back item driven in this same time step overrides it.
    vif.drv_cb.PSEL    <= 1'b0;
    vif.drv_cb.PENABLE <= 1'b0;
    last_done_t = $time;
    have_done   = 1'b1;
  endtask

endclass
