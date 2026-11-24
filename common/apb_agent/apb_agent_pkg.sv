// ----------------------------------------------------------------------------
// apb_agent_pkg.sv : reusable APB master agent
// Compile apb_if.sv before this package.
// ----------------------------------------------------------------------------
package apb_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "apb_seq_item.sv"
  `include "apb_agent_cfg.sv"
  `include "apb_driver.sv"
  `include "apb_monitor.sv"
  `include "apb_agent.sv"
  `include "apb_base_seqs.sv"

endpackage
