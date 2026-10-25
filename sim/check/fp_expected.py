#!/usr/bin/env python3
"""FP_REF's expected differences, one fingerprint cell each (step7_gates.sh).

  fp_expected.py REF CAND OUT CELL...

CELL is FRAME:COLUMN:REF_VALUE:RUN_VALUE. For each CELL, REF (the FP_REF
file) must hold REF_VALUE and CAND (this run's file) RUN_VALUE in that frame
and column, exactly; anything else is a FAIL (exit 1), so a cell that changes
again on either side is seen. OUT is then REF with each CELL set to its
RUN_VALUE, for frame_gate.py --strict OUT CAND: every other cell must still
be equal. Each accepted cell is printed with "expected difference".
"""
import csv
import sys


def rows(path):
    with open(path, newline="") as f:
        r = list(csv.reader(f))
    return r[0], r[1:]


def main():
    if len(sys.argv) < 5:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    ref, cand, out, cells = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    hr, rr = rows(ref)
    hc, rc = rows(cand)
    bad = 0
    for cell in cells:
        frame, col, rv, cv = cell.split(":")
        if col not in hr or col not in hc:
            print(f"  FAIL: expected difference frame {frame} {col}: no column {col}")
            bad = 1
            continue
        ir, ic = hr.index(col), hc.index(col)
        a = [x for x in rr if x and x[0] == frame]
        b = [x for x in rc if x and x[0] == frame]
        if len(a) != 1 or len(b) != 1:
            print(f"  FAIL: expected difference frame {frame} {col}: frame {frame} not found once in both files")
            bad = 1
            continue
        if a[0][ir] != rv or b[0][ic] != cv:
            print(f"  FAIL: expected difference frame {frame} {col}: FP_REF {a[0][ir]} (expected {rv}),"
                  f" this run {b[0][ic]} (expected {cv})")
            bad = 1
            continue
        a[0][ir] = cv
        print(f"  expected difference: frame {frame} {col}, FP_REF {rv}, this run {cv}")
    if bad:
        return 1
    with open(out, "w", newline="") as f:
        csv.writer(f, lineterminator="\n").writerows([hr] + rr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
