// =============================================================================
// File : spi_tb_top.sv
// Description : Top-level module. Instantiates DUTs, interface, clock/reset,
//               passes interface to UVM via config_db, binds assertions,
//               and kicks off the UVM test.
// =============================================================================
`timescale 1ns/1ps

// Import UVM and the SPI TB package
import uvm_pkg::*;
`include "uvm_macros.svh"
import spi_pkg::*;

module spi_tb_top;

  // ==========================================================================
  // Parameters — match procedural TB exactly
  // ==========================================================================
  parameter CLK_PERIOD           = 10;   // 100 MHz
  parameter DIVIDE_FREQUENCY_SPI = 1;
  parameter MODE                 = 0;
  parameter FRAME_FORMAT         = 0;
  parameter SS_PIN_ENABLE        = 1;

  // ==========================================================================
  // Clock and Reset
  // ==========================================================================
  logic clk;
  logic rst_n;
  logic clk_en;

  initial begin
    $dumpvars(0, spi_tb_top);
  end

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  assign clk_en = 1'b1;

  // Reset: assert for 10 cycles, then release
  initial begin
    rst_n = 1'b0;
    repeat(10) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  end

  // ==========================================================================
  // Interface instantiation
  // ==========================================================================
  spi_if dut_if (.clk(clk));

  // Connect reset to interface so assertions and monitors can access it
  assign dut_if.rst_n = rst_n;

  // ==========================================================================
  // DUT instantiation — SPIMaster
  // ==========================================================================
  SPIMaster #(
    .DIVIDE_FREQUENCY_SPI (DIVIDE_FREQUENCY_SPI),
    .MODE                 (MODE),
    .FRAME_FORMAT         (FRAME_FORMAT),
    .SS_PIN_ENABLE        (SS_PIN_ENABLE)
  ) u_master (
    .i_Clk        (clk),
    .i_Clk_en     (clk_en),
    .i_Rst_n      (rst_n),
    .i_tx_ready   (dut_if.master_tx_ready),
    .i_tx_byte    (dut_if.master_tx_byte),
    .o_rx_byte    (dut_if.master_rx_byte),
    .i_miso       (dut_if.miso),
    .o_mosi       (dut_if.mosi),
    .o_sclk       (dut_if.sclk),
    .o_ss         (dut_if.ss),
    .o_byte_ready (dut_if.master_byte_ready),
    .o_busy       (dut_if.master_busy)
  );

  // ==========================================================================
  // DUT instantiation — spiSlave
  // ==========================================================================
  spiSlave #(
    .MODE         (MODE),
    .FRAME_FORMAT (FRAME_FORMAT)
  ) u_slave (
    .i_Clk        (clk),
    .i_Clk_en     (clk_en),
    .i_Rst_n      (rst_n),
    .i_tx_ready   (dut_if.slave_tx_ready),
    .i_tx_byte    (dut_if.slave_tx_byte),
    .o_rx_byte    (dut_if.slave_rx_byte),
    .o_byte_ready (dut_if.slave_byte_ready),
    .o_busy       (dut_if.slave_busy),
    .i_mosi       (dut_if.mosi),
    .i_sclk       (dut_if.sclk),
    .i_ss         (dut_if.ss),
    .o_miso       (dut_if.miso)
  );

  // ==========================================================================
  // Bind SVA assertions to the interface
  // WHY bind? It attaches the assertion module to the interface signals
  // without modifying the DUT or interface source — industry standard practice.
  // ==========================================================================
  bind spi_if spi_assertions u_spi_assertions (
    .clk               (clk),
    .rst_n             (rst_n),
    .sclk              (sclk),
    .mosi              (mosi),
    .miso              (miso),
    .ss                (ss),
    .master_tx_byte    (master_tx_byte),
    .master_rx_byte    (master_rx_byte),
    .master_tx_ready   (master_tx_ready),
    .master_byte_ready (master_byte_ready),
    .master_busy       (master_busy),
    .slave_tx_byte     (slave_tx_byte),
    .slave_rx_byte     (slave_rx_byte),
    .slave_tx_ready    (slave_tx_ready),
    .slave_byte_ready  (slave_byte_ready),
    .slave_busy        (slave_busy)
  );

  // ==========================================================================
  // Pass interface to UVM via config_db
  // WHY: UVM components are dynamic objects — they can't directly access
  // module-level signals. config_db bridges the static/dynamic boundary.
  // Both master and slave agents retrieve the same interface handle.
  // ==========================================================================
  initial begin
    uvm_config_db #(virtual spi_if)::set(null, "uvm_test_top.*", "vif", dut_if);
    // Run the random test by default
    // To run base test: pass +UVM_TESTNAME=spi_base_test on command line
    run_test("spi_rand_test");
  end

endmodule : spi_tb_top