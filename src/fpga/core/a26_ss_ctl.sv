//------------------------------------------------------------------------------
// Atari 2600 core: the save-state controller (docs/SAVESTATE.md)
//
// The Pocket's commands reach it through core_bridge_cmd (clk_74a):
//   0x00A0  save   savestate_start held until ack; then busy, and ok or err
//                  held until the next request
//   0x00A4  load   the same with savestate_load; the host has written the
//                  blob over the bridge before it sends the command
//   0x00B0  menu   osnotify_inmenu: with pause_en ("Pause in Menu") the
//                  machine is frozen while the menu is open
// Sleep is a save and, on wake, a load (core.json sleep_supported). The host
// polls for the result code: 0 idle, 1 busy, 2 ok, 3 error. The status bits
// change one at a time, 4 clk_sys apart, in an order that never shows the
// host a wrong code across the crossing: busy rises, then ok / err clear,
// then ack; at the end ok or err rises, then busy drops. (The protocol,
// the status order, the header checks and the wake rule are the
// Intellivision core's, openFPGA-Intellivision intv_ss_ctl.sv, our own MIT
// code; the state is read and written here through a scan chain.)
//
// The blob: tools/savestate.py's layout (a26_ss_pkg), 131,072 bytes at bridge
// address 0x50000000, 32-bit words, big-endian. Its live part, words 0 to
// SS_W_END - 1, is staged in a block RAM with a port on each clock: the
// bridge reads and writes it on clk_74a (a read's word is on bridge_rd_data
// from the clock after its bridge_rd until the next one: the bridge sends the
// word of the previous read), the controller on clk_sys. The rest reads 0;
// a write of anything but 0 there marks the blob bad (cleared by a write to
// word 0).
//
// Freezing (SAVESTATE.md 2): frz holds every flip-flop of the machine (the
// scan chain's ss_frz) and the wrapper's peripherals; the wrapper's
// substitute raster keeps the Pocket's video in sync meanwhile. The freeze
// lands at a frame boundary: the first CPU cycle (cpu_ce, the phi1 enable)
// after the machine's VSync rose, with the machine out of reset, and only
// while the peripherals are quiet (quiet: no SaveKey RAM access, no FA2 flash
// copy, the AtariVox silent). Without a VSync for 4 periods of 2^18 clk_sys
// (about 73 ms) it freezes at the next CPU cycle anyway; with no quiet point
// for 128 periods (2.3 s: the AtariVox speaking) the save or load ends with
// err and the machine untouched. A refused cartridge (refuse: DPC+, CDF,
// CDFJ, CDFJ+, the Supercharger, an unsupported image) answers err at once.
//
//   save  freeze; settle 8 clk_sys; the chain shifted out word by word, its
//         output fed back to its input (after SS_CHAIN_BITS clocks every flop
//         holds what it held), then the RIOT RAM, the FA2 work RAM and the
//         AtariVox register file through their state port (ss_ram), the
//         cartridge RAM through the SRAM's cartridge port (t_*), each word
//         into the staging RAM with the payload CRC32; then the header; ok.
//   load  freeze; the header (magic, version, size, length, the cartridge's
//         CRC32 and length, the mapper word, the PAL flag, the chain's length
//         and signature, the cart RAM size, reserved words 0), the payload's
//         CRC32, the unused areas 0 and nothing but 0 written beyond the live
//         part; a foreign or corrupt blob ends with err and the machine
//         resumes untouched. Else the chain is shifted in, the RAMs and the
//         cartridge RAM written, and ok.
// After either, frz stays high at least 32 clk_sys more with ss_en and the
// ports released: the block RAMs' read registers reload from the machine's
// own (restored) addresses, and the SRAM and SDRAM serve the machine's
// pending request again. The machine resumes when the substitute raster
// reaches the position the picture stopped at (resume_ok), and not while
// the menu holds it.
//
// Wake: a load asked for while the console is held in reset (the host's
// reset; the cartridge loaded) is checked at once and answered without a
// freeze; an ok one is staged (pend) and applied, checked once more, at the
// first freeze point after the reset exit, with no status change.
//
// SPDX-License-Identifier: MIT
//------------------------------------------------------------------------------

`default_nettype none

module a26_ss_ctl (
	// ---------------------------------------------- clk_74a: APF
	input  wire logic        clk_74a,
	/* verilator lint_off UNUSEDSIGNAL */
	input  wire logic [31:0] bridge_addr,          // [1:0] unused: word accesses
	/* verilator lint_on UNUSEDSIGNAL */
	input  wire logic        bridge_rd,
	input  wire logic        bridge_wr,
	input  wire logic [31:0] bridge_wr_data,
	output logic      [31:0] bridge_rd_data,

	input  wire logic        savestate_start,
	output logic             savestate_start_ack,
	output logic             savestate_start_busy,
	output logic             savestate_start_ok,
	output logic             savestate_start_err,
	input  wire logic        savestate_load,
	output logic             savestate_load_ack,
	output logic             savestate_load_busy,
	output logic             savestate_load_ok,
	output logic             savestate_load_err,
	input  wire logic        osnotify_inmenu,
	input  wire logic        pause_en,

	// ---------------------------------------------- clk_sys: the machine
	input  wire logic        clk,
	input  wire logic        mreset,          // the console held in reset
	input  wire logic        cart_ready,      // a cartridge loaded (its CRC32 known)
	input  wire logic        refuse,          // a scheme v1 does not save
	input  wire logic        cpu_ce,          // the 6507's phi1 enable
	input  wire logic        vsync,           // the machine's VSync
	input  wire logic        quiet,           // the peripherals: no access in flight
	input  wire logic        resume_ok,       // the substitute raster is where the picture stopped
	input  wire logic [31:0] cart_crc,
	input  wire logic [31:0] cart_len,
	input  wire logic [31:0] mapper_word,     // header word 6
	input  wire logic [31:0] flags_word,      // header word 7 (bit 0: PAL, checked)

	output logic             frz,             // hold the machine
	output logic             ss_en,           // shift the chain
	output wire              ss_si,           // the chain's input (its output while a save rotates it)
	input  wire logic        ss_so,

	output logic             ss_ram,          // a RAM's state port
	output logic      [1:0]  ss_rsel,         // 0 RIOT, 1 FA2, 2 AtariVox register file
	output logic      [7:0]  ss_ra,
	output logic             ss_rwe,
	output logic     [31:0]  ss_rd,           // the byte RAMs take [7:0]
	input  wire logic  [7:0] ss_rq8,          // RIOT or FA2 (ss_rsel)
	input  wire logic [31:0] ss_rq32,         // the AtariVox register file

	output logic             t_own,           // the SRAM's cartridge port is the controller's
	output logic             t_rd,
	output logic             t_wr,
	output logic     [16:0]  t_addr,
	output logic      [7:0]  t_wdata,
	input  wire logic  [7:0] t_rdata
);

	import a26_ss_pkg::*;
	// power-up values on registers the processes assign (DEVELOPING.md, "Power-up values")
	/* verilator lint_off PROCASSINIT */

	localparam int WA = 14;                        // staging word address bits
	localparam int CHAIN_WORDS = (SS_CHAIN_BITS + 31) / 32;
	localparam int LAST_BITS = SS_CHAIN_BITS - 32 * (CHAIN_WORDS - 1);

	// ============================================== the staging RAM
	// port a: the bridge (clk_74a); port b: the controller (clk_sys); one
	// M10K block RAM of 9,216 x 32 (Quartus does not infer a true dual-port
	// RAM on two clocks this size from an array: altsyncram, as save_ram_dp)
	logic [WA-1:0] sb_a;
	logic          sb_we;
	logic [31:0]   sb_d, sb_q;
	logic [31:0]   sa_q;
	wire           b_hit  = bridge_addr[31:24] == 8'h50;
	wire  [21:0]   b_w    = bridge_addr[23:2];
	wire           b_live = b_w < 22'(SS_W_END);
	altsyncram #(
		.operation_mode                 ("BIDIR_DUAL_PORT"),
		.width_a                        (32),
		.widthad_a                      (WA),
		.numwords_a                     (SS_W_END),
		.width_b                        (32),
		.widthad_b                      (WA),
		.numwords_b                     (SS_W_END),
		.outdata_reg_a                  ("UNREGISTERED"),
		.outdata_reg_b                  ("UNREGISTERED"),
		.address_reg_b                  ("CLOCK1"),
		.indata_reg_b                   ("CLOCK1"),
		.wrcontrol_wraddress_reg_b      ("CLOCK1"),
		.clock_enable_input_a           ("BYPASS"),
		.clock_enable_input_b           ("BYPASS"),
		.clock_enable_output_a          ("BYPASS"),
		.clock_enable_output_b          ("BYPASS"),
		.power_up_uninitialized         ("FALSE"),
		.read_during_write_mode_port_a  ("NEW_DATA_NO_NBE_READ"),
		.read_during_write_mode_port_b  ("NEW_DATA_NO_NBE_READ"),
		.intended_device_family         ("Cyclone V"),
		.lpm_type                       ("altsyncram")
	) stg (
		.clock0    (clk_74a),
		.address_a (b_w[WA-1:0]),
		.data_a    (bridge_wr_data),
		.wren_a    (bridge_wr && b_hit && b_live),
		.q_a       (sa_q),

		.clock1    (clk),
		.address_b (sb_a),
		.data_b    (sb_d),
		.wren_b    (sb_we),
		.q_b       (sb_q),

		.aclr0 (1'b0), .aclr1 (1'b0),
		.addressstall_a (1'b0), .addressstall_b (1'b0),
		.byteena_a (1'b1), .byteena_b (1'b1),
		.clocken0 (1'b1), .clocken1 (1'b1), .clocken2 (1'b1), .clocken3 (1'b1),
		.rden_a (1'b1), .rden_b (1'b1),
		/* verilator lint_off PINCONNECTEMPTY */
		.eccstatus ()
		/* verilator lint_on PINCONNECTEMPTY */
	);

	// the bridge's read latch: the word of a read is taken on the clock after
	// its bridge_rd and held until the next read
	logic rd_q = 1'b0, rd_take = 1'b0, rd_live = 1'b0;
	logic wbad = 1'b0;                           // a non-zero write beyond the live part
	initial bridge_rd_data = 32'd0;
	always_ff @(posedge clk_74a) begin
		rd_q <= bridge_rd;
		rd_take <= bridge_rd && !rd_q && b_hit;
		if (bridge_rd && !rd_q && b_hit)
			rd_live <= b_live;
		if (rd_take)
			bridge_rd_data <= rd_live ? sa_q : 32'd0;
		if (bridge_wr && b_hit) begin
			if (b_w == 22'd0)
				wbad <= 1'b0;
			else if (!b_live && bridge_wr_data != 32'd0)
				wbad <= 1'b1;
		end
	end

	// status to clk_74a: levels, each through two flip-flops
	logic s_ack = 1'b0, s_busy = 1'b0, s_ok = 1'b0, s_err = 1'b0;
	logic l_ack = 1'b0, l_busy = 1'b0, l_ok = 1'b0, l_err = 1'b0;
	logic [7:0] st_a = 8'd0, st_b = 8'd0;
	always_ff @(posedge clk_74a) begin
		st_a <= {s_ack, s_busy, s_ok, s_err, l_ack, l_busy, l_ok, l_err};
		st_b <= st_a;
	end
	assign {savestate_start_ack, savestate_start_busy, savestate_start_ok, savestate_start_err,
	        savestate_load_ack, savestate_load_busy, savestate_load_ok, savestate_load_err} = st_b;

	// ============================================== clk_sys side
	logic [2:0] st_s = 3'd0, ld_s = 3'd0, mn_s = 3'd0, pz_s = 3'd0, wb_s = 3'd0;
	always_ff @(posedge clk) begin
		st_s <= {st_s[1:0], savestate_start};
		ld_s <= {ld_s[1:0], savestate_load};
		mn_s <= {mn_s[1:0], osnotify_inmenu};
		pz_s <= {pz_s[1:0], pause_en};
		wb_s <= {wb_s[1:0], wbad};
	end
	wire start_lv  = st_s[2], load_lv = ld_s[2];
	wire menu_hold = mn_s[2] && pz_s[2];
	wire wbad_s    = wb_s[2];

	// ---------------------------------------------- CRC-32 (zlib), a byte a clock
	function automatic logic [31:0] crc_byte(input logic [31:0] c, input logic [7:0] b);
		logic [31:0] x;
		x = c ^ {24'd0, b};
		for (int k = 0; k < 8; k++)
			x = x[0] ? (x >> 1) ^ 32'hEDB88320 : x >> 1;
		return x;
	endfunction

	// ---------------------------------------------- freeze
	logic si_q, rot;                             // a load's next bit; a save rotates the chain
	assign ss_si = rot ? ss_so : si_q;
	logic op = 1'b0;                             // a save or load holds the freeze
	logic rel = 1'b0;                            // the operation's ports are released: may resume
	// the menu's pause gives way to a reset (the wrapper keeps it for the
	// machine until it runs: ss_rst_pend)
	wire  want = op || (menu_hold && !mreset);
	logic vs_q = 1'b0, vs_seen = 1'b0;
	logic [17:0] per = 18'd0;                    // a period of 2^18 clk_sys
	logic [2:0]  nov = 3'd0;                     // periods without VSync while waiting
	wire  fpoint = cpu_ce && !mreset && (vs_seen || nov[2]);
	typedef enum logic [1:0] {F_RUN, F_FROZEN, F_HOLD} fst_t;
	fst_t fst = F_RUN;
	logic [5:0] hcnt = 6'd0;
	initial begin
		frz = 1'b0; ss_en = 1'b0; si_q = 1'b0; rot = 1'b0;
		ss_ram = 1'b0; ss_rsel = 2'd0; ss_ra = 8'd0; ss_rwe = 1'b0; ss_rd = 32'd0;
		t_own = 1'b0; t_rd = 1'b0; t_wr = 1'b0; t_addr = 17'd0; t_wdata = 8'd0;
	end

	always_ff @(posedge clk) begin
		vs_q <= vsync;
		per <= per + 18'd1;
		// a VSync since the freeze was wanted; periods without one
		if (!want || frz) begin
			vs_seen <= 1'b0;
			nov <= 3'd0;
		end else begin
			if (vsync && !vs_q)
				vs_seen <= 1'b1;
			if (per == 18'h3FFFF && !nov[2])
				nov <= nov + 3'd1;
		end
		case (fst)
			F_RUN: if (want && quiet && fpoint) begin
				frz <= 1'b1;
				fst <= F_FROZEN;
			end
			F_FROZEN: if (!want || rel) begin    // released: hold 32 more, then wait for the raster
				hcnt <= 6'd32;
				fst <= F_HOLD;
			end
			F_HOLD: if (want && !rel) begin
				fst <= F_FROZEN;
			end else if (hcnt != 6'd0)
				hcnt <= hcnt - 6'd1;
			else if (!want && resume_ok) begin
				frz <= 1'b0;
				fst <= F_RUN;
			end
			default: fst <= F_RUN;
		endcase
	end
	wire settled = (fst == F_FROZEN);

	// ---------------------------------------------- the operation
	typedef enum logic [4:0] {
		O_IDLE, O_HS1, O_HS2, O_WAITF, O_SETTLE,
		O_SCH, O_SCHW, O_SRAM, O_SRAMR, O_SCRAM, O_SCRAMR, O_SWR, O_SCRC, O_HDR,
		O_VHDR, O_VHDR2, O_VPAY, O_VPAY2, O_VCRC, O_VCHK,
		O_AW, O_AW2, O_ACH, O_ARAM, O_ACRAM,
		O_FIN_OK, O_FIN_ERR, O_FIN2
	} ost_t;
	ost_t        ost = O_IDLE;
	logic        is_load = 1'b0, staged = 1'b0, pend = 1'b0, silent = 1'b0;
	logic [2:0]  dly = 3'd0;
	logic [WA-1:0] w = '0;                        // blob word
	logic [5:0]  bi = 6'd0;                       // bit / byte / clock count in_arc a word
	logic [1:0]  bq = 2'd0;                       // CRC byte
	logic [31:0] v = 32'd0, crc = 32'hFFFFFFFF, hdr_crc = 32'd0;
	logic        bad = 1'b0;
	logic [7:0]  tmo = 8'd0;
	/* verilator lint_off UNUSEDSIGNAL */
	logic        ld_applied = 1'b0;               // a load's state is in (one clk; the bench)
	/* verilator lint_on UNUSEDSIGNAL */

	wire in_chain = w >= WA'(SS_W_CHAIN) && w < WA'(SS_W_CHAIN + CHAIN_WORDS);
	wire in_cpad  = w >= WA'(SS_W_CHAIN + CHAIN_WORDS) && w < WA'(SS_W_RIOT);
	wire in_riot  = w >= WA'(SS_W_RIOT) && w < WA'(SS_W_FA2);
	wire in_fa2   = w >= WA'(SS_W_FA2) && w < WA'(SS_W_AVOX);
	wire in_avox  = w >= WA'(SS_W_AVOX) && w < WA'(SS_W_GAP);
	wire in_gap   = w >= WA'(SS_W_GAP) && w < WA'(SS_W_CRAM);
	wire in_cram  = w >= WA'(SS_W_CRAM);
	wire w_lastch = w == WA'(SS_W_CHAIN + CHAIN_WORDS - 1);
	wire w_last   = w == WA'(SS_W_END - 1);
	wire [5:0] nbits = w_lastch ? 6'(LAST_BITS) : 6'd32;
	// the byte RAMs: word w holds bytes 4k .. 4k + 3, the first in bits 31-24
	wire [7:0]  rb_i  = in_riot ? 8'({w - WA'(SS_W_RIOT), 2'b00}) : 8'({w - WA'(SS_W_FA2), 2'b00});
	wire [16:0] cr_i  = 17'({w - WA'(SS_W_CRAM), 2'b00});
	// the last chain word's bits past the chain must be 0 in a blob
	wire [31:0] pad_mask = (LAST_BITS == 32) ? 32'd0 : (32'hFFFFFFFF >> LAST_BITS);

	// the header this core writes and expects (word SS_H_CRC: c)
	function automatic logic [31:0] hdr_exp(input logic [3:0] i, input logic [31:0] c);
		case (i)
			4'(SS_H_MAGIC):      hdr_exp = SS_MAGIC;
			4'(SS_H_VERSION):    hdr_exp = SS_VERSION;
			4'(SS_H_SIZE):       hdr_exp = 32'(SS_BLOB_BYTES);
			4'(SS_H_LENGTH):     hdr_exp = 32'(SS_PAYLOAD);
			4'(SS_H_CART_CRC):   hdr_exp = cart_crc;
			4'(SS_H_CART_LEN):   hdr_exp = cart_len;
			4'(SS_H_MAPPER):     hdr_exp = mapper_word;
			4'(SS_H_FLAGS):      hdr_exp = flags_word;
			4'(SS_H_CRC):        hdr_exp = c;
			4'(SS_H_CHAIN_BITS): hdr_exp = 32'(SS_CHAIN_BITS);
			4'(SS_H_CHAIN_SIG):  hdr_exp = SS_CHAIN_SIG;
			4'(SS_H_CRAM_BYTES): hdr_exp = 32'(SS_CRAM_BYTES);
			default:             hdr_exp = 32'd0;
		endcase
	endfunction
	// the bits of a header word a load checks (the flags: PAL only)
	function automatic logic [31:0] hdr_mask(input logic [3:0] i);
		case (i)
			4'(SS_H_FLAGS): hdr_mask = SS_FLAGS_CHECKED;
			4'(SS_H_CRC):   hdr_mask = 32'd0;
			default:        hdr_mask = 32'hFFFFFFFF;
		endcase
	endfunction

	always_ff @(posedge clk) begin
		sb_we <= 1'b0;
		ss_rwe <= 1'b0;
		ld_applied <= 1'b0;
		if (!start_lv) s_ack <= 1'b0;
		if (!load_lv) l_ack <= 1'b0;
		if (dly != 3'd0) dly <= dly - 3'd1;
		if (ost == O_WAITF && per == 18'h3FFFF && tmo != 8'hFF) tmo <= tmo + 8'd1;

		case (ost)
			O_IDLE: begin
				rel <= 1'b0;
				if (pend && !mreset && cart_ready) begin  // apply the staged load
					is_load <= 1'b1;
					silent <= 1'b1;
					op <= 1'b1;
					tmo <= 8'd0;
					ost <= O_WAITF;
				end else if ((start_lv && !s_ack) || (load_lv && !l_ack)) begin
					is_load <= !(start_lv && !s_ack);
					if (start_lv && !s_ack) s_busy <= 1'b1; else l_busy <= 1'b1;
					dly <= 3'd4;
					ost <= O_HS1;
				end
			end
			O_HS1: if (dly == 3'd0) begin
				s_ok <= 1'b0; s_err <= 1'b0; l_ok <= 1'b0; l_err <= 1'b0;
				dly <= 3'd4;
				ost <= O_HS2;
			end
			O_HS2: if (dly == 3'd0) begin
				if (is_load) l_ack <= 1'b1; else s_ack <= 1'b1;
				if (is_load) pend <= 1'b0;                // a new load replaces a staged one
				staged <= 1'b0;
				tmo <= 8'd0;
				op <= 1'b1;
				ost <= O_WAITF;
			end

			// the freeze: wait for it (a frame boundary with the console out of
			// reset and the peripherals quiet); a load while the console is in
			// reset (wake) is checked at once and applied at the reset's exit
			O_WAITF: begin
				if (cart_ready && refuse)
					ost <= O_FIN_ERR;                     // a scheme v1 does not save
				else if (settled) begin
					dly <= 3'd7;
					ost <= O_SETTLE;
				end else if (silent && mreset) begin      // reset again: wait for its exit
					op <= 1'b0;
					silent <= 1'b0;
					ost <= O_IDLE;
				end else if (is_load && !silent && mreset && cart_ready) begin
					staged <= 1'b1;
					w <= '0; crc <= 32'hFFFFFFFF; bad <= 1'b0;
					ost <= O_VHDR;
				end else if ((cart_ready && !mreset && tmo >= 8'd128) || tmo == 8'hFF)
					ost <= O_FIN_ERR;                     // no quiet point (the AtariVox speaks), or no cartridge
			end
			O_SETTLE: if (dly == 3'd0) begin
				w <= is_load ? WA'(0) : WA'(SS_W_CHAIN);
				bi <= 6'd0;
				crc <= 32'hFFFFFFFF;
				bad <= 1'b0;
				ost <= is_load ? O_VHDR : O_SCH;
			end

			// ---------------- save: the payload word by word, then the header
			O_SCH: begin                                  // one word of the chain, or a zero
				if (in_chain) begin
					if (bi == 6'd0) begin
						v <= 32'd0;
						ss_en <= 1'b1;
						rot <= 1'b1;
						bi <= 6'd1;
					end else begin
						v[32 - bi] <= ss_so;          // the bit this clock shifts out
						if (bi == nbits) begin
							ss_en <= 1'b0;
							rot <= 1'b0;
							bi <= 6'd0;
							ost <= O_SWR;
						end else
							bi <= bi + 6'd1;
					end
				end else if (in_cpad || in_gap) begin
					v <= 32'd0;
					ost <= O_SWR;
				end else if (in_riot || in_fa2) begin
					ss_ram <= 1'b1;
					ss_rsel <= in_riot ? 2'd0 : 2'd1;
					ss_ra <= rb_i;
					bi <= 6'd0;
					ost <= O_SRAM;
				end else if (in_avox) begin
					ss_ram <= 1'b1;
					ss_rsel <= 2'd2;
					ss_ra <= 8'(w - WA'(SS_W_AVOX));
					bi <= 6'd0;
					ost <= O_SRAMR;
				end else begin                            // cart RAM: 4 bytes through the SRAM port
					t_own <= 1'b1;
					t_rd <= 1'b1;
					t_wr <= 1'b0;
					t_addr <= cr_i;
					bi <= 6'd0;
					ost <= O_SCRAM;
				end
			end
			O_SRAM: begin                                 // a byte RAM: address bi + 1 out, byte bi in
				bi <= bi + 6'd1;
				ss_ra <= ss_ra + 8'd1;
				if (bi != 6'd0)
					v <= {v[23:0], ss_rq8};
				if (bi == 6'd4) begin
					ss_ram <= 1'b0;
					ost <= O_SWR;
				end
			end
			O_SRAMR: begin                                // the register file: one word
				bi <= bi + 6'd1;
				if (bi == 6'd1) begin
					v <= ss_rq32;
					ss_ram <= 1'b0;
					ost <= O_SWR;
				end
			end
			O_SCRAM: begin                                // 6 clk_sys an access (sram_ctrl.sv's budget, and more)
				bi <= bi + 6'd1;
				if (bi[2:0] == 3'd5) begin
					v <= {v[23:0], t_rdata};
					bi <= {bi[5:3] + 3'd1, 3'd0};
					t_addr <= t_addr + 17'd1;
					if (bi[5:3] == 3'd3) begin
						t_rd <= 1'b0;
						ost <= O_SWR;
					end
				end
			end
			O_SWR: begin                                  // v into the staging RAM at w, and the CRC
				sb_a <= w;
				sb_d <= v;
				sb_we <= 1'b1;
				bq <= 2'd0;
				ost <= O_SCRC;
			end
			O_SCRC: begin
				crc <= crc_byte(crc, v[31 - 8*bq -: 8]);
				bq <= bq + 2'd1;
				if (bq == 2'd3) begin
					if (w_last) begin
						w <= '0;
						ost <= O_HDR;
					end else begin
						w <= w + WA'(1);
						ost <= O_SCH;
					end
				end
			end
			O_HDR: begin
				sb_a <= w;
				sb_d <= hdr_exp(4'(w), ~crc);
				sb_we <= 1'b1;
				if (w == WA'(SS_HDR_WORDS - 1))
					ost <= O_FIN_OK;
				else
					w <= w + WA'(1);
			end

			// ---------------- load: the header, the payload's CRC, then apply
			O_VHDR: begin                                 // read word w (one clock)
				sb_a <= w;
				dly <= 3'd2;
				ost <= O_VHDR2;
			end
			O_VHDR2: if (dly == 3'd0) begin
				if (w == WA'(SS_H_CRC))
					hdr_crc <= sb_q;
				if ((sb_q & hdr_mask(4'(w))) != (hdr_exp(4'(w), 32'd0) & hdr_mask(4'(w))))
					bad <= 1'b1;
				if (w == WA'(SS_HDR_WORDS - 1)) begin
					w <= WA'(SS_W_CHAIN);
					ost <= O_VPAY;
				end else begin
					w <= w + WA'(1);
					ost <= O_VHDR;
				end
			end
			O_VPAY: begin
				if (bad)
					ost <= O_FIN_ERR;                     // foreign: no need to read on
				else begin
					sb_a <= w;
					dly <= 3'd2;
					ost <= O_VPAY2;
				end
			end
			O_VPAY2: if (dly == 3'd0) begin
				v <= sb_q;
				if ((in_cpad || in_gap) && sb_q != 32'd0) bad <= 1'b1;
				if (w_lastch && (sb_q & pad_mask) != 32'd0) bad <= 1'b1;
				bq <= 2'd0;
				ost <= O_VCRC;
			end
			O_VCRC: begin
				crc <= crc_byte(crc, v[31 - 8*bq -: 8]);
				bq <= bq + 2'd1;
				if (bq == 2'd3) begin
					if (w_last)
						ost <= O_VCHK;
					else begin
						w <= w + WA'(1);
						ost <= O_VPAY;
					end
				end
			end
			O_VCHK: begin
				if (bad || wbad_s || ~crc != hdr_crc)
					ost <= O_FIN_ERR;
				else if (staged)
					ost <= O_FIN_OK;                      // applied after the reset exit
				else begin
					w <= WA'(SS_W_CHAIN);
					ost <= O_AW;
				end
			end
			O_AW: begin                                   // apply word w: read it
				sb_a <= w;
				dly <= 3'd2;
				ost <= O_AW2;
			end
			O_AW2: if (dly == 3'd0) begin
				v <= sb_q;
				bi <= 6'd0;
				if (in_chain)
					ost <= O_ACH;
				else if (in_riot || in_fa2) begin
					ss_ram <= 1'b1;
					ss_rsel <= in_riot ? 2'd0 : 2'd1;
					ss_ra <= rb_i;
					ost <= O_ARAM;
				end else if (in_avox) begin
					ss_ram <= 1'b1;
					ss_rsel <= 2'd2;
					ss_ra <= 8'(w - WA'(SS_W_AVOX));
					ss_rd <= sb_q;
					ss_rwe <= 1'b1;
					ost <= O_ARAM;
					bi <= 6'd4;
				end else if (in_cram) begin
					t_own <= 1'b1;
					t_rd <= 1'b0;
					t_wr <= 1'b1;
					t_addr <= cr_i;
					t_wdata <= sb_q[31:24];
					ost <= O_ACRAM;
				end else
					ost <= O_ACRAM;                       // padding, gap: nothing to write
			end
			O_ACH: begin                                  // shift the word in, its bit 31 first
				if (bi == nbits) begin
					ss_en <= 1'b0;
					bi <= 6'd0;
					ost <= O_ACRAM;
				end else begin
					ss_en <= 1'b1;
					si_q <= v[31];
					v <= {v[30:0], 1'b0};
					bi <= bi + 6'd1;
				end
			end
			O_ARAM: begin                                 // a byte RAM: bytes 31-24 .. 7-0; the register file: one word
				if (bi == 6'd4) begin
					ss_ram <= 1'b0;
					ost <= O_ACRAM;
				end else begin
					ss_rd <= {24'd0, v[31:24]};
					ss_rwe <= 1'b1;
					if (bi != 6'd0)
						ss_ra <= ss_ra + 8'd1;
					v <= {v[23:0], 8'd0};
					bi <= bi + 6'd1;
				end
			end
			O_ACRAM: begin                                // the cart RAM's 4 bytes (6 clocks each), or the next word
				if (t_wr) begin
					bi <= bi + 6'd1;
					if (bi[2:0] == 3'd5) begin
						bi <= {bi[5:3] + 3'd1, 3'd0};
						t_addr <= t_addr + 17'd1;
						v <= {v[23:0], 8'd0};
						t_wdata <= v[23:16];
						if (bi[5:3] == 3'd3)
							t_wr <= 1'b0;
					end
				end else begin
					if (w_last)
						ost <= O_FIN_OK;
					else begin
						w <= w + WA'(1);
						ost <= O_AW;
					end
				end
			end

			// ---------------- the end
			O_FIN_OK, O_FIN_ERR: begin
				ss_en <= 1'b0;
				rot <= 1'b0;
				ss_ram <= 1'b0;
				t_own <= 1'b0;
				t_rd <= 1'b0;
				t_wr <= 1'b0;
				rel <= 1'b1;
				if (is_load) begin
					if (ost == O_FIN_OK && !staged) ld_applied <= 1'b1;
					if (staged) pend <= ost == O_FIN_OK;
					if (silent) pend <= 1'b0;
					if (!silent) begin
						if (ost == O_FIN_OK) l_ok <= 1'b1; else l_err <= 1'b1;
					end
				end else begin
					if (ost == O_FIN_OK) s_ok <= 1'b1; else s_err <= 1'b1;
				end
				dly <= 3'd4;
				ost <= O_FIN2;
			end
			O_FIN2: if (dly == 3'd0) begin
				s_busy <= 1'b0;
				l_busy <= 1'b0;
				op <= 1'b0;
				staged <= 1'b0;
				silent <= 1'b0;
				ost <= O_IDLE;
			end
			default: ost <= O_IDLE;
		endcase
	end

	/* verilator lint_on PROCASSINIT */
endmodule

`default_nettype wire

