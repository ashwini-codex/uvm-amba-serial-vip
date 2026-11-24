// ----------------------------------------------------------------------------
// apb_coverage.sv : functional coverage on transfer type, address range,
// wait states, back-to-back vs idle, and error response.
// ----------------------------------------------------------------------------
class apb_coverage extends uvm_subscriber #(apb_seq_item);

  `uvm_component_utils(apb_coverage)

  apb_seq_item tr;

  covergroup apb_cg;
    option.per_instance = 1;

    cp_dir : coverpoint tr.write {
      bins read  = {1'b0};
      bins write = {1'b1};
    }

    // Order of transfers (write-after-read etc.)
    cp_dir_seq : coverpoint tr.write {
      bins rd_rd = (1'b0 => 1'b0);
      bins rd_wr = (1'b0 => 1'b1);
      bins wr_rd = (1'b1 => 1'b0);
      bins wr_wr = (1'b1 => 1'b1);
    }

    cp_addr : coverpoint tr.addr {
      bins low     = {[32'h000 : 32'h0FF]};
      bins mid     = {[32'h100 : 32'h2FF]};
      bins high    = {[32'h300 : 32'h3FF]};
      bins invalid = {[32'h400 : 32'hFFFF_FFFF]};
    }

    cp_addr_edge : coverpoint tr.addr {
      bins first_word = {32'h000};
      bins last_word  = {32'h3FC};
      bins first_bad  = {32'h400};
    }

    cp_data : coverpoint tr.data {
      bins zeros = {32'h0000_0000};
      bins ones  = {32'hFFFF_FFFF};
      bins other = {[32'h0000_0001 : 32'hFFFF_FFFE]};
    }

    cp_wait : coverpoint tr.wait_states {
      bins zero  = {0};
      bins one   = {1};
      bins multi = {[2:$]};
    }

    cp_gap : coverpoint tr.idle_gap {
      bins back_to_back = {0};
      bins short_gap    = {[1:2]};
      bins long_gap     = {[3:$]};
    }

    cp_err : coverpoint tr.slverr {
      bins okay = {1'b0};
      bins err  = {1'b1};
    }

    x_dir_addr : cross cp_dir, cp_addr;
    x_dir_wait : cross cp_dir, cp_wait;
    x_dir_gap  : cross cp_dir, cp_gap;
    x_dir_err  : cross cp_dir, cp_err;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apb_cg = new();
  endfunction

  virtual function void write(apb_seq_item t);
    tr = t;
    apb_cg.sample();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("APB_COV", $sformatf("apb_cg coverage = %0.2f%%", apb_cg.get_inst_coverage()), UVM_LOW)
    `uvm_info("APB_COV", $sformatf("  cp_dir=%0.1f cp_dir_seq=%0.1f cp_addr=%0.1f cp_addr_edge=%0.1f cp_data=%0.1f",
      apb_cg.cp_dir.get_inst_coverage(), apb_cg.cp_dir_seq.get_inst_coverage(),
      apb_cg.cp_addr.get_inst_coverage(), apb_cg.cp_addr_edge.get_inst_coverage(),
      apb_cg.cp_data.get_inst_coverage()), UVM_LOW)
    `uvm_info("APB_COV", $sformatf("  cp_wait=%0.1f cp_gap=%0.1f cp_err=%0.1f x_dir_addr=%0.1f x_dir_wait=%0.1f x_dir_gap=%0.1f x_dir_err=%0.1f",
      apb_cg.cp_wait.get_inst_coverage(), apb_cg.cp_gap.get_inst_coverage(),
      apb_cg.cp_err.get_inst_coverage(), apb_cg.x_dir_addr.get_inst_coverage(),
      apb_cg.x_dir_wait.get_inst_coverage(), apb_cg.x_dir_gap.get_inst_coverage(),
      apb_cg.x_dir_err.get_inst_coverage()), UVM_LOW)
  endfunction

endclass
