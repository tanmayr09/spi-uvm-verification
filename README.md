# SPI Master + Slave — UVM Verification Testbench

A complete **UVM (Universal Verification Methodology) testbench** for a pair of SPI RTL modules written in SystemVerilog. Built from scratch as a learning project to practice functional verification — stimulus generation, protocol assertions, scoreboard checking, and functional coverage — all on real RTL with real bugs.

---

## Final Results

| Metric | Result |
|---|---|
| Compile | 0 Errors · 0 Warnings |
| Transactions | 514 (4 corners + 10 stress + 500 random) |
| Scoreboard checks | 1028 — **PASS=1028 FAIL=0** |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| SVA assertions | 14 assertions · 0 failures |
| Functional coverage | **94.6%** (avg of 6 covergroups) |
| RTL bugs found | **4** (all fixed before simulation) |

---

## Why Two Separate RTL Files?

Most production SPI controllers are a **single configurable module** — one file with a parameter like `MODE = MASTER` or `MODE = SLAVE` that selects behaviour at elaboration time. This is the industry standard because it means one RTL block to maintain, one set of tests, and one silicon implementation that can be used as either end.

This project uses **two separate modules** — `SPIMaster.sv` and `spiSlave.sv` — because the original RTL was written as an academic/learning exercise where each role is implemented independently. The interface contracts are identical (same signal names, same timing), so the verification methodology is exactly the same as it would be for a single configurable controller. The UVM testbench treats them as two separate agents on the same bus — which is also a realistic topology (a real SPI bus always has a master and one or more slaves as distinct physical devices).

The separation actually makes the testbench more interesting to verify: both sides must agree on every transferred byte, proven by the scoreboard checking `master_rx == slave_tx` and `slave_rx == master_tx` simultaneously on every transfer.

---

## Protocol

| Parameter | Value |
|---|---|
| SPI Mode | Mode 0 (CPOL=0, CPHA=0) |
| Bit order | MSB first |
| Frame size | 8 bits |
| Clock | 100 MHz system clock |
| Full-duplex | Yes — both sides exchange simultaneously |

---


> **EDA Playground note:** The simulator requires all code in two files — `design.sv` (RTL) and `testbench.sv` (TB). These are the merged versions of the individual files in `rtl/` and `tb/`.

---

## Testbench Architecture

```
┌─────────────────────────────────────────────────────────┐
│  spi_env                                                │
│                                                         │
│  ┌──────────────────┐        ┌──────────────────┐      │
│  │  spi_master_agent │        │  spi_slave_agent  │      │
│  │  ┌─────────────┐ │        │ ┌─────────────┐  │      │
│  │  │  sequencer  │ │        │ │  sequencer  │  │      │
│  │  │  driver     │ │        │ │  driver     │  │      │
│  │  │  monitor ───┼─┼──┐  ┌─┼─┼─ monitor   │  │      │
│  │  └─────────────┘ │  │  │  │ └─────────────┘  │      │
│  └──────────────────┘  │  │  └──────────────────┘      │
│                         ▼  ▼                            │
│                  ┌─────────────────┐                    │
│                  │  spi_scoreboard │──► spi_coverage    │
│                  │  PASS/FAIL check│                    │
│                  └─────────────────┘                    │
└─────────────────────────────────────────────────────────┘
          │                        │
    ┌─────┴──────┐          ┌──────┴─────┐
    │ SPIMaster  │◄─── SPI ─►│  spiSlave  │
    └────────────┘   bus     └────────────┘
```

| Component | Purpose |
|---|---|
| `spi_if` | Interface with clocking blocks (cb_master, cb_slave) — prevents race conditions |
| `spi_transaction` | Data object: master_data, slave_data, master_rx, slave_rx + constraints |
| `spi_master_driver` | Drives i_tx_ready and i_tx_byte, waits for o_byte_ready |
| `spi_slave_driver` | Preloads slave TX buffer **before** SS falls — critical RTL timing requirement |
| `spi_master_monitor` | Captures master_tx_byte and master_rx_byte at each transfer |
| `spi_slave_monitor` | Captures slave_data at **negedge SS** (before buffer overwrite), slave_rx after transfer |
| `spi_scoreboard` | Two checks per transfer: slave_rx==master_tx and master_rx==slave_tx |
| `spi_coverage` | 5 coverpoints — master_data, slave_data, full_duplex, master_rx, slave_rx |
| `spi_assertions` | 14 SVAs — reset, protocol, byte_ready pulse width, output stability |

---

## Tests

The default test `spi_full_test` runs three phases in one simulation:

| Phase | Name | Transfers | Description |
|---|---|---|---|
| 1 | Corner cases | 4 | Directed: (0x00↔0xFF), (0xFF↔0x00), (0xAA↔0x55), (0x55↔0xAA) |
| 2 | Stress | 10 | Back-to-back random, no inter-transfer gap |
| 3 | Random | 500 | Constrained-random |

Additional registered tests: `spi_base_test`, `spi_rand_test`, `spi_corners_test`, `spi_stress_test`, `spi_reset_test`.

---

## Assertions (SVA)

14 SystemVerilog assertions across 4 groups — all passed, 0 failures:

| Group | Assertions |
|---|---|
| Reset | SS HIGH, master_busy LOW, slave_busy LOW, MISO high-Z after reset |
| Protocol | SS low → both busy, SS high → slave not busy, MISO high-Z when idle, SCLK stable when idle |
| Byte-ready | master_byte_ready pulse = 1 cycle, slave_byte_ready pulse = 1 cycle, slave follows master within 5 cycles |
| Stability | master_rx_byte stable after byte_ready falls, slave_rx_byte stable, busy held if tx_ready during transfer |

---

## RTL Bugs Found

| # | File | Bug | Fix |
|---|---|---|---|
| B-01 | SPIMaster.sv | FSM never left IDLE — `!state==STATE_IDLE` always false due to operator precedence | Changed to `state!=STATE_IDLE` |
| B-02 | SPIMaster.sv | No SCLK generated — DIVIDE_FREQUENCY_SPI=0 caused divide-by-zero | Set to 1 |
| B-03 | spiSlave.sv | Slave busy at reset — r_ss reset value was `'0` (selected) | Changed to `1'b1` |
| B-04 | spiSlave.sv | Illegal non-blocking assignment in always_comb for w_miso | Changed `<=` to `=` |

---

## How to Run (EDA Playground)

1. Go to [edaplayground.com](https://edaplayground.com)
2. Paste contents of `tb/design.sv` into the **Design** tab
3. Paste contents of `tb/testbench.sv` into the **Testbench** tab
4. Set:
   - **Simulator:** Aldec Riviera-PRO
   - **UVM:** UVM 1.2
   - **Compile options:** `-timescale 1ns/1ns`
   - **Run options:** `+UVM_TESTNAME=spi_full_test +access +r`
5. Check **"Open EPWave after run"** for waveform viewing
6. Click **Run**

Expected output (end of log):
```
  TOTAL COVERAGE  : 94.6%
  Transactions checked : 514
  PASS                 : 1028
  FAIL                 : 0
  RESULT               : TEST PASSED
  UVM_ERROR :    0
  UVM_FATAL :    0
```

---

## Interactive Diagrams

Open these HTML files in any browser — no server needed:

- **[SPIMaster Block Diagram](docs/spi_master_diagram.html)** — click any block to see internal signal details
- **[spiSlave Block Diagram](docs/spi_slave_diagram.html)** — same for the slave
- **[Transaction Flow Diagram](docs/spi_transaction_flow.html)** — all 5 FSM states with signal waveform strip

---

## Tools

- **Simulator:** Aldec Riviera-PRO 2025.04 (EDU Edition)
- **UVM:** UVM 1.2
- **Language:** SystemVerilog (IEEE 1800-2017)
- **Platform:** EDA Playground

---

## Original RTL

RTL source: [github.com/oafonsoo/SPI-Module-in-SystemVerilog](https://github.com/oafonsoo/SPI-Module-in-SystemVerilog)
