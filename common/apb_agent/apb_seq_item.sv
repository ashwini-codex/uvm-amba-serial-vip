// ----------------------------------------------------------------------------
// apb_seq_item.sv : one APB transfer
// ----------------------------------------------------------------------------
class apb_seq_item extends uvm_sequence_item;

  rand bit [31:0]   addr;
  rand bit [31:0]   data;         // write data, or read data filled in by driver/monitor
  rand bit          write;        // 1 = write, 0 = read
  rand int unsigned idle_cycles;  // idle cycles the driver inserts before SETUP

  // Observed fields (filled in by driver / monitor, not randomized)
  bit               slverr;
  int unsigned      wait_states;  // cycles PREADY was low in ACCESS
  int unsigned      idle_gap;     // idle cycles seen before this SETUP

  constraint c_idle  { idle_cycles dist {0 := 40, 1 := 30, [2:4] := 30}; }
  constraint c_align { soft addr[1:0] == 2'b00; }

  `uvm_object_utils_begin(apb_seq_item)
    `uvm_field_int(addr,        UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(data,        UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(write,       UVM_ALL_ON)
    `uvm_field_int(idle_cycles, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(slverr,      UVM_ALL_ON)
    `uvm_field_int(wait_states, UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(idle_gap,    UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "apb_seq_item");
    super.new(name);
  endfunction

  virtual function string convert2string();
    return $sformatf("%s addr=0x%08h data=0x%08h slverr=%0b wait=%0d gap=%0d",
                     write ? "WR" : "RD", addr, data, slverr, wait_states, idle_gap);
  endfunction

endclass
