// The AtariVox's voice for the Pocket (docs/ATARIVOX.md): the SpeakJet's
// serial input and buffer (avox_rx) and a speech engine of our own
// (avox_engine) that plays its codes with our sound tables. The SaveKey
// half of the AtariVox is the core's savekey EEPROM, as before.
//
// Port 2: `line` is the UP pin as the console drives it; `down_n` goes to
// the DOWN pin and is low while the buffer is half full.
//
// Save states (docs/SAVESTATE.md): the scan chain runs through div, avox_rx
// and avox_engine (ss_si to ss_so, 235 bits); the engine's register file
// through its state port (ss_ram). `quiet`: nothing coming in or waiting,
// and the voice silent (the engine's sample 0) for 4,096 ticks (0.25 s).
//
// MIT licence, as the rest of the Pocket port's own code.

module atarivox (
	input  logic               ss_en,       // save states: shift the chain
	input  logic               ss_frz,      // hold every register
	input  logic               ss_si,
	output logic               ss_so,
	input  logic               ss_ram,      // the register file's state port
	input  logic        [7:0]  ss_ra,
	input  logic               ss_rwe,
	input  logic       [31:0]  ss_rd,
	output logic       [31:0]  ss_rq,
	output logic               quiet,
	input  logic               clk,         // clk_sys
	input  logic               reset,
	input  logic               pal,         // clk_sys is the PAL frequency

	input  logic               line,
	output logic               down_n,

	output logic signed [15:0] sample       // 16,384 Hz, held; full scale about +-4096 x master/128
);

	// 16,384 Hz from clk_sys: 874 x 16,384 = 14.32 MHz (NTSC), 866 for PAL
	// (14.19 MHz); both within 0.1%.
	/* verilator lint_off PROCASSINIT */  // power-up value (DEVELOPING.md, "Power-up values")
	logic [9:0] div = 10'd0;
	/* verilator lint_on PROCASSINIT */
	wire  [9:0] div_last = pal ? 10'd865 : 10'd873;
	wire        tick = (div == div_last);
	logic ss_c1, ss_c2;
	always_ff @(posedge clk)
		if (ss_en)
			div <= {ss_si, div[9:1]};
		else if (!ss_frz)
			div <= (reset || tick) ? 10'd0 : div + 10'd1;

	logic       abort_set, ready_set, pop, nonempty, half_full;
	logic [7:0] q;

	logic rx_idle;
	avox_rx rx (
		.ss_en     (ss_en),
		.ss_frz    (ss_frz),
		.ss_si     (div[0]),
		.ss_so     (ss_c1),
		.idle      (rx_idle),
		.clk       (clk),
		.reset     (reset),
		.line      (line),
		.abort_set (abort_set),
		.ready_set (ready_set),
		.pop       (pop),
		.q         (q),
		.nonempty  (nonempty),
		.half_full (half_full)
	);

	avox_engine engine (
		.ss_en         (ss_en),
		.ss_frz        (ss_frz),
		.ss_si         (ss_c1),
		.ss_so         (ss_c2),
		.ss_ram        (ss_ram),
		.ss_ra         (ss_ra),
		.ss_rwe        (ss_rwe),
		.ss_rd         (ss_rd),
		.ss_rq         (ss_rq),
		.clk           (clk),
		.reset         (reset),
		.tick          (tick),
		.abort_set     (abort_set),
		.ready_set     (ready_set),
		.fifo_q        (q),
		.fifo_nonempty (nonempty),
		.fifo_pop      (pop),
		.sample        (sample),
		/* verilator lint_off PINCONNECTEMPTY */  // the held sample is enough
		.sample_strobe ()
		/* verilator lint_on PINCONNECTEMPTY */
	);

	assign down_n = ~half_full;
	assign ss_so  = ss_c2;

	// quiet: rx idle and the sample 0 for 4,096 ticks. Not machine state
	// (not chained): it holds while the voice is held (a shifting chain
	// shows it arbitrary samples), so a save does not restart it.
	/* verilator lint_off PROCASSINIT */
	logic [12:0] qcnt = 13'd0;
	/* verilator lint_on PROCASSINIT */
	always_ff @(posedge clk)
		if (reset)
			qcnt <= 13'h1000;
		else if (ss_en || ss_frz)
			qcnt <= qcnt;
		else if (!rx_idle || sample != 16'sd0)
			qcnt <= 13'd0;
		else if (tick && !qcnt[12])
			qcnt <= qcnt + 13'd1;
	assign quiet = rx_idle && qcnt[12];

endmodule
