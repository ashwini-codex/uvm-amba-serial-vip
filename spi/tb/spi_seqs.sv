// ----------------------------------------------------------------------------
// spi_seqs.sv : slave-side response sequence (runs for the whole test)
// ----------------------------------------------------------------------------
class spi_rsp_seq extends uvm_sequence #(spi_seq_item);

  `uvm_object_utils(spi_rsp_seq)

  function new(string name = "spi_rsp_seq");
    super.new(name);
  endfunction

  virtual task body();
    forever begin
      req = spi_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize()) `uvm_error("SPI_SEQ", "randomize failed")
      finish_item(req);
    end
  endtask

endclass
