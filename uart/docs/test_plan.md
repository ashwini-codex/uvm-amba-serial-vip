# APB UART: test plan

DUT: `uart/rtl/apb_uart.sv`. It's a UART with an APB3 register interface: 8 data bits, LSB first, optional even/odd parity and 1 stop bit, with the bit time set by `BAUD.div` (PCLK cycles per bit). The transmitter takes one byte at a time (write TXDATA when STATUS.tx_busy = 0). The receiver uses a 2-FF synchronizer and samples at mid-bit. It flags parity and framing errors per byte and sets overrun if a new byte arrives before RXDATA is read.

| Offset | Register | Access | Fields |
|---|---|---|---|
| 0x00 | CTRL | RW | [0] parity_en, [1] parity_odd |
| 0x04 | BAUD | RW | [15:0] div (reset 16) |
| 0x08 | TXDATA | W | [7:0] byte to send |
| 0x0C | RXDATA | R | [7:0] data, [8] parity_err, [9] frame_err, [10] valid. Reading clears valid, the errors and overrun |
| 0x10 | STATUS | R | [0] tx_busy, [1] rx_valid, [2] rx_overrun |

Bench: `uart/tb/` plus `common/apb_agent/`. It has two agents: the shared APB master agent for registers, and a UART agent that drives `rx` and decodes both `tx` and `rx`. A **virtual sequencer** holds both sub-sequencers, and the virtual sequences program the DUT over APB and run serial traffic at the same time.

## 1. Architecture

```
tb_top
 ├─ apb_if, uart_if (SVA)
 ├─ apb_uart (DUT)
 └─ uart_*_test       gets both vifs from config_db, fills uart_env_cfg
     └─ uart_env
         ├─ apb_agt   (common APB agent)
         ├─ uart_agt  driver (rx, error injection) + monitor (tx and rx)
         ├─ vsqr      uart_vsequencer {apb_sqr, uart_sqr, cfg}
         ├─ sb        TX: TXDATA writes == tx frames; RX: rx frames == RXDATA reads
         └─ cov       frame_cg, reg_cg
```

Each virtual sequence first calls `configure()`. It writes BAUD and CTRL over APB, then updates `uart_agent_cfg` (div and parity) so the agent's driver and monitor follow the new line settings.

## 2. Feature → test → check

| # | Feature | Test / virtual sequence | Check / coverpoint | Status |
|---|---|---|---|---|
| F1 | TX framing (start, 8 data LSB first, stop) | `uart_tx_test` / `uart_tx_vseq` | SB TX compare; monitor frame_err | Written |
| F2 | TX parity even / odd / none | `uart_full_test` (every mode) | SB (monitor flags wrong parity); `cp_parity`, `x_dir_parity` | Written |
| F3 | RX data path | `uart_rx_test` / `uart_rx_vseq` | SB RX compare | Written |
| F4 | Full duplex (TX and RX at once, APB shared) | `uart_full_test` / `uart_duplex_vseq` | SB both directions | Written |
| F5 | Baud rates: fast, mid, slow | `uart_full_test` (3 speed buckets per mode) | `cp_div`, `x_parity_div` | Written |
| F6 | RX parity error detection | `uart_err_test` / `uart_err_vseq` | SB compares RXDATA[8]; `cp_err.parity`, `x_err_parity` | Written |
| F7 | RX framing error detection | `uart_err_test` / `uart_err_vseq` | SB compares RXDATA[9]; `cp_err.frame` | Written |
| F8 | Overrun: two frames with no read in between | `uart_err_test` / `uart_overrun_vseq` | vseq checks STATUS[2]; SB keeps only the newest byte | Written |
| F9 | Reading RXDATA clears valid and overrun | `uart_overrun_vseq` | vseq reads STATUS after RXDATA | Written |
| F10 | Register read-back, PSLVERR on unmapped addresses | `uart_full_test` / `uart_reg_vseq` | vseq read-back; SB PSLVERR; `reg_cg` | Written |
| F11 | Data corners 0x00, 0xFF, 0x55, 0xAA | all (`rand_byte`) | `cp_data` | Written |
| F12 | Lines never X; no 1-cycle glitches on tx | all | `a_tx_known`, `a_rx_known`, `a_tx_no_glitch`; APB SVA | Written |

### Covergroups (`uart_coverage.sv`)

| Covergroup | Coverpoints / crosses |
|---|---|
| `frame_cg` | dir {TX, RX}, data {00, FF, 55, AA, low, high}, parity {none, even, odd}, div {4–8, 9–16, 17+}, err {none, frame, parity, both}; crosses dir×parity, parity×div, err×parity (parity errors with no parity bit are ignored) |
| `reg_cg` | register {CTRL, BAUD, TXDATA, RXDATA, STATUS, unmapped} × dir (writes to read-only registers and reads of TXDATA are ignored) |

## 3. Injected bugs

| Define | Bug | Expected to fail | Best test | Caught? |
|---|---|---|---|---|
| `BUG_UART_PARITY` | TX sends the inverted parity bit | SB TX (monitor sees parity_err) | `uart_full_test` | |
| `BUG_UART_RXMSB` | RX drops data bit 7 | SB RX compare | `uart_rx_test` | |

## 4. Results

Fill in from real runs only.

| Test | Seed | TX match | RX match | Mismatch | UVM_ERROR | frame_cg % | reg_cg % | Stmt % | Branch % | Result |
|---|---|---|---|---|---|---|---|---|---|---|
| uart_tx_test   | | | | | | | | | | |
| uart_rx_test   | | | | | | | | | | |
| uart_err_test  | | | | | | | | | | |
| uart_full_test | | | | | | | | | | |

| Define | Test | UVM_ERROR count | First failing check | Result |
|---|---|---|---|---|
| BUG_UART_PARITY | uart_full_test | | | |
| BUG_UART_RXMSB  | uart_rx_test   | | | |

## 5. Running

See the top-level `README.md`. Default test: `uart_full_test`. Plusargs: `+NUM_TXNS=<n>` (bytes per phase, default 20), `+DUMP`.

## 6. Assumptions and limits

- Software writes TXDATA only when tx_busy = 0 (the virtual sequences poll first). A write while busy is ignored by the DUT, and the scoreboard does not model that.
- Line settings change only when both lines are idle.
- 1 stop bit only, with no FIFOs. Bit timing is counted in PCLK cycles; the bench doesn't model baud-rate mismatch.
