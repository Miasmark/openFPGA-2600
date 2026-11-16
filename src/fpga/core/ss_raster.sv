`default_nettype none

//------------------------------------------------------------------------------
// The substitute raster (SAVESTATE.md 2.2): the Pocket's sync comes straight
// from the TIA, so while the machine is frozen (hold) this module sends a
// raster of its own, learned from the outputs while the machine runs: each
// line's length and HSync width and HBlank, each frame's length (clk_sys from
// VSync rise to VSync rise) and VSync width and VBlank, the pixel strobe's
// phase in the line. Its counters continue the picture where it stopped, and
// resume_ok rises one clock before they reach that position again, so the
// machine resumes into a regular frame. While the machine runs the outputs
// are its own, unchanged.
//
// SPDX-License-Identifier: MIT
//------------------------------------------------------------------------------
module ss_raster (
	input  wire logic clk,
	input  wire logic hold,
	input  wire logic hs, vs, hb, vb, ce,     // the picture's
	output logic      o_hs, o_vs, o_hb, o_vb, o_ce,
	output logic      resume_ok
);
	/* verilator lint_off PROCASSINIT */  // power-up values (DEVELOPING.md, "Power-up values")
	logic        hs_q = 1'b0, vs_q = 1'b0, hb_q = 1'b0, vb_q = 1'b0;
	logic  [9:0] ho = 10'd0;                  // the next clock's offset from the HSync rise
	logic [19:0] fo = 20'd0;                  // the next clock's offset from the VSync rise
	logic  [9:0] l_h = 10'd0, hs_w = 10'd0, hb_on = 10'd0, hb_off = 10'd0;
	logic [19:0] l_f = 20'd0, vs_w = 20'd0, vb_on = 20'd0, vb_off = 20'd0, f_stop = 20'd0;
	logic  [1:0] ce_ph = 2'd0;
	/* verilator lint_on PROCASSINIT */
	wire hs_rise = hs && !hs_q;
	wire vs_rise = vs && !vs_q;
	// this clock's offsets: the picture's while it runs, the counters' while held
	wire  [9:0] hc = (!hold && hs_rise) ? 10'd0 : ho;
	wire [19:0] fc = (!hold && vs_rise) ? 20'd0 : fo;
	function automatic logic in_arc(input logic [19:0] x, input logic [19:0] a, input logic [19:0] b);
		in_arc = (a <= b) ? (x >= a && x < b) : (x >= a || x < b);
	endfunction
	always_ff @(posedge clk) begin
		if (!hold) begin
			hs_q <= hs; vs_q <= vs; hb_q <= hb; vb_q <= vb;
			if (hs_rise) l_h <= ho;               // the clocks since the last rise
			if (!hs && hs_q) hs_w <= hc;
			if (hb && !hb_q) hb_on <= hc;
			if (!hb && hb_q) hb_off <= hc;
			if (vs_rise) l_f <= fo;
			if (!vs && vs_q) vs_w <= fc;
			if (vb && !vb_q) vb_on <= fc;
			if (!vb && vb_q) vb_off <= fc;
			if (ce) ce_ph <= hc[1:0];
			f_stop <= fc;                         // where the picture stopped, if it stops now
			ho <= hc + 10'd1;
			fo <= fc + 20'd1;
		end else begin
			ho <= (l_h == 10'd0 || hc + 10'd1 >= l_h) ? 10'd0 : hc + 10'd1;
			fo <= (l_f == 20'd0 || fc + 20'd1 >= l_f) ? 20'd0 : fc + 20'd1;
		end
	end
	assign o_hs = hold ? (hc < hs_w) : hs;
	assign o_hb = hold ? in_arc({10'd0, hc}, {10'd0, hb_on}, {10'd0, hb_off}) : hb;
	assign o_vs = hold ? (fc < vs_w) : vs;
	assign o_vb = hold ? in_arc(fc, vb_on, vb_off) : vb;
	assign o_ce = hold ? (hc[1:0] == ce_ph) : ce;
	// one clock before the counters reach the first offset the picture did
	// not show (f_stop + 1): the machine's first clock after the resume shows it
	assign resume_ok = !hold || l_f == 20'd0 || fc == f_stop;
endmodule

`default_nettype wire
