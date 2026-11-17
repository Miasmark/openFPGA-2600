#!/bin/bash
# The save-state chain's length (docs/SAVESTATE.md 5.1), measured in the
# whole core: tb_load +ss_measure fills the chain with 0, shifts a 1 through
# it and prints each segment's length. Without --write the measured length
# must equal tools/savestate/chain_bits.txt (the generated package's
# SS_CHAIN_BITS); with --write it is written there (then run
# tools/savestate/savestate.py gen and build again).
#   sim/run_sschain.sh [--write]
# Environment: WORK (default sim/work/sschain), VERILATOR, RTL_TREE as
# run_sim.sh. Prints "SSCHAIN bits ..." and "SSCHAIN pass" or "SSCHAIN FAIL".
# SPDX-License-Identifier: MIT
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${RTL_TREE:-$HERE/..}"
WORK="${WORK:-$HERE/work/sschain}"
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
SS_BENCH=1 BUILD_TOP=tb_load WORK="$WORK" bash "$HERE/run_sim.sh" > "$WORK/build.log" 2>&1 \
	|| { tail -5 "$WORK/build.log"; echo "SSCHAIN FAIL (build)"; exit 1; }
cd "$WORK"
python3 "$HERE/ssprobe_test.py" > sschain_test.a26
./obj_load/vtb +image=sschain_test.a26 +ss_measure > measure.log 2>&1
line="$(grep -a -m1 '^SSCHAIN bits' measure.log)"
echo "${line:-SSCHAIN no measurement (see $WORK/measure.log)}"
n="$(sed -n 's/^SSCHAIN bits \([0-9]*\):.*/\1/p' measure.log)"
[ -n "$n" ] || { echo "SSCHAIN FAIL"; exit 1; }
want="$(awk '{print $1; exit}' "$ROOT/tools/savestate/chain_bits.txt" 2>/dev/null)"
if [ "${1:-}" = --write ]; then
	echo "$n measured by tb_load +ss_measure:${line#*:}" > "$ROOT/tools/savestate/chain_bits.txt"
	echo "SSCHAIN wrote tools/savestate/chain_bits.txt ($n)"
	exit 0
fi
[ "$n" = "$want" ] && { echo "SSCHAIN pass ($n bits, as chain_bits.txt)"; exit 0; }
echo "SSCHAIN FAIL: measured $n, chain_bits.txt says ${want:-nothing}"; exit 1
