#!/bin/bash
# tb_paddles4: paddle_timer4.sv (the four paddle timers with one shared
# calibration engine) against four of MiSTer's paddle_timer, on every clock
# of four random-stimulus seeds (2 x 10^7 clocks each by default; seeds 3
# and 4 with the clock enable dropping at random), and two planted faults
# the bench must catch: the engine reads paddle 0's `cleared` for every
# paddle, and a pending width is dropped in a dump. Seeds 2 and 4 also save
# and load the save-state chain (+chain=696) about every 200,000 clocks; the
# same with the chain one bit short (695) must be caught.
# run_sim.sh runs it after tb_vaxis5; it also runs alone.
#   sim/run_paddles4.sh
# Environment (all optional):
#   WORK=DIR       build and log directory (default sim/work/paddles4)
#   VERILATOR=BIN  the Verilator to use (5.040; PATH's otherwise)
#   RTL_TREE=DIR   the RTL of another checkout (DIR/src/fpga), as run_sim.sh
#   SEEDS="1 2"  CE_SEEDS="3 4"  CYCLES=20000000  per seed
# Prints one "PADDLES4 seed ..." line per seed with its coverage, the
# planted faults' lines and "PADDLES4 pass" or "PADDLES4 FAIL"; exit status
# 0 on pass, 1 otherwise.
# SPDX-License-Identifier: MIT
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FPGA="${RTL_TREE:-$HERE/..}/src/fpga"
WORK="${WORK:-$HERE/work/paddles4}"
V="${VERILATOR:-verilator}"
SEEDS="${SEEDS:-1 2}"
CE_SEEDS="${CE_SEEDS:-3 4}"
CYCLES="${CYCLES:-20000000}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
SRC="$FPGA/core/paddle_timer4.sv"
# paddles.sv assigns its `output charged` (a wire) from an always block,
# which Quartus allows and Verilator does not (as run_sim.sh patches it).
sed -E 's/^(\s*)output(\s+)charged,/\1output logic\2charged,/' "$FPGA/mister/rtl/paddles.sv" > "$WORK/paddles.sv"

build() {   # build <objdir> <paddle_timer4 source>
	"$V" --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style --top-module tb_paddles4 -Mdir "$WORK/$1" -o vtb \
		"$WORK/paddles.sv" "$2" "$HERE/tb_paddles4.sv" > "$WORK/$1.log" 2>&1 \
		|| { echo "PADDLES4 build of $1 failed:"; grep -m20 "%Error" "$WORK/$1.log"; echo "PADDLES4 FAIL"; exit 1; }
}
plant() {   # plant <name> <sed expression>: one line changed
	sed "$2" "$SRC" > "$WORK/$1.sv"
	if [ "$(diff "$SRC" "$WORK/$1.sv" | grep -c '^>')" != 1 ]; then
		echo "PADDLES4 the planted fault $1 did not apply to $SRC (one changed line expected)"; echo "PADDLES4 FAIL"; exit 1
	fi
	build "obj_$1" "$WORK/$1.sv"
}

build obj_good "$SRC"
plant cleared0 's/^\(\twire        e_go  = ce \&\& e_act \&\& !clear \&\& \)p_cleared\[sel\];/\1p_cleared[0];/'
plant dropwidth 's/^\(\t\t\t\tif (dump_done) begin\)$/\1 pend <= 1'"'"'b0;/'

ok=1
for s in $SEEDS $CE_SEEDS; do
	ce=""; [[ " $CE_SEEDS " == *" $s "* ]] && ce="+ce"
	# seeds 2 and 4 also save and load the chain (the save-state scan chain)
	ch=""; [ $((s % 2)) = 0 ] && ch="+chain=696"
	"$WORK/obj_good/vtb" +seed="$s" +cycles="$CYCLES" $ce $ch > "$WORK/seed_$s.log" 2>&1 || ok=0
	grep -m10 '^MISMATCH' "$WORK/seed_$s.log"
	line="$(grep -m1 '^PADDLES4 seed' "$WORK/seed_$s.log")"
	echo "${line:-PADDLES4 seed $s: no result line (see $WORK/seed_$s.log)}"
	grep -E '^PADDLES4 (coverage|chain)' "$WORK/seed_$s.log" | sed 's/^/  /'
	[[ "$line" =~ \ mismatches\ 0$ ]] || ok=0
done
# the chain one bit short: the load must be seen
"$WORK/obj_good/vtb" +seed=2 +cycles="$CYCLES" +chain=695 > "$WORK/planted_chain.log" 2>&1
pm="$(sed -n 's/^PADDLES4 seed .* mismatches \([0-9]*\)$/\1/p' "$WORK/planted_chain.log")"
if [ -n "$pm" ] && [ "$pm" -gt 0 ]; then
	echo "PADDLES4 planted fault (the chain shifted one bit short), seed 2: caught, $pm mismatches"
else
	echo "PADDLES4 planted fault (the chain shifted one bit short), seed 2: NOT caught (${pm:-no result line})"; ok=0
fi
for f in cleared0:"the engine reads paddle 0's cleared" dropwidth:"a pending width dropped in a dump"; do
	n="${f%%:*}"; what="${f#*:}"
	"$WORK/obj_$n/vtb" +seed=1 +cycles="$CYCLES" > "$WORK/planted_$n.log" 2>&1
	pm="$(sed -n 's/^PADDLES4 seed .* mismatches \([0-9]*\)$/\1/p' "$WORK/planted_$n.log")"
	if [ -n "$pm" ] && [ "$pm" -gt 0 ]; then
		echo "PADDLES4 planted fault ($what), seed 1: caught, $pm mismatches"
	else
		echo "PADDLES4 planted fault ($what), seed 1: NOT caught (${pm:-no result line})"; ok=0
	fi
done
[ "$ok" = 1 ] && { echo "PADDLES4 pass"; exit 0; }
echo "PADDLES4 FAIL"; exit 1
