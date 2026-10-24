#!/bin/bash
# core_top.v against the APF package files: sim/tb_core_top.sv with a
# stand-in wrapper and stand-ins for the Intel IP. Checks the JSON files
# first (sim/check/apf_json_check.py), which also writes the bench's
# stimulus. Prints APF_JSON and CORE_TOP verdicts; exit 0 when both pass.
#   ./run_core_top.sh
# Environment (optional): WORK=DIR (default sim/work_core_top),
# VERILATOR=BIN (5.040), RTL_TREE=DIR (another checkout's src/fpga and dist).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="${RTL_TREE:-$HERE/..}"
FPGA="$TREE/src/fpga"
WORK="${WORK:-$HERE/work_core_top}"
mkdir -p "$WORK"

set +e
python3 -I "$HERE/check/apf_json_check.py" --root "$TREE" --vectors "$WORK/vectors.txt" --plusargs "$WORK/plusargs.txt"
json=$?
set -e

# The macros the Pocket build sets (ap_core.qsf), so core_top.v's ports and
# `ifdef blocks are the release build's
DEFS=()
while read -r m; do DEFS+=("+define+$m"); done < <(sed -n 's/^set_global_assignment -name VERILOG_MACRO "\([^"]*\)".*/\1/p' "$FPGA/ap_core.qsf")

python3 -I "$HERE/make_wrap_stub.py" "$FPGA/core/atari2600_pocket.sv" > "$WORK/wrap_stub.sv"
rm -rf "$WORK/obj"
"${VERILATOR:-verilator}" --binary --timing -j "${VL_JOBS:-2}" -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
	-Wno-TIMESCALEMOD -Wno-PINMISSING "${DEFS[@]}" --top-module tb_core_top -Mdir "$WORK/obj" -o vtb \
	"$HERE/sim_stubs.sv" "$HERE/core_top_stubs.sv" "$WORK/wrap_stub.sv" \
	"$FPGA/apf/common.v" "$FPGA/pocket_utils/data_loader.sv" \
	"$FPGA/pocket_utils/sound_i2s.sv" "$FPGA/core/audio_filter.sv" "$FPGA/core/pll_region.v" \
	"$FPGA/core/core_bridge_cmd.v" "$FPGA/core/core_top.v" "$HERE/tb_core_top.sv" > "$WORK/build.log" 2>&1 \
	|| { tail -40 "$WORK/build.log"; echo "CORE_TOP FAIL (build)"; exit 1; }
"$WORK/obj/vtb" +vectors="$WORK/vectors.txt" $(cat "$WORK/plusargs.txt") | tee "$WORK/run.log"
grep -q "^CORE_TOP pass$" "$WORK/run.log" && [ $json -eq 0 ]
