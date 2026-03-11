// =============================================================================
// File        : spi_transaction.sv
// Project     : SPI UVM Testbench
// Description : Shared UVM sequence item for one complete SPI transfer.
//
// CONSTRAINT PHILOSOPHY (updated for real coverage-driven verification):
//
//   OLD approach — the constraints were FORCING corner values with dist{}.
//   This made coverage close fast but it was the constraints doing the work,
//   not the randomiser. Coverage was measuring "did our forced stimulus fire?"
//   rather than "did the design handle what the solver threw at it?"
//
//   NEW approach — pure unconstrained random by default.
//   The only active constraint is c_not_same (master != slave) which exists
//   to prevent a wiring short from being masked. Corner values (0x00, 0xFF,
//   0xAA, 0x55, single-bit values) will appear naturally over enough
//   transactions — the coverage model measures when they do.
//
//   Directed sequences (spi_master_directed_seq / spi_slave_directed_seq)
//   still exist for the corner-case phase of spi_full_test. Those send
//   exact values on purpose. But the random phase uses pure randomness.
//
//   Constraint classes available:
//     c_not_same       — always active: master_data != slave_data
//     c_corners        — disabled by default, enable in directed tests
//     c_single_bits    — disabled by default, enable for bit-walk tests
//     c_allow_equal    — disables c_not_same when you want equal values
// =============================================================================

class spi_transaction extends uvm_sequence_item;

  `uvm_object_utils_begin(spi_transaction)
    `uvm_field_int(master_data, UVM_ALL_ON)
    `uvm_field_int(slave_data,  UVM_ALL_ON)
    `uvm_field_int(master_rx,   UVM_ALL_ON)
    `uvm_field_int(slave_rx,    UVM_ALL_ON)
  `uvm_object_utils_end

  // ---------------------------------------------------------------------------
  // Stimulus fields (randomised by sequences, driven by drivers)
  // ---------------------------------------------------------------------------
  rand logic [7:0] master_data;   // byte master sends over MOSI
  rand logic [7:0] slave_data;    // byte slave preloads into TX buffer (MISO)

  // ---------------------------------------------------------------------------
  // Response fields (filled in by monitors after transfer completes)
  // ---------------------------------------------------------------------------
  logic [7:0] master_rx;          // byte master actually received over MISO
  logic [7:0] slave_rx;           // byte slave actually received over MOSI

  // ---------------------------------------------------------------------------
  // Metadata
  // ---------------------------------------------------------------------------
  logic master_byte_ready;
  logic slave_byte_ready;
  time  start_time;
  time  end_time;

  // ---------------------------------------------------------------------------
  // Constraints
  // ---------------------------------------------------------------------------

  // Always active — master and slave must send different values.
  // WHY: if master_data == slave_data on every transfer, a MOSI-MISO
  // short circuit would go completely undetected. The scoreboard checks
  // would still pass because both sides received the same value.
  // This constraint ensures full-duplex independence is always exercised.
  constraint c_not_same {
    master_data != slave_data;
  }

  // Disabled by default — enable in directed tests when you specifically
  // want to force corner values. Use with:
  //   tr.c_corners.constraint_mode(1);
  constraint c_corners {
    master_data inside {8'h00, 8'hFF, 8'hAA, 8'h55, 8'h01, 8'h80, 8'h7F, 8'hFE};
    slave_data  inside {8'h00, 8'hFF, 8'hAA, 8'h55, 8'h01, 8'h80, 8'h7F, 8'hFE};
  }

  // Disabled by default — enable for a bit-walk sequence that sends
  // every power-of-two value to check each bit position independently.
  constraint c_single_bits {
    master_data inside {8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80};
    slave_data  inside {8'hFE, 8'hFD, 8'hFB, 8'hF7, 8'hEF, 8'hDF, 8'hBF, 8'h7F};
  }

  // Disabled by default — enables equal values (turns off c_not_same).
  // Use when you specifically want to test master_data == slave_data transfers.
  constraint c_allow_equal {
    master_data == slave_data;
  }

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "spi_transaction");
    super.new(name);
    // Disable directed constraints by default — pure random
    c_corners.constraint_mode(0);
    c_single_bits.constraint_mode(0);
    c_allow_equal.constraint_mode(0);
  endfunction

  // ---------------------------------------------------------------------------
  // convert2string
  // ---------------------------------------------------------------------------
  function string convert2string();
    return $sformatf(
      "mst_tx=0x%02h  slv_tx=0x%02h  |  mst_rx=0x%02h  slv_rx=0x%02h  [%0t-%0t]",
      master_data, slave_data, master_rx, slave_rx, start_time, end_time
    );
  endfunction

endclass : spi_transaction