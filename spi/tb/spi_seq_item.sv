// ----------------------------------------------------------------------------
// spi_seq_item.sv : one SPI byte transfer (one chip-select window)
// ----------------------------------------------------------------------------
class spi_seq_item extends uvm_sequence_item;

  rand bit [7:0] miso_data;    // what the slave agent answers with

  // Observed by the monitor
  bit [7:0]    mosi_seen;
  bit [7:0]    miso_seen;
  bit          cpol, cpha;     // mode the agent expected
  int unsigned div_exp;        // expected SCLK half-period
  int unsigned num_edges;
  int unsigned half_min, half_max;
  bit          idle_ok;        // SCLK at CPOL level at CS fall and rise

  constraint c_miso {
    miso_data dist { 8'h00 := 5, 8'hFF := 5, 8'h55 := 5, 8'hAA := 5, [8'h01 : 8'hFE] :/ 80 };
  }

  `uvm_object_utils_begin(spi_seq_item)
    `uvm_field_int(miso_data, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(mosi_seen, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(miso_seen, UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(cpol,      UVM_ALL_ON)
    `uvm_field_int(cpha,      UVM_ALL_ON)
    `uvm_field_int(div_exp,   UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(num_edges, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(half_min,  UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(half_max,  UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(idle_ok,   UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "spi_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("mode%0d mosi=0x%02h miso=0x%02h edges=%0d half=%0d..%0d (exp %0d) idle_ok=%0b",
                     {cpol, cpha}, mosi_seen, miso_seen, num_edges, half_min, half_max, div_exp, idle_ok);
  endfunction

endclass
