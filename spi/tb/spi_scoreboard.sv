// ----------------------------------------------------------------------------
// spi_scoreboard.sv
//   MOSI : byte written to TXDATA  ==  byte seen on MOSI
//   MISO : byte the slave sent     ==  RXDATA read back (when done=1)
//   Line : 16 SCLK edges per byte, half-period == CLKDIV, SCLK idles at CPOL
//   APB  : PSLVERR exactly for unmapped addresses
// ----------------------------------------------------------------------------
class spi_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(spi_scoreboard)

  uvm_analysis_imp_apb #(apb_seq_item, spi_scoreboard) apb_imp;
  uvm_analysis_imp_spi #(spi_seq_item, spi_scoreboard) spi_imp;

  bit [7:0] mosi_exp [$];
  bit [7:0] miso_exp [$];

  int unsigned n_mosi_ok, n_mosi_bad, n_miso_ok, n_miso_bad, n_line_bad, n_slverr_bad;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_imp = new("apb_imp", this);
    spi_imp = new("spi_imp", this);
  endfunction

  virtual function void write_apb(apb_seq_item t);
    bit       mapped = t.addr inside {SPI_CTRL, SPI_CLKDIV, SPI_TXDATA, SPI_RXDATA, SPI_STATUS};
    bit [7:0] exp;
    if (t.slverr != !mapped) begin
      n_slverr_bad++;
      `uvm_error("SPI_SB", $sformatf("PSLVERR=%0b for address 0x%08h", t.slverr, t.addr))
    end
    if (!mapped) return;

    if (t.write && t.addr == SPI_TXDATA)
      mosi_exp.push_back(t.data[7:0]);

    if (!t.write && t.addr == SPI_RXDATA && t.data[8]) begin
      if (miso_exp.size() == 0) begin
        n_miso_bad++;
        `uvm_error("SPI_SB", "RXDATA done=1 but no transfer was seen")
        return;
      end
      exp = miso_exp.pop_front();
      if (t.data[7:0] !== exp) begin
        n_miso_bad++;
        `uvm_error("SPI_SB", $sformatf("RXDATA=0x%02h, slave sent 0x%02h", t.data[7:0], exp))
      end
      else n_miso_ok++;
    end
  endfunction

  virtual function void write_spi(spi_seq_item t);
    bit [7:0] exp;

    if (!t.idle_ok || t.num_edges != 16 || t.half_min != t.div_exp || t.half_max != t.div_exp) begin
      n_line_bad++;
      `uvm_error("SPI_SB", $sformatf("bad SCLK waveform: %s", t.convert2string()))
    end

    if (mosi_exp.size() == 0) begin
      n_mosi_bad++;
      `uvm_error("SPI_SB", $sformatf("transfer with no TXDATA write: %s", t.convert2string()))
    end
    else begin
      exp = mosi_exp.pop_front();
      if (t.mosi_seen !== exp) begin
        n_mosi_bad++;
        `uvm_error("SPI_SB", $sformatf("MOSI=0x%02h, TXDATA was 0x%02h (%s)", t.mosi_seen, exp, t.convert2string()))
      end
      else n_mosi_ok++;
    end
    miso_exp.push_back(t.miso_seen);
  endfunction

  virtual function void check_phase(uvm_phase phase);
    if (mosi_exp.size() != 0)
      `uvm_error("SPI_SB", $sformatf("%0d TXDATA writes never appeared on MOSI", mosi_exp.size()))
    if (miso_exp.size() != 0)
      `uvm_error("SPI_SB", $sformatf("%0d received bytes never read from RXDATA", miso_exp.size()))
    if (n_mosi_ok == 0)
      `uvm_error("SPI_SB", "scoreboard checked nothing")
  endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SPI_SB", $sformatf("MOSI ok=%0d bad=%0d | MISO ok=%0d bad=%0d | line_bad=%0d slverr_bad=%0d",
              n_mosi_ok, n_mosi_bad, n_miso_ok, n_miso_bad, n_line_bad, n_slverr_bad), UVM_LOW)
  endfunction

endclass
