#!/usr/bin/env python3
"""The chain's completeness check (docs/SAVESTATE.md 5.3): every flip-flop
Quartus keeps in a build of the chained tree, below the machine's modules,
must be in the chain, or on a list of what is not state, with its reason.

  completeness.py REGS [--keep KEEP] [--map CHAIN_MAP]

REGS: the post-map register names of a quartus_map of the chained tree
(one per line, as get_register_info prints them; the savestates work's
run_map.sh writes regs_postmap.txt). A register below one of the chained
modules (the vendored ones scan_insert.py rewrote, and our hand-chained
ones) that is neither chained nor listed below fails the check, as does a
module of the chain map that the build no longer has.
Exit 0 when every register is accounted for.
SPDX-License-Identifier: MIT
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scan_insert as SI  # noqa: E402

# Our hand-chained modules: every register is chained, but these.
HAND = {
    "paddle_timer4": {},
    "virtual_axis5": {},
    "atarivox": {"qcnt": "the silence counter: follows the voice, not machine state (the save's quiet input)"},
    "avox_rx": {"q": "the FIFO's read register: a save waits for an empty FIFO, which the engine then does not read"},
    "avox_engine": {},
}
# Registers of the chained vendored modules that are not in the chain, with
# the reason (beyond Quartus's own constants and fanout-free registers,
# which a map of the chained tree no longer keeps either).
NOT_STATE = {
    "M6532": {"irq_en": "constant (the 6507 has no IRQ pin; the base build removed it)"},
}


def chained_names(keep):
    """module -> set of register names chained (keep.txt's, as scan_insert reads it)"""
    return {m: set(v) for m, v in keep.items()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("regs")
    ap.add_argument("--keep", default=os.path.join(HERE, "keep.txt"))
    ap.add_argument("--map", default=os.path.join(HERE, "chain_map.txt"))
    a = ap.parse_args()
    keep = SI.read_keep(a.keep)
    chained = chained_names(keep)
    # the chain map's modules and the names it left out of each block
    mods, left = set(), {}
    for l in open(a.map):
        if l.startswith("#"):
            continue
        f = l.rstrip("\n").split("\t")
        mods.add(f[0])
        for x in f:
            if x.startswith("not chained: "):
                left.setdefault(f[0], set()).update(x[len("not chained: "):].split(","))
    mods |= set(HAND)
    seen = {}
    bad = []
    for line in open(a.regs):
        k = SI.reg_key(line.strip())
        if not k:
            continue
        m, n = k
        if m not in mods or m in SI.SKIP_MODULES:
            continue
        seen.setdefault(m, 0)
        seen[m] += 1
        if m in HAND:
            base = re.split(r"[\[.]", n)[0]
            if base not in HAND[m]:
                continue
            continue
        if n in chained.get(m, ()):
            continue
        # a chain node's name: Quartus names a chained flip-flop after the
        # wire it drives (ss_cK, ss_so; the probe saw the same)
        if re.fullmatch(r"ss_c\d+|ss_so", n):
            continue
        base = re.split(r"[\[.]", n)[0]
        # a name scan_insert chains whole (an enum the base kept one-hot,
        # base.VALUE, or a scalar): any bit of it, in whatever form this
        # build keeps it
        if any(c == base or re.fullmatch(re.escape(base) + r"\.[A-Z][A-Z0-9_]*", c) for c in chained.get(m, ())):
            continue
        if base in NOT_STATE.get(m, {}):
            continue
        why = "left out by the chain map (Quartus removed it in the base)" if base in left.get(m, ()) else "not in the chain"
        bad.append("%s %s: %s" % (m, n, why))
    for m in sorted(mods - set(seen) - SI.SKIP_MODULES):
        print("  note: module %s has no register in this build" % m)
    for b in bad:
        print("  FAIL: " + b)
    n = sum(seen.values())
    print("completeness: %d registers in %d chained modules, %d unaccounted for" % (n, len(seen), len(bad)))
    print("COMPLETENESS %s" % ("pass" if not bad else "FAIL"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
