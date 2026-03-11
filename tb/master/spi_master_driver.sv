// =============================================================================
// File        : spi_master_driver.sv
// Project     : SPI UVM Testbench
// Description : UVM driver for the SPI master agent.
//
//               Responsibilities:
//                 1. Fetch transactions from the sequencer via seq_item_port
//                 2. Wait for master to be free (not busy) — mirrors the
//                    wait(!master_busy) logic in the procedural TB
//                 3. Drive master_tx_byte and master_tx_ready into the interface
//                 4. Wait for the transfer to complete (master_byte_ready pulse)
//                 5. Return item to sequencer so next transaction can start
//
//               Timing model (matches procedural TB exactly):
//                 - All drives happen through cb_master clocking block
//                 - cb_master has #1 output skew → drives 1ns after posedge clk
//                 - This guarantees no race condition with the DUT
// =============================================================================

class spi_master_driver extends uvm_driver #(spi_transaction);

  // ---------------------------------------------------------------------------
  // UVM Factory Registration
  // ---------------------------------------------------------------------------
  `uvm_component_utils(spi_master_driver)

  // ---------------------------------------------------------------------------
  // Virtual Interface Handle
  //
  // WHY virtual?
  // The interface is a static SystemVerilog construct that exists in the module
  // hierarchy. UVM classes are dynamic objects — they can't directly hold a
  // module-level interface. A virtual interface is a handle (pointer) that a
  // dynamic class can hold, pointing to the actual interface instance.
  // The actual interface instance is set in spi_tb_top.sv via uvm_config_db.
  // ---------------------------------------------------------------------------
  virtual spi_if vif;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "spi_master_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // ---------------------------------------------------------------------------
  // build_phase()
  //
  // WHY: The build phase runs before simulation starts (time 0).
  // We retrieve the virtual interface handle from the UVM config database.
  // The config_db is the standard UVM mechanism for passing interfaces from
  // the static world (tb_top) into the dynamic world (UVM components).
  //
  // If the interface is not found, we call uvm_fatal — there is no point
  // running the simulation without a valid interface connection.
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("MASTER_DRV", "build_phase: failed to get vif from config_db")
    end
  endfunction

  // ---------------------------------------------------------------------------
  // run_phase()
  //
  // WHY: run_phase is where time actually passes. It runs as a continuous loop
  // for the entire simulation. Each iteration:
  //   1. Asks the sequencer for the next transaction (blocking get)
  //   2. Calls drive_transfer() to wiggle the pins
  //   3. Tells the sequencer the item is done (item_done)
  //
  // The forever loop is standard UVM driver pattern — the sequencer controls
  // how many transactions are sent; the driver just keeps consuming them.
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    spi_transaction tr;

    // Initialize master control signals to safe idle state
    vif.cb_master.master_tx_ready <= 1'b0;
    vif.cb_master.master_tx_byte  <= 8'h00;

    // Wait for reset to deassert before driving anything
    // WHY: Driving during reset can corrupt the DUT state machine
    @(posedge vif.clk);
    wait(vif.master_busy === 1'b0);

    forever begin
      // Step 1: Ask sequencer for next transaction — BLOCKS until one is ready
      seq_item_port.get_next_item(tr);

      `uvm_info("MASTER_DRV",
        $sformatf("Driving transfer: master_data=0x%0h  slave_data=0x%0h",
          tr.master_data, tr.slave_data),
        UVM_MEDIUM)

      // Step 2: Drive the transfer
      drive_transfer(tr);

      // Step 3: Tell sequencer this item is consumed — unblocks the sequence
      seq_item_port.item_done();
    end
  endtask

  // ---------------------------------------------------------------------------
  // drive_transfer()
  //
  // WHY a separate task?
  // Keeps run_phase clean and readable. This task mirrors the run_transfer()
  // task in your procedural TB but uses clocking block syntax instead of
  // direct signal assignment, and uses UVM messaging instead of $display.
  //
  // Timing sequence (must match procedural TB):
  //   1. Wait until master is not busy (safe to start)
  //   2. Drive master_tx_byte (set up data before the ready pulse)
  //   3. Drive master_tx_ready HIGH for one clock cycle (start pulse)
  //   4. Drive master_tx_ready LOW  (pulse width = 1 cycle)
  //   5. Wait for master_byte_ready to go HIGH (transfer complete)
  //   6. Wait one more clock (let byte_ready fall, rx_byte settle)
  // ---------------------------------------------------------------------------
  task drive_transfer(spi_transaction tr);

    // ------------------------------------------------------------------
    // Step 1: Wait for master to be free
    // WHY: The RTL only accepts i_tx_ready when state == STATE_IDLE.
    // If we pulse tx_ready while busy, the transfer is silently ignored.
    // This matches: wait(!master_busy) in the procedural TB.
    // ------------------------------------------------------------------
    while (vif.cb_master.master_busy) begin
      @(vif.cb_master);
    end

    // ------------------------------------------------------------------
    // Step 2 & 3: Set data byte and pulse tx_ready for one cycle
    // WHY one cycle after clock edge?
    // cb_master has #1 output skew — drives happen 1ns after posedge,
    // safely after the DUT has finished sampling the previous cycle.
    // ------------------------------------------------------------------
    @(vif.cb_master);
    vif.cb_master.master_tx_byte  <= tr.master_data;
    vif.cb_master.master_tx_ready <= 1'b1;

    // ------------------------------------------------------------------
    // Step 4: Drop tx_ready after one clock
    // WHY: The master RTL transitions from STATE_IDLE on the posedge where
    // it sees i_tx_ready HIGH. One cycle is sufficient — holding it high
    // longer does nothing but could confuse back-to-back transfers.
    // ------------------------------------------------------------------
    @(vif.cb_master);
    vif.cb_master.master_tx_ready <= 1'b0;

    // ------------------------------------------------------------------
    // Step 5: Wait for master_byte_ready pulse (transfer complete)
    // WHY: master_byte_ready fires one cycle after state returns to
    // STATE_IDLE. This is the handshake that says "rx_byte is valid now."
    // ------------------------------------------------------------------
    @(posedge vif.clk);
    wait(vif.master_byte_ready === 1'b1);

    // ------------------------------------------------------------------
    // Step 6: One extra clock for byte_ready to fall and rx_byte to settle
    // WHY: The monitor also watches byte_ready. Waiting here ensures the
    // monitor has time to sample before we request the next transaction.
    // ------------------------------------------------------------------
    @(vif.cb_master);

    `uvm_info("MASTER_DRV",
      $sformatf("Transfer complete. master_rx=0x%0h", vif.master_rx_byte),
      UVM_HIGH)

  endtask : drive_transfer

endclass : spi_master_driver