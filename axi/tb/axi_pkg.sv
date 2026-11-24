// ============================================================================
// axi_pkg.sv  --  types, helpers and every class of the AXI4 UVM bench
// ============================================================================
package axi_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // bench-wide parameters (must match axi_if / axi_mem)
  // --------------------------------------------------------------------------
  parameter int AXI_ADDR_W     = 32;
  parameter int AXI_DATA_W     = 32;
  parameter int AXI_ID_W       = 4;
  parameter int AXI_DATA_BYTES = AXI_DATA_W / 8;
  parameter int AXI_MEM_BYTES  = 4096;

  // --------------------------------------------------------------------------
  // types
  // --------------------------------------------------------------------------
  typedef enum bit       {AXI_READ = 1'b0, AXI_WRITE = 1'b1}                 axi_rw_e;
  typedef enum bit [1:0] {AXI_FIXED = 2'b00, AXI_INCR = 2'b01, AXI_WRAP = 2'b10} axi_burst_e;
  typedef enum bit [1:0] {AXI_OKAY = 2'b00, AXI_EXOKAY = 2'b01,
                          AXI_SLVERR = 2'b10, AXI_DECERR = 2'b11}            axi_resp_e;
  // how the sequence item fills WSTRB
  typedef enum           {STRB_FULL, STRB_RANDOM, STRB_NONE}                 axi_strb_mode_e;
  // what a beat's WSTRB turned out to be (for coverage)
  typedef enum           {STRB_K_FULL, STRB_K_PARTIAL, STRB_K_NONE}          axi_strb_kind_e;
  typedef enum           {CH_AW, CH_W, CH_B, CH_AR, CH_R}                    axi_chan_e;

  // --------------------------------------------------------------------------
  // AXI address math (AMBA AXI spec, section A3.4.1)
  // --------------------------------------------------------------------------
  // Address of beat n (0-based) of a burst.
  function automatic bit [31:0] axi_beat_addr(bit [31:0]   start,
                                              bit [2:0]    size,
                                              bit [7:0]    len,
                                              axi_burst_e  burst,
                                              int unsigned n);
    bit [31:0] nbytes, aligned, total, lower, a;
    nbytes  = 32'd1 << size;
    aligned = start & ~(nbytes - 32'd1);
    case (burst)
      AXI_FIXED: a = start;
      AXI_INCR : a = (n == 0) ? start : aligned + n * nbytes;
      AXI_WRAP : begin
        total = nbytes * (len + 32'd1);          // power of two for legal WRAP
        lower = start & ~(total - 32'd1);
        a     = start + n * nbytes;
        if (a >= lower + total) a = a - total;
      end
      default  : a = start;
    endcase
    return a;
  endfunction

  // Byte lanes of the 32-bit bus that carry data for a beat at address a.
  function automatic bit [AXI_DATA_BYTES-1:0] axi_lane_mask(bit [31:0] a, bit [2:0] size);
    int unsigned nbytes, lo, hi;
    bit [AXI_DATA_BYTES-1:0] m;
    nbytes = 1 << size;
    lo     = a % AXI_DATA_BYTES;
    hi     = ((a & ~(nbytes - 1)) % AXI_DATA_BYTES) + nbytes - 1;
    if (hi > AXI_DATA_BYTES - 1) hi = AXI_DATA_BYTES - 1;
    m = '0;
    for (int unsigned i = lo; i <= hi; i++) m[i] = 1'b1;
    return m;
  endfunction

  function automatic bit axi_addr_in_range(bit [31:0] a);
    return (a < AXI_MEM_BYTES);
  endfunction

  // --------------------------------------------------------------------------
  // classes
  // --------------------------------------------------------------------------
  `include "axi_seq_item.sv"
  `include "axi_env_cfg.sv"
  `include "axi_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_agent.sv"
  `include "axi_scoreboard.sv"
  `include "axi_coverage.sv"
  `include "axi_env.sv"
  `include "axi_seq_lib.sv"
  `include "axi_base_test.sv"
  `include "axi_tests.sv"

endpackage
