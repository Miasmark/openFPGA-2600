// Equivalence bench for paddle_timer4.sv (the four paddle timers with one
// shared calibration engine) against four of MiSTer's paddle_timer
// (mister/rtl/paddles.sv), on every clock: each paddle's `charged`, and
// every register behind it (high_count, lowest, highest, difference,
// read_count, cleared; width through m = (width + 13,968) >> 8, lowest >
// highest through lgh), and the dump counter (clear_count = cc x 6,984).
//
// Stimulus (own xorshift generator, so a seed gives the same run anywhere),
// built like a game's paddle loop but wider:
//   - the dump line (common): dumps of 481-30,000 clocks (paddle_timer's full
//     dump is 480), short ones of 1-480 and ones of 478-483, between charge
//     periods of 1-60, 61-5,000, 5,000-60,000 (most), 60,000-700,000 and a
//     few of 1.2-1.3 million clocks (high_count's 33 bits wrap); a sixteenth
//     of the reads end 0-2 clocks before a dump starts, and a quarter of the
//     charge periods start with a read 0-40 clocks in;
//   - reads (at most one paddle per clock, as the TIA's INPT decode): pulses
//     of 1-8 clocks, 0-3,000 clocks apart (a tenth of them back to back, on
//     the next clock), a quarter on the paddle read before, in and out of
//     the dumps;
//   - positions per paddle: steps of 1-3 and jumps, on any clock, sometimes
//     on two or more paddles at once;
//   - resets of 1-20 clocks on one paddle, a pair, or all four;
//   - with +ce, the clock enable low for 1-2,000 clocks at random times;
//   - with +chain=N, the save-state chain (paddle_timer4's ss_* ports): about
//     every 200,000 clocks, with the reference's clock enable low meanwhile,
//     the engine's registers are shifted out N clocks with random bits in,
//     kept, and shifted back in (a load of what was saved), after a hold of
//     1-50 clocks with ss_frz high. N = 696, the chain's length, must change
//     nothing; any other N must be seen.
//
//   +seed=N +cycles=N +ce +chain=N  (defaults 1, 2 x 10^7, ce always high, no chain)
// Prints "PADDLES4 seed ... mismatches N", the first 10 mismatches and
// coverage counted on the reference's registers; ends with $finish whatever
// the result: sim/run_paddles4.sh reads the line and gives the verdict.
//
// SPDX-License-Identifier: MIT

`default_nettype none

module tb_paddles4;
	logic clk = 1'b0;
	always #5 clk = ~clk;

	longint unsigned rs = 64'h9E37_79B9_7F4A_7C15;
	function automatic int unsigned rnd();
		rs ^= rs << 13;
		rs ^= rs >> 7;
		rs ^= rs << 17;
		return rs[47:16];
	endfunction
	function automatic int unsigned urange(int unsigned lo, int unsigned hi);
		return lo + rnd() % (hi - lo + 1);
	endfunction

	int unsigned seed = 1;
	longint      cycles = 64'd20_000_000;
	bit          use_ce = 1'b0;
	initial begin
		void'($value$plusargs("seed=%d", seed));
		void'($value$plusargs("cycles=%d", cycles));
		use_ce = $test$plusargs("ce");
		rs = 64'h9E37_79B9_7F4A_7C15 ^ (64'(seed) * 64'h0000_0100_0000_01B3);
		repeat (20) void'(rnd());
	end

	// ---- stimulus (driven on the rising edge, as flops) ----
	logic       ce = 1'b1, clear = 1'b0;
	logic       ss_busy = 1'b0;           // the chain test (+chain) runs: the reference waits
	wire        ref_ce = ce && !ss_busy;
	logic [3:0] rst = 4'd0, read = 4'd0;
	logic [7:0] k [4] = '{8'd128, 8'd128, 8'd128, 8'd128};
	wire [31:0] kohms = {k[3], k[2], k[1], k[0]};

	// ---- the reference: four paddle_timer ----
	wire [3:0] ref_charged;
	genvar g;
	generate
	for (g = 0; g < 4; g = g + 1) begin : rf
		paddle_timer pt (
			.clk        (clk),
			.ce         (ref_ce),
			.reset      (rst[g]),
			.kohms      ({2'b00, k[g]}),
			.clear      (clear),
			.read       (read[g]),
			.charged    (ref_charged[g]),
			.difference ()
		);
	end
	endgenerate

	// ---- the design ----
	wire [3:0] dut_charged;
	logic ss_en = 1'b0, ss_frz = 1'b0, ss_si = 1'b0;
	wire  ss_so;
	paddle_timer4 dut (
		.ss_en   (ss_en),
		.ss_frz  (ss_frz),
		.ss_si   (ss_si),
		.ss_so   (ss_so),
		.clk     (clk),
		.ce      (ce),
		.reset   (rst),
		.kohms   (kohms),
		.clear   (clear),
		.read    (read),
		.charged (dut_charged)
	);

	// ---- the chain (+chain=N): out with random bits in, hold, back in ----
	int unsigned chain_n = 0, ch_left = 0, ch_ph = 0, ch_gap = 100000, ch_i = 0, ch_rot = 0;
	bit   kept [0:4095];
	initial void'($value$plusargs("chain=%d", chain_n));
	always @(posedge clk) begin
		if (chain_n != 0) begin
			case (ch_ph)
				0: if (ch_gap != 0) ch_gap <= ch_gap - 1;
				   else begin ss_busy <= 1'b1; ss_frz <= 1'b1; ch_left <= urange(1, 50); ch_ph <= 1; end
				1: if (ch_left != 0) ch_left <= ch_left - 1;
				   else begin ss_en <= 1'b1; ss_si <= 1'(urange(0, 1)); ch_i <= 0; ch_ph <= 2; end
				2: begin                      // out: keep ss_so, random bits in
					kept[ch_i] = ss_so;
					if (ch_i + 1 == chain_n) begin ss_en <= 1'b0; ch_left <= urange(1, 50); ch_ph <= 3; end
					else ss_si <= 1'(urange(0, 1));
					ch_i <= ch_i + 1;
				end
				3: if (ch_left != 0) ch_left <= ch_left - 1;
				   else begin ss_en <= 1'b1; ss_si <= kept[0]; ch_i <= 1; ch_ph <= 4; end
				4: begin                      // back in, in the order it came out
					if (ch_i == chain_n) begin ss_en <= 1'b0; ch_left <= urange(1, 50); ch_ph <= 5; end
					else ss_si <= kept[ch_i];
					ch_i <= ch_i + 1;
				end
				5: if (ch_left != 0) ch_left <= ch_left - 1;
				   else begin ss_frz <= 1'b0; ss_busy <= 1'b0; ch_gap <= urange(100000, 300000); ch_rot <= ch_rot + 1; ch_ph <= 0; end
			endcase
		end
	end

	// ---- stimulus generator ----
	int unsigned phase_left = 2000;   // clocks left in this dump / charge period
	int unsigned rd_gap = 100, rd_len = 0, ce_left = 0, rst_left = 0;
	logic  [1:0] rd_p = 2'd0;
	logic  [3:0] rst_mask = 4'd0;
	always @(posedge clk) begin
		// the dump line
		if (phase_left == 0) begin
			if (clear) begin
				clear <= 1'b0;
				case (urange(0, 19))
					0, 1:    phase_left <= urange(1, 60);
					2, 3, 4: phase_left <= urange(61, 5000);
					5:       phase_left <= urange(60000, 700000);
					6:       if (urange(0, 9) == 0) phase_left <= urange(1200000, 1300000);   // past high_count's 33 bits
					         else phase_left <= urange(5000, 60000);
					default: phase_left <= urange(5000, 60000);
				endcase
				// a read soon after the dump line falls (a new lowest)
				if (urange(0, 3) == 0 && rd_len == 0) rd_gap <= urange(0, 40);
			end else begin
				clear <= 1'b1;
				case (urange(0, 9))
					0, 1:    phase_left <= urange(1, 480);
					2:       phase_left <= urange(478, 483);
					default: phase_left <= urange(481, 30000);
				endcase
			end
		end else
			phase_left <= phase_left - 1;

		// reads: one paddle at a time
		if (rd_len != 0) begin
			rd_len <= rd_len - 1;
			if (rd_len == 1) begin
				read <= 4'd0;
				// a dump that starts 0-2 clocks after a read (its width pending in the dump)
				if (!clear && urange(0, 15) == 0) phase_left <= urange(0, 2);
				case (urange(0, 9))
					0:       rd_gap <= urange(0, 3);
					1, 2, 3: rd_gap <= urange(4, 100);
					default: rd_gap <= urange(100, 3000);
				endcase
			end
		end else if (rd_gap != 0)
			rd_gap <= rd_gap - 1;
		else begin
			logic [1:0] q;
			q = (urange(0, 3) == 0) ? rd_p : 2'(urange(0, 3));
			rd_p <= q;
			read <= 4'd1 << q;
			rd_len <= urange(1, 8);
		end

		// positions
		for (int i = 0; i < 4; i++)
			if (urange(0, 1999) == 0) begin
				if (urange(0, 9) < 7) begin
					int s;
					s = int'(k[i]) + ((urange(0, 1) != 0) ? int'(urange(1, 3)) : -int'(urange(1, 3)));
					k[i] <= (s < 0) ? 8'd0 : (s > 255) ? 8'd255 : 8'(s);
				end else
					k[i] <= 8'(urange(0, 255));
			end

		// resets
		if (rst_left != 0) begin
			rst_left <= rst_left - 1;
			if (rst_left == 1) rst <= 4'd0;
		end else if (urange(0, 999999) == 0) begin
			case (urange(0, 2))
				0:       rst_mask = 4'd1 << urange(0, 3);
				1:       rst_mask = (urange(0, 1) != 0) ? 4'b1100 : 4'b0011;
				default: rst_mask = 4'b1111;
			endcase
			rst <= rst_mask;
			rst_left <= urange(1, 20);
		end

		// clock enable
		if (use_ce) begin
			if (ce_left != 0) begin
				ce_left <= ce_left - 1;
				if (ce_left == 1) ce <= 1'b1;
			end else if (urange(0, 49999) == 0) begin
				ce <= 1'b0;
				ce_left <= urange(1, 2000);
			end
		end
	end

	// ---- comparison on every clock (sampled between edges) ----
	longint n = 0, mism = 0;
	longint cov_charge = 0, cov_high = 0, cov_low = 0, cov_width = 0, cov_meas = 0, cov_dump = 0, cov_defer = 0;
	logic [3:0] ref_charged_d = 4'd0, ref_rm_d = 4'd0;
	task automatic report(input string what, input int p, input longint a, input longint b);
		mism++;
		if (mism <= 10)
			$display("MISMATCH clock %0d paddle %0d %s: reference %0h, engine %0h", n, p, what, a, b);
	endtask
	always @(negedge clk) if (!ss_busy) begin
		n++;
		if (rf[0].pt.clear_count != 33'(dut.cc) * 33'd6984) report("clear_count", 0, rf[0].pt.clear_count, dut.cc);
		if (ref_charged != dut_charged) report("charged", -1, ref_charged, dut_charged);
		`define CMP(P) \
			if (rf[P].pt.high_count != dut.pd[P].high_count) report("high_count", P, rf[P].pt.high_count, dut.pd[P].high_count); \
			if (rf[P].pt.lowest != dut.pd[P].lowest) report("lowest", P, rf[P].pt.lowest, dut.pd[P].lowest); \
			if (rf[P].pt.highest != dut.pd[P].highest) report("highest", P, rf[P].pt.highest, dut.pd[P].highest); \
			if (rf[P].pt.difference != dut.pd[P].difference) report("difference", P, rf[P].pt.difference, dut.pd[P].difference); \
			if (rf[P].pt.read_count != dut.pd[P].read_count) report("read_count", P, rf[P].pt.read_count, dut.pd[P].read_count); \
			if (rf[P].pt.cleared != dut.pd[P].cleared) report("cleared", P, rf[P].pt.cleared, dut.pd[P].cleared); \
			if (26'((34'(rf[P].pt.width) + 34'd13968) >> 8) != dut.pd[P].m) report("width (as m)", P, rf[P].pt.width, dut.pd[P].m); \
			if ((rf[P].pt.lowest > rf[P].pt.highest) != dut.pd[P].lgh) report("lowest > highest", P, rf[P].pt.lowest > rf[P].pt.highest, dut.pd[P].lgh);
		`CMP(0)
		`CMP(1)
		`CMP(2)
		`CMP(3)
		`undef CMP
		// coverage, on the reference
		cov_charge += $countones(ref_charged & ~ref_charged_d);
		ref_charged_d = ref_charged;
		if (dut.ev_high) cov_high++;
		if (dut.ev_low) cov_low++;
		if (dut.ev_high && dut.e_lt) cov_width++;
		if (clear && ce && dut.cc == 9'd479) cov_dump++;
		if (clear && (dut.pd[0].pend || dut.pd[1].pend || dut.pd[2].pend || dut.pd[3].pend)) cov_defer++;
		if (ref_rm_d != {&rf[3].pt.read_count, &rf[2].pt.read_count, &rf[1].pt.read_count, &rf[0].pt.read_count}) cov_meas++;
		ref_rm_d = {&rf[3].pt.read_count, &rf[2].pt.read_count, &rf[1].pt.read_count, &rf[0].pt.read_count};
		if (n == cycles) begin
			$display("PADDLES4 coverage: INPT rises %0d, new highest %0d (with a width %0d), new lowest %0d, full dumps %0d, clocks with a width pending in a dump %0d, read_measured changes %0d",
				cov_charge, cov_high, cov_width, cov_low, cov_dump, cov_defer, cov_meas);
			$display("PADDLES4 coverage: final read_count %0d %0d %0d %0d, difference %0h %0h %0h %0h",
				rf[0].pt.read_count, rf[1].pt.read_count, rf[2].pt.read_count, rf[3].pt.read_count,
				rf[0].pt.difference, rf[1].pt.difference, rf[2].pt.difference, rf[3].pt.difference);
			if (chain_n != 0) $display("PADDLES4 chain %0d bits: %0d loads", chain_n, ch_rot);
			$display("PADDLES4 seed %0d ce %0d clocks %0d mismatches %0d", seed, use_ce, n, mism);
			$finish;
		end
	end
endmodule
