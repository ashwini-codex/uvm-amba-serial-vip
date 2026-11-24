// ----------------------------------------------------------------------------
// uart_seqs.sv : sequences that run on the UART agent's sequencer
// ----------------------------------------------------------------------------
class uart_frame_seq extends uvm_sequence #(uart_seq_item);

  `uvm_object_utils(uart_frame_seq)

  rand bit [7:0] m_data;
  rand bit       m_perr;
  rand bit       m_ferr;

  constraint c_err { soft m_perr == 1'b0; soft m_ferr == 1'b0; }

  function new(string name = "uart_frame_seq");
    super.new(name);
  endfunction

  virtual task body();
    req = uart_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { data == m_data;
                                inject_parity_err == m_perr;
                                inject_frame_err  == m_ferr; })
      `uvm_error("UART_SEQ", "randomize failed")
    finish_item(req);
  endtask

endclass
