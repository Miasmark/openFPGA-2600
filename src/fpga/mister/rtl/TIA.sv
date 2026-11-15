// k7800 (c) by Jamie Blanks
//
// Copyright (c) 2021-2026 Jamie Blanks
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Based on Stella Programmer's Guide, TIA Schematics, and Decapped TIA.

// This design is not the most efficient in the world. There's combinational loops, and there's
// places that seem like they could use clock enables rather continuous logic. The reason I
// ultimately did it this way is because there is frankly tons of analog delays and asynchronous
// clocking that make the outcome of various scenarios fairly unpredictable, and almost
// all of these edge cases seem to come up in one game or another. Thus, I erred on the side
// of accuracy at the price of efficiency.

typedef enum bit [5:0] {
	VSYNC   = 6'h00,  // Write: vertical sync set-clear (D1)
	VBLANK  = 6'h01,  // Write: vertical blank set-clear (D7-6,D1)
	WSYNC   = 6'h02,  // Write: wait for leading edge of hrz. blank (strobe)
	RSYNC   = 6'h03,  // Write: reset hrz. sync counter (strobe)
	NUSIZ0  = 6'h04,  // Write: number-size player-missle 0 (D5-0)
	NUSIZ1  = 6'h05,  // Write: number-size player-missle 1 (D5-0)
	COLUP0  = 6'h06,  // Write: color-lum player 0 (D7-1)
	COLUP1  = 6'h07,  // Write: color-lum player 1 (D7-1)
	COLUPF  = 6'h08,  // Write: color-lum playfield (D7-1)
	COLUBK  = 6'h09,  // Write: color-lum background (D7-1)
	CTRLPF  = 6'h0a,  // Write: cntrl playfield ballsize & coll. (D5-4,D2-0)
	REFP0   = 6'h0b,  // Write: reflect player 0 (D3)
	REFP1   = 6'h0c,  // Write: reflect player 1 (D3)
	PF0     = 6'h0d,  // Write: playfield register byte 0 (D7-4)
	PF1     = 6'h0e,  // Write: playfield register byte 1 (D7-0)
	PF2     = 6'h0f,  // Write: playfield register byte 2 (D7-0)
	RESP0   = 6'h10,  // Write: reset player 0 (strobe)
	RESP1   = 6'h11,  // Write: reset player 1 (strobe)
	RESM0   = 6'h12,  // Write: reset missle 0 (strobe)
	RESM1   = 6'h13,  // Write: reset missle 1 (strobe)
	RESBL   = 6'h14,  // Write: reset ball (strobe)
	AUDC0   = 6'h15,  // Write: audio control 0 (D3-0)
	AUDC1   = 6'h16,  // Write: audio control 1 (D4-0)
	AUDF0   = 6'h17,  // Write: audio frequency 0 (D4-0)
	AUDF1   = 6'h18,  // Write: audio frequency 1 (D3-0)
	AUDV0   = 6'h19,  // Write: audio volume 0 (D3-0)
	AUDV1   = 6'h1a,  // Write: audio volume 1 (D3-0)
	GRP0    = 6'h1b,  // Write: graphics player 0 (D7-0)
	GRP1    = 6'h1c,  // Write: graphics player 1 (D7-0)
	ENAM0   = 6'h1d,  // Write: graphics (enable) missle 0 (D1)
	ENAM1   = 6'h1e,  // Write: graphics (enable) missle 1 (D1)
	ENABL   = 6'h1f,  // Write: graphics (enable) ball (D1)
	HMP0    = 6'h20,  // Write: horizontal motion player 0 (D7-4)
	HMP1    = 6'h21,  // Write: horizontal motion player 1 (D7-4)
	HMM0    = 6'h22,  // Write: horizontal motion missle 0 (D7-4)
	HMM1    = 6'h23,  // Write: horizontal motion missle 1 (D7-4)
	HMBL    = 6'h24,  // Write: horizontal motion ball (D7-4)
	VDELP0  = 6'h25,  // Write: vertical delay player 0 (D0)
	VDELP1  = 6'h26,  // Write: vertical delay player 1 (D0)
	VDELBL  = 6'h27,  // Write: vertical delay ball (D0)
	RESMP0  = 6'h28,  // Write: reset missle 0 to player 0 (D1)
	RESMP1  = 6'h29,  // Write: reset missle 1 to player 1 (D1)
	HMOVE   = 6'h2a,  // Write: apply horizontal motion (strobe)
	HMCLR   = 6'h2b,  // Write: clear horizontal motion registers (strobe)
	CXCLR   = 6'h2c,  // Write: clear collision latches (strobe)
	ENBLO   = 6'h3D,  // Not a real register, used for ENABL OLD
	GRP0O   = 6'h3E,  // Not a real register, used for GRP0 storage
	GRP1O   = 6'h3F   // Not a real register, used for GRP1 storage
} write_registers;

typedef enum bit [3:0] {
	CXM0P   = 4'h0,  // Read collision: D7=(M0,P1); D6=(M0,P0)
	CXM1P   = 4'h1,  // Read collision: D7=(M1,P0); D6=(M1,P1)
	CXP0FB  = 4'h2,  // Read collision: D7=(P0,PF); D6=(P0,BL)
	CXP1FB  = 4'h3,  // Read collision: D7=(P1,PF); D6=(P1,BL)
	CXM0FB  = 4'h4,  // Read collision: D7=(M0,PF); D6=(M0,BL)
	CXM1FB  = 4'h5,  // Read collision: D7=(M1,PF); D6=(M1,BL)
	CXBLPF  = 4'h6,  // Read collision: D7=(BL,PF); D6=(unused)
	CXPPMM  = 4'h7,  // Read collision: D7=(P0,P1); D6=(M0,M1)
	INPT0   = 4'h8,  // Read pot port: D7
	INPT1   = 4'h9,  // Read pot port: D7
	INPT2   = 4'ha,  // Read pot port: D7
	INPT3   = 4'hb,  // Read pot port: D7
	INPT4   = 4'hc,  // Read P1 joystick trigger: D7
	INPT5   = 4'hd   // Read P2 joystick trigger: D7
} read_registers;

typedef struct packed {
	logic edge_p1;  // Clock falling edge for all clocks
	logic edge_p2;  // Clock rising edge for all clocks
	logic level_p1; // Phase 1 for ripple counters
	logic level_p2; // Phase 2 for ripple counters
	logic clock;    // Clock for symmetric clocks
} clock_t;

/////////////////////////////////////////////////////////////////////////////////////////

module lfsr_6
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input clk,
	input phi1,
	input phi2,
	input reset,
	input sys_reset,
	output logic [5:0] lfsr
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;

	reg [5:0] lfsr_latch1, lfsr_next;

	assign lfsr = reset ? 6'd0 : (phi2 ? lfsr_next : lfsr_latch1);

	always @(posedge clk) begin
		if (ss_en) {lfsr_next[5], lfsr_next[4], lfsr_next[3], lfsr_next[2], lfsr_next[1], lfsr_next[0], lfsr_latch1[5], lfsr_latch1[4], lfsr_latch1[3], lfsr_latch1[2], lfsr_latch1[1], lfsr_latch1[0]} <= {ss_c0, lfsr_next[5], lfsr_next[4], lfsr_next[3], lfsr_next[2], lfsr_next[1], lfsr_next[0], lfsr_latch1[5], lfsr_latch1[4], lfsr_latch1[3], lfsr_latch1[2], lfsr_latch1[1], lfsr_latch1[0]} >> 1;
		else if (!ss_frz) begin

		if (phi1)
			lfsr_next <= {~((lfsr_latch1[1] && ~lfsr_latch1[0]) || ~(lfsr_latch1[1] || ~lfsr_latch1[0])), lfsr_latch1[5:1]};

		if (phi2)
			lfsr_latch1 <= lfsr;

		if (reset || sys_reset) begin
			lfsr_latch1 <= 0;
		end
	end
	end
	assign ss_c1 = {lfsr_next[5], lfsr_next[4], lfsr_next[3], lfsr_next[2], lfsr_next[1], lfsr_next[0], lfsr_latch1[5], lfsr_latch1[4], lfsr_latch1[3], lfsr_latch1[2], lfsr_latch1[1], lfsr_latch1[0]};

endmodule

module lfsr_6_instant
(
	input logic ss_en, input logic ss_frz,
	input clk,
	input phi1,
	input phi2,
	input reset,
	input sys_reset,
	output logic [5:0] lfsr
);
	reg [5:0] lfsr_latch1;

	wire [5:0] lfsr_next = reset ? 6'd0 : {~((lfsr[1] && ~lfsr[0]) || ~(lfsr[1] || ~lfsr[0])), lfsr[5:1]};
	always @(posedge clk)
		if (!(ss_en || ss_frz))  // ss hold
 begin
		if (phi1) begin
			lfsr_latch1 <= lfsr_next;
		end

		if (phi2)
			lfsr <= lfsr_latch1;

		if (sys_reset) begin
			lfsr_latch1 <= 0;
			lfsr <= 0;
		end
	end

endmodule

module sr_latch
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input clk,
	input reset,
	input r,
	input s,
	output logic q,
	output logic q_n
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;


	wire i_val = r ? 1'd0 : (s ? 1'd1 : sr_val);
	logic sr_val, sr_val_n;
	assign q_n = (r & s) ? 1'd0 : ~q;
	assign q = i_val;

	always @(posedge clk) begin
		if (ss_en) {sr_val} <= {ss_c0, sr_val} >> 1;
		else if (!ss_frz) begin
		sr_val <= i_val;
		if (reset)
			sr_val <= 1'd0;
	end
	end
	assign ss_c1 = {sr_val};

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
// The die's F cell is two cross coupled latch stages gated by opposite halves
// of tick. Both stages are transparent only while their own half is high, so
// the pair collapses to two registers with no path from r_n/s_n to q:
//
//   tick low   master follows s_n / r_n     q = slave
//   tick high  master holds                 q = ~master, slave <= ~master
//
// This is the same cycle for cycle behaviour the two sr_latch instances gave,
// written so a cross coupled pair of cells is no longer a combinational loop
// for Verilator and TimeQuest.
module f_cell
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input  logic   clk,
	input  logic   reset,
	input  logic   tick,
	input  logic   r_n,
	input  logic   s_n,
	output logic   q_n,
	output logic   q
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;

	logic master, slave;

	assign q   = reset ? 1'd0 : (tick ? ~master : slave);
	assign q_n = ~q;

	always @(posedge clk) begin
		if (ss_en) {slave, master} <= {ss_c0, slave, master} >> 1;
		else if (!ss_frz) begin
		if (tick)
			slave  <= ~master;
		else
			master <= ~s_n ? 1'd0 : (~r_n ? 1'd1 : master);

		if (reset) begin
			master <= 1'd0;
			slave  <= 1'd0;
		end
	end
	end
	assign ss_c1 = {slave, master};

endmodule

module f_counter_ll
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input  logic   clk,
	input  logic   reset,
	input  logic   sys_reset,
	input  logic   tick,
	output clock_t clock,
	output logic   f1_qn,
	output logic   f1_q_l
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c3;


	logic q_left, q_left_n, q_right, q_right_n;
	logic f1_q_l_l;

	assign clock.clock = 0; // Edges and clock are unused for the ripple counter low level
	assign clock.edge_p1 = 0;
	assign clock.edge_p2 = 0;
	assign clock.level_p1 = ~(q_left || q_right);
	assign clock.level_p2 = ~(q_left_n || q_right_n);
	assign f1_qn = q_right_n;

	f_cell f_left
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk        (clk),
		.reset      (reset || sys_reset),
		.tick       (tick),
		.s_n        (q_right),
		.r_n        (q_right_n),
		.q          (q_left),
		.q_n        (q_left_n)
	);

	f_cell f_right
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk        (clk),
		.reset      (reset || sys_reset),
		.tick       (tick),
		.s_n        (q_left_n),
		.r_n        (q_left),
		.q          (q_right),
		.q_n        (q_right_n)
	);

	sr_latch q_1l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c2), .ss_so(ss_c3),
		.clk        (clk),
		.reset      (sys_reset),
		.r          (~q_right_n),
		.s          (reset),
		.q          (f1_q_l),
		.q_n        ()
	);
endmodule

module d_cell
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input  logic   clk,
	input  logic   reset,
	input  logic   phi1,
	input  logic   phi2,
	input  logic   in,
	output logic   out
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;

	logic out_next, out_latch;

	assign out = reset ? 1'd0 : (phi2 ? out_next : out_latch);

	always @(posedge clk) begin
		if (ss_en) {out_next, out_latch} <= {ss_c0, out_next, out_latch} >> 1;
		else if (!ss_frz) begin
		if (phi1)
			out_next <= in;

		if (phi2)
			out_latch <= out_next;

		if (reset) begin
			out_latch <= 0;
			out_next <= 0;
		end
	end
	end
	assign ss_c1 = {out_next, out_latch};
endmodule

module inverter_reg
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input clk,
	input reset,
	input set,
	input in,
	output out
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;


	logic inv_latch = 0;
	// FIXME: I'm treating this as a gate delay since I am using a 14mhz clock for this design,
	// but with slower clocks, this may need to be continuous to work correctly.
	assign out = /*set ? in : */inv_latch;

	always @(posedge clk) begin
		if (ss_en) {inv_latch} <= {ss_c0, inv_latch} >> 1;
		else if (!ss_frz) begin
		if (set)
			inv_latch <= in;
		if (reset)
			inv_latch <= 0;
	end
	end
	assign ss_c1 = {inv_latch};
endmodule


/////////////////////////////////////////////////////////////////////////////////////////
module f_counter
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input  logic   clk,
	input  logic   reset,
	input  logic   sys_reset,
	input  logic   tick,
	output clock_t clock,
	output logic   f1_qn,
	output logic   f1_qn_edge,
	output logic   f1_q_l
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;


// This component re-occurs throughout the design multiple times and contains two
// F1 cells, effectively creating a counter that goes from 0 to 3 and then resets, flipping the
// clock on two of the four positions.

// This does not generate a symmetric clock. It is a four phase ripple counter, so PH1 and
// PH2 will only be high for one clock each out of four clocks total.

localparam EDGE_P1 = 3;
localparam LEVEL_P1 = 0;
localparam EDGE_P2 = 1;
localparam LEVEL_P2 = 2;

// Left      Right
// q   qn    q   qn
// 0    1    0    1
// 1    0    0    1
// 1    0    1    0
// 0    1    1    0

logic [1:0] f_count = 0;
logic old_tick, old_reset;
logic f1_qn_reg;

wire tick_edge = ~old_tick && tick;

assign clock.edge_p1 = tick_edge && ((f_count == EDGE_P1) || reset && ~clock.level_p1);
assign clock.edge_p2 = tick_edge && (f_count == EDGE_P2) && ~clock.level_p2 && ~reset;
assign clock.level_p1 = (f_count == LEVEL_P1) || reset && old_reset;
assign clock.level_p2 = (f_count == LEVEL_P2);
assign f1_qn_edge = tick_edge && f_count == 3;
assign f1_qn = (f_count == 0 || f_count == 1);
assign f1_q_l = reset ? 1'd1 : (~f1_qn ? 1'd0 : f1_qn_reg);
assign clock.clock = 0; // Clock is unused for ripple counters!!

always_ff @(posedge clk) begin
		if (ss_en) {old_tick, old_reset, f_count[1], f_count[0], f1_qn_reg} <= {ss_c0, old_tick, old_reset, f_count[1], f_count[0], f1_qn_reg} >> 1;
		else if (!ss_frz) begin
	old_tick <= tick;
	old_reset <= reset;

	if (tick_edge) begin
		f_count <= f_count + 1'd1;
	end

	if (reset || sys_reset) begin
		f_count <= reset ? 1'd1 : 2'd0;
		if (sys_reset) old_tick <= 0;
		if (reset)
			f1_qn_reg <= 1;
	end

	if (~f1_qn)
		f1_qn_reg <= 0;

end
	end
	assign ss_c1 = {old_tick, old_reset, f_count[1], f_count[0], f1_qn_reg};

endmodule


module cpuclk
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input         clk,
	input         reset,
	input clock_t oclk,
	input         resp0,
	output        phi0
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c4;


	logic q_1, q_2, q_3, q_4;
	logic qn_1, qn_2, qn_3, qn_4;

	assign phi0 = (q_1 || q_4);

	wire q_3_nor = ~(q_4 || qn_2);

	sr_latch q_1l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk    (clk),
		.reset  (reset),
		.r      (~(oclk.clock || q_4)),
		.s      (~(oclk.clock || qn_4)),
		.q      (q_1),
		.q_n    (qn_1)
	);

	sr_latch q_2l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk    (clk),
		.reset  (reset),
		.r      (oclk.clock && q_1),
		.s      ((oclk.clock && qn_1) || resp0),
		.q      (q_2),
		.q_n    (qn_2)
	);

	sr_latch q_3l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c2), .ss_so(ss_c3),
		.clk    (clk),
		.reset  (reset),
		.r      (~(oclk.clock || ~q_3_nor)),
		.s      (~(oclk.clock || q_3_nor)),
		.q      (q_3),
		.q_n    (qn_3)
	);

	sr_latch q_4l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c3), .ss_so(ss_c4),
		.clk    (clk),
		.reset  (reset),
		.r      (oclk.clock && q_3),
		.s      ((oclk.clock && qn_3) || resp0),
		.q      (q_4),
		.q_n    (qn_4)
	);
endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module clockgen
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input  logic   clk,    // System clock
	input  logic   is_7800,
	input  logic   ce,     // clock enable. This is expected to be 7.159091 mhz, 2x the original atari oscillator
	input  logic   reset,  // reset signal
	input  logic   rsync,  // RSYNC register written to
	input  logic   rsynd,  // rsynd wire coming from the horizontal lfsr decoder
	input  logic   pext_1, // CPU clk Phi1 external (7800)
	input  logic   pext_2, // CPU clk Phi0/2 external
	output logic   rsynl,  // RSYNC latch
	output clock_t pclk, // CPU clock
	output clock_t hclk, // Horizontal clock
	output clock_t oclk,  // Oscillator Clock
	output logic   phi0_ll,
	// The divider's own edges. Same as pclk.edge_p* in 2600 mode; in 7800 mode
	// pclk follows pext_* and these do not. Every term below is a register, so
	// there is no path from pext_* to here - which is what breaks the
	// pext -> pclk -> phase controller -> pext ring. See the TIA phi*_gen pins.
	output logic   pclk_gen_edge_p1,
	output logic   pclk_gen_edge_p2
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c2;


parameter PHI2_EXT = 0;
// Fantastic Clocks and Where To Find Them
// system oscillator - every other CE, 3.1mhz
// motclk            - inverse of the system oscillator while not hblank
// clkp              - pixel clk, inverse of the system oscillator
// horizontal clk    - HP1 and HP2, every four clkp
// pclk              - phi0 = phi2, phi1 = ~phi0. cpu clk, every 3 system oscillator clks

logic oclk_tog;
logic [2:0] pclk_div;
logic pclock;
// Held outside the struct: a clock_t is one signal to the linter, so a field
// derived from another field of the same struct reads as a loop.
logic oclk_clock, pclk_clock;
wire pclk_edge = (oclk.edge_p1 || oclk.edge_p2);
assign oclk.edge_p2 = oclk_tog && ce;
assign oclk.edge_p1 = ~oclk_tog && ce;
assign oclk.clock    = oclk_clock;
assign oclk.level_p1 = ~oclk_clock;
assign oclk.level_p2 = oclk_clock;

assign pclk_gen_edge_p2 = ((pclk_div == 2) && pclk_edge) && ~pclk_clock;
assign pclk_gen_edge_p1 = ((pclk_div == 5 || (resp0 && pclk_div == 0)) && pclk_edge) && pclk_clock;

assign pclk.edge_p2 = (is_7800 || PHI2_EXT) ? (pext_2 && ~pclk_clock) : pclk_gen_edge_p2; // Phi0 // 0
assign pclk.edge_p1 = is_7800 ? (pext_1 && pclk_clock) : pclk_gen_edge_p1; // Phi1 // 1
assign pclk.clock    = pclk_clock;
assign pclk.level_p1 = ~pclk_clock;
assign pclk.level_p2 = pclk_clock;

clock_t hclk_ll, hclk_hl;

f_counter hclk_counter
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
	.clk        (clk),
	.reset      (rsync),
	.sys_reset  (reset),
	.tick       (oclk.edge_p2),
	.clock      (hclk),
	.f1_qn      (),
	.f1_qn_edge (),
	.f1_q_l     (rsynl)
);

wire resp0 = (hclk.level_p2 && rsynd) || reset;

// This is an original cpu clock divider purely for reference purposes. I left it in case
// anyone ever wanted to use it for research.

// cpuclk pclk_gen
// (
// 	.clk        (clk),
// 	.reset      (reset),
// 	.oclk       (oclk),
// 	.resp0      (resp0),
// 	.phi0       (phi0_ll)
// );
assign phi0_ll = 0;

always_ff @(posedge clk) begin
		if (ss_en) {oclk_tog, oclk_clock, pclk_div[2], pclk_div[1], pclk_div[0], pclk_clock} <= {ss_c1, oclk_tog, oclk_clock, pclk_div[2], pclk_div[1], pclk_div[0], pclk_clock} >> 1;
		else if (!ss_frz) begin : phi0_gen
	// Oscillator Clock
	if (ce) begin
		oclk_tog <= ~oclk_tog;
	end

	if (oclk.edge_p2) begin
		oclk_clock <= 1;
	end else if (oclk.edge_p1) begin
		oclk_clock <= 0;
	end

	// CPU Clock
	if (pclk_edge) begin
		pclk_div <= (pclk_div == 5) ? 3'd0 : pclk_div + 1'd1;
	end

	if (pclk.edge_p2)
		pclk_clock <= 1'b1;
	else if (pclk.edge_p1)
		pclk_clock <= 1'b0;

	if (hclk.edge_p2 && rsynd) begin
		pclk_div <= 3'd2;
	end

	if (reset) begin
		pclk_div <= 3'd4;
		oclk_tog <= 0;
		oclk_clock <= '0;
		pclk_clock <= 0;
	end
end
	end
	assign ss_c2 = {oclk_tog, oclk_clock, pclk_div[2], pclk_div[1], pclk_div[0], pclk_clock};

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module horiz_gen
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input logic clk,
	input logic rst,
	input clock_t hclk,
	input logic rsynl,
	input logic sec,
	output logic hsync,
	output logic CB,
	output logic cntd,
	output logic cnt,
	output logic hblank, // Hblank signal with proper delays for hmove
	output logic hgap, // Hblank signal without delay
	output logic aud0, // Audio clocks need to be high twice per line
	output logic aud1,
	output logic shb,
	output logic rhb,
	output logic rsynd
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5, ss_c6, ss_c7, ss_c8, ss_c9, ss_c10, ss_c11, ss_c12;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c12;


	logic [5:0] lfsr;
	logic sec_latch, sec_latch_n;
	
	logic err, rhs, rcb, shs, lrhb, ehb;
	logic aud1_l, aud2_l;
	logic rhs_d;
	logic hblank_n, hgap_n;
	
	assign aud0 = aud1_l;
	assign aud1 = aud2_l;
	wire eer = (ehb || rsynl || err);
	
	lfsr_6 timing_lfsr
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk       (clk),
		.phi1      (hclk.level_p1),
		.phi2      (hclk.level_p2),
		.reset     (shb || rst),
		.sys_reset (rst),
		.lfsr      (lfsr)
	);

	always_comb begin
		{err, rhs, ehb, cnt, shs, lrhb, rhb, rcb} = '0;
		case (lfsr)
				6'b111111: err  = 1;    // Error
				6'b010100: ehb  = 1;    // End (Set Hblank)
				6'b110111: rhs  = 1;    // Reset HSync
				6'b101100: cnt  = 1;    // Center
				6'b001111: rcb  = 1;    // Reset Color Burst
				6'b111100: shs  = 1;    // Set Hsync
				6'b011100: rhb  = 1;    // Reset HBlank
				6'b010111: lrhb = 1;    // Late Reset Hblank
				default: ;
		endcase
	end

	sr_latch sec_l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk    (clk),
		.reset  (rst),
		.r      (sec),
		.s      (shb),
		.q      (sec_latch),
		.q_n    (sec_latch_n)
	);

	inverter_reg rsynd_ir(ss_en, ss_frz, ss_c2, ss_c3, clk, rst, hclk.level_p1, eer, rsynd);
	inverter_reg shb_ir(ss_en, ss_frz, ss_c3, ss_c4, clk, rst, hclk.level_p2, rsynd, shb);

	d_cell aud1_d
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c4), .ss_so(ss_c5),
		.clk        (clk),
		.reset      (rst),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (shb || lrhb),
		.out        (aud1_l)
	);

	d_cell aud2_d
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c5), .ss_so(ss_c6),
		.clk        (clk),
		.reset      (rst),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (rhs || cnt),
		.out        (aud2_l)
	);

	d_cell rhs_db
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c6), .ss_so(ss_c7),
		.clk        (clk),
		.reset      (rst),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (rhs),
		.out        (rhs_d)
	);

	d_cell hsync_dl
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c7), .ss_so(ss_c8),
		.clk        (clk),
		.reset      (rst || rhs_d),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (hsync || shs),
		.out        (hsync)
	);

	wire hb_1a = sec_latch && rhb;
	wire hb_1b = sec_latch_n && lrhb;

	d_cell hblank_dl
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c8), .ss_so(ss_c9),
		.clk        (clk),
		.reset      (rst || shb),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (hblank_n || hb_1a || hb_1b),
		.out        (hblank_n)
	);

	assign hblank = ~hblank_n;

	d_cell hgap_dl
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c9), .ss_so(ss_c10),
		.clk        (clk),
		.reset      (rst || shb),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (hgap_n || rhb),
		.out        (hgap_n)
	);

	assign hgap = ~hgap_n;

	d_cell cb_dl
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c10), .ss_so(ss_c11),
		.clk        (clk),
		.reset      (rst || rhs_d),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (CB || rcb),
		.out        (CB)
	);

	d_cell cnt_d
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c11), .ss_so(ss_c12),
		.clk        (clk),
		.reset      (rst),
		.phi1       (hclk.level_p1),
		.phi2       (hclk.level_p2),
		.in         (cnt),
		.out        (cntd)
	);

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module hmove_gen
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input  logic       clk,
	input  logic       reset,
	input  clock_t     hclk,
	input  clock_t     oclk,
	input  clock_t     pclk,
	input  logic       hmove,
	input  logic       hblank,
	input  logic [3:0] p0_m,
	input  logic [3:0] p1_m,
	input  logic [3:0] m0_m,
	input  logic [3:0] m1_m,
	input  logic [3:0] bl_m,
	output logic       sec,
	output logic       p0_mclk,
	output logic       p1_mclk,
	output logic       m0_mclk,
	output logic       m1_mclk,
	output logic       bl_mclk
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c5;

	logic [1:0] p0ec, p1ec, m0ec, m1ec, blec;
	logic [3:0] hmove_cnt;
	logic sec_1, sec_0;
	logic hmove_latch;

	wire [3:0] hmc_uns = {~hmove_cnt[3], hmove_cnt[2:0]};

	assign p0_mclk = (p0ec[1] && hclk.level_p1);
	assign p1_mclk = (p1ec[1] && hclk.level_p1);
	assign m0_mclk = (m0ec[1] && hclk.level_p1);
	assign m1_mclk = (m1ec[1] && hclk.level_p1);
	assign bl_mclk = (blec[1] && hclk.level_p1);

	sr_latch hmove_l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk    (clk),
		.reset  (reset),
		.r      (sec_1),
		.s      (hmove),
		.q      (hmove_latch),
		.q_n    ()
	);

	inverter_reg s0_ir(ss_en, ss_frz, ss_c1, ss_c2, clk, reset, hclk.level_p1, hmove_latch, sec_0);
	inverter_reg sec_ir(ss_en, ss_frz, ss_c2, ss_c3, clk, reset, hclk.level_p2, sec_0, sec);
	inverter_reg sec1_ir(ss_en, ss_frz, ss_c3, ss_c4, clk, reset, hclk.level_p1, sec, sec_1);

	always @(posedge clk) begin
		if (ss_en) {hmove_cnt[3], hmove_cnt[2], hmove_cnt[1], hmove_cnt[0], p0ec[1], p0ec[0], p1ec[1], p1ec[0], m0ec[1], m0ec[0], m1ec[1], m1ec[0], blec[1], blec[0]} <= {ss_c4, hmove_cnt[3], hmove_cnt[2], hmove_cnt[1], hmove_cnt[0], p0ec[1], p0ec[0], p1ec[1], p1ec[0], m0ec[1], m0ec[0], m1ec[1], m1ec[0], blec[1], blec[0]} >> 1;
		else if (!ss_frz) begin : hmove_block
		if (hclk.edge_p2) begin
			if (sec || |hmove_cnt)
				hmove_cnt <= hmove_cnt + 1'd1;
			{p0ec[1], p1ec[1], m0ec[1], m1ec[1], blec[1]} <= {p0ec[0], p1ec[0], m0ec[0], m1ec[0], blec[0]};
		end

		if (hclk.level_p1) begin
			// Arm each extra-clock latch once; SEC spans two modelled phase windows.
			if (sec && ~sec_1)
				{p0ec[0], p1ec[0], m0ec[0], m1ec[0], blec[0]} <= 5'b11111;
			if (p0_m[3:0] == hmc_uns)
				p0ec[0] <= 0;
			if (p1_m[3:0] == hmc_uns)
				p1ec[0] <= 0;
			if (m0_m[3:0] == hmc_uns)
				m0ec[0] <= 0;
			if (m1_m[3:0] == hmc_uns)
				m1ec[0] <= 0;
			if (bl_m[3:0] == hmc_uns)
				blec[0] <= 0;
		end

		if (reset) begin
			{p0ec, p1ec, m0ec, m1ec, blec} <= 10'd0;
			hmove_cnt <= 0;
		end
	end
	end
	assign ss_c5 = {hmove_cnt[3], hmove_cnt[2], hmove_cnt[1], hmove_cnt[0], p0ec[1], p0ec[0], p1ec[1], p1ec[0], m0ec[1], m0ec[0], m1ec[1], m1ec[0], blec[1], blec[0]};

endmodule


/////////////////////////////////////////////////////////////////////////////////////////

module playfield
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input         clk,     // Master clock
	input         reset,   // System reset
	input logic   clkp,    // Pixel Clock
	input clock_t hclk,    // Horizontal clock phase 2
	input         reflect, // Control playfield, 1 makes right half mirror image
	input         cnt,     // center signal, high means right half
	input         rhb,     // Reset HBlank signal
	input [19:0]  pfc,     // Combined playfield registers
	output logic  pf       // Playfield graphics
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c5;


	logic [4:0] pf_index, pf_next, pf_latch2, pf_latch1;
	logic pf_1, pf_2, pf_3;

	// Outputs in order PF0 4..7, PF1 7:0, PF2 0:7, then the empty position
	logic [4:0] index_lut[21];

	wire pf_reset = rhb || (cnt && ~reflect);
	wire pf_reflect = (cnt && reflect);

	assign index_lut = '{
		5'd00, 5'd01, 5'd02, 5'd03,                             // PF0
		5'd11, 5'd10, 5'd09, 5'd08, 5'd07, 5'd06, 5'd05, 5'd04, // PF1 in reverse
		5'd12, 5'd13, 5'd14, 5'd15, 5'd16, 5'd17, 5'd18, 5'd19, // PF2
		5'd20                                                   // empty
	};

	logic [4:0] pf_latch;
	logic dir;

	// This is a 20 bit parallel to serial converter (TIA-1A manual figure 5),
	// so once both halves of the line have been shifted out it has nothing
	// left to emit and PF reads low until the next [RHB]. That silence is what
	// keeps an object frozen mid-draw across HBLANK from colliding with the
	// last playfield pixel on every scanline. The count still holds at the
	// mirrored centre, where PF2 D7 is emitted twice.
	localparam PF_EMPTY = 5'd20;
	wire [20:0] pf_bits = {1'b0, pfc};

	assign pf_index = pf_reset ? 1'd0 : (hclk.level_p2 ? pf_latch1 : pf_latch2);
	assign pf_next = (pf_index == PF_EMPTY) ? PF_EMPTY :
		dir ? (|pf_index ? pf_index - 1'd1 : PF_EMPTY) :
		(pf_index < 19 ? pf_index + 1'd1 : (reflect ? 5'd19 : PF_EMPTY));

	assign pf_1 = pf_bits[index_lut[pf_index]];

	f_cell pf_out
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk        (clk),
		.reset      (reset),
		.tick       (clkp),
		.s_n        (~pf_3),
		.r_n        (pf_3),
		.q          (pf),
		.q_n        ()
	);

	sr_latch dir_l
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk        (clk),
		.reset      (reset),
		.r          (pf_reset),
		.s          (pf_reflect),
		.q          (dir),
		.q_n        ()
	);

	inverter_reg pf1_ir(ss_en, ss_frz, ss_c2, ss_c3, clk, reset, hclk.level_p1, pf_1, pf_2);
	inverter_reg pf2_ir(ss_en, ss_frz, ss_c3, ss_c4, clk, reset, hclk.level_p2, pf_2, pf_3);

	always @(posedge clk) begin
		if (ss_en) {pf_latch1[4], pf_latch1[3], pf_latch1[2], pf_latch1[1], pf_latch1[0], pf_latch2[4], pf_latch2[3], pf_latch2[2], pf_latch2[1], pf_latch2[0]} <= {ss_c4, pf_latch1[4], pf_latch1[3], pf_latch1[2], pf_latch1[1], pf_latch1[0], pf_latch2[4], pf_latch2[3], pf_latch2[2], pf_latch2[1], pf_latch2[0]} >> 1;
		else if (!ss_frz) begin : pf_block
		if (hclk.level_p1) begin
			pf_latch1 <= pf_next;
		end

		if (hclk.level_p2) begin
			pf_latch2 <= pf_latch1;
		end
	end
	end
	assign ss_c5 = {pf_latch1[4], pf_latch1[3], pf_latch1[2], pf_latch1[1], pf_latch1[0], pf_latch2[4], pf_latch2[3], pf_latch2[2], pf_latch2[1], pf_latch2[0]};

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module object_tick
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input clk,
	input reset,
	input motck,
	input ec,
	output tick
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;

	// The reason for signal this centers around an analog delay of around 21ns which causes an
	// extra clock edge to form if the hmove counter is glitched into remaining on during non-hblank
	// clocks. This was discovered by Crispy and is available in this topic here:
	// https://atariage.com/forums/topic/261596-cosmic-ark-star-field-revisited/
	logic old_motck, old_ec;

	wire edge_miss = (old_motck && ~motck) && (~old_ec && ec);
	assign tick = (motck || ec) && ~edge_miss;
	always @(posedge clk) begin
		if (ss_en) {old_motck, old_ec} <= {ss_c0, old_motck, old_ec} >> 1;
		else if (!ss_frz) begin
		old_motck <= motck;
		old_ec <= ec;
		if (reset) begin
			old_motck <= 0;
			old_ec <= 0;
		end
	end
	end
	assign ss_c1 = {old_motck, old_ec};

endmodule

/////////////////////////////////////////////////////////////////////////////////////////

module ball
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input       clk,         // Master Clock
	input       reset,       // System Reset
	input       clkp,        // Pixel Clock
	input       motck,       // Motion Clock (real clock)
	input       blec,        // Ball extra clock
	input       blre,        // Ball reset signal
	input       blen,        // Ball enable register
	input       blen_o,      // Ball enable register (last)
	input       blvd,        // Ball vdel
	input [1:0] blsiz,       // Ball size register
	output      bl           // Ball graphics output
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5, ss_c6;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c6;

	clock_t objclk;

	logic [1:0] d1l_1, d1l_2;
	logic [5:0] lfsr;
	logic fc1_qn;
	logic q_or_res;

	wire object_tick;
	wire object_reset = (lfsr == 6'b111111 || lfsr == 6'b101101 || q_or_res);

	object_tick bl_tick
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk        (clk),
		.reset      (reset),
		.motck      (motck),
		.ec         (blec),
		.tick       (object_tick)
	);

	f_counter_ll object_counter
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk        (clk),
		.reset      (blre),
		.sys_reset  (reset),
		.tick       (object_tick),
		.clock      (objclk),
		.f1_qn      (fc1_qn),
		.f1_q_l     (q_or_res)
	);

	lfsr_6 object_lfsr
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c2), .ss_so(ss_c3),
		.clk       (clk),
		.phi1      (objclk.level_p1),
		.phi2      (objclk.level_p2),
		.reset     (~d1l_1[1]),
		.sys_reset (reset),
		.lfsr      (lfsr)
	);

	wire gr1  = ~((~blvd && blen) || (blvd && blen_o));
	wire gr2a = ~(~blsiz[1] || ~blsiz[0] || d1l_2[1] || gr1);
	wire gr2b = ~(~blsiz[0] || fc1_qn);
	wire gr3  = ~(blsiz[1] || gr2b || objclk.level_p2);
	wire gr4  = ~(gr1 || gr3 || d1l_1[1]);
	wire gr5 = ~(gr2a || gr4);

	f_cell ball_out
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c3), .ss_so(ss_c4),
		.clk        (clk),
		.reset      (reset),
		.tick       (clkp),
		.s_n        (gr5),
		.r_n        (~gr5),
		.q          (bl),
		.q_n        ()
	);

	d_cell obj_1
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c4), .ss_so(ss_c5),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (~object_reset),
		.out        (d1l_1[1])
	);

	d_cell obj_2
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c5), .ss_so(ss_c6),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (d1l_1[1]),
		.out        (d1l_2[1])
	);

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module missile
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input       clk,        // Master Clock
	input       reset,      // System Reset
	input       clkp,       // Pixel clock
	input       motck,      // Motion Clock (real clock)
	input       mec,        // Missile extra clock
	input       mre,        // Missile reset signal
	input       men,        // Missile enable register
	input [5:0] nusiz,      // Player/missile size
	output      m           // Missile graphics output
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5, ss_c6, ss_c7;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c7;


	clock_t objclk;

	logic [1:0] d1l_1, d1l_2;
	logic [5:0] lfsr;
	logic fc1_qn;
	logic or_d;

	wire object_tick;
	wire [1:0] m_size_n = ~nusiz[5:4];
	wire [2:0] ns_sel = nusiz[2:0];
	wire q_or_res;
	wire object_reset = (lfsr == 6'b111111 || lfsr == 6'b101101 || q_or_res);
	wire object_draw = (lfsr == 6'b101101) ||
		((lfsr == 6'b111000) && ((ns_sel == 3'b001) || (ns_sel == 3'b011))) ||
		((lfsr == 6'b101111) && ((ns_sel == 3'b011) || (ns_sel == 3'b010)   || (ns_sel == 3'b110))) ||
		((lfsr == 6'b111001) && ((ns_sel == 3'b100) || (ns_sel == 3'b110)));

	object_tick m_tick
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk        (clk),
		.reset      (reset),
		.motck      (motck),
		.ec         (mec),
		.tick       (object_tick)
	);

	f_counter_ll object_counter
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk        (clk),
		.reset      (mre),
		.sys_reset  (reset),
		.tick       (object_tick),
		.clock      (objclk),
		.f1_qn      (fc1_qn),
		.f1_q_l     (q_or_res)
	);

	lfsr_6 object_lfsr
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c2), .ss_so(ss_c3),
		.clk       (clk),
		.phi1      (objclk.level_p1),
		.phi2      (objclk.level_p2),
		.reset     (or_d),
		.sys_reset (reset),
		.lfsr      (lfsr)
	);

	wire mg1  = ~(fc1_qn || m_size_n[0]);
	wire mg2a = ~(mg1 || objclk.level_p2 || ~m_size_n[1]);
	wire mg2b = ~(~men || m_size_n[1] || d1l_2[1] || m_size_n[0]);
	wire mg3  = ~(mg2a || ~men || d1l_1[1]);
	wire mg4  = ~(mg3 || mg2b);

	f_cell mis_out
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c3), .ss_so(ss_c4),
		.clk        (clk),
		.reset      (reset),
		.tick       (clkp),
		.s_n        (mg4),
		.r_n        (~mg4),
		.q          (m),
		.q_n        ()
	);

	d_cell obj_1
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c4), .ss_so(ss_c5),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (object_reset),
		.out        (or_d)
	);

	d_cell obj_2
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c5), .ss_so(ss_c6),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (~object_draw),
		.out        (d1l_1[1])
	);

	d_cell obj_3
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c6), .ss_so(ss_c7),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (d1l_1[1]),
		.out        (d1l_2[1])
	);

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module player
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input       clk,        // Master Clock
	input       reset,      // System Reset
	input       clkp,       // Pixel Clock
	input       motck,      // Motion Clock (real clock)
	input       pec,        // Player extra clock
	input       pre,        // Player reset signal
	input       pvdel,      // Player Vertical Delay
	input       m2pr,       // Missile To Player Reset Enabled
	input       pref,       // player reflect
	input [5:0] nusiz,      // Player size
	input [7:0] grpnew,     // Player graphic (new)
	input [7:0] grpold,     // Player graphic (delayed)
	output      msrst,      // Missile to player reset signal
	output      p           // Player graphics output
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5, ss_c6, ss_c7, ss_c8, ss_c9, ss_c10, ss_c11, ss_c12;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c12;

	clock_t objclk;

	logic [1:0] d1l_1, d1l_2;
	logic [5:0] lfsr;
	logic fstob;
	logic fc1_qn;
	logic ena_n;
	logic start_n;
	logic f_psc1_q, f_psc1_q_n, f_psc2_q, f_psc2_q_n, f_psc3_q, f_psc3_q_n;
	logic go_n;
	logic or_d;
	logic [2:0] gs;

	wire object_tick;
	wire [2:0] ns_sel = nusiz[2:0];
	wire q_or_res;
	wire object_reset = (lfsr == 6'b111111 || lfsr == 6'b101101 || q_or_res);
	wire object_fstob =
		((lfsr == 6'b111000) && ((ns_sel == 3'b001) || (ns_sel == 3'b011))) ||
		((lfsr == 6'b101111) && ((ns_sel == 3'b011) || (ns_sel == 3'b010)   || (ns_sel == 3'b110))) ||
		((lfsr == 6'b111001) && ((ns_sel == 3'b100) || (ns_sel == 3'b110)));

	wire object_draw = (lfsr == 6'b101101) || object_fstob;
	wire pns = ~(~nusiz[0] || ~nusiz[2]);
	wire pns2 = objclk.level_p1 && ~nusiz[1];
	wire count_n = ~(~pns || pns2 || objclk.level_p2);
	wire stop = ~(f_psc1_q_n || f_psc2_q_n || f_psc3_q_n);
	wire start_stop = ~(start_n && stop);
	wire newgrp = grpnew[gs];
	wire oldgrp = grpold[gs];

	assign msrst = ~(fstob || ena_n || object_tick || f_psc3_q || f_psc2_q || f_psc1_q_n || ~m2pr);
	assign gs[0] = ~((pref && f_psc1_q_n) || (~pref && f_psc1_q));
	assign gs[1] = ~((pref && f_psc2_q_n) || (~pref && f_psc2_q));
	assign gs[2] = ~((pref && f_psc3_q_n) || (~pref && f_psc3_q));

	object_tick p_tick
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk        (clk),
		.reset      (reset),
		.motck      (motck),
		.ec         (pec),
		.tick       (object_tick)
	);

	f_counter_ll object_counter
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
		.clk        (clk),
		.reset      (pre),
		.sys_reset  (reset),
		.tick       (object_tick),
		.clock      (objclk),
		.f1_qn      (fc1_qn),
		.f1_q_l     (q_or_res)
	);

	lfsr_6 object_lfsr
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c2), .ss_so(ss_c3),
		.clk       (clk),
		.phi1      (objclk.level_p1),
		.phi2      (objclk.level_p2),
		.reset     (or_d),
		.sys_reset (reset),
		.lfsr      (lfsr)
	);

	wire pl_1a = ~(go_n || ~oldgrp || ~pvdel);
	wire pl_1b = ~(go_n || ~newgrp || pvdel);
	wire pl_2 = ~(pl_1a || pl_1b);

	f_cell pl_out
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c3), .ss_so(ss_c4),
		.clk        (clk),
		.reset      (reset),
		.tick       (clkp),
		.s_n        (pl_2),
		.r_n        (~pl_2),
		.q          (p),
		.q_n        ()
	);

	d_cell obj_reset
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c4), .ss_so(ss_c5),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (object_reset),
		.out        (or_d)
	);

	d_cell obj_start
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c5), .ss_so(ss_c6),
		.clk        (clk),
		.reset      (reset),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (~object_draw),
		.out        (start_n)
	);

	d_cell obj_fstob
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c6), .ss_so(ss_c7),
		.clk        (clk),
		.reset      (reset || or_d),
		.phi1       (objclk.level_p1),
		.phi2       (objclk.level_p2),
		.in         (fstob || object_fstob),
		.out        (fstob)
	);

	f_cell f_ena
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c7), .ss_so(ss_c8),
		.clk        (clk),
		.reset      (reset),
		.tick       (object_tick),
		.s_n        (count_n),
		.r_n        (~count_n),
		.q          (),
		.q_n        (ena_n)
	);

	f_cell f_go
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c8), .ss_so(ss_c9),
		.clk        (clk),
		.reset      (reset),
		.tick       (object_tick),
		.s_n        (ena_n || start_n),
		.r_n        (ena_n || start_stop),
		.q          (),
		.q_n        (go_n)
	);

	wire ena_n_or_go_n = (ena_n || go_n);

	f_cell f_psc1
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c9), .ss_so(ss_c10),
		.clk        (clk),
		.reset      (reset),
		.tick       (object_tick),
		.s_n        (ena_n_or_go_n || f_psc1_q),
		.r_n        (ena_n_or_go_n || f_psc1_q_n),
		.q          (f_psc1_q),
		.q_n        (f_psc1_q_n)
	);

	wire ena_n_or_go_2 = (ena_n_or_go_n || f_psc1_q_n);

	f_cell f_psc2
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c10), .ss_so(ss_c11),
		.clk        (clk),
		.reset      (reset),
		.tick       (object_tick),
		.s_n        (ena_n_or_go_2 || f_psc2_q),
		.r_n        (ena_n_or_go_2 || f_psc2_q_n),
		.q          (f_psc2_q),
		.q_n        (f_psc2_q_n)
	);

	wire ena_n_or_go_3 = (ena_n_or_go_2 || f_psc2_q_n);

	f_cell f_psc3
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c11), .ss_so(ss_c12),
		.clk        (clk),
		.reset      (reset),
		.tick       (object_tick),
		.s_n        (ena_n_or_go_3 || f_psc3_q),
		.r_n        (ena_n_or_go_3 || f_psc3_q_n),
		.q          (f_psc3_q),
		.q_n        (f_psc3_q_n)
	);

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module priority_encoder
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input           clk,
	input           p0,
	input           m0,
	input           p1,
	input           m1,
	input           pf,
	input           bl,
	input           blank,
	input           cntd,
	input           pfp,
	input           score,
	output [3:0]    col_select // {bk, pf, p1, p0}
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;


	// Normal priority:
	// 0: P0, M0
	// 1: P1, M1
	// 2: PF, BL
	// 3: BK

	// PFP:
	// 0: PF, BL
	// 1: P0, M0
	// 2: P1, M1
	// 3: BK

	// When a one is written into the score control bit, the playfield is forced
	// to take the color-lum of player 0 in the left half of the screen and player
	// 1 in the right half of the screen.
	logic rs_q;
	logic rs_qn;

	sr_latch center_delayed
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
		.clk    (clk),
		.reset  (),
		.r      (blank),
		.s      (cntd),
		.q      (rs_q),
		.q_n    (rs_qn)
	);

	wire score_n = ~score;
	wire pfp_n = ~pfp;

	wire pf_n = ~pf;
	wire pf_nor_bl = ~(pf || bl);
	wire pr_1a = ~(rs_q || pf_n || score_n);
	wire pr_1b = ~(pf_n || score_n || rs_qn);
	wire pr_2a = ~(p0 || m0 || pr_1a);
	wire pr_2b = ~(p1 || m1 || pr_1b);
	wire pr_2c = ~(pf_nor_bl || pfp_n);

	wire sel_p0 = ~(blank || pr_2a || pr_2c);
	wire sel_p1 = ~(blank || pr_2b || pr_2c || sel_p0);
	wire sel_pf = ~(blank || pf_nor_bl || sel_p1 || sel_p0);
	wire sel_bk = ~(blank || sel_pf || sel_p1 || sel_p0);

	assign col_select = {sel_bk, sel_pf, sel_p1, sel_p0};

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module audio_channel
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input           clk,
	input           reset,
	input           aud0,
	input           aud1,
	input  [3:0]    volume,
	input  [4:0]    freq,
	input  [3:0]    audc,
	output [3:0]    audio
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5, ss_c6, ss_c7, ss_c8, ss_c9;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c9;


	// Audio is quite a lot of convoluted wide nors and odd shifting, so
	// I just got sick of trying to simplify it and did it at gate level.

	// Frequency divider area signals
	logic [4:0] freq_div, freq_latch, freq_next;
	logic freq_match, freq_div1, freq_div2;
	logic T1, T2;

	// Noise area signals
	logic [4:0] noise, noise_latch, noise_next;
	logic noise_wnor_1;
	logic noise_wnor_2;
	logic nor1, nor2, nor3, nor4, nor5, nor6, nor7, nor8;
	logic and1, and2;
	logic noise0_latch_n;
	logic nor2_latch;

	// Pulse area signals
	logic nor_a, nor_b, nor_c, nor_d, nor_e;
	logic pulse_bit;
	logic pulse_wnor_1;
	logic pulse_wnor_2;
	logic rnor1, rnor2, rnor3;
	logic rand1;
	logic pulse3_q, pulse2_q, pulse1_q, pulse0_q;
	logic pulse3_qn, pulse2_qn, pulse1_qn, pulse0_qn;

	// Frequency divider area logic
	assign freq_div = (aud1 ? (~freq_div2 ? 5'd0 : freq_next) : freq_latch);
	assign freq_match = (freq == freq_div);

	inverter_reg freq_div01(ss_en, ss_frz, ss_c0, ss_c1, clk, reset, aud0, ~freq_match, freq_div1);
	inverter_reg freq_div02(ss_en, ss_frz, ss_c1, ss_c2, clk, reset, aud1, freq_div1, freq_div2);

	assign T1 = ~|{~aud0, freq_div2};
	assign T2 = ~|{~aud1, freq_div1};

	// Noise area logic
	assign nor1 = ~|{~audc[1:0], noise0_latch_n};
	assign nor2 = ~|{nor1, ~audc[1], noise_wnor_1};
	assign nor3 = ~|{audc[1:0], pulse_wnor_1};
	assign nor4 = ~|audc[1:0];
	assign nor5 = ~|{~noise[2], nor4};
	assign nor6 = ~|{nor5, and1};
	assign nor7 = ~|{nor6, noise[0]};
	assign nor8 = ~|{nor_a, nor7, and2, noise_wnor_2};

	assign and1 = nor4 && pulse0_q;
	assign and2 = noise[0] && nor6;

	assign noise_wnor_1 = ~|{noise[4:2], ~noise[1], audc[0], ~audc[1]};
	assign noise_wnor_2 = ~|{noise, nor3};

	// Pulse area logic
	assign rnor1 = ~|{pulse_wnor_2, pulse1_q};
	assign rnor2 = ~|{pulse1_q, pulse0_q};
	assign rnor3 = ~|{pulse_wnor_1, rnor2, rand1};

	assign rand1 = pulse1_q && pulse0_q;

	assign nor_a = ~|audc;
	assign nor_b = ~|{audc[3:2], rnor3};
	assign nor_c = ~|{~audc[3:2], rnor1};
	assign nor_d = ~|{audc[3], ~audc[2], pulse3_qn};
	assign nor_e = ~|{~audc[3], audc[2], noise0_latch_n};

	assign pulse_bit = ~|{nor_a, nor_b, nor_c, nor_d, nor_e};

	assign pulse_wnor_1 = ~|{pulse3_qn, pulse2_q, pulse1_qn, pulse0_q};
	assign pulse_wnor_2 = ~|{pulse3_q, pulse2_q, pulse1_q};

	inverter_reg noise0_latch(ss_en, ss_frz, ss_c2, ss_c3, clk, reset, T1, ~noise[0], noise0_latch_n);
	inverter_reg nor2_l(ss_en, ss_frz, ss_c3, ss_c4, clk, reset, T1, nor2, nor2_latch);

	wire pulse_clock = ~|{~T2, nor2_latch};

	assign noise = T2 ? noise_next : noise_latch;

	f_cell pulse_3
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c4), .ss_so(ss_c5),
		.clk        (clk),
		.reset      (reset),
		.tick       (pulse_clock),
		.s_n        (~pulse_bit),
		.r_n        (pulse_bit),
		.q          (pulse3_q),
		.q_n        (pulse3_qn)
	);
	f_cell pulse_2
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c5), .ss_so(ss_c6),
		.clk        (clk),
		.reset      (reset),
		.tick       (pulse_clock),
		.s_n        (pulse3_q),
		.r_n        (pulse3_qn),
		.q          (pulse2_q),
		.q_n        (pulse2_qn)
	);
	f_cell pulse_1
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c6), .ss_so(ss_c7),
		.clk        (clk),
		.reset      (reset),
		.tick       (pulse_clock),
		.s_n        (pulse2_q),
		.r_n        (pulse2_qn),
		.q          (pulse1_q),
		.q_n        (pulse1_qn)
	);
	f_cell pulse_0
	( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c7), .ss_so(ss_c8),
		.clk        (clk),
		.reset      (reset),
		.tick       (pulse_clock),
		.s_n        (pulse1_q),
		.r_n        (pulse1_qn),
		.q          (pulse0_q),
		.q_n        (pulse0_qn)
	);

	always_ff @(posedge clk) begin
		if (ss_en) {freq_next[4], freq_next[3], freq_next[2], freq_next[1], freq_next[0], freq_latch[4], freq_latch[3], freq_latch[2], freq_latch[1], freq_latch[0], noise_next[4], noise_next[3], noise_next[2], noise_next[1], noise_next[0], noise_latch[4], noise_latch[3], noise_latch[2], noise_latch[1], noise_latch[0]} <= {ss_c8, freq_next[4], freq_next[3], freq_next[2], freq_next[1], freq_next[0], freq_latch[4], freq_latch[3], freq_latch[2], freq_latch[1], freq_latch[0], noise_next[4], noise_next[3], noise_next[2], noise_next[1], noise_next[0], noise_latch[4], noise_latch[3], noise_latch[2], noise_latch[1], noise_latch[0]} >> 1;
		else if (!ss_frz) begin

		if (aud0)
			freq_next <= freq_div + 1'd1;
		if (aud1)
			freq_latch <= ~freq_div2 ? 5'd0 : freq_next;
		if (T1)
			noise_next <= {~nor8, noise_latch[4:1]};
		if (T2)
			noise_latch <= noise_next;

		if (reset) begin
			freq_next <= 0;
			freq_latch <= 0;
			noise_latch <= 0;
			noise_next <= 0;
		end

	end
	end
	assign ss_c9 = {freq_next[4], freq_next[3], freq_next[2], freq_next[1], freq_next[0], freq_latch[4], freq_latch[3], freq_latch[2], freq_latch[1], freq_latch[0], noise_next[4], noise_next[3], noise_next[2], noise_next[1], noise_next[0], noise_latch[4], noise_latch[3], noise_latch[2], noise_latch[1], noise_latch[0]};

	assign audio = ~pulse0_qn ? volume : 4'd0;

endmodule

module video_stabilize
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	input           clk,        // system clock
	input           reset,      // System reset
	input clock_t   oclk,       // Oscillator clock aka pixel clock or color clock
	input [1:0]     mode,       // 00 = smart, 01 = fixed, 10 = none
	input           vsync_in,   // Unmodified vsync signal
	input           vblank_in,  // Umodified vblank signal
	input           hsync_in,   // Unmodified hsync signal
	input           hblank_in,  // Hblank signal with applicable system delays
	output          vsync,
	output          vblank,
	output          auto_pal,
	output          f1           // Indicates Odd field of interlaced video
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c1;

	localparam ntsc_vb_end = 9'd19; // 19
	localparam pal_vb_end = 9'd23; // 23
	localparam ntsc_vb_start = 9'd240 + ntsc_vb_end; //9'd262;//9'd243;
	localparam pal_vb_start = 9'd288 + pal_vb_end; //9'd312;//9'd288;
	// Region detection, after Stella's FrameLayoutDetector. A 2600 image carries
	// no region field, so the frame length the program produces is the only
	// evidence - but one frame is not evidence. Frames are scored across
	// 262..312 lines, odd counts count half because a real PAL field is even,
	// startup and impossible frames are discarded, and the sums decide once.
	localparam [8:0] lines_absurd   = 9'd412;  // pal + 100, Stella's own cutoff
	localparam [5:0] score_span     = 6'd50;   // 312 - 262
	localparam [5:0] garbage_frames = 6'd8;    // skipped while the kernel settles
	localparam [5:0] detect_frames  = 6'd40;   // scored before the verdict stands


	logic [8:0] v_count, total_lines, vsync_line, vsync_end_line;
	logic [7:0] h_count;
	logic old_hblank, old_vblank, old_hsync, old_vsync;
	logic vsync_en, vsync_set, vblank_en, midline_sync, vsync_override, set_end;
	logic [7:0] vsync_count, vblank_count, lines_from_vs;
	logic [7:0] dot_count = 0;
	logic vsync_emulate;
	logic pal_mode;
	logic region_done;
	logic [5:0] region_frames;
	logic [11:0] pal_sum, ntsc_sum;

//	wire vblank_start = ~old_vblank && vblank_in;
//	wire vblank_end   = old_vblank && ~vblank_in;
	wire hblank_start = ~old_hblank && hblank_in;
	wire hblank_end   = old_hblank && ~hblank_in;
	wire vsync_start  = ~old_vsync && vsync_in;
//	wire vsync_end    = old_vsync && ~vsync_in;
//	wire hsync_start  = ~old_hsync && hsync_in;
//	wire hsync_end    = old_hsync && ~hsync_in;

	assign vblank = |mode ? vblank_in : vblank_en;
	assign vsync = |mode ? vsync_in : vsync_en;
	assign f1 = 1'b0; // |mode ? 1'b0 : midline_sync; // I could never make this work productively
	// Decided once and then frozen. region_select drives the PLL, a PLL
	// reconfiguration resets the core, and that restarts the very video measured
	// here - so the region may move at most once per loaded ROM. `reset` covers
	// the download, which is what re-arms detection for the next cart.
	assign auto_pal = pal_mode;

	// The frame that just ended is v_count lines long: 0 at 262 or below, the
	// full span at 312 or above, proportional between, halved when odd.
	wire [8:0] over_ntsc = (v_count > 9'd262) ? (v_count - 9'd262) : 9'd0;
	wire [5:0] score_raw = (over_ntsc >= {3'b0, score_span}) ? score_span : over_ntsc[5:0];
	wire [5:0] frame_score = v_count[0] ? {1'b0, score_raw[5:1]} : score_raw;

	always_ff @(posedge clk) begin
		if (ss_en) {old_hblank, old_vsync, total_lines[8], total_lines[7], total_lines[6], total_lines[5], total_lines[4], total_lines[3], total_lines[2], total_lines[1], total_lines[0], vsync_override, vsync_emulate, v_count[8], v_count[7], v_count[6], v_count[5], v_count[4], v_count[3], v_count[2], v_count[1], v_count[0], vblank_en, vsync_en, vsync_set, vsync_count[7], vsync_count[6], vsync_count[5], vsync_count[4], vsync_count[3], vsync_count[2], vsync_count[1], vsync_count[0], vsync_line[8], vsync_line[7], vsync_line[6], vsync_line[5], vsync_line[4], vsync_line[3], vsync_line[2], vsync_line[1], vsync_line[0], region_frames[5], region_frames[4], region_frames[3], region_frames[2], region_frames[1], region_frames[0], pal_sum[11], pal_sum[10], pal_sum[9], pal_sum[8], pal_sum[7], pal_sum[6], pal_sum[5], pal_sum[4], pal_sum[3], pal_sum[2], pal_sum[1], pal_sum[0], ntsc_sum[11], ntsc_sum[10], ntsc_sum[9], ntsc_sum[8], ntsc_sum[7], ntsc_sum[6], ntsc_sum[5], ntsc_sum[4], ntsc_sum[3], ntsc_sum[2], ntsc_sum[1], ntsc_sum[0], pal_mode, region_done} <= {ss_c0, old_hblank, old_vsync, total_lines[8], total_lines[7], total_lines[6], total_lines[5], total_lines[4], total_lines[3], total_lines[2], total_lines[1], total_lines[0], vsync_override, vsync_emulate, v_count[8], v_count[7], v_count[6], v_count[5], v_count[4], v_count[3], v_count[2], v_count[1], v_count[0], vblank_en, vsync_en, vsync_set, vsync_count[7], vsync_count[6], vsync_count[5], vsync_count[4], vsync_count[3], vsync_count[2], vsync_count[1], vsync_count[0], vsync_line[8], vsync_line[7], vsync_line[6], vsync_line[5], vsync_line[4], vsync_line[3], vsync_line[2], vsync_line[1], vsync_line[0], region_frames[5], region_frames[4], region_frames[3], region_frames[2], region_frames[1], region_frames[0], pal_sum[11], pal_sum[10], pal_sum[9], pal_sum[8], pal_sum[7], pal_sum[6], pal_sum[5], pal_sum[4], pal_sum[3], pal_sum[2], pal_sum[1], pal_sum[0], ntsc_sum[11], ntsc_sum[10], ntsc_sum[9], ntsc_sum[8], ntsc_sum[7], ntsc_sum[6], ntsc_sum[5], ntsc_sum[4], ntsc_sum[3], ntsc_sum[2], ntsc_sum[1], ntsc_sum[0], pal_mode, region_done} >> 1;
		else if (!ss_frz) begin
		old_hblank <= hblank_in;
		old_vsync <= vsync_in;
		if (&v_count) begin // Something is whack, emulate a signal
			total_lines <= 9'd262;
			vsync_override <= 1'd1;
			vsync_emulate <= 1'd1;
		end

		// Base new lines on the horizontal LFSR reset
		if (hblank_start) begin
			v_count <= v_count + 1'd1;
			if (v_count == (auto_pal ? pal_vb_end : ntsc_vb_end))
				vblank_en <= 0;
			// Pocket: end the window 1 line before the frame ends, not 4, so a
			// standard frame (262 / 312 lines) fills the whole 240 / 288 line
			// window. With 4 it gave 239 / 285: the Pocket's scaler then kept
			// its last rows from an earlier game, a flickering line at the bottom.
			if (v_count == (auto_pal ? pal_vb_start : ntsc_vb_start) || v_count == ((vsync_override ? vsync_line : total_lines) - 4'd1))
				vblank_en <= 1;

			if ((vsync_override && v_count == (vsync_line - 1'd1)) || vsync_set) begin
				if (vsync_emulate)
					v_count <= 0;
				vsync_en <= 1;
				vsync_set <= 0;
				vblank_en <= 1;
				if (~|vsync_count)
					vsync_count <= 3'd3;
			end
			if (|vsync_count) begin
				vsync_count <= vsync_count - 1'd1;
				if (vsync_count == 1)
					vsync_en <= 0;
			end
		end

		if (oclk.edge_p1)
			dot_count <= dot_count + 1'd1;
		if (hblank_end)
			dot_count <= 0;

		if (vsync_start) begin
			vsync_emulate <= 0;
			if (v_count != total_lines) begin
				vsync_set <= 1;
				if (total_lines - v_count < 3'd4) begin
					vsync_override <= 1;
					vsync_line <= v_count;
				end else if (v_count - total_lines < 3'd4) begin
					vsync_override <= 1;
					vsync_line <= total_lines;
				end else begin
					vsync_override <= 0;
				end
			end
			if (~vsync_override) begin
				vsync_set <= 1;
			end
			v_count <= 0;
			total_lines <= v_count;

			if (!region_done) begin
				region_frames <= region_frames + 1'd1;
				// Startup frames and impossible ones are not evidence.
				if (region_frames >= garbage_frames && v_count <= lines_absurd) begin
					pal_sum  <= pal_sum  + {6'b0, frame_score};
					ntsc_sum <= ntsc_sum + {6'b0, (score_span - frame_score)};
				end
				// One frame past the window, so the last score is counted.
				if (region_frames == garbage_frames + detect_frames) begin
					pal_mode <= pal_sum > ntsc_sum;
					region_done <= 1'b1;
				end
			end

			// if (dot_count > 15 && dot_count < 145) // Vsync outside of hblank can be considered invoking interlaced resolutions
			// 	midline_sync <= 1;
			// else
			// 	midline_sync <= 0;
		end

		if (reset) begin
			vsync_emulate <= 0;
			dot_count <= 0;
			vsync_set <= 0;
			vsync_line <= 0;
			vsync_override <= 0;
			total_lines <= 9'd262;
			pal_mode <= 1'b0;
			region_done <= 1'b0;
			region_frames <= 6'd0;
			pal_sum <= 12'd0;
			ntsc_sum <= 12'd0;
			v_count <= 0;
			vblank_en <= 1;
			vsync_en <= 0;
		end

	end
	end
	assign ss_c1 = {old_hblank, old_vsync, total_lines[8], total_lines[7], total_lines[6], total_lines[5], total_lines[4], total_lines[3], total_lines[2], total_lines[1], total_lines[0], vsync_override, vsync_emulate, v_count[8], v_count[7], v_count[6], v_count[5], v_count[4], v_count[3], v_count[2], v_count[1], v_count[0], vblank_en, vsync_en, vsync_set, vsync_count[7], vsync_count[6], vsync_count[5], vsync_count[4], vsync_count[3], vsync_count[2], vsync_count[1], vsync_count[0], vsync_line[8], vsync_line[7], vsync_line[6], vsync_line[5], vsync_line[4], vsync_line[3], vsync_line[2], vsync_line[1], vsync_line[0], region_frames[5], region_frames[4], region_frames[3], region_frames[2], region_frames[1], region_frames[0], pal_sum[11], pal_sum[10], pal_sum[9], pal_sum[8], pal_sum[7], pal_sum[6], pal_sum[5], pal_sum[4], pal_sum[3], pal_sum[2], pal_sum[1], pal_sum[0], ntsc_sum[11], ntsc_sum[10], ntsc_sum[9], ntsc_sum[8], ntsc_sum[7], ntsc_sum[6], ntsc_sum[5], ntsc_sum[4], ntsc_sum[3], ntsc_sum[2], ntsc_sum[1], ntsc_sum[0], pal_mode, region_done};

endmodule

/////////////////////////////////////////////////////////////////////////////////////////
module TIA
(
	input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,
	// Original Pins
	input           clk,
	output          phi0,
	input           phi2,
	output logic    phi1,
	input           RW_n,
	output logic    rdy,
	input  [5:0]    addr,
	input  [7:0]    d_in,
	output logic [7:0] d_out,
	output logic [7:0] d_out_oe, // Which of D7:D0 the chip is actually driving
	input  [3:0]    i,     // On real hardware, these would be ADC pins. i0..3
	output [3:0]    i_out,
	input           i4,
	input           i5,
	output [3:0]    aud0,
	output [3:0]    aud1,
	output [3:0]    col,
	output [2:0]    lum,
	output          BLK_n,
	output          sync,
	input           cs0_n,
	input           cs2_n,

	// Abstractions
	input           rst,
	input           ce,     // Clock enable for CLK generation only, should be 2x normal TIA clk
	output          video_ce,
	output          vblank,
	output          hblank,
	output          hgap,
	output          vsync,
	output          hsync,
	input           phi1_in,
	// phi0/phi1 above are the chip's pins: in 7800 mode they echo the pair
	// MARIA supplies, which is what the silicon does and what
	// tia_clock_boundary_tb guards. Feeding that echo back to the core's phase
	// controller closes a combinational ring, so the controller reads these
	// instead - the divider's own phase, with no path from phi1_in/phi2. In
	// 2600 mode, the only mode the controller selects the TIA in, they are the
	// same signals.
	output          phi0_gen,
	output logic    phi1_gen,
	input           is_7800,
	input           decomb,
	output logic    cart_ce,
	output logic    [9:0] row,
	output logic    [9:0] column,
	output          is_pal,
	output          is_f1,
	input           stabilize,
	output  [3:0]   paddle_read // Helper to let us autodetect paddles
);
	// save states: scan chain (tools/savestate/scan_insert.py)
	wire ss_c0, ss_c1, ss_c2, ss_c3, ss_c4, ss_c5, ss_c6, ss_c7, ss_c8, ss_c9, ss_c10, ss_c11, ss_c12, ss_c13, ss_c14, ss_c15, ss_c16, ss_c17, ss_c18, ss_c19, ss_c20, ss_c21, ss_c22;
	assign ss_c0 = ss_si;
	assign ss_so = ss_c22;


logic [7:0] wreg[64]; // Write registers. Only 44 are used.
logic [7:0] rreg[16]; // Read registers.

logic cs; // Chip Select (cs1 and 3 were NC)
logic wsync,rsync,resp0,resp1,resm0,resm1,resbl,hmove,hmclr,cxclr; // Strobe register signals
logic [3:0] color_select;
logic p0, p1, m0, m1, bl, pf; // Current object active flags
logic aclk0, aclk1, rhb, shb, cnt, cntd; // horizontal triggers
logic sec;
logic hblank_o, vblank_o, vsync_o, hgap_o; // Original video timing signals
logic msrst0, msrst1; // Missile/player reset signals
logic p0ec, p1ec, m0ec, m1ec, blec; // HMOVE Extra clock signals
logic rsynl, rsynd; // Reset synchronization signals
logic motck; // Motion Clock
logic clkp;  // Pixel Clock
logic hblank_d;
logic blank;
logic phi2_delay;

logic old_hblank, old_vsync;
logic [1:0] vsync_count;
logic hgap_1;

clock_t hclk;
clock_t pclk;
clock_t oclk;

assign phi0 = pclk.edge_p2;
assign phi1 = pclk.edge_p1;
assign cs = ~cs0_n && ~cs2_n;
assign video_ce = oclk.edge_p2;
assign BLK_n = blank;
assign sync = ~(hsync || vsync);
assign vsync_o = wreg[VSYNC][1];
assign vblank_o = wreg[VBLANK][1];
assign cart_ce = oclk.edge_p2;
assign motck = ~oclk.clock & ~hblank_d;
assign clkp = ~oclk.clock;

f_cell hgap1_out
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c0), .ss_so(ss_c1),
	.clk        (clk),
	.reset      (rst),
	.tick       (oclk.level_p1),
	.s_n        (~hgap_o),
	.r_n        (hgap_o),
	.q          (hgap_1),
	.q_n        ()
);

f_cell hgap_out
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c1), .ss_so(ss_c2),
	.clk        (clk),
	.reset      (rst),
	.tick       (oclk.level_p1),
	.s_n        (~hgap_1),
	.r_n        (hgap_1),
	.q          (hgap),
	.q_n        ()
);

f_cell hblank_out
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c2), .ss_so(ss_c3),
	.clk        (clk),
	.reset      (rst),
	.tick       (oclk.level_p1),
	.s_n        (~hblank_o),
	.r_n        (hblank_o),
	.q          (hblank),
	.q_n        ()
);

f_cell blank_out
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c3), .ss_so(ss_c4),
	.clk        (clk),
	.reset      (rst),
	.tick       (oclk.level_p1),
	.s_n        (~(~hblank_o && ~vblank_o)),
	.r_n        ((~hblank_o && ~vblank_o)),
	.q          (),
	.q_n        (blank)
);

video_stabilize stab
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c4), .ss_so(ss_c5),
	.clk        (clk),
	.reset      (rst),
	.oclk       (oclk),
	.mode       (stabilize),
	.vsync_in   (vsync_o),
	.vblank_in  (vblank_o),
	.hsync_in   (hsync),
	.hblank_in  (hgap),
	.vsync      (vsync),
	.vblank     (vblank),
	.auto_pal   (is_pal),
	.f1         (is_f1)
);


always_ff @(posedge clk) begin
		if (ss_en) {hblank_d} <= {ss_c5, hblank_d} >> 1;
		else if (!ss_frz) begin
	old_hblank <= hblank_o;
	old_vsync <= vsync_o;
	hblank_d <= hblank_o;
	if (oclk.edge_p1)
		column <= column + 1'd1;
	if (old_hblank && !hblank_o) begin
		column <= 0;
		row <= row + 1'd1;
	end
	if (old_vsync && !vsync_o)
		row <= 0;
end
	end
	assign ss_c6 = {hblank_d};

// Reads and writes
// NOTE: A realistic attempt at bus stuffing might need the registers to be set in a combinational
// way, but otherwise using the clock enable signal keeps the timings valid.
always_ff @(posedge clk) begin
		if (ss_en) {phi2_delay, i_out[1], wreg[63][7], wreg[63][6], wreg[63][5], wreg[63][4], wreg[63][3], wreg[63][2], wreg[63][1], wreg[63][0], wreg[62][7], wreg[62][6], wreg[62][5], wreg[62][4], wreg[62][3], wreg[62][2], wreg[62][1], wreg[62][0], wreg[61][1], wreg[41][1], wreg[40][1], wreg[39][0], wreg[38][0], wreg[37][0], wreg[36][7], wreg[36][6], wreg[36][5], wreg[36][4], wreg[35][7], wreg[35][6], wreg[35][5], wreg[35][4], wreg[34][7], wreg[34][6], wreg[34][5], wreg[34][4], wreg[33][7], wreg[33][6], wreg[33][5], wreg[33][4], wreg[32][7], wreg[32][6], wreg[32][5], wreg[32][4], wreg[31][1], wreg[30][1], wreg[29][1], wreg[28][7], wreg[28][6], wreg[28][5], wreg[28][4], wreg[28][3], wreg[28][2], wreg[28][1], wreg[28][0], wreg[27][7], wreg[27][6], wreg[27][5], wreg[27][4], wreg[27][3], wreg[27][2], wreg[27][1], wreg[27][0], wreg[26][3], wreg[26][2], wreg[26][1], wreg[26][0], wreg[25][3], wreg[25][2], wreg[25][1], wreg[25][0], wreg[24][4], wreg[24][3], wreg[24][2], wreg[24][1], wreg[24][0], wreg[23][4], wreg[23][3], wreg[23][2], wreg[23][1], wreg[23][0], wreg[22][3], wreg[22][2], wreg[22][1], wreg[22][0], wreg[21][3], wreg[21][2], wreg[21][1], wreg[21][0], wreg[15][7], wreg[15][6], wreg[15][5], wreg[15][4], wreg[15][3], wreg[15][2], wreg[15][1], wreg[15][0], wreg[14][7], wreg[14][6], wreg[14][5], wreg[14][4], wreg[14][3], wreg[14][2], wreg[14][1], wreg[14][0], wreg[13][7], wreg[13][6], wreg[13][5], wreg[13][4], wreg[12][3], wreg[11][3], wreg[10][5], wreg[10][4], wreg[10][2], wreg[10][1], wreg[10][0], wreg[9][7], wreg[9][6], wreg[9][5], wreg[9][4], wreg[9][3], wreg[9][2], wreg[9][1], wreg[8][7], wreg[8][6], wreg[8][5], wreg[8][4], wreg[8][3], wreg[8][2], wreg[8][1], wreg[7][7], wreg[7][6], wreg[7][5], wreg[7][4], wreg[7][3], wreg[7][2], wreg[7][1], wreg[6][7], wreg[6][6], wreg[6][5], wreg[6][4], wreg[6][3], wreg[6][2], wreg[6][1], wreg[5][5], wreg[5][4], wreg[5][2], wreg[5][1], wreg[5][0], wreg[4][5], wreg[4][4], wreg[4][2], wreg[4][1], wreg[4][0], wreg[1][7], wreg[1][6], wreg[1][1], wreg[0][1], hmclr, cxclr} <= {ss_c6, phi2_delay, i_out[1], wreg[63][7], wreg[63][6], wreg[63][5], wreg[63][4], wreg[63][3], wreg[63][2], wreg[63][1], wreg[63][0], wreg[62][7], wreg[62][6], wreg[62][5], wreg[62][4], wreg[62][3], wreg[62][2], wreg[62][1], wreg[62][0], wreg[61][1], wreg[41][1], wreg[40][1], wreg[39][0], wreg[38][0], wreg[37][0], wreg[36][7], wreg[36][6], wreg[36][5], wreg[36][4], wreg[35][7], wreg[35][6], wreg[35][5], wreg[35][4], wreg[34][7], wreg[34][6], wreg[34][5], wreg[34][4], wreg[33][7], wreg[33][6], wreg[33][5], wreg[33][4], wreg[32][7], wreg[32][6], wreg[32][5], wreg[32][4], wreg[31][1], wreg[30][1], wreg[29][1], wreg[28][7], wreg[28][6], wreg[28][5], wreg[28][4], wreg[28][3], wreg[28][2], wreg[28][1], wreg[28][0], wreg[27][7], wreg[27][6], wreg[27][5], wreg[27][4], wreg[27][3], wreg[27][2], wreg[27][1], wreg[27][0], wreg[26][3], wreg[26][2], wreg[26][1], wreg[26][0], wreg[25][3], wreg[25][2], wreg[25][1], wreg[25][0], wreg[24][4], wreg[24][3], wreg[24][2], wreg[24][1], wreg[24][0], wreg[23][4], wreg[23][3], wreg[23][2], wreg[23][1], wreg[23][0], wreg[22][3], wreg[22][2], wreg[22][1], wreg[22][0], wreg[21][3], wreg[21][2], wreg[21][1], wreg[21][0], wreg[15][7], wreg[15][6], wreg[15][5], wreg[15][4], wreg[15][3], wreg[15][2], wreg[15][1], wreg[15][0], wreg[14][7], wreg[14][6], wreg[14][5], wreg[14][4], wreg[14][3], wreg[14][2], wreg[14][1], wreg[14][0], wreg[13][7], wreg[13][6], wreg[13][5], wreg[13][4], wreg[12][3], wreg[11][3], wreg[10][5], wreg[10][4], wreg[10][2], wreg[10][1], wreg[10][0], wreg[9][7], wreg[9][6], wreg[9][5], wreg[9][4], wreg[9][3], wreg[9][2], wreg[9][1], wreg[8][7], wreg[8][6], wreg[8][5], wreg[8][4], wreg[8][3], wreg[8][2], wreg[8][1], wreg[7][7], wreg[7][6], wreg[7][5], wreg[7][4], wreg[7][3], wreg[7][2], wreg[7][1], wreg[6][7], wreg[6][6], wreg[6][5], wreg[6][4], wreg[6][3], wreg[6][2], wreg[6][1], wreg[5][5], wreg[5][4], wreg[5][2], wreg[5][1], wreg[5][0], wreg[4][5], wreg[4][4], wreg[4][2], wreg[4][1], wreg[4][0], wreg[1][7], wreg[1][6], wreg[1][1], wreg[0][1], hmclr, cxclr} >> 1;
		else if (!ss_frz) begin
	phi2_delay <= pclk.level_p2; // Phi2 analog delay
	i_out <= {4{~wreg[VBLANK][7]}};
	if (pclk.edge_p2 || pclk.level_p2) begin
		if (cs && ~RW_n && addr <= 6'h2C) begin
			wreg[addr] <= d_in;

			if (addr == GRP0)
				wreg[GRP1O] <= wreg[GRP1];
			if (addr == GRP1) begin
				wreg[GRP0O] <= wreg[GRP0];
				wreg[ENBLO] <= wreg[ENABL];
			end
		end
	end

	// FIXME: Due to analog delays in the chip, it appears these signals need roughly a
	// 50ish nanosecond delay. This may need adaptation if you use a different speed clock.
	{hmclr, cxclr} <= '0;
	if (~RW_n && phi2_delay && cs) begin
		case(addr)
			HMCLR: hmclr <= 1;
			CXCLR: cxclr <= 1;
			default: ;
		endcase
	end

	if (hmclr) begin
		wreg[HMP0] <= 0;
		wreg[HMP1] <= 0;
		wreg[HMM0] <= 0;
		wreg[HMM1] <= 0;
		wreg[HMBL] <= 0;
	end

	if (rst) begin
		wreg <= '{64{8'h00}};
		wreg[VBLANK][1] <= 1;
	end
end
	end
	assign ss_c7 = {phi2_delay, i_out[1], wreg[63][7], wreg[63][6], wreg[63][5], wreg[63][4], wreg[63][3], wreg[63][2], wreg[63][1], wreg[63][0], wreg[62][7], wreg[62][6], wreg[62][5], wreg[62][4], wreg[62][3], wreg[62][2], wreg[62][1], wreg[62][0], wreg[61][1], wreg[41][1], wreg[40][1], wreg[39][0], wreg[38][0], wreg[37][0], wreg[36][7], wreg[36][6], wreg[36][5], wreg[36][4], wreg[35][7], wreg[35][6], wreg[35][5], wreg[35][4], wreg[34][7], wreg[34][6], wreg[34][5], wreg[34][4], wreg[33][7], wreg[33][6], wreg[33][5], wreg[33][4], wreg[32][7], wreg[32][6], wreg[32][5], wreg[32][4], wreg[31][1], wreg[30][1], wreg[29][1], wreg[28][7], wreg[28][6], wreg[28][5], wreg[28][4], wreg[28][3], wreg[28][2], wreg[28][1], wreg[28][0], wreg[27][7], wreg[27][6], wreg[27][5], wreg[27][4], wreg[27][3], wreg[27][2], wreg[27][1], wreg[27][0], wreg[26][3], wreg[26][2], wreg[26][1], wreg[26][0], wreg[25][3], wreg[25][2], wreg[25][1], wreg[25][0], wreg[24][4], wreg[24][3], wreg[24][2], wreg[24][1], wreg[24][0], wreg[23][4], wreg[23][3], wreg[23][2], wreg[23][1], wreg[23][0], wreg[22][3], wreg[22][2], wreg[22][1], wreg[22][0], wreg[21][3], wreg[21][2], wreg[21][1], wreg[21][0], wreg[15][7], wreg[15][6], wreg[15][5], wreg[15][4], wreg[15][3], wreg[15][2], wreg[15][1], wreg[15][0], wreg[14][7], wreg[14][6], wreg[14][5], wreg[14][4], wreg[14][3], wreg[14][2], wreg[14][1], wreg[14][0], wreg[13][7], wreg[13][6], wreg[13][5], wreg[13][4], wreg[12][3], wreg[11][3], wreg[10][5], wreg[10][4], wreg[10][2], wreg[10][1], wreg[10][0], wreg[9][7], wreg[9][6], wreg[9][5], wreg[9][4], wreg[9][3], wreg[9][2], wreg[9][1], wreg[8][7], wreg[8][6], wreg[8][5], wreg[8][4], wreg[8][3], wreg[8][2], wreg[8][1], wreg[7][7], wreg[7][6], wreg[7][5], wreg[7][4], wreg[7][3], wreg[7][2], wreg[7][1], wreg[6][7], wreg[6][6], wreg[6][5], wreg[6][4], wreg[6][3], wreg[6][2], wreg[6][1], wreg[5][5], wreg[5][4], wreg[5][2], wreg[5][1], wreg[5][0], wreg[4][5], wreg[4][4], wreg[4][2], wreg[4][1], wreg[4][0], wreg[1][7], wreg[1][6], wreg[1][1], wreg[0][1], hmclr, cxclr};

// The bus drivers are asynchronous. Their stored sources live in rreg, but
// registering the pin value on phase 2 makes it arrive after the CPU closes
// its data latch on that same edge.
// D5:D0 have no drivers at all in the part, and the collision registers and
// the trigger inputs reach only D7, so most reads leave part of the byte to
// whatever charge the bus already carries. d_out_oe says which bits are real;
// the system bus fills the rest.
always_comb begin
	d_out = 8'h00;
	d_out_oe = 8'h00;
	if (cs && RW_n) begin
		if (addr[3:0] == INPT4 && ~wreg[VBLANK][6]) begin
			d_out[7] = i4;
			d_out_oe = 8'b1000_0000;
		end else if (addr[3:0] == INPT5 && ~wreg[VBLANK][6]) begin
			d_out[7] = i5;
			d_out_oe = 8'b1000_0000;
		end else if (~&addr[3:1]) begin // $xE and $xF decode to nothing
			if (addr[3] || addr[3:0] == CXBLPF) begin
				d_out[7] = rreg[addr[3:0]][7];
				d_out_oe = 8'b1000_0000;
			end else begin
				d_out[7:6] = rreg[addr[3:0]][7:6];
				d_out_oe = 8'b1100_0000;
			end
		end
	end
end

// "Strobe" registers have an immediate effect
always_comb begin
	{wsync,rsync,resp0,resp1,resm0,resm1,resbl,hmove} = '0;
	if (~RW_n && pclk.level_p2 && cs) begin
		case(addr)
			WSYNC: wsync = 1;
			RSYNC: rsync = 1;
			RESP0: resp0 = 1;
			RESP1: resp1 = 1;
			RESM0: resm0 = 1;
			RESM1: resm1 = 1;
			RESBL: resbl = 1;
			HMOVE: hmove = 1;
			default: ;
		endcase
	end
	paddle_read = '0;
	if (RW_n && pclk.level_p2 && cs) begin
		paddle_read[0] = (addr[3:0] == INPT0);
		paddle_read[1] = (addr[3:0] == INPT1);
		paddle_read[2] = (addr[3:0] == INPT2);
		paddle_read[3] = (addr[3:0] == INPT3);
	end
end

// Submodules
clockgen clockgen
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c7), .ss_so(ss_c8),
	.clk        (clk),
	.is_7800    (is_7800),
	.ce         (ce),
	.reset      (rst),
	.rsync      (rsync),
	.rsynd      (rsynd),
	.rsynl      (rsynl),
	.pext_1     (phi1_in),
	.pext_2     (phi2),
	.pclk       (pclk),
	.hclk       (hclk),
	.oclk       (oclk),
	.phi0_ll    (),  // reference divider, tied off - see clockgen
	.pclk_gen_edge_p1 (phi1_gen),
	.pclk_gen_edge_p2 (phi0_gen)
);

horiz_gen h_gen
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c8), .ss_so(ss_c9),
	.clk        (clk),
	.rst        (rst),
	.hclk       (hclk),
	.rsynl      (rsynl),
	.rsynd      (rsynd),
	.sec        (sec),
	.hsync      (hsync),
	.hgap       (hgap_o),
	.hblank     (hblank_o),
	.cntd       (cntd),
	.cnt        (cnt),
	.aud0       (aclk0),
	.aud1       (aclk1),
	.shb        (shb),
	.rhb        (rhb),
	.CB         ()   // colour burst gate, unused outside horiz_gen
);

playfield playfield
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c9), .ss_so(ss_c10),
	.clk        (clk),
	.reset      (rst),
	.clkp       (clkp),
	.hclk       (hclk),
	.rhb        (rhb),
	.reflect    (wreg[CTRLPF][0]),
	.cnt        (cnt),
	.pfc        ({wreg[PF2], wreg[PF1], wreg[PF0][7:4]}),
	.pf         (pf)
);

hmove_gen hmv
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c10), .ss_so(ss_c11),
	.clk        (clk),
	.reset      (rst),
	.sec        (sec),
	.hclk       (hclk),
	.oclk       (oclk),
	.pclk       (pclk),
	.hmove      (hmove),
	.hblank     (hblank_o),
	.p0_m       (hmclr ? 4'd0 : wreg[HMP0][7:4]),
	.p1_m       (hmclr ? 4'd0 : wreg[HMP1][7:4]),
	.m0_m       (hmclr ? 4'd0 : wreg[HMM0][7:4]),
	.m1_m       (hmclr ? 4'd0 : wreg[HMM1][7:4]),
	.bl_m       (hmclr ? 4'd0 : wreg[HMBL][7:4]),
	.p0_mclk    (p0ec),
	.p1_mclk    (p1ec),
	.m0_mclk    (m0ec),
	.m1_mclk    (m1ec),
	.bl_mclk    (blec)
);

player pl1 ( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c11), .ss_so(ss_c12),
	.clk        (clk),
	.reset      (rst),
	.clkp       (clkp),
	.motck      (motck),
	.pec        (p0ec),
	.pre        (resp0),
	.pvdel      (wreg[VDELP0][0]),
	.m2pr       (wreg[RESMP0][1]),
	.pref       (wreg[REFP0][3]),
	.nusiz      (wreg[NUSIZ0][5:0]),
	.grpnew     (wreg[GRP0]),
	.grpold     (wreg[GRP0O]),
	.msrst      (msrst0),
	.p          (p0)
);

player pl2 ( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c12), .ss_so(ss_c13),
	.clk        (clk),
	.reset      (rst),
	.clkp       (clkp),
	.motck      (motck),
	.pec        (p1ec),
	.pre        (resp1),
	.pvdel      (wreg[VDELP1][0]),
	.m2pr       (wreg[RESMP1][1]),
	.pref       (wreg[REFP1][3]),
	.nusiz      (wreg[NUSIZ1][5:0]),
	.grpnew     (wreg[GRP1]),
	.grpold     (wreg[GRP1O]),
	.msrst      (msrst1),
	.p          (p1)
);

missile mis0 ( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c13), .ss_so(ss_c14),
	.clk        (clk),
	.reset      (rst),
	.clkp       (clkp),
	.motck      (motck),
	.mec        (m0ec),
	.mre        (resm0 || (wreg[RESMP0][1] && msrst0)),
	.men        (wreg[ENAM0][1] && ~wreg[RESMP0][1]),
	.nusiz      (wreg[NUSIZ0][5:0]),
	.m          (m0)
);

missile mis1 ( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c14), .ss_so(ss_c15),
	.clk        (clk),
	.reset      (rst),
	.clkp       (clkp),
	.motck      (motck),
	.mec        (m1ec),
	.mre        (resm1 || (wreg[RESMP1][1] && msrst1)),
	.men        (wreg[ENAM1][1] && ~wreg[RESMP1][1]),
	.nusiz      (wreg[NUSIZ1][5:0]),
	.m          (m1)
);

ball bal ( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c15), .ss_so(ss_c16),
	.clk        (clk),
	.reset      (rst),
	.clkp       (clkp),
	.motck      (motck),
	.blec       (blec),
	.blre       (resbl),
	.blen       (wreg[ENABL][1]),
	.blen_o     (wreg[ENBLO][1]),
	.blvd       (wreg[VDELBL][0]),
	.blsiz      (wreg[CTRLPF][5:4]),
	.bl         (bl)
);

priority_encoder prior
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c16), .ss_so(ss_c17),
	.clk        (clk),
	.p0         (p0),
	.m0         (m0),
	.p1         (p1),
	.m1         (m1),
	.bl         (bl),
	.pf         (pf),
	.cntd       (cntd),
	.blank      (blank),
	.pfp        (wreg[CTRLPF][2]),
	.score      (wreg[CTRLPF][1]),
	.col_select (color_select)
);

audio_channel audio0
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c17), .ss_so(ss_c18),
	.clk        (clk),
	.reset      (rst),
	.aud0       (aclk0),
	.aud1       (aclk1),
	.volume     (wreg[AUDV0][3:0]),
	.freq       (wreg[AUDF0][4:0]),
	.audc       (wreg[AUDC0][3:0]),
	.audio      (aud0)
);

audio_channel audio1
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c18), .ss_so(ss_c19),
	.clk        (clk),
	.reset      (rst),
	.aud0       (aclk0),
	.aud1       (aclk1),
	.volume     (wreg[AUDV1][3:0]),
	.freq       (wreg[AUDF1][4:0]),
	.audc       (wreg[AUDC1][3:0]),
	.audio      (aud1)
);

// Select the correct output register
always_ff @(posedge clk) begin
		if (ss_en) {col[3], col[2], col[1], col[0], lum[2], lum[1], lum[0]} <= {ss_c19, col[3], col[2], col[1], col[0], lum[2], lum[1], lum[0]} >> 1;
		else if (!ss_frz) if (oclk.edge_p1) begin
	if ((hblank || vblank_o))
		{col, lum} <= decomb ? wreg[COLUBK][7:1] : 7'h0; // Blank non-visible areas
	else begin
		case (color_select)
			4'b0001: {col, lum} <= wreg[COLUP0][7:1];
			4'b0010: {col, lum} <= wreg[COLUP1][7:1];
			4'b0100: {col, lum} <= wreg[COLUPF][7:1];
			4'b1000: {col, lum} <= wreg[COLUBK][7:1];
			default: {col, lum} <= 7'd0;
		endcase
	end
end
	end
	assign ss_c20 = {col[3], col[2], col[1], col[0], lum[2], lum[1], lum[0]};

// WSYNC register controls the RDY signal to the CPU. It is cleared at the start of hblank.
wire rdy_q;
assign rdy = ~rdy_q;
sr_latch in_sr
( .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c20), .ss_so(ss_c21),
	.clk        (clk),
	.reset      (rst),
	.r          (shb),
	.s          (wsync),
	.q          (rdy_q),
	.q_n        ()
);

// Calculate the collisions

always_ff @(posedge clk) begin
		if (ss_en) {rreg[13][7], rreg[12][7], rreg[11][7], rreg[10][7], rreg[9][7], rreg[8][7], rreg[7][7], rreg[7][6], rreg[6][7], rreg[5][7], rreg[5][6], rreg[4][7], rreg[4][6], rreg[3][7], rreg[3][6], rreg[2][7], rreg[2][6], rreg[1][7], rreg[1][6], rreg[0][7], rreg[0][6]} <= {ss_c21, rreg[13][7], rreg[12][7], rreg[11][7], rreg[10][7], rreg[9][7], rreg[8][7], rreg[7][7], rreg[7][6], rreg[6][7], rreg[5][7], rreg[5][6], rreg[4][7], rreg[4][6], rreg[3][7], rreg[3][6], rreg[2][7], rreg[2][6], rreg[1][7], rreg[1][6], rreg[0][7], rreg[0][6]} >> 1;
		else if (!ss_frz) begin : read_reg_block
	if (cxclr) begin
		{rreg[CXM0P][7:6], rreg[CXM1P][7:6], rreg[CXP0FB][7:6],
			rreg[CXP1FB][7:6], rreg[CXM0FB][7:6], rreg[CXM1FB][7:6],
			rreg[CXBLPF][7:6], rreg[CXPPMM][7:6]} <= '0;
	end else if (oclk.level_p2 && ~vblank_o) begin
		rreg[CXM0P][7:6]  <= (rreg[CXM0P][7:6]  | {(m0 && p1), (m0 && p0)});
		rreg[CXM1P][7:6]  <= (rreg[CXM1P][7:6]  | {(m1 && p0), (m1 && p1)});
		rreg[CXP0FB][7:6] <= (rreg[CXP0FB][7:6] | {(p0 && pf), (p0 && bl)});
		rreg[CXP1FB][7:6] <= (rreg[CXP1FB][7:6] | {(p1 && pf), (p1 && bl)});
		rreg[CXM0FB][7:6] <= (rreg[CXM0FB][7:6] | {(m0 && pf), (m0 && bl)});
		rreg[CXM1FB][7:6] <= (rreg[CXM1FB][7:6] | {(m1 && pf), (m1 && bl)});
		rreg[CXBLPF][7:6] <= (rreg[CXBLPF][7:6] | {(bl && pf), 1'b0});
		rreg[CXPPMM][7:6] <= (rreg[CXPPMM][7:6] | {(p0 && p1), (m0 && m1)});
	end

	for (logic [2:0] x = 0; x < 4; x = x + 1'd1) begin
		rreg[{2'b10, x[1:0]}][7] <= wreg[VBLANK][7] ? 1'b0 : i[x[1:0]];
	end

	if (~wreg[VBLANK][6]) begin
		{rreg[INPT4][7], rreg[INPT5][7]} <= '1;
	end else begin
		if (~i4)
			rreg[INPT4][7] <= 0;
		if (~i5)
			rreg[INPT5][7] <= 0;
	end

	if (pclk.edge_p2 && cs && ~RW_n) begin
		if (addr == VBLANK && d_in[6]) begin
			{rreg[INPT4][7], rreg[INPT5][7]} <= '1;
		end
	end

	if (rst) begin
		rreg <= '{16{8'h00}};
	end
end
	end
	assign ss_c22 = {rreg[13][7], rreg[12][7], rreg[11][7], rreg[10][7], rreg[9][7], rreg[8][7], rreg[7][7], rreg[7][6], rreg[6][7], rreg[5][7], rreg[5][6], rreg[4][7], rreg[4][6], rreg[3][7], rreg[3][6], rreg[2][7], rreg[2][6], rreg[1][7], rreg[1][6], rreg[0][7], rreg[0][6]};

endmodule
