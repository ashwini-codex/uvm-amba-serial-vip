// ----------------------------------------------------------------------------
// i2c_coverage.sv : byte-level, transaction-level and command coverage
// ----------------------------------------------------------------------------
class i2c_coverage extends uvm_component;

  `uvm_component_utils(i2c_coverage)

  uvm_analysis_imp_apb #(apb_seq_item, i2c_coverage) apb_imp;
  uvm_analysis_imp_i2c #(i2c_bus_item, i2c_coverage) i2c_imp;

  i2c_bus_item b;
  apb_seq_item rg;

  covergroup byte_cg;
    option.per_instance = 1;
    cp_kind  : coverpoint b.is_addr   { bins data = {1'b0}; bins addr = {1'b1}; }
    cp_dir   : coverpoint b.master_tx { bins slave_tx = {1'b0}; bins master_tx = {1'b1}; }
    cp_ack   : coverpoint b.ack_n     { bins ack = {1'b0}; bins nack = {1'b1}; }
    cp_strch : coverpoint b.stretched { bins none = {1'b0}; bins stretched = {1'b1}; }
    cp_data  : coverpoint b.data iff (!b.is_addr) {
      bins zero  = {8'h00};
      bins ones  = {8'hFF};
      bins alt55 = {8'h55};
      bins altAA = {8'hAA};
      bins other = {[8'h01 : 8'h54], [8'h56 : 8'hA9], [8'hAB : 8'hFE]};
    }
    x_kind_dir_ack : cross cp_kind, cp_dir, cp_ack {
      ignore_bins addr_from_slave = binsof(cp_kind.addr) && binsof(cp_dir.slave_tx);
    }
    x_dir_strch : cross cp_dir, cp_strch;
    x_dir_data  : cross cp_dir, cp_data;
  endgroup

  covergroup txn_cg;
    option.per_instance = 1;
    cp_rw     : coverpoint b.rw       { bins write = {1'b0}; bins read = {1'b1}; }
    cp_match  : coverpoint b.addr7    { bins ours = {I2C_SLV_ADDR}; bins other = {[0:I2C_SLV_ADDR-1], [I2C_SLV_ADDR+1:127]}; }
    cp_aack   : coverpoint b.addr_ack { bins nack = {1'b0}; bins ack = {1'b1}; }
    cp_nbytes : coverpoint b.nbytes   { bins none = {0}; bins one = {1}; bins few = {[2:4]}; bins many = {[5:$]}; }
    // (bin names avoid "start"/"stop": those are built-in covergroup methods)
    cp_start  : coverpoint b.started_rep   { bins first_start = {1'b0}; bins rep_start = {1'b1}; }
    cp_end    : coverpoint b.ended_by_stop { bins rep_start = {1'b0}; bins by_stop = {1'b1}; }
    x_rw_nbytes : cross cp_rw, cp_nbytes;
    x_rw_start  : cross cp_rw, cp_start;
    x_match_ack : cross cp_match, cp_aack {
      ignore_bins other_acked = binsof(cp_match.other) && binsof(cp_aack.ack);   // impossible
    }
  endgroup

  covergroup cmd_cg;
    option.per_instance = 1;
    cp_cmd : coverpoint rg.data[4:0] iff (rg.write && rg.addr == I2C_CMD) {
      bins cmd_start = {5'b00001};
      bins cmd_stop  = {5'b00010};
      bins write     = {5'b00100};
      bins read_ack  = {5'b01000};
      bins read_nack = {5'b11000};
    }
    cp_reg : coverpoint rg.addr {
      bins clkdiv   = {I2C_CLKDIV};
      bins cmd      = {I2C_CMD};
      bins txdata   = {I2C_TXDATA};
      bins rxdata   = {I2C_RXDATA};
      bins status   = {I2C_STATUS};
      bins unmapped = {[32'h14 : 32'hFFFF_FFFF]};
    }
    cp_div : coverpoint rg.data[7:0] iff (rg.write && rg.addr == I2C_CLKDIV) {
      bins fast = {[1:3]};
      bins mid  = {[4:7]};
      bins slow = {[8:255]};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    byte_cg = new();
    txn_cg  = new();
    cmd_cg  = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_imp = new("apb_imp", this);
    i2c_imp = new("i2c_imp", this);
  endfunction

  virtual function void write_i2c(i2c_bus_item t);
    b = t;
    if (t.kind == I2C_BYTE) byte_cg.sample();
    if (t.kind == I2C_TXN)  txn_cg.sample();
  endfunction

  virtual function void write_apb(apb_seq_item t);
    rg = t;
    cmd_cg.sample();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("I2C_COV", $sformatf("byte_cg = %0.2f%%  (x_kind_dir_ack %0.1f x_dir_strch %0.1f x_dir_data %0.1f)",
      byte_cg.get_inst_coverage(), byte_cg.x_kind_dir_ack.get_inst_coverage(),
      byte_cg.x_dir_strch.get_inst_coverage(), byte_cg.x_dir_data.get_inst_coverage()), UVM_LOW)
    `uvm_info("I2C_COV", $sformatf("txn_cg  = %0.2f%%  (x_rw_nbytes %0.1f x_rw_start %0.1f x_match_ack %0.1f cp_end %0.1f)",
      txn_cg.get_inst_coverage(), txn_cg.x_rw_nbytes.get_inst_coverage(),
      txn_cg.x_rw_start.get_inst_coverage(), txn_cg.x_match_ack.get_inst_coverage(),
      txn_cg.cp_end.get_inst_coverage()), UVM_LOW)
    `uvm_info("I2C_COV", $sformatf("cmd_cg  = %0.2f%%", cmd_cg.get_inst_coverage()), UVM_LOW)
  endfunction

endclass
