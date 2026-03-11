// =============================================================================
// File        : spi_slave_sequence.sv
// Project     : SPI UVM Testbench
// Description : All slave-side sequence classes.
//               Mirror structure of spi_master_sequence.sv.
//
//               Three sequences are defined here:
//
//               1. spi_slave_base_seq
//                  Single constrained-random preload. Used by spi_base_test
//                  and spi_reset_test.
//
//               2. spi_slave_directed_seq
//                  Single preload with a FIXED slave_data value set via
//                  the tx_value field. Used by spi_corners_test and
//                  spi_full_test to preload exact corner values into the
//                  slave TX buffer. Without this class those tests cannot compile.
//
//               3. spi_slave_rand_seq
//                  N constrained-random preloads. Default N=100.
//                  Must match the master sequence count so scoreboard queues
//                  stay balanced.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Base sequence — one random preload
// -----------------------------------------------------------------------------
class spi_slave_base_seq extends uvm_sequence #(spi_transaction);
  `uvm_object_utils(spi_slave_base_seq)

  function new(string name = "spi_slave_base_seq");
    super.new(name);
  endfunction

  task body();
    spi_transaction tr = spi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize())
      `uvm_fatal("SLAVE_SEQ", "Randomization failed")
    finish_item(tr);
  endtask

endclass : spi_slave_base_seq


// -----------------------------------------------------------------------------
// 2. Directed sequence — one preload with a specific slave_data value
//    Set tx_value before calling start():
//      spi_slave_directed_seq ss = spi_slave_directed_seq::type_id::create("ss");
//      ss.tx_value = 8'h55;
//      ss.start(env.slave_agent.sequencer);
// -----------------------------------------------------------------------------
class spi_slave_directed_seq extends uvm_sequence #(spi_transaction);
  `uvm_object_utils(spi_slave_directed_seq)

  logic [7:0] tx_value;  // set this before calling start()

  function new(string name = "spi_slave_directed_seq");
    super.new(name);
  endfunction

  task body();
    spi_transaction tr = spi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with { slave_data == tx_value; })
      `uvm_fatal("SLAVE_SEQ", "Directed randomization failed")
    finish_item(tr);
  endtask

endclass : spi_slave_directed_seq


// -----------------------------------------------------------------------------
// 3. Random sequence — N constrained-random preloads
//    Default num_transactions = 100. Must match master sequence count.
// -----------------------------------------------------------------------------
class spi_slave_rand_seq extends uvm_sequence #(spi_transaction);
  `uvm_object_utils(spi_slave_rand_seq)

  int unsigned num_transactions = 100;

  function new(string name = "spi_slave_rand_seq");
    super.new(name);
  endfunction

  task body();
    spi_transaction tr;
    repeat (num_transactions) begin
      tr = spi_transaction::type_id::create("tr");
      start_item(tr);
      if (!tr.randomize())
        `uvm_fatal("SLAVE_SEQ", "Randomization failed")
      finish_item(tr);
    end
  endtask

endclass : spi_slave_rand_seq