# AXI4 slave memory: test plan

DUT: `axi/rtl/axi_mem.sv`. It's an AXI4 slave with 32-bit data, a 32-bit address, a 4-bit ID and 4 KB of memory at `0x000`–`0xFFF`. It supports FIXED, INCR and WRAP bursts with AxLEN 0–15, AxSIZE of 1, 2 or 4 bytes, and WSTRB. It echoes the ID and inserts random READY back-pressure from an LFSR. It returns SLVERR for addresses outside the memory, and it handles one outstanding write and one outstanding read.

Bench: `axi/tb/`. It's a UVM 1.2 environment with one active master agent (sequencer, driver and monitor), a scoreboard with a byte-addressed reference memory, a coverage subscriber, and SVA in the interface.

## 1. Architecture

```
tb_top
 ├─ axi_if  (drv_cb / mon_cb clocking blocks, SVA, cover properties)
 ├─ axi_mem (DUT)
 └─ run_test()
     └─ axi_*_test            creates axi_env_cfg → uvm_config_db("env*","cfg")
         └─ axi_env
             ├─ axi_agent     (cfg.is_active)
             │   ├─ axi_sequencer
             │   ├─ axi_driver   AW ∥ W threads, then B;  AR, then R until RLAST
             │   └─ axi_monitor  AW+W+B → write txn, AR+R → read txn → ap
             ├─ axi_scoreboard  reference memory, WSTRB + FIXED/INCR/WRAP math,
             │                  BRESP/RRESP/ID/beat-count checks, R data compare
             └─ axi_coverage    5 covergroups (cfg.has_coverage)
```

`tb_top` passes the virtual interface with `uvm_config_db#(virtual axi_if)::set(null,"*","vif",vif)`. The test passes the settings with `uvm_config_db#(axi_env_cfg)::set(this,"env*","cfg",cfg)`. The env, the agent and every sequence (through `m_sequencer`) read that config.

## 2. Feature → test → check

Status values: **Written** means the code exists but has not been run. **Pass**, **Fail** and **Closed** may only be filled in from a real simulator run.

| # | Feature | Test / sequence | Assertion / check / coverpoint | Status |
|---|---|---|---|---|
| F1 | Single-beat write and read, all sizes | `axi_single_test` / `axi_single_beat_seq` | SB R data compare; `cg_burst.cp_len.len_1`; `cg_burst.cp_size` | Written |
| F2 | FIXED burst addressing | `axi_burst_test` / `axi_len_size_sweep_seq`, `axi_burst_type_seq(FIXED)` | SB beat address = start for every beat; `x_burst_len_size` FIXED bins | Written |
| F3 | INCR burst addressing, including an unaligned start | `axi_burst_test` / sweep, `axi_burst_type_seq(INCR)` | SB aligned-increment math, first-beat lane mask; INCR bins | Written |
| F4 | WRAP burst addressing (len 2/4/8/16) | `axi_burst_test` / sweep, `axi_burst_type_seq(WRAP)` + `readback_container` | SB wrap math; INCR readback of the whole container; `a_aw_wrap`, `a_ar_wrap`; WRAP bins | Written |
| F5 | Every AxLEN 0–15 × AxSIZE 1/2/4 B | `axi_len_size_sweep_seq` | `x_burst_len_size` (33 bins) | Written |
| F6 | 4 KB boundary never crossed | all (item constraint `c_4k`) | `a_aw_4k`, `a_ar_4k` | Written |
| F7 | WSTRB byte enables (full / partial / none) | `axi_rand_test` / `axi_strobe_seq` (full write, then random-strobe write, then readback) | SB applies only strobed lanes; SB flags strobes outside the beat's lanes; `cg_wstrb.x_kind_size` | Written |
| F8 | ID echo on B and R | all | SB `BID == AWID`, `RID == ARID` on every beat | Written |
| F9 | SLVERR for out-of-range addresses; no aliasing | `axi_err_test` / `axi_err_seq`, `axi_rand_mix_seq(err_pct)` | SB expected BRESP/RRESP; the alias readback must be unchanged; `cg_addr.oor`, `cg_resp.slverr`; `c_b_slverr`, `c_r_slverr` | Written |
| F10 | VALID held until READY (AW, W, B, AR, R) | all | `a_aw_hold`, `a_w_hold`, `a_b_hold`, `a_ar_hold`, `a_r_hold` | Written |
| F11 | Payload stable while VALID && !READY | all | `a_aw_stable`, `a_w_stable`, `a_b_stable`, `a_ar_stable`, `a_r_stable` | Written |
| F12 | WLAST / RLAST exactly on beat AxLEN | all | `a_wlast_on_len`, `a_rlast_on_len`; SB beat count == AxLEN+1 | Written |
| F13 | B only after the last W handshake; R only after AR | all | `a_b_after_wlast`, `a_r_after_ar`, `a_w_after_aw` (rule specific to this DUT) | Written |
| F14 | No X/Z on control signals, or on payloads while VALID | all | `a_ctrl_known`, `a_*_known` | Written |
| F15 | Legal encodings (no reserved burst, size ≤ bus width) | all | `a_aw_legal`, `a_ar_legal` | Written |
| F16 | Handshake back-pressure on every channel | all (LFSR READY in the DUT, random VALID/READY delays in the driver) | `cg_hs.x_ch_wait` (5 channels × 4 wait buckets); `c_*_stall`, `c_w_b2b` | Written |
| F17 | Random read/write mix against the reference model | `axi_rand_test` / `axi_rand_mix_seq` | SB on every txn; `cg_addr.x_rw_range`; `cg_resp.x_rw_resp` | Written |

### Covergroups (`axi_coverage.sv`)

| Covergroup | Coverpoints / cross | Bins |
|---|---|---|
| `cg_burst` | burst {FIXED, INCR, WRAP} × len {1, 2–4, 5–8, 9–16} × size {1, 2, 4 B} | 36 − 3 ignored (WRAP × 1 beat) = 33 cross bins |
| `cg_addr` | rw × addr range {low 0–1023, mid 1024–3071, high 3072–4095, oor ≥ 4096} | 8 cross bins |
| `cg_resp` | rw × resp {OKAY, SLVERR} (EXOKAY/DECERR are illegal_bins) | 4 cross bins |
| `cg_wstrb` | per write beat: kind {full, partial, none} × size | 9 − 1 ignored (partial × 1 B) = 8 cross bins |
| `cg_hs` | channel {AW, W, B, AR, R} × wait {0, 1, 2–3, ≥4 cycles} | 20 cross bins |

## 3. Injected bugs

Compile with exactly one `+define+BUG_AXI_*` (or none for the clean DUT). Each row lists the checks that are expected to catch that bug. Confirm the "Caught?" column from a real run.

| Define | Bug in `axi_mem` | Expected to fail | Best test | Caught? |
|---|---|---|---|---|
| `BUG_AXI_WRAP` | The write path wraps back to the start address instead of the wrap boundary | SB R data mismatch (lower part of the container) | `axi_burst_test` | |
| `BUG_AXI_WSTRB` | WSTRB is ignored and all 4 lanes are written | SB R data mismatch on unstrobed lanes | `axi_rand_test` (`axi_strobe_seq`) | |
| `BUG_AXI_RLAST` | RLAST comes one beat early | `a_rlast_on_len`; SB beat count | `axi_burst_test` | |
| `BUG_AXI_ID` | BID/RID are returned inverted | SB BID/RID checks | any | |
| `BUG_AXI_RESP` | OKAY instead of SLVERR when out of range | SB BRESP/RRESP | `axi_err_test` | |
| `BUG_AXI_RSTABLE` | RDATA toggles while RVALID && !RREADY | `a_r_stable`; SB R data mismatch | `axi_rand_test` | |
| `BUG_AXI_FIXED` | The read path increments the address on FIXED bursts | SB R data mismatch | `axi_burst_test` | |

## 4. Results

Fill this in from real runs only. Leave a cell blank until a run produces the number. The coverage figures come from the `COV` report the coverage subscriber prints, and from the Riviera coverage report for code coverage.

### Clean DUT

| Test | Seed | Txns (SB) | Match | Mismatch | UVM_ERROR | cg_burst % | cg_addr % | cg_resp % | cg_wstrb % | cg_hs % | Stmt % | Branch % | Result |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| axi_base_test   | | | | | | | | | | | | | |
| axi_single_test | | | | | | | | | | | | | |
| axi_burst_test  | | | | | | | | | | | | | |
| axi_rand_test   | | | | | | | | | | | | | |
| axi_err_test    | | | | | | | | | | | | | |

### Bug runs

| Define | Test | UVM_ERROR count | First failing check | Result |
|---|---|---|---|---|
| BUG_AXI_WRAP    | axi_burst_test | | | |
| BUG_AXI_WSTRB   | axi_rand_test  | | | |
| BUG_AXI_RLAST   | axi_burst_test | | | |
| BUG_AXI_ID      | axi_single_test| | | |
| BUG_AXI_RESP    | axi_err_test   | | | |
| BUG_AXI_RSTABLE | axi_rand_test  | | | |
| BUG_AXI_FIXED   | axi_burst_test | | | |

## 5. Running on EDA Playground

1. Choose these settings:
   - **Testbench + Design:** SystemVerilog/Verilog
   - **UVM / OVM:** UVM 1.2
   - **Tools & Simulators:** Aldec Riviera-PRO
2. Fill the files:
   - **design.sv:** paste `axi/rtl/axi_mem.sv`.
   - **testbench.sv:** paste `axi/tb/tb_top.sv`.
   - **Extra files:** add each of these as a new file, with the same name, next to testbench.sv. Includes use bare file names, so the folder must be flat.
     ```
     axi_if.sv  axi_pkg.sv  axi_seq_item.sv  axi_env_cfg.sv  axi_driver.sv
     axi_monitor.sv  axi_agent.sv  axi_scoreboard.sv  axi_coverage.sv
     axi_env.sv  axi_seq_lib.sv  axi_base_test.sv  axi_tests.sv
     ```
3. Fill in **Run Options**:
   ```
   +UVM_TESTNAME=axi_rand_test
   ```
   You can also add `+NUM_TXNS=<n>`, `+ERR_PCT=<n>`, `+ZERO_DELAY` and `+UVM_VERBOSITY=UVM_HIGH` (prints every transaction). Use `-sv_seed <n>` or `-sv_seed random` for a different seed; check the exact seed switch in the command line that EDA Playground echoes for Riviera.
4. To inject a bug, add it to **Compile Options**:
   ```
   +define+BUG_AXI_WSTRB
   ```
   Add `+define+DUMP` to get `dump.vcd` for EPWave.
5. At the end of the log, check:
   - the `SB` block (match and mismatch counts)
   - the `COV` block (`get_inst_coverage()` for each covergroup)
   - `*** <test> PASSED ***` or `FAILED`
   - the UVM report summary

### Code coverage (Riviera-PRO)

The functional coverage percentages are printed by the bench itself. Code coverage needs Riviera's coverage database (ACDB). Aldec's own app-note scripts show these commands:

```
alog -coverage sb -coverage_options count ...   # compile with statement + branch coverage
asim -acdb ...                                   # simulate with the coverage database enabled
acdb save -file <name>.acdb                      # save the database after run -all
```

On EDA Playground, these go into a custom `run.do`: tick **Use run.do Tcl file** and add a file named `run.do`. The exact report command and the extra coverage letters (expression, toggle, FSM) haven't been confirmed here. Check them against the Riviera-PRO docs, or the command EDA Playground echoes, before recording code-coverage numbers. Record only the numbers the tool prints.

## 6. Assumptions and limits

- The master issues one burst at a time. Reads and writes never overlap, so the reference model needs no read/write ordering rules. The SVA burst trackers and the monitor assume in-order responses with one burst outstanding per direction.
- `axi_mem` accepts W beats only after the AW handshake. AXI allows a slave to do this. The driver still raises WVALID as soon as it chooses, without waiting for AWREADY.
- Read data is compared only on the active byte lanes of each beat. Out-of-range beats are checked for SLVERR but not for data.
- `axi_rand_test` is meant to close all five covergroups in one run, because a single EDA Playground run cannot merge coverage across tests. Confirm that from the `COV` report.
