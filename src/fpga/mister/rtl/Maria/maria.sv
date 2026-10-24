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


// openFPGA-2600 (plan step 4): what is left of MARIA is the part the 2600
// side runs on. The clock block below is MARIA's own, verbatim: the master
// clock halves (mclk0/mclk1), the TIA's clock enable (tia_clk_x2, with its
// two-tick start-up count) and the processor clock's two phases (pclk0/1),
// which carry the CPU until the reset is released and the TIA takes over
// (top.sv's cpu_phase_controller). The decode is control.sv's 2600 memory
// map, verbatim, for the TIA and RIOT selects. MARIA's video, DMA, line RAM,
// registers and 7800 memory map are gone, and so is everything they fed:
// MEN (maria_en) was never set in the 2600 core, so the constants below are
// the values those inputs always had there: every access is a slow one
// (control.sv's sel_slow_clock with MEN low) and WSYNC is never written (no
// MARIA registers in the 2600 map). lrc is the exception: video_sync was held
// in reset while MEN was low, and its lrc is high in reset, so it was
// constantly 1, not 0. Tying it 0 changes nothing: with wsync 0, lrc only
// ever sets ready_int, which the reset already sets and nothing clears.
module maria(
	// Busses
	input  logic [15:0] AB_in,

	// Clocking
	input logic         reset,
	input logic         clk_sys,
	input logic         ce,
	output logic        mclk0,     // This serves as tia_clk
	output logic        mclk1,
	output logic        tia_clk_x2,
	output logic        pclk0,
	output logic        pclk1,

	// Chip Select lines
	output logic        cs_riot,
	output logic        cs_tia,

	// CPU
	output logic        ready
);

	wire              maria_en = 1'b0;
	wire              sel_slow_clock = 1'b1;
	wire              wsync = 1'b0;
	wire              lrc = 1'b0;      // was 1 (see above); same effect
	/* verilator lint_off UNUSEDSIGNAL */
	wire [15:0]       AB = AB_in;     // the decode reads A15-A5

	logic [2:0]       clock_div = 3'd2;
	logic             clk_toggle = 1'b0;
	logic             pclk_toggle = 1'b0;
	logic             slow_clk_latch = 1'b0;
	logic             ready_int;
	logic             old_men = 1'b0;
	logic [3:0]       men_count = 4'd0;
	logic             pclk = 1'b0;    // the phase level control.sv and DMA read
	/* verilator lint_on UNUSEDSIGNAL */
	logic             tia_clk_en;
	logic [3:0]       tia_enable_count = 4'd2;

	assign ready = ready_int;

	assign tia_clk_en = ~|tia_enable_count;
	assign tia_clk_x2 = tia_clk_en && mclk0;

	always @(posedge clk_sys) begin
		mclk1 <= 1'b0;
		mclk0 <= 1'b0;
		pclk0 <= 1'b0;
		pclk1 <= 1'b0;

		if (reset) begin
			ready_int <= 1'b1;
		end

		if (ce) begin
			old_men <= maria_en;

			// If maria enabled rises, the CPU clock is held in a state
			// of reset for 5 master oscillator cycles.
			if (~old_men && maria_en)
				men_count <= 4'd5;

			if (mclk1 && |tia_enable_count)
				tia_enable_count <= tia_enable_count - 1'd1;

			if (|men_count)
				men_count <= men_count - 1'd1;

			// Follow the phase pulse itself, not the mclk0 that normally
			// carries it. This is decision 0076, from when PAL was slowed by
			// dropping one master clock in 110 and a dropped cycle could steal
			// the toggle. PAL now has its own clock out of the PLL (decision
			// 0088) and there is no bubble, so a phase pulse always lands on an
			// mclk0 cycle and this is the same cycle either way. Kept because
			// following the pulse states the intent more directly.
			if (pclk1)
				pclk <= 0;
			else if (pclk0)
				pclk <= 1;

			if (pclk0)
				slow_clk_latch <= sel_slow_clock;

			// Uniform in both regions: PAL's master clock is simply slower,
			// out of the PLL (decision 0088). MARIA halves clk_sys either way.
			mclk0 <= clk_toggle;
			mclk1 <= ~clk_toggle;
			clk_toggle <= ~clk_toggle;

			if (!reset) begin
				if (wsync)
					ready_int <= 1'b0;
				else
					if (lrc)
						ready_int <= 1'b1;

			end

			// The timing schematic has no reset input to the processor-clock
			// generator. Keep PCLK0 running while the model reset clears
			// functional state so SALLY can recognize reset.
			if (mclk1) begin
				if (clock_div != 3'd0)
					clock_div <= clock_div - 1'd1;
				else begin
					pclk_toggle <= ~pclk_toggle;
					pclk1 <= pclk_toggle;
					pclk0 <= ~pclk_toggle;
					clock_div <= (~pclk_toggle ? sel_slow_clock : slow_clk_latch) ? 3'd2 : 3'd1;
				end
			end

			if (|men_count) begin
				pclk_toggle <= 1'b0;
				clock_div <= sel_slow_clock ? 3'd2 : 3'd1;
			end
		end
	end

	/* verilator lint_off CASEX */
	always_comb begin
		{cs_riot, cs_tia} = 0;
		casex (AB[15:5])
				11'bXXX0_XX0X_1XX,
				11'bxxx0_xx1x_1xx: cs_riot = 1;
				11'bxxx0_xxxx_0xx: cs_tia = 1;
				default: ;
		endcase
	end
	/* verilator lint_on CASEX */

endmodule
