// ----------------------------------------------------------------------------
// uart_vseqs.sv : virtual sequences. They program the DUT over APB and run
// serial traffic on the UART agent at the same time.
// ----------------------------------------------------------------------------
class uart_base_vseq extends uvm_sequence;

  `uvm_object_utils(uart_base_vseq)
  `uvm_declare_p_sequencer(uart_vsequencer)

  int unsigned num_bytes = 20;

  // Line settings this vseq programs (randomized by the test).
  rand int unsigned div;
  rand bit          par_en;
  rand bit          par_odd;

  constraint c_div { div dist { [4:8] :/ 30, [9:16] :/ 40, [17:40] :/ 30 }; }

  function new(string name = "uart_base_vseq");
    super.new(name);
  endfunction

  // ---------------- register helpers ----------------
  task reg_write(bit [31:0] waddr, bit [31:0] wdata);
    apb_write_seq s = apb_write_seq::type_id::create("wr");
    if (!s.randomize() with { m_addr == waddr; m_data == wdata; })
      `uvm_error("VSEQ", "apb_write_seq randomize failed")
    s.start(p_sequencer.apb_sqr, this);
  endtask

  task reg_read(bit [31:0] raddr, output bit [31:0] rdata);
    apb_read_seq s = apb_read_seq::type_id::create("rd");
    if (!s.randomize() with { m_addr == raddr; })
      `uvm_error("VSEQ", "apb_read_seq randomize failed")
    s.start(p_sequencer.apb_sqr, this);
    rdata = s.m_rdata;
  endtask

  // Poll STATUS until bit `pos` equals `val`.
  task wait_status(int pos, bit val, int unsigned max_polls = 5000);
    bit [31:0] st;
    for (int unsigned i = 0; i < max_polls; i++) begin
      reg_read(UART_STATUS, st);
      if (st[pos] == val) return;
    end
    `uvm_error("VSEQ", $sformatf("timeout waiting for STATUS[%0d] == %0b", pos, val))
  endtask

  // Program the DUT and tell the UART agent to follow.
  task configure();
    reg_write(UART_BAUD, div);
    reg_write(UART_CTRL, {30'h0, par_odd, par_en});
    p_sequencer.cfg.uart_cfg.div     = div;
    p_sequencer.cfg.uart_cfg.par_en  = par_en;
    p_sequencer.cfg.uart_cfg.par_odd = par_odd;
    `uvm_info("VSEQ", $sformatf("configured div=%0d parity=%s", div,
              !par_en ? "none" : (par_odd ? "odd" : "even")), UVM_LOW)
  endtask

  // ---------------- traffic helpers ----------------
  function bit [7:0] rand_byte();
    bit [7:0] b;
    randcase
      5 : b = 8'h00;
      5 : b = 8'hFF;
      5 : b = 8'h55;
      5 : b = 8'hAA;
      80: b = $urandom_range(8'hFE, 8'h01);
    endcase
    return b;
  endfunction

  task send_tx(bit [7:0] b);
    wait_status(0, 1'b0);          // TX idle
    reg_write(UART_TXDATA, b);
  endtask

  task drain_tx();
    wait_status(0, 1'b0);
  endtask

  task send_rx(bit [7:0] b, bit perr = 0, bit ferr = 0, bit read_back = 1);
    bit [31:0]     rd;
    uart_frame_seq f = uart_frame_seq::type_id::create("f");
    if (!f.randomize() with { m_data == b; m_perr == perr; m_ferr == ferr; })
      `uvm_error("VSEQ", "uart_frame_seq randomize failed")
    f.start(p_sequencer.uart_sqr, this);
    if (read_back) begin
      wait_status(1, 1'b1);        // rx_valid
      reg_read(UART_RXDATA, rd);
    end
  endtask

endclass


// DUT -> line: write bytes to TXDATA and let the monitor decode them.
class uart_tx_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_tx_vseq)
  function new(string name = "uart_tx_vseq"); super.new(name); endfunction

  virtual task body();
    configure();
    repeat (num_bytes) send_tx(rand_byte());
    drain_tx();
  endtask
endclass


// Line -> DUT: drive frames on rx and read them back from RXDATA.
class uart_rx_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_rx_vseq)
  function new(string name = "uart_rx_vseq"); super.new(name); endfunction

  virtual task body();
    configure();
    repeat (num_bytes) send_rx(rand_byte());
  endtask
endclass


// Both directions at once: two threads share the APB sequencer.
class uart_duplex_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_duplex_vseq)
  function new(string name = "uart_duplex_vseq"); super.new(name); endfunction

  virtual task body();
    configure();
    fork
      begin repeat (num_bytes) send_tx(rand_byte()); drain_tx(); end
      begin repeat (num_bytes) send_rx(rand_byte()); end
    join
  endtask
endclass


// Error injection on rx: parity errors (when parity is on), framing errors, both.
class uart_err_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_err_vseq)
  function new(string name = "uart_err_vseq"); super.new(name); endfunction

  virtual task body();
    bit perr, ferr;
    configure();
    repeat (num_bytes) begin
      perr = par_en ? $urandom_range(1, 0) : 1'b0;
      ferr = $urandom_range(1, 0);
      send_rx(rand_byte(), perr, ferr);
    end
  endtask
endclass


// Two frames without a read in between: STATUS.rx_overrun must set and
// RXDATA must hold the newer byte.
class uart_overrun_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_overrun_vseq)
  function new(string name = "uart_overrun_vseq"); super.new(name); endfunction

  virtual task body();
    bit [31:0] st, rd;
    configure();
    repeat (num_bytes) begin
      send_rx(rand_byte(), 0, 0, 0);
      send_rx(rand_byte(), 0, 0, 0);
      wait_status(1, 1'b1);
      reg_read(UART_STATUS, st);
      if (!st[2]) `uvm_error("VSEQ", "STATUS.rx_overrun not set after two unread frames")
      reg_read(UART_RXDATA, rd);
      reg_read(UART_STATUS, st);
      if (st[2] || st[1]) `uvm_error("VSEQ", "RXDATA read did not clear rx_valid / rx_overrun")
    end
  endtask
endclass


// Touch every register, including read-back of CTRL/BAUD and an unmapped address.
class uart_reg_vseq extends uart_base_vseq;
  `uvm_object_utils(uart_reg_vseq)
  function new(string name = "uart_reg_vseq"); super.new(name); endfunction

  virtual task body();
    bit [31:0] rd;
    configure();
    reg_read(UART_CTRL, rd);
    if (rd[1:0] != {par_odd, par_en}) `uvm_error("VSEQ", $sformatf("CTRL read back 0x%0h", rd))
    reg_read(UART_BAUD, rd);
    if (rd[15:0] != div[15:0])        `uvm_error("VSEQ", $sformatf("BAUD read back 0x%0h", rd))
    reg_read(UART_STATUS, rd);
    reg_read(UART_RXDATA, rd);
    reg_write(32'h0000_0020, 32'hDEAD_BEEF);   // unmapped -> PSLVERR (scoreboard checks)
    reg_read (32'h0000_0100, rd);              // unmapped -> PSLVERR
  endtask
endclass
