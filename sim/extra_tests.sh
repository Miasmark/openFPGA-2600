#!/bin/bash
# openFPGA-2600's game-free tests beyond run_sim.sh: synthetic 2600 images
# (our own code, made by Python scripts; no ROMs are stored in this
# repository) and the Supercharger BIOS, fetched from MiSTer's repository at
# test time as a user would supply it. Needs python3, curl and the Verilator
# build that run_sim.sh makes. Plan step 6 ported the 7800 core's script:
# its 7800 sections (multisprite, POKEY at $450 and $4000, the DLI sweep, the
# A78 SaveKey cart, the High Score Cart firmware) are gone with the 7800
# hardware, and with them the dasm and 7800basic clones they were built with.
#
#   cartram      2600 cartridge RAM on every RAM mapper, Flicker Blend off and
#                on, and the Supercharger, through tb_cartram's +cartram
#                monitor (cartram2600_test.py), and the directed s19 run;
#                first (with AR_TAPE=1 it fetches the Supercharger BIOS first
#                and adds the tape load with +cartram, artape: about an hour
#                more)
#   savekey      the SaveKey on port 2 and its save slot: console_test.py's
#                2600 image writes 8 bytes over I2C and reads them back; On,
#                Off (the default: no acknowledge) and the 32 KiB round trip
#   firmware     the Supercharger BIOS slot, then a 2600 image
#   supercharger Supercharger loads without the BIOS (POCKET_SUPERCHARGER's
#                stub), from ar_test.py's images; AR_TAPE=1 adds the
#                tape path with the BIOS (long: about 20 simulated seconds)
#   mapper       the Mapper menu (bs_override) on console_test.py's
#                multicarts: MC2K, MC4K and MC8K forced, four games each, a
#                console reset every 200 ms; and one with Mapper Auto
#   inputs       the Port 1 and 2 Input values on input_test.py's image:
#                each port type (joystick, paddles, driving, light gun, dual
#                stick, Booster Grip) as the program reads it
#   switches     the Left and Right Difficulty and TV Type items, and L's
#                Colour/B&W toggle, on console_test.py's SWCHB image
# FP=1 writes each run's per-frame fingerprint to $WORK/fp/extra_<case>.csv
# (tb_load +fp), and the cartridge-RAM runs' to $WORK/fp/cartram_<case>.csv,
# for comparing two builds frame by frame. A bench that exits non-zero
# prints "SIMULATOR EXIT N: <command>" (its "%Fatal" line may have gone to a
# grep). The checker sim/check/extra_tests_check.py turns this script's
# output into one exit code (with --ref, the reference build's log, for the
# Supercharger tape colours).
#
# In pieces (2026-10-23, the 7800 core: a whole run with AR_TAPE=1 took
# 5.1-5.2 h on the DARIA build and 3.7-3.9 h on the plain one, about 80 % of
# it the three tape loads; docs/ENVIRONMENT.md 6 has the table):
#   EXTRA_ONLY=S[,S...]
#        run only those sections, each exactly as in a whole run: cartram
#        savekey firmware supercharger mapper inputs switches (an unknown
#        name: exit 2). The header line then ends ", EXTRA_ONLY ...";
#        extra_tests_check.py fails such a log for the sections left out: a
#        quick look, not a verdict.
#   EXTRA_JOBS=N
#        (default 1) the sections as up to N processes at once, longest
#        first, each under EXTRA_SLOT (a command prefix that runs one
#        simulation in one of the caller's slots, e.g. "flock FILE"; empty:
#        none). The firmware is fetched first; the pieces' logs (in
#        $X/pieces) are then printed in the serial order, so the output is a
#        serial run's and extra_tests_check.py gives the same verdict. Exit 1
#        when a piece exited non-zero (a serial run stops at that section
#        instead). Every piece is a simulation: do not run EXTRA_JOBS>1
#        inside one slot, and EXTRA_JOBS>1 with no EXTRA_SLOT is refused
#        (exit 2). On the owner's VM use EXTRA_SLOT=~/daria_work/bin/simslot;
#        "flock FILE" with one FILE runs the pieces one at a time.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/work}"
X="$WORK/extra"
mkdir -p "$X"
[ -x "$WORK/obj_load/vtb" ] || { echo "run ./run_sim.sh first"; exit 1; }
SECTIONS="cartram savekey firmware supercharger mapper inputs switches"
EXTRA_ONLY="${EXTRA_ONLY:-}"; EXTRA_ONLY="${EXTRA_ONLY//,/ }"
for s in $EXTRA_ONLY; do
	case " $SECTIONS " in *" $s "*) ;; *) echo "extra_tests.sh: unknown section '$s' in EXTRA_ONLY (sections: $SECTIONS)" >&2; exit 2 ;; esac
done
if [ "${EXTRA_JOBS:-1}" -gt 1 ] && [ -z "${EXTRA_PIECE:-}" ] && [ -z "${EXTRA_SLOT:-}" ]; then
	echo "extra_tests.sh: EXTRA_JOBS=$EXTRA_JOBS needs EXTRA_SLOT, a command prefix that holds one simulation slot (on the owner's VM, EXTRA_SLOT=~/daria_work/bin/simslot); without it every piece runs outside a slot" >&2
	exit 2
fi
want() { [ -z "$EXTRA_ONLY" ] || case " $EXTRA_ONLY " in *" $1 "*) true ;; *) false ;; esac; }
fp() { [ "${FP:-0}" = 1 ] && printf '%s' "+fp=$WORK/fp/extra_$1.csv"; true; }
[ "${FP:-0}" = 1 ] && mkdir -p "$WORK/fp"
# Every bench run goes through sim (as in run_sim.sh): a pipe into grep drops
# the bench's exit status and its "%Fatal" line, so sim prints "SIMULATOR
# EXIT N" past the pipe, on the script's stdout (descriptor 3).
exec 3>&1
sim() { local rc=0; "$@" || rc=$?; [ "$rc" = 0 ] || echo "SIMULATOR EXIT $rc: $*" >&3; return 0; }
# The firmware files (not in this repository; MiSTer's copies are fetched at
# test time, as a user would supply them).
UP="https://raw.githubusercontent.com/MiSTer-unstable-nightlies/Atari7800_MiSTer/$(cat "$HERE/../src/fpga/mister/UPSTREAM_COMMIT")/rtl"
fetch_ar() {
	mkdir -p "$X/fw"
	# written whole, then renamed: a piece running at the same time never
	# reads a half-written file
	[ -s "$X/fw/supercharger.bin" ] || { curl -fsSL "$UP/ar.hex" | python3 "$HERE/../tools/hex2bin.py" > "$X/fw/supercharger.bin.$$" \
		&& mv -f "$X/fw/supercharger.bin.$$" "$X/fw/supercharger.bin"; }
}

[ -n "${EXTRA_PIECE:-}" ] || echo "-- extra_tests.sh: WORK $WORK, obj_load/vtb md5 $(md5sum < "$WORK/obj_load/vtb" | cut -d' ' -f1), AR_TAPE ${AR_TAPE:-0}${EXTRA_ONLY:+, EXTRA_ONLY $EXTRA_ONLY}"

# EXTRA_JOBS>1: each section is a piece, this script again with EXTRA_ONLY=it and
# EXTRA_PIECE=1 (no header, nothing fetched that another piece uses), its log
# in $X/pieces; the logs are then printed in the serial order.
if [ "${EXTRA_JOBS:-1}" -gt 1 ] && [ -z "${EXTRA_PIECE:-}" ]; then
	if want firmware || { [ "${AR_TAPE:-0}" = 1 ] && { want cartram || want supercharger; }; }; then fetch_ar; fi
	P="$X/pieces"; rm -rf "$P"; mkdir -p "$P"
	for s in supercharger cartram inputs mapper savekey switches firmware; do
		want "$s" || continue
		while [ "$(jobs -rp | wc -l)" -ge "$EXTRA_JOBS" ]; do wait -n || true; done
		( set +e; EXTRA_ONLY="$s" EXTRA_PIECE=1 EXTRA_JOBS=1 $EXTRA_SLOT bash "$HERE/extra_tests.sh" > "$P/$s.out" 2>&1; echo $? > "$P/$s.rc" ) &
	done
	wait
	rc=0
	for s in $SECTIONS; do
		want "$s" || continue
		cat "$P/$s.out"
		[ "$(cat "$P/$s.rc" 2>/dev/null)" = 0 ] || rc=1
	done
	exit $rc
fi

# 2600 cartridge RAM (docs/DARIA_CORE.md, "Fix B"; docs/daria_step7/plan.md
# 1.2 row 6): tb_cartram (tb_load + the +cartram monitor) is built in WORK
# from run_sim.sh's source list when missing. Every RAM mapper's test image
# with Flicker Blend off and on, the Supercharger's full load and multiload:
# no fail code, 0 wrong bytes, 0 reads without a fresh
# access, writes = strobes, shadow = SRAM, the per-image read and write
# counts, and each build's latency buckets (cartram2600_test.py's header).
# Then the directed s19 run: another client's access placed at every
# clk_sdram edge of the 6507 cycle in turn.
if want cartram; then
echo "-- 2600 cartridge RAM (cartram2600_test.py: 8 RAM mappers x Flicker Blend, Supercharger, s19 sweep)"
# (re)built unless it is newer than run_sim.sh's own tb_load build, which
# run_sim.sh makes afresh on every run: a tb_cartram older than that may be
# of other RTL
[ -x "$WORK/obj_cartram/vtb" ] && [ ! "$WORK/obj_load/vtb" -nt "$WORK/obj_cartram/vtb" ] \
	&& [ ! "$HERE/tb_cartram.sv" -nt "$WORK/obj_cartram/vtb" ] \
	|| WORK="$WORK" BUILD_TOP=tb_cartram VL_JOBS="${VL_JOBS:-2}" bash "$HERE/run_sim.sh" | sed 's/^/  /'
CT_FP=(); [ "${FP:-0}" = 1 ] && CT_FP=(--fp)
CT_TAPE=()
if [ "${AR_TAPE:-0}" = 1 ]; then
	# the Supercharger's full load from tape, through the BIOS, with +cartram
	fetch_ar
	CT_TAPE=(--arfw "$X/fw/supercharger.bin")
fi
python3 "$HERE/cartram2600_test.py" matrix --work "$WORK" "${CT_FP[@]}" "${CT_TAPE[@]}" || true
python3 "$HERE/cartram2600_test.py" s19 --work "$WORK" "${CT_FP[@]}" || true
fi

# The SaveKey (plan 7.D.4): console_test.py's 2600 image writes 8 bytes to
# the 24LC256 at $1234 over I2C on port 2 (SDA PA2, SCL PA3), waits out the
# write cycle and reads them back; its tone says whether they matched (AUDF0
# 7) or the EEPROM never acknowledged or read back wrong (AUDF0 31). The save
# file is pseudo-random with the 8 bytes the cart writes inverted, so the round
# trip shows exactly 8 bytes changed.
if want savekey; then
echo "-- SaveKey (24LC256 on port 2) and its save slot: console_test.py's 2600 image"
mkdir -p "$X/savekey"; ln -sfn "$WORK/rtl" "$X/savekey/rtl"
python3 "$HERE/console_test.py" savekey > "$X/savekey/sk.a26"
python3 -c "import random; d = bytearray(random.Random(2600).randbytes(32768)); w = bytes.fromhex('a55a0102807fff00'); d[0x1234:0x123c] = bytes(b ^ 0xff for b in w); open('$X/savekey/random.bin','wb').write(d)"
cd "$X/savekey"
echo "  SaveKey On (expect pass tone ~1962 Hz, the 8 bytes in the save RAM):"
sim "$WORK/obj_load/vtb" +image=sk.a26 +audf=7 +sk_on +skcheck $(fp sk_on) | grep -aE "TONE|SAVEKEY"
echo "  SaveKey Off, the default (expect no acknowledge: fail tone ~490 Hz):"
sim "$WORK/obj_load/vtb" +image=sk.a26 +audf=31 $(fp sk_off) | grep -aE "TONE"
echo "  32 KiB save round trip, APF read protocol (expect pass tone, exactly the 8 bytes the cart wrote to differ):"
sim "$WORK/obj_load/vtb" +image=sk.a26 +audf=7 +sk_on +sksave=random.bin $(fp sk_roundtrip) | grep -aE "TONE|SAVEKEY"
cd - >/dev/null
fi

# The Supercharger BIOS's data slot (supercharger.bin), then a 2600 image:
# the slot's ROM must hold the file, and the image run as before.
if want firmware; then
echo "-- Firmware slot: the Supercharger BIOS (not in this repository;"
echo "   MiSTer's copy is fetched at test time, as a user would supply it)"
mkdir -p "$X/fw"; ln -sfn "$WORK/rtl" "$X/fw/rtl"
fetch_ar
python3 "$HERE/tone_test.py" 14 2600 | head -4096 | python3 -c "import sys;sys.stdout.buffer.write(bytes(int(l,16) for l in sys.stdin))" > "$X/fw/tone.a26"
cd "$X/fw"
echo "  The BIOS through its slot, then a 2600 image (expect 0 ROM bytes differ, the image's tone):"
sim "$WORK/obj_load/vtb" +image=tone.a26 +audf=14 +arfw=supercharger.bin $(fp fw_ar) | grep -aE "FIRMWARE|TONE"
cd - >/dev/null
fi

if want supercharger; then
echo "-- Supercharger without the BIOS: the core's loader stub (POCKET_SUPERCHARGER)"
mkdir -p "$X/ar"; ln -sfn "$WORK/rtl" "$X/ar/rtl"
cd "$X/ar"
python3 "$HERE/ar_test.py" multi > ar_multi.bin
python3 "$HERE/ar_test.py" tape > ar_tape.bin
python3 "$HERE/ar_test.py" full > ar_full.bin
echo "  Full 24-page load (expect magenta \$54 / AUDF0 5 within about 0.1 s, 0 RAM bytes differ):"
sim "$WORK/obj_load/vtb" +image=ar_full.bin +arprobe +wav=400 +ardump=ram.bin $(fp ar_full) | grep -E "^AR "
python3 "$HERE/ar_test.py" check ram.bin ar_full.bin || echo "ARCHECK FAIL"
echo "  Multiload (expect red \$44 / AUDF0 7, then at about 1 s the stub's clear and green \$c4 / AUDF0 14):"
sim "$WORK/obj_load/vtb" +image=ar_multi.bin +arprobe +wav=1500 $(fp ar_multi) | grep -E "^AR "
echo "  Two loads numbered 0, reset after the first (expect blue \$84 / AUDF0 3, then after the reset yellow \$1e / AUDF0 20):"
sim "$WORK/obj_load/vtb" +image=ar_tape.bin +arprobe +wav=1000 +resetat=500 $(fp ar_tape) | grep -E "^AR |RESET"
if [ "${AR_TAPE:-0}" = 1 ]; then
	fetch_ar
	echo "  With the BIOS, from tape: full load (expect 0 RAM bytes differ) and multiload (expect red, then green):"
	sim "$WORK/obj_load/vtb" +image=ar_full.bin +arfw="$X/fw/supercharger.bin" +arprobe +wav=22000 +ardump=ram_tape.bin $(fp ar_tape_full) | grep -E "^AR "
	python3 "$HERE/ar_test.py" check ram_tape.bin ar_full.bin || echo "ARCHECK FAIL"
	sim "$WORK/obj_load/vtb" +image=ar_multi.bin +arfw="$X/fw/supercharger.bin" +arprobe +wav=12000 $(fp ar_tape_multi) | grep -E "^AR "
fi
cd - >/dev/null
fi

# The Mapper menu (plan 3.2 item 1, 7.D.6): bs_override forces a scheme
# (tb_load's +bs, detect2600.sv's bss_type index: MC2K 29, MC4K 30, MC8K 31,
# which no image can reach by detection). console_test.py's multicarts hold
# four games each; a console reset every 200 ms moves to the next game, and
# the fourth back to the first. Each game sets its own COLUBK and AUDF0
# (tb_load's +arprobe logs them): game N $12 + $20 N and 3 + 4 N. The MC8K
# games start in bank 1 and switch to bank 0 with a read of $1FF8 (a game
# that stays in bank 1 sets $0e and 31). With Mapper Auto the MC4K image
# runs one game, whatever the resets.
if want mapper; then
echo "-- Mapper menu override (bs_override): console_test.py's multicarts, four games, a console reset every 200 ms"
mkdir -p "$X/mapper"; ln -sfn "$WORK/rtl" "$X/mapper/rtl"
cd "$X/mapper"
printf '%s\n' "200 reset" "400 reset" "600 reset" "800 reset" > resets.txt
printf '%s\n' "200 reset" > reset1.txt
for s in 2 4 8; do
	python3 "$HERE/console_test.py" mc $s 4 > mc${s}k.bin
	bs=$((s == 2 ? 29 : s == 4 ? 30 : 31))
	echo "  MC${s}K forced (Mapper MC${s}K, bs_override $bs; expect games 0, 1, 2, 3, then 0 again):"
	sim "$WORK/obj_load/vtb" +image=mc${s}k.bin +bs=$bs +arprobe +wav=1000 +joyscript=resets.txt $(fp mc${s}k) \
		| grep -aE "^(OPTIONS|AR |RESET)" | sed 's/^/    /'
done
echo "  MC4K's image with Mapper Auto (expect one game throughout):"
sim "$WORK/obj_load/vtb" +image=mc4k.bin +arprobe +wav=400 +joyscript=reset1.txt $(fp mc4k_auto) \
	| grep -aE "^(OPTIONS|AR |RESET)" | sed 's/^/    /'
cd - >/dev/null
fi
# The Port 1 and 2 Input items (plan 7.D.5; the review of step 5, which had
# apf_json_check.py read the paddle and light gun arms from the wrapper):
# input_test.py's image reads the ports every frame as paddle, driving and
# light-gun games do and stores what it saw; +joyscript presses the
# controllers and prints it (INPUT lines: tb_load's show, the wrapper's port
# types, each port's driving gray codes). Six runs cover every menu value on
# port 1 and the four of port 2: Joystick (0, and 1), Paddles (2), Driving
# (3), Light Gun (4), Dual Stick (5), Booster Grip (6). tb_load's joy bits:
# 0 right, 1 left, 2 down, 3 up, 9 A (fire 1), 10 B, 11 X, 12 Y.
if want inputs; then
echo "-- Port Input: each port type as input_test.py's program reads it"
mkdir -p "$X/inputs"; ln -sfn "$WORK/rtl" "$X/inputs/rtl"
cd "$X/inputs"
python3 "$HERE/input_test.py" > in.a26
printf '%s\n' "0 types" "300 show" "300 joy0=1" "500 joy0=0" "560 show" "560 drive" "560 joy1=2" "760 joy1=0" \
	"820 show" "820 drive" "820 joy0=200" "880 show" "880 joy0=0" "880 joy1=1" "1080 joy1=0" "1140 drive" > pd.txt
printf '%s\n' "0 types" "300 show" "300 drive" "300 joy0=1" "500 joy0=0" "560 drive" "560 joy0=2" "760 joy0=0" \
	"820 drive" "820 joy0=200" "880 show" "880 joy0=0" "880 joy2=1" "1080 joy2=0" "1140 show" > dp.txt
printf '%s\n' "0 types" "300 show" "300 joy0=200" "360 show" "360 joy0=0" "360 joy1=9" "420 show" "420 joy1=200" \
	"480 show" "480 joy1=0" > gj.txt
printf '%s\n' "0 types" "300 show" "300 joy0=6" "360 show" "360 joy0=200" "420 show" "420 joy0=0" "420 joy1=200" \
	"480 show" "480 joy1=0" > jg.txt
printf '%s\n' "0 types" "300 show" "300 joy0=1" "360 show" "360 joy0=200" "420 show" "420 joy0=400" "480 show" \
	"480 joy0=800" "540 show" "540 joy0=1000" "600 show" "600 joy0=0" > ds.txt
printf '%s\n' "0 types" "300 show" "300 joy0=400" "420 show" "420 joy0=0" "540 show" "540 joy0=800" "660 show" \
	"660 joy0=200" "720 show" "720 joy0=0" "840 show" > bg.txt
inrun() {   # inrun TITLE CASE PORT1 PORT2 MS SCRIPT
	echo "  $1:"
	sim "$WORK/obj_load/vtb" +image=in.a26 +port1=$3 +port2=$4 +wav=$5 +joyscript=$6 $(fp "in_$2") | grep -aE "^INPUT" | sed 's/^/    /'
}
inrun "Port 1 Paddles (2), Port 2 Driving (3)" paddles_driving 2 3 1160 pd.txt
inrun "Port 1 Driving (3), Port 2 Paddles (2)" driving_paddles 3 2 1160 dp.txt
inrun "Port 1 Light Gun (4), Port 2 Joystick (0)" gun_joystick 4 0 500 gj.txt
inrun "Port 1 Joystick (0), Port 2 Light Gun (4)" joystick_gun 0 4 500 jg.txt
inrun "Port 1 Dual Stick (5), Port 2 Joystick (1)" dualstick 5 1 620 ds.txt
inrun "Port 1 Booster Grip (6), Port 2 Joystick (0)" booster 6 0 860 bg.txt
cd - >/dev/null
fi

# The console switches (plan 3.2 item 2, 7.D.5): the Left and Right
# Difficulty items (SWCHB bits 6 and 7, 1 = A), the TV Type item (bit 3, 1 =
# Colour) and L, which toggles TV Type until the item changes or the next
# load (plan O6); select and the reset switch (bits 1 and 0, low while
# pressed) from controllers 1 and 2. console_test.py's switches image copies
# SWCHB to COLUBK, so +arprobe logs every change.
if want switches; then
echo "-- Console switches: Difficulty, TV Type and L on console_test.py's SWCHB image"
mkdir -p "$X/switches"; ln -sfn "$WORK/rtl" "$X/switches/rtl"
cd "$X/switches"
python3 "$HERE/console_test.py" switches > sw.a26
printf '%s\n' "100 ldiff=A" "150 rdiff=A" "200 ldiff=B" "250 rdiff=B" "300 bw=1" "350 joy0=40" "400 joy0=0" \
	"450 joy0=40" "500 joy0=0" "550 bw=0" "600 joy0=80" "620 joy0=0" "640 joy0=100" "660 joy0=0" "680 joy1=40" \
	"700 joy1=0" > sw.txt
printf '%s\n' "100 joy0=40" "150 joy0=0" > sw_start.txt
echo "  B, B, Colour; each item in turn, L twice under B&W, select, reset, controller 2's L (expect SWCHB \$3f \$7f \$ff \$bf \$3f \$37 \$3f \$37 \$3f \$3d \$3f \$3e \$3f \$37):"
sim "$WORK/obj_load/vtb" +image=sw.a26 +arprobe +wav=720 +joyscript=sw.txt $(fp switches) | grep -aE "^(AR |SWITCH)" | sed 's/^/    /'
echo "  A, A, B&W from the load, then L (expect SWCHB \$f7, then \$ff):"
sim "$WORK/obj_load/vtb" +image=sw.a26 +arprobe +wav=200 +ldiffa +rdiffa +bw +joyscript=sw_start.txt $(fp switches_start) | grep -aE "^(AR |SWITCH)" | sed 's/^/    /'
cd - >/dev/null
fi
