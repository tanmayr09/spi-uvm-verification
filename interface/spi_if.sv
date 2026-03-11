// =============================================================================
// File        : spi_if.sv
// Project     : SPI UVM Testbench
// Description : Shared SPI bus interface.
//               Connects the DUT ports, UVM drivers, and UVM monitors
//               through a single clean bundle.
//               Contains two clocking blocks:
//                 - cb_master : used by master driver + master monitor
//                 - cb_slave  : used by slave driver  + slave monitor
//               Assertions live in assertions/spi_assertions.sv and are
//               bound to this interface from spi_tb_top.sv.
// =============================================================================

interface spi_if (input logic clk);

  // ===========================================================================
  // 1. CORE SPI BUS SIGNALS
  //    These are the physical wires between master and slave.
  // ===========================================================================
  logic sclk;   // SPI clock      : master drives, slave receives
  logic mosi;   // Master-Out Slave-In : master drives, slave receives
  logic miso;   // Master-In Slave-Out : slave drives,  master receives
  logic ss;     // Slave Select (active LOW) : master drives, slave receives

  // ===========================================================================
  // 2. MASTER CONTROL SIGNALS
  //    These are the control/data pins on the SPIMaster module.
  //    The master driver writes i_tx_ready / i_tx_byte.
  //    The master monitor reads o_rx_byte / o_byte_ready / o_busy.
  // ===========================================================================
  logic       master_tx_ready;   // Pulse: tell master to start a transfer
  logic [7:0] master_tx_byte;    // Data byte master will send over MOSI
  logic [7:0] master_rx_byte;    // Data byte master received over MISO
  logic       master_byte_ready; // Pulse: master finished, rx_byte is valid
  logic       master_busy;       // High while master transfer is in progress

  // ===========================================================================
  // 3. SLAVE CONTROL SIGNALS
  //    These are the control/data pins on the spiSlave module.
  //    The slave driver writes i_tx_ready / i_tx_byte (preload TX buffer).
  //    The slave monitor reads o_rx_byte / o_byte_ready / o_busy.
  // ===========================================================================
  logic       slave_tx_ready;    // Pulse: load slave TX buffer
  logic [7:0] slave_tx_byte;     // Data byte slave will send over MISO
  logic [7:0] slave_rx_byte;     // Data byte slave received over MOSI
  logic       slave_byte_ready;  // Pulse: slave finished, rx_byte is valid
  logic       slave_busy;        // High while slave is selected (SS low)

  // ===========================================================================
  // 4. CLOCKING BLOCKS
  //
  //    WHY clocking blocks?
  //    Without them, a UVM driver writing a signal on the same posedge the DUT
  //    reads it causes a race condition — results become simulator-dependent.
  //    Clocking blocks enforce a safe sampling/driving skew automatically.
  //
  //    Convention:
  //      #1 input  skew  → sample 1ns BEFORE the clock edge (avoids hold issues)
  //      #1 output skew  → drive  1ns AFTER  the clock edge (avoids setup race)
  //
  //    cb_master : clocking block for master-side driver and monitor
  //    cb_slave  : clocking block for slave-side driver and monitor
  // ===========================================================================

  clocking cb_master @(posedge clk);
    // --- Master driver outputs (TB drives these INTO the master DUT) ---
    output #1 master_tx_ready;  // drive tx_ready after clock edge
    output #1 master_tx_byte;   // drive tx_byte  after clock edge

    // --- Master monitor inputs (TB samples these FROM the master DUT) ---
    input  #1 master_rx_byte;    // sample rx_byte
    input  #1 master_byte_ready; // sample byte_ready pulse
    input  #1 master_busy;       // sample busy

    // --- SPI bus signals visible to master monitor ---
    input  #1 sclk;
    input  #1 mosi;
    input  #1 miso;
    input  #1 ss;
  endclocking

  clocking cb_slave @(posedge clk);
    // --- Slave driver outputs (TB drives these INTO the slave DUT) ---
    output #1 slave_tx_ready;   // drive tx_ready after clock edge
    output #1 slave_tx_byte;    // drive tx_byte  after clock edge

    // --- Slave monitor inputs (TB samples these FROM the slave DUT) ---
    input  #1 slave_rx_byte;    // sample rx_byte
    input  #1 slave_byte_ready; // sample byte_ready pulse
    input  #1 slave_busy;       // sample busy

    // --- SPI bus signals visible to slave monitor ---
    input  #1 sclk;
    input  #1 mosi;
    input  #1 miso;
    input  #1 ss;
  endclocking

  // ===========================================================================
  // 5. MODPORTS
  //
  //    WHY modports?
  //    They restrict which signals each component can see and in which direction.
  //    This catches wiring bugs at compile time (e.g. a monitor accidentally
  //    driving a signal it should only observe).
  //
  //    mp_master_drv  : master driver  — can only drive master control inputs
  //    mp_master_mon  : master monitor — can only observe (read-only)
  //    mp_slave_drv   : slave driver   — can only drive slave control inputs
  //    mp_slave_mon   : slave monitor  — can only observe (read-only)
  //    mp_dut         : DUT connection — all signals, used in spi_tb_top.sv
  // ===========================================================================

  modport mp_master_drv (
    clocking cb_master,
    input    clk
  );

  modport mp_master_mon (
    clocking cb_master,
    input    clk
  );

  modport mp_slave_drv (
    clocking cb_slave,
    input    clk
  );

  modport mp_slave_mon (
    clocking cb_slave,
    input    clk
  );

  // DUT modport — tb_top uses this to wire the interface to the RTL ports
  modport mp_dut (
    input  clk,
    // SPI bus
    inout  sclk,
    inout  mosi,
    inout  miso,
    inout  ss,
    // Master side
    input  master_tx_ready,
    input  master_tx_byte,
    output master_rx_byte,
    output master_byte_ready,
    output master_busy,
    // Slave side
    input  slave_tx_ready,
    input  slave_tx_byte,
    output slave_rx_byte,
    output slave_byte_ready,
    output slave_busy
  );

endinterface : spi_if