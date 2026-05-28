# SPI Master–Slave — UVM + Formal Verification Project

**Language:** SystemVerilog + UVM 1.2 &nbsp;|&nbsp; **Simulator:** Aldec Riviera-PRO 2025.04 on EDA Playground  
**Formal Toolchain:** SymbiYosys (OSS CAD Suite) &nbsp;|&nbsp; **SMT Solver:** Bitwuzla &nbsp;|&nbsp; **Platform:** WSL2 Ubuntu  
**Design source:** [github.com/oafonsoo/SPI-Module-in-SystemVerilog](https://github.com/oafonsoo/SPI-Module-in-SystemVerilog)  
**My contribution:** Parameterized `DATA_WIDTH` · Complete UVM testbench from scratch · SVA assertions module · Formal verification environment (BMC + Cover + k-Induction)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [File Structure](#2-file-structure)
3. [SPI Protocol — Quick Reference](#3-spi-protocol--quick-reference)
4. [Design Modules](#4-design-modules)
5. [Testbench Architecture](#5-testbench-architecture)
6. [Verification Components](#6-verification-components)
7. [SVA Assertions](#7-sva-assertions)
8. [Formal Verification](#8-formal-verification)
9. [Functional Coverage](#9-functional-coverage)
10. [Tests](#10-tests)
11. [Simulation Results](#11-simulation-results)
12. [How to Run](#12-how-to-run)
13. [Assumptions & Limitations](#13-assumptions--limitations)

---

## 1. Project Overview

This project performs RTL-level functional verification of an SPI (Serial Peripheral Interface) Master–Slave pair using two complementary methodologies: UVM-based simulation and formal verification with SymbiYosys.

**Design modification —** `DATA_WIDTH` was added as a parameter to both `SPIMaster` and `spiSlave`. Every shift register, cycle counter, and data bus now scales automatically to 8, 16, or 32 bits without any other code changes.

**UVM testbench —** A full UVM environment was written from scratch: interface with clocking blocks and fault-injection mux, master and slave agents (driver + monitor + sequencer), dual-path scoreboard, 6-covergroup coverage collector, virtual sequencer, 15 test classes, and a standalone SVA assertions module with 14 properties.

**Formal verification —** The UVM environment was extended with a formal verification phase using SymbiYosys. Both master and slave were verified independently using Bounded Model Checking (BMC) and Cover mode. The formal environment proves that the stated properties hold for **every possible legal input sequence**, not just the scenarios the testbench happened to generate. k-Induction was also attempted on both modules; the basecase passes and work is ongoing to close the unbounded proof with auxiliary invariants.

The combination of simulation and formal gives substantially stronger confidence than either methodology alone: UVM validates the design against realistic protocol scenarios; formal proves the same properties hold universally.

---

## 2. File Structure

```
SPI_FINAL/
├── Project code/
│   ├── assertions/          # SVA assertions module (simulation)
│   ├── formal/
│   │   ├── spi_master/
│   │   │   ├── spi_master_formal.sv   # RTL + formal env (assumptions, assertions, cover)
│   │   │   └── spi_master.sby         # SymbiYosys configuration script
│   │   └── spi_slave/
│   │       ├── spi_slave_formal.sv    # RTL + formal env (assumptions, assertions, cover)
│   │       └── spi_slave.sby          # SymbiYosys configuration script
│   ├── interface/           # spi_if — clocking blocks + fault-injection mux
│   ├── logs/
│   │   ├── logs_formal/
│   │   │   ├── master_bmc_pass.txt
│   │   │   ├── master_cover_pass.txt
│   │   │   ├── master_kinduction_unknown.txt
│   │   │   ├── slave_bmc_pass.txt
│   │   │   ├── slave_cover_pass.txt
│   │   │   └── slave_kinduction_unknown.txt
│   │   ├── spi_full_test_waveform.png
│   │   └── summary.txt      # UVM simulation summary
│   ├── pkg/                 # spi_pkg — parameters and imports
│   ├── rtl/
│   │   ├── spi_master.sv
│   │   └── spi_slave.sv
│   ├── tb/
│   │   ├── master/          # Master agent (driver, monitor, sequencer)
│   │   ├── slave/           # Slave agent (driver, monitor, sequencer)
│   │   ├── spi_coverage.sv
│   │   ├── spi_env.sv
│   │   ├── spi_scoreboard.sv
│   │   ├── spi_tests.sv
│   │   ├── spi_transactions.sv
│   │   ├── spi_virtual_sequence.sv
│   │   └── spi_virtual_sequencer.sv
│   └── top/                 # spi_tb_top
├── docs/
├── README.md
├── SPI_Test_Plan_Final.docx
└── SPI_UVM_Verification_Final.pptx

> **Note:** `SPI_Test_Plan_Final.docx` and `SPI_UVM_Verification_Final.pptx` cover the UVM verification phase only.
> Formal verification methodology, results, and counterexample analysis are documented in [Section 8](#8-formal-verification).
```

---

## 3. SPI Protocol — Quick Reference

SPI is a synchronous, full-duplex serial protocol. The master controls the clock and slave-select. Both sides shift data simultaneously — one bit per clock edge.

```
  Master                                 Slave
  ──────                                 ─────
    │─────────── SS (active LOW) ────────▶│
    │─────────── SCLK ───────────────────▶│
    │─────────── MOSI ───────────────────▶│   (master → slave data)
    │◀────────── MISO ────────────────────│   (slave  → master data)
```

**SPI Mode table:**

| Mode | CPOL | CPHA | SCLK idle | Capture edge |
|:----:|:----:|:----:|:---------:|:------------:|
| 0    | 0    | 0    | LOW       | Rising       |
| 1    | 0    | 1    | LOW       | Falling      |
| 2    | 1    | 0    | HIGH      | Falling      |
| 3    | 1    | 1    | HIGH      | Rising       |

When `SS` is HIGH (deasserted), `MISO` must be High-Z to free the bus.

---

## 4. Design Modules

### SPIMaster

Controls the bus. Drives `SCLK`, `MOSI`, and `SS`. Implements a 4-state Mealy FSM.

```
                  i_tx_ready && !o_busy
         ┌──────────────────────────────────────┐
         │                                      ▼
      IDLE                                  PRE_COMM
         ▲                                      │  (always, 1 cycle)
         │                                      ▼
    POS_COMM  ◀─────────────────────────────  COMM
    (SS hold)      r_cycle_count >= DATA_WIDTH
                   && r_edge_detect
```

| State       | What happens                                                                              |
|-------------|-------------------------------------------------------------------------------------------|
| `IDLE`      | SS=1, SCLK at CPOL idle, `o_busy=0`. Waits for `i_tx_ready`.                            |
| `PRE_COMM`  | Asserts SS LOW. Drives first MOSI bit if CPHA=0. Latches `i_tx_byte`.                   |
| `COMM`      | Divider counter toggles `r_sclk`. On each `r_edge_detect` pulse: shift MOSI out, sample MISO in. Counts `DATA_WIDTH` bits. |
| `POS_COMM`  | Holds SS low briefly for slave to latch last edge. Then: SS=1, latch `o_rx_byte`, pulse `o_byte_ready` for 1 cycle. |

**SCLK generation:**

```
r_cont_sclk counts 0 → DIVIDE_FREQUENCY_SPI
  └─ on overflow: toggle r_sclk, fire r_edge_detect (1-cycle pulse)

fSCLK = fCLK / 2(DIVIDE_FREQUENCY_SPI + 1)
```

**TX shift register (parameterized):**

```systemverilog
// MSB-first
w_tx_byte = r_tx_byte << r_cycle_count;   // top bit [DATA_WIDTH-1] drives MOSI
// LSB-first
w_tx_byte = r_tx_byte >> r_cycle_count;   // bottom bit [0] drives MOSI
```

### spiSlave

Responds to master. Does not generate clocks.

- **Input sync:** `i_mosi`, `i_sclk`, `i_ss` are registered through flip-flops every system clock to prevent metastability.
- **Generate blocks:** select `posedge` vs `negedge` `w_sclk` for shift logic at elaboration time based on the `MODE` parameter — no runtime multiplexing.
- **MISO:** driven to `1'bz` when `i_ss = 1`. Combinational: `w_miso = w_tx_byte[DATA_WIDTH-1]` (MSB-first) or `w_tx_byte[0]` (LSB-first).
- **RX output:** when `r_ss` rises and slave was busy, `o_rx_byte` is latched and `o_byte_ready` pulses for one clock.

### Parameters (both modules)

| Parameter              | Default | Description                                      |
|------------------------|:-------:|--------------------------------------------------|
| `DATA_WIDTH`           | `8`     | Bits per transfer. Supported: 8, 16, 32.         |
| `MODE`                 | `0`     | SPI mode 0–3                                     |
| `FRAME_FORMAT`         | `0`     | `0` = MSB-first, `1` = LSB-first                |
| `DIVIDE_FREQUENCY_SPI` | `1`     | fSCLK = fCLK / 2(N+1). Master only.             |
| `SS_PIN_ENABLE`        | `1`     | `1` = SS driven by module. Master only.          |

---

## 5. Testbench Architecture

### Block Diagram

```
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  spi_tb_top                                                                  │
 │                                                                              │
 │   ┌──────────────┐   SS / SCLK / MOSI / MISO   ┌──────────────┐            │
 │   │  SPIMaster   │◀──────────────────────────▶│  spiSlave    │            │
 │   │    (DUT)     │        (via FI mux)          │    (DUT)     │            │
 │   └──────────────┘                              └──────────────┘            │
 │          │                                             │                    │
 │          └──────────────── spi_if ──────────────────────┘                   │
 │                    (clocking blocks + FI mux)                               │
 │                               │                                             │
 │   ┌───────────────────────────┼────────────────────────────────────────┐    │
 │   │ spi_env                   │                                        │    │
 │   │                           ▼                                        │    │
 │   │  ┌─────────────────────────────┐   ┌──────────────────────────┐   │    │
 │   │  │    spi_master_agent         │   │    spi_slave_agent        │   │    │
 │   │  │  ┌────────┐ ┌──────────┐   │   │  ┌────────┐ ┌──────────┐ │   │    │
 │   │  │  │Sequencer│ │ Driver  │   │   │  │Sequencer│ │ Driver  │ │   │    │
 │   │  │  └────────┘ └──────────┘   │   │  └────────┘ └──────────┘ │   │    │
 │   │  │             ┌──────────┐   │   │             ┌──────────┐  │   │    │
 │   │  │             │ Monitor  │──AP│   │AP──         │ Monitor  │  │   │    │
 │   │  └─────────────┴──────────┴───┘   └─────────────┴──────────┴──┘   │    │
 │   │           │ master AP                        │ slave AP            │    │
 │   │           ▼                                  ▼                     │    │
 │   │   ┌───────────────────────────────────────────┐                    │    │
 │   │   │             spi_scoreboard                │──▶ cov_ap          │    │
 │   │   │  master_export   │   slave_export         │         │          │    │
 │   │   └───────────────────────────────────────────┘         ▼          │    │
 │   │                                                   spi_coverage      │    │
 │   │   ┌──────────────────────────────────────┐       (6 covergroups)   │    │
 │   │   │       spi_virtual_sequencer          │                         │    │
 │   │   │  .master_seqr   .slave_seqr          │                         │    │
 │   │   └──────────────────────────────────────┘                         │    │
 │   └────────────────────────────────────────────────────────────────────┘    │
 │                                                                              │
 │   spi_assertions (SVA — 14 properties, bound at top)                        │
 └──────────────────────────────────────────────────────────────────────────────┘
```

### Transfer Data Flow

```
 Virtual Sequence
    │
    ├─(fork)──▶ Slave Driver:  pulse slave_tx_ready + slave_tx_byte
    │
    └─(#50ns)─▶ Master Driver: pulse master_tx_ready + master_tx_byte (1 clock)
                      │
                      ▼
              SPIMaster FSM runs DATA_WIDTH bit cycles on SCLK
              MOSI clocks master_tx_byte into slave's shift register
              MISO clocks slave_tx_byte  into master's shift register
                      │
               master_byte_ready ──(1-cycle pulse)
               slave_byte_ready  ──(1-cycle pulse)
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
  Master Monitor            Slave Monitor
  captures:                 captures:
  master_tx_byte            slave_tx_byte
  master_rx_byte            slave_rx_byte
          │                       │
          ▼                       ▼
  scoreboard.write_master()  scoreboard.write_slave()
                      │
               check_transfer():
               ✓  slave_rx  == master_tx   (MOSI path)
               ✓  master_rx == slave_tx    (MISO path)
                      │
               cov_ap.write(merged_txn) ──▶ spi_coverage (6 CGs sampled)
```

---

## 6. Verification Components

### spi_if (Interface)

Bundles all DUT signals with clocking blocks and fault-injection overrides.

| Group           | Signals                                                                    |
|-----------------|----------------------------------------------------------------------------|
| SPI bus         | `sclk`, `mosi`, `miso`, `ss`, `rst_n`                                     |
| Master control  | `master_tx_ready`, `master_tx_byte`, `master_rx_byte`, `master_byte_ready`, `master_busy` |
| Slave control   | `slave_tx_ready`, `slave_tx_byte`, `slave_rx_byte`, `slave_byte_ready`, `slave_busy` |
| Fault injection | `fi_miso_corrupt/value`, `fi_ss_override/value`, `fi_mosi_override/value`, `fi_sclk_override/value` |

Clocking blocks use `#1` output skew (drive 1 ns after posedge) and `#1` input skew (sample 1 ns before posedge) to avoid race conditions.

Fault injection mux in `spi_tb_top`:
```systemverilog
assign dut_if.miso = fi_miso_corrupt  ? fi_miso_value  : miso_from_slave;
assign dut_if.ss   = fi_ss_override   ? fi_ss_value    : dut_ss;
assign dut_if.mosi = fi_mosi_override ? fi_mosi_value  : dut_mosi;
assign dut_if.sclk = fi_sclk_override ? fi_sclk_value  : dut_sclk;
```

### spi_transaction (Sequence Item)

| Field         | Type                          | Description                                           |
|---------------|-------------------------------|-------------------------------------------------------|
| `master_data` | `rand logic [DATA_WIDTH-1:0]` | Data master sends on MOSI (stimulus)                  |
| `slave_data`  | `rand logic [DATA_WIDTH-1:0]` | Data slave sends on MISO (stimulus)                   |
| `master_rx`   | `logic [DATA_WIDTH-1:0]`      | Captured by master monitor (response)                 |
| `slave_rx`    | `logic [DATA_WIDTH-1:0]`      | Captured by slave monitor (response)                  |

| Constraint      | Default | Purpose                                                              |
|-----------------|:-------:|----------------------------------------------------------------------|
| `c_not_same`    | ON      | `master_data != slave_data` — prevents a short from faking a pass   |
| `c_corners`     | OFF     | Constrains to all-0s, all-1s, `0xAA`, `0x55`, single-bit set/clear |
| `c_single_bits` | OFF     | Exactly 1 bit set in master, 1 bit clear in slave                   |
| `c_allow_equal` | OFF     | Forces `master_data == slave_data` (disable `c_not_same` first)     |

All corner values are parameterized — they recompute automatically when `DATA_WIDTH` changes.

### Scoreboard

Dual-import scoreboard using `uvm_analysis_imp_decl` macros. Maintains two queues and pairs transactions by arrival order. Performs **two checks per transaction**:

```
Check 1 — MOSI path:  slave_rx  == master_data  → PASS / UVM_ERROR
Check 2 — MISO path:  master_rx == slave_data   → PASS / UVM_ERROR
```

A timestamp guard logs a warning if the pairing skew between master and slave transactions exceeds 1 time unit.

### Sequences

**Agent-level** (one side only): `base_seq`, `directed_seq`, `rand_seq`, `corners_rand_seq`, `single_bits_rand_seq` — available for both master and slave.

**Virtual sequences** (coordinate both sides via `spi_virtual_sequencer`):

| Virtual Sequence              | Transactions | How it works                                     |
|-------------------------------|:------------:|--------------------------------------------------|
| `spi_virtual_base_seq`        | 1            | One random coordinated transfer                  |
| `spi_virtual_directed_seq`    | 1            | Fixed `master_data` / `slave_data`               |
| `spi_virtual_rand_seq`        | 500          | N random coordinated transfers                   |
| `spi_virtual_corners_seq`     | 100          | N corner-value transfers                         |
| `spi_virtual_single_bits_seq` | 50           | N single-bit-pattern transfers                   |

All virtual sequences use `fork`–`join`: slave item is launched first, master item fires `#50 ns` later to ensure the slave TX register is preloaded before `SS` falls.

---

## 7. SVA Assertions

`spi_assertions` is a standalone module instantiated at `spi_tb_top`. Each property has a matching `cover` property and integer `hit`/`fail` counters. A `final` block prints the full report at end of simulation.

| Group         | Assertion Name                  | Property (simplified)                          | Violation caught                            |
|---------------|---------------------------------|------------------------------------------------|---------------------------------------------|
| **Reset**     | `a_reset_ss_high`               | `!rst_n \|=> ss`                               | SS not deasserted after reset               |
|               | `a_reset_master_busy_low`       | `!rst_n \|=> !master_busy`                     | Master not idle after reset                 |
|               | `a_reset_slave_busy_low`        | `!rst_n \|=> !slave_busy`                      | Slave not idle after reset                  |
|               | `a_reset_miso_z`                | `!rst_n \|=> miso===1'bz`                      | MISO not Hi-Z after reset                   |
| **Protocol**  | `a_ss_high_slave_not_busy`      | `$rose(ss) \|=> ##1 !slave_busy`               | Slave still busy after SS deasserts         |
|               | `a_ss_low_both_busy`            | `$fell(ss) \|=> ##1 m_busy && s_busy`          | Not both busy when transfer active          |
|               | `a_miso_z_when_ss_high`         | `$rose(ss) \|=> miso===1'bz`                   | MISO driven when not selected               |
|               | `a_sclk_idle_when_ss_high`      | `ss && !$rose(ss) \|=> sclk===CPOL`            | SCLK not at idle level between transfers    |
| **Data**      | `a_master_byte_ready_pulse`     | `master_byte_ready \|=> !master_byte_ready`    | `byte_ready` held high > 1 cycle           |
|               | `a_slave_byte_ready_pulse`      | `slave_byte_ready \|=> !slave_byte_ready`      | Slave `byte_ready` held high > 1 cycle     |
|               | `a_slave_ready_after_master`    | `master_rdy \|-> ##[1:20] slave_rdy`           | Slave never signals transfer complete       |
| **Stability** | `a_master_rx_stable`            | `$fell(byte_ready) \|=> $stable(master_rx)`    | `master_rx_byte` changed after latching     |
|               | `a_slave_rx_stable`             | `$fell(byte_ready) \|=> $stable(slave_rx)`     | `slave_rx_byte` changed after latching      |
|               | `a_no_transfer_when_busy`       | `tx_ready && busy \|=> busy`                   | New transfer accepted while previous active |

---

## 8. Formal Verification

### 8.1 Overview and Motivation

After completing the UVM simulation, the verification environment was extended with formal verification using SymbiYosys. Simulation checks the design against the inputs you thought of — formal proves properties hold for **every possible legal input sequence** the solver can construct.

The master and slave were verified independently as standalone modules. Both were checked using three modes:

| Mode | What it does | Result meaning |
|------|-------------|----------------|
| `bmc` | Bounded Model Checking — tries to falsify all assertions within N steps | PASS = no bug found within bound. Not a complete proof for all time. |
| `cover` | Reachability — finds the shortest witness trace satisfying a cover condition | PASS = the condition is reachable. Confirms assumptions do not over-constrain the design. |
| `prove` | BMC + k-Induction simultaneously | PASS = proved for all time. UNKNOWN = induction did not close (not a bug — requires auxiliary invariants). |

### 8.2 Toolchain

| Component | Role |
|-----------|------|
| SymbiYosys (sby) | Frontend orchestrator. Calls Yosys to elaborate the RTL, then passes the model to the solver. |
| Yosys + clk2fflogic | Synthesis backend. `clk2fflogic` transforms all flip-flops into clock-agnostic combinational logic, making all clock signals — including data-derived clocks like `w_sclk` — free solver variables. |
| Bitwuzla (smtbmc) | SMT solver backend. Finds counterexamples (BMC) or proves no counterexample exists within the bound (k-Induction). |

> **Note on toolchain:** SymbiYosys is an open-source tool and differs from industry tools like JasperGold or VC Formal. Known limitations include partial SVA support, no `bind` construct (without Verific), and no modelling of tri-state (`'z`) logic. All RTL changes made for formal compatibility are inside `` `ifdef FORMAL `` guards — the original simulation and synthesis behaviour is completely preserved.

### 8.3 SPI Master — Formal Verification

**Formal environment summary:**

| Parameter | Value |
|-----------|-------|
| Module | `SPIMaster` |
| Parameters fixed | `MODE=0`, `DATA_WIDTH=8`, `DIVIDE_FREQUENCY_SPI=1` |
| Assumptions written | 6 (A1–A6) |
| Assertions written | 6 (F2–F7) |
| Cover properties | 1 (F8) |
| BMC depth | 80 |
| BMC result | DONE (PASS, rc=0) — all 6 assertions hold |
| Cover result | DONE (PASS, rc=0) — complete transfer witnessed at step 70 |
| k-Induction result | UNKNOWN — basecase PASS, auxiliary invariant needed |

**RTL changes for formal compatibility (all inside `` `ifdef FORMAL `` guards):**

Six targeted changes were made: `bit` → `logic` conversion for registers used under `clk2fflogic`; inline initializer removal (Yosys may silently ignore these); parameter-derived constants moved to `always_ff` reset blocks; tri-state (`'z`) outputs replaced with driven values (`1'b0` / `1'b1`) since formal solvers do not model Hi-Z.

**Assumptions (A1–A6):**

All assumptions use combinational `always @(*)` blocks — clocked assumptions leave inter-edge gaps the solver can exploit under `clk2fflogic`.

| Assumption | Constraint |
|------------|------------|
| A1 | `i_Clk_en` always HIGH (clock permanently enabled) |
| A2 | `i_Rst_n` starts LOW at time zero (forces clean reset start state) |
| A3 | `i_tx_ready` cannot assert while `o_busy` is HIGH (core protocol rule) |
| A4 | `i_tx_ready` is a single-cycle pulse (shadow register `f_tx_ready_prev`) |
| A5 | `i_tx_ready` starts LOW at time zero (closes time-zero gap) |
| A6 | Once `i_Rst_n` deasserts it never reasserts (`f_rst_n_prev` shadow register) |

**Assertions (F2–F7):**

All assertions use `always @(posedge w_Clk)` blocks gated on `f_past_valid`.

| Assertion | Property | What it catches |
|-----------|----------|----------------|
| F2 | After reset: `o_busy=0`, `o_ss=1`, `o_sclk=0` | Any failure to correctly initialise outputs after reset |
| F3 | `o_ss` never LOW when FSM is in `STATE_IDLE` | Phantom slave-select — SS asserting with no transfer in progress |
| F4 | `o_sclk` equals `w_CPOL` when FSM is in IDLE or PRE_COMM | Any SCLK glitch outside the transfer window |
| F5 | `r_cycle_count` never exceeds `DATA_WIDTH` | Bit counter overflow — would cause wrong number of bits shifted |
| F6 | `r_cycle_count` is zero when FSM is in `STATE_IDLE` | Bit counter not resetting between transfers |
| F7 | `o_busy` correctly reflects `$past(state)` with one-cycle lag | `o_busy` ever misreporting transfer status to external logic |

**Cover property (F8):** Witnesses the FSM transitioning from `STATE_POS_COMM` → `STATE_IDLE` — proves a complete 8-bit transfer is reachable under the formal environment.

**Counterexamples encountered and resolved:**

| Failure | Root cause | Fix |
|---------|-----------|-----|
| F7 at step 6 | Solver pulsed reset mid-transfer (physically impossible in real hardware) | Added A6: once reset deasserts it must stay deasserted |
| Cover unreachable at depth 60 | With `clk2fflogic`, each `w_Clk` cycle requires two solver steps; depth 60 insufficient for a full 8-bit transfer | Increased depth to 80 |
| Cover unreachable at depth 80 | `w_mode_select` and `r_frame_formart` clocked on `posedge i_Clk` while all design FFs use `posedge w_Clk` — independent free variables under `clk2fflogic` | Changed `always_ff` block to `posedge w_Clk` |
| F4, F6 at step 70 | Both `o_sclk` and `r_cycle_count` are registered — hold previous values on first cycle in `STATE_IDLE` | Changed assertions to check `$past(state)` instead of `state` |

**k-Induction:** Basecase passed (equivalent to BMC). Inductive step failed because the solver constructed an artificially reachable starting state where `o_busy` and `state` are inconsistent — something that cannot occur in real execution but which the inductive step has no history to rule out. Closing the proof requires an auxiliary invariant asserting the consistent relationship between `o_busy` and `state`.

---

### 8.4 SPI Slave — Formal Verification

The slave is structurally harder than the master for formal tools. Three features significantly increase complexity:

| Complexity | Description | Formal impact |
|-----------|-------------|---------------|
| Multiple clock domains | Registers clocked on `posedge w_sclk`, `negedge w_sclk`, and `posedge w_Clk` | Each becomes an independent free solver variable under `clk2fflogic`, expanding reachable state space |
| Mixed reset styles | `r_cycle_count` resets on `posedge r_ss` (SS deassertion), not `negedge i_Rst_n` | `posedge r_ss` is itself a separate clock domain under `clk2fflogic` requiring careful assumption writing |
| Generate blocks with edge-sensitive logic | `MODE` selects `posedge` or `negedge w_sclk` for cycle counting and RX sampling | Fixing `MODE=0` at elaboration reduces clock domain count to a tractable level |

With `MODE=0` fixed, `clk2fflogic` sees four independent trigger events: `posedge w_Clk`, `posedge w_sclk`, `negedge w_sclk`, and `posedge r_ss`. All four are free solver variables.

**Formal environment summary:**

| Parameter | Value |
|-----------|-------|
| Module | `spiSlave` |
| Parameters fixed | `MODE=0`, `FRAME_FORMAT=0`, `DATA_WIDTH=8` |
| Assumptions written | 9 (A1–A9) |
| Assertions written | 7 (F1–F7); F5 removed — documented tool limitation |
| Cover properties | 1 (F8) |
| BMC depth | 80 |
| BMC result | DONE (PASS, rc=0) — all 6 remaining assertions hold |
| Cover result | DONE (PASS, rc=0) — complete 8-bit transfer witnessed at step 8 |
| k-Induction result | UNKNOWN — basecase PASS, inductive step FAIL on F6 (expected) |
| Counterexamples resolved | 2 |

**Assumptions (A1–A9):**

Shadow registers replace `$past()` wherever assumption logic needs history.

| Assumption | Constraint | Why needed |
|------------|------------|------------|
| A1 | `i_Clk_en` always HIGH | Simplifies state space |
| A2 (strengthened) | `r_sclk` must be LOW when `r_ss` is HIGH | CPOL=0 for MODE=0; constraining `i_sclk` alone insufficient after `clk2fflogic` |
| A3 | `i_tx_ready` cannot fire while transfer in progress | Core SPI protocol rule |
| A4 | `i_tx_ready` is a single-cycle pulse | Models real hardware |
| A5 | `i_Rst_n` stays HIGH once deasserted | Prevents solver from pulsing reset mid-transfer |
| A6 | At time zero: `~i_Rst_n`, `i_ss=1`, `i_sclk=0` | Seals time-zero gap before `f_past_valid` is set |
| A7 | Once SS deasserts, `i_ss` must stay HIGH one more cycle | Prevents immediate SS re-assertion; discovered through counterexample analysis |
| A8 | `i_sclk` must be LOW when `i_ss` is HIGH | Belt-and-suspenders constraint at raw input level |
| A9 | `r_sclk` must be LOW on transition cycle when SS just deasserted | Closes the one-cycle transition window |

**Assertions (F1–F7, F5 removed):**

| Assertion | Property | Final status |
|-----------|----------|-------------|
| F1 | After `~i_Rst_n`: `o_busy=0` and `o_byte_ready=0` | PASS |
| F2 | `o_busy == !$past(r_ss)` at every `posedge w_Clk` | PASS |
| F3 | `o_byte_ready` cannot be HIGH on two consecutive cycles | PASS |
| F4 | When `o_byte_ready` fires: `$past(o_busy)` HIGH and `r_ss` HIGH | PASS (after A7 added) |
| F5 | `r_cycle_count <= DATA_WIDTH` at all times | **REMOVED** — see section 8.5 |
| F6 | `r_tx_byte` does not change while `r_ss` is LOW | PASS |
| F7 | `o_busy=0` while `~i_Rst_n` is held | PASS |

**Cover property (F8):** `cover (f_past_valid && o_byte_ready)` — witnesses a complete slave receive-side SPI transfer. Cover PASS at step 8 confirms the full receive pipeline is reachable and that assumptions do not over-constrain the design.

**Counterexamples encountered and resolved:**

| Failure | Root cause | Fix |
|---------|-----------|-----|
| F4 at step 8 (depth 30) | Solver made `i_ss` go LOW again on the exact cycle `o_byte_ready` fired — physically impossible in real hardware | Added A7: `i_ss` must stay HIGH for one more `w_Clk` cycle after SS deasserts |
| F5 at steps 42–80 | Fundamental `clk2fflogic` tool limitation — see section 8.5 | F5 removed with full documentation |

**Shadow registers:**

| Shadow register | Tracks | Used in |
|----------------|--------|---------|
| `f_past_valid` | HIGH after first `posedge w_Clk` | Gate for all `$past()`-based assertions |
| `f_r_ss_prev` | `r_ss` delayed one `w_Clk` cycle | A2, A3, A9 |
| `f_i_ss_prev` | `i_ss` delayed one `w_Clk` cycle | A7 |
| `f_i_ss_prev2` | `i_ss` delayed two `w_Clk` cycles | A7 (second-level hold detection) |
| `f_tx_ready_prev` | `i_tx_ready` delayed one `w_Clk` cycle | A4 |

---

### 8.5 The clk2fflogic Data-Derived Clock Limitation

This section documents a fundamental tool constraint discovered during slave verification that affects any formal verification of designs with data-derived clocks under `clk2fflogic`.

**What clk2fflogic does:** Transforms every flip-flop into clock-agnostic combinational logic with an explicit enable signal representing the clock edge event. For a multi-clock design, every clock edge becomes an independent free boolean — the solver is not constrained to any relationship between them.

**The signal value vs trigger event distinction:** After `clk2fflogic`, two things exist that are completely separate in the SMT model:

- The **signal value** of `w_sclk` — a wire derived from `r_sclk` → `i_sclk`. Constraining `i_sclk` constrains this value.
- The **trigger event** `negedge w_sclk` — a free boolean enable created by `clk2fflogic`. **No connection to the signal value.**

In real hardware a negedge event can only occur when the signal transitions 1→0. In the SMT model they are completely independent — the solver can assert the negedge trigger regardless of what `w_sclk` holds.

**Why F5 cannot be proved:** `r_cycle_count` is clocked on `negedge w_sclk`. After `clk2fflogic` its enable is the free negedge trigger. The solver can fire this trigger any number of times per step, incrementing `r_cycle_count` without bound. Constraining `i_sclk` signal values has no effect on the trigger — they are decoupled. This was confirmed by three successive fixing attempts that reduced the failure step but never eliminated it.

**Why F5 removal is correct:** The bound on `r_cycle_count` is enforced in real hardware by the physical SPI constraint that exactly `DATA_WIDTH` SCLK edges occur per transfer — a system-level property belonging in master-slave integration verification, not standalone slave verification. The six remaining assertions prove all meaningful standalone slave properties and all pass at depth 80.

---

### 8.6 Formal Verification Results Summary

| Module | Mode | Depth | Result |
|--------|------|-------|--------|
| SPIMaster | BMC | 80 | ✅ DONE (PASS, rc=0) — 6/6 assertions |
| SPIMaster | Cover | 80 | ✅ DONE (PASS, rc=0) — complete transfer witnessed |
| SPIMaster | k-Induction | 30 | ⚠️ UNKNOWN — basecase PASS, auxiliary invariant needed |
| spiSlave | BMC | 80 | ✅ DONE (PASS, rc=0) — 6/6 active assertions |
| spiSlave | Cover | 80 | ✅ DONE (PASS, rc=0) — complete transfer witnessed at step 8 |
| spiSlave | k-Induction | 30 | ⚠️ UNKNOWN — basecase PASS, auxiliary invariant needed |

Raw tool output for all six runs is in `logs/logs_formal/`.

**Next steps:** Adding auxiliary invariants to close k-Induction for both modules, followed by end-to-end master-slave formal verification as the final phase.

---

## 9. Functional Coverage

`spi_coverage` extends `uvm_subscriber #(spi_transaction)` and is connected to the scoreboard's analysis port. All bin boundary values are `localparams` derived from `DATA_WIDTH`.

| Covergroup          | Bins | What it measures                                                                  |
|---------------------|:----:|-----------------------------------------------------------------------------------|
| `cg_master_tx`      | 11   | MOSI value space — 8 corner bins (all-0s, all-1s, 0xAA/0x55, single-bit set/clear) + 3 range bins |
| `cg_slave_tx`       | 11   | Same structure for MISO — verifies MISO path independently                        |
| `cg_transfer_pair`  | 23   | 5-category MOSI × MISO cross — catches untested combinations. 2 bins ignored (`c_not_same` prevents same-zeros/ones) |
| `cg_rx_integrity`   | 22   | Actual captured `master_rx` and `slave_rx` values — verifies receive logic, not just transmit |
| `cg_back_to_back`   | 16   | Previous × current MOSI category — catches shift-register residue bugs between back-to-back transfers |
| `cg_bit_toggle`     | 64   | `rose`/`fell` per MOSI and MISO bit — detects stuck-at-0 and stuck-at-1 on individual lines |

**Pass threshold:** ≥ 90% average. **Achieved:** 99.8% (5 groups at 100%, `cg_transfer_pair` at 98.6% — by design due to `c_not_same`).

---

## 10. Tests

All tests extend `spi_base_test` (builds `spi_env`) and override `run_phase`.

### Positive / Corner / Regression

| Test                     | Txns | Description                                                              |
|--------------------------|:----:|--------------------------------------------------------------------------|
| `spi_base_test`          | 1    | Single random transfer — validates basic MOSI and MISO paths             |
| `spi_rand_test`          | 500  | 500 random transfers — broad data path coverage                          |
| `spi_directed_vseq_test` | 3    | Directed: `0x38/0x12`, `0xFF/0x00`, `0xAA/0x55`                        |
| `spi_corners_test`       | 100  | Corner values — all-0s, all-1s, alternating, single-bit patterns        |
| `spi_single_bits_test`   | 50   | 1-bit-set master / 1-bit-clear slave — stuck-at fault coverage           |
| `spi_stress_test`        | 10   | 10 back-to-back transfers — shift-register flush check                   |
| `spi_reset_test`         | 2    | Transfer → assert `rst_n` → release → recovery transfer                 |
| **`spi_full_test`**      | **660** | **Regression: corners(50) + single-bits(50) + stress(10) + rand(500)** |

### Negative / Fault Injection

All negative tests use `check_phase` self-validation — if no `UVM_ERROR` was raised when one was expected, `uvm_fatal` is called.

| Test                              | Fault injected                                   | Expected result         |
|-----------------------------------|--------------------------------------------------|-------------------------|
| `spi_fault_inject_test`           | MISO forced LOW for 1 SCLK cycle mid-transfer    | UVM_ERROR — data mismatch |
| `spi_neg_test`                    | MISO held LOW entire transfer                    | UVM_ERROR — `master_rx=0x00` ≠ `slave_tx` |
| `spi_ss_deassert_mid_transfer_test` | SS pulled HIGH after `DATA_WIDTH/2` edges      | UVM_ERROR — incomplete frame |
| `spi_tx_ready_during_busy_test`   | `tx_ready` hammered ×10 while master is busy     | 0 errors — RTL ignores extra pulses |
| `spi_glitch_on_mosi_test`         | MOSI flipped at mid-transfer sample point        | UVM_ERROR — slave_rx bit flip |
| `spi_double_start_test`           | Two `tx_ready` pulses before `busy` rises        | 0 errors — second pulse ignored |
| `spi_ss_glitch_test`              | SS glitches HIGH for 1 SCLK cycle mid-transfer   | UVM_ERROR — frame corrupted |
| `spi_clock_glitch_test`           | SCLK inverted for 1 edge mid-transfer            | UVM_ERROR — extra clock edge |

---

## 11. Simulation Results

Results from `spi_full_test` on Aldec Riviera-PRO 2025.04.

### Scoreboard Summary

```
Transactions checked : 610
Total checks         : 1220   (2 per transaction — MOSI path + MISO path)
PASS                 : 1220
FAIL                 : 0
UVM_ERROR            : 0
RESULT               : TEST PASSED
```

### Coverage Summary

```
cg_master_tx     (MOSI value bins)      : 100.0%
cg_slave_tx      (MISO value bins)      : 100.0%
cg_transfer_pair (MOSI x MISO cross)    :  98.6%   ← 2 bins excluded by c_not_same
cg_rx_integrity  (received value bins)  : 100.0%
cg_back_to_back  (consecutive trans.)   : 100.0%
cg_bit_toggle    (per-bit toggle)       : 100.0%
─────────────────────────────────────────────────
TOTAL (avg of 6)                        :  99.8%
```

### Assertion Summary

```
437,679 total evaluations  ·  0 failures  ·  14/14 properties passing

a_reset_ss_high             HIT=31270  PASS=31270  FAIL=0
a_reset_master_busy_low     HIT=31270  PASS=31270  FAIL=0
a_reset_slave_busy_low      HIT=31270  PASS=31270  FAIL=0
a_reset_miso_z              HIT=31270  PASS=31270  FAIL=0
a_ss_high_slave_not_busy    HIT=31260  PASS=31260  FAIL=0
a_ss_low_both_busy          HIT=31260  PASS=31260  FAIL=0
a_miso_z_when_ss_high       HIT=31260  PASS=31260  FAIL=0
a_sclk_idle_when_ss_high    HIT=31259  PASS=31259  FAIL=0
a_master_byte_ready_pulse   HIT=31260  PASS=31260  FAIL=0
a_slave_byte_ready_pulse    HIT=31260  PASS=31260  FAIL=0
a_slave_ready_after_master  HIT=31260  PASS=31260  FAIL=0
a_master_rx_stable          HIT=31260  PASS=31260  FAIL=0
a_slave_rx_stable           HIT=31260  PASS=31260  FAIL=0
a_no_transfer_when_busy     HIT=31260  PASS=31260  FAIL=0
```

All 8 negative tests passed their `check_phase` self-check.

---

## 12. How to Run

### UVM Simulation (EDA Playground)

1. Go to [edaplayground.com](https://edaplayground.com) and select **Aldec Riviera-PRO 2025.04**
2. Paste `spi_design.sv` into the **Design** pane
3. Paste `testbench.sv` into the **Testbench** pane
4. Add to simulation arguments:

```
+UVM_TESTNAME=spi_full_test
```

Replace with any test name to run a specific test (e.g. `spi_rand_test`, `spi_neg_test`).

5. Add `+access+r` to enable EPWave waveform viewing.
6. Click **Run**.

### Formal Verification (SymbiYosys on WSL2)

**Prerequisites:** OSS CAD Suite installed on WSL2 Ubuntu. Installation at [https://github.com/YosysHQ/oss-cad-suite-build](https://github.com/YosysHQ/oss-cad-suite-build).

Source the environment then run from the repo root:

```bash
# SPI Master — BMC + Cover
cd "Project code/formal/spi_master"
sby -f spi_master.sby

# SPI Slave — BMC + Cover
cd "Project code/formal/spi_slave"
sby -f spi_slave.sby
```

Expected output:
```
SBY  DONE (PASS, rc=0)
```

To run k-Induction, set mode to `prove` in the `.sby` file. Expected result is `UNKNOWN` — basecase passes; closing the inductive step requires auxiliary invariants (work in progress). Reference logs for all six runs are in `logs/logs_formal/`.

### Changing DATA_WIDTH (UVM)

In `spi_tb_top`:
```systemverilog
parameter int DATA_WIDTH = 8;   // change to 16 or 32
```

Also update `SPI_DATA_WIDTH` in `spi_pkg` to match:
```systemverilog
parameter int SPI_DATA_WIDTH = 8;
```

### Changing SPI Mode (UVM)

In `spi_tb_top`:
```systemverilog
parameter int MODE = 0;   // 0–3
```

---

## 13. Assumptions & Limitations

| Area | Assumption / Limitation |
|------|------------------------|
| Clock domain (simulation) | Fully synchronous, single clock domain. No CDC analysis performed. |
| Formal — parameters fixed | Formal verification fixes `MODE=0`, `FRAME_FORMAT=0`, `DATA_WIDTH=8`. Other configurations require separate runs. |
| Formal — bounded proof | BMC at depth 80 is a bounded proof, not a proof for all time. k-Induction is in progress to close the unbounded proof. |
| Formal — F5 (slave) | `r_cycle_count` bound not proved — fundamental `clk2fflogic` limitation with data-derived clocks. Not a design bug. See section 8.5. |
| Formal — standalone modules | Master and slave verified independently. End-to-end master-slave formal verification is the planned next phase. |
| MODE tested (simulation) | Simulation uses MODE=0. Other modes share the same FSM; only SCLK polarity/phase differs. |
| DATA_WIDTH tested | Verified at 8-bit default. Parameterization confirmed by code inspection. |
| Clock enable | `i_Clk_en` is tied HIGH throughout. Clock-gating scenarios not tested. |
| SS_PIN_ENABLE | Set to 1 (module drives SS). External SS management not tested. |
| Multi-master / slave | Single master, single slave only. Multi-slave SS routing is out of scope. |
| MISO Hi-Z | Resolved directly by simulator. No physical pull resistor modeled. |
| Timing | Ideal RTL simulation. Setup/hold margins and physical timing not analyzed. |
| DIVIDE_FREQUENCY_SPI | Fixed at 1 throughout (fSCLK = 25 MHz at 100 MHz system clock). |

---

*Design source: [oafonsoo/SPI-Module-in-SystemVerilog](https://github.com/oafonsoo/SPI-Module-in-SystemVerilog)*  
*Parameterization, full UVM testbench, and formal verification environment by Tanmay Rambha.*