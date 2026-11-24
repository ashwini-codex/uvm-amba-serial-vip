// ----------------------------------------------------------------------------
// uart_scoreboard.sv
//   TX path : byte written to TXDATA over APB  ==  byte decoded on tx line
//             (and the DUT's frame must have correct parity and stop bit)
//   RX path : byte driven on rx line (with its injected errors)
//             ==  RXDATA read over APB (data, parity_err, frame_err)
//             If several frames arrived before the read (overrun), the DUT
//             keeps only the newest one, so the model does the same.
//   PSLVERR : set exactly for unmapped addresses
// ----------------------------------------------------------------------------
class uart_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(uart_scoreboard)

  uvm_analysis_imp_apb  #(apb_seq_item,  uart_scoreboard) apb_imp;
  uvm_analysis_imp_uart #(uart_seq_item, uart_scoreboard) uart_imp;

  bit [7:0]     tx_exp [$];
  uart_seq_item rx_exp [$];

  int unsigned n_tx_match, n_tx_mismatch, n_rx_match, n_rx_mismatch, n_overrun, n_slverr_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_imp  = new("apb_imp",  this);
    uart_imp = new("uart_imp", this);
  endfunction

  virtual function void write_apb(apb_seq_item t);
    bit mapped = t.addr inside {UART_CTRL, UART_BAUD, UART_TXDATA, UART_RXDATA, UART_STATUS};
    if (t.slverr != !mapped) begin
      n_slverr_bad++;
      `uvm_error("UART_SB", $sformatf("PSLVERR=%0b for address 0x%08h", t.slverr, t.addr))
    end
    if (!mapped) return;

    if (t.write && t.addr == UART_TXDATA)
      tx_exp.push_back(t.data[7:0]);

    if (!t.write && t.addr == UART_RXDATA && t.data[10])
      check_rx(t.data);
  endfunction

  virtual function void write_uart(uart_seq_item t);
    if (t.dir == UART_TX) check_tx(t);
    else                  rx_exp.push_back(t);
  endfunction

  protected function void check_tx(uart_seq_item t);
    bit [7:0] exp;
    if (tx_exp.size() == 0) begin
      n_tx_mismatch++;
      `uvm_error("UART_SB", $sformatf("unexpected TX frame %s", t.convert2string()))
      return;
    end
    exp = tx_exp.pop_front();
    if (t.data !== exp || t.parity_err || t.frame_err) begin
      n_tx_mismatch++;
      `uvm_error("UART_SB", $sformatf("TX: expected 0x%02h, got %s", exp, t.convert2string()))
    end
    else n_tx_match++;
  endfunction

  protected function void check_rx(bit [31:0] rd);
    uart_seq_item exp;
    if (rx_exp.size() == 0) begin
      n_rx_mismatch++;
      `uvm_error("UART_SB", $sformatf("RXDATA valid (0x%03h) but no frame was sent", rd[10:0]))
      return;
    end
    if (rx_exp.size() > 1) n_overrun++;
    exp = rx_exp[$];
    rx_exp.delete();
    if (rd[7:0] !== exp.data || rd[8] !== exp.parity_err || rd[9] !== exp.frame_err) begin
      n_rx_mismatch++;
      `uvm_error("UART_SB", $sformatf("RX: sent %s, read data=0x%02h perr=%0b ferr=%0b",
                 exp.convert2string(), rd[7:0], rd[8], rd[9]))
    end
    else n_rx_match++;
  endfunction

  virtual function void check_phase(uvm_phase phase);
    if (tx_exp.size() != 0)
      `uvm_error("UART_SB", $sformatf("%0d TX bytes written but never seen on the line", tx_exp.size()))
    if (rx_exp.size() != 0)
      `uvm_error("UART_SB", $sformatf("%0d RX frames sent but never read back", rx_exp.size()))
    if (n_tx_match + n_rx_match == 0)
      `uvm_error("UART_SB", "scoreboard checked nothing")
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("UART_SB", $sformatf(
      "TX match=%0d mismatch=%0d | RX match=%0d mismatch=%0d overrun=%0d | slverr_bad=%0d",
      n_tx_match, n_tx_mismatch, n_rx_match, n_rx_mismatch, n_overrun, n_slverr_bad), UVM_LOW)
  endfunction

endclass
