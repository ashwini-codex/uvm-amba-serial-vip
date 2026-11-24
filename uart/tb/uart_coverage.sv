// ----------------------------------------------------------------------------
// uart_coverage.sv : frame coverage (data, parity mode, baud, errors) and
// register-access coverage (which registers, read/write, PSLVERR).
// ----------------------------------------------------------------------------
class uart_coverage extends uvm_component;

  `uvm_component_utils(uart_coverage)

  uvm_analysis_imp_apb  #(apb_seq_item,  uart_coverage) apb_imp;
  uvm_analysis_imp_uart #(uart_seq_item, uart_coverage) uart_imp;

  uart_seq_item fr;
  apb_seq_item  rg;

  covergroup frame_cg;
    option.per_instance = 1;

    cp_dir : coverpoint fr.dir;

    cp_data : coverpoint fr.data {
      bins zero  = {8'h00};
      bins ones  = {8'hFF};
      bins alt55 = {8'h55};
      bins altAA = {8'hAA};
      bins low   = {[8'h01 : 8'h7F]};
      bins high  = {[8'h80 : 8'hFE]};
    }

    cp_parity : coverpoint {fr.par_en, fr.par_odd} {
      bins none = {2'b00, 2'b01};
      bins even = {2'b10};
      bins odd  = {2'b11};
    }

    cp_div : coverpoint fr.div {
      bins fast = {[4:8]};
      bins mid  = {[9:16]};
      bins slow = {[17:$]};
    }

    cp_err : coverpoint {fr.parity_err, fr.frame_err} {
      bins none   = {2'b00};
      bins frame  = {2'b01};
      bins parity = {2'b10};
      bins both   = {2'b11};
    }

    x_dir_parity : cross cp_dir, cp_parity;
    x_parity_div : cross cp_parity, cp_div;
    x_err_parity : cross cp_err, cp_parity {
      ignore_bins no_parity_bit = binsof(cp_parity.none) && binsof(cp_err) intersect {2'b10, 2'b11};
    }
  endgroup

  covergroup reg_cg;
    option.per_instance = 1;
    cp_reg : coverpoint rg.addr {
      bins ctrl     = {UART_CTRL};
      bins baud     = {UART_BAUD};
      bins txdata   = {UART_TXDATA};
      bins rxdata   = {UART_RXDATA};
      bins status   = {UART_STATUS};
      bins unmapped = {[32'h14 : 32'hFFFF_FFFF]};
    }
    cp_dir : coverpoint rg.write { bins rd = {1'b0}; bins wr = {1'b1}; }
    cp_err : coverpoint rg.slverr { bins okay = {1'b0}; bins err = {1'b1}; }
    x_reg_dir : cross cp_reg, cp_dir {
      ignore_bins ro_write = binsof(cp_reg) intersect {UART_RXDATA, UART_STATUS} && binsof(cp_dir.wr);
      ignore_bins wo_read  = binsof(cp_reg) intersect {UART_TXDATA} && binsof(cp_dir.rd);
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    frame_cg = new();
    reg_cg   = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_imp  = new("apb_imp",  this);
    uart_imp = new("uart_imp", this);
  endfunction

  virtual function void write_uart(uart_seq_item t);
    fr = t;
    frame_cg.sample();
  endfunction

  virtual function void write_apb(apb_seq_item t);
    rg = t;
    reg_cg.sample();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("UART_COV", $sformatf("frame_cg = %0.2f%%  (dir %0.1f data %0.1f parity %0.1f div %0.1f err %0.1f | x_dir_par %0.1f x_par_div %0.1f x_err_par %0.1f)",
      frame_cg.get_inst_coverage(), frame_cg.cp_dir.get_inst_coverage(), frame_cg.cp_data.get_inst_coverage(),
      frame_cg.cp_parity.get_inst_coverage(), frame_cg.cp_div.get_inst_coverage(), frame_cg.cp_err.get_inst_coverage(),
      frame_cg.x_dir_parity.get_inst_coverage(), frame_cg.x_parity_div.get_inst_coverage(),
      frame_cg.x_err_parity.get_inst_coverage()), UVM_LOW)
    `uvm_info("UART_COV", $sformatf("reg_cg   = %0.2f%%", reg_cg.get_inst_coverage()), UVM_LOW)
  endfunction

endclass
