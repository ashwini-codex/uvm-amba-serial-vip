// ----------------------------------------------------------------------------
// uart_seq_item.sv : one UART frame
// ----------------------------------------------------------------------------
typedef enum bit {UART_TX, UART_RX} uart_dir_e;   // TX = from DUT, RX = into DUT

class uart_seq_item extends uvm_sequence_item;

  rand bit [7:0]    data;
  rand bit          inject_parity_err;   // driver flips the parity bit
  rand bit          inject_frame_err;    // driver sends stop bit = 0
  rand int unsigned idle_bits;           // idle bit-times before the start bit

  // Observed / stamped by the monitor
  uart_dir_e        dir;
  bit               parity_err;
  bit               frame_err;
  int unsigned      div;
  bit               par_en;
  bit               par_odd;

  constraint c_err  { soft inject_parity_err == 1'b0; soft inject_frame_err == 1'b0; }
  constraint c_idle { idle_bits inside {[1:4]}; }

  `uvm_object_utils_begin(uart_seq_item)
    `uvm_field_int (data,              UVM_ALL_ON | UVM_HEX)
    `uvm_field_int (inject_parity_err, UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int (inject_frame_err,  UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int (idle_bits,         UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_enum(uart_dir_e, dir,   UVM_ALL_ON)
    `uvm_field_int (parity_err,        UVM_ALL_ON)
    `uvm_field_int (frame_err,         UVM_ALL_ON)
    `uvm_field_int (div,               UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int (par_en,            UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_int (par_odd,           UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "uart_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s data=0x%02h perr=%0b ferr=%0b (div=%0d par=%s)",
                     dir.name(), data, parity_err, frame_err, div,
                     !par_en ? "none" : (par_odd ? "odd" : "even"));
  endfunction

endclass
