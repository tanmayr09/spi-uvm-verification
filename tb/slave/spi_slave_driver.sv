// =============================================================================
// File        : spi_slave_driver.sv
// Project     : SPI UVM Testbench
// Description : UVM driver for the SPI slave agent.
//
//               Critical timing requirement:
//                 The spiSlave RTL only accepts i_tx_ready when r_ss == 1
//                 (slave is idle / deselected). The TB preloads the TX buffer
//                 BEFORE the master drives SS low. The master driver delays
//                 its SS assertion by 50ns via a fork in the test — this gives
//                 the slave driver enough time to complete the preload pulse.
//
//               Timing sequence per transaction:
//                 1. get_next_item(tr)         — block until sequence sends one
//                 2. @(cb_slave)               — align to clock edge
//                 3. drive slave_tx_byte + slave_tx_ready HIGH for 1 cycle
//                 4. drive slave_tx_ready LOW  — 1-cycle pulse complete
//                 5. wait(slave_byte_ready==1) — transfer complete, rx valid
//                 6. @(cb_slave)               — let byte_ready fall
//                 7. item_done()               — release sequencer
// =============================================================================

class spi_slave_driver extends uvm_driver #(spi_transaction);
  `uvm_component_utils(spi_slave_driver)

  virtual spi_if vif;

  function new(string name = "spi_slave_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif))
      `uvm_fatal("SLAVE_DRV", "build_phase: failed to get vif from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    spi_transaction tr;

    // Initialize slave control signals to safe idle state
    vif.cb_slave.slave_tx_ready <= 1'b0;
    vif.cb_slave.slave_tx_byte  <= 8'h00;

    // Wait one clock before starting loop
    @(posedge vif.clk);

    forever begin

      // Step 1: Block until sequence provides a transaction
      seq_item_port.get_next_item(tr);

      `uvm_info("SLAVE_DRV",
        $sformatf("Preloading slave TX buffer: slave_data=0x%02h", tr.slave_data),
        UVM_MEDIUM)

      // Step 2: Align to clock edge
      @(vif.cb_slave);

      // Step 3: Drive data byte and assert tx_ready for one cycle
      vif.cb_slave.slave_tx_byte  <= tr.slave_data;
      vif.cb_slave.slave_tx_ready <= 1'b1;

      // Step 4: Deassert tx_ready — 1-cycle pulse
      @(vif.cb_slave);
      vif.cb_slave.slave_tx_ready <= 1'b0;

      // Step 5: Wait for slave_byte_ready — transfer is complete, rx_byte valid
      @(posedge vif.clk);
      wait(vif.slave_byte_ready === 1'b1);

      // Step 6: One more clock for byte_ready to fall and rx_byte to settle
      @(vif.cb_slave);

      `uvm_info("SLAVE_DRV",
        $sformatf("Slave transfer complete. slave_rx=0x%02h", vif.slave_rx_byte),
        UVM_HIGH)

      // Step 7: Release sequencer — allows sequence to send next transaction
      seq_item_port.item_done();

    end
  endtask

endclass : spi_slave_driver