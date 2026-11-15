#!/bin/bash
# Re-create the probe's scan chain in src/fpga/mister/rtl from the base
# commit's pristine sources (BASE, default the merge this branch starts from).
#   tools/ssprobe/apply.sh > tools/ssprobe/chain_map.txt
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BASE="${BASE:-92f763d}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
for f in TIA.sv RIOT/M6532.sv Maria/maria.sv 6502/mos6502_ctl.sv 6502/mos6502_dp.sv 6502/mos6502.sv 6502/sally.sv top.sv; do
	mkdir -p "$T/$(dirname "$f")"
	git -C "$ROOT" show "$BASE:src/fpga/mister/rtl/$f" > "$T/$f"
done
python3 "$HERE/scan_insert.py" "$T" "$ROOT/src/fpga/mister/rtl" --keep "$HERE/base_regs_postmap.txt"
