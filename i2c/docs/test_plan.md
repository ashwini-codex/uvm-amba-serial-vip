# APB I2C master: test plan

DUT: `i2c/rtl/apb_i2c_master.sv`. It's a byte-level I2C master with an APB3 register interface. Software issues one command at a time (START, STOP, WRITE byte, READ byte with ACK/NACK) and polls STATUS.busy. SCL and SDA are open-drain. The master supports clock stretching: after releasing SCL it waits until the line is really high.

| Offset | Register | Access | Fields |
|---|---|---|---|
| 0x00 | CLKDIV | RW | [7:0]; quarter-period = CLKDIV + 2 PCLK cycles (reset 4) |
| 0x04 | CMD | W | [0] START, [1] STOP, [2] WRITE, [3] READ, [4] NACK |
| 0x08 | TXDATA | RW | [7:0] byte for WRITE |
| 0x0C | RXDATA | R | [7:0] byte from the last READ |
| 0x10 | STATUS | R | [0] busy, [1] rx_ack (1 = NACK), [2] bus_active |

Bench: `i2c/tb/` plus `common/apb_agent/`. It has two agents: the shared APB master agent, and an **I2C slave agent** at address 0x50 with a 256-byte register memory (EEPROM style: pointer byte, then data; the pointer persists). At each START the slave takes an `i2c_seq_item` from `i2c_rsp_seq` that says whether to NACK the address, NACK a data byte, or stretch SCL. The bus uses `tri1` nets for the pull-ups. A **virtual sequencer** holds both sub-sequencers.

## 1. Architecture

```
tb_top
 ├─ apb_if, i2c_if (tri1 scl/sda, m_*_oe from DUT, s_*_oe from agent, SVA + bit tracker)
 ├─ apb_i2c_master (DUT)
 └─ i2c_*_test      starts i2c_rsp_seq (fork/join_none), runs virtual sequences
     └─ i2c_env
         ├─ apb_agt   (common APB agent)
         ├─ i2c_agt   reactive slave driver (memory, ACK/NACK, stretch) + monitor
         ├─ vsqr      i2c_vsequencer {apb_sqr, i2c_sqr, cfg}
         ├─ sb        command order, TXDATA/RXDATA/rx_ack, reference memory mirror
         └─ cov       byte_cg, txn_cg, cmd_cg
```

The virtual sequences are written like driver software: `write_regs` sends S, addr+W, ptr, data…, P. `read_regs` sends S, addr+W, ptr, Sr, addr+R, data… (NACK on the last byte), P. `read_current` sends S, addr+R, data…, P. All three stop early on any NACK.

## 2. Feature → test → check

| # | Feature | Test / virtual sequence | Check / coverpoint | Status |
|---|---|---|---|---|
| F1 | START / STOP generation | all | SB command order; `c_start`, `c_stop` | Written |
| F2 | Repeated START | `read_regs` in every test | SB; `txn_cg.cp_start.rep_start`, `cp_end.rep_start`, `x_rw_start` | Written |
| F3 | WRITE byte puts TXDATA on SDA, MSB first | all | SB WRITE compare | Written |
| F4 | ACK/NACK after WRITE reported in STATUS.rx_ack | `i2c_rand_test` (random NACKs, wrong addresses) | SB rx_ack check; `x_kind_dir_ack` | Written |
| F5 | READ byte captured into RXDATA | all | SB RXDATA == bus byte | Written |
| F6 | Master ACK / NACK after READ | `read_regs`, `read_current` | SB requested ACK == bus ACK; `cmd_cg.cp_cmd` | Written |
| F7 | Write then read back through the slave memory | `i2c_wr_rd_test` / `i2c_wr_rd_vseq` | SB reference memory mirror | Written |
| F8 | Address match / mismatch | `i2c_rand_vseq` (15% wrong address) | `x_match_ack` | Written |
| F9 | Slave NACK on address or data mid-transaction | `i2c_rand_test` (rsp policy) | SB; vseq stops; `cp_aack`, `cp_ack` | Written |
| F10 | Clock stretching | `i2c_rand_test` (stretch 0–60 cycles) | DUT waits (SB and SVA still pass); `cp_strch`, `x_dir_strch`; `c_clock_stretch` | Written |
| F11 | Transfer lengths 0, 1, 2–4, 5+ bytes | `i2c_rand_vseq`, `i2c_wr_rd_vseq` | `x_rw_nbytes` | Written |
| F12 | SDA stable while SCL high, except START/STOP | all | `a_sda_stable_scl_high` (uses the in-interface bit counter) | Written |
| F13 | SDA setup/hold to SCL edges; minimum SCL high/low | all | `a_sda_setup`, `a_sda_hold`, `a_scl_min_high`, `a_scl_min_low` | Written |
| F14 | Slave only moves SDA while SCL is low | all | `a_slave_sda_scl_low` | Written |
| F15 | Bus speeds | `i2c_full_test` (3 CLKDIV buckets) | `cmd_cg.cp_div` | Written |
| F16 | Register read-back, PSLVERR on unmapped addresses | `i2c_full_test` / `i2c_reg_vseq` | vseq checks; SB PSLVERR; `cmd_cg.cp_reg` | Written |

## 3. Injected bugs

| Define | Bug | Expected to fail | Best test | Caught? |
|---|---|---|---|---|
| `BUG_I2C_ACK` | STATUS.rx_ack reports the inverted ACK bit | SB rx_ack check (the vseqs also see a fake NACK and STOP early) | `i2c_wr_rd_test` | |
| `BUG_I2C_RDLSB` | RXDATA bit 0 always 0 | SB RXDATA compare | `i2c_wr_rd_test` | |

## 4. Results

Fill in from real runs only.

| Test | Seed | Cmd ok | RXDATA ok | Ref mem ok | UVM_ERROR | byte_cg % | txn_cg % | cmd_cg % | Stmt % | Branch % | Result |
|---|---|---|---|---|---|---|---|---|---|---|---|
| i2c_wr_rd_test | | | | | | | | | | | |
| i2c_rand_test  | | | | | | | | | | | |
| i2c_full_test  | | | | | | | | | | | |

| Define | Test | UVM_ERROR count | First failing check | Result |
|---|---|---|---|---|
| BUG_I2C_ACK   | i2c_wr_rd_test | | | |
| BUG_I2C_RDLSB | i2c_wr_rd_test | | | |

## 5. Running

See the top-level `README.md`. Default test: `i2c_full_test`. Plusargs: `+NUM_TXNS=<n>` (transactions per phase, default 15), `+DUMP`.

## 6. Assumptions and limits

- Single master; no arbitration-lost detection. 7-bit addressing only.
- Software issues the next command only after busy = 0. Commands written while busy are ignored and not modelled.
- After ACKing a read byte, software must keep reading (NACK the last byte before Sr/STOP). The vseqs always do this.
- The slave's memory is a TB model, so the reference-memory check covers the whole write-then-read path. The DUT-specific checks are the command-order, TXDATA, RXDATA and rx_ack checks.
