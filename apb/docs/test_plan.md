# APB3 slave memory: test plan

DUT: `apb/rtl/apb_mem.sv`. It's an APB3 slave with 256 × 32-bit words (byte addresses `0x000`–`0x3FC`). It inserts 0–3 random wait states per transfer from an LFSR and returns PSLVERR for any address ≥ `0x400`. An out-of-range write is dropped and an out-of-range read returns 0. Memory resets to 0.

Bench: `apb/tb/` plus the shared agent in `common/apb_agent/`. It's a UVM 1.2 environment with one active APB master agent (sequencer, driver and monitor), a scoreboard with a reference memory, a coverage subscriber, and SVA in `apb_if`.

## 1. Architecture

```
tb_top
 ├─ apb_if   (drv_cb / mon_cb, protocol SVA, cover properties)
 ├─ apb_mem  (DUT)
 └─ run_test()
     └─ apb_*_test        gets vif from config_db ("apb_vif"), fills apb_env_cfg,
         │                 reads +NUM_TXNS, sets config_db("env*","cfg")
         └─ apb_env       passes cfg.apb_cfg to config_db("agent*","apb_cfg")
             ├─ apb_agent      (common) sequencer + driver + monitor
             ├─ apb_scoreboard reference memory, PRDATA + PSLVERR checks
             └─ apb_coverage   apb_cg
```

## 2. Feature → test → check

Status: **Written** means the code exists but has not been run. Fill in **Pass**/**Fail** only from a real run.

| # | Feature | Test / sequence | Assertion / check / coverpoint | Status |
|---|---|---|---|---|
| F1 | SETUP is followed by ACCESS | all | `a_setup_to_access`, `a_enable_needs_sel` | Written |
| F2 | PADDR/PWRITE/PWDATA held from SETUP into ACCESS | all | `a_setup_stable` | Written |
| F3 | Wait states: master holds everything while PREADY is low | all (DUT LFSR) | `a_wait_stable`; `cp_wait` {0, 1, 2+}; `c_wait_state` | Written |
| F4 | PENABLE drops after each transfer | all | `a_enable_drops` | Written |
| F5 | Back-to-back transfers (no IDLE between) | `apb_rand_test` / `apb_b2b_seq` | `cp_gap.back_to_back`; `c_back_to_back` | Written |
| F6 | Idle gaps of different lengths | all (`idle_cycles` dist) | `cp_gap` {0, 1–2, 3+} | Written |
| F7 | Write then read the same word | `apb_rw_test` / `apb_wr_rd_seq` | SB read compare; `cp_dir_seq.wr_rd` | Written |
| F8 | First/last word, all-0 / all-1 data | `apb_rw_test` / `apb_corner_seq` | SB; `cp_addr_edge`, `cp_data` | Written |
| F9 | Reads and writes across low/mid/high ranges | `apb_rand_test` / `apb_rand_seq` | SB; `x_dir_addr` | Written |
| F10 | Out-of-range access → PSLVERR, no write | `apb_err_test` / `apb_err_seq` | SB PSLVERR check; `cp_err`, `cp_addr.invalid`, `cp_addr_edge.first_bad`, `x_dir_err` | Written |
| F11 | Unwritten words read as 0 | `apb_rand_test` | SB (model default 0) | Written |
| F12 | No X on bus signals | all | `a_no_x_ctrl`, `a_no_x_bus`, `a_no_x_wdata`, `a_no_x_rdata` | Written |

### Covergroup `apb_cg` (`apb_coverage.sv`)

| Coverpoint / cross | Bins |
|---|---|
| `cp_dir` | read, write |
| `cp_dir_seq` (transitions) | rd→rd, rd→wr, wr→rd, wr→wr |
| `cp_addr` | low 0x000–0x0FF, mid 0x100–0x2FF, high 0x300–0x3FF, invalid ≥ 0x400 |
| `cp_addr_edge` | 0x000, 0x3FC, 0x400 |
| `cp_data` | 0x00000000, 0xFFFFFFFF, other |
| `cp_wait` | 0, 1, 2+ |
| `cp_gap` | back-to-back, 1–2, 3+ |
| `cp_err` | OKAY, SLVERR |
| `x_dir_addr`, `x_dir_wait`, `x_dir_gap`, `x_dir_err` | 8, 6, 6, 4 |

## 3. Injected bugs

| Define | Bug in `apb_mem` | Expected to fail | Best test | Caught? |
|---|---|---|---|---|
| `BUG_APB_ALIAS` | Writes to the top quarter (0x300–0x3FF) land 0x100 lower | SB read mismatch | `apb_full_test` | |
| `BUG_APB_SLVERR` | PSLVERR never asserts | SB PSLVERR check | `apb_err_test` | |

## 4. Results

Fill in from real runs only.

### Clean DUT

| Test | Seed | Writes | Reads | Mismatch | UVM_ERROR | apb_cg % | Stmt % | Branch % | Result |
|---|---|---|---|---|---|---|---|---|---|
| apb_base_test | | | | | | | | | |
| apb_rw_test   | | | | | | | | | |
| apb_rand_test | | | | | | | | | |
| apb_err_test  | | | | | | | | | |
| apb_full_test | | | | | | | | | |

### Bug runs

| Define | Test | UVM_ERROR count | First failing check | Result |
|---|---|---|---|---|
| BUG_APB_ALIAS  | apb_full_test | | | |
| BUG_APB_SLVERR | apb_err_test  | | | |

## 5. Running

See the top-level `README.md`. Default test: `apb_full_test`. Plusargs: `+UVM_TESTNAME=<test>`, `+NUM_TXNS=<n>` (default 200), `+DUMP` (writes `dump.vcd`).

## 6. Assumptions and limits

- The master issues one transfer at a time (APB has no pipelining).
- The scoreboard checks only what the monitor sees on the bus; the driver's copy of PRDATA isn't used for checking.
- SVA failures are reported with `uvm_error` (ID `APB_SVA`), so they count toward the `TEST PASSED` / `TEST FAILED` verdict.
