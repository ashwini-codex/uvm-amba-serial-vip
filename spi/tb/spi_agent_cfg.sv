// ----------------------------------------------------------------------------
// spi_agent_cfg.sv : SPI slave agent settings (mode follows the DUT's CTRL)
// ----------------------------------------------------------------------------
class spi_agent_cfg extends uvm_object;

  virtual spi_if           vif;
  uvm_active_passive_enum  is_active = UVM_ACTIVE;

  bit          cpol = 1'b0;
  bit          cpha = 1'b0;
  int unsigned div  = 4;      // DUT reset value of CLKDIV

  `uvm_object_utils(spi_agent_cfg)

  function new(string name = "spi_agent_cfg");
    super.new(name);
  endfunction

endclass
