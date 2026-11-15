//------------------------------------------------------------------------------
// The four paddle timers of atari2600_pocket.sv with one shared engine
//
// Four of MiSTer's paddle_timer (mister/rtl/paddles.sv, Jamie Blanks, MIT),
// clock for clock: each `charged` output and every register that affects it
// follow paddle_timer's on every clock. What is shared and what is not:
//
//   shared   the dump-line counter (clear_count: the dump line is common, so
//            the four copies were always equal), here as a tick count; and
//            the calibration engine: the reads' compares and subtract (the
//            new lowest / highest, the width), which serve the one paddle
//            being read. The TIA reads one INPT register per clock, so
//            `read` has at most one bit set: the engine never has two
//            paddles to serve.
//   per      the charge counter and its compare with `difference` (every
//   paddle   paddle can cross its threshold on any clock), `difference`
//            itself (lowest + the width's slope x the position, every clock:
//            the position changes on its own clocks), and the calibration
//            registers the engine writes.
//
// Two of paddle_timer's values are stored in another form:
//   - width as m = (width + 2 x NS_PER_TICK) >> 8, the only form
//     `difference` reads;
//   - lowest > highest as the flag lgh, written when lowest or highest is.
// paddle_timer updates width one clock after lowest / highest change, and
// again on every later clock while lowest < highest (no change then). Here
// the engine computes the new width with the new lowest / highest and keeps
// it in pv; the paddle's flag pend marks it as not yet applied, and it is
// applied on the first clock paddle_timer would apply it (dump line low,
// paddle cleared). At most one paddle has pend set: a pending width is
// applied on the first clock with the dump line low, which comes no later
// than the next read the engine serves.
//
// Power-up values are paddle_timer's (its registers without an initializer
// power up 0 in Quartus, as in Verilator), so the two agree from the first
// clock. sim/tb_paddles4.sv compares them on every clock.
//
// SPDX-License-Identifier: MIT
//------------------------------------------------------------------------------

`default_nettype none

module paddle_timer4 (
	input  wire        clk,
	input  wire        ce,
	input  wire  [3:0] reset,      // per paddle (paddle_timer's reset)
	input  wire [31:0] kohms,      // paddle p's position in [8p+7:8p] (paddle_timer's kohms[7:0])
	input  wire        clear,      // the dump line, common to the four
	input  wire  [3:0] read,       // the TIA reads INPTp: at most one bit set
	output wire  [3:0] charged
);
	// paddle_timer's constants (its NS_PER_TICK, CLEAR_NS, the unmeasured
	// threshold), in its units: nanoseconds x 100.
	localparam [32:0] NS_PER_TICK = 33'd6984;
	localparam  [8:0] CLEAR_TICKS = 9'd480;        // CLEAR_NS 3,352,320 = 480 x NS_PER_TICK
	localparam [33:0] UNMEASURED  = 34'h114B6C376;
	localparam [25:0] M_WIDTH0    = 26'd54;        // m of width 0: (0 + 13,968) >> 8

	// ---- shared: the dump line ----
	/* verilator lint_off PROCASSINIT */  // power-up values (DEVELOPING.md, "Power-up values")
	reg  [8:0] cc = 9'd0;                // clear_count / NS_PER_TICK (0..480)
	reg        old_clear = 1'b0;         // paddle_timer's old_read
	reg [25:0] pv = 26'd0;               // the pending width, as m
	/* verilator lint_on PROCASSINIT */
	wire dump_done = (cc >= CLEAR_TICKS); // clear_count >= CLEAR_NS
	wire clear_rise = clear && !old_clear;

	always @(posedge clk) if (ce) begin
		old_clear <= clear;
		if (clear) begin
			if (!dump_done)
				cc <= cc + 9'd1;
		end else
			cc <= 9'd0;
	end

	// ---- per paddle state, read by the engine through sel ----
	wire [32:0] p_high    [0:3];
	wire [32:0] p_lowest  [0:3];
	wire [32:0] p_highest [0:3];
	wire        p_cleared [0:3];

	// ---- the shared calibration engine: the paddle being read ----
	wire        e_act = |read;
	wire  [1:0] sel   = {read[3] | read[2], read[3] | read[1]};
	wire [32:0] e_h   = p_high[sel];
	wire [32:0] e_lo  = p_lowest[sel];
	wire [32:0] e_hi  = p_highest[sel];
	wire [33:0] e_d   = {1'b0, e_h} - {1'b0, e_lo};     // bit 33: high_count < lowest
	wire        e_go  = ce && e_act && !clear && p_cleared[sel];
	wire        ev_low  = e_go && e_d[33];                // a new lowest (highest and read_count to 0)
	wire        ev_high = e_go && !e_d[33] && (e_hi < e_h); // a new highest
	wire        e_lt  = (e_d[32:0] != 33'd0);             // lowest < the new highest
	wire [33:0] e_w   = {1'b0, e_d[32:0]} + {NS_PER_TICK, 1'b0};
	always @(posedge clk)
		if (ev_high)
			pv <= e_w[33:8];

	genvar p;
	generate
	for (p = 0; p < 4; p = p + 1) begin : pd
		/* verilator lint_off PROCASSINIT */
		reg [32:0] high_count = 33'd0;
		reg [32:0] lowest     = 33'd0;
		reg [32:0] highest    = 33'd0;
		reg [33:0] difference = 34'd0;
		reg [25:0] m          = M_WIDTH0;
		reg  [1:0] read_count = 2'd0;
		reg        chg        = 1'b0;
		reg        cleared    = 1'b0;
		reg        lgh        = 1'b0;    // lowest > highest
		reg        pend       = 1'b0;    // pv is this paddle's width, not yet applied
		/* verilator lint_on PROCASSINIT */

		wire        read_measured = &read_count;
		wire  [7:0] k      = kohms[8*p +: 8];
		wire [33:0] slope  = m * k;
		wire [33:0] next_d = (lgh | ~read_measured) ? UNMEASURED : {1'b0, lowest} + slope;
		wire        mine   = (sel == p);

		always @(posedge clk) if (ce) begin
			if (~read_measured && clear_rise)
				read_count <= read_count + 2'd1;

			if (clear) begin
				if (dump_done) begin
					cleared    <= 1'b1;
					high_count <= 33'd0;
					chg        <= 1'b0;
				end
			end else begin
				if ({1'b0, high_count} < difference)
					high_count <= high_count + NS_PER_TICK;
				else
					chg <= 1'b1;

				if (cleared && pend) begin
					m    <= pv;
					pend <= 1'b0;
				end
				if (ev_high && mine) begin
					highest <= high_count;
					lgh     <= 1'b0;
					pend    <= e_lt;
				end
				if (ev_low && mine) begin
					lowest     <= high_count;
					highest    <= 33'd0;
					read_count <= 2'd0;
					lgh        <= (high_count != 33'd0);
					pend       <= 1'b0;
				end
				difference <= next_d;
			end

			if (reset[p]) begin
				cleared    <= 1'b0;
				m          <= M_WIDTH0;
				read_count <= 2'd0;
				lowest     <= {33{1'b1}};
				highest    <= 33'd0;
				difference <= 34'd0;
				lgh        <= 1'b1;
				pend       <= 1'b0;
			end
		end

		assign p_high[p]    = high_count;
		assign p_lowest[p]  = lowest;
		assign p_highest[p] = highest;
		assign p_cleared[p] = cleared;
		assign charged[p]   = chg;
	end
	endgenerate

endmodule
