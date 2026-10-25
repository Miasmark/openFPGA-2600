#!/usr/bin/env python3
"""The modules openFPGA-2600 shares with openFPGA-7800, preprocessed alike
(openFPGA-2600 plan step 6: "pp_equiv --files against 3c7041c for shared
modules"; plan 9, "shared files drift between repos").

  pp_shared.py --ref-repo DIR [--ref-rev REV] [--repo DIR] --out DIR
               [--diverged PATH,...]

Both Quartus file lists come from each tree's own ap_core.qsf (pp_equiv.py's
walk, which also gives the qsf's VERILOG_MACROs). A shared module is a
Verilog/SystemVerilog file at the same path under src/fpga in both builds.
Each is preprocessed alone with pp_equiv.py --files and the build's macros
(comments, spacing and blank lines do not count), once from openFPGA-7800 at
REV (default 3c7041c, the commit the import names) and once from this tree,
and the two hashes must be equal, except for the files DIVERGED lists: the
ones the 2600 core changed on purpose. A listed file that no longer differs
fails too (the list is stale), and so do two macro sets that differ (a shared
file would see other macros). Prints one line per diverged file, the count of
equal ones, and PP_SHARED pass or FAIL; exit 0 or 1 (2 on a usage or git
error). --diverged replaces DIVERGED with the paths given (relative to
src/fpga; "" for none), for selftest.py's scratch trees.
SPDX-License-Identifier: MIT
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PP = os.path.join(HERE, "pp_equiv.py")

# the shared paths the 2600 core changed on purpose, and the step that did
DIVERGED = {
    "core/core_top.v": "plan steps 3 and 5: the data slots, the menu, the scaler slot",
    "core/bupchip/bupchip_pocket.sv": "plan step 3: the CAP_A78 parameter (capture in image mode only)",
    "core/bupchip/bup_capture.sv": "plan step 3: the A78 parameter (capture in image mode only)",
    "mister/rtl/top.sv": "plan step 4: the 7800 cartridge, RAM, BIOS path, INPTCTRL and MARIA cut out",
    "mister/rtl/Maria/maria.sv": "plan step 4(c): MARIA reduced to its clock and 2600 decode",
}


def qsf_list(fpga, out):
    r = subprocess.run([sys.executable, PP, fpga, out], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"pp_shared: pp_equiv.py on {fpga} failed:\n{r.stdout}{r.stderr}")
    m = re.search(r"macros: (.*)$", r.stdout, re.M)
    files = [l.strip() for l in open(os.path.join(out, "files.txt")) if l.strip()]
    files = [f for f in files if re.search(r"\.(s?v|svh?|vh)$", f) and " " not in f]
    return files, (m.group(1).split() if m else [])


def one(out, path, macros):
    defs = []
    for x in macros:
        defs += ["-D", x]
    r = subprocess.run([sys.executable, PP, "--files", out, path] + defs, capture_output=True, text=True)
    if r.returncode != 0:
        return None, (r.stdout + r.stderr).strip().splitlines()[-1:]
    return r.stdout.split()[0], None


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--ref-repo", required=True)
    p.add_argument("--ref-rev", default="3c7041c")
    p.add_argument("--repo", default=os.path.dirname(os.path.dirname(HERE)))
    p.add_argument("--out", required=True)
    p.add_argument("--diverged", help="the diverged paths, comma-separated (default: DIVERGED)")
    a = p.parse_args()
    div = DIVERGED if a.diverged is None else {x: "given" for x in a.diverged.split(",") if x}
    os.makedirs(a.out, exist_ok=True)
    ref = os.path.join(a.out, "ref")
    subprocess.run(["rm", "-rf", "--", ref], check=True)
    os.makedirs(ref)
    arch = subprocess.run(["git", "-C", a.ref_repo, "archive", a.ref_rev, "src/fpga"], capture_output=True)
    if arch.returncode != 0:
        print(f"pp_shared: git archive {a.ref_rev} in {a.ref_repo}: {arch.stderr.decode(errors='replace').strip()}")
        return 2
    subprocess.run(["tar", "-x", "-C", ref], input=arch.stdout, check=True)
    rf, rm = qsf_list(os.path.join(ref, "src", "fpga"), os.path.join(a.out, "qsf_ref"))
    mf, mm = qsf_list(os.path.join(a.repo, "src", "fpga"), os.path.join(a.out, "qsf_this"))
    bad = []
    print(f"openFPGA-7800 {a.ref_rev}: {len(rf)} Verilog files, macros {' '.join(rm)}")
    print(f"this tree: {len(mf)} Verilog files, macros {' '.join(mm)}")
    if sorted(rm) != sorted(mm):
        bad.append(f"the two builds' macro sets differ: {sorted(set(rm) ^ set(mm))}")
    common = [f for f in mf if f in set(rf)]
    print(f"shared: {len(common)} files at the same path in both builds; only in this one: "
          f"{' '.join(f for f in mf if f not in set(rf)) or 'none'}")
    same = 0
    for i, f in enumerate(common):
        h0, e0 = one(os.path.join(a.out, "f", str(i), "ref"), os.path.join(ref, "src", "fpga", f), rm)
        h1, e1 = one(os.path.join(a.out, "f", str(i), "this"), os.path.join(a.repo, "src", "fpga", f), mm)
        if h0 is None or h1 is None:
            bad.append(f"{f}: preprocessor error {e0 or e1}")
        elif h0 == h1:
            if f in div:
                bad.append(f"{f}: listed as diverged ({div[f]}) but preprocesses as 7800's: the list is stale")
            same += 1
        elif f in div:
            print(f"  diverged, as listed: {f} ({div[f]})")
        else:
            bad.append(f"{f}: preprocesses differently from openFPGA-7800 {a.ref_rev}'s (this {h1[:16]}, 7800 {h0[:16]})")
    for f in div:
        if f not in common:
            bad.append(f"{f}: listed as diverged but not a shared file of the build")
    print(f"equal: {same} of {len(common)} shared files")
    for b in bad:
        print("  FAIL: " + b)
    print("PP_SHARED " + ("pass" if not bad else f"FAIL ({len(bad)})"))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
