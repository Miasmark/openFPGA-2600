// core_top.v with a stand-in wrapper (sim/make_wrap_stub.py) and stand-ins
// for the Intel IP (sim/core_top_stubs.sv, sim/sim_stubs.sv): what the APF
// host writes reaches the wrapper's ports as interact.json and data.json mean
// it. Run by sim/run_core_top.sh, which writes the stimulus from the JSON
// files (sim/check/apf_json_check.py --vectors, --plusargs).
//
// 1. Menu: every option of every interact.json item, written over the bridge
//    as the host writes it; after each write every setting port of the
//    wrapper (and core_top's audio mix and menu reset) must hold the value
//    the vectors give, so a write that reaches the wrong port fails too.
//    Includes both Mapper items and their priority, TV Type, both
//    Difficulty items and SaveKey.
// 2. Data table: the core side writes only the size fields of the save
//    slots, at data.json's indices, with data.json's sizes; read back over
//    the bridge as the host reads it (0xF8002000).
// 3. Downloads: the cartridge and Supercharger BIOS slots, announced with
//    the host's "data slot request write" command by data.json's ids and
//    written at data.json's addresses, reach the wrapper as cart_download /
//    arfw_download bytes in order from address 0; nothing else does.
// 4. Save slots: a write at data.json's SaveKey and FA2 addresses reaches the
//    wrapper's sk_/fa2_bridge port with the word address and data, and a
//    read returns that port's data.
// 5. Scaler slot: after each line the slot index in rgb[23:13] is
//    video.json's NTSC mode (160x240) or PAL mode (160x288), by the
//    wrapper's video_pal_o, whatever tia_mode_o says.
// Prints CORE_TOP pass or CORE_TOP FAIL.
`timescale 1ns/1ps
`default_nettype none
module tb_core_top;
	reg         clk_74a = 0;
	always #6.734 clk_74a = ~clk_74a;

	reg  [31:0] bridge_addr = 0;
	reg         bridge_rd = 0;
	reg         bridge_wr = 0;
	reg  [31:0] bridge_wr_data = 0;
	wire [31:0] bridge_rd_data;
	wire        bridge_endian_little;
	wire [23:0] video_rgb;
	wire        video_rgb_clock, video_de;

	core_top dut (
		.clk_74a              ( clk_74a ),
		.clk_74b              ( clk_74a ),
		.bridge_endian_little ( bridge_endian_little ),
		.bridge_addr          ( bridge_addr ),
		.bridge_rd            ( bridge_rd ),
		.bridge_rd_data       ( bridge_rd_data ),
		.bridge_wr            ( bridge_wr ),
		.bridge_wr_data       ( bridge_wr_data ),
		.cont1_key ( 32'd0 ), .cont2_key ( 32'd0 ), .cont3_key ( 32'd0 ), .cont4_key ( 32'd0 ),
		.cont1_joy ( 32'h00008080 ), .cont2_joy ( 32'h00008080 ),
		.cont3_joy ( 32'h00008080 ), .cont4_joy ( 32'h00008080 ),
		.cont1_trig ( 16'd0 ), .cont2_trig ( 16'd0 ), .cont3_trig ( 16'd0 ), .cont4_trig ( 16'd0 ),
		.video_rgb            ( video_rgb ),
		.video_rgb_clock      ( video_rgb_clock ),
		.video_de             ( video_de )
	);

	integer errors = 0;
	task automatic fail(input string s);
		begin
			$display("  FAIL %s", s);
			errors = errors + 1;
		end
	endtask

	task automatic wait74(input integer n);
		repeat (n) @(posedge clk_74a);
	endtask

	task automatic bwrite(input [31:0] a, input [31:0] d);
		begin
			@(posedge clk_74a);
			bridge_addr <= a; bridge_wr_data <= d; bridge_wr <= 1'b1;
			@(posedge clk_74a);
			bridge_wr <= 1'b0;
			wait74(4);
		end
	endtask

	task automatic bread(input [31:0] a, output [31:0] d);
		begin
			// The host's bridge sets the address well before its read strobe
			@(posedge clk_74a);
			bridge_addr <= a;
			wait74(4);
			bridge_rd <= 1'b1;
			@(posedge clk_74a);
			bridge_rd <= 1'b0;
			wait74(4);
			d = bridge_rd_data;
		end
	endtask

	task automatic host_cmd(input [15:0] cmd, input [31:0] p20, input [31:0] p24);
		reg [31:0] st;
		integer n;
		begin
			bwrite(32'hF8000020, p20);
			bwrite(32'hF8000024, p24);
			bwrite(32'hF8000000, {16'h434D, cmd});
			st = 0;
			for (n = 0; n < 50 && st[31:16] != 16'h4F4B; n = n + 1) bread(32'hF8000000, st);
			if (st[31:16] != 16'h4F4B || st[15:0] != 16'h0)
				fail($sformatf("host command %04h: status %08h", cmd, st));
		end
	endtask

	// The wrapper's setting ports, in apf_json_check.py's PORTS order
	function automatic [31:0] port_val(input integer p);
		case (p)
			0:  port_val = 32'(dut.atari.bs_override);
			1:  port_val = 32'(dut.atari.diff_left_b);
			2:  port_val = 32'(dut.atari.diff_right_b);
			3:  port_val = 32'(dut.atari.bw_setting);
			4:  port_val = 32'(dut.atari.savekey_setting);
			5:  port_val = 32'(dut.atari.swap_joysticks);
			6:  port_val = 32'(dut.atari.region_setting);
			7:  port_val = 32'(dut.atari.palette_temp);
			8:  port_val = 32'(dut.atari.port1_input);
			9:  port_val = 32'(dut.atari.port2_input);
			10: port_val = 32'(dut.atari.turbo);
			11: port_val = 32'(dut.atari.atarivox_setting);
			12: port_val = 32'(dut.atari.stereo_tia);
			13: port_val = 32'(dut.stmix);
			14: port_val = 32'(dut.atari.decomb);
			15: port_val = 32'(dut.atari.flicker_blend);
			16: port_val = 32'(dut.atari.reset_in);
			default: port_val = 32'hDEADBEEF;
		endcase
	endfunction
	string port_name [0:16] = '{"bs_override", "diff_left_b", "diff_right_b", "bw_setting",
		"savekey_setting", "swap_joysticks", "region_setting", "palette_temp", "port1_input",
		"port2_input", "turbo", "atarivox_setting", "stereo_tia", "stmix", "decomb",
		"flicker_blend", "menu_reset"};

	// Scaler slot monitor (clk_sys, as core_top sends it)
	integer ntsc_slot = 7, pal_slot = 7;
	integer slot_seen [0:1][0:1];      // [video_pal][tia_mode]
	integer slot_bad = 0;
	reg de_q = 0, pal_q = 0, tia_q = 0;
	initial begin
		slot_seen[0][0] = 0; slot_seen[0][1] = 0; slot_seen[1][0] = 0; slot_seen[1][1] = 0;
	end
	always @(posedge video_rgb_clock) begin
		if (de_q && !video_de) begin
			if (video_rgb[23:13] != 11'(pal_q ? pal_slot : ntsc_slot) || video_rgb[12:0] != 0) begin
				if (slot_bad < 5)
					$display("  FAIL scaler slot word %06h with video_pal %0d (expected slot %0d)",
						video_rgb, pal_q, pal_q ? pal_slot : ntsc_slot);
				slot_bad = slot_bad + 1;
			end else
				slot_seen[pal_q][tia_q] = slot_seen[pal_q][tia_q] + 1;
		end
		de_q  <= video_de;
		pal_q <= dut.atari.video_pal_o;
		tia_q <= dut.atari.tia_mode_o;
	end

	integer fd, kind, nchk, nwr, i, cart_id, arfw_id, sk_idx, sk_size, fa2_idx, fa2_size;
	reg [31:0] f1, f2, f3, f4, d, cart_addr, arfw_addr, sk_addr, fa2_addr;
	string line, vec;

	initial begin
		if (!$value$plusargs("vectors=%s", vec)) begin $display("CORE_TOP FAIL (no +vectors)"); $finish; end
		void'($value$plusargs("cart_id=%h", cart_id));
		void'($value$plusargs("arfw_id=%h", arfw_id));
		void'($value$plusargs("cart_addr=%h", cart_addr));
		void'($value$plusargs("arfw_addr=%h", arfw_addr));
		void'($value$plusargs("sk_addr=%h", sk_addr));
		void'($value$plusargs("fa2_addr=%h", fa2_addr));
		void'($value$plusargs("sk_idx=%d", sk_idx));
		void'($value$plusargs("sk_size=%d", sk_size));
		void'($value$plusargs("fa2_idx=%d", fa2_idx));
		void'($value$plusargs("fa2_size=%d", fa2_size));
		void'($value$plusargs("ntsc_slot=%d", ntsc_slot));
		void'($value$plusargs("pal_slot=%d", pal_slot));

		wait (dut.pll_core_locked_s);
		wait74(200);
		host_cmd(16'h0011, 0, 0);       // reset exit: reset_in follows the menu's Reset alone
		wait74(50);
		if (dut.atari.reset_in !== 1'b0) fail("reset_in still high after the host's reset exit");

		// 1. Menu
		$display("-- menu: interact.json writes and the wrapper's setting ports");
		fd = $fopen(vec, "r");
		nchk = 0; nwr = 0;
		while ($fgets(line, fd)) begin
			f1 = 0; f2 = 0; f3 = 0; f4 = 0;
			if ($sscanf(line, "%h %h %h %h", f1, f2, f3, f4) < 4) continue;
			kind = f1;
			if (kind == 0) break;
			if (kind == 1) begin
				bwrite(f2, f3);
				wait74(f4);
				nwr = nwr + 1;
			end else if (kind == 3) begin
				wait74(f4);
			end else if (kind == 2) begin
				nchk = nchk + 1;
				if (port_val(f2) != f3)
					fail($sformatf("after write %0d: %s = %0h, expected %0h", nwr, port_name[f2], port_val(f2), f3));
			end
		end
		$fclose(fd);
		$display("  %0d writes, %0d port checks", nwr, nchk);

		// 2. Data table
		$display("-- data table: save slot sizes at data.json's indices");
		wait74(20);
		for (i = 0; i < 256; i = i + 1)
			if (dut.icb.idt.written_a[i] != (i == sk_idx * 2 + 1 || i == fa2_idx * 2 + 1))
				fail($sformatf("data table entry %0d written by the core: %0d", i, dut.icb.idt.written_a[i]));
		bread(32'hF8002000 + (sk_idx * 2 + 1) * 4, d);
		if (d != sk_size) fail($sformatf("SaveKey (slot %0d) size %0d, expected %0d", sk_idx, d, sk_size));
		else $display("  slot %0d (SaveKey) size %0d", sk_idx, d);
		bread(32'hF8002000 + (fa2_idx * 2 + 1) * 4, d);
		if (d != fa2_size) fail($sformatf("FA2 (slot %0d) size %0d, expected %0d", fa2_idx, d, fa2_size));
		else $display("  slot %0d (FA2) size %0d", fa2_idx, d);

		// 3. Downloads
		$display("-- downloads: cartridge (id %0h at %08h) and Supercharger BIOS (id %0h at %08h)",
			cart_id, cart_addr, arfw_id, arfw_addr);
		host_cmd(16'h0082, cart_id, 8);
		bwrite(cart_addr, 32'hC0C1C2C3); wait74(120);
		bwrite(cart_addr + 4, 32'hC4C5C6C7); wait74(120);
		host_cmd(16'h008F, 0, 0);
		wait74(100);
		host_cmd(16'h0082, arfw_id, 8);
		bwrite(arfw_addr, 32'hA0A1A2A3); wait74(120);
		bwrite(arfw_addr + 4, 32'hA4A5A6A7); wait74(120);
		host_cmd(16'h008F, 0, 0);
		wait74(100);
		if (dut.atari.cart_n != 8 || dut.atari.arfw_n != 8)
			fail($sformatf("download bytes: cartridge %0d, BIOS %0d (expected 8 each)", dut.atari.cart_n, dut.atari.arfw_n));
		for (i = 0; i < 8; i = i + 1) begin
			if (dut.atari.cart_b[i] != 8'hC0 + 8'(i) || dut.atari.cart_a[i] != 25'(i))
				fail($sformatf("cartridge byte %0d: %02h at %0h", i, dut.atari.cart_b[i], dut.atari.cart_a[i]));
			if (dut.atari.arfw_b[i] != 8'hA0 + 8'(i) || dut.atari.arfw_a[i] != 25'(i))
				fail($sformatf("BIOS byte %0d: %02h at %0h", i, dut.atari.arfw_b[i], dut.atari.arfw_a[i]));
		end
		$display("  cartridge %0d bytes, BIOS %0d bytes", dut.atari.cart_n, dut.atari.arfw_n);

		// 4. Save slots
		$display("-- save slots: SaveKey at %08h, FA2 at %08h", sk_addr, fa2_addr);
		bwrite(sk_addr + 32'h7FFC, 32'h5AFE0001);
		bwrite(fa2_addr + 32'hFC, 32'hFA2FA2FA);
		if (dut.atari.sk_wr_n != 1 || dut.atari.sk_wr_addr != 13'h1FFF || dut.atari.sk_wr_data != 32'h5AFE0001)
			fail($sformatf("SaveKey write: %0d, word %0h, data %08h", dut.atari.sk_wr_n, dut.atari.sk_wr_addr, dut.atari.sk_wr_data));
		if (dut.atari.fa2_wr_n != 1 || dut.atari.fa2_wr_addr != 6'h3F || dut.atari.fa2_wr_data != 32'hFA2FA2FA)
			fail($sformatf("FA2 write: %0d, word %0h, data %08h", dut.atari.fa2_wr_n, dut.atari.fa2_wr_addr, dut.atari.fa2_wr_data));
		bread(sk_addr + 32'h10, d);
		if (d != 32'h5E000004) fail($sformatf("SaveKey read %08h", d));
		bread(fa2_addr + 32'h10, d);
		if (d != 32'hFA200004) fail($sformatf("FA2 read %08h", d));
		if (dut.atari.sk_rd_n != 1 || dut.atari.fa2_rd_n != 1)
			fail($sformatf("save slot read strobes: SaveKey %0d, FA2 %0d", dut.atari.sk_rd_n, dut.atari.fa2_rd_n));
		$display("  SaveKey %0d write(s), %0d read(s); FA2 %0d write(s), %0d read(s)",
			dut.atari.sk_wr_n, dut.atari.sk_rd_n, dut.atari.fa2_wr_n, dut.atari.fa2_rd_n);

		// 5. Scaler slot, with each video_pal (Region) and tia_mode (Palette bit 0)
		$display("-- scaler slot: NTSC %0d, PAL %0d", ntsc_slot, pal_slot);
		bwrite(32'h1000026C, 1); bwrite(32'h10000270, 0); wait74(4000);
		bwrite(32'h10000270, 1); wait74(4000);
		bwrite(32'h1000026C, 2); wait74(4000);
		bwrite(32'h10000270, 0); wait74(4000);
		$display("  slot words: NTSC %0d / %0d, PAL %0d / %0d (tia_mode 0 / 1), wrong %0d",
			slot_seen[0][0], slot_seen[0][1], slot_seen[1][0], slot_seen[1][1], slot_bad);
		if (slot_bad != 0 || slot_seen[0][0] == 0 || slot_seen[0][1] == 0 || slot_seen[1][0] == 0 || slot_seen[1][1] == 0)
			fail("scaler slot");

		$display("CORE_TOP %s", errors == 0 ? "pass" : $sformatf("FAIL (%0d)", errors));
		$finish;
	end

	initial begin
		#20ms;
		$display("CORE_TOP FAIL (timeout)");
		$finish;
	end
endmodule
`default_nettype wire
