#!/bin/bash
# Build and run the whole-core simulation (tested with Verilator 5.040;
# point VERILATOR at the binary if it is not the one on PATH).
#   ./run_sim.sh
# openFPGA-2600 (plan step 6): the 2600 cases of the 7800 core's run_sim.sh,
# without its 7800 sections (the 7800-mode tones and MARIA's geometry, the
# BIOS boot rule, the BupChip end to end, the POKEY reads), and two reloads.
# Environment (all optional; without them the runs are as they always were):
#   WORK=DIR       work directory (default sim/work)
#   VERILATOR=BIN  the Verilator to use (5.040; PATH's otherwise)
#   VL_JOBS=N      build parallelism (default 4)
#   DARIA=0|1      POCKET_DARIA off or on; default: as ap_core.qsf sets it
#   BUP_DEBUG=0|1, BUPCHIP=0, SRAM=0: as below
#   FP=1           every run also writes its per-frame fingerprint (tb_load's
#                  and tb_system's +fp) to $WORK/fp/<case>.csv, for comparing
#                  two builds frame by frame (sim/check/frame_gate.py --strict)
#   ARM_DIV=19     the DARIA build's clk_arm at VCO/19 instead of VCO/18 (the
#                  benches' default, pll_core.v's divider)
#   RTL_TREE=DIR   build the RTL of another checkout (DIR/src/fpga) with this
#                  checkout's benches, e.g. a lane's worktree
#   BUILD_TOP=TOP  only build the bench TOP (tb_system, tb_load,
#                  tb_cartram or tb_frames) into $WORK/obj_TOP and stop;
#                  tb_frames is built without BUP_DEBUG and with -O3
#                  --x-assign fast --x-initial fast, as run_daria.sh builds
#                  tb_daria (docs/daria_step7/plan.md 3.6 I4c)
#   FRAMES_DEBUG=1 build tb_frames with BUP_DEBUG all the same: its DARIA
#                  status overlay checks (sim/tb_frames.sv's header). The
#                  build writes WORK/obj_frames.mode ("FRAMES_DEBUG=0|1 md5
#                  <the binary's>"), which sim/run_frames.sh checks
#   ONLY=daria     build tb_load alone and run only the DARIA section (below),
#                  e.g. the BUP_DEBUG overlay check at another divider or on
#                  a scratch tree (sim/bupchip/dstat/run_ovl.sh); its log is
#                  checked with run_sim_check.py --only daria, as it is no
#                  whole run
# The checker sim/check/run_sim_check.py turns this script's output into one
# exit code.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
FPGA="${RTL_TREE:-$HERE/..}/src/fpga"
RTL="$FPGA/mister/rtl"
WORK="${WORK:-$HERE/work}"
mkdir -p "$WORK/rtl"

# Quartus 21.1 ignores an initializer on an output port declaration
# (`output logic x = 1'b0`, `output reg x = 0`) and, with Power-Up Don't
# Care, picks the power-up level itself: a sticky flag became a constant 1
# (docs/DEVELOPING.md, "Power-up values"). Simulation honours the
# initializer, so it cannot see this; refuse such declarations in the
# Pocket's own RTL.
if grep -nE '^\s*output\s+(logic|reg)\b[^;/]*=' "$FPGA"/core/*.v "$FPGA"/core/*.sv "$FPGA"/core/bupchip/*.sv; then
	echo "run_sim.sh: an output port above has an initializer, which Quartus ignores; use an initial block" >&2
	exit 1
fi

# The MiSTer sources load their ROM/palette images from "rtl/..." relative
# to the working directory.
for f in palettes ooo.hex; do
	ln -sfn "$RTL/$f" "$WORK/rtl/$f"
done
ln -sfn "$FPGA/core/ar_stub.hex" "$WORK/rtl/ar_stub.hex"
# The AtariVox engine's ROM images (tools/atarivox/sjhw.py --build)
for f in vox_irom.hex vox_drom.hex; do ln -sfn "$FPGA/core/atarivox/$f" "$WORK/rtl/$f"; done

# Verilator (5.040) rejects initialised unpacked `wire` arrays, which
# upstream uses for constant tables and Quartus accepts. Simulate copies with
# those declarations as `logic`; the sources themselves are not touched.
PATCHED="$WORK/patched"
mkdir -p "$PATCHED"
for f in banks2600.sv video_mux.sv RIOT/M6532.sv; do
	mkdir -p "$PATCHED/$(dirname "$f")"
	sed -E 's/^(\s*)wire(\s+\[[^]]+\]\s+\w+\s*\[[0-9]+\]\s*=)/\1logic\2/' "$RTL/$f" > "$PATCHED/$f"
done
# paddles.sv assigns its `output charged` (a wire) from an always block,
# which Quartus allows and Verilator does not.
sed -E 's/^(\s*)output(\s+)charged,/\1output logic\2charged,/' "$RTL/paddles.sv" > "$PATCHED/paddles.sv"

# No POKEY (nor any other 7800 cartridge chip) in the 2600 system module
# (plan step 4): POKEY= and the GHDL conversion of Mark Watson's POKEY are
# gone with it.

SRCS=(
	"$HERE/sim_stubs.sv"
	"$RTL/arm7tdmi/arm7tdmi_pkg.sv"
	"$RTL/6502/mos6502_pkg.sv"
	$(ls "$RTL"/6502/*.sv | grep -v pkg)
	"$RTL/Maria/maria.sv"
	"$RTL/cache_ram.v" "$RTL/bram.v"
	"$RTL/composite_out.sv" "$RTL/cart_ram_tdp.sv" "$RTL/cdf_fastjump_table.sv"
	"$RTL"/arm_mapper_{memory,controller,subsystem,tables,ram_init,writeback,audio}.sv
	"$RTL"/mapper_{dpcplus,cdf,bus,fa2}.sv "$RTL/fa2_nvram_bridge.sv"
	"$RTL/TIA.sv"
	"$RTL/cart2600.sv" "$PATCHED/banks2600.sv" "$PATCHED/video_mux.sv"
	"$RTL/detect2600.sv" "$RTL/a78_cart_extent.sv" "$PATCHED/RIOT/M6532.sv"
	"$RTL/top.sv"
	"$RTL/EEPROM_24LC256.sv" "$FPGA/core/atari2600_pocket.sv"
	"$FPGA/core/atarivox/avox_rx.sv" "$FPGA/core/atarivox/avox_engine.sv" "$FPGA/core/atarivox/atarivox.sv"
	"$FPGA/core/virtual_axis.sv" "$FPGA/core/virtual_axis5.sv" "$FPGA/core/stick_dirs.sv" "$FPGA/core/sram_ctrl.sv" "$PATCHED/paddles.sv" "$RTL/lightgun.sv"
	"$FPGA/pocket_utils/data_loader.sv"
	"$FPGA/core/audio_filter.sv"
	"$RTL/bupchip_peripheral.sv" "$FPGA/pocket_utils/psram.sv"
	"$FPGA"/core/bupchip/{bup_cpu,bup_capture,bup_asset_wr,bup_asset_cache,bup_tick48k,bup_load_probe,bup_status_osd,bupchip_pocket}.sv
	"$HERE/bupchip/s4/psram_model.sv"
)

# The POCKET_SRAM build (cartridge RAM, Flicker Blend frame, SaveKey and BIOS
# in the Pocket's SRAM; no memory editor), as the qsf defines it. SRAM=0
# builds the block RAM version instead.
SRAM_DEFS=""
# KEEP_NOCART_ROM keeps the built-in cartridge image tb_system runs from.
[ "${SRAM:-1}" = 1 ] && SRAM_DEFS="-DPOCKET_SRAM -DEXTERNAL_CARTRAM -DNO_MEM_EDITOR -DKEEP_NOCART_ROM"
# The Pocket's BupChip (ARIA, docs/BUPCHIP_CORE.md), and BUP_DEBUG when the
# qsf sets it (hardware test builds); the testbenches put the PSRAM model on
# cram0. BUP_DEBUG=1 or 0 overrides the qsf; BUPCHIP=0 leaves out the whole
# BupChip.
QSF_BUP_DEBUG=0
grep -q '^set_global_assignment -name VERILOG_MACRO "BUP_DEBUG=1"' "$FPGA/ap_core.qsf" && QSF_BUP_DEBUG=1
BUP_DEFS=""
if [ "${BUPCHIP:-1}" = 1 ]; then
	BUP_DEFS="-DPOCKET_BUPCHIP"
	[ "${BUP_DEBUG:-$QSF_BUP_DEBUG}" = 1 ] && BUP_DEFS="$BUP_DEFS -DBUP_DEBUG"
fi
# DARIA (docs/DARIA_CORE.md; POCKET_DARIA needs POCKET_BUPCHIP): read from the
# qsf as BUP_DEBUG is; DARIA=1 or 0 overrides it. The DARIA build adds the
# daria_* sources, the front end's package first. daria_smp.sv and
# bup_dbg_snap.sv join when they exist (step 7 adds them).
QSF_DARIA=0
grep -q '^set_global_assignment -name VERILOG_MACRO "POCKET_DARIA=1"' "$FPGA/ap_core.qsf" && QSF_DARIA=1
DARIA_ON=0
if [ "${BUPCHIP:-1}" = 1 ] && [ "${DARIA:-$QSF_DARIA}" = 1 ]; then
	DARIA_ON=1
	BUP_DEFS="$BUP_DEFS -DPOCKET_DARIA"
	B="$FPGA/core/bupchip"
	SRCS+=("$B/daria_fe_pkg.sv" "$B/daria_mem.sv" "$B/daria_call.sv" "$B/daria_mmio.sv")
	for f in daria_smp bup_dbg_snap; do [ -f "$B/$f.sv" ] && SRCS+=("$B/$f.sv"); done
	SRCS+=($(ls "$B"/daria_fe_*.sv | grep -v daria_fe_pkg.sv) "$B/daria_fe.sv")
	# The DARIA section's taps need daria_fe in the wrapper as u_fe (plan P14):
	# an instance "daria_fe [#(...)] u_fe (", on one line or over several
	sed 's,//.*,,' "$FPGA/core/atari2600_pocket.sv" | tr '\n' ' ' \
		| grep -qE '(^|[^A-Za-z0-9_$.])daria_fe\s*(#[^;]*)?[^A-Za-z0-9_$]u_fe\s*\(' && BUP_DEFS="$BUP_DEFS -DSIM_DARIA_FE"
fi
# Fix B's P2 assertion in the benches (docs/daria_step7/plan.md P2): on when
# sram_ctrl.sv has Fix B's two requests, m_new and t_new, and the build has
# the SRAM controller at all (the wrapper instantiates sram_ctrl as sram only
# under POCKET_SRAM: SRAM=0 has no dut.sram to tap).
SIM_DEFS=""
[ "${SRAM:-1}" = 1 ] && grep -qE '\bt_new\b' "$FPGA/core/sram_ctrl.sv" && grep -qE '\bm_new\b' "$FPGA/core/sram_ctrl.sv" \
	&& SIM_DEFS="-DSIM_FIXB"
ARMDIV_ARG=""
[ "$DARIA_ON" = 1 ] && [ -n "${ARM_DIV:-}" ] && ARMDIV_ARG="+arm_div=$ARM_DIV"
# fp CASE: the plusargs every run gets: its fingerprint file with FP=1, and
# the DARIA build's clk_arm divider with ARM_DIV.
fp() { [ "${FP:-0}" = 1 ] && printf '%s ' "+fp=$WORK/fp/$1.csv"; printf '%s' "$ARMDIV_ARG"; }
[ "${FP:-0}" = 1 ] && mkdir -p "$WORK/fp"

# Every bench run goes through sim. Most cases pipe the bench into grep,
# which drops its exit status and its "%Fatal" line (Verilator prints it on
# stdout); sim prints "SIMULATOR EXIT N: <command>" past the pipe, on the
# script's own stdout (descriptor 3), when the bench exits non-zero, and
# sim/check/run_sim_check.py fails on that line. A passing run prints
# nothing more than before.
exec 3>&1
sim() { local rc=0; "$@" || rc=$?; [ "$rc" = 0 ] || echo "SIMULATOR EXIT $rc: $*" >&3; return 0; }

VL_OPT=(-O2)
build() {   # build <top> <objdir> [more bench sources]
	local top="$1" obj="$2"; shift 2
	"${VERILATOR:-verilator}" --binary --timing -j "${VL_JOBS:-4}" "${VL_OPT[@]}" -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
		-Wno-TIMESCALEMOD \
		-DNO_ARM_MAPPER -DNO_BUPCHIP -DNO_DDRAM -DEXTERNAL_FIRMWARE -DEEPROM_NACK_ENDS_READ -DPOCKET_SUPERCHARGER -DPOCKET_ATARIVOX \
		$SRAM_DEFS $BUP_DEFS $SIM_DEFS \
		--top-module "$top" -Mdir "$WORK/$obj" -o vtb "${SRCS[@]}" "$@" "$HERE/$top.sv" > "$WORK/$obj.log" 2>&1 \
		|| { grep -m20 "%Error" "$WORK/$obj.log"; exit 1; }
}
echo "-- run_sim.sh: VERILATOR ${VERILATOR:-verilator} ($("${VERILATOR:-verilator}" --version)), RTL $(cd "$FPGA/../.." && pwd), POCKET_DARIA $DARIA_ON, defines:$SRAM_DEFS $BUP_DEFS $SIM_DEFS"
case "${ONLY:-}" in
	"") ;;
	daria) [ "$DARIA_ON" = 1 ] || { echo "run_sim.sh: ONLY=daria needs the DARIA build (DARIA=1)" >&2; exit 1; }
		echo "-- run_sim.sh ONLY=daria: tb_load and the DARIA section alone, not a whole run" ;;
	*) echo "run_sim.sh: ONLY=$ONLY: daria is the section that runs alone" >&2; exit 1 ;;
esac
if [ -n "${BUILD_TOP:-}" ]; then
	case "$BUILD_TOP" in
		tb_cartram) o=obj_cartram; build tb_cartram $o "$HERE/tb_load.sv" ;;
		tb_system) o=obj; build tb_system $o ;;
		tb_load) o=obj_load; build tb_load $o ;;
		tb_frames)
			o=obj_frames
			VL_OPT=(-O3 --x-assign fast --x-initial fast)
			BUP_DEFS="${BUP_DEFS/ -DBUP_DEBUG/}"
			dbg=off
			if [ "${FRAMES_DEBUG:-0}" = 1 ] && [ "${BUPCHIP:-1}" = 1 ]; then BUP_DEFS="$BUP_DEFS -DBUP_DEBUG"; dbg="on (FRAMES_DEBUG=1)"; fi
			echo "-- tb_frames: BUP_DEBUG $dbg, ${VL_OPT[*]}, defines:$SRAM_DEFS $BUP_DEFS $SIM_DEFS"
			build tb_frames $o "$HERE/tb_load.sv"
			# the build's mode, for run_frames.sh: BUP_DEBUG or not, and the binary it is for
			fdbg=0; [[ " $BUP_DEFS " == *" -DBUP_DEBUG "* ]] && fdbg=1
			echo "FRAMES_DEBUG=$fdbg md5 $(md5sum < "$WORK/$o/vtb" | cut -d' ' -f1)" > "$WORK/$o.mode" ;;
		*) echo "run_sim.sh: BUILD_TOP=$BUILD_TOP: tb_system, tb_load, tb_cartram or tb_frames" >&2; exit 1 ;;
	esac
	echo "-- built $BUILD_TOP: $o/vtb md5 $(md5sum < "$WORK/$o/vtb" | cut -d' ' -f1)"
	exit 0
fi
if [ -z "${ONLY:-}" ]; then
build tb_system obj
build tb_load obj_load
echo "-- built: obj/vtb md5 $(md5sum < "$WORK/obj/vtb" | cut -d' ' -f1), obj_load/vtb md5 $(md5sum < "$WORK/obj_load/vtb" | cut -d' ' -f1)"
else
build tb_load obj_load
echo "-- built: obj_load/vtb md5 $(md5sum < "$WORK/obj_load/vtb" | cut -d' ' -f1)"
fi

cd "$WORK"
# (ONLY=daria: from here to the DARIA section, every case is left out)
if [ -z "${ONLY:-}" ]; then
# tb_system runs its program from rtl/mem0.hex (KEEP_NOCART_ROM), with no
# cartridge loaded. The 7800 core's 7800-mode tones and MARIA's border and
# geometry cases are gone with MARIA (plan step 4).
echo "-- 2600 mode (TIA video, stabilised):"
for audf in 0 14; do
	rm -f rtl/mem0.hex   # may be a link to the upstream file: never write through it
	python3 "$HERE/tone_test.py" "$audf" 2600 > rtl/mem0.hex
	out=$(sim ./obj/vtb +audf="$audf" +mode2600 $(fp mode2600_$audf))
	echo "$out" | grep TONE; echo "$out" | grep FRAME | tail -1
done

echo "-- PAL 2600 frame, after region detection (expect 288 lines, video PAL 1):"
rm -f rtl/mem0.hex; python3 "$HERE/tone_test.py" 14 2600 pal > rtl/mem0.hex
sim ./obj/vtb +audf=14 +mode2600 +long $(fp pal2600) | grep FRAME | tail -1
rm -f rtl/mem0.hex

echo "-- load an A78 through the APF data loader (refused, plan D8: the bad game screen, silent):"
ln -sfn "$RTL/mem0.hex" rtl/mem0.hex     # upstream's built-in image: no tone
python3 "$HERE/make_a78.py" 7 > load_test.a78
sim ./obj_load/vtb +image=load_test.a78 +audf=7 $(fp load_a78) | grep -E "LOAD|TONE"

echo "-- load a headerless 2600 image (4 KiB):"
python3 "$HERE/tone_test.py" 14 2600 | head -4096 | python3 -c "import sys;sys.stdout.buffer.write(bytes(int(l,16) for l in sys.stdin))" > load_test.a26
# grep -a: the LOAD line prints the image's first bytes as its header, raw;
# in a UTF-8 locale grep would hold that line back ("binary file matches").
sim ./obj_load/vtb +image=load_test.a26 +audf=14 $(fp load_a26) | grep -aE "LOAD|TONE"

# The FA2 flash's save slot (fa2.sav, 0x40000000): sim/fa2_test.py's
# synthetic FA2 cartridge (no game data) loads the flash through the
# mapper's fa2_nvram_* port, saves it changed, and loads it again; tb_load
# writes the file in before the run and reads the slot back afterwards with
# the APF read protocol (+fa2save, +fa2expect, +fa2prog). Two A78 runs, each
# with the file loaded, must leave it as it was: load_test.a78, which
# detect2600.sv does not take for FA2, and fa2_test.py's a78 image, which it
# does take for FA2 (mapper 25) and which issued a save command in the 7800
# core's 7800 mode. openFPGA-2600 refuses both (plan D8): they run the bad
# game screen's scheme (mapper 32), so no copy starts (saves 0), and the
# wrapper's fa2_on keeps the slot out of reach anyway.
echo "-- FA2 flash save slot (fa2.sav): a synthetic FA2 cartridge loads, saves and reloads it through the mapper's port:"
python3 "$HERE/fa2_test.py" image > fa2_test.a26
python3 "$HERE/fa2_test.py" flash 256 > fa2_flash.bin
python3 "$HERE/fa2_test.py" expect 256 > fa2_flash_expect.bin
python3 "$HERE/fa2_test.py" expect > fa2_blank_expect.bin
echo "  a saved flash file (expect 2 loads, 1 save, 256 slot RAM writes; 0 bytes differ):"
sim ./obj_load/vtb +image=fa2_test.a26 +fa2save=fa2_flash.bin +fa2expect=fa2_flash_expect.bin +fa2prog $(fp fa2_file) | grep -aE "^ *FA2"
echo "  no file, a blank flash read as \$FF (expect the same counts; 0 bytes differ):"
sim ./obj_load/vtb +image=fa2_test.a26 +fa2expect=fa2_blank_expect.bin +fa2prog $(fp fa2_blank) | grep -aE "^ *FA2"
echo "  an A78 game with the file loaded, not taken for FA2 (refused: expect mapper 32, 0 bytes differ):"
sim ./obj_load/vtb +image=load_test.a78 +audf=7 +fa2save=fa2_flash.bin $(fp fa2_a78) | grep -aE "^ *FA2"
python3 "$HERE/fa2_test.py" a78 > fa2_test.a78
echo "  an A78 game that detect2600 takes for FA2 and that issues a save command, the file loaded (refused: expect mapper 32, 0 bytes differ):"
sim ./obj_load/vtb +image=fa2_test.a78 +fa2save=fa2_flash.bin $(fp fa2_a78fa2) | grep -aE "^ *FA2"

# The A78 refusal (openFPGA-2600, plan D8 and 7.D.3). An image whose bytes
# 1-5 read "ATARI" runs as a 2600 cartridge in the bad game screen's scheme
# (cart2600.sv's "unsupported" screen, mapper 32): no hang, a steady NTSC
# picture. Its header asks for everything a refused image must not get: PAL
# (byte 57, with Region Auto: the PLL must never be asked for PAL, so
# is_pal_o never changes), the HSC and a SaveKey (byte 58 = 3), a light gun
# on port 1 and an AtariVox on port 2 (bytes 55-56), the Souper flag (type
# bit 12). With SaveKey On and a save file in each slot, nothing may be
# written: the SaveKey and FA2 slots read back as loaded, no EEPROM write, no
# I2C clock, no FA2 copy. tb_load's +refuse prints the REFUSE lines.
echo "-- A78 refusal (plan D8): an A78 runs the bad game screen, writes no save and asks for no retune:"
python3 "$HERE/make_a78.py" 7 --region 1 --save 3 --ports 2,10 --type 0x1000 > refuse_test.a78
python3 -c 'import random, sys; random.seed(2600); sys.stdout.buffer.write(bytes(random.randrange(256) for _ in range(32768)))' > refuse_sk.bin
sim ./obj_load/vtb +image=refuse_test.a78 +audf=7 +sk_on +sksave=refuse_sk.bin +fa2save=fa2_flash.bin +refuse $(fp a78_refuse) > refuse.log
grep -aE "^(LOAD|REFUSE|SAVEKEY|FA2|TONE)" refuse.log | sed 's/^/  /'
rf_ok=1
for p in "^LOAD 16512 bytes, header ATARI, cart_is_7800=1, cart_size=16512, tia_mode=1, payload mismatches=0$" \
	"^REFUSE image: header ATARI, cart_is_7800 1, a78_refused 1, tia_mode 1, tia_en 1, 2600 mapper 32, bad game screen 1$" \
	"^REFUSE devices: use_sk 0, fa2_on 0, hsc_en 0, gun_en 0, port types 1 1, daria_profile 0$" \
	"^REFUSE region: is_pal_o 0, changed 0 times since power-up; header byte 57 1$" \
	"^REFUSE frames: (1[0-9]|[2-9][0-9]) since the reset's release, the last (1[0-9]|[2-9][0-9]) with the same picture, the last 238944 clk_sys long$" \
	"^REFUSE saves: SaveKey SCL edges 0, EEPROM bytes written 0; FA2 flash loads 0, saves 0, slot RAM writes 0$" \
	"^SAVEKEY save after load, reset and running: 0 of 32768 bytes differ from the save file$" \
	"^FA2 save slot after load, reset and 300 ms of running \(APF read protocol\): 0 of 256 bytes differ from the expected file$"; do
	grep -aEq "$p" refuse.log || { echo "  MISSING: $p"; rf_ok=0; }
done
[ "$rf_ok" = 1 ] && echo "A78_REFUSAL pass" || echo "A78_REFUSAL FAIL"

# Reloads: a second image loaded 150 ms into the run, as picking another
# game on the Pocket does (tb_load's +image2, no reset_in), after a 2600
# image and after a refused A78. tb_load's BOOT lines give, at each reset
# release, where the 6507's reset vector and first opcode came from (the
# cartridge slot: no BIOS in this core); IMAGE2 the second load.
# reload_a26_a26 is plan step 4's r26_26 (load_test.a26, then
# load_test2.a26). The 7800 core's BIOS cases that loaded a 2600 image are
# these without the BIOS, which this core has no slot for.
echo "-- reloads: a second image at 150 ms, after a 2600 image and after a refused A78:"
python3 "$HERE/tone_test.py" 7 2600 | head -4096 | python3 -c "import sys;sys.stdout.buffer.write(bytes(int(l,16) for l in sys.stdin))" > load_test2.a26
echo "  2600 image, then another 2600 image (expect both from the cartridge slot at \$f000):"
sim ./obj_load/vtb +image=load_test.a26 +audf=14 +wav=300 +image2=load_test2.a26 +image2at=150 $(fp reload_a26_a26) | grep -aE "^(BOOT|IMAGE2)" | sed 's/^/    /'
echo "  a refused A78, then a 2600 image (expect the bad game screen, then the 2600 image from \$f000):"
sim ./obj_load/vtb +image=load_test.a78 +audf=7 +wav=300 +image2=load_test.a26 +image2at=150 $(fp reload_a78_a26) | grep -aE "^(BOOT|IMAGE2)" | sed 's/^/    /'
fi   # ONLY

# DARIA in the whole core (docs/daria_step7/plan.md 3.6), game-free: tb_load
# runs fe_dir's synthetic ARM images (sim/bupchip/daria/fe_dir/mkimg.py: a
# DPC+, a CDFJ and the 64 KB "digital" CDFJ image, which also reads ROM above
# 32 KB) through the real loader and wrapper. Each must boot and finish its
# test bodies (RIOT $FF at least the count its .meta needs, $FE 0: no failed
# self-check), every call daria_fe posts must return, with 0 PSRAM model
# violations, no CPU halt, and the guard locked with 0 unlocks at VCO/18,
# the default, or unlocked with 0 unlocks with ARM_DIV=19 (the guard never
# locks there).
# With BUP_DEBUG, the DARIA status overlay (tb_load.sv's overlay block) too.
# Each run's "DARIA overlay:" line must pass: the overlay's counts equal the
# bench's (calls since the console's last reset, unlocks, the guard bit),
# its copy of the RIOT timer equals the RIOT, its cells read back as its
# layout says from u_dstat's counts, rows 6-8 only while halted, and it
# checked what OVL below requires of that run (the rows whose every cell must
# be read back, at least a given number of cells read; +ovl_timer: the RIOT
# timer written and read, with late calls and calls on time; +ovl_late=meta:
# exactly the late calls the image's .meta gives for this run length).
# smoke_dpc's and smoke_cdf's frames are a few lines long and never reach the
# TIA's window, which opens at line 19: for them the rows and cells are
# waived (+ovl_rows=0 +ovl_cells=0), and their lines say so. Three more runs
# join the section in these builds only: frame_cdfj (fe_dir's
# tests.CORE_TESTS: 105-line frames, which show the six rows, and the RIOT
# timer written before each call and read once after it);
# frame_cdfj_pattern, the same image with the guard's nets forced from 100
# ms (locked for 20 ms, 4 unlock pulses: +ovl_guard, so the guard and unlock
# terms compare nonzero values at VCO/19 too) and the overlay's inputs forced
# from 150 ms to a pattern and then its complement (+ovl_pattern_at), which
# light every cell, every row and every colour, rows 6-8 included; and
# frame_cdfj_retune, the same image with a PAL/NTSC retune at 150 ms
# (+retune), whose console reset clears u_dstat's calls and late calls: the
# second epoch must compare as the first (+ovl_resets=2). Then the section as
# a whole: "overlay cells:" sums the cells read back and requires rows 0-5
# complete in the normal runs and rows 0-8 in the pattern's.
# sim/check/run_sim_check.py also requires each run's line to state the
# requirement OVL gives it.
# Only in the DARIA build; without POCKET_DARIA the section is inactive,
# which is not a pass (run_sim_check.py).
if [ "$DARIA_ON" = 1 ]; then
	echo "-- DARIA: synthetic ARM images in the whole core (fe_dir/mkimg.py):"
	DR="$WORK/daria"
	mkdir -p "$DR"; ln -sfn "$WORK/rtl" "$DR/rtl"
	DIMG=(smoke_dpc smoke_cdf digital_cdfj)
	RUNS=("${DIMG[@]}")
	OVL_ON=0
	if [[ " $BUP_DEFS " == *" -DBUP_DEBUG "* ]]; then
		OVL_ON=1
		DIMG+=(frame_cdfj)
		RUNS+=(frame_cdfj frame_cdfj_pattern frame_cdfj_retune)
	fi
	# the overlay's requirement of each run (BUP_DEBUG builds). The cell
	# floors are about half the cells measured at VCO/19 and /18
	# (digital_cdfj 4,008; frame_cdfj and its pattern run: run_ovl.sh's logs).
	# +ovl_late=meta: the .meta's "ovl_late N MS", for +daria=MS only.
	declare -A OVL=(
		[smoke_dpc]="+ovl_rows=0 +ovl_cells=0"
		[smoke_cdf]="+ovl_rows=0 +ovl_cells=0"
		[digital_cdfj]="+ovl_rows=7 +ovl_cells=2000"
		[frame_cdfj]="+region=1 +ovl_rows=3F +ovl_cells=1500 +ovl_timer=1 +ovl_late=meta"
		[frame_cdfj_pattern]="+region=1 +ovl_rows=1FF +ovl_cells=2000 +ovl_timer=1 +ovl_late=meta +ovl_guard=4 +ovl_guard_at=100 +ovl_pattern_at=150"
		[frame_cdfj_retune]="+region=1 +ovl_rows=3F +ovl_cells=1500 +ovl_timer=1 +ovl_resets=2 +retune=150")
	python3 "$HERE/bupchip/daria/fe_dir/mkimg.py" "$DR/img" "${DIMG[@]}" > "$DR/mkimg.log"
	daria_ok=1
	guard=locked; [ "${ARM_DIV:-18}" = 19 ] && guard=unlocked
	ovl_n=0; ovl_rows=0; ovl_prows=0
	for r in "${RUNS[@]}"; do
		t="${r%_pattern}"; t="${t%_retune}"
		oa=""; [ "$OVL_ON" = 1 ] && oa="${OVL[$r]}"
		lfail=""
		if [[ " $oa " == *" +ovl_late=meta "* ]]; then
			lm="$(sed -n 's/^ovl_late \([0-9]*\) \([0-9]*\)$/\1 \2/p' "$DR/img/$t.meta")"
			if [ -n "$lm" ] && [ "${lm#* }" = "${DARIA_MS:-300}" ]; then oa="${oa/+ovl_late=meta/+ovl_late=${lm% *}}"
			else
				lfail="$t.meta gives no late count for +daria=${DARIA_MS:-300} (it has: ${lm:-none})"
				oa="${oa/ +ovl_late=meta/}"
			fi
		fi
		# shellcheck disable=SC2086
		(cd "$DR" && sim ./../obj_load/vtb +image="img/$t.bin" +daria="${DARIA_MS:-300}" $oa $(fp daria_$r) < /dev/null > "$r.log" 2>&1) || true
		line="$(grep -m1 "^DARIA result:" "$DR/$r.log" || echo "DARIA result: none (the run did not finish; see $DR/$r.log)")"
		echo "  $r: ${line#DARIA result: }"
		[ -z "$lfail" ] || { echo "    FAIL: $lfail"; daria_ok=0; }
		# +ovl_guard=N forces N unlock pulses on the guard's net, which the
		# bench's unlock count (this line's) sees too: exactly N, not 0
		ul=0; [[ " $oa " =~ \ \+ovl_guard=([0-9]+)\  ]] && ul="${BASH_REMATCH[1]}"
		python3 - "$DR/img/$t.meta" "$line" "$guard" "$ul" <<-'PY' || daria_ok=0
		import re, sys
		meta, line, guard, ul = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
		need = {"dir_marker": 1, "call_accept": 1}
		for l in open(meta):
		    m = re.match(r"need (dir_marker|call_accept) >= (\d+)$", l.strip())
		    if m:
		        need[m.group(1)] = int(m.group(2))
		m = re.match(r"DARIA result: marker (\d+), self-check errors (\d+), calls (\d+), returns (\d+), "
		             r"psram_viol (\d+), halted (\d+), guard (\w+), unlocks (\d+)$", line)
		bad = []
		if not m:
		    bad.append("no result line")
		else:
		    mk, err, calls, rets, viol, halt, g, unl = m.groups()
		    if int(mk) < need["dir_marker"]: bad.append("marker %s < %d" % (mk, need["dir_marker"]))
		    if int(err): bad.append("self-check errors %s" % err)
		    if int(calls) < need["call_accept"]: bad.append("calls %s < %d" % (calls, need["call_accept"]))
		    if rets != calls: bad.append("returns %s != calls %s" % (rets, calls))
		    if int(viol): bad.append("psram_viol %s" % viol)
		    if int(halt): bad.append("halted")
		    if g != guard: bad.append("guard %s, expected %s" % (g, guard))
		    if int(unl) != ul: bad.append("unlocks %s" % unl + (", expected %d (forced)" % ul if ul else ""))
		if bad:
		    print("    FAIL: " + "; ".join(bad))
		sys.exit(1 if bad else 0)
		PY
		# BUP_DEBUG builds: the DARIA status overlay's line (tb_load.sv) must pass
		if [ "$OVL_ON" = 1 ]; then
			ol="$(grep -m1 "^DARIA overlay:" "$DR/$r.log" || echo "DARIA overlay: none (no line)")"
			echo "    overlay: ${ol#DARIA overlay: }"
			[[ "$ol" == *"; PASS" ]] || { echo "    FAIL: the DARIA status overlay ($r)"; daria_ok=0; }
			n="$(sed -n 's/.*; checked: \([0-9]*\) cells (rows complete \([01]*\),.*/\1/p' <<< "$ol")"
			m="$(sed -n 's/.*; checked: \([0-9]*\) cells (rows complete \([01]*\),.*/\2/p' <<< "$ol")"
			ovl_n=$((ovl_n + ${n:-0}))
			if [ "$r" = frame_cdfj_pattern ]; then ovl_prows=$((ovl_prows | 2#${m:-0}))
			else ovl_rows=$((ovl_rows | 2#${m:-0})); fi
		fi
	done
	# BUP_DEBUG builds: the section as a whole read cells back, rows 0-5 in
	# normal frames and rows 0-8 under the pattern (a section whose runs each
	# met a waived or too small requirement fails here)
	if [ "$OVL_ON" = 1 ]; then
		ov="pass"
		[ "$ovl_n" -gt 0 ] && [ $((ovl_rows & 0x3F)) = $((0x3F)) ] && [ "$ovl_prows" = $((0x1FF)) ] || { ov="FAIL"; daria_ok=0; }
		bin9() { local i s=""; for i in 8 7 6 5 4 3 2 1 0; do s+=$((($1 >> i) & 1)); done; echo "$s"; }
		echo "  overlay cells: $ovl_n read back in the section; rows complete $(bin9 $ovl_rows) in the normal runs, $(bin9 $ovl_prows) in the pattern run (required: rows 0-5, rows 0-8); $ov"
	fi
	[ "$daria_ok" = 1 ] && echo "DARIA pass" || echo "DARIA FAIL"
else
	echo "-- DARIA: inactive (POCKET_DARIA is not in the qsf; DARIA=1 builds it): not run, and not a pass"
fi

[ -z "${ONLY:-}" ] || exit 0

echo "-- PAL/NTSC PLL retune sequence:"
"${VERILATOR:-verilator}" --binary --timing -Wno-fatal -Wno-lint --top-module tb_pll_region \
	-Mdir "$WORK/obj_pllr" -o vtb "$FPGA/core/pll_region.v" "$HERE/tb_pll_region.sv" > "$WORK/obj_pllr.log" 2>&1 \
	|| { grep -m20 "%Error" "$WORK/obj_pllr.log"; exit 1; }
sim ./obj_pllr/vtb | grep -E "fraction|PLL_REGION|FAIL"

echo "-- the region asked of the PLL (atari2600_pocket.sv's region_pll with pll_region.v, tb_region; RTL-1, RTL-2):"
WORK="$WORK/region" bash "$HERE/run_region.sh" | grep -E "^REGION " || true

echo "-- audio filter:"
"${VERILATOR:-verilator}" --binary --timing -O2 -Wno-fatal -Wno-lint --top-module tb_audio_filter \
	-Mdir "$WORK/obj_af" -o vtb "$FPGA/core/audio_filter.sv" "$HERE/tb_audio_filter.sv" > "$WORK/obj_af.log" 2>&1 \
	|| { grep -m20 "%Error" "$WORK/obj_af.log"; exit 1; }
sim ./obj_af/vtb | grep AUDIO

echo "-- virtual paddle / driving / light-gun axis:"
"${VERILATOR:-verilator}" --binary --timing -Wno-fatal -Wno-lint --top-module tb_virtual_axis \
	-Mdir "$WORK/obj_va" -o vtb "$FPGA/core/virtual_axis.sv" "$HERE/tb_virtual_axis.sv" > "$WORK/obj_va.log" 2>&1 \
	|| { grep -m20 "%Error" "$WORK/obj_va.log"; exit 1; }
sim ./obj_va/vtb | grep AXIS

echo "-- the five virtual axes as one engine (virtual_axis5.sv, tb_vaxis5):"
WORK="$WORK/vaxis5" bash "$HERE/run_vaxis5.sh" | grep -E "^VAXIS5 (seed|planted|pass|FAIL|build)|^MISMATCH" || true
