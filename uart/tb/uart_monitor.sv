// ----------------------------------------------------------------------------
// uart_monitor.sv : decodes frames on both lines.
//   tx line -> items with dir = UART_TX (what the DUT sent)
//   rx line -> items with dir = UART_RX (what the agent sent into the DUT)
// parity_err / frame_err describe what was actually on the line.
// ----------------------------------------------------------------------------
class uart_monitor extends uvm_monitor;

  `uvm_component_utils(uart_monitor)

  uart_agent_cfg                     cfg;
  virtual uart_if                    vif;
  uvm_analysis_port #(uart_seq_item) ap;

  int unsigned n_tx, n_rx;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    wait (vif.rst_n === 1'b1);
    fork
      watch_line(UART_TX);
      watch_line(UART_RX);
    join
  endtask

  protected function bit line(uart_dir_e d);
    return (d == UART_TX) ? vif.mon_cb.tx : vif.mon_cb.rx;
  endfunction

  protected task watch_line(uart_dir_e d);
    uart_seq_item tr;
    bit           prev = 1'b1;
    bit           cur;
    bit [7:0]     data;
    bit           par_bit;
    int unsigned  div;

    forever begin
      @(vif.mon_cb);
      cur = line(d);
      if (!(prev && !cur)) begin   // wait for a falling edge
        prev = cur;
        continue;
      end

      // Snapshot the line settings at the start of the frame.
      div = cfg.div;
      tr  = uart_seq_item::type_id::create("tr");
      tr.dir     = d;
      tr.div     = div;
      tr.par_en  = cfg.par_en;
      tr.par_odd = cfg.par_odd;

      // Middle of the start bit
      repeat (div / 2) @(vif.mon_cb);
      if (line(d) !== 1'b0) begin
        `uvm_warning("UART_MON", $sformatf("%s: false start bit", d.name()))
        prev = line(d);
        continue;
      end

      for (int i = 0; i < 8; i++) begin
        repeat (div) @(vif.mon_cb);
        data[i] = line(d);
      end
      if (tr.par_en) begin
        repeat (div) @(vif.mon_cb);
        par_bit       = line(d);
        tr.parity_err = (par_bit != cfg.parity(data));
      end
      repeat (div) @(vif.mon_cb);
      tr.frame_err = (line(d) !== 1'b1);
      tr.data      = data;
      prev         = line(d);

      if (d == UART_TX) n_tx++; else n_rx++;
      `uvm_info("UART_MON", tr.convert2string(), UVM_MEDIUM)
      ap.write(tr);
    end
  endtask

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("UART_MON", $sformatf("decoded %0d TX frames, %0d RX frames", n_tx, n_rx), UVM_LOW)
  endfunction

endclass
