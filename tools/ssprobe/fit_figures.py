#!/usr/bin/env python3
"""Fit figures for the save-state probe: totals, the entity table rows of the
machine (ALMs needed (own), ALUTs, registers), and the worst setup/hold slack
per clock over every corner.

Usage: fit_figures.py OUTPUT_FILES_DIR [BASE_OUTPUT_FILES_DIR]
With a base, prints the deltas too.
"""
import os
import re
import sys

ENTITIES = [
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|M6502C:cpu_inst",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|M6532:riot_inst",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|TIA:tia_inst",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|TIA:tia_inst|video_stabilize:stab",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|maria:maria_inst",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|cpu_phase_controller:phase_controller",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|cart2600:cart2600",
    "|apf_top|core_top:ic|atari2600_pocket:atari|Atari7800:main|video_mux:mux",
    "|apf_top|core_top:ic|atari2600_pocket:atari",
    "|apf_top|core_top:ic",
]
CLOCKS = {
    "counter[0]": "clk_sys",
    "counter[1]": "clk_sdram",
    "counter[3]": "clk_arm",
    "clk_74a": "clk_74a",
    "bridge_spiclk": "bridge_spiclk",
}


def num(s):
    m = re.match(r"\s*([-0-9.]+)\s*(?:\(([-0-9.]+)\))?", s)
    return (float(m.group(1)), float(m.group(2)) if m.group(2) else None)


def figures(d):
    fit = open(os.path.join(d, "ap_core.fit.rpt"), errors="replace").read()
    out = {}
    s = open(os.path.join(d, "ap_core.fit.summary")).read()
    out["alms"] = int(re.search(r"Logic utilization \(in ALMs\) : ([\d,]+)", s).group(1).replace(",", ""))
    out["regs"] = int(re.search(r"Total registers : (\d+)", s).group(1))
    out["m10k"] = int(re.search(r"Total RAM Blocks : (\d+)", s).group(1))
    out["dsp"] = int(re.search(r"Total DSP Blocks : (\d+)", s).group(1))
    i = fit.index("; Fitter Resource Utilization by Entity")
    tab = fit[i:fit.index("\n\n", i)]
    ents = {}
    for line in tab.splitlines():
        f = [x.strip() for x in line.split(";")]
        if len(f) > 16 and f[15].startswith("|apf_top"):
            ents[f[15]] = dict(alm=num(f[2]), aluts=num(f[7]), regs=num(f[8]))
    out["ents"] = ents
    sta = open(os.path.join(d, "ap_core.sta.summary")).read()
    slack = {}
    for m in re.finditer(r"Type\s*: (.*?) Model (Setup|Hold) '([^']*)'\s*\nSlack\s*: ([-0-9.]+)", sta):
        clk = next((v for k, v in CLOCKS.items() if k in m.group(3)), m.group(3))
        key = (clk, m.group(2))
        v = float(m.group(4))
        if key not in slack or v < slack[key]:
            slack[key] = v
    out["slack"] = slack
    return out


def main():
    a = figures(sys.argv[1])
    b = figures(sys.argv[2]) if len(sys.argv) > 2 else None

    def d(x, y, fmt="%+.1f"):
        return (" (" + fmt % (x - y) + ")") if b is not None else ""
    print("ALMs %d%s, registers %d%s, M10K %d%s, DSP %d%s" % (
        a["alms"], d(a["alms"], b["alms"] if b else 0, "%+d"), a["regs"], d(a["regs"], b["regs"] if b else 0, "%+d"),
        a["m10k"], d(a["m10k"], b["m10k"] if b else 0, "%+d"), a["dsp"], d(a["dsp"], b["dsp"] if b else 0, "%+d")))
    print("%-70s %16s %12s %12s" % ("entity", "ALMs (own)", "ALUTs", "regs"))
    for e in ENTITIES:
        if e not in a["ents"]:
            continue
        x = a["ents"][e]
        line = "%-70s %8.1f (%6.1f) %6d (%4d) %6d (%4d)" % (
            e.replace("|apf_top|core_top:ic|atari2600_pocket:atari", "~"), x["alm"][0], x["alm"][1],
            x["aluts"][0], x["aluts"][1], x["regs"][0], x["regs"][1])
        if b and e in b["ents"]:
            y = b["ents"][e]
            line += "   delta ALMs %+7.1f regs %+5d" % (x["alm"][0] - y["alm"][0], x["regs"][0] - y["regs"][0])
        print(line)
    print("worst slack over the four corners (ns):")
    for k in sorted(a["slack"]):
        line = "  %-14s %-5s %7.3f" % (k[0], k[1], a["slack"][k])
        if b and k in b["slack"]:
            line += "  (base %7.3f, %+.3f)" % (b["slack"][k], a["slack"][k] - b["slack"][k])
        print(line)


if __name__ == "__main__":
    main()
