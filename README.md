# UVM Verification of AMBA and Serial Interfaces

Five UVM 1.2 testbenches for APB, AXI4, UART, SPI and I2C, each around a small self-written DUT. They're meant to run on [EDA Playground](https://www.edaplayground.com) with Aldec Riviera-PRO.

| Bench | DUT | Agents | Main checks | Test plan |
|---|---|---|---|---|
| `apb/` | APB3 slave memory with random wait states and PSLVERR | APB master | Reference memory, PSLVERR, setup/access SVA | [apb/docs/test_plan.md](apb/docs/test_plan.md) |
| `axi/` | AXI4 slave memory: FIXED/INCR/WRAP, WSTRB, back-pressure | AXI master | Byte-addressed reference memory, VALID/READY SVA on all 5 channels | [axi/docs/test_plan.md](axi/docs/test_plan.md) |
| `uart/` | APB UART: parity, baud divisor, error flags | APB + UART, virtual sequencer | TX and RX data paths, parity/framing/overrun | [uart/docs/test_plan.md](uart/docs/test_plan.md) |
| `spi/` | APB SPI master, all 4 modes | APB + SPI slave, virtual sequencer | MOSI/MISO data, SCLK edges/period/idle level | [spi/docs/test_plan.md](spi/docs/test_plan.md) |
| `i2c/` | APB I2C master, byte commands, clock stretching | APB + I2C slave (with memory), virtual sequencer | Command order, RXDATA/ACK, reference memory, SDA/SCL SVA | [i2c/docs/test_plan.md](i2c/docs/test_plan.md) |

`common/apb_agent/` is a single APB master agent: interface, item, driver, monitor, agent and register read/write sequences. The APB, UART, SPI and I2C benches all reuse it.

## Layout

```
common/apb_agent/   shared APB agent (apb_if.sv, apb_agent_pkg.sv, ...)
<bench>/rtl/        DUT            -> design.sv on EDA Playground
<bench>/tb/         UVM bench      -> tb_top.sv is testbench.sv
<bench>/docs/       test plan + results tables
scripts/make_edap.sh  bundles one bench into a flat edap/<bench>/ folder
```

Every bench follows the same pattern:
- `tb_top` creates clock, reset, interfaces and DUT, puts each `virtual <x>_if` into `uvm_config_db`, and calls `run_test()`.
- The test gets the virtual interfaces, builds a `<bench>_env_cfg` (agent configs, active/passive, coverage on/off, `+NUM_TXNS`) and passes it down through `uvm_config_db`. The env hands each agent its own config the same way.
- Monitors publish on analysis ports to a scoreboard and a coverage collector. Protocol rules are SVA in the interfaces.
- The UART, SPI and I2C envs have a virtual sequencer holding the APB sequencer and the protocol agent's sequencer. Their virtual sequences program the DUT over APB and drive or answer the serial side.
- Every DUT has `` `ifdef BUG_* `` switches that inject a known bug, so you can show the checks catch it.

## Running on EDA Playground

1. Bundle the bench:
   ```bash
   scripts/make_edap.sh uart
   ```
   This writes `edap/uart/design.sv`, `edap/uart/testbench.sv` and the extra files. Use `all` to bundle all five.
2. On EDA Playground, select **UVM 1.2** and **Aldec Riviera-PRO**. Paste `design.sv` and `testbench.sv` into the two main tabs. Add every other file with the **+** button, using the same file name.
3. In **Run Options**, choose the test and any settings, for example:
   ```
   +UVM_TESTNAME=uart_full_test +NUM_TXNS=30
   ```
   Waveforms: add `+DUMP` to Run Options for APB/UART/SPI/I2C, or `+define+DUMP` to Compile Options for AXI.
4. To inject a bug, add `+define+BUG_UART_PARITY` (or another `BUG_*` from the test plan) to **Compile Options**.
5. At the end of the log, check:
   - the scoreboard summary (`*_SB`)
   - the coverage lines (`*_COV`, from `get_inst_coverage()`)
   - `*** TEST PASSED ***` or `FAILED`
   - the UVM report summary
   - any `*_SVA` messages (assertion failures are `uvm_error`s, so they also count toward `TEST FAILED`)

Default tests: `apb_full_test`, `uart_full_test`, `spi_full_test`, `i2c_full_test`. For AXI, pass `+UVM_TESTNAME` (see its test plan).

## Compile check (no simulator needed)

`scripts/compile_check.sh` compiles every bench against the UVM 1.2 source with [slang](https://github.com/MikePopoloski/slang). It builds each clean DUT and each `` `ifdef `` variant. One-time setup is in the script header. Then run:

```bash
scripts/compile_check.sh <path-to>/uvm-1.2/src all
```

The only warnings are 2 empty-loop warnings from inside the UVM library.

## Status

All five benches and all 16 `` `ifdef `` variants **compile cleanly** under slang with UVM 1.2. They are **not yet simulated**: there's no simulator on the machine they were written on. The results tables in each test plan are empty on purpose. Fill them in only from real runs, including code coverage, once Riviera's coverage options are confirmed on EDA Playground (see the AXI test plan, section 5).
# uvm-amba-serial-vip
