// ----------------------------------------------------------------------------
// i2c_scoreboard.sv
//  1. Command check: every CMD written over APB must show up on the bus, in
//     order, as the matching event (START / STOP / BYTE). WRITE bytes must
//     carry TXDATA; READ bytes must end with the requested ACK/NACK.
//  2. Read-back check: RXDATA == the byte that was on the bus;
//     STATUS.rx_ack == the ACK bit the slave gave after a WRITE.
//  3. Reference memory: a mirror of the slave's 256-byte memory, updated
//     from ACKed write transactions; every byte read from the slave must
//     match the mirror.
//  4. PSLVERR exactly for unmapped addresses.
// ----------------------------------------------------------------------------
class i2c_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(i2c_scoreboard)

  uvm_analysis_imp_apb #(apb_seq_item, i2c_scoreboard) apb_imp;
  uvm_analysis_imp_i2c #(i2c_bus_item, i2c_scoreboard) i2c_imp;

  typedef struct {
    i2c_kind_e kind;
    bit [7:0]  data;
    bit        master_tx;
    bit        ack_n;
  } exp_t;

  exp_t     exp_q [$];
  bit [7:0] last_tx;
  bit [7:0] rd_q  [$];
  bit       wr_ack_valid;
  bit       wr_ack_n;

  // Reference memory model
  bit [7:0] mirror [256];
  int       byte_idx;
  bit       addressed, rw, ptr_phase;
  bit [7:0] ptr;

  int unsigned n_cmd_ok, n_cmd_bad, n_rd_ok, n_rd_bad, n_ack_ok, n_ack_bad,
               n_mem_ok, n_mem_bad, n_slverr_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_imp = new("apb_imp", this);
    i2c_imp = new("i2c_imp", this);
    foreach (mirror[i]) mirror[i] = i2c_mem_init(i);
  endfunction

  // ---------------- APB side ----------------
  virtual function void write_apb(apb_seq_item t);
    bit   mapped = t.addr inside {I2C_CLKDIV, I2C_CMD, I2C_TXDATA, I2C_RXDATA, I2C_STATUS};
    exp_t e;
    if (t.slverr != !mapped) begin
      n_slverr_bad++;
      `uvm_error("I2C_SB", $sformatf("PSLVERR=%0b for address 0x%08h", t.slverr, t.addr))
    end
    if (!mapped) return;

    if (t.write && t.addr == I2C_TXDATA) last_tx = t.data[7:0];

    if (t.write && t.addr == I2C_CMD && (t.data[3:0] != 0)) begin
      wr_ack_valid = 1'b0;
      e.data       = last_tx;
      e.ack_n      = t.data[4];
      e.master_tx  = 1'b0;
      if      (t.data[0]) e.kind = I2C_START;
      else if (t.data[1]) e.kind = I2C_STOP;
      else if (t.data[2]) begin e.kind = I2C_BYTE; e.master_tx = 1'b1; end
      else                e.kind = I2C_BYTE;
      exp_q.push_back(e);
    end

    if (!t.write && t.addr == I2C_RXDATA && rd_q.size() > 0) begin
      bit [7:0] bus_byte;
      bus_byte = rd_q.pop_front();
      if (t.data[7:0] !== bus_byte) begin
        n_rd_bad++;
        `uvm_error("I2C_SB", $sformatf("RXDATA=0x%02h, bus byte was 0x%02h", t.data[7:0], bus_byte))
      end
      else n_rd_ok++;
    end

    if (!t.write && t.addr == I2C_STATUS && !t.data[0] && wr_ack_valid) begin
      if (t.data[1] !== wr_ack_n) begin
        n_ack_bad++;
        `uvm_error("I2C_SB", $sformatf("STATUS.rx_ack=%0b, slave answered %s",
                   t.data[1], wr_ack_n ? "NACK" : "ACK"))
      end
      else n_ack_ok++;
      wr_ack_valid = 1'b0;
    end
  endfunction

  // ---------------- Bus side ----------------
  virtual function void write_i2c(i2c_bus_item t);
    exp_t e;
    if (t.kind == I2C_TXN) return;

    if (exp_q.size() == 0) begin
      n_cmd_bad++;
      `uvm_error("I2C_SB", $sformatf("bus event %s with no command issued", t.convert2string()))
    end
    else begin
      e = exp_q.pop_front();
      if (e.kind != t.kind) begin
        n_cmd_bad++;
        `uvm_error("I2C_SB", $sformatf("expected %s on the bus, saw %s", e.kind.name(), t.convert2string()))
      end
      else if (t.kind == I2C_BYTE && e.master_tx && t.data !== e.data) begin
        n_cmd_bad++;
        `uvm_error("I2C_SB", $sformatf("WRITE: TXDATA 0x%02h, bus 0x%02h", e.data, t.data))
      end
      else if (t.kind == I2C_BYTE && !e.master_tx && t.ack_n !== e.ack_n) begin
        n_cmd_bad++;
        `uvm_error("I2C_SB", $sformatf("READ: requested %s, master sent %s",
                   e.ack_n ? "NACK" : "ACK", t.ack_n ? "NACK" : "ACK"))
      end
      else n_cmd_ok++;

      if (t.kind == I2C_BYTE) begin
        if (e.master_tx) begin
          wr_ack_n     = t.ack_n;
          wr_ack_valid = 1'b1;
        end
        else rd_q.push_back(t.data);
      end
    end

    update_mirror(t);
  endfunction

  protected function void update_mirror(i2c_bus_item t);
    case (t.kind)
      I2C_START: byte_idx = 0;
      I2C_BYTE : begin
        if (byte_idx == 0) begin
          rw        = t.data[0];
          addressed = (t.data[7:1] == I2C_SLV_ADDR) && !t.ack_n;
          ptr_phase = 1'b1;
        end
        else if (addressed && !rw) begin
          if (!t.ack_n) begin
            if (ptr_phase) begin ptr = t.data; ptr_phase = 1'b0; end
            else           begin mirror[ptr] = t.data; ptr++;    end
          end
        end
        else if (addressed && rw) begin
          if (t.data !== mirror[ptr]) begin
            n_mem_bad++;
            `uvm_error("I2C_SB", $sformatf("slave mem[0x%02h]: read 0x%02h, reference has 0x%02h",
                       ptr, t.data, mirror[ptr]))
          end
          else n_mem_ok++;
          ptr++;
        end
        byte_idx++;
      end
      default: ;
    endcase
  endfunction

  virtual function void check_phase(uvm_phase phase);
    if (exp_q.size() != 0)
      `uvm_error("I2C_SB", $sformatf("%0d commands never appeared on the bus", exp_q.size()))
    if (rd_q.size() != 0)
      `uvm_error("I2C_SB", $sformatf("%0d read bytes never fetched from RXDATA", rd_q.size()))
    if (n_cmd_ok == 0)
      `uvm_error("I2C_SB", "scoreboard checked nothing")
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("I2C_SB", $sformatf(
      "cmd ok=%0d bad=%0d | rxdata ok=%0d bad=%0d | rx_ack ok=%0d bad=%0d | ref mem ok=%0d bad=%0d | slverr_bad=%0d",
      n_cmd_ok, n_cmd_bad, n_rd_ok, n_rd_bad, n_ack_ok, n_ack_bad, n_mem_ok, n_mem_bad, n_slverr_bad), UVM_LOW)
  endfunction

endclass
