# Running the benches on EDA Playground and recording results

This is the step-by-step runbook for getting real numbers into the results tables in each `<bench>/docs/test_plan.md`. Record only what the log and the tool print. Leave a cell blank if a run did not produce the number.

Nothing here has been run yet. If a step fails (compile error, fatal, hang), write down the log lines and fix the bench before filling any table.

## 1. One-time setup

1. Sign in at <https://www.edaplayground.com> (Riviera-PRO needs a login).
2. In the left panel choose:
   - **Testbench + Design:** SystemVerilog/Verilog
   - **UVM / OVM:** UVM 1.2
   - **Tools & Simulators:** Aldec Riviera-PRO
3. Tick **Open EPWave after run** only if you want waveforms (it needs `+DUMP`, or `+define+DUMP` for AXI). Leave it off for long runs.

## 2. Load a bench

From the repo root, bundle the bench into a flat folder:

```bash
scripts/make_edap.sh uart
```

Replace `uart` with `apb`, `axi`, `spi` or `i2c`. The script writes `edap/<bench>/`. Then in EDA Playground:

1. Paste `design.sv` into the **design.sv** tab and `testbench.sv` into the **testbench.sv** tab.
2. Add every other file in `edap/<bench>/` with the **+** button, using the exact same file name. Includes use bare names, so the names must match.
3. Re-bundle and re-paste any time a source file changes. Old pastes go stale.

## 3. Smoke test first

Before the full matrix, run the base test once to confirm the bench compiles, elaborates and runs:

| Bench | Run Options |
|---|---|
| apb  | `+UVM_TESTNAME=apb_base_test` |
| axi  | `+UVM_TESTNAME=axi_base_test` |
| uart | `+UVM_TESTNAME=uart_base_test` |
| spi  | `+UVM_TESTNAME=spi_base_test` |
| i2c  | `+UVM_TESTNAME=i2c_base_test` |

Press **Run**. If the log shows compile errors, a `UVM_FATAL`, or no UVM report summary, stop and fix that first.

## 4. Run matrix

Each row is one run. Set the test in **Run Options** (`+UVM_TESTNAME=<test>`). For bug runs, also add the define to **Compile Options**, one at a time, and remove it afterwards.

### Clean DUT (no defines)

| Bench | Tests (one run each) |
|---|---|
| apb  | `apb_base_test`, `apb_rw_test`, `apb_rand_test`, `apb_err_test`, `apb_full_test` |
| axi  | `axi_base_test`, `axi_single_test`, `axi_burst_test`, `axi_rand_test`, `axi_err_test` |
| uart | `uart_tx_test`, `uart_rx_test`, `uart_err_test`, `uart_full_test` |
| spi  | `spi_mode_test`, `spi_rand_test`, `spi_full_test` |
| i2c  | `i2c_wr_rd_test`, `i2c_rand_test`, `i2c_full_test` |

### Bug runs (one define per run)

| Compile Options | Run Options |
|---|---|
| `+define+BUG_APB_ALIAS`  | `+UVM_TESTNAME=apb_full_test` |
| `+define+BUG_APB_SLVERR` | `+UVM_TESTNAME=apb_err_test` |
| `+define+BUG_AXI_WRAP`    | `+UVM_TESTNAME=axi_burst_test` |
| `+define+BUG_AXI_WSTRB`   | `+UVM_TESTNAME=axi_rand_test` |
| `+define+BUG_AXI_RLAST`   | `+UVM_TESTNAME=axi_burst_test` |
| `+define+BUG_AXI_ID`      | `+UVM_TESTNAME=axi_single_test` |
| `+define+BUG_AXI_RESP`    | `+UVM_TESTNAME=axi_err_test` |
| `+define+BUG_AXI_RSTABLE` | `+UVM_TESTNAME=axi_rand_test` |
| `+define+BUG_AXI_FIXED`   | `+UVM_TESTNAME=axi_burst_test` |
| `+define+BUG_UART_PARITY` | `+UVM_TESTNAME=uart_full_test` |
| `+define+BUG_UART_RXMSB`  | `+UVM_TESTNAME=uart_rx_test` |
| `+define+BUG_SPI_CPOL` | `+UVM_TESTNAME=spi_mode_test` |
| `+define+BUG_SPI_CPHA` | `+UVM_TESTNAME=spi_mode_test` |
| `+define+BUG_I2C_ACK`   | `+UVM_TESTNAME=i2c_wr_rd_test` |
| `+define+BUG_I2C_RDLSB` | `+UVM_TESTNAME=i2c_wr_rd_test` |

A bug is **caught** when the run ends with `*** ... FAILED` and at least one `UVM_ERROR` (scoreboard or `*_SVA`). A bug run that still prints `PASSED` is **not caught**. Record that as is.

### Optional knobs

- `+NUM_TXNS=<n>` shrinks or grows the run (defaults: APB 200, AXI per test, UART 20, SPI 25, I2C 15). If a long run such as `axi_rand_test` (1500 transactions) times out on EDA Playground, lower it and note the value in the table row.
- AXI also takes `+ERR_PCT=<n>` and `+ZERO_DELAY`.
- `+UVM_VERBOSITY=UVM_HIGH` prints every transaction. Use it only when debugging.
- Seed: the AXI test plan (section 5) suggests `-sv_seed <n>`. Check the simulator command EDA Playground echoes at the top of the log to confirm the switch. If the log prints the seed, copy it. Otherwise pass a fixed `-sv_seed` yourself and record that number.

## 5. What to copy from each log

Search the log for these. Copy the lines, not a screenshot.

| Bench | Scoreboard line(s) | Coverage line(s) |
|---|---|---|
| apb  | `APB_SB` (writes, reads, match, mismatch) | `APB_COV` (`apb_cg`) |
| axi  | the `AXI scoreboard` block | the `AXI functional coverage` block |
| uart | `UART_SB` (TX/RX match, mismatch) | `UART_COV` (`frame_cg`, `reg_cg`) |
| spi  | `SPI_SB` (MOSI/MISO ok, bad) | `SPI_COV` (`xfer_cg`, `reg_cg`) |
| i2c  | `I2C_SB` (cmd, rxdata, ref mem) | `I2C_COV` (`byte_cg`, `txn_cg`, `cmd_cg`) |

Plus, for every run:

- the `*** ... PASSED ***` or `*** ... FAILED ***` line
- the `UVM_ERROR` and `UVM_FATAL` counts from the UVM Report Summary
- every line containing `_SVA` (assertion failures are `uvm_error`, so they are already in the error count)
- the seed
- for a bug run, the first `UVM_ERROR` line (that is the "First failing check" column)

## 6. Code coverage (Stmt % and Branch %)

Those two columns need Riviera's coverage database. The commands and the open questions are in the AXI test plan, section 5 ("Code coverage"). They are not confirmed on EDA Playground yet. Leave the columns blank until you have a number printed by the tool.

## 7. Paste the results

Two ways to get the numbers into the tables.

**A. Paste into the Claude chat.** For each run, paste a block like this:

```text
bench: uart
test: uart_full_test
defines: (none)            <- or +define+BUG_UART_PARITY
run options: +UVM_TESTNAME=uart_full_test +NUM_TXNS=20
seed: 12345

<paste: *_SB line(s)>
<paste: *_COV line(s)>
<paste: *** ... PASSED/FAILED *** line>
<paste: UVM Report Summary (UVM_ERROR / UVM_FATAL counts)>
<paste: any *_SVA lines, and for a bug run the first UVM_ERROR line>
```

The assistant copies the numbers into the matching table in `<bench>/docs/test_plan.md` and does not fill in anything the log did not print.

**B. Fill the tables yourself.** Open `<bench>/docs/test_plan.md`, section 4 "Results":

- **Clean DUT table:** one row per test. Seed, counts from the `*_SB` line, coverage percentages from the `*_COV` lines, `UVM_ERROR` count, then `PASS` or `FAIL`.
- **Bug runs table:** one row per define. `UVM_ERROR` count, the first failing check, then `Caught` or `Not caught`. Also tick the "Caught?" column in section 3.

## 8. After the runs

- Commit the updated test plans together with any bench fixes the runs forced.
- Update the **Status** section of `README.md`, which currently says nothing has been simulated.
- Only then change the resume wording about tracking coverage.
