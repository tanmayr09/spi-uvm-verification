// =============================================================================
// File : spi_slave_agent.sv
// =============================================================================
class spi_slave_agent extends uvm_agent;
  `uvm_component_utils(spi_slave_agent)

  spi_slave_driver  driver;
  spi_slave_monitor monitor;
  uvm_sequencer #(spi_transaction) sequencer;

  uvm_analysis_port #(spi_transaction) ap;

  function new(string name = "spi_slave_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap        = new("ap", this);
    sequencer = uvm_sequencer #(spi_transaction)::type_id::create("sequencer", this);
    driver    = spi_slave_driver::type_id::create("driver", this);
    monitor   = spi_slave_monitor::type_id::create("monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
    monitor.ap.connect(ap);
  endfunction

endclass : spi_slave_agent