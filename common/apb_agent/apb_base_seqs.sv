// ----------------------------------------------------------------------------
// apb_base_seqs.sv : single write / single read sequences.
// The peripheral benches (UART, SPI, I2C) use these from their virtual
// sequences to program registers.
// ----------------------------------------------------------------------------
class apb_write_seq extends uvm_sequence #(apb_seq_item);

  `uvm_object_utils(apb_write_seq)

  rand bit [31:0]   m_addr;
  rand bit [31:0]   m_data;
  rand int unsigned m_idle;
  bit               m_slverr;

  constraint c_idle { m_idle inside {[0:4]}; }

  function new(string name = "apb_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = apb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { addr == m_addr; data == m_data; write == 1'b1; idle_cycles == m_idle; })
      `uvm_error("APB_WR_SEQ", "randomize failed")
    finish_item(req);
    m_slverr = req.slverr;
  endtask

endclass


class apb_read_seq extends uvm_sequence #(apb_seq_item);

  `uvm_object_utils(apb_read_seq)

  rand bit [31:0]   m_addr;
  rand int unsigned m_idle;
  bit  [31:0]       m_rdata;  // filled in after the transfer
  bit               m_slverr;

  constraint c_idle { m_idle inside {[0:4]}; }

  function new(string name = "apb_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = apb_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { addr == m_addr; write == 1'b0; idle_cycles == m_idle; })
      `uvm_error("APB_RD_SEQ", "randomize failed")
    finish_item(req);
    m_rdata  = req.data;
    m_slverr = req.slverr;
  endtask

endclass
