// ----------------------------------------------------------------------------
// i2c_vseqs.sv : virtual sequences. Software-style driver code over APB
// (START / WRITE / READ / STOP commands) building full I2C transactions,
// while the slave agent answers on the bus.
// ----------------------------------------------------------------------------
class i2c_base_vseq extends uvm_sequence;

  `uvm_object_utils(i2c_base_vseq)
  `uvm_declare_p_sequencer(i2c_vsequencer)

  int unsigned num_txns = 15;

  rand bit [7:0] div;
  constraint c_div { div dist { [1:3] :/ 30, [4:7] :/ 40, [8:10] :/ 30 }; }

  function new(string name = "i2c_base_vseq");
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

  task wait_idle(output bit [31:0] st);
    for (int unsigned i = 0; i < 20000; i++) begin
      reg_read(I2C_STATUS, st);
      if (!st[0]) return;
    end
    `uvm_error("VSEQ", "timeout waiting for STATUS.busy == 0")
  endtask

  task issue(bit [4:0] cmd, output bit [31:0] st);
    wait_idle(st);
    reg_write(I2C_CMD, {27'h0, cmd});
    wait_idle(st);
  endtask

  task configure();
    bit [31:0] st;
    wait_idle(st);
    reg_write(I2C_CLKDIV, div);
    `uvm_info("VSEQ", $sformatf("configured CLKDIV=%0d", div), UVM_LOW)
  endtask

  // ---------------- bus-level helpers ----------------
  task i2c_start();
    bit [31:0] st;
    issue(I2C_CMD_START, st);
  endtask

  task i2c_stop();
    bit [31:0] st;
    issue(I2C_CMD_STOP, st);
  endtask

  // Returns 1 if the slave ACKed.
  task i2c_write(bit [7:0] b, output bit acked);
    bit [31:0] st;
    reg_write(I2C_TXDATA, b);
    issue(I2C_CMD_WRITE, st);
    acked = !st[1];
  endtask

  task i2c_read(bit nack, output bit [7:0] b);
    bit [31:0] st, rd;
    issue(nack ? (I2C_CMD_READ | I2C_CMD_NACK) : I2C_CMD_READ, st);
    reg_read(I2C_RXDATA, rd);
    b = rd[7:0];
  endtask

  // ---------------- transactions ----------------
  // S, addr+W, ptr, data..., P   (stops early on any NACK)
  task write_regs(bit [6:0] addr7, bit [7:0] ptr, bit [7:0] data[$]);
    bit acked;
    i2c_start();
    i2c_write({addr7, 1'b0}, acked);
    if (acked) i2c_write(ptr, acked);
    foreach (data[i]) begin
      if (!acked) break;
      i2c_write(data[i], acked);
    end
    i2c_stop();
  endtask

  // S, addr+W, ptr, Sr, addr+R, data... (NACK last), P
  task read_regs(bit [6:0] addr7, bit [7:0] ptr, int unsigned n);
    bit       acked;
    bit [7:0] b;
    i2c_start();
    i2c_write({addr7, 1'b0}, acked);
    if (acked) i2c_write(ptr, acked);
    if (acked) begin
      i2c_start();                                  // repeated START
      i2c_write({addr7, 1'b1}, acked);
      if (acked)
        for (int unsigned i = 0; i < n; i++) i2c_read(i == n - 1, b);
    end
    i2c_stop();
  endtask

  // S, addr+R, data... (NACK last), P  - reads from the current pointer
  task read_current(bit [6:0] addr7, int unsigned n);
    bit       acked;
    bit [7:0] b;
    i2c_start();
    i2c_write({addr7, 1'b1}, acked);
    if (acked)
      for (int unsigned i = 0; i < n; i++) i2c_read(i == n - 1, b);
    i2c_stop();
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

  function bit [6:0] rand_addr();
    return ($urandom_range(99, 0) < 85) ? I2C_SLV_ADDR : 7'($urandom_range(127, 0));
  endfunction

endclass


// Write a random block, then read it back with write-ptr / Sr / read.
class i2c_wr_rd_vseq extends i2c_base_vseq;
  `uvm_object_utils(i2c_wr_rd_vseq)
  function new(string name = "i2c_wr_rd_vseq"); super.new(name); endfunction

  virtual task body();
    bit [7:0] data[$];
    bit [7:0] ptr;
    int       len;
    configure();
    repeat (num_txns) begin
      ptr = $urandom_range(255, 0);
      len = $urandom_range(6, 1);
      data.delete();
      repeat (len) data.push_back(rand_byte());
      write_regs(I2C_SLV_ADDR, ptr, data);
      read_regs (I2C_SLV_ADDR, ptr, len);
    end
  endtask
endclass


// Random mix of writes, pointer reads and current-address reads, sometimes
// to the wrong address (slave must NACK).
class i2c_rand_vseq extends i2c_base_vseq;
  `uvm_object_utils(i2c_rand_vseq)
  function new(string name = "i2c_rand_vseq"); super.new(name); endfunction

  virtual task body();
    bit [7:0] data[$];
    configure();
    repeat (num_txns) begin
      randcase
        40: begin
              data.delete();
              repeat ($urandom_range(8, 0)) data.push_back(rand_byte());
              write_regs(rand_addr(), $urandom_range(255, 0), data);
            end
        35: read_regs(rand_addr(), $urandom_range(255, 0), $urandom_range(8, 1));
        25: read_current(rand_addr(), $urandom_range(4, 1));
      endcase
    end
  endtask
endclass


// Register read-back and unmapped addresses.
class i2c_reg_vseq extends i2c_base_vseq;
  `uvm_object_utils(i2c_reg_vseq)
  function new(string name = "i2c_reg_vseq"); super.new(name); endfunction

  virtual task body();
    bit [31:0] rd;
    configure();
    reg_read(I2C_CLKDIV, rd);
    if (rd[7:0] != div) `uvm_error("VSEQ", $sformatf("CLKDIV read back 0x%0h", rd))
    reg_write(I2C_TXDATA, 32'h0000_00C3);
    reg_read (I2C_TXDATA, rd);
    if (rd[7:0] != 8'hC3) `uvm_error("VSEQ", $sformatf("TXDATA read back 0x%0h", rd))
    reg_read(I2C_STATUS, rd);
    if (rd[2:0] != 3'b000) `uvm_error("VSEQ", $sformatf("STATUS not idle: 0x%0h", rd))
    reg_write(32'h0000_0018, 32'hFFFF_FFFF);   // unmapped -> PSLVERR
    reg_read (32'h0000_0200, rd);              // unmapped -> PSLVERR
  endtask
endclass
