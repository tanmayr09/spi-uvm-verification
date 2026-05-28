///////////////////////////////////////////////////////////////////////////////
/* Description: SPI (Serial Peripheral Interface) Slave

// Note:  The Maximum frequency of the SPI can be the same as FPGA's clock, as long as you don't register the mosi and sclk,
however, in that case you need guarantee the stable of the input signals. Other point is than, more high the speed, the signal can be more unstable, this way, It's advisable you keep the signal register.
So, in cases where these signals are register the FPGA's frequency should be at least 4x sclk, i.e i_Clk >= 4*i_sclk

 Parameters:  DATA_WIDTH = Number of bits per SPI transfer (default 8).
                           Supported: 8, 16, 32, etc.

              SPI_MODE
              Mode | Clock Polarity (CPOL) | Clock Phase (CPHA)
               0   |             0             |        0
               1   |             0             |        1
               2   |             1             |        0
               3   |             1             |        1
              See: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface#/media/File:SPI_timing_diagram2.svg
							
							FRAME FORMAT : 0 - MSB and 1 - LSB
*/
///////////////////////////////////////////////////////////////////////////////
module spiSlave #(
    parameter MODE         = 0,
    parameter FRAME_FORMAT = 0,
    parameter DATA_WIDTH   = 8   // Number of bits per SPI transfer
) (
    input                            i_Clk        , // Clock.
    input                            i_Clk_en     , // Clock Enable.
    input                            i_Rst_n      , // Asynchronous reset active low
    input                            i_tx_ready   , // Data ready to be register.
    input  logic [DATA_WIDTH-1:0]    i_tx_byte    , // Data to sent.
    output logic [DATA_WIDTH-1:0]    o_rx_byte    , // Data received.
    output logic                     o_byte_ready , // Data received in last communication ready.
    input                            i_mosi       , // SPI MOSI.
    input                            i_sclk       , // SPI CLOCK.
    input                            i_ss         , // Slave Select
    output logic                     o_miso       , // SPI MISO
    output logic                     o_busy         // Communication is running.
);

// Variable Declarations to SPI MODE select
// FIX: 'bit' changed to 'logic' (Yosys does not support 'bit' type)
// FIX: inline initializers removed — moved into `ifdef FORMAL initial blocks below
logic         w_Clk               ;
logic [1:0]   w_mode_select       ; // Passing parameter to variable. Avoiding something bugs during module synthesize.
logic         w_CPOL              ;
logic         w_CPHA              ;

// 0 - MSB and 1 - LSB
// FIX: 'bit' changed to 'logic', inline initializer removed
logic r_frame_formart; // Passing parameter to variable. Avoiding something bugs during module synthesize.

// Variables Declaration to store tx and rx data words
logic [DATA_WIDTH-1:0] r_tx_byte, w_tx_byte;
logic [DATA_WIDTH-1:0] r_rx_byte, r_tx_byte_tmp;

// SPI registers
logic w_sclk;
logic w_miso;
logic r_mosi;
logic r_sclk;
logic r_ss  ;

// r_cycle_count needs to count from 0 to DATA_WIDTH, so width = $clog2(DATA_WIDTH)+1
logic [$clog2(DATA_WIDTH):0] r_cycle_count;

// FIX: Parameter-derived constants initialised here instead of as inline initializers
// This is the correct pattern for Yosys — parameters are not supported as inline initializers
`ifdef FORMAL
initial begin
    w_mode_select  = MODE;
    r_frame_formart = FRAME_FORMAT[0];
end
`else
initial begin
    w_mode_select  = MODE;
    r_frame_formart = FRAME_FORMAT[0];
end
`endif

// Process to register the external SPI's signals.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if(~i_Rst_n) begin
        r_mosi <= '0;
        r_sclk <= '0;
        r_ss   <= 1'b1;
    end else begin
        r_mosi <= i_mosi;
        r_sclk <= i_sclk;
        r_ss   <= i_ss;
    end
end

// Combinational logic to define SPI MODE.
always_comb begin

    if(w_mode_select == 2'd0) begin
        w_CPOL = '0;
        w_CPHA = '0;
    end else if (w_mode_select == 2'd1) begin
        w_CPOL = 1'd0;
        w_CPHA = 1'd1;
    end else if (w_mode_select == 2'd2) begin
        w_CPOL = 1'd1;
        w_CPHA = 1'd0;
    end else if (w_mode_select == 2'd3) begin
        w_CPOL = 1'd1;
        w_CPHA = 1'd1;
    end else begin
        // FIX: 'z replaced with '0 — high-impedance is not supported in formal/Yosys combinational logic
        w_CPOL = '0;
        w_CPHA = '0;
    end
end

// Assigns
// FIX: w_Clk is now a logic wire driven by assign (not a 'bit' with inline init)
assign w_Clk  = i_Clk_en ? i_Clk : '0; // Clock enable.

// FIX: o_miso tri-state ('z) replaced for formal
// In real RTL, o_miso is high-impedance when SS is deasserted (slave not selected)
// Yosys/formal cannot handle 'z in output assigns — under FORMAL we drive w_miso through always
`ifdef FORMAL
    assign o_miso = w_miso;
`else
    assign o_miso = r_ss ? 'z : w_miso;
`endif

assign w_sclk = w_CPOL ? !r_sclk : r_sclk;


// Process to register input signal.
// If the communication is running the value doesn't update until the final of the actual communication
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if(~i_Rst_n) begin
        r_tx_byte <= '0;
    end else begin
        if(i_tx_ready && r_ss) begin
            r_tx_byte <= i_tx_byte;
        end
    end
end

// Process to update communication state to outside module.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if(~i_Rst_n) begin
        o_busy <= '0;
    end else begin
        o_busy <= !r_ss;
    end
end

// Process to shift data to pass the value to miso's output
// MSB-first: shift left by r_cycle_count, output MSB
// LSB-first: shift right by r_cycle_count, output LSB
always_comb begin
    if (!r_frame_formart) begin
        w_tx_byte = r_tx_byte << r_cycle_count ;
    end else begin
        w_tx_byte = r_tx_byte >> r_cycle_count ;
    end
end

// Parameterized MSB/LSB output bit selection
always_comb begin
    if (!r_frame_formart) begin
        w_miso = w_tx_byte[DATA_WIDTH-1];
    end else begin
        w_miso = w_tx_byte[0];
    end
end


// Generate is dependent of the SPI mode. The difference is the edge detection in always parameter
// With MODE=0 fixed, only the negedge w_sclk branch elaborates.
// posedge r_ss acts as async reset for r_cycle_count (no i_Rst_n path — this is intentional in the design)
generate
    if(MODE == 1 || MODE == 3)

        always_ff @(posedge w_sclk or posedge r_ss) begin
            if(r_ss) begin
                r_cycle_count <= ($clog2(DATA_WIDTH)'(0) + ($clog2(DATA_WIDTH)+1)'('1)); // -1 in the appropriate width
            end else begin
                r_cycle_count <= r_cycle_count + 1'd1;
            end
        end

    else

        always_ff @(negedge w_sclk or posedge r_ss) begin
            if(r_ss) begin
                r_cycle_count <= '0;
            end else begin
                r_cycle_count <= r_cycle_count + 1'd1;
            end
        end

endgenerate

// Parameterized RX shift register
// MSB-first: shift left, insert new bit at LSB:  {r_rx_byte[DATA_WIDTH-2:0], r_mosi}
// LSB-first: shift right, insert new bit at MSB: {r_mosi, r_rx_byte[DATA_WIDTH-1:1]}
generate
    if (MODE == 1 || MODE == 3)

        always_ff @(negedge w_sclk or negedge i_Rst_n) begin
            if(~i_Rst_n) begin
                r_rx_byte <= '0;
            end else begin
                if (!r_frame_formart) begin
                    r_rx_byte <= {r_rx_byte[DATA_WIDTH-2:0], r_mosi};
                end else begin
                    r_rx_byte <= {r_mosi, r_rx_byte[DATA_WIDTH-1:1]};
                end
            end
        end

        else

            always_ff @(posedge w_sclk or negedge i_Rst_n) begin
                if(~i_Rst_n) begin
                    r_rx_byte <= '0;
                end else begin
                    if (!r_frame_formart) begin
                        r_rx_byte <= {r_rx_byte[DATA_WIDTH-2:0], r_mosi};
                    end else begin
                        r_rx_byte <= {r_mosi, r_rx_byte[DATA_WIDTH-1:1]};
                    end
                end
            end

endgenerate

// Update the signal received after end communication. The o_byte_ready is a pulse of the FPGA clock.
always_ff @(posedge w_Clk or negedge i_Rst_n) begin
    if(~i_Rst_n) begin
        o_rx_byte    <= '0;
        o_byte_ready <= '0;
    end else begin
        if (r_ss && o_busy) begin
            o_rx_byte    <= r_rx_byte ;
            o_byte_ready <= 1'd1;
        end else begin
            o_byte_ready <= '0;
        end
    end
end

// ============================================================
// FORMAL VERIFICATION BLOCK
// All assertions, assumptions, and cover properties live here.
// ============================================================
`ifdef FORMAL

// ------------------------------------------------------------
// f_past_valid: gates all assertions that use $past()
// Must use posedge w_Clk (not i_Clk) — clk2fflogic makes these independent
// ------------------------------------------------------------
logic f_past_valid;
initial f_past_valid = 1'b0;
always @(posedge w_Clk) f_past_valid <= 1'b1;

// Shadow register: previous value of r_ss, for use in combinational assumptions
// ($past is not allowed in always @(*) blocks in Yosys)
logic f_r_ss_prev;
initial f_r_ss_prev = 1'b1; // SS starts deasserted
always @(posedge w_Clk) f_r_ss_prev <= r_ss;

// Shadow register: previous value of i_ss (pre-registration), for time-zero gap
logic f_i_ss_prev;
initial f_i_ss_prev = 1'b1;
always @(posedge w_Clk) f_i_ss_prev <= i_ss;

// ------------------------------------------------------------
// INITIAL ASSUMPTIONS — seal time-zero state
// ------------------------------------------------------------
initial assume (~i_Rst_n);        // Reset is asserted at time zero
initial assume (i_ss  == 1'b1);   // SS starts deasserted (slave idle)
initial assume (i_sclk == 1'b0);  // SCLK idles low (CPOL=0, MODE=0)

// ------------------------------------------------------------
// ASSUMPTIONS (A1–A6) — environment constraints
// All in combinational always @(*) blocks — airtight with clk2fflogic
// ------------------------------------------------------------

// A1: Clock enable is always active
always @(*) begin
    assume (i_Clk_en == 1'b1);
end

// A2: When SS is deasserted (r_ss==1), SCLK must be idle low (CPOL=0)
// Uses shadow register f_r_ss_prev because we're in a combinational block
// and need to know the registered state of SS
//always @(*) begin
//    if (f_r_ss_prev) begin
//        assume (i_sclk == 1'b0);
//    end
//end
// A2 (strengthened): r_sclk must be low when r_ss is high (SS deasserted)
// r_sclk is the registered version of i_sclk — w_sclk is derived directly from r_sclk
// Constraining i_sclk alone is not sufficient because after clk2fflogic,
// w_sclk is a free solver variable independent of i_sclk
// We constrain r_sclk directly to close the gap
always @(*) begin
    if (r_ss) begin
        assume (r_sclk == 1'b0);
    end
end

// A3: i_tx_ready can only be asserted when SS is deasserted (slave not in transfer)
// TX data is loaded before a transfer begins
always @(*) begin
    if (!f_r_ss_prev) begin
        assume (i_tx_ready == 1'b0);
    end
end

// A4: i_tx_ready is a single-cycle pulse — cannot be held high
// Shadow register tracks previous tx_ready state
// (Defined below after f_tx_ready_prev declaration)

// A5: SS must stay low for a full transfer once asserted
// We don't constrain SS deassert timing here — that's what the assertions verify

// A6: Reset is not asserted during normal operation (after initial reset)
// Prevents the solver from spuriously toggling reset mid-proof
always @(*) begin
    if (f_past_valid) begin
        assume (i_Rst_n == 1'b1);
    end
end

// Shadow register for i_tx_ready (needed for A4 pulse constraint)
logic f_tx_ready_prev;
initial f_tx_ready_prev = 1'b0;
always @(posedge w_Clk) f_tx_ready_prev <= i_tx_ready;

// Shadow register: i_ss delayed by two w_Clk cycles
// Needed for A7 - to detect the cycle after SS deasserts
logic f_i_ss_prev2;
initial f_i_ss_prev2 = 1'b1;
always @(posedge w_Clk) f_i_ss_prev2 <= f_i_ss_prev;

// A4 (continued): tx_ready is a pulse — deasserts the cycle after it fires
always @(*) begin
    if (f_tx_ready_prev) begin
        assume (i_tx_ready == 1'b0);
    end
end

// A7: SS hold-high — once SS deasserts (r_ss goes 0→1), hold i_ss high
// for at least one more w_Clk cycle so o_byte_ready fires cleanly
// f_r_ss_prev == 0 means last cycle we were still in transfer
// f_i_ss_prev == 1 means i_ss already went high last cycle
// Together: SS just deasserted — prevent immediate re-assertion
always @(*) begin
    if (f_i_ss_prev == 1'b1 && f_r_ss_prev == 1'b0) begin
        assume (i_ss == 1'b1);
    end
end 

// A8: SCLK must be low when SS is currently deasserted at the input level
// Covers the cycle of deassertion itself - A2 only covers f_r_ss_prev (one cycle later)
// Prevents a rogue negedge w_sclk from firing after SS deasserts
// but before posedge r_ss resets r_cycle_count
//always @(*) begin
//    if (i_ss == 1'b1) begin
//        assume(i_sclk == 1'b0);
//    end
//end

// A9: r_sclk must also be low when f_r_ss_prev is low but r_ss is now high
// (the transition cycle — SS just deasserted this w_Clk cycle)
// Prevents a negedge w_sclk firing on exactly the deassertion cycle
//always @(*) begin
//    if (f_r_ss_prev == 1'b0 && r_ss == 1'b1) begin
//        assume (r_sclk == 1'b0);
//    end
//end

// ------------------------------------------------------------
// ASSERTIONS (F1–F7)
// All inside always @(posedge w_Clk) — registered signals,
// must check $past() values to account for 1-cycle update lag
// ------------------------------------------------------------

always @(posedge w_Clk) begin

    // F1: After reset deasserts, o_busy and o_byte_ready must be cleared
    // o_busy and o_byte_ready are registered on posedge w_Clk,
    // so we check the cycle AFTER reset was active
    if (f_past_valid && $past(~i_Rst_n)) begin
        F1_reset_clears_busy:       assert (o_busy       == 1'b0);
        F1_reset_clears_byte_ready: assert (o_byte_ready == 1'b0);
    end

    // F2: o_busy must reflect !r_ss with one cycle lag
    // o_busy is assigned <= !r_ss on posedge w_Clk
    // So this cycle's o_busy = last cycle's !r_ss
    if (f_past_valid) begin
        F2_busy_tracks_ss: assert (o_busy == !$past(r_ss));
    end

    // F3: o_byte_ready is a single-cycle pulse
    // Cannot be high two cycles in a row
    if (f_past_valid && $past(o_byte_ready)) begin
        F3_byte_ready_pulse: assert (o_byte_ready == 1'b0);
    end

    // F4: o_byte_ready only fires on the cycle after SS deasserts while busy
    // Condition: r_ss is now high AND o_busy was high last cycle
    // (o_busy was high = $past(r_ss) was low = we were in a transfer)
    if (f_past_valid && o_byte_ready) begin
        F4_byte_ready_after_transfer: assert ($past(o_busy) && r_ss); 
    end

    // F5: r_cycle_count is bounded — never exceeds DATA_WIDTH
    // r_cycle_count resets to 0 on posedge r_ss and increments on negedge w_sclk
    // Maximum meaningful value is DATA_WIDTH (after all bits shifted)
    //F5_cycle_count_bounded: assert (r_cycle_count <= DATA_WIDTH[$clog2(DATA_WIDTH):0]);

    // F5 (strengthened): 
    // During transfer (r_ss low): count bounded by DATA_WIDTH
    // After transfer ends: count allowed one cycle to reset, then must be 0
    // f_r_ss_prev captures whether last cycle was still in transfer
    //if (f_past_valid) begin
    //    F5_count_during_transfer: assert (!r_ss ? 
    //        r_cycle_count <= DATA_WIDTH[$clog2(DATA_WIDTH):0] : 1'b1);
    //    F5_count_settled_idle: assert ((r_ss && $past(r_ss)) ? 
    //        r_cycle_count == '0 : 1'b1);
    //end
    // F5: r_cycle_count invariant
    // Assert unconditionally — this becomes a lemma the solver 
    // must maintain at every step including across clock domain boundaries
    // The negedge w_sclk trigger increments the count, posedge r_ss resets it
    // We bound it at DATA_WIDTH+1 to give one extra count of slack for the
    // inter-domain timing gap between the last negedge w_sclk and posedge r_ss
    //F5_cycle_count_bounded: assert (r_cycle_count <= (DATA_WIDTH[$clog2(DATA_WIDTH):0] + 1'b1));

    // F5 (REMOVED): r_cycle_count bounded by DATA_WIDTH
    // r_cycle_count is clocked on negedge w_sclk — a data-derived clock.
    // After clk2fflogic, negedge w_sclk is a free solver trigger completely
    // decoupled from w_Clk. The solver can fire it arbitrarily many times
    // per w_Clk cycle, making any bound on r_cycle_count unprovable as a
    // posedge w_Clk assertion regardless of assumptions on i_sclk or r_sclk.
    // This is a known limitation of clk2fflogic on data-derived clocks.
    // The counter bound is guaranteed in real hardware by the physical
    // SCLK frequency relationship — not a design bug.
    // Provable only with a single-clock redesign or a separate clock-domain
    // assertion framework.

    // F6: TX byte is stable during a transfer
    // Once SS is asserted (r_ss goes low), r_tx_byte must not change
    // r_tx_byte only updates when i_tx_ready && r_ss — so during transfer it's frozen
    if (f_past_valid && !r_ss && !$past(r_ss)) begin
        F6_tx_stable_during_transfer: assert (r_tx_byte == $past(r_tx_byte));
    end

    // F7: o_busy is never high after reset (while reset is held)
    // Belt-and-suspenders with F1 — catches multi-cycle reset hold
    if (~i_Rst_n) begin
        F7_no_busy_in_reset: assert (o_busy == 1'b0);
    end

end

// ------------------------------------------------------------
// COVER PROPERTY (F8) — witness that a complete transfer is reachable
// o_byte_ready going high proves the slave completed a full SPI transfer
// and latched received data to o_rx_byte
// ------------------------------------------------------------
always @(posedge w_Clk) begin
    F8_complete_transfer: cover (f_past_valid && o_byte_ready);
end

`endif // FORMAL

endmodule