// =============================================================================
// File        : spi_slave_monitor.sv
// Project     : SPI UVM Testbench
// Description : Passive monitor for the SPI slave agent.
//               Observes slave-side signals and builds transactions.
//
//               Critical timing decision — WHY negedge ss for slave_data:
//
//                 The slave driver preloads the TX buffer BEFORE SS goes low.
//                 After the transfer ends (posedge SS + byte_ready), the driver
//                 immediately preloads the buffer again for the NEXT transfer.
//                 If this monitor waits for posedge SS before capturing slave_data,
//                 it risks reading the NEXT preloaded value instead of the
//                 current one — giving wrong data to the scoreboard.
//
//                 Solution: trigger on NEGEDGE SS (start of transfer) and
//                 capture slave_tx_byte one clock later. At that point the
//                 current preloaded value is still valid on the interface.
//                 Then wait for POSEDGE SS to know the transfer ended, wait
//                 for byte_ready to confirm slave_rx_byte is valid, then
//                 capture slave_rx and broadcast the transaction.
//
//               Timing sequence:
//                 1. @(negedge ss)         — transfer starts
//                 2. @(posedge clk)        — settle one cycle
//                 3. capture slave_data    — still valid from preload
//                 4. @(posedge ss)         — transfer ends
//                 5. @(posedge clk)        — settle
//                 6. wait(byte_ready==1)   — slave latched rx_byte
//                 7. @(posedge clk)        — settle
//                 8. capture slave_rx      — valid
//                 9. ap.write(tr)          — broadcast to scoreboard
// =============================================================================

class spi_slave_monitor extends uvm_monitor;
  `uvm_component_utils(spi_slave_monitor)

  virtual spi_if vif;

  // Analysis port — broadcasts completed transactions to scoreboard
  uvm_analysis_port #(spi_transaction) ap;

  function new(string name = "spi_slave_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif))
      `uvm_fatal("SLAVE_MON", "build_phase: failed to get vif from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    spi_transaction tr;

    forever begin

      // Step 1: Wait for SS to go LOW — transfer is starting
      // Capture slave_data here while the preloaded value is still valid
      @(negedge vif.ss);
      tr            = spi_transaction::type_id::create("tr");
      tr.start_time = $time;

      // Step 2-3: One clock settle, then capture slave_tx_byte
      @(posedge vif.clk);
      tr.slave_data = vif.slave_tx_byte;

      // Step 4: Wait for SS to go HIGH — transfer is ending
      @(posedge vif.ss);

      // Step 5-7: Wait for slave_byte_ready pulse — slave has latched rx_byte
      @(posedge vif.clk);
      wait(vif.slave_byte_ready === 1'b1);
      @(posedge vif.clk);

      // Step 8: Capture received byte and metadata
      tr.slave_rx         = vif.slave_rx_byte;
      tr.slave_byte_ready = vif.slave_byte_ready;
      tr.end_time         = $time;

      `uvm_info("SLAVE_MON",
        $sformatf("Observed: slave_data=0x%02h  slave_rx=0x%02h",
          tr.slave_data, tr.slave_rx),
        UVM_MEDIUM)

      // Step 9: Broadcast to scoreboard
      ap.write(tr);

    end
  endtask

endclass : spi_slave_monitor