#!/bin/bash
# Save states (docs/SAVESTATE.md 5): re-create the scan chain in the vendored
# machine files from the base commit's pristine copies (BASE: the commit
# before the chain), with the keep list (keep.txt) and the hold rule's and
# RAM ports' replacements in scan_insert.py, and write chain_map.txt; then
# the package and docs (savestate.py gen). No line of the generated files is
# edited by hand: change the pristine file at BASE's successor and rerun.
#   tools/savestate/apply.sh
# The chain's length is measured by sim/run_sschain.sh (chain_bits.txt);
# run it and then savestate.py gen again when the chain changes.
# SPDX-License-Identifier: MIT
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
BASE="${BASE:-6e1b1e2}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
git -C "$ROOT" archive "$BASE" src/fpga/mister/rtl | tar -x -C "$T"
python3 "$HERE/scan_insert.py" "$T/src/fpga" "$ROOT/src/fpga" --keep "$HERE/keep.txt" > "$HERE/chain_map.txt"
grep -q "^# UNMATCHED" "$HERE/chain_map.txt" && { echo "apply.sh: a kept register matched no chained name (chain_map.txt)" >&2; exit 1; }
python3 "$HERE/savestate.py" gen
