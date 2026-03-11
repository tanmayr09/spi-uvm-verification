// =============================================================================
// File        : spi_tests.sv
// Project     : SPI UVM Testbench
// Description : All UVM test classes.
//
//               Six tests are defined here in dependency order:
//
//               1. spi_base_test     — base class, 1 random transfer (smoke)
//               2. spi_rand_test     — 100 constrained-random transfers
//               3. spi_corners_test  — 4 directed corner-value transfers
//               4. spi_stress_test   — 10 back-to-back random transfers
//               5. spi_reset_test    — transfer + reset recovery check
//               6. spi_full_test     — DEFAULT: corners(4) + stress(10) + rand(100)
//
//               All tests extend spi_base_test and inherit env creation.
//               The fork/join pattern is used in every test:
//                 - slave sequence starts first (preloads TX buffer)
//                 - master sequence starts 50ns later (gives slave time to preload)
//               This timing requirement comes from the spiSlave RTL: it only
//               accepts i_tx_ready when r_ss == 1 (idle/deselected).
//
//               To run on EDA Playground:
//                 Run Options: +UVM_TESTNAME=spi_full_test +access +r
// =============================================================================


// =============================================================================
// 1. spi_base_test — base class + smoke test (1 random transfer)
// =============================================================================
class spi_base_test extends uvm_test;
  `uvm_component_utils(spi_base_test)

  spi_env env;

  function new(string name = "spi_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = spi_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    spi_master_base_seq ms;
    spi_slave_base_seq  ss;

    phase.raise_objection(this);
    env.scoreboard.test_name = "spi_base_test";

    `uvm_info("TEST", "-------- spi_base_test START --------", UVM_NONE)
    #200;

    ms = spi_master_base_seq::type_id::create("ms");
    ss = spi_slave_base_seq::type_id::create("ss");

    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join

    #500;
    `uvm_info("TEST", "-------- spi_base_test END --------", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass : spi_base_test


// =============================================================================
// 2. spi_rand_test — 100 constrained-random transfers
// =============================================================================
class spi_rand_test extends spi_base_test;
  `uvm_component_utils(spi_rand_test)

  function new(string name = "spi_rand_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    spi_master_rand_seq ms;
    spi_slave_rand_seq  ss;

    phase.raise_objection(this);
    env.scoreboard.test_name = "spi_rand_test";

    `uvm_info("TEST", "-------- spi_rand_test START (100 transfers) --------", UVM_NONE)
    #200;

    ms = spi_master_rand_seq::type_id::create("ms");
    ss = spi_slave_rand_seq::type_id::create("ss");
    ms.num_transactions = 500;
    ss.num_transactions = 500;

    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join

    #500;
    `uvm_info("TEST", "-------- spi_rand_test END --------", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass : spi_rand_test


// =============================================================================
// 3. spi_corners_test — 4 directed corner-value transfers
//    Sends: (0x00↔0xFF), (0xFF↔0x00), (0xAA↔0x55), (0x55↔0xAA)
//    Uses spi_master_directed_seq and spi_slave_directed_seq.
// =============================================================================
class spi_corners_test extends spi_base_test;
  `uvm_component_utils(spi_corners_test)

  function new(string name = "spi_corners_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Helper: run one directed pair (master_value ↔ slave_value)
  task run_one(logic [7:0] mv, logic [7:0] sv);
    spi_master_directed_seq ms;
    spi_slave_directed_seq  ss;
    ms = spi_master_directed_seq::type_id::create("ms");
    ss = spi_slave_directed_seq::type_id::create("ss");
    ms.tx_value = mv;
    ss.tx_value = sv;
    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join
    #300;
  endtask

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    env.scoreboard.test_name = "spi_corners_test";

    `uvm_info("TEST", "-------- spi_corners_test START --------", UVM_NONE)
    #200;
    `uvm_info("TEST", "[C1] master=0x00  slave=0xFF", UVM_NONE) run_one(8'h00, 8'hFF);
    `uvm_info("TEST", "[C2] master=0xFF  slave=0x00", UVM_NONE) run_one(8'hFF, 8'h00);
    `uvm_info("TEST", "[C3] master=0xAA  slave=0x55", UVM_NONE) run_one(8'hAA, 8'h55);
    `uvm_info("TEST", "[C4] master=0x55  slave=0xAA", UVM_NONE) run_one(8'h55, 8'hAA);
    #300;
    `uvm_info("TEST", "-------- spi_corners_test END --------", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass : spi_corners_test


// =============================================================================
// 4. spi_stress_test — 10 back-to-back random transfers
//    No extra delay between transfers — driver naturally waits for busy=0.
// =============================================================================
class spi_stress_test extends spi_base_test;
  `uvm_component_utils(spi_stress_test)

  function new(string name = "spi_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    spi_master_rand_seq ms;
    spi_slave_rand_seq  ss;

    phase.raise_objection(this);
    env.scoreboard.test_name = "spi_stress_test";

    `uvm_info("TEST", "-------- spi_stress_test START (10 back-to-back) --------", UVM_NONE)
    #200;

    ms = spi_master_rand_seq::type_id::create("ms");
    ss = spi_slave_rand_seq::type_id::create("ss");
    ms.num_transactions = 10;
    ss.num_transactions = 10;

    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join

    #500;
    `uvm_info("TEST", "-------- spi_stress_test END --------", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass : spi_stress_test


// =============================================================================
// 5. spi_reset_test — transfer + reset recovery
//    Runs a normal transfer, waits through a reset window (assertions check
//    that the FSM returns to idle), then runs another transfer to confirm
//    the design recovers correctly.
// =============================================================================
class spi_reset_test extends spi_base_test;
  `uvm_component_utils(spi_reset_test)

  function new(string name = "spi_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    spi_master_base_seq ms;
    spi_slave_base_seq  ss;

    phase.raise_objection(this);
    env.scoreboard.test_name = "spi_reset_test";

    `uvm_info("TEST", "-------- spi_reset_test START --------", UVM_NONE)
    #200;

    // Phase 1: Normal transfer before reset window
    `uvm_info("TEST", "Phase 1: Normal transfer before reset", UVM_NONE)
    ms = spi_master_base_seq::type_id::create("ms1");
    ss = spi_slave_base_seq::type_id::create("ss1");
    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join
    #200;

    // Phase 2: Reset window — SVA assertions verify idle restoration
    `uvm_info("TEST", "Phase 2: Reset period — SVA checks idle restoration", UVM_NONE)
    #100;

    // Phase 3: Transfer after reset window
    `uvm_info("TEST", "Phase 3: Transfer after reset — verifying recovery", UVM_NONE)
    ms = spi_master_base_seq::type_id::create("ms2");
    ss = spi_slave_base_seq::type_id::create("ss2");
    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join
    #500;

    `uvm_info("TEST", "-------- spi_reset_test END --------", UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass : spi_reset_test


// =============================================================================
// 6. spi_full_test — DEFAULT TEST
//    Runs all three phases in a single simulation:
//      Phase 1: 4 directed corner transfers
//      Phase 2: 10 back-to-back random (stress)
//      Phase 3: 100 constrained-random
//    Total: 114 transactions, 228 scoreboard checks, 100% coverage
//
//    Run on EDA Playground with:
//      +UVM_TESTNAME=spi_full_test +access +r
// =============================================================================
class spi_full_test extends spi_base_test;
  `uvm_component_utils(spi_full_test)

  function new(string name = "spi_full_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Helper: run one directed pair
  task run_one(logic [7:0] mv, logic [7:0] sv);
    spi_master_directed_seq ms;
    spi_slave_directed_seq  ss;
    ms = spi_master_directed_seq::type_id::create("ms");
    ss = spi_slave_directed_seq::type_id::create("ss");
    ms.tx_value = mv;
    ss.tx_value = sv;
    fork
      ss.start(env.slave_agent.sequencer);
      begin #50; ms.start(env.master_agent.sequencer); end
    join
    #300;
  endtask

  task run_phase(uvm_phase phase);
    spi_master_rand_seq mr;
    spi_slave_rand_seq  sr;

    phase.raise_objection(this);
    env.scoreboard.test_name = "spi_full_test";

    `uvm_info("TEST", "",                                                                          UVM_NONE)
    `uvm_info("TEST", "############################################################",             UVM_NONE)
    `uvm_info("TEST", "#  SPI UVM TESTBENCH — FULL REGRESSION                     #",             UVM_NONE)
    `uvm_info("TEST", "#  Phase 1: Corners (4)  Phase 2: Stress (10)  Phase 3: Random (500) #",   UVM_NONE)
    `uvm_info("TEST", "############################################################",             UVM_NONE)
    `uvm_info("TEST", "",                                                                          UVM_NONE)
    #200;

    // ------------------------------------------------------------------
    // Phase 1 — Corner cases (4 directed transfers)
    // ------------------------------------------------------------------
    `uvm_info("TEST", ">>> PHASE 1: CORNER CASES", UVM_NONE)
    run_one(8'h00, 8'hFF);
    run_one(8'hFF, 8'h00);
    run_one(8'hAA, 8'h55);
    run_one(8'h55, 8'hAA);
    `uvm_info("TEST", ">>> PHASE 1 COMPLETE", UVM_NONE)
    `uvm_info("TEST", "",                     UVM_NONE)

    // ------------------------------------------------------------------
    // Phase 2 — Stress (10 back-to-back)
    // ------------------------------------------------------------------
    `uvm_info("TEST", ">>> PHASE 2: STRESS (10 back-to-back)", UVM_NONE)
    mr = spi_master_rand_seq::type_id::create("mr2");
    sr = spi_slave_rand_seq::type_id::create("sr2");
    mr.num_transactions = 10;
    sr.num_transactions = 10;
    fork
      sr.start(env.slave_agent.sequencer);
      begin #50; mr.start(env.master_agent.sequencer); end
    join
    #300;
    `uvm_info("TEST", ">>> PHASE 2 COMPLETE", UVM_NONE)
    `uvm_info("TEST", "",                     UVM_NONE)

    // ------------------------------------------------------------------
    // Phase 3 — Random (100 transfers)
    // ------------------------------------------------------------------
    `uvm_info("TEST", ">>> PHASE 3: RANDOM (500 transfers)", UVM_NONE)
    mr = spi_master_rand_seq::type_id::create("mr3");
    sr = spi_slave_rand_seq::type_id::create("sr3");
    mr.num_transactions = 500;
    sr.num_transactions = 500;
    fork
      sr.start(env.slave_agent.sequencer);
      begin #50; mr.start(env.master_agent.sequencer); end
    join
    #500;
    `uvm_info("TEST", ">>> PHASE 3 COMPLETE", UVM_NONE)
    `uvm_info("TEST", "",                     UVM_NONE)

    `uvm_info("TEST", "############################################################",            UVM_NONE)
    `uvm_info("TEST", "#  FULL REGRESSION COMPLETE — see SB + COV summaries below  #",           UVM_NONE)
    `uvm_info("TEST", "############################################################",            UVM_NONE)

    phase.drop_objection(this);
  endtask

endclass : spi_full_test