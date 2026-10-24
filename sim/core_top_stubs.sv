// Stand-ins for core_top.v's Intel IP in sim/tb_core_top.sv (not for any
// other bench): the PLL gives free-running clocks at the NTSC rates, the PLL
// reconfiguration block answers at once, and the APF data table is a plain
// dual-port RAM that also records which addresses its core side wrote.
// sound_i2s's sync_fifo (its dcfifo has ports sim_stubs.sv's model lacks)
// is a stand-in too: the bench does not look at the audio.
`timescale 1ns/1ps
/* verilator lint_off UNUSEDSIGNAL */
module pll_core (
	input  wire        refclk,
	input  wire        rst,
	output reg         outclk_0,     // clk_sys     14.318 MHz
	output reg         outclk_1,     // clk_sdram   4 x clk_sys, edge aligned
	output reg         outclk_2,     // clk_sys_90
	output reg         outclk_3,     // clk_arm
	output reg         locked,
	input  wire [63:0] reconfig_to_pll,
	output wire [63:0] reconfig_from_pll
);
	reg [1:0] div = 2'd0;
	initial begin
		outclk_0 = 0; outclk_1 = 0; outclk_2 = 0; outclk_3 = 0; locked = 0;
		#2000 locked = 1;
	end
	always #8.730 outclk_1 = ~outclk_1;
	always #13.096 outclk_3 = ~outclk_3;
	always @(posedge outclk_1) begin
		div <= div + 2'd1;
		if (div == 2'd1) outclk_0 <= 1'b1;
		if (div == 2'd3) outclk_0 <= 1'b0;
	end
	always @(outclk_0) outclk_2 <= #17.46 outclk_0;
	assign reconfig_from_pll = 64'd0;
endmodule

module pll_cfg (
	input  wire        mgmt_clk,
	input  wire        mgmt_reset,
	output wire        mgmt_waitrequest,
	input  wire        mgmt_read,
	output wire [31:0] mgmt_readdata,
	input  wire        mgmt_write,
	input  wire  [5:0] mgmt_address,
	input  wire [31:0] mgmt_writedata,
	output wire [63:0] reconfig_to_pll,
	input  wire [63:0] reconfig_from_pll
);
	assign mgmt_waitrequest = 1'b0;
	assign mgmt_readdata = 32'd0;
	assign reconfig_to_pll = 64'd0;
endmodule

module mf_datatable (
	input  wire  [7:0] address_a,
	input  wire  [7:0] address_b,
	input  wire        clock_a,
	input  wire        clock_b,
	input  wire [31:0] data_a,
	input  wire [31:0] data_b,
	input  wire        wren_a,
	input  wire        wren_b,
	output reg  [31:0] q_a,
	output reg  [31:0] q_b
);
	reg  [31:0] mem [0:255];
	reg [255:0] written_a = 256'd0;   // addresses the core side has written
	integer i;
	initial for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;
	always @(posedge clock_a) begin
		if (wren_a) begin mem[address_a] <= data_a; written_a[address_a] <= 1'b1; end
		q_a <= mem[address_a];
	end
	always @(posedge clock_b) begin
		if (wren_b) mem[address_b] <= data_b;
		q_b <= mem[address_b];
	end
endmodule
module sync_fifo #(parameter WIDTH = 2) (
	input  wire             clk_write,
	input  wire             clk_read,
	input  wire             write_en,
	input  wire [WIDTH-1:0] data,
	output reg  [WIDTH-1:0] data_s = 0,
	output reg              write_en_s = 0
);
endmodule
/* verilator lint_on UNUSEDSIGNAL */
