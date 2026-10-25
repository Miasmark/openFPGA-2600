#!/usr/bin/env python3
"""Verdict of a run_sim.sh log, as one exit code (DARIA step 7, plan 1.2 row 3;
openFPGA-2600 plan step 6: the 2600 cases alone).

  run_sim_check.py LOG [--build plain|daria|auto] [--ref REF_LOG] [--only daria]

run_sim.sh prints measurements and a few verdicts (A78_REFUSAL, PLL_REGION,
DARIA) and exits 0 whatever they say. This checks every case against its
expected lines and fails on:
  - a section that is missing, or says "skipped": a skipped section is not a
    pass;
  - any FAIL verdict, a MISSING pattern, a simulator error;
  - a TONE ratio outside 0.990-1.010 where the case must play its tone;
  - video geometry other than the documented frame (lines, pixels, PAL flag,
    frame length in clk_sys) for each case, and a last FRAME line other than
    the run's own (FRAME 17 at 300 ms; FRAME 75 for the PAL 2600 case's
    +long run): tb_system prints its FRAME lines only when the run ends, so
    an earlier number means a run that stopped or changed length;
  - a "SIMULATOR EXIT N" line: a bench that exited non-zero, e.g. on a
    $fatal, in a case whose output run_sim.sh pipes through grep (which
    drops the "%Fatal" line);
  - the loads (an A78 refused: stored whole, the bad game screen, silent; a
    headerless 2600 image and its tone), the A78 refusal's verdict, the
    reloads' BOOT and IMAGE2 lines (each reset release's vector and first
    opcode from the cartridge slot; the second image loaded, a 2600 image
    after a refused A78 too), the PLL retune, audio filter and virtual axis
    lines other than expected;
  - the FA2 flash save slot's lines (fa2.sav, sim/fa2_test.py's program)
    other than expected: each FA2 program run done with 2 flash loads, 1
    save and 256 writes into the slot's RAM, 0 bytes wrong in the work RAM
    after the reload and in the slot read back, and both A78 runs (refused:
    the bad game screen's scheme, 32) leaving the file as it was;
  - tb_vaxis5 (sim/run_vaxis5.sh) other than its four seeds of 10^7 clocks
    with 0 mismatches each, the planted fault caught and "VAXIS5 pass";
  - tb_region (sim/run_region.sh) other than its lines for the DARIA and
    the plain build (every trial with the retunes wanted, no retune back to
    back, and in the DARIA build daria_rgn exact: scenarios A, B and C for
    DARIA, A and B for plain, whose C is not judged), its four planted
    variants caught, the sketch by its hazard in C (a retune back to back
    or daria_rgn wrong), and "REGION pass";
  - "exit N" with N != 0 when the log records the script's exit status.
The 7800 core's sections (its 7800-mode tones and MARIA's border and
geometry, the BIOS boot rule, the BupChip end to end, the POKEY reads) are
gone with that hardware: a log that still holds one of them fails ("a 7800
section"), as a 7800 core's log is not this core's.
DARIA section: in the DARIA build (--build daria, or auto from run_sim.sh's
"POCKET_DARIA 1" line) "DARIA pass" is required. In the plain build the
section prints that it is inactive; that is reported, and is not a pass of
anything. A log from before step 7 (no "-- run_sim.sh:" line) has no DARIA
section at all; it is then checked as a plain build.
In a BUP_DEBUG build of DARIA (the "-- run_sim.sh:" line's defines hold
-DBUP_DEBUG) the DARIA status overlay's lines are required too: one
"overlay: ... PASS" line under each of the section's six runs (smoke_dpc,
smoke_cdf, digital_cdfj, frame_cdfj, frame_cdfj_pattern, frame_cdfj_retune),
each with its "checked:" field stating the requirement run_sim.sh's OVL
table gives that run (OVL_REQ below: the rows, the waiver or a cell floor,
the exact late calls, the forced guard, the pattern, the second reset), and
the section's "overlay cells: ...; pass" line; a BUP_DEBUG build without
them fails ("the overlay check did not run"), and so does an overlay line in
a build without BUP_DEBUG.
--only daria checks a run_sim.sh ONLY=daria log (tb_load and the DARIA
section alone): the global rules and the DARIA section only. A log that
says ONLY=daria fails without it, and one that does not fails with it.
--ref REF_LOG also compares every measurement and verdict line with another
log (e.g. the same tree before a bench change): any difference fails.
Exit status: 0 pass, 1 fail, 2 usage.
SPDX-License-Identifier: MIT
"""
import argparse
import re
import sys

TONE = re.compile(r"^\s*TONE (?:AUDC0=4|from loaded cart) AUDF0=(\d+): measured ([0-9.]+) Hz, "
                  r"TIA reference ([0-9.]+) Hz, ratio ([0-9.]+)$")
# (frame_ and overlay: lines of BUP_DEBUG builds only, so a reference log of
# a build without BUP_DEBUG compares as before)
VERDICT_LINE = re.compile(r"^\s*(TONE|FRAME|\+|LOAD|BOOT|IMAGE2|A78_REFUSAL|REFUSE|"
                          r"NTSC|PAL ->|PLL_REGION|AUDIO|AXIS|DARIA|smoke_|digital_|frame_|overlay)")
# the 7800 core's sections: a log with one of them is not this core's
SECTIONS_7800 = ("-- border hidden", "-- PAL and overscan geometry", "-- 7800 BIOS", "-- BupChip end to end",
                 "-- POKEY reads")
# the reloads (run_sim.sh's "-- reloads"): each case's title and the lines
# it must hold. A reset release takes its vector and first opcode from the
# cartridge slot at $f000: the 2600 images', and the refused A78's (its 16
# KiB payload's last 4 KiB as the bad game screen's scheme sees them).
BOOT_SLOT = (r"BOOT {n} vector: \$f000 from the cartridge slot, first opcode fetch at \$f000 from the cartridge slot")
BOOT_AT = r"BOOT {n} at \d+ ms: use_bios 0, bypass_bios 1, tia_mode 1, cart_present 1"
BOOT_ROM = r"BOOT {n} after 50 ms: 0 CPU reads from the BIOS ROM, tia_en 1"
RELOADS = [
    ("2600 image, then another 2600 image", [
        BOOT_AT.format(n=1), BOOT_SLOT.format(n=1), BOOT_ROM.format(n=1),
        r"IMAGE2 load_test2\.a26 loaded at \d+ ms: 4096 bytes, tia_mode=0, mapper 0",
        BOOT_AT.format(n=2), BOOT_SLOT.format(n=2), BOOT_ROM.format(n=2)]),
    ("a refused A78, then a 2600 image", [
        BOOT_AT.format(n=1), BOOT_SLOT.format(n=1), BOOT_ROM.format(n=1),
        r"IMAGE2 load_test\.a26 loaded at \d+ ms: 4096 bytes, tia_mode=0, mapper 0",
        BOOT_AT.format(n=2), BOOT_SLOT.format(n=2), BOOT_ROM.format(n=2)]),
]
OVL_RUNS = ("smoke_dpc", "smoke_cdf", "digital_cdfj", "frame_cdfj", "frame_cdfj_pattern", "frame_cdfj_retune")
# What each run's overlay line must say it required and checked (run_sim.sh's
# OVL table): a line that passes on a smaller requirement fails here.
_WAIVED = r"required 000000000, at least 0 cells\)"
_LATE = r"\(required, with exactly (\d+) late calls\)"
_SOME_LATE = r"\(required, with late calls above 0 and below the calls\)"
OVL_REQ = {
    "smoke_dpc": [_WAIVED],
    "smoke_cdf": [_WAIVED],
    "digital_cdfj": [r"required 000000111, at least [1-9]\d* cells\)"],
    "frame_cdfj": [r"required 000111111, at least [1-9]\d* cells\)", _LATE],
    "frame_cdfj_pattern": [r"required 111111111, at least [1-9]\d* cells\)", _LATE,
                           r"guard forced: [1-9]\d* unlock pulses counted, locked on [1-9]\d* clk_sys \(required at least [1-9]\d* pulses\)",
                           r"; pattern read back as forced \("],
    "frame_cdfj_retune": [r"required 000111111, at least [1-9]\d* cells\)", _SOME_LATE,
                          r"reset releases [2-9]\d* \(required at least 2\)"],
}
AXIS = [
    r"AXIS start at 128",
    r"AXIS 16 ms tap right: 129",
    r"AXIS right to the end\s+305\s+ms to reach 255",
    r"AXIS left across, normal\s+511\s+ms to reach 0",
    r"AXIS right across, fast \(Y\)\s+265\s+ms to reach 255",
    r"AXIS left 64, slow \(X\)\s+677\s+ms to reach 191",
    r"AXIS driving, 1 s right: 18 gray steps, 51 ms apart at full speed",
    r"AXIS driving, 1 s right fast \(Y\): 37 gray steps, 25 ms apart at full speed",
    r"AXIS stick 200 -> position 200 after 40 ms",
    r"AXIS stick 60 -> position 60 after 40 ms",
    r"AXIS D-pad press \(rest now 60\), then stick 250: 250",
    r"AXIS driving, stick pushed fully right 1 s: 31 gray steps, 32 ms apart",
]
# tb_vaxis5 through sim/run_vaxis5.sh's defaults: seeds 1-4, 10^7 clocks each
VAXIS5 = [r"VAXIS5 seed %d cycles 10000000 ticks [1-9]\d* resets [1-9]\d* \(on a tick [1-9]\d*, "
          r"1-4 clocks after one [1-9]\d*\) mismatches 0" % k for k in (1, 2, 3, 4)] + [
    r"VAXIS5 planted fault \(axis 4 reads axis 3's slow\), seed 1: caught, [1-9]\d* mismatches",
    r"VAXIS5 pass",
]
# tb_region through sim/run_region.sh: the region logic of both builds in
# RTL-1's and RTL-2's load sequences, and its planted variants. The plain
# build's C line is not judged (back-to-back retunes there are the build
# without DARIA's own, as in 2.2.1). The sketch's C line must show the hazard
# it was rejected for, so that "caught" means the bench saw it. REGION lines
# are not in VERDICT_LINE, so a --ref log from before the bench still compares.
REGION = [
    r"REGION daria A trials 1641 retunes 1:1641 rgn_bad 0 b2b 0",
    r"REGION daria B pal trials 11 retunes 0:11 rgn_bad 0 b2b 0",
    r"REGION daria B ntsc trials 11 retunes 1:11 rgn_bad 0 b2b 0",
    r"REGION daria C trials 49 retunes 2:49 rgn_bad 0 b2b 0",
    r"REGION plain A trials 1641 retunes 1:1641 rgn_bad \d+ b2b 0",
    r"REGION plain B pal trials 11 retunes 0:11 rgn_bad \d+ b2b 0",
    r"REGION plain B ntsc trials 11 retunes 1:11 rgn_bad \d+ b2b 0",
    r"REGION sketch C trials 49 retunes [\d: ]+ rgn_bad (?:[1-9]\d* b2b \d+|\d+ b2b [1-9]\d*)",
    r"REGION verdict daria: pass \(.*\)",
    r"REGION verdict plain: pass \(.*\)",
] + [r"REGION verdict %s: planted, caught" % v for v in ("old", "rtl2", "rtl1", "sketch")] + [r"REGION pass"]
# The FA2 flash save slot (fa2.sav): each pattern and how many times the
# section must hold it (the two FA2 program runs, then the two A78 runs; mapper
# 25 is detect2600.sv's BANKFA2). The second A78 run is one detect2600.sv
# takes for FA2, with a save command (in the 7800 core's 7800 mode it reached
# the slot until the wrapper's fa2_on gate): refused here, it runs the bad game
# screen's scheme. FA2 lines are not in VERDICT_LINE.
FA2 = [
    (r"FA2 program: mapper 25, done after \d+ ms; flash loads 2, saves 1, slot RAM writes 256", 2),
    (r"FA2 work RAM after the reload: 0 of 255 bytes differ from the expected file", 2),
    (r"FA2 save slot read back \(APF read protocol\): 0 of 256 bytes differ from the expected file", 2),
    # openFPGA-2600: an A78 is refused (plan D8): it runs the bad game screen's
    # scheme, 32, as a 2600 image (tia_mode 1), so no FA2 copy starts at all
    (r"FA2 image: 2600 mapper 32, cart_is_7800 1, tia_mode 1; flash loads 0, saves 0, slot RAM writes 0", 2),
    (r"FA2 save slot after load, reset and 300 ms of running \(APF read protocol\): "
     r"0 of 256 bytes differ from the expected file", 2),
]


class Log:
    def __init__(self, path):
        self.lines = open(path, "rb").read().decode("utf-8", "replace").splitlines()
        self.sections = []          # (header, [lines])
        cur = ("(start)", [])
        for l in self.lines:
            if l.startswith("-- "):
                self.sections.append(cur)
                cur = (l, [])
            else:
                cur[1].append(l)
        self.sections.append(cur)

    def section(self, prefix):
        for h, body in self.sections:
            if h.startswith(prefix):
                return h, body
        return None, None


def tone_ok(line, audf=None):
    m = TONE.match(line)
    if not m:
        return False
    if audf is not None and int(m.group(1)) != audf:
        return False
    return 0.990 <= float(m.group(4)) <= 1.010


def overlay_check(body, debug, bad, notes):
    """The DARIA section's overlay lines (BUP_DEBUG builds): each run's
    "overlay:" line, which must pass and say what it checked, and the
    section's "overlay cells:" line."""
    s = [x.rstrip() for x in body]
    ovl = [x.strip() for x in s if x.strip().startswith("overlay:")]
    if not debug:
        if ovl:
            bad.append("DARIA section: overlay lines in a build without BUP_DEBUG")
        return
    if not ovl and not any(x.strip().startswith("overlay cells:") for x in s):
        bad.append("BUP_DEBUG build: the overlay check did not run (no overlay lines in the DARIA section)")
        return
    for run in OVL_RUNS:
        idx = [i for i, x in enumerate(s) if re.match(r"^  %s: " % re.escape(run), x)]
        if len(idx) != 1:
            bad.append(f"BUP_DEBUG build: DARIA run {run}: {len(idx)} result lines, expected 1")
            continue
        nxt = [x.strip() for x in s[idx[0] + 1:idx[0] + 3] if x.startswith("    overlay: ")]
        if not nxt:
            bad.append(f"BUP_DEBUG build: DARIA run {run}: no overlay line")
        elif not re.search(r"; checked: \d+ cells \(rows complete [01]{9}, required [01]{9}, at least \d+ cells\)", nxt[0]) \
                or not nxt[0].endswith("; PASS"):
            bad.append(f"BUP_DEBUG build: DARIA run {run}: overlay line not a pass with its checked field: {nxt[0][:160]}")
        else:
            miss = [r for r in OVL_REQ[run] if not re.search(r, nxt[0])]
            if miss:
                bad.append(f"BUP_DEBUG build: DARIA run {run}: overlay line without its requirement: " + "; ".join(miss))
            m, n = re.search(_LATE, nxt[0]), re.match(r"overlay: calls \d+ .*?, late calls (\d+),", nxt[0])
            if m and (not n or n.group(1) != m.group(1)):
                bad.append(f"BUP_DEBUG build: DARIA run {run}: late calls {n.group(1) if n else '?'}, required {m.group(1)}")
    agg = [x.strip() for x in s if x.strip().startswith("overlay cells:")]
    if len(agg) != 1 or not re.fullmatch(r"overlay cells: [1-9]\d* read back in the section; rows complete [01]{3}111111 in "
                                         r"the normal runs, 111111111 in the pattern run \(.*\); pass", agg[0]):
        bad.append("BUP_DEBUG build: no passing 'overlay cells:' line for the section: %s" % (agg[:1] or "none"))
    else:
        notes.append("DARIA status overlay: " + agg[0])


def check(log, build, only=None):
    L = Log(log)
    bad, notes = [], []

    def need(body, pat, what):
        if body is None or not any(re.fullmatch(pat, x.strip()) for x in body):
            bad.append(f"{what}: missing /{pat}/")

    # global rules
    for x in L.lines:
        if re.search(r":\s*skipped\b", x):
            bad.append("skipped section: " + x.strip())
        if re.search(r"\bFAIL\b", x):
            bad.append("FAIL: " + x.strip())
        if "MISSING:" in x:
            bad.append(x.strip())
        if re.search(r"^(\[\d+\] )?%(Error|Fatal)|Assertion failed", x.strip()):
            bad.append("simulator: " + x.strip()[:160])
        m = re.match(r"^exit (\d+)$", x.strip())
        if m and m.group(1) != "0":
            bad.append("run_sim.sh exit status " + m.group(1))
        if x.startswith("SIMULATOR EXIT"):
            bad.append("a bench exited non-zero: " + x.strip()[:160])
    new_format = any(x.startswith("-- run_sim.sh:") for x in L.lines)
    if build == "auto":
        build = "daria" if any(re.match(r"^-- run_sim\.sh: .*POCKET_DARIA 1,", x) for x in L.lines) else "plain"
    debug = any(re.match(r"^-- run_sim\.sh: .*defines:.* -DBUP_DEBUG( |$)", x) for x in L.lines)
    said_only = next((m.group(1) for m in (re.match(r"^-- run_sim\.sh ONLY=(\w+)", x) for x in L.lines) if m), None)
    if said_only != only:
        bad.append(f"the log is a run_sim.sh ONLY={said_only} run: check it with --only {said_only}" if said_only
                   else f"--only {only}, but the log is not a run_sim.sh ONLY={only} run")
    if only == "daria":
        h, b = L.section("-- DARIA")
        if build != "daria" or h is None or "inactive" in h:
            bad.append("--only daria: the DARIA section did not run")
        elif "DARIA pass" not in [x.strip() for x in b]:
            bad.append("DARIA build: no 'DARIA pass'")
        else:
            notes.append("DARIA section: pass (ONLY=daria: no other section ran)")
        if h is not None:
            overlay_check(b, debug, bad, notes)
        return bad, notes, build

    for x in SECTIONS_7800:
        if L.section(x)[0] is not None:
            bad.append(f"a 7800 section, not this core's: {L.section(x)[0]}")
    h, b = L.section("-- 2600 mode")
    for a in (0, 14):
        if not b or not any(tone_ok(x, a) for x in b):
            bad.append(f"2600 tone AUDF0={a}: no TONE line with ratio 0.990-1.010")
    if not b or sum(1 for x in b if re.fullmatch(
            r"FRAME 17: 238944 clk_sys \(59\.923 Hz\), active lines 240, active pixels/line 160, video PAL 0", x.strip())) != 2:
        bad.append("2600 frames: expected two FRAME 17 lines, 240-line 160-pixel NTSC frames")
    h, b = L.section("-- PAL 2600 frame")
    need(b, r"FRAME 75: 284544 clk_sys \(50\.320 Hz\), active lines 288, active pixels/line 160, video PAL 1", "PAL 2600 frame")
    # openFPGA-2600: the A78 is refused (plan D8): stored whole, run as a 2600
    # image in the bad game screen, silent (its TONE line reads 0 Hz)
    h, b = L.section("-- load an A78")
    need(b, r"LOAD 16512 bytes, header ATARI, cart_is_7800=1, cart_size=16512, tia_mode=1, payload mismatches=0", "A78 load")
    need(b, r"TONE from loaded cart AUDF0=7: measured 0\.0 Hz, TIA reference 1962\.5 Hz, ratio 0\.000", "A78 load")
    h, b = L.section("-- A78 refusal")
    if b is None:
        bad.append("A78 refusal: section missing")
    elif "A78_REFUSAL pass" not in [x.strip() for x in b]:
        bad.append("A78 refusal: no 'A78_REFUSAL pass'")
    else:
        notes.append("A78 refusal: pass")
    h, b = L.section("-- load a headerless 2600 image")
    need(b, r"LOAD 4096 bytes, header .*, cart_is_7800=0, cart_size=4096, tia_mode=1, payload mismatches=0", "2600 load")
    if not b or not any(tone_ok(x, 14) for x in b):
        bad.append("2600 load: no tone AUDF0=14 with ratio 0.990-1.010")
    h, b = L.section("-- FA2 flash save slot")
    if b is None:
        bad.append("FA2 save slot: section missing")
    else:
        for pat, n in FA2:
            k = sum(1 for x in b if re.fullmatch(pat, x.strip()))
            if k != n:
                bad.append(f"FA2 save slot: {k} of {n} lines /{pat}/")
        if any(x.strip().startswith("FA2 byte") for x in b):
            bad.append("FA2 save slot: bytes differ ('FA2 byte' lines)")

    # the reloads
    h, b = L.section("-- reloads")
    if b is None:
        bad.append("reloads: section missing")
    else:
        cases, cur = [], None
        for x in b:
            if re.match(r"^  \S.*:$", x):
                cur = (x.strip(), [])
                cases.append(cur)
            elif cur:
                cur[1].append(x.strip())
        for title, pats in RELOADS:
            hit = [c for c in cases if c[0].startswith(title)]
            if len(hit) != 1:
                bad.append(f"reload '{title}': {len(hit)} found")
                continue
            for p in pats:
                if not any(re.fullmatch(p, x) for x in hit[0][1]):
                    bad.append(f"reload '{title}': missing /{p}/")
            if sum(1 for x in hit[0][1] if x.startswith("BOOT") and " at " in x and "ms:" in x) != 2:
                bad.append(f"reload '{title}': expected two reset releases (BOOT 1, BOOT 2)")

    # DARIA
    h, b = L.section("-- DARIA")
    if build == "daria":
        if h is None or "inactive" in h:
            bad.append("DARIA build: the DARIA section did not run")
        elif "DARIA pass" not in [x.strip() for x in b]:
            bad.append("DARIA build: no 'DARIA pass'")
        else:
            notes.append("DARIA section: pass")
        if h is not None and "inactive" not in h:
            overlay_check(b, debug, bad, notes)
    else:
        if h is None:
            if new_format:
                bad.append("DARIA section line missing from a step-7 run_sim.sh log")
            notes.append("DARIA section: absent (a log from before step 7); plain build, not counted")
        elif "inactive" in h:
            notes.append("DARIA section: inactive (no POCKET_DARIA); not counted as a pass")
        else:
            bad.append("plain build, but the DARIA section ran: " + h)

    # PLL retune
    h, b = L.section("-- PAL/NTSC PLL retune")
    need(b, r"NTSC -> PAL: fraction 737741760, reset held 3\.5 us before the start and 3\.5 us after relock", "PLL retune")
    need(b, r"PAL -> NTSC: fraction 1100363522, reset held 3\.5 us before the start and 3\.5 us after relock", "PLL retune")
    need(b, r"PLL_REGION pass \(0 errors\)", "PLL retune")
    # audio filter
    h, b = L.section("-- audio filter")
    m = None
    for x in b or []:
        m = re.fullmatch(r"AUDIO tone: min (-?\d+) max (-?\d+) mean (-?\d+) \(expect.*\)", x.strip()) or m
    if not m:
        bad.append("audio filter: no tone line")
    else:
        mn, mx, mean = (int(v) for v in m.groups())
        if abs(mn + 16383) > 200 or abs(mx - 16383) > 200 or abs(mean) > 64:
            bad.append(f"audio filter: tone min {mn} max {mx} mean {mean}, expect about -16383 / +16383 / 0")
    m = None
    for x in b or []:
        m = re.fullmatch(r"AUDIO silence after 2 s: (-?\d+) \(expect near 0\)", x.strip()) or m
    if not m or abs(int(m.group(1))) > 16:
        bad.append("audio filter: silence not near 0")
    # the region asked of the PLL
    h, b = L.section("-- the region asked of the PLL")
    if b is None:
        bad.append("tb_region: section missing")
    else:
        for p in REGION:
            need(b, p, "tb_region")
    # virtual axis
    h, b = L.section("-- virtual paddle")
    for p in AXIS:
        need(b, p, "virtual axis")
    # the five axes as one engine
    h, b = L.section("-- the five virtual axes")
    for p in VAXIS5:
        need(b, p, "tb_vaxis5")
    if b and any(x.startswith("MISMATCH") for x in b):
        bad.append("tb_vaxis5: MISMATCH lines")
    return bad, notes, build


def verdict_lines(path):
    out = []
    for x in open(path, "rb").read().decode("utf-8", "replace").splitlines():
        if VERDICT_LINE.match(x):
            out.append(x.strip())
    return out


def main():
    p = argparse.ArgumentParser(description="run_sim.sh log checker")
    p.add_argument("log")
    p.add_argument("--build", choices=("plain", "daria", "auto"), default="auto")
    p.add_argument("--ref")
    p.add_argument("--only", choices=("daria",))
    a = p.parse_args()
    bad, notes, build = check(a.log, a.build, a.only)
    if a.ref:
        mine, ref = verdict_lines(a.log), verdict_lines(a.ref)
        if mine != ref:
            import difflib
            d = [l for l in difflib.unified_diff(ref, mine, "ref", "log", lineterm="", n=0)
                 if not l.startswith(("---", "+++", "@@"))]
            bad.append(f"differs from the reference in {len(d)} line(s)")
            for l in d[:20]:
                bad.append("  " + l)
        else:
            notes.append(f"all {len(mine)} measurement and verdict lines equal the reference's")
    print(f"run_sim_check {a.log} ({build} build)")
    for n in notes:
        print("  note: " + n)
    for b in bad:
        print("  FAIL: " + b)
    print("RUN_SIM " + ("pass" if not bad else f"FAIL ({len(bad)} finding(s))"))
    sys.exit(0 if not bad else 1)


if __name__ == "__main__":
    main()
