// ----------------------------------------------------------------------------
// i2c_items.sv
//   i2c_seq_item : how the slave agent should behave for one transaction
//                  (sent by the response sequence, consumed at each START)
//   i2c_bus_item : what the monitor saw on the bus
// ----------------------------------------------------------------------------
class i2c_seq_item extends uvm_sequence_item;

  rand bit          nack_addr;    // NACK the address byte even if it matches
  rand int          nack_at;      // NACK the n-th received data byte (-1 = never)
  rand int unsigned stretch;      // hold SCL low this many cycles after each byte

  constraint c_nack    { nack_addr dist {1'b0 := 92, 1'b1 := 8};
                         nack_at   dist {-1 := 88, [0:3] :/ 12}; }
  constraint c_stretch { stretch   dist {0 := 50, [1:8] :/ 25, [20:60] :/ 25}; }

  `uvm_object_utils_begin(i2c_seq_item)
    `uvm_field_int(nack_addr, UVM_ALL_ON)
    `uvm_field_int(nack_at,   UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(stretch,   UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "i2c_seq_item");
    super.new(name);
  endfunction

endclass


typedef enum {I2C_START, I2C_STOP, I2C_BYTE, I2C_TXN} i2c_kind_e;

class i2c_bus_item extends uvm_sequence_item;

  i2c_kind_e   kind;

  // START
  bit          repeated;      // repeated START (no STOP before it)
  // BYTE
  bit [7:0]    data;
  bit          ack_n;         // 9th bit: 0 = ACK, 1 = NACK
  bit          is_addr;
  bit          master_tx;     // byte driven by the master (address or write data)
  bit          stretched;     // slave held SCL low during this byte
  // TXN summary (START .. STOP / repeated START)
  bit [6:0]    addr7;
  bit          rw;            // 1 = read
  bit          addr_ack;
  int unsigned nbytes;        // data bytes after the address
  bit          started_rep;
  bit          ended_by_stop;

  `uvm_object_utils_begin(i2c_bus_item)
    `uvm_field_enum(i2c_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(repeated,      UVM_ALL_ON)
    `uvm_field_int(data,          UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(ack_n,         UVM_ALL_ON)
    `uvm_field_int(is_addr,       UVM_ALL_ON)
    `uvm_field_int(master_tx,     UVM_ALL_ON)
    `uvm_field_int(stretched,     UVM_ALL_ON)
    `uvm_field_int(addr7,         UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(rw,            UVM_ALL_ON)
    `uvm_field_int(addr_ack,      UVM_ALL_ON)
    `uvm_field_int(nbytes,        UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(started_rep,   UVM_ALL_ON)
    `uvm_field_int(ended_by_stop, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "i2c_bus_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    case (kind)
      I2C_START: return repeated ? "Sr" : "S";
      I2C_STOP : return "P";
      I2C_BYTE : return $sformatf("%s 0x%02h %s%s", is_addr ? "ADDR" : (master_tx ? "WR" : "RD"),
                                  data, ack_n ? "NACK" : "ACK", stretched ? " (stretched)" : "");
      default  : return $sformatf("TXN addr=0x%02h %s %s nbytes=%0d %s..%s", addr7, rw ? "R" : "W",
                                  addr_ack ? "ACK" : "NACK", nbytes,
                                  started_rep ? "Sr" : "S", ended_by_stop ? "P" : "Sr");
    endcase
  endfunction

endclass
