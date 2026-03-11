// =============================================================================
// File        : spi_env.sv
// Project     : SPI UVM Testbench
// Description : Top-level UVM environment.
//               Instantiates and connects all agents, scoreboard, and coverage.
//
//               Connection map (connect_phase):
//
//                 master_agent.ap  ──►  scoreboard.master_export
//                 slave_agent.ap   ──►  scoreboard.slave_export
//                 scoreboard.cov_ap ──► coverage.analysis_export
//
//               WHY scoreboard.cov_ap → coverage (NOT master_agent.ap)?
//               The scoreboard merges both monitor transactions into one object
//               that has ALL four fields populated:
//                 master_data, master_rx  ← from master monitor
//                 slave_data,  slave_rx   ← from slave monitor
//               Coverage needs all four to sample cp_slave_data, cp_slave_rx,
//               and cp_full_duplex. Connecting master_agent.ap directly would
//               leave slave_data and slave_rx as zero — those coverpoints
//               would never close.
// =============================================================================

class spi_env extends uvm_env;
  `uvm_component_utils(spi_env)

  spi_master_agent master_agent;
  spi_slave_agent  slave_agent;
  spi_scoreboard   scoreboard;
  spi_coverage     coverage;

  function new(string name = "spi_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    master_agent = spi_master_agent::type_id::create("master_agent", this);
    slave_agent  = spi_slave_agent::type_id::create("slave_agent",   this);
    scoreboard   = spi_scoreboard::type_id::create("scoreboard",     this);
    coverage     = spi_coverage::type_id::create("coverage",         this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // Both monitors → scoreboard (separate imp ports)
    master_agent.ap.connect(scoreboard.master_export);
    slave_agent.ap.connect(scoreboard.slave_export);

    // Scoreboard broadcasts MERGED transaction → coverage
    // This is the correct connection — do NOT connect master_agent.ap here
    scoreboard.cov_ap.connect(coverage.analysis_export);
  endfunction

endclass : spi_env