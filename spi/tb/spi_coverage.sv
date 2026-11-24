// ----------------------------------------------------------------------------
// spi_coverage.sv : transfer coverage (mode, clock divider, data) and
// register-access coverage.
// ----------------------------------------------------------------------------
class spi_coverage extends uvm_component;

  `uvm_component_utils(spi_coverage)

  uvm_analysis_imp_apb #(apb_seq_item, spi_coverage) apb_imp;
  uvm_analysis_imp_spi #(spi_seq_item, spi_coverage) spi_imp;

  spi_seq_item xf;
  apb_seq_item rg;

  covergroup xfer_cg;
    option.per_instance = 1;

    cp_mode : coverpoint {xf.cpol, xf.cpha} {
      bins mode0 = {2'b00};
      bins mode1 = {2'b01};
      bins mode2 = {2'b10};
      bins mode3 = {2'b11};
    }

    cp_div : coverpoint xf.div_exp {
      bins d2    = {2};
      bins d3    = {3};
      bins d4_7  = {[4:7]};
      bins d8_up = {[8:$]};
    }

    cp_mosi : coverpoint xf.mosi_seen {
      bins zero  = {8'h00};
      bins ones  = {8'hFF};
      bins alt55 = {8'h55};
      bins altAA = {8'hAA};
      bins low   = {[8'h01 : 8'h7F]};
      bins high  = {[8'h80 : 8'hFE]};
    }

    cp_miso : coverpoint xf.miso_seen {
      bins zero  = {8'h00};
      bins ones  = {8'hFF};
      bins alt55 = {8'h55};
      bins altAA = {8'hAA};
      bins low   = {[8'h01 : 8'h7F]};
      bins high  = {[8'h80 : 8'hFE]};
    }

    // MSB / LSB set: catches bit-order and first/last-bit timing bugs per mode
    cp_mosi_ends : coverpoint {xf.mosi_seen[7], xf.mosi_seen[0]};
    cp_miso_ends : coverpoint {xf.miso_seen[7], xf.miso_seen[0]};

    x_mode_div       : cross cp_mode, cp_div;
    x_mode_mosi_ends : cross cp_mode, cp_mosi_ends;
    x_mode_miso_ends : cross cp_mode, cp_miso_ends;
  endgroup

  covergroup reg_cg;
    option.per_instance = 1;
    cp_reg : coverpoint rg.addr {
      bins ctrl     = {SPI_CTRL};
      bins clkdiv   = {SPI_CLKDIV};
      bins txdata   = {SPI_TXDATA};
      bins rxdata   = {SPI_RXDATA};
      bins status   = {SPI_STATUS};
      bins unmapped = {[32'h14 : 32'hFFFF_FFFF]};
    }
    cp_dir : coverpoint rg.write { bins rd = {1'b0}; bins wr = {1'b1}; }
    x_reg_dir : cross cp_reg, cp_dir {
      ignore_bins ro_write = binsof(cp_reg) intersect {SPI_RXDATA, SPI_STATUS} && binsof(cp_dir.wr);
      ignore_bins wo_read  = binsof(cp_reg) intersect {SPI_TXDATA} && binsof(cp_dir.rd);
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    xfer_cg = new();
    reg_cg  = new();
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_imp = new("apb_imp", this);
    spi_imp = new("spi_imp", this);
  endfunction

  virtual function void write_spi(spi_seq_item t);
    xf = t;
    xfer_cg.sample();
  endfunction

  virtual function void write_apb(apb_seq_item t);
    rg = t;
    reg_cg.sample();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SPI_COV", $sformatf("xfer_cg = %0.2f%%  (mode %0.1f div %0.1f mosi %0.1f miso %0.1f | x_mode_div %0.1f x_mode_mosi_ends %0.1f x_mode_miso_ends %0.1f)",
      xfer_cg.get_inst_coverage(), xfer_cg.cp_mode.get_inst_coverage(), xfer_cg.cp_div.get_inst_coverage(),
      xfer_cg.cp_mosi.get_inst_coverage(), xfer_cg.cp_miso.get_inst_coverage(),
      xfer_cg.x_mode_div.get_inst_coverage(), xfer_cg.x_mode_mosi_ends.get_inst_coverage(),
      xfer_cg.x_mode_miso_ends.get_inst_coverage()), UVM_LOW)
    `uvm_info("SPI_COV", $sformatf("reg_cg  = %0.2f%%", reg_cg.get_inst_coverage()), UVM_LOW)
  endfunction

endclass
