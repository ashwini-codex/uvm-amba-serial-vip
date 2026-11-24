// ----------------------------------------------------------------------------
// apb_tb_pkg.sv : APB memory bench (env, scoreboard, coverage, sequences, tests)
// ----------------------------------------------------------------------------
package apb_tb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import apb_agent_pkg::*;

  `include "apb_env_cfg.sv"
  `include "apb_scoreboard.sv"
  `include "apb_coverage.sv"
  `include "apb_env.sv"
  `include "apb_seqs.sv"
  `include "apb_tests.sv"

endpackage
