// =============================================================================
// File : spi_master_monitor.sv
// =============================================================================
class spi_master_monitor extends uvm_monitor;
  `uvm_component_utils(spi_master_monitor)

  virtual spi_if vif;

  // Analysis port — broadcasts completed transactions to scoreboard + coverage
  uvm_analysis_port #(spi_transaction) ap;

  function new(string name = "spi_master_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif))
      `uvm_fatal("MASTER_MON", "build_phase: failed to get vif from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    spi_transaction tr;

    forever begin
      // Wait for SS to go LOW — start of a transfer
      @(negedge vif.ss);

      tr = spi_transaction::type_id::create("tr");
      tr.start_time = $time;

      // Capture what the master was sending (already driven on interface)
      @(posedge vif.clk);
      tr.master_data = vif.master_tx_byte;

      // Wait for master_byte_ready pulse — transfer complete
      @(posedge vif.clk);
      wait(vif.master_byte_ready === 1'b1);
      @(posedge vif.clk);

      tr.master_rx          = vif.master_rx_byte;
      tr.master_byte_ready  = vif.master_byte_ready;
      tr.end_time           = $time;

      `uvm_info("MASTER_MON",
        $sformatf("Observed: master_data=0x%0h master_rx=0x%0h",
          tr.master_data, tr.master_rx),
        UVM_MEDIUM)

      // Broadcast transaction to scoreboard and coverage
      ap.write(tr);
    end
  endtask

endclass : spi_master_monitor