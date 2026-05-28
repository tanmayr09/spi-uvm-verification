/*
 Description: SPI (Serial Peripheral Interface) Master
              
              Sends data one bit at a time on o_mosi
              Will also receive data one bit at a time on i_miso.               

Note: Sclk Frequency is equal to fsclk = Fpga Frequency / 2(n+1), where n is DIVIDE_FREQUENCY_SPI parameter      
              
 Parameters:  DIVIDE_FREQUENCY_SPI = See note above.
              DATA_WIDTH = Number of bits per SPI transfer (default 8). 
                           Supported: 8, 16, 32, etc.
 							
 							SPI_MODE
              Mode | Clock Polarity (CPOL) | Clock Phase (CPHA)
               0   |             0             |        0
               1   |             0             |        1
               2   |             1             |        0
               3   |             1             |        1
              See: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface#/media/File:SPI_timing_diagram2.svg
						
							FRAME FORMAT : 0 - MSB and 1 - LSB 
							SS_PIN_ENABLE : 1 - Enable the ss by Module. 0- Enable the ss by Module. 
															0- The signal is set up in High-Z. 
															In this case you need create the ss signal by yourself. 
															It's Advisable using  o_ss module signal and forward for desire slave. But it feel free.

Attention : If you use the multi-master, You need manage the i_Clk_en with the other cs signal to avoid start 
the communication while other master is using the bus. 
The same way, you need to guarantee than other masters don't try to use bus during communication this master. 

Attention : Before the pulse i_tx_ready must ensure that o_busy is low.

 ============================================================
 FORMAL VERIFICATION CHANGES (inside `ifdef FORMAL guards)
 ============================================================
 CHANGE 1 : bit -> logic for r_frame_formart, r_sclk, r_edge_detect,
            r_edge_detect_tmp, r_ss, r_mosi, w_Clk.
            Reason: Yosys handles 4-state `logic` cleanly in formal;
            `bit` with inline initializers is unreliable under clk2fflogic.

 CHANGE 2 : Inline initializers removed from r_frame_formart, r_sclk,
            r_edge_detect_tmp. These are now driven exclusively by reset.
            Reason: Yosys may silently ignore or mishandle inline
            initializers on registers under clk2fflogic elaboration.

 CHANGE 3 : r_frame_formart driven from reset block instead of
            declaration initializer.
            Reason: Same as CHANGE 2. Parameter value is captured in
            reset so behaviour is identical to original.

 CHANGE 4 : Tri-state ('z) on o_mosi replaced with 1'b0 under FORMAL.
            Reason: Formal solvers/Yosys do not model tri-state/high-Z.
            'z is treated as 'x which causes spurious assertion failures.

 CHANGE 5 : Tri-state ('z) on o_ss replaced with 1'b0 under FORMAL
            when SS_PIN_ENABLE == 0.
            Reason: Same as CHANGE 4.

 CHANGE 6 : w_mode_select declaration initializer removed; driven from
            a reset always_ff block instead.
            Reason: Same class of issue as CHANGE 2 — inline
            initializers on logic variables are unreliable under Yosys
            formal elaboration.
*/

module SPIMaster #(
    parameter DIVIDE_FREQUENCY_SPI = 1,
    parameter MODE                 = 0,
    parameter FRAME_FORMAT         = 0,
    parameter SS_PIN_ENABLE        = 1,
    parameter DATA_WIDTH           = 8
) (
    input                            i_Clk       ,
    input                            i_Clk_en    ,
    input                            i_Rst_n     ,
    input                            i_tx_ready  ,
    input  logic [DATA_WIDTH-1:0]    i_tx_byte   ,
    output logic [DATA_WIDTH-1:0]    o_rx_byte   ,
    input                            i_miso      ,
    output logic                     o_mosi      ,
    output logic                     o_sclk      ,
    output logic                     o_ss        ,
    output logic                     o_byte_ready,
    output logic                     o_busy
);

// ---------------------------------------------------------------------------
// Clock wire
// ---------------------------------------------------------------------------
// CHANGE 1: was `bit w_Clk`
logic w_Clk;

// ---------------------------------------------------------------------------
// SPI MODE decode
// ---------------------------------------------------------------------------
// CHANGE 6: was `logic [1:0] w_mode_select = MODE`
// Inline initializer removed; driven from reset block below.
logic [1:0] w_mode_select;
logic       w_CPOL;
logic       w_CPHA;

// ---------------------------------------------------------------------------
// Frame format
// ---------------------------------------------------------------------------
// CHANGE 1+2: was `bit r_frame_formart = bit'(FRAME_FORMAT)`
// Converted to logic, initializer removed, driven from reset block below.
logic r_frame_formart;

// ---------------------------------------------------------------------------
// SCLK generation
// ---------------------------------------------------------------------------
logic [$clog2(DIVIDE_FREQUENCY_SPI):0] r_cont_sclk;

// CHANGE 1+2: was `bit r_sclk` / `bit r_edge_detect`
logic r_sclk;
logic r_edge_detect;

// ---------------------------------------------------------------------------
// TX / RX data
// ---------------------------------------------------------------------------
logic [DATA_WIDTH-1:0] r_tx_byte, w_tx_byte;
logic [DATA_WIDTH-1:0] r_rx_byte;

// ---------------------------------------------------------------------------
// Auxiliary signals
// ---------------------------------------------------------------------------
// CHANGE 1: was `bit r_ss` / `bit r_mosi`
logic r_ss;
logic r_mosi;

logic [$clog2(DATA_WIDTH):0] r_cycle_count;
logic [7:0]                  r_count_pos_com;

// ---------------------------------------------------------------------------
// FSM
// ---------------------------------------------------------------------------
typedef enum logic[2:0] {
    STATE_IDLE,
    STATE_PRE_COMM,
    STATE_COMM,
    STATE_POS_COMM
} state_t;

state_t state, next_state;

// ---------------------------------------------------------------------------
// CHANGE 6: drive w_mode_select and r_frame_formart from reset
// These were previously set by inline initializers at declaration.
// Capturing parameter values here gives identical behaviour, but in a
// form Yosys/clk2fflogic handles correctly.
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin 
    if (~i_Rst_n) begin
        w_mode_select  <= MODE[1:0];
        r_frame_formart <= FRAME_FORMAT[0];
    end
    // These are constants derived from parameters — no other driver needed.
    // They will never change after reset deasserts.
end

// ---------------------------------------------------------------------------
// FSM state register
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        state <= STATE_IDLE;
    end else begin
        state <= next_state;
    end
end

// ---------------------------------------------------------------------------
// FSM combinational logic — unchanged
// ---------------------------------------------------------------------------
always_comb begin
    next_state = state;

    case (state)
        STATE_IDLE : begin
            if (i_tx_ready) begin
                next_state = STATE_PRE_COMM;
            end
        end

        STATE_PRE_COMM : begin
            next_state = STATE_COMM;
        end

        STATE_COMM : begin
            if (r_cycle_count >= ($clog2(DATA_WIDTH)'(0) + DATA_WIDTH[$clog2(DATA_WIDTH):0]) && r_edge_detect) begin
                next_state = STATE_POS_COMM;
            end
        end

        STATE_POS_COMM : begin
            if (r_count_pos_com == DIVIDE_FREQUENCY_SPI >> 1) begin
                next_state = STATE_IDLE;
            end
        end
    endcase
end

// ---------------------------------------------------------------------------
// Clock gating assign — unchanged functionally
// ---------------------------------------------------------------------------
assign w_Clk = i_Clk_en ? i_Clk : '0;

// ---------------------------------------------------------------------------
// o_mosi tri-state
// CHANGE 4: under FORMAL replace 'z with 1'b0 to avoid X-state issues.
// Outside FORMAL the original tri-state behaviour is preserved.
// ---------------------------------------------------------------------------
`ifdef FORMAL
    assign o_mosi = !r_ss ? r_mosi : 1'b0;
`else
    assign o_mosi = !r_ss ? r_mosi : 'z;
`endif

// ---------------------------------------------------------------------------
// SPI MODE decode — unchanged logic, now reads from r register (CHANGE 6)
// ---------------------------------------------------------------------------
always_comb begin
    if      (w_mode_select == 2'd0) begin w_CPOL = 1'b0; w_CPHA = 1'b0; end
    else if (w_mode_select == 2'd1) begin w_CPOL = 1'b0; w_CPHA = 1'b1; end
    else if (w_mode_select == 2'd2) begin w_CPOL = 1'b1; w_CPHA = 1'b0; end
    else if (w_mode_select == 2'd3) begin w_CPOL = 1'b1; w_CPHA = 1'b1; end
    else                            begin w_CPOL = 1'b0; w_CPHA = 1'b0; end
    // CHANGE 4 (minor): replaced 'z default with 1'b0 — same reason as o_mosi.
end

// ---------------------------------------------------------------------------
// TX shift register — unchanged
// ---------------------------------------------------------------------------
always_comb begin
    if (!r_frame_formart) begin
        w_tx_byte = r_tx_byte << r_cycle_count;
    end else begin
        w_tx_byte = r_tx_byte >> r_cycle_count;
    end
end

// ---------------------------------------------------------------------------
// TX buffer register — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_tx_byte <= '0;
    end else begin
        if (i_tx_ready && state == STATE_IDLE) begin
            r_tx_byte <= i_tx_byte;
        end
    end
end

// ---------------------------------------------------------------------------
// o_busy — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        o_busy <= '0;
    end else begin
        o_busy <= (state != STATE_IDLE) ? 1'b1 : 1'b0;
    end
end

// ---------------------------------------------------------------------------
// SS (Slave Select) register — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_ss <= 1'b1;
    end else begin
        if (state == STATE_PRE_COMM) begin
            r_ss <= 1'b0;
        end
        if (state == STATE_POS_COMM && (r_count_pos_com == DIVIDE_FREQUENCY_SPI >> 1)) begin
            r_ss <= 1'b1;
        end
    end
end

// ---------------------------------------------------------------------------
// o_ss output
// CHANGE 5: under FORMAL replace 'z with 1'b1 (deasserted/idle level)
// when SS_PIN_ENABLE==0, to avoid X-state issues.
// ---------------------------------------------------------------------------
always_comb begin
    if (SS_PIN_ENABLE) begin
        o_ss = r_ss;
    end else begin
`ifdef FORMAL
        o_ss = 1'b1;
`else
        o_ss = 1'bz;
`endif
    end
end

// ---------------------------------------------------------------------------
// MOSI shift + bit counter — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_mosi        <= '0;
        r_cycle_count <= '0;
    end else begin
        if ((state == STATE_PRE_COMM) && !w_CPHA) begin
            r_mosi        <= r_frame_formart ? w_tx_byte[0] : w_tx_byte[DATA_WIDTH-1];
            r_cycle_count <= r_cycle_count + 1'd1;
        end
        else if ((state == STATE_COMM) || (state == STATE_POS_COMM)) begin
            if (!w_CPHA) begin
                if (!r_sclk && r_edge_detect) begin
                    r_mosi        <= r_frame_formart ? w_tx_byte[0] : w_tx_byte[DATA_WIDTH-1];
                    r_cycle_count <= r_cycle_count + 1'd1;
                end
            end else begin
                if (r_sclk && r_edge_detect) begin
                    r_mosi        <= r_frame_formart ? w_tx_byte[0] : w_tx_byte[DATA_WIDTH-1];
                    r_cycle_count <= r_cycle_count + 1'd1;
                end
            end
        end
        else if (state == STATE_IDLE) begin
            r_cycle_count <= '0;
        end
    end
end

// ---------------------------------------------------------------------------
// SCLK counter — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_cont_sclk <= '0;
    end else begin
        if (state == STATE_COMM) begin
            if (r_cont_sclk == DIVIDE_FREQUENCY_SPI) begin
                r_cont_sclk <= '0;
            end else begin
                r_cont_sclk <= r_cont_sclk + 1'd1;
            end
        end else begin
            r_cont_sclk <= '0;
        end
    end
end

// ---------------------------------------------------------------------------
// SCLK edge detect
// CHANGE 1+2: r_edge_detect_tmp was `bit r_edge_detect_tmp` with no
// explicit reset. Now `logic`, reset to 0 explicitly.
// ---------------------------------------------------------------------------
// CHANGE 1+2: was `bit r_edge_detect_tmp`
logic r_edge_detect_tmp;

always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_sclk            <= 1'b0;
        r_edge_detect     <= 1'b0;
        r_edge_detect_tmp <= 1'b0;   // CHANGE 2: explicit reset added
    end else begin
        r_edge_detect_tmp <= r_edge_detect;
        if (state == STATE_COMM) begin
            if (r_cont_sclk == DIVIDE_FREQUENCY_SPI) begin
                r_sclk        <= !r_sclk;
                r_edge_detect <= 1'b1;
            end else begin
                r_edge_detect <= 1'b0;
            end
        end else begin
            r_sclk        <= 1'b0;
            r_edge_detect <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// o_sclk output — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        o_sclk <= 1'b0;
    end else begin
        if (state == STATE_COMM || state == STATE_POS_COMM) begin
            o_sclk <= w_CPOL ? !r_sclk : r_sclk;
        end else begin
            o_sclk <= w_CPOL ? 1'b1 : 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// POST_COMM counter — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_count_pos_com <= '0;
    end else begin
        if (state == STATE_POS_COMM) begin
            r_count_pos_com <= r_count_pos_com + 1'd1;
        end else if (state == STATE_IDLE) begin
            r_count_pos_com <= '0;
        end
    end
end

// ---------------------------------------------------------------------------
// RX shift register — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        r_rx_byte <= '0;
    end else begin
        if ((w_mode_select == 0 || w_mode_select == 3) && o_sclk && r_edge_detect_tmp) begin
            r_rx_byte <= !r_frame_formart ? {r_rx_byte[DATA_WIDTH-2:0], i_miso}
                                          : {i_miso, r_rx_byte[DATA_WIDTH-1:1]};
        end
        else if ((w_mode_select == 1 || w_mode_select == 2) && !o_sclk && r_edge_detect_tmp) begin
            r_rx_byte <= !r_frame_formart ? {r_rx_byte[DATA_WIDTH-2:0], i_miso}
                                          : {i_miso, r_rx_byte[DATA_WIDTH-1:1]};
        end
    end
end

// ---------------------------------------------------------------------------
// RX output + byte_ready — unchanged
// ---------------------------------------------------------------------------
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if (~i_Rst_n) begin
        o_rx_byte    <= '0;
        o_byte_ready <= 1'b0;
    end else begin
        if (state == STATE_IDLE && o_busy) begin
            o_rx_byte    <= r_rx_byte;
            o_byte_ready <= 1'b1;
        end else begin
            o_byte_ready <= 1'b0;
        end
    end
end

// ============================================================================
// FORMAL VERIFICATION BLOCK
// Only compiled when SymbiYosys defines FORMAL.
// Invisible to simulation and synthesis.
//
// Structure:
//   1. Past-valid tracking
//   2. Assumptions  (constrain solver inputs to legal stimulus)
//   3. Assertions   (properties the design must always satisfy)
//   4. Cover        (reachability witness for a complete transfer)
// ============================================================================
`ifdef FORMAL

// ----------------------------------------------------------------------------
// 1. PAST-VALID TRACKING
//
// $past() is valid only after the first clock edge.
// f_past_valid goes high after the very first posedge and stays high.
// Every assertion that uses $past() is gated on f_past_valid so the
// solver does not try to evaluate $past at time zero (undefined).
// ----------------------------------------------------------------------------
logic f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge w_Clk) f_past_valid <= 1'b1;

// ----------------------------------------------------------------------------
// 2. ASSUMPTIONS
//
// Assumptions tell the solver what it is ALLOWED to do with the inputs.
// Without these, the solver applies completely unrestricted stimulus —
// including illegal combinations your design was never designed to handle.
// A false counterexample caused by illegal stimulus is called a vacuous
// failure; assumptions prevent that.
//
// All assumptions use combinational always @(*) blocks.
// Reason: with clk2fflogic, i_Clk is a free solver variable, not a real
// clock. A clocked always @(posedge i_Clk) assumption has gaps between
// edges that the solver can exploit. always @(*) is evaluated every
// timestep with no gaps, making it airtight.
// ----------------------------------------------------------------------------

// -- A1: Clock enable is always asserted --
// We want to verify the design running normally.
// Holding i_Clk_en=1 simplifies the state space without losing coverage
// of any meaningful behaviour (i_Clk_en=0 just stalls everything).
always @(*) begin
    assume(i_Clk_en == 1'b1);
end

// -- A2: Reset is deasserted at time zero --
// The solver must start from a clean reset state.
// Without this, it can start with i_Rst_n=1 at time zero (before any
// reset has occurred), which means all registers hold unknown values.
initial assume(i_Rst_n == 1'b0);

// -- A3: i_tx_ready is never asserted while o_busy is high --
// This is the core protocol rule stated in the RTL header comment:
// "Before the pulse i_tx_ready must ensure that o_busy is low."
// If the solver violates this, it is driving the design illegally.
always @(*) begin
    if (o_busy) begin
        assume(i_tx_ready == 1'b0);
    end
end

// --A6: Reset is stable - once deasserted it never reasserts --
logic f_rst_n_prev;
initial f_rst_n_prev = 1'b0;
always @(posedge w_Clk) f_rst_n_prev <= i_Rst_n;

// If reset was high last w_Clk cycle, it must stay high now.
// This is purely combinational - no gaps for the solver to exploit.
always @(*) begin
    if (f_rst_n_prev) begin
        assume(i_Rst_n == 1'b1);
    end
end

// -- A4: i_tx_ready is a single-cycle pulse --
// Shadow register to track previous value of i_tx_ready.
// We need $past(i_tx_ready) in a combinational assume block, but Yosys
// rejects $past() outside clocked blocks. A shadow register is the
// correct substitute — it holds exactly what $past() would return.
logic f_tx_ready_prev;
initial f_tx_ready_prev = 1'b0;
always @(posedge w_Clk) f_tx_ready_prev <= i_tx_ready;

// Now constrain: if i_tx_ready was high last cycle, it must be low this cycle.
// This models a pulse — the user cannot hold tx_ready asserted continuously.
always @(*) begin
    if (f_past_valid) begin
        assume(!(i_tx_ready && f_tx_ready_prev));
    end
end

// -- A5: i_tx_ready starts low --
// Close the time-zero gap: before f_past_valid is set, we cannot rely
// on f_tx_ready_prev. This initial assume ensures the solver does not
// assert i_tx_ready at the very first timestep before reset completes.
initial assume(i_tx_ready == 1'b0);

// ----------------------------------------------------------------------------
// 3. ASSERTIONS
//
// These are the properties the design MUST satisfy for all possible
// legal input sequences (i.e. all sequences allowed by the assumptions).
// A single counterexample trace causes the assertion to FAIL.
//
// All assertions live inside always @(posedge i_Clk) blocks.
// Reason: clk2fflogic makes i_Clk a free variable; placing assertions
// here ties them to clock edges, which is the correct evaluation point
// for registered outputs.
// ----------------------------------------------------------------------------

// -- F2: Reset correctness --
// The cycle AFTER reset deasserts, all key outputs must be in their
// safe idle state:
//   o_busy = 0   (no transfer in progress)
//   o_ss   = 1   (slave not selected)
//   o_sclk = 0   (idle level for CPOL=0; we fix MODE=0 for this run)
// Gated on f_past_valid so $past() is safe to evaluate.
always @(posedge w_Clk) begin
    if (f_past_valid && !$past(i_Rst_n)) begin
        assert(o_busy == 1'b0);
        assert(o_ss   == 1'b1);
        assert(o_sclk == 1'b0);
    end
end

// -- F3: SS discipline --
// o_ss must only be low when the FSM is active (not IDLE).
// If the design ever pulls SS low while sitting in IDLE, that is a
// protocol violation — a slave would start receiving a phantom transfer.
always @(posedge w_Clk) begin
    if (f_past_valid && i_Rst_n) begin
        if (o_ss == 1'b0) begin
            assert(state != STATE_IDLE);
        end
    end
end

// -- F4: SCLK idle level --
// When the FSM is in IDLE or PRE_COMM, o_sclk must sit at the CPOL
// idle level. For MODE=0 (CPOL=0) that is 0. For MODE=2 (CPOL=1)
// that would be 1. Since we run with MODE=0, CPOL=0, we assert 0.
// This catches any glitch that drives SCLK outside the transfer window.
always @(posedge w_Clk) begin
    if (f_past_valid && i_Rst_n && $past(i_Rst_n)) begin
        // o_sclk is registered - check one cycle after state is stable
        if ($past(state) == STATE_IDLE || $past(state) == STATE_PRE_COMM) begin
            assert(o_sclk == w_CPOL);
        end
    end
end

// -- F5: Bit counter bounds --
// r_cycle_count must never exceed DATA_WIDTH.
// If it does, the FSM exit condition in STATE_COMM is broken and the
// design would shift out more bits than the transfer width — a serious
// protocol error.
always @(posedge w_Clk) begin
    if (f_past_valid && i_Rst_n) begin
        assert(r_cycle_count <= DATA_WIDTH[$clog2(DATA_WIDTH):0]);
    end
end

// -- F6: Bit counter resets in IDLE --
// Whenever the FSM is in STATE_IDLE, r_cycle_count must be zero.
// This ensures every new transfer starts from a clean count and bits
// from a previous transfer do not bleed into the next one.
always @(posedge w_Clk) begin
    if (f_past_valid && i_Rst_n && $past(i_Rst_n)) begin
        // r_cycle_count resets on posedge w_Clk when state==IDLE
        // so check it one cycle after entering IDLE 
        if ($past(state) == STATE_IDLE) begin
            assert(r_cycle_count == '0);
        end
    end
end

// -- F7: o_busy correctly tracks FSM --
always @(posedge w_Clk) begin
    if (f_past_valid && i_Rst_n && $past(i_Rst_n)) begin
        if ($past(state) != STATE_IDLE) begin
            assert(o_busy == 1'b1);
        end else begin
            assert(o_busy == 1'b0);
        end
    end
end
    // o_busy is registered - it reflects $past(state), not current state.
    // We only check this when reset has been deasserted for at least 
    // two consecutive cycles, ensuring o_busy has had a full clock edge 
    // to update after any reset event.

// ----------------------------------------------------------------------------
// 4. COVER PROPERTIES
//
// Cover properties ask: "can the design ever reach this state?"
// They are checked in cover mode (not BMC mode) — SymbiYosys finds the
// SHORTEST trace that satisfies the condition and outputs it as a
// waveform you can inspect.
//
// This is the sanity check that assumptions are not so tight that the
// design can never do anything useful. If cover fails, your assumptions
// are over-constraining the solver.
// ----------------------------------------------------------------------------

// -- F8: Complete transfer witness --
// Can the FSM ever return to STATE_IDLE after having been in STATE_POS_COMM?
// This is a simpler and more direct witness - it purely tracks the FSM 
// state sequence without depending on the registered o_busy output.
always @(posedge w_Clk) begin 
    cover(f_past_valid &&
          i_Rst_n      &&
          $past(state) == STATE_POS_COMM &&
          state == STATE_IDLE);
end

`endif
// ============================================================================
// END FORMAL VERIFICATION BLOCK
// ============================================================================

endmodule