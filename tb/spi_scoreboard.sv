// =============================================================================
// File        : spi_scoreboard.sv
// Project     : SPI UVM Testbench
// Description : Scoreboard — checks data integrity for every SPI transfer.
//
//               Receives transactions from two separate monitors via two
//               analysis imp ports (master_export and slave_export).
//               Each write_*() call pushes to a queue and calls check_transfer().
//               When both queues have an entry, they are popped and checked.
//
//               Two checks per transaction:
//                 1. slave_rx  == master_data  (master sent → slave received)
//                 2. master_rx == slave_data   (slave sent  → master received)
//
//               After both checks, the scoreboard MERGES all four fields into
//               a single transaction and broadcasts it via cov_ap to coverage.
//               WHY merge? The master monitor only fills master_data + master_rx.
//               The slave monitor only fills slave_data + slave_rx.
//               Coverage needs all four — merging here is the cleanest solution.
//
// NOTE: The `uvm_analysis_imp_decl macros MUST be declared outside the class.
//       They generate write_master() and write_slave() method signatures.
//       They are placed here (inside the package via `include) so they are
//       declared exactly once before spi_scoreboard is defined.
// =============================================================================

`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class spi_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(spi_scoreboard)

  // ---------------------------------------------------------------------------
  // Ports
  // ---------------------------------------------------------------------------
  // Two separate imp ports — one from master monitor, one from slave monitor
  uvm_analysis_imp_master #(spi_transaction, spi_scoreboard) master_export;
  uvm_analysis_imp_slave  #(spi_transaction, spi_scoreboard) slave_export;

  // Outgoing port — broadcasts the fully merged transaction to spi_coverage
  // Connected in spi_env: scoreboard.cov_ap → coverage.analysis_export
  uvm_analysis_port #(spi_transaction) cov_ap;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------
  spi_transaction master_q[$];   // holds transactions from master monitor
  spi_transaction slave_q[$];    // holds transactions from slave monitor

  int unsigned pass_count;
  int unsigned fail_count;
  int unsigned txn_count;        // transaction number for log formatting
  string       test_name;        // set by each test for the summary header

  // ---------------------------------------------------------------------------
  // Constructor + phases
  // ---------------------------------------------------------------------------
  function new(string name = "spi_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    master_export = new("master_export", this);
    slave_export  = new("slave_export",  this);
    cov_ap        = new("cov_ap",        this);
    pass_count = 0;
    fail_count = 0;
    txn_count  = 0;
    test_name  = "UNKNOWN";
  endfunction

  // ---------------------------------------------------------------------------
  // write_master() — called when master monitor broadcasts a transaction
  // ---------------------------------------------------------------------------
  function void write_master(spi_transaction tr);
    master_q.push_back(tr);
    check_transfer();
  endfunction

  // ---------------------------------------------------------------------------
  // write_slave() — called when slave monitor broadcasts a transaction
  // ---------------------------------------------------------------------------
  function void write_slave(spi_transaction tr);
    slave_q.push_back(tr);
    check_transfer();
  endfunction

  // ---------------------------------------------------------------------------
  // check_transfer() — runs whenever either queue receives a new entry.
  //                    Only proceeds when BOTH queues have at least one entry.
  // ---------------------------------------------------------------------------
  function void check_transfer();
    spi_transaction m_tr, s_tr, merged;

    if (master_q.size() == 0 || slave_q.size() == 0) return;

    m_tr = master_q.pop_front();
    s_tr = slave_q.pop_front();
    txn_count++;

    // -----------------------------------------------------------------------
    // Check 1: Did slave receive what master sent?
    // master drove master_data onto MOSI → slave should have captured it
    // -----------------------------------------------------------------------
    if (s_tr.slave_rx === m_tr.master_data) begin
      `uvm_info("SB", $sformatf("[TXN %03d] PASS | slave_rx=0x%02h == master_tx=0x%02h",
        txn_count, s_tr.slave_rx, m_tr.master_data), UVM_NONE)
      pass_count++;
    end else begin
      `uvm_error("SB", $sformatf("[TXN %03d] FAIL | slave_rx=0x%02h != master_tx=0x%02h  *** MISMATCH ***",
        txn_count, s_tr.slave_rx, m_tr.master_data))
      fail_count++;
    end

    // -----------------------------------------------------------------------
    // Check 2: Did master receive what slave sent?
    // slave preloaded slave_data onto MISO → master should have captured it
    // -----------------------------------------------------------------------
    if (m_tr.master_rx === s_tr.slave_data) begin
      `uvm_info("SB", $sformatf("[TXN %03d] PASS | master_rx=0x%02h == slave_tx=0x%02h",
        txn_count, m_tr.master_rx, s_tr.slave_data), UVM_NONE)
      pass_count++;
    end else begin
      `uvm_error("SB", $sformatf("[TXN %03d] FAIL | master_rx=0x%02h != slave_tx=0x%02h  *** MISMATCH ***",
        txn_count, m_tr.master_rx, s_tr.slave_data))
      fail_count++;
    end

    // -----------------------------------------------------------------------
    // Merge both sides into one transaction and send to coverage.
    // master monitor fills: master_data, master_rx
    // slave  monitor fills: slave_data,  slave_rx
    // Coverage needs all four — neither monitor alone has the full picture.
    // -----------------------------------------------------------------------
    merged            = spi_transaction::type_id::create("merged");
    merged.master_data = m_tr.master_data;
    merged.slave_data  = s_tr.slave_data;
    merged.master_rx   = m_tr.master_rx;
    merged.slave_rx    = s_tr.slave_rx;
    cov_ap.write(merged);

  endfunction

  // ---------------------------------------------------------------------------
  // report_phase() — prints boxed summary at end of simulation
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info("SB", "============================================================", UVM_NONE)
    `uvm_info("SB", $sformatf("  SCOREBOARD SUMMARY  [%s]", test_name),             UVM_NONE)
    `uvm_info("SB", "============================================================", UVM_NONE)
    `uvm_info("SB", $sformatf("  Transactions checked : %0d", txn_count),           UVM_NONE)
    `uvm_info("SB", $sformatf("  Total checks         : %0d", pass_count+fail_count),UVM_NONE)
    `uvm_info("SB", $sformatf("  PASS                 : %0d", pass_count),           UVM_NONE)
    `uvm_info("SB", $sformatf("  FAIL                 : %0d", fail_count),           UVM_NONE)
    if (fail_count > 0) begin
      `uvm_info("SB",  "  RESULT               : *** TEST FAILED ***", UVM_NONE)
      `uvm_error("SB", "Scoreboard detected mismatches")
    end else
      `uvm_info("SB",  "  RESULT               : TEST PASSED", UVM_NONE)
    `uvm_info("SB", "============================================================", UVM_NONE)
  endfunction

endclass : spi_scoreboard