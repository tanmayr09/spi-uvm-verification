// =============================================================================
// File : spi_pkg.sv
// Description : Package that bundles all UVM TB files in correct compile order.
//               On EDA Playground: add this as the ONLY TB file — it includes
//               everything else. The interface and top module are separate.
// =============================================================================
package spi_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // 1. Transaction — must be first (all other classes reference it)
  // --------------------------------------------------------------------------
  `include "spi_transaction.sv"

  // --------------------------------------------------------------------------
  // 2. Master agent components
  // --------------------------------------------------------------------------
  `include "spi_master_driver.sv"
  `include "spi_master_monitor.sv"
  `include "spi_master_sequence.sv"
  `include "spi_master_agent.sv"

  // --------------------------------------------------------------------------
  // 3. Slave agent components
  // --------------------------------------------------------------------------
  `include "spi_slave_driver.sv"
  `include "spi_slave_monitor.sv"
  `include "spi_slave_sequence.sv"
  `include "spi_slave_agent.sv"

  // --------------------------------------------------------------------------
  // 4. Shared system-level components
  // --------------------------------------------------------------------------
  `include "spi_scoreboard.sv"
  `include "spi_coverage.sv"
  `include "spi_env.sv"

  // --------------------------------------------------------------------------
  // 5. Tests — must be last (reference env and sequences)
  // --------------------------------------------------------------------------
  `include "spi_tests.sv"

endpackage : spi_pkg