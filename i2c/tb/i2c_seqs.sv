// ----------------------------------------------------------------------------
// i2c_seqs.sv : slave behaviour sequences (run for the whole test)
// ----------------------------------------------------------------------------
class i2c_rsp_seq extends uvm_sequence #(i2c_seq_item);

  `uvm_object_utils(i2c_rsp_seq)

  bit allow_nack    = 1'b1;
  bit allow_stretch = 1'b1;

  function new(string name = "i2c_rsp_seq");
    super.new(name);
  endfunction

  virtual task body();
    forever begin
      req = i2c_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            !allow_nack    -> (nack_addr == 0 && nack_at == -1);
            !allow_stretch -> (stretch == 0);
          })
        `uvm_error("I2C_SEQ", "randomize failed")
      finish_item(req);
    end
  endtask

endclass
