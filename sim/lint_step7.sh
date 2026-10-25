#!/bin/bash
# Verilator -Wall lint of DARIA step 7's three macro sets (docs/daria_step7/
# plan.md 3.3 item 1), each against the same set on a base revision: no
# warning may be added (counted: a warning text that appears once more is
# added too). Warnings removed are listed and allowed.
#   sim/lint_step7.sh [--out DIR] [--base REV] [--debug]
# Sets (ap_core.qsf's VERILOG_MACROs, read from the tree's qsf):
#   daria    the qsf's macros plus POCKET_DARIA, top atari2600_pocket
#   nodaria  the qsf's macros without POCKET_DARIA, top atari2600_pocket
#   (the 7800 core's third set, run_daria.sh's WRAPPER set with top
#   tb_daria, upstream's ARM as the oracle, is gone: openFPGA-2600 keeps no
#   oracle RTL, and R1 runs from the openFPGA-7800 checkout, plan O2)
#   debug    with --debug only: the daria set plus BUP_DEBUG (a hardware
#            test build's, Q5's), top atari2600_pocket, for a change seen
#            only under BUP_DEBUG (plan 7.6), such as the status overlay
#   debug_nodaria  with --debug only: the nodaria set plus BUP_DEBUG (a
#            BupChip-only hardware test build), top atari2600_pocket: the
#            status overlay's DARIA ports are there too, tied to 0
# The base (default 73fd755, openFPGA-2600's system module once cut, plan
# step 4; give a step's own base with --base) is taken with git archive into
# the output directory, so neither tree is written. Warnings are compared
# with the tree's path and the line and column numbers removed. A base from
# before the wrapper's rename to atari2600_pocket (openFPGA-2600 step 2) is
# linted with its own atari*_pocket.sv as top, and its warnings are read with
# the new name.
# Environment: VERILATOR (default /opt/verilator-5.040/bin/verilator).
# Exit status 0 when no set adds a warning, 1 otherwise, 2 on a usage or
# tool error. SPDX-License-Identifier: MIT
set -u
export LC_ALL=C
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$HERE/work/step7/lint"
BASE=73fd755
SETS="daria nodaria"
while [ $# -gt 0 ]; do
	case "$1" in
		--out) OUT="$2"; shift 2 ;;
		--base) BASE="$2"; shift 2 ;;
		--debug) SETS="$SETS debug debug_nodaria"; shift ;;
		*) echo "lint_step7.sh: unknown argument $1" >&2; exit 2 ;;
	esac
done
V="${VERILATOR:-/opt/verilator-5.040/bin/verilator}"
[ -x "$V" ] || V=verilator
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
echo "-- lint_step7.sh: tree $REPO HEAD $(git -C "$REPO" rev-parse HEAD), base $BASE ($(git -C "$REPO" rev-parse "$BASE" 2>/dev/null))"
echo "-- status: [$(git -C "$REPO" status --porcelain | tr '\n' ';')]"
echo "-- tool: $V ($("$V" --version)), --lint-only -Wall (no binary)"

rm -rf "$OUT/base"; mkdir -p "$OUT/base"
git -C "$REPO" archive "$BASE" src/fpga sim/sim_stubs.sv sim/bupchip/s4/psram_model.sv sim/bupchip/daria \
	| tar -x -C "$OUT/base" || { echo "lint_step7.sh: git archive $BASE failed" >&2; exit 2; }

# lint TREE SET DIR: DIR/SET.raw (Verilator's output), DIR/SET.norm (normalised warnings, one per line, sorted)
lint() {
	local T="$1" SET="$2" D="$3" FPGA RTL B P QSF_DEFS DEFS SRCS TOP
	FPGA="$T/src/fpga"; RTL="$FPGA/mister/rtl"; B="$FPGA/core/bupchip"; P="$D/patched_$SET"
	# the wrapper; a tree from before the rename has one atari*_pocket.sv
	local W="$FPGA/core/atari2600_pocket.sv"
	[ -f "$W" ] || W="$(ls "$FPGA"/core/atari*_pocket.sv | head -1)"
	mkdir -p "$P"
	# Verilator 5.040 rejects initialised unpacked wires and paddles.sv's
	# always-driven output; patched copies, as run_sim.sh simulates them
	for f in Maria/control.sv banks2600.sv video_mux.sv RIOT/M6532.sv; do
		[ -f "$RTL/$f" ] || continue   # control.sv: trees before openFPGA-2600 step 4
		mkdir -p "$P/$(dirname "$f")"
		sed -E 's/^(\s*)wire(\s+\[[^]]+\]\s+\w+\s*\[[0-9]+\]\s*=)/\1logic\2/' "$RTL/$f" > "$P/$f"
	done
	sed -E 's/^(\s*)output(\s+)charged,/\1output logic\2charged,/' "$RTL/paddles.sv" > "$P/paddles.sv"
	local CORE=("$T/sim/sim_stubs.sv" "$RTL/arm7tdmi/arm7tdmi_pkg.sv" "$RTL/6502/mos6502_pkg.sv"
		$(ls "$RTL"/6502/*.sv | grep -v pkg)
		$(ls "$RTL"/Maria/*.sv | grep -v control.sv) "$P/Maria/control.sv"
		$(ls "$RTL"/Pokey/*.sv 2> /dev/null)
		$(sed -n 's/.*qip_path) \(.*\.sv\) *\].*/\1/p' "$RTL/Minnie/Minnie.qip" 2> /dev/null | sed "s#^#$RTL/Minnie/#")
		"$RTL/SN76489/sn76489.sv" "$RTL"/jt51/*.v "$RTL/cache_ram.v" "$RTL/bram.v"
		"$RTL/composite_out.sv" "$RTL/cart_ram_tdp.sv" "$RTL/cdf_fastjump_table.sv"
		"$RTL"/arm_mapper_{memory,controller,subsystem,tables,ram_init,writeback,audio}.sv
		"$RTL"/mapper_{dpcplus,cdf,bus,fa2}.sv "$RTL/fa2_nvram_bridge.sv"
		"$RTL/ps2_to_pokey.v" "$RTL/souper.v" "$RTL/TIA.sv" "$RTL/cart.sv"
		"$RTL/cart2600.sv" "$P/banks2600.sv" "$P/video_mux.sv"
		"$RTL/detect2600.sv" "$RTL/a78_cart_extent.sv" "$P/RIOT/M6532.sv" "$RTL/top.sv")
	# openFPGA-2600 step 4 removed the 7800 cartridge (cart.sv and its sound
	# chips) and MARIA's video and DMA: a tree past it lints without them
	# (POKEY's files stayed for its own benches until step 6 removed both)
	local C=() g
	for g in "${CORE[@]}"; do
		[ -e "$g" ] || continue
		[ -f "$RTL/cart.sv" ] || case "$g" in "$RTL"/Pokey/*) continue ;; esac
		C+=("$g")
	done
	CORE=("${C[@]}")
	local DARIA=("$B/daria_mem.sv" "$B/daria_call.sv" "$B/daria_mmio.sv")
	local f
	for f in daria_smp bup_dbg_snap; do [ -f "$B/$f.sv" ] && DARIA+=("$B/$f.sv"); done
	local FE=("$B/daria_fe_pkg.sv" $(ls "$B"/daria_fe_*.sv | grep -v daria_fe_pkg.sv) "$B/daria_fe.sv")
	local BUP=("$RTL/bupchip_peripheral.sv" "$FPGA/pocket_utils/psram.sv"
		"$B"/{bup_cpu,bup_capture,bup_asset_wr,bup_asset_cache,bup_tick48k,bup_load_probe,bup_status_osd,bupchip_pocket}.sv)
	# the qsf's macros, from the tree being linted
	QSF_DEFS=($(sed -n 's/^set_global_assignment -name VERILOG_MACRO "\([A-Za-z0-9_]*\)=\(.*\)"$/-D\1=\2/p' "$FPGA/ap_core.qsf" \
		| grep -v '^-DPOCKET_DARIA='))
	case "$SET" in
		daria|nodaria|debug|debug_nodaria)
			DEFS=("${QSF_DEFS[@]}"); [ "$SET" = daria ] || [ "$SET" = debug ] && DEFS+=(-DPOCKET_DARIA=1)
			[ "$SET" = debug ] || [ "$SET" = debug_nodaria ] && DEFS+=(-DBUP_DEBUG=1)
			SRCS=("${CORE[@]}" "$RTL/EEPROM_24LC256.sv" "$W"
				"$FPGA/core/virtual_axis.sv" "$FPGA/core/stick_dirs.sv" "$FPGA/core/sram_ctrl.sv" "$P/paddles.sv"
				"$RTL/lightgun.sv" "$FPGA/pocket_utils/data_loader.sv" "$FPGA/core/audio_filter.sv" "${BUP[@]}")
			# the five virtual axes as one engine (virtual_axis5.sv); trees before it have none
			[ -f "$FPGA/core/virtual_axis5.sv" ] && SRCS+=("$FPGA/core/virtual_axis5.sv")
			# the AtariVox (32e3ede), in core.qip's order; trees before it have none
			for f in avox_rx avox_engine atarivox; do
				[ -f "$FPGA/core/atarivox/$f.sv" ] && SRCS+=("$FPGA/core/atarivox/$f.sv")
			done
			[ "$SET" = daria ] || [ "$SET" = debug ] && SRCS+=("${DARIA[@]}" "${FE[@]}")
			TOP="$(basename "$W" .sv)" ;;
	esac
	(cd "$D" && nice -n 10 "$V" --lint-only -Wall --timing -Wno-fatal "${DEFS[@]}" --top-module "$TOP" \
		-Mdir "$D/mdir_$SET" "${SRCS[@]}") > "$D/$SET.raw" 2>&1
	local rc=$?
	grep -E '^%(Warning|Error)' "$D/$SET.raw" | sed -E "s#$P/#PATCHED/#g; s#$T/##g; s#:[0-9]+:[0-9]+:#:#g; s#atari[0-9]+_pocket#atari2600_pocket#g" \
		| sort > "$D/$SET.norm"
	echo "   $SET: rc $rc, $(grep -c '^%Warning' "$D/$SET.raw") warnings, $(grep -c '^%Error' "$D/$SET.raw") errors"
	[ "$rc" = 0 ] && ! grep -q '^%Error' "$D/$SET.raw"
}

fail=0
for set in $SETS; do
	echo "== $set"
	mkdir -p "$OUT/head" "$OUT/base_lint"
	lint "$OUT/base" "$set" "$OUT/base_lint" || { echo "   base: lint error (see $OUT/base_lint/$set.raw)"; fail=1; }
	lint "$REPO" "$set" "$OUT/head" || { echo "   HEAD: lint error (see $OUT/head/$set.raw)"; fail=1; }
	added="$(comm -13 "$OUT/base_lint/$set.norm" "$OUT/head/$set.norm")"
	removed="$(comm -23 "$OUT/base_lint/$set.norm" "$OUT/head/$set.norm")"
	echo "   added: $(printf '%s' "$added" | grep -c .), removed: $(printf '%s' "$removed" | grep -c .)"
	[ -n "$removed" ] && printf '%s\n' "$removed" | sort | uniq -c | sed 's/^/   < /'
	if [ -n "$added" ]; then
		printf '%s\n' "$added" | sort | uniq -c | sed 's/^/   > /'
		fail=1
	fi
done
[ $fail = 0 ] && echo "LINT pass: no warning added in any set" || echo "LINT FAIL"
exit $fail
