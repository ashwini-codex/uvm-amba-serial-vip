// ----------------------------------------------------------------------------
// i2c_slave_driver.sv : reactive I2C slave with a 256-byte register memory.
//   write txn : S, addr+W, ptr, data0, data1 ... -> mem[ptr++] = data
//   read  txn : S, addr+R, then mem[ptr++] until the master NACKs
// The pointer persists across transactions (EEPROM style), so the usual
// "write ptr, Sr, read" pattern works. At each START it takes one
// i2c_seq_item from the sequencer telling it whether to NACK / stretch.
// Runs one step per clk cycle so it can react to START/STOP at any time.
// ----------------------------------------------------------------------------
class i2c_slave_driver extends uvm_driver #(i2c_seq_item);

  `uvm_component_utils(i2c_slave_driver)

  i2c_agent_cfg  cfg;
  virtual i2c_if vif;

  bit [7:0] mem [256];

  typedef enum {S_IDLE, S_RX, S_ACK_OUT, S_TX, S_ACK_IN, S_IGNORE} state_e;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (mem[i]) mem[i] = i2c_mem_init(i);
  endfunction

  virtual task run_phase(uvm_phase phase);
    state_e      st = S_IDLE;
    bit          prev_scl = 1'b1, prev_sda = 1'b1;
    bit          scl, sda, rise, fall;
    bit [7:0]    sh, out;
    int          bitcnt, txbit, data_idx;
    bit          first, addressed, rw, ptr_phase, ack, mack, have_pol;
    bit [7:0]    ptr;
    int unsigned stretch_left;

    vif.s_scl_oe <= 1'b0;
    vif.s_sda_oe <= 1'b0;
    wait (vif.rst_n === 1'b1);

    forever begin
      @(vif.drv_cb);
      scl  = vif.drv_cb.scl;
      sda  = vif.drv_cb.sda;
      rise = !prev_scl &&  scl;
      fall =  prev_scl && !scl;

      // Clock stretching
      if (stretch_left > 0) begin
        vif.drv_cb.s_scl_oe <= 1'b1;
        stretch_left--;
      end
      else begin
        vif.drv_cb.s_scl_oe <= 1'b0;
      end

      if (prev_scl && scl && prev_sda && !sda) begin
        // START or repeated START: fetch this transaction's behaviour
        if (have_pol) seq_item_port.item_done();
        seq_item_port.get_next_item(req);
        have_pol  = 1'b1;
        st        = S_RX;
        bitcnt    = 0;
        first     = 1'b1;
        addressed = 1'b0;
        data_idx  = 0;
        vif.drv_cb.s_sda_oe <= 1'b0;
      end
      else if (prev_scl && scl && !prev_sda && sda) begin
        // STOP
        if (have_pol) begin
          seq_item_port.item_done();
          have_pol = 1'b0;
        end
        st = S_IDLE;
        vif.drv_cb.s_sda_oe <= 1'b0;
      end
      else begin
        case (st)
          S_RX: begin
            if (rise) begin
              sh = {sh[6:0], sda};
              bitcnt++;
            end
            else if (fall && bitcnt == 8) begin
              if (first) begin
                rw        = sh[0];
                addressed = (sh[7:1] == cfg.slave_addr) && !req.nack_addr;
                ack       = addressed;
                ptr_phase = 1'b1;
              end
              else begin
                ack = addressed && (req.nack_at != data_idx);
                if (ack) begin
                  if (ptr_phase) begin ptr = sh; ptr_phase = 1'b0; end
                  else           begin mem[ptr] = sh; ptr++;      end
                end
                data_idx++;
              end
              vif.drv_cb.s_sda_oe <= ack;               // pull SDA low = ACK
              if (ack) stretch_left = req.stretch;
              st = S_ACK_OUT;
            end
          end

          S_ACK_OUT: begin
            if (fall) begin                               // end of the ACK bit
              if (!ack) begin
                vif.drv_cb.s_sda_oe <= 1'b0;
                st = S_IGNORE;
              end
              else if (first && rw) begin                 // read: start sending
                out = mem[ptr];
                ptr++;
                vif.drv_cb.s_sda_oe <= !out[7];
                txbit = 6;
                st    = S_TX;
              end
              else begin
                vif.drv_cb.s_sda_oe <= 1'b0;
                bitcnt = 0;
                st     = S_RX;
              end
              first = 1'b0;
            end
          end

          S_TX: begin
            if (fall) begin
              if (txbit >= 0) begin
                vif.drv_cb.s_sda_oe <= !out[txbit];
                txbit--;
              end
              else begin
                vif.drv_cb.s_sda_oe <= 1'b0;              // release for master ACK
                st = S_ACK_IN;
              end
            end
          end

          S_ACK_IN: begin
            if (rise) mack = sda;
            else if (fall) begin
              if (!mack) begin                            // master ACK: next byte
                out = mem[ptr];
                ptr++;
                vif.drv_cb.s_sda_oe <= !out[7];
                txbit = 6;
                if (req.stretch != 0) stretch_left = req.stretch;
                st = S_TX;
              end
              else st = S_IGNORE;                         // master NACK: done
            end
          end

          default: ;                                      // S_IDLE, S_IGNORE
        endcase
      end

      prev_scl = scl;
      prev_sda = sda;
    end
  endtask

endclass
