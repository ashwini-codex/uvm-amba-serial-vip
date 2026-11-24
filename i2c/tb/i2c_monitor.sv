// ----------------------------------------------------------------------------
// i2c_monitor.sv : decodes the bus into START / STOP / BYTE events and one
// TXN summary per transaction (START .. STOP or repeated START).
// ----------------------------------------------------------------------------
class i2c_monitor extends uvm_monitor;

  `uvm_component_utils(i2c_monitor)

  i2c_agent_cfg                     cfg;
  virtual i2c_if                    vif;
  uvm_analysis_port #(i2c_bus_item) ap;

  int unsigned n_bytes, n_txns;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction

  protected function void publish(i2c_bus_item it);
    `uvm_info("I2C_MON", it.convert2string(), UVM_MEDIUM)
    ap.write(it);
  endfunction

  protected function void close_txn(i2c_bus_item txn, bit by_stop);
    txn.ended_by_stop = by_stop;
    n_txns++;
    publish(txn);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit          prev_scl = 1'b1, prev_sda = 1'b1;
    bit          scl, sda;
    bit          in_txn, stretched;
    int          bitcnt, byte_idx;
    bit [7:0]    sh;
    i2c_bus_item ev, txn;

    wait (vif.rst_n === 1'b1);
    forever begin
      @(vif.mon_cb);
      scl = vif.mon_cb.scl;
      sda = vif.mon_cb.sda;
      if (vif.mon_cb.s_scl_oe && !vif.mon_cb.m_scl_oe) stretched = 1'b1;

      if (prev_scl && scl && prev_sda && !sda) begin                 // START / Sr
        ev = i2c_bus_item::type_id::create("ev");
        ev.kind     = I2C_START;
        ev.repeated = in_txn;
        if (in_txn) close_txn(txn, 1'b0);
        publish(ev);
        txn = i2c_bus_item::type_id::create("txn");
        txn.kind        = I2C_TXN;
        txn.started_rep = ev.repeated;
        in_txn    = 1'b1;
        bitcnt    = 0;
        byte_idx  = 0;
        stretched = 1'b0;
      end
      else if (prev_scl && scl && !prev_sda && sda) begin            // STOP
        if (bitcnt > 1)
          `uvm_error("I2C_MON", $sformatf("STOP in the middle of a byte (bit %0d)", bitcnt))
        ev = i2c_bus_item::type_id::create("ev");
        ev.kind = I2C_STOP;
        if (in_txn) close_txn(txn, 1'b1);
        publish(ev);
        in_txn = 1'b0;
        bitcnt = 0;
      end
      else if (!prev_scl && scl && in_txn) begin                     // SCL rising: sample
        bitcnt++;
        if (bitcnt <= 8) sh = {sh[6:0], sda};
        else begin
          ev = i2c_bus_item::type_id::create("ev");
          ev.kind      = I2C_BYTE;
          ev.data      = sh;
          ev.ack_n     = sda;
          ev.is_addr   = (byte_idx == 0);
          ev.master_tx = (byte_idx == 0) || !txn.rw;
          ev.stretched = stretched;
          if (byte_idx == 0) begin
            txn.addr7    = sh[7:1];
            txn.rw       = sh[0];
            txn.addr_ack = !sda;
            ev.master_tx = 1'b1;
          end
          else txn.nbytes++;
          n_bytes++;
          publish(ev);
          byte_idx++;
          bitcnt    = 0;
          stretched = 1'b0;
        end
      end

      prev_scl = scl;
      prev_sda = sda;
    end
  endtask

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("I2C_MON", $sformatf("observed %0d bytes in %0d transactions", n_bytes, n_txns), UVM_LOW)
  endfunction

endclass
