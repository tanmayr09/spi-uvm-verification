// =============================================================================
// File        : spi_master_sequence.sv
// Project     : SPI UVM Testbench
// Description : All master-side sequence classes.
//
//               Three sequences are defined here:
//
//               1. spi_master_base_seq
//                  Single constrained-random transfer. Used by spi_base_test
//                  and spi_reset_test for simple smoke checks.
//
//               2. spi_master_directed_seq
//                  Single transfer with a FIXED master_data value set via
//                  the tx_value field. Used by spi_corners_test and
//                  spi_full_test to send exact corner values (0x00, 0xFF,
//                  0xAA, 0x55). Without this class those tests cannot compile.
//
//               3. spi_master_rand_seq
//                  N constrained-random transfers. Default N=100.
//                  Used by spi_rand_test, spi_stress_test (N=10),
//                  and Phase 2+3 of spi_full_test.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Base sequence — one random transfer
// -----------------------------------------------------------------------------
class spi_master_base_seq extends uvm_sequence #(spi_transaction);
  `uvm_object_utils(spi_master_base_seq)

  function new(string name = "spi_master_base_seq");
    super.new(name);
  endfunction

  task body();
    spi_transaction tr = spi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize())
      `uvm_fatal("MASTER_SEQ", "Randomization failed")
    finish_item(tr);
  endtask

endclass : spi_master_base_seq


// -----------------------------------------------------------------------------
// 2. Directed sequence — one transfer with a specific master_data value
//    Set tx_value before calling start():
//      spi_master_directed_seq ms = spi_master_directed_seq::type_id::create("ms");
//      ms.tx_value = 8'hAA;
//      ms.start(env.master_agent.sequencer);
// -----------------------------------------------------------------------------
class spi_master_directed_seq extends uvm_sequence #(spi_transaction);
  `uvm_object_utils(spi_master_directed_seq)

  logic [7:0] tx_value;  // set this before calling start()

  function new(string name = "spi_master_directed_seq");
    super.new(name);
  endfunction

  task body();
    spi_transaction tr = spi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with { master_data == tx_value; })
      `uvm_fatal("MASTER_SEQ", "Directed randomization failed")
    finish_item(tr);
  endtask

endclass : spi_master_directed_seq


// -----------------------------------------------------------------------------
// 3. Random sequence — N constrained-random transfers
//    Default num_transactions = 100. Override before calling start():
//      ms.num_transactions = 10;
// -----------------------------------------------------------------------------
class spi_master_rand_seq extends uvm_sequence #(spi_transaction);
  `uvm_object_utils(spi_master_rand_seq)

  int unsigned num_transactions = 100;

  function new(string name = "spi_master_rand_seq");
    super.new(name);
  endfunction

  task body();
    spi_transaction tr;
    repeat (num_transactions) begin
      tr = spi_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize())
        `uvm_fatal("MASTER_SEQ", "Randomization failed")
      finish_item(tr);
    end
  endtask

endclass : spi_master_rand_seq