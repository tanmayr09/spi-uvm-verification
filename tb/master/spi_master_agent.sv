// =============================================================================
// File : spi_master_agent.sv
// =============================================================================
class spi_master_agent extends uvm_agent;
  `uvm_component_utils(spi_master_agent)

  spi_master_driver  driver;
  spi_master_monitor monitor;
  uvm_sequencer #(spi_transaction) sequencer;

  // Analysis port passthrough to env
  uvm_analysis_port #(spi_transaction) ap;

  function new(string name = "spi_master_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap        = new("ap", this);
    sequencer = uvm_sequencer #(spi_transaction)::type_id::create("sequencer", this);
    driver    = spi_master_driver::type_id::create("driver", this);
    monitor   = spi_master_monitor::type_id::create("monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // Connect driver to sequencer TLM port
    driver.seq_item_port.connect(sequencer.seq_item_export);
    // Pass monitor analysis port up to agent level
    monitor.ap.connect(ap);
  endfunction

endclass : spi_master_agent