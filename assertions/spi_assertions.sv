// =============================================================================
// File : spi_assertions.sv
// Project : SPI UVM Testbench
// Description : SVA assertions bound to spi_if in spi_tb_top.sv
//               Ported and extended from spi_system_tb.sv procedural assertions
// =============================================================================
module spi_assertions (
  input logic clk,
  input logic rst_n,
  // SPI bus
  input logic sclk,
  input logic mosi,
  input logic miso,
  input logic ss,
  // Master signals
  input logic [7:0] master_tx_byte,
  input logic [7:0] master_rx_byte,
  input logic       master_tx_ready,
  input logic       master_byte_ready,
  input logic       master_busy,
  // Slave signals
  input logic [7:0] slave_tx_byte,
  input logic [7:0] slave_rx_byte,
  input logic       slave_tx_ready,
  input logic       slave_byte_ready,
  input logic       slave_busy
);

  // ==========================================================================
  // Group 1: Reset Assertions
  // ==========================================================================

  // 1.1 After reset, SS must be HIGH (slave deselected)
  property p_reset_ss_high;
    @(posedge clk) !rst_n |=> ss;
  endproperty
  a_reset_ss_high: assert property(p_reset_ss_high)
    else $error("[%0t] FAIL a_reset_ss_high", $time);

  // 1.2 After reset, master busy must be LOW
  property p_reset_master_busy_low;
    @(posedge clk) !rst_n |=> !master_busy;
  endproperty
  a_reset_master_busy_low: assert property(p_reset_master_busy_low)
    else $error("[%0t] FAIL a_reset_master_busy_low", $time);

  // 1.3 After reset, slave busy must be LOW
  property p_reset_slave_busy_low;
    @(posedge clk) !rst_n |=> !slave_busy;
  endproperty
  a_reset_slave_busy_low: assert property(p_reset_slave_busy_low)
    else $error("[%0t] FAIL a_reset_slave_busy_low", $time);

  // 1.4 After reset, MISO must be Z (slave tri-stated)
  property p_reset_miso_z;
    @(posedge clk) !rst_n |=> (miso === 1'bz);
  endproperty
  a_reset_miso_z: assert property(p_reset_miso_z)
    else $error("[%0t] FAIL a_reset_miso_z", $time);

  // ==========================================================================
  // Group 2: SPI Bus Protocol Assertions
  // ==========================================================================

  // 2.1 When SS rises, slave should not be busy shortly after
  property p_ss_high_slave_not_busy;
    @(posedge clk) disable iff(!rst_n)
    $rose(ss) |=> ##1 !slave_busy;
  endproperty
  a_ss_high_slave_not_busy: assert property(p_ss_high_slave_not_busy)
    else $error("[%0t] FAIL a_ss_high_slave_not_busy", $time);

  // 2.2 When SS falls, both master and slave must be busy shortly after
  property p_ss_low_both_busy;
    @(posedge clk) disable iff(!rst_n)
    $fell(ss) |=> ##1 (master_busy && slave_busy);
  endproperty
  a_ss_low_both_busy: assert property(p_ss_low_both_busy)
    else $error("[%0t] FAIL a_ss_low_both_busy", $time);

  // 2.3 MISO must be Z when SS is HIGH
  property p_miso_z_when_ss_high;
    @(posedge clk) disable iff(!rst_n)
    $rose(ss) |=> (miso === 1'bz);
  endproperty
  a_miso_z_when_ss_high: assert property(p_miso_z_when_ss_high)
    else $error("[%0t] FAIL a_miso_z_when_ss_high", $time);

  // 2.4 SCLK must be stable (LOW) when SS is HIGH and not just risen (CPOL=0)
  property p_sclk_idle_when_ss_high;
    @(posedge clk) disable iff(!rst_n)
    (ss && !$rose(ss)) |=> $stable(sclk);
  endproperty
  a_sclk_idle_when_ss_high: assert property(p_sclk_idle_when_ss_high)
    else $error("[%0t] FAIL a_sclk_idle_when_ss_high", $time);

  // ==========================================================================
  // Group 3: End-to-End Data Integrity
  // ==========================================================================

  // 3.1 master_byte_ready must be a single cycle pulse
  property p_master_byte_ready_pulse;
    @(posedge clk) disable iff(!rst_n)
    master_byte_ready |=> !master_byte_ready;
  endproperty
  a_master_byte_ready_pulse: assert property(p_master_byte_ready_pulse)
    else $error("[%0t] FAIL a_master_byte_ready_pulse", $time);

  // 3.2 slave_byte_ready must be a single cycle pulse
  property p_slave_byte_ready_pulse;
    @(posedge clk) disable iff(!rst_n)
    slave_byte_ready |=> !slave_byte_ready;
  endproperty
  a_slave_byte_ready_pulse: assert property(p_slave_byte_ready_pulse)
    else $error("[%0t] FAIL a_slave_byte_ready_pulse", $time);

  // 3.3 Slave byte_ready must follow master byte_ready within a few cycles
  property p_slave_ready_after_master;
    @(posedge clk) disable iff(!rst_n)
    master_byte_ready |-> ##[1:5] slave_byte_ready;
  endproperty
  a_slave_ready_after_master: assert property(p_slave_ready_after_master)
    else $error("[%0t] FAIL a_slave_ready_after_master", $time);

  // ==========================================================================
  // Group 4: Stability Assertions
  // ==========================================================================

  // 4.1 master_rx_byte must be stable after byte_ready falls
  property p_master_rx_stable;
    @(posedge clk) disable iff(!rst_n)
    $fell(master_byte_ready) |=> $stable(master_rx_byte);
  endproperty
  a_master_rx_stable: assert property(p_master_rx_stable)
    else $error("[%0t] FAIL a_master_rx_stable", $time);

  // 4.2 slave_rx_byte must be stable after byte_ready falls
  property p_slave_rx_stable;
    @(posedge clk) disable iff(!rst_n)
    $fell(slave_byte_ready) |=> $stable(slave_rx_byte);
  endproperty
  a_slave_rx_stable: assert property(p_slave_rx_stable)
    else $error("[%0t] FAIL a_slave_rx_stable", $time);

  // 4.3 If master is busy and tx_ready fires, busy must stay high
  property p_no_transfer_when_busy;
    @(posedge clk) disable iff(!rst_n)
    (master_tx_ready && master_busy) |=> master_busy;
  endproperty
  a_no_transfer_when_busy: assert property(p_no_transfer_when_busy)
    else $error("[%0t] FAIL a_no_transfer_when_busy", $time);

endmodule : spi_assertions