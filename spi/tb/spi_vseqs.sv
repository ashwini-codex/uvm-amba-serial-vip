// ----------------------------------------------------------------------------
// spi_vseqs.sv : virtual sequences. Program the mode/divider over APB, keep the
// SPI slave agent in step, and run transfers.
// ----------------------------------------------------------------------------
class spi_base_vseq extends uvm_sequence;

  `uvm_object_utils(spi_base_vseq)
  `uvm_declare_p_sequencer(spi_vsequencer)

  int unsigned num_xfers = 25;

  rand bit          cpol;
  rand bit          cpha;
  rand int unsigned div;

  constraint c_div { div dist { 2 := 20, 3 := 20, [4:7] :/ 30, [8:16] :/ 30 }; }

  function new(string name = "spi_base_vseq");
    super.new(name);
  endfunction

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

  task wait_status(int pos, bit val, int unsigned max_polls = 2000);
    bit [31:0] st;
    for (int unsigned i = 0; i < max_polls; i++) begin
      reg_read(SPI_STATUS, st);
      if (st[pos] == val) return;
    end
    `uvm_error("VSEQ", $sformatf("timeout waiting for STATUS[%0d] == %0b", pos, val))
  endtask

  task configure();
    wait_status(0, 1'b0);                       // never change mode mid-transfer
    reg_write(SPI_CLKDIV, div);
    reg_write(SPI_CTRL,   {30'h0, cpha, cpol});
    p_sequencer.cfg.spi_cfg.cpol     = cpol;
    p_sequencer.cfg.spi_cfg.cpha     = cpha;
    p_sequencer.cfg.spi_cfg.div      = div;
    p_sequencer.cfg.spi_cfg.vif.cpol_exp = cpol;
    `uvm_info("VSEQ", $sformatf("configured mode%0d div=%0d", {cpol, cpha}, div), UVM_LOW)
  endtask

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

  // One full byte exchange: wait idle, write TXDATA, wait done, read RXDATA.
  task xfer(bit [7:0] b);
    bit [31:0] rd;
    wait_status(0, 1'b0);
    reg_write(SPI_TXDATA, b);
    wait_status(1, 1'b1);
    reg_read(SPI_RXDATA, rd);
  endtask

endclass


class spi_xfer_vseq extends spi_base_vseq;
  `uvm_object_utils(spi_xfer_vseq)
  function new(string name = "spi_xfer_vseq"); super.new(name); endfunction

  virtual task body();
    configure();
    repeat (num_xfers) xfer(rand_byte());
  endtask
endclass


// Register read-back and unmapped addresses.
class spi_reg_vseq extends spi_base_vseq;
  `uvm_object_utils(spi_reg_vseq)
  function new(string name = "spi_reg_vseq"); super.new(name); endfunction

  virtual task body();
    bit [31:0] rd;
    configure();
    reg_read(SPI_CTRL, rd);
    if (rd[1:0] != {cpha, cpol}) `uvm_error("VSEQ", $sformatf("CTRL read back 0x%0h", rd))
    reg_read(SPI_CLKDIV, rd);
    if (rd[7:0] != div[7:0])     `uvm_error("VSEQ", $sformatf("CLKDIV read back 0x%0h", rd))
    reg_read(SPI_STATUS, rd);
    reg_read(SPI_RXDATA, rd);
    reg_write(32'h0000_0040, 32'h1234_5678);   // unmapped -> PSLVERR
    reg_read (32'h0000_1000, rd);              // unmapped -> PSLVERR
  endtask
endclass
