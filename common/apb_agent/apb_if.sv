// ----------------------------------------------------------------------------
// apb_if.sv : APB3 interface with driver/monitor clocking blocks and protocol SVA
// Shared by every bench that talks to a DUT over APB.
// ----------------------------------------------------------------------------
`include "uvm_macros.svh"

interface apb_if (input logic PCLK, input logic PRESETn);

  import uvm_pkg::*;

  logic [31:0] PADDR;
  logic        PSEL;
  logic        PENABLE;
  logic        PWRITE;
  logic [31:0] PWDATA;
  logic [31:0] PRDATA;
  logic        PREADY;
  logic        PSLVERR;

  // Master-side driving: outputs change 1ns after the edge, inputs sampled
  // just before the edge.
  clocking drv_cb @(posedge PCLK);
    default input #1step output #1;
    output PADDR, PSEL, PENABLE, PWRITE, PWDATA;
    input  PRDATA, PREADY, PSLVERR;
  endclocking

  clocking mon_cb @(posedge PCLK);
    default input #1step;
    input PRESETn, PADDR, PSEL, PENABLE, PWRITE, PWDATA, PRDATA, PREADY, PSLVERR;
  endclocking

  // --------------------------------------------------------------------------
  // Protocol assertions (setup -> access phase, stability, no X)
  // --------------------------------------------------------------------------
  // A setup cycle (PSEL && !PENABLE) must be followed by an access cycle.
  a_setup_to_access : assert property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> (PSEL && PENABLE))
    else `uvm_error("APB_SVA", "setup phase not followed by access phase")

  // PENABLE is only legal while PSEL is high.
  a_enable_needs_sel : assert property (@(posedge PCLK) disable iff (!PRESETn)
    PENABLE |-> PSEL)
    else `uvm_error("APB_SVA", "PENABLE high without PSEL")

  // Address, direction and write data hold from setup into access.
  a_setup_stable : assert property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) |=> ($stable(PADDR) && $stable(PWRITE) && (!PWRITE || $stable(PWDATA))))
    else `uvm_error("APB_SVA", "PADDR/PWRITE/PWDATA changed between setup and access")

  // While the slave holds PREADY low, the master must hold everything.
  a_wait_stable : assert property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && !PREADY) |=>
      (PSEL && PENABLE && $stable(PADDR) && $stable(PWRITE) && (!PWRITE || $stable(PWDATA))))
    else `uvm_error("APB_SVA", "master changed signals during a wait state")

  // After a completed transfer PENABLE must drop (either IDLE or a new SETUP).
  a_enable_drops : assert property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PREADY) |=> !PENABLE)
    else `uvm_error("APB_SVA", "PENABLE stayed high after transfer completed")

  // No X on control, and no X on the bus when it is in use.
  a_no_x_ctrl : assert property (@(posedge PCLK) disable iff (!PRESETn)
    !$isunknown({PSEL, PENABLE}))
    else `uvm_error("APB_SVA", "X on PSEL/PENABLE")

  a_no_x_bus : assert property (@(posedge PCLK) disable iff (!PRESETn)
    PSEL |-> !$isunknown({PADDR, PWRITE}))
    else `uvm_error("APB_SVA", "X on PADDR/PWRITE while selected")

  a_no_x_wdata : assert property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PWRITE) |-> !$isunknown(PWDATA))
    else `uvm_error("APB_SVA", "X on PWDATA during write")

  a_no_x_rdata : assert property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PREADY && !PWRITE) |-> !$isunknown({PRDATA, PSLVERR}))
    else `uvm_error("APB_SVA", "X on PRDATA/PSLVERR at read completion")

  // Cover the interesting handshakes so the log shows they really happened.
  c_zero_wait : cover property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) ##1 (PENABLE && PREADY));
  c_wait_state : cover property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && !PENABLE) ##1 (PENABLE && !PREADY) ##[1:$] (PENABLE && PREADY));
  c_back_to_back : cover property (@(posedge PCLK) disable iff (!PRESETn)
    (PSEL && PENABLE && PREADY) ##1 (PSEL && !PENABLE));

endinterface
