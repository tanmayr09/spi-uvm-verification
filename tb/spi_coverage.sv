// =============================================================================
// File        : spi_coverage.sv
// Project     : SPI UVM Testbench
// Description : Functional coverage model for SPI Master + Slave verification.
//
// COVERAGE PHILOSOPHY:
//   Every covergroup here is motivated by a specific class of bug that could
//   exist in the RTL. Coverage is not just bins for the sake of bins — each
//   bin represents a stimulus condition that has a real reason to be tested.
//
//   Six covergroups:
//
//   1. cg_master_tx    — what master sends. Fine-grained bins targeting
//                        shift-register bit-position bugs. Single-bit values
//                        (0x01, 0x02 ... 0x80) catch stuck-at faults on
//                        individual bit lines of the MOSI shift register.
//
//   2. cg_slave_tx     — same as above for slave MISO shift register.
//
//   3. cg_transfer_pair — CROSS coverage of master_data × slave_data bucketed
//                         into 5 categories each → 25 combinations (23 valid).
//                         Catches bugs that only appear when specific value
//                         classes are in-flight simultaneously on MOSI+MISO.
//
//   4. cg_rx_integrity — what was actually RECEIVED by each side. Separate
//                        from what was sent — proves the shift registers
//                        correctly captured the incoming bit stream.
//
//   5. cg_back_to_back — tracks prev_master_data → curr_master_data transitions.
//                        Catches bugs where the shift register does not reset
//                        cleanly between back-to-back transfers.
//
//   6. cg_bit_toggle   — for each bit position 0-7 on MOSI and MISO, was
//                        there a 0→1 and a 1→0 transition across consecutive
//                        transfers? Catches stuck-at faults per bit line.
//
// RECEIVED VIA scoreboard.cov_ap (merged transaction):
//   All four fields (master_data, master_rx, slave_data, slave_rx) are
//   populated on every write() call by the scoreboard merge logic.
//
// TRANSACTIONS NEEDED TO CLOSE (pure random, c_not_same only):
//   cg_master_tx      ~ 200
//   cg_slave_tx       ~ 200
//   cg_transfer_pair  ~ 400-600  (23 cross bins)
//   cg_rx_integrity   ~ 200
//   cg_back_to_back   ~ 300-500  (16 cross bins)
//   cg_bit_toggle     ~ 150      (32 toggle bins)
//   Recommended: spi_rand_test with num_transactions = 500
// =============================================================================

class spi_coverage extends uvm_subscriber #(spi_transaction);
  `uvm_component_utils(spi_coverage)

  spi_transaction tr;

  // Previous transfer values for back-to-back and toggle covergroups
  logic [7:0] prev_master_data;
  logic [7:0] prev_slave_data;
  bit         first_transaction;

  // ===========================================================================
  // COVERGROUP 1 — cg_master_tx
  // What values did the master send over MOSI?
  //
  // Single-bit-set bins: if bit N of MOSI is stuck-at-0, the only way to
  // detect it is to send a value where bit N is the only set bit. Any
  // corruption (receiving 0x00 instead of 0x08 for example) will cause a
  // scoreboard FAIL — but only if that exact stimulus was generated.
  // Without this bin, the stimulus might never isolate bit N.
  // ===========================================================================
  covergroup cg_master_tx;
    cp_master_tx: coverpoint tr.master_data {
      bins all_zeros  = {8'h00};            // 0000_0000 — stuck-at-1 stress
      bins all_ones   = {8'hFF};            // 1111_1111 — stuck-at-0 stress
      bins alt_AA     = {8'hAA};            // 1010_1010 — alternating
      bins alt_55     = {8'h55};            // 0101_0101 — alternating inverse
      bins bit0_only  = {8'h01};            // only LSB set
      bins bit1_only  = {8'h02};
      bins bit2_only  = {8'h04};
      bins bit3_only  = {8'h08};
      bins bit4_only  = {8'h10};
      bins bit5_only  = {8'h20};
      bins bit6_only  = {8'h40};
      bins bit7_only  = {8'h80};            // only MSB set (first bit shifted)
      bins bit0_clear = {8'hFE};            // only LSB clear
      bins bit7_clear = {8'h7F};            // only MSB clear
      bins low_range  = {[8'h03:8'h54]};   // general low values
      bins mid_range  = {[8'h56:8'hA9]};   // general mid values
      bins high_range = {[8'hAB:8'hFD]};   // general high values
    }
  endgroup


  // ===========================================================================
  // COVERGROUP 2 — cg_slave_tx
  // What values did the slave send over MISO?
  // Same rationale as cg_master_tx — the MISO shift register has the same
  // potential stuck-at faults as the MOSI shift register.
  // ===========================================================================
  covergroup cg_slave_tx;
    cp_slave_tx: coverpoint tr.slave_data {
      bins all_zeros  = {8'h00};
      bins all_ones   = {8'hFF};
      bins alt_AA     = {8'hAA};
      bins alt_55     = {8'h55};
      bins bit0_only  = {8'h01};
      bins bit1_only  = {8'h02};
      bins bit2_only  = {8'h04};
      bins bit3_only  = {8'h08};
      bins bit4_only  = {8'h10};
      bins bit5_only  = {8'h20};
      bins bit6_only  = {8'h40};
      bins bit7_only  = {8'h80};
      bins bit0_clear = {8'hFE};
      bins bit7_clear = {8'h7F};
      bins low_range  = {[8'h03:8'h54]};
      bins mid_range  = {[8'h56:8'hA9]};
      bins high_range = {[8'hAB:8'hFD]};
    }
  endgroup


  // ===========================================================================
  // COVERGROUP 3 — cg_transfer_pair
  // Cross coverage: master_data category × slave_data category.
  //
  // MOSI and MISO are active simultaneously on every SCLK edge during a
  // transfer. A timing or coupling bug could cause the value on one line
  // to corrupt the other — but only for specific value combinations.
  // Without cross coverage you would never know if "master=0x00 while
  // slave=0xFF" was ever tested specifically.
  //
  // Bucketed into 5 categories × 5 = 25 bins.
  // ignore_bins removes same_zeros and same_ones (impossible with c_not_same).
  // 23 valid bins to close.
  // ===========================================================================
  covergroup cg_transfer_pair;

    cp_mosi_cat: coverpoint tr.master_data {
      bins zeros       = {8'h00};
      bins ones        = {8'hFF};
      bins alternating = {8'hAA, 8'h55};
      bins low         = {[8'h01:8'h7F]};
      bins high        = {[8'h80:8'hFE]};
    }

    cp_miso_cat: coverpoint tr.slave_data {
      bins zeros       = {8'h00};
      bins ones        = {8'hFF};
      bins alternating = {8'hAA, 8'h55};
      bins low         = {[8'h01:8'h7F]};
      bins high        = {[8'h80:8'hFE]};
    }

    cx_mosi_miso: cross cp_mosi_cat, cp_miso_cat {
      // c_not_same prevents master==slave for corner values
      ignore_bins same_zeros = binsof(cp_mosi_cat.zeros) && binsof(cp_miso_cat.zeros);
      ignore_bins same_ones  = binsof(cp_mosi_cat.ones)  && binsof(cp_miso_cat.ones);
    }

  endgroup


  // ===========================================================================
  // COVERGROUP 4 — cg_rx_integrity
  // What was actually RECEIVED by each side?
  //
  // cg_master_tx and cg_slave_tx measure what was DRIVEN onto the bus.
  // This covergroup measures what the shift registers CAPTURED.
  //
  // Example bug this catches:
  //   Slave shift register has an off-by-one bug — it captures bits [6:0]
  //   and always reads bit 7 as 0. The tx covergroup shows 0x80 was sent.
  //   The rx covergroup shows 0x80 was NEVER received — revealing the bug.
  //   (The scoreboard FAIL also catches this, but coverage gives you the
  //   distribution picture across all transactions, not just one failure.)
  // ===========================================================================
  covergroup cg_rx_integrity;

    cp_master_rx: coverpoint tr.master_rx {
      bins all_zeros  = {8'h00};
      bins all_ones   = {8'hFF};
      bins alt_AA     = {8'hAA};
      bins alt_55     = {8'h55};
      bins bit0_only  = {8'h01};
      bins bit7_only  = {8'h80};
      bins bit0_clear = {8'hFE};
      bins bit7_clear = {8'h7F};
      bins low_range  = {[8'h02:8'h54]};
      bins mid_range  = {[8'h56:8'hA9]};
      bins high_range = {[8'hAB:8'hFD]};
    }

    cp_slave_rx: coverpoint tr.slave_rx {
      bins all_zeros  = {8'h00};
      bins all_ones   = {8'hFF};
      bins alt_AA     = {8'hAA};
      bins alt_55     = {8'h55};
      bins bit0_only  = {8'h01};
      bins bit7_only  = {8'h80};
      bins bit0_clear = {8'hFE};
      bins bit7_clear = {8'h7F};
      bins low_range  = {[8'h02:8'h54]};
      bins mid_range  = {[8'h56:8'hA9]};
      bins high_range = {[8'hAB:8'hFD]};
    }

  endgroup


  // ===========================================================================
  // COVERGROUP 5 — cg_back_to_back
  // Consecutive transfer transitions: prev_master_data → curr_master_data.
  //
  // A SPI shift register must be completely flushed between transfers.
  // The dangerous transition is high → low (or low → high):
  //   Transfer N:   master sends 0xFF  (shift register fills with 1s)
  //   Transfer N+1: master sends 0x00  (register must clear to all 0s)
  // If a reset bug leaves residual bits, slave receives 0xFF instead of 0x00.
  // Without this covergroup you'd never know if that exact transition occurred.
  //
  // 4 × 4 = 16 transition bins.
  // ===========================================================================
  covergroup cg_back_to_back;

    cp_prev_master: coverpoint prev_master_data {
      bins was_zeros = {8'h00};
      bins was_ones  = {8'hFF};
      bins was_low   = {[8'h01:8'h7F]};
      bins was_high  = {[8'h80:8'hFE]};
    }

    cp_curr_master: coverpoint tr.master_data {
      bins now_zeros = {8'h00};
      bins now_ones  = {8'hFF};
      bins now_low   = {[8'h01:8'h7F]};
      bins now_high  = {[8'h80:8'hFE]};
    }

    cx_transitions: cross cp_prev_master, cp_curr_master;

  endgroup


  // ===========================================================================
  // COVERGROUP 6 — cg_bit_toggle
  // Per-bit toggle coverage across consecutive transfers.
  //
  // A stuck-at fault on bit N means bit N never changes value.
  // Toggle coverage proves every bit went 0→1 AND 1→0 at least once.
  //
  // For each bit N:
  //   rose: prev[N]=0, curr[N]=1  (0→1 transition)
  //   fell: prev[N]=1, curr[N]=0  (1→0 transition)
  //
  // 8 bits × 2 transitions × 2 signals (MOSI + MISO) = 32 toggle bins.
  // These close quickly with random stimulus (~150 transactions).
  // ===========================================================================
  covergroup cg_bit_toggle;

    // MOSI bit toggles
    cp_mosi_b0: coverpoint {prev_master_data[0], tr.master_data[0]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b1: coverpoint {prev_master_data[1], tr.master_data[1]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b2: coverpoint {prev_master_data[2], tr.master_data[2]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b3: coverpoint {prev_master_data[3], tr.master_data[3]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b4: coverpoint {prev_master_data[4], tr.master_data[4]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b5: coverpoint {prev_master_data[5], tr.master_data[5]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b6: coverpoint {prev_master_data[6], tr.master_data[6]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_mosi_b7: coverpoint {prev_master_data[7], tr.master_data[7]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }

    // MISO bit toggles
    cp_miso_b0: coverpoint {prev_slave_data[0], tr.slave_data[0]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b1: coverpoint {prev_slave_data[1], tr.slave_data[1]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b2: coverpoint {prev_slave_data[2], tr.slave_data[2]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b3: coverpoint {prev_slave_data[3], tr.slave_data[3]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b4: coverpoint {prev_slave_data[4], tr.slave_data[4]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b5: coverpoint {prev_slave_data[5], tr.slave_data[5]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b6: coverpoint {prev_slave_data[6], tr.slave_data[6]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }
    cp_miso_b7: coverpoint {prev_slave_data[7], tr.slave_data[7]} {
      bins rose = {2'b01}; bins fell = {2'b10}; }

  endgroup


  // ===========================================================================
  // Constructor
  // ===========================================================================
  function new(string name = "spi_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_master_tx     = new();
    cg_slave_tx      = new();
    cg_transfer_pair = new();
    cg_rx_integrity  = new();
    cg_back_to_back  = new();
    cg_bit_toggle    = new();
    first_transaction = 1;
    prev_master_data  = 8'h00;
    prev_slave_data   = 8'h00;
  endfunction


  // ===========================================================================
  // write() — called for every merged transaction from scoreboard.cov_ap
  // ===========================================================================
  function void write(spi_transaction t);
    tr = t;

    cg_master_tx.sample();
    cg_slave_tx.sample();
    cg_transfer_pair.sample();
    cg_rx_integrity.sample();

    // Back-to-back and toggle only make sense from transaction 2 onwards
    if (!first_transaction) begin
      cg_back_to_back.sample();
      cg_bit_toggle.sample();
    end

    prev_master_data  = t.master_data;
    prev_slave_data   = t.slave_data;
    first_transaction = 0;
  endfunction


  // ===========================================================================
  // report_phase
  // ===========================================================================
  function void report_phase(uvm_phase phase);
    real cg1, cg2, cg3, cg4, cg5, cg6, total;

    cg1   = cg_master_tx.get_coverage();
    cg2   = cg_slave_tx.get_coverage();
    cg3   = cg_transfer_pair.get_coverage();
    cg4   = cg_rx_integrity.get_coverage();
    cg5   = cg_back_to_back.get_coverage();
    cg6   = cg_bit_toggle.get_coverage();
    total = (cg1 + cg2 + cg3 + cg4 + cg5 + cg6) / 6.0;

    `uvm_info("COV", "============================================================", UVM_NONE)
    `uvm_info("COV", "  COVERAGE SUMMARY",                                           UVM_NONE)
    `uvm_info("COV", "============================================================", UVM_NONE)
    `uvm_info("COV", $sformatf("  cg_master_tx     (MOSI value bins)     : %0.1f%%", cg1), UVM_NONE)
    `uvm_info("COV", $sformatf("  cg_slave_tx      (MISO value bins)     : %0.1f%%", cg2), UVM_NONE)
    `uvm_info("COV", $sformatf("  cg_transfer_pair (MOSI x MISO cross)   : %0.1f%%", cg3), UVM_NONE)
    `uvm_info("COV", $sformatf("  cg_rx_integrity  (received value bins) : %0.1f%%", cg4), UVM_NONE)
    `uvm_info("COV", $sformatf("  cg_back_to_back  (consec transitions)  : %0.1f%%", cg5), UVM_NONE)
    `uvm_info("COV", $sformatf("  cg_bit_toggle    (per-bit toggle)      : %0.1f%%", cg6), UVM_NONE)
    `uvm_info("COV", "------------------------------------------------------------", UVM_NONE)
    `uvm_info("COV", $sformatf("  TOTAL (avg of 6 covergroups)           : %0.1f%%", total), UVM_NONE)
    `uvm_info("COV", "============================================================", UVM_NONE)

    if (total < 90.0)
      `uvm_warning("COV", "Coverage below 90% — increase num_transactions in spi_rand_test")

  endfunction

endclass : spi_coverage