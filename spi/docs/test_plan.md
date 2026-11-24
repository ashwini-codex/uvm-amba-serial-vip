# APB SPI master: test plan

DUT: `spi/rtl/apb_spi_master.sv`. It's an SPI master with an APB3 register interface. It sends one byte per chip-select, MSB first, in all four modes (CPOL/CPHA), with the SCLK half-period set by `CLKDIV` (≥ 2 PCLK cycles).

| Offset | Register | Access | Fields |
|---|---|---|---|
| 0x00 | CTRL | RW | [0] cpol, [1] cpha |
| 0x04 | CLKDIV | RW | [7:0] half-period (reset 4) |
| 0x08 | TXDATA | W | [7:0]; the write starts a transfer |
| 0x0C | RXDATA | R | [7:0] MISO byte, [8] done. Reading clears done |
| 0x10 | STATUS | R | [0] busy, [1] done |

Bench: `spi/tb/` plus `common/apb_agent/`. It has two agents: the shared APB master agent, and an **SPI slave agent**. The slave agent's reactive driver answers every transfer with a random MISO byte from `spi_rsp_seq`, which runs for the whole test. Its monitor records each CS window. A **virtual sequencer** holds both sub-sequencers.

## 1. Architecture

```
tb_top
 ├─ apb_if, spi_if (SVA, cpol_exp)
 ├─ apb_spi_master (DUT)
 └─ spi_*_test      starts spi_rsp_seq (fork/join_none), runs virtual sequences
     └─ spi_env
         ├─ apb_agt   (common APB agent)
         ├─ spi_agt   slave driver (MISO on shift edge) + monitor
         ├─ vsqr      spi_vsequencer {apb_sqr, spi_sqr, cfg}
         ├─ sb        MOSI == TXDATA, RXDATA == MISO, SCLK waveform checks
         └─ cov       xfer_cg, reg_cg
```

`configure()` writes CLKDIV and CTRL. It then updates `spi_agent_cfg` (cpol, cpha, div) and `spi_if.cpol_exp` so the agent and the SVA use the same mode.

## 2. Feature → test → check

| # | Feature | Test / virtual sequence | Check / coverpoint | Status |
|---|---|---|---|---|
| F1 | Mode 0–3 MOSI timing (MSB first) | `spi_mode_test` | SB MOSI compare; `cp_mode` | Written |
| F2 | Mode 0–3 MISO sampling | `spi_mode_test` | SB RXDATA compare | Written |
| F3 | SCLK idles at CPOL when CS asserts and releases | all | `a_idle_at_cs_fall`, `a_idle_at_cs_rise`; SB `idle_ok` | Written |
| F4 | Exactly 16 SCLK edges per byte | all | SB `num_edges == 16` | Written |
| F5 | SCLK half-period == CLKDIV | `spi_full_test` (every divider bucket) | SB `half_min == half_max == div`; `cp_div`, `x_mode_div` | Written |
| F6 | Each mode × each divider | `spi_full_test` | `x_mode_div` (16 bins) | Written |
| F7 | First and last bit per mode | all | `x_mode_mosi_ends`, `x_mode_miso_ends` | Written |
| F8 | Data corners | all | `cp_mosi`, `cp_miso` | Written |
| F9 | busy/done flags, done cleared by RXDATA read | all (`xfer` polls both) | vseq timeouts; SB reads only when done = 1 | Written |
| F10 | Register read-back, PSLVERR on unmapped addresses | `spi_full_test` / `spi_reg_vseq` | vseq checks; SB PSLVERR; `reg_cg` | Written |
| F11 | No X on the bus, SCLK pulses ≥ 2 cycles | all | `a_cs_known`, `a_bus_known`, `a_sclk_min_width` | Written |

## 3. Injected bugs

| Define | Bug | Expected to fail | Best test | Caught? |
|---|---|---|---|---|
| `BUG_SPI_CPOL` | SCLK always idles low | `a_idle_at_cs_*`; SB idle_ok / MOSI / MISO in modes 2 and 3 | `spi_mode_test` | |
| `BUG_SPI_CPHA` | MISO always sampled on the leading edge | SB RXDATA and MOSI in modes 1 and 3 | `spi_mode_test` | |

## 4. Results

Fill in from real runs only.

| Test | Seed | MOSI ok | MISO ok | Bad | UVM_ERROR | xfer_cg % | reg_cg % | Stmt % | Branch % | Result |
|---|---|---|---|---|---|---|---|---|---|---|
| spi_mode_test | | | | | | | | | | |
| spi_rand_test | | | | | | | | | | |
| spi_full_test | | | | | | | | | | |

| Define | Test | UVM_ERROR count | First failing check | Result |
|---|---|---|---|---|
| BUG_SPI_CPOL | spi_mode_test | | | |
| BUG_SPI_CPHA | spi_mode_test | | | |

## 5. Running

See the top-level `README.md`. Default test: `spi_full_test`. Plusargs: `+NUM_TXNS=<n>` (transfers per phase, default 25), `+DUMP`.

## 6. Assumptions and limits

- One byte per CS window; there is no multi-byte CS hold.
- The slave agent samples SCLK on PCLK, so CLKDIV must be ≥ 2 (the vseqs constrain this, and the SVA checks it).
- Writing TXDATA while busy is ignored by the DUT and isn't modelled. The vseqs always wait for busy = 0 first.
