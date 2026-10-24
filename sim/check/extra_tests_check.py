#!/usr/bin/env python3
"""Verdict of an extra_tests.sh log, as one exit code (DARIA step 7, plan 1.2 row 4;
openFPGA-2600 plan step 6: its 2600 sections).

  extra_tests_check.py LOG [--ref REF_LOG] [--ar-tape]

extra_tests.sh prints what it measured and its expectations in prose; this
turns every section into rules:
  SaveKey       console_test.py's 2600 image: with SaveKey On the pass tone and
                the cart's 8 bytes in the save RAM; Off (the default) the fail
                tone (no acknowledge); the round trip with the pass tone and
                exactly the 8 bytes the cart wrote differing
  Firmware      the Supercharger BIOS slot: 2048 bytes, 0 ROM bytes differ
                from the file, and the 2600 image after it plays its tone
  Supercharger  full load: magenta $54 / AUDF0 5 within 0.2 s and ARCHECK 0
                differ; multiload: red $44 / AUDF0 7, then green $c4 / AUDF0
                14 after about 1 s; two loads numbered 0: blue $84 / AUDF0 3,
                the reset, then yellow $1e / AUDF0 20; with AR_TAPE=1 (or
                --ar-tape, which requires it): the tape full load's ARCHECK 0
                differ and its tone, the multiload's two loads in order (their
                tones), and the colours equal to the reference build's
                (--ref; on the 7800 core's aeee6d2 both tape loads show white,
                not the header's red and green: reported as a note)
  cartridge RAM the CARTRAM_MATRIX and CARTRAM_S19 verdicts
                (cartram2600_test.py); with the tape path (AR_TAPE=1) also
                the matrix's tape load with +cartram ("PASS artape"), whose
                colours must equal this log's own tape full load's (the same
                image, BIOS and run, without the monitor)
  Mapper        each forced multicart (MC2K, MC4K, MC8K): the OPTIONS line
                with its bss_type index forced, four console resets, and
                between them games 0, 1, 2, 3 and 0 again, each by its own
                COLUBK and AUDF0 (console_test.py's game()) and no other value
                (MC8K's bank 1 colour $0e would be a bank switch that did not
                happen); with Mapper Auto one game before and after the reset
  Inputs        see INPUT_RUNS below: each Port Input value's port type, and
                what input_test.py's program read with each device
  Switches      see SWITCHES below: SWCHB, as console_test.py's switches image
                copies it to COLUBK, after each Difficulty and TV Type change
                and each L press
The 7800 core's sections (multisprite, POKEY, DLI, the A78 SaveKey cart,
the High Score Cart firmware) are gone with that hardware; a log holding one
fails ("a 7800 section").
and fails on any "FAIL", "skipped" or simulator error, on a "SIMULATOR EXIT
N" line (a bench that exited non-zero in a piped case), and on "exit N"
with N != 0 when the log records the exit status.
Exit status: 0 pass, 1 fail, 2 usage.
SPDX-License-Identifier: MIT
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import console_test  # noqa: E402  (sim/console_test.py: what each multicart game sets)

SECTIONS_7800 = ("-- multisprite", "-- POKEY at", "-- DLI + WSYNC", "-- Firmware slots: HSC")

TONE = re.compile(r"^TONE from loaded cart AUDF0=(\d+): measured ([0-9.]+) Hz, TIA reference ([0-9.]+) Hz, ratio ([0-9.]+)$")


def sections(lines):
    # A line starting "-- " opens a section, except cartram2600_test.py's
    # binary line ("-- tb_cartram: obj_cartram/vtb md5 ...", plan P23), which
    # it prints inside the cartridge-RAM section before the verdicts
    out, cur = [], ("(start)", [])
    for l in lines:
        if l.startswith("-- ") and not l.startswith("-- tb_cartram: "):
            out.append(cur)
            cur = (l, [])
        else:
            cur[1].append(l)
    out.append(cur)
    return out


def section(secs, prefix):
    for h, b in secs:
        if h.startswith(prefix):
            return [x.rstrip() for x in b]
    return None


def cases(body):
    """Split a section at its '  title:' lines."""
    out, cur = [], None
    for x in body or []:
        if re.match(r"^  \S.*:$", x):
            cur = (x.strip(), [])
            out.append(cur)
        elif cur:
            cur[1].append(x.strip())
    return out


def tone_ok(lines, audf):
    for x in lines:
        m = TONE.match(x.strip())
        if m and int(m.group(1)) == audf and 0.990 <= float(m.group(4)) <= 1.010:
            return True
    return False


def ar_events(lines):
    ev = []
    for x in lines:
        m = re.match(r"^AR (\d+) ms: (AUDF0 = (\d+)|COLUBK = \$([0-9a-f]{2}))$", x.strip())
        if m:
            ev.append((int(m.group(1)), "audf" if m.group(3) else "colubk", m.group(3) or m.group(4)))
    return ev


def check(a):
    lines = open(a.log, "rb").read().decode("utf-8", "replace").splitlines()
    secs = sections(lines)
    bad, notes = [], []
    ref = sections(open(a.ref, "rb").read().decode("utf-8", "replace").splitlines()) if a.ref else None

    for x in lines:
        if re.search(r":\s*skipped\b", x): bad.append("skipped: " + x.strip())
        if re.search(r"\bFAIL\b", x): bad.append("FAIL: " + x.strip())
        if re.search(r"^(\[\d+\] )?%(Error|Fatal)|Assertion failed", x.strip()): bad.append("simulator: " + x.strip()[:160])
        m = re.match(r"^exit (\d+)$", x.strip())
        if m and m.group(1) != "0": bad.append("extra_tests.sh exit status " + m.group(1))
        if x.startswith("SIMULATOR EXIT"): bad.append("a bench exited non-zero: " + x.strip()[:160])

    def need(body, pat, what):
        if body is None or not any(re.fullmatch(pat, x.strip()) for x in body):
            bad.append(f"{what}: missing /{pat}/")

    for p in SECTIONS_7800:
        if section(secs, p) is not None:
            bad.append(f"a 7800 section, not this core's: {p}")

    # SaveKey
    cs = cases(section(secs, "-- SaveKey"))
    for title, kind in (("SaveKey On", "on"), ("SaveKey Off", "off"), ("32 KiB save round trip", "rt")):
        hit = [c for c in cs if c[0].startswith(title)]
        if len(hit) != 1:
            bad.append(f"SaveKey '{title}': {len(hit)} found")
            continue
        body = hit[0][1]
        if kind in ("on", "rt") and not tone_ok(body, 7):
            bad.append(f"SaveKey '{title}': no pass tone (AUDF0=7)")
        if kind == "on":
            need(body, r"SAVEKEY EEPROM \$1234\.\.\$123B in the save RAM: a5 5a 01 02 80 7f ff 00 \(matches what the cart wrote\)",
                 f"SaveKey '{title}'")
        elif kind == "off":
            if not tone_ok(body, 31):
                bad.append(f"SaveKey '{title}': no fail tone (AUDF0=31): the EEPROM answered with SaveKey Off")
        else:
            m = None
            for x in body:
                m = re.fullmatch(r"SAVEKEY save after load, reset and running: (\d+) of 32768 bytes differ from the save file", x) or m
            if not m:
                bad.append("SaveKey round trip: no result line")
            elif int(m.group(1)) != 8:
                bad.append(f"SaveKey round trip: {m.group(1)} bytes differ, expected exactly the cart's 8")

    # Firmware slot
    cs = cases(section(secs, "-- Firmware slot"))
    hit = [c for c in cs if c[0].startswith("The BIOS through its slot")]
    if len(hit) != 1:
        bad.append(f"Firmware: {len(hit)} cases 'The BIOS through its slot'")
    else:
        need(hit[0][1], r"FIRMWARE Supercharger: 2048 byte file, 0 ROM bytes differ from it", "Firmware")
        if not tone_ok(hit[0][1], 14):
            bad.append("Firmware: no tone AUDF0=14 from the 2600 image after the BIOS")

    # Supercharger
    body = section(secs, "-- Supercharger without the BIOS")
    cs = cases(body)
    hit = {t: [c for c in cs if c[0].startswith(t)] for t in ("Full 24-page load", "Multiload", "Two loads numbered 0", "With the BIOS, from tape")}
    if len(hit["Full 24-page load"]) != 1:
        bad.append("Supercharger full load: case missing")
    else:
        b = hit["Full 24-page load"][0][1]
        ev = ar_events(b)
        if not any(e[1] == "audf" and e[2] == "5" and e[0] <= 200 for e in ev) or \
           not any(e[1] == "colubk" and e[2] == "54" and e[0] <= 200 for e in ev):
            bad.append(f"Supercharger full load: no magenta $54 / AUDF0 5 within 0.2 s ({ev})")
        need(b, r"ARCHECK 24 pages, 0 of 6144 RAM bytes differ from the image", "Supercharger full load")
    if len(hit["Multiload"]) != 1:
        bad.append("Supercharger multiload: case missing")
    else:
        ev = ar_events(hit["Multiload"][0][1])
        au = [e for e in ev if e[1] == "audf" and e[2] != "0"]
        co = [e for e in ev if e[1] == "colubk" and e[2] != "00"]
        if [e[2] for e in au[:2]] != ["7", "14"] or [e[2] for e in co[:2]] != ["44", "c4"] or au[1][0] < 900:
            bad.append(f"Supercharger multiload: {ev}, expect red $44 / AUDF0 7, then green $c4 / AUDF0 14 after about 1 s")
    if len(hit["Two loads numbered 0"]) != 1:
        bad.append("Supercharger two loads: case missing")
    else:
        b = hit["Two loads numbered 0"][0][1]
        ev = ar_events(b)
        rs = [int(m.group(1)) for x in b for m in [re.fullmatch(r"RESET at (\d+) ms", x)] if m]
        au = [e for e in ev if e[1] == "audf" and e[2] != "0"]
        if not rs or [e[2] for e in au[:2]] != ["3", "20"] or au[1][0] < rs[0] or \
           [e[2] for e in ev if e[1] == "colubk" and e[2] != "00"][:2] != ["84", "1e"]:
            bad.append(f"Supercharger two loads: {ev}, resets {rs}; expect blue $84 / AUDF0 3, the reset, yellow $1e / AUDF0 20")
    tape = hit["With the BIOS, from tape"]
    tape_full_colours = None
    if tape:
        # With the BIOS the tape loads take seconds, and the BIOS plays its
        # own tones (AUDF0 counting down) while it loads. A load has run when
        # its tone follows the tape stopping: the full load's 5; the
        # multiload's 7, then (after the tape stops again) 14. The colour
        # each program sets depends on what the BIOS leaves in $80
        # (ar_test.py): it is compared with the reference build's, and a
        # colour other than the header's (red, then green) is reported.
        b = tape[0][1]
        need(b, r"ARCHECK 24 pages, 0 of 6144 RAM bytes differ from the image", "Supercharger tape full load")
        idx = max((i for i, x in enumerate(b) if x.startswith("ARCHECK")), default=None)
        full = b[:idx] if idx is not None else b
        multi = b[idx + 1:] if idx is not None else []

        def loads(part):
            out, stopped = [], False
            for x in part:
                if re.match(r"^AR \d+ ms: tape stops", x):
                    stopped = True
                m = re.match(r"^AR (\d+) ms: AUDF0 = (\d+)$", x)
                if m and stopped and m.group(2) != "0":
                    out.append(int(m.group(2)))
                    stopped = False
            return out
        if loads(full)[:1] != [5]:
            bad.append(f"Supercharger tape full load: tones after the tape {loads(full)}, expect 5")
        tape_full_colours = [e[2] for e in ar_events(full) if e[1] == "colubk" and e[2] != "00"]
        if loads(multi)[:2] != [7, 14]:
            bad.append(f"Supercharger tape multiload: tones after the tape {loads(multi)}, expect 7, then 14")
        colours = [e[2] for e in ar_events(multi) if e[1] == "colubk" and e[2] != "00"]
        if colours[:2] != ["44", "c4"]:
            notes.append(f"Supercharger tape multiload: colours {colours}, not red $44 then green $c4 as the header "
                         f"expects (white $0e: the program did not find its control byte in $80)")
        if ref is None:
            bad.append("Supercharger tape: colours not compared (no --ref: they must equal the reference build's)")
        else:
            rt = [c for c in cases(section(ref, "-- Supercharger without the BIOS")) if c[0].startswith("With the BIOS")]
            if rt:
                mine = [e for e in ar_events(b) if e[1] == "colubk"]
                theirs = [e for e in ar_events(rt[0][1]) if e[1] == "colubk"]
                if [e[2] for e in mine] != [e[2] for e in theirs]:
                    bad.append(f"Supercharger tape: colours {[e[2] for e in mine]} differ from the reference's {[e[2] for e in theirs]}")
        if not [x for x in bad if x.startswith("Supercharger tape")]:
            notes.append("Supercharger tape path (AR_TAPE=1): full load 0 bytes differ, multiload loads 0 then 1")
    elif a.ar_tape:
        bad.append("Supercharger tape path: AR_TAPE=1 section missing")

    # cartridge RAM (step 7)
    b = section(secs, "-- 2600 cartridge RAM")
    if b is None:
        bad.append("cartridge RAM: section missing")
    else:
        for v in ("CARTRAM_MATRIX pass", "CARTRAM_S19 pass"):
            if not any(x.strip() == v for x in b):
                bad.append(f"cartridge RAM: no '{v}'")
        if tape or a.ar_tape:
            # the tape load with +cartram (artape) runs with AR_TAPE=1
            at = [x.strip() for x in b if x.strip().startswith(("PASS artape", "FAIL artape"))]
            if not any(x.startswith("PASS artape blend 0:") for x in at):
                bad.append("cartridge RAM: no 'PASS artape' (AR_TAPE=1 runs the tape load with +cartram)")
            else:
                m = re.search(r"; colours ((?:\$[0-9a-f]{2} ?)+|-)", at[0])
                cols = m.group(1).replace("$", "").split() if m and m.group(1) != "-" else []
                if tape_full_colours is not None and cols != tape_full_colours:
                    bad.append(f"cartridge RAM: artape's colours {cols} differ from the tape full load's "
                               f"{tape_full_colours} (the same run without the monitor)")
        if not [x for x in bad if x.startswith("cartridge RAM")]:
            notes.append("cartridge RAM: CARTRAM_MATRIX pass, CARTRAM_S19 pass" + (", artape pass" if tape or a.ar_tape else ""))

    mapper_check(secs, bad, notes)
    inputs_check(secs, bad, notes)
    switches_check(secs, bad, notes)
    return bad, notes


def probe_events(body):
    """tb_load's +arprobe COLUBK / AUDF0 lines and the joyscript's RESET
    lines of one case, in order: (ms, kind, value)."""
    ev = []
    for x in body:
        m = re.fullmatch(r"AR (\d+) ms: (?:COLUBK = \$([0-9a-f]{2})|AUDF0 = (\d+))", x)
        if m:
            ev.append((int(m.group(1)), "colubk" if m.group(2) else "audf", m.group(2) or m.group(3)))
        m = re.fullmatch(r"RESET at (\d+) ms", x)
        if m:
            ev.append((int(m.group(1)), "reset", None))
    return ev


def games_between_resets(ev):
    """The game each span between resets showed: the set of (colubk, audf)
    values set in it."""
    spans, cur = [], set()
    for _, k, v in ev:
        if k == "reset":
            spans.append(cur)
            cur = set()
        else:
            cur.add((k, v))
    spans.append(cur)
    return spans


def game_values(n):
    c, f = console_test.game(n)
    return {("colubk", f"{c:02x}"), ("audf", str(f))}


def mapper_check(secs, bad, notes):
    cs = cases(section(secs, "-- Mapper menu override"))
    for s, bs in ((2, 29), (4, 30), (8, 31)):
        title = f"MC{s}K forced"
        hit = [c for c in cs if c[0].startswith(title)]
        if len(hit) != 1:
            bad.append(f"Mapper '{title}': {len(hit)} found")
            continue
        body = hit[0][1]
        need_opt = rf"OPTIONS 2600 mapper {bs} \(override {bs}\)"
        if not any(re.fullmatch(need_opt, x) for x in body):
            bad.append(f"Mapper '{title}': missing /{need_opt}/")
        ev = probe_events(body)
        spans = games_between_resets(ev)
        want = [game_values(n) for n in (0, 1, 2, 3, 0)]
        # a reset's span may begin with values left from the game before it
        # only if they are written again: compare the sets each span set
        if len(spans) != 5:
            bad.append(f"Mapper '{title}': {len(spans) - 1} resets, expected 4 ({ev})")
        elif [sp for sp in spans] != want:
            bad.append(f"Mapper '{title}': games {spans}, expected games 0, 1, 2, 3, 0 ({want})")
        else:
            notes.append(f"Mapper: {title}: games 0, 1, 2, 3, 0 across 4 resets")
    hit = [c for c in cs if c[0].startswith("MC4K's image with Mapper Auto")]
    if len(hit) != 1:
        bad.append(f"Mapper Auto: {len(hit)} found")
    else:
        body = hit[0][1]
        m = [re.fullmatch(r"OPTIONS 2600 mapper (\d+) \(override 0\)", x) for x in body]
        m = [x for x in m if x]
        spans = games_between_resets(probe_events(body))
        if not m or int(m[0].group(1)) in (29, 30, 31):
            bad.append(f"Mapper Auto: the scheme detected {m[0].group(1) if m else '?'} (a multicart scheme, or no OPTIONS line)")
        elif len(spans) != 2 or not spans[0] or spans[1] != spans[0]:
            bad.append(f"Mapper Auto: {spans}: expected one game, the same before and after the reset")
        else:
            notes.append(f"Mapper: MC4K's image with Mapper Auto runs scheme {m[0].group(1)} and one game")


# The console switches: SWCHB as the switches image copies it to COLUBK, in
# order, for each case (tb_load's +arprobe prints a COLUBK line on each
# change). Bit 7 right difficulty and bit 6 left (1 = A), bit 3 TV type (1 =
# Colour), bits 1 and 0 select and reset (0 while pressed), bits 5, 4 and 2
# read as the RIOT's undriven port B pins (1).
SWITCHES = [
    ("B, B, Colour; each item in turn", ["3f", "7f", "ff", "bf", "3f", "37", "3f", "37", "3f", "3d", "3f", "3e", "3f", "37"],
     "left A, right A, left B, right B, TV Type B&W, L to Colour, L to B&W, TV Type Colour, select, reset, "
     "controller 2's L to B&W"),
    ("A, A, B&W from the load, then L", ["f7", "ff"], "both A and B&W from the load, L to Colour"),
]


def switches_check(secs, bad, notes):
    cs = cases(section(secs, "-- Console switches"))
    for title, want, what in SWITCHES:
        hit = [c for c in cs if c[0].startswith(title)]
        if len(hit) != 1:
            bad.append(f"Switches '{title}': {len(hit)} found")
            continue
        got = [v for _, k, v in probe_events(hit[0][1]) if k == "colubk"]
        if got != want:
            bad.append(f"Switches '{title}': SWCHB {' '.join(got)}, expected {' '.join(want)} ({what})")
        else:
            notes.append(f"Switches: {title}: SWCHB as expected ({what})")


# The Port Input runs (extra_tests.sh's inputs section): each run's port
# types line (the wrapper's porta_type / portb_type, the light gun's port,
# paddle_en, dual_stick), then its INPUT lines checked by INPUT_RULES below.
# input_test.py's program stores, each frame, the visible lines before each
# of INPT0-3 read charged (paddles; 192: never, 0: from the start), SWCHA
# (bits 7-4 port 1 R L D U, 3-0 port 2; a paddle's button, the driving
# controller's gray code in bits 5:4 / 1:0, the light gun's trigger in bit 4
# / 0) and INPT4 / INPT5 read live. The driving controller's gray code turns
# 3, 1, 0, 2 (then 3 again) to the right and the other way to the left.
INPUT_TYPES = {
    "Port 1 Paddles (2), Port 2 Driving (3)": "A 3, B 6; gun_en 0 on port 1, paddle_en 0011, dual_stick 0",
    "Port 1 Driving (3), Port 2 Paddles (2)": "A 6, B 3; gun_en 0 on port 1, paddle_en 1100, dual_stick 0",
    "Port 1 Light Gun (4), Port 2 Joystick (0)": "A 2, B 1; gun_en 1 on port 1, paddle_en 0000, dual_stick 0",
    "Port 1 Joystick (0), Port 2 Light Gun (4)": "A 1, B 2; gun_en 1 on port 2, paddle_en 0000, dual_stick 0",
    "Port 1 Dual Stick (5), Port 2 Joystick (1)": "A 10, B 1; gun_en 0 on port 1, paddle_en 0000, dual_stick 1",
    "Port 1 Booster Grip (6), Port 2 Joystick (0)": "A 9, B 1; gun_en 0 on port 1, paddle_en 0000, dual_stick 0",
}
GRAY_RIGHT = "3102"


def gray_dir(seq):
    """+1 when every step of the gray code sequence turns right, -1 when every
    one turns left, 0 otherwise (or fewer than two steps)."""
    if len(seq) < 2 or not all(c in GRAY_RIGHT for c in seq):
        return 0
    steps = {(GRAY_RIGHT.index(b) - GRAY_RIGHT.index(a)) % 4 for a, b in zip(seq, seq[1:])}
    return 1 if steps == {1} else -1 if steps == {3} else 0


def input_events(body):
    shows, drives, types = {}, {}, None
    for x in body:
        m = re.fullmatch(r"INPUT at (\d+) ms\s+paddles\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+gun line\s+(\d+)\s+SWCHA ([01]{8})\s+"
                         r"INPT4 ([01]) INPT5 ([01])\s+\(frame \d+\)", x)
        if m:
            g = m.groups()
            shows[int(g[0])] = {"p": [int(v) for v in g[1:5]], "gun": int(g[5]), "swcha": g[6], "inpt4": g[7], "inpt5": g[8]}
        m = re.fullmatch(r"INPUT driving gray codes at (\d+) ms: port 1 ([0-3]+|-), port 2 ([0-3]+|-)", x)
        if m:
            drives[int(m.group(1))] = (m.group(2).strip("-"), m.group(3).strip("-"))
        m = re.fullmatch(r"INPUT port types: (.*)", x)
        if m:
            types = m.group(1)
    return types, shows, drives


def input_rules(title, s, d):
    """(what, ok) pairs for one run: s the shows by ms, d the drive lines."""
    out = []
    try:
        if title.startswith("Port 1 Paddles"):
            r = s[300]["p"][0]
            out += [("paddles 0 and 1 at rest alike, inside the screen; 2 and 3 (not paddles) 192",
                     0 < r < 192 and s[300]["p"][1] == r and s[300]["p"][2:] == [192, 192]),
                    ("controller 1 right: paddle 0 below its rest, paddle 1 unmoved", s[560]["p"][0] < r and s[560]["p"][1] == r),
                    ("controller 2 left: paddle 1 above its rest", s[820]["p"][1] > r),
                    ("controller 1 A: paddle 0's button (SWCHA bit 7) low", s[880]["swcha"][0] == "0"),
                    ("controller 2 left: port 2's driving code turns left", gray_dir(d[820][1]) == -1),
                    ("controller 2 right: port 2's driving code turns right", gray_dir(d[1140][1]) == 1),
                    ("port 1 (paddles) shows no driving code", d[820][0] == "" and d[1140][0] == "")]
        elif title.startswith("Port 1 Driving"):
            r = s[300]["p"][2]
            out += [("paddles 2 and 3 at rest alike, inside the screen; 0 and 1 (not paddles) 192",
                     0 < r < 192 and s[300]["p"][3] == r and s[300]["p"][:2] == [192, 192]),
                    ("controller 1 right: port 1's driving code turns right", gray_dir(d[560][0]) == 1),
                    ("controller 1 left: port 1's driving code turns left", gray_dir(d[820][0]) == -1),
                    ("controller 1 A: the driving controller's button (INPT4) low", s[880]["inpt4"] == "0"),
                    ("controller 3 right: paddle 2 below its rest, paddle 3 unmoved", s[1140]["p"][2] < r and s[1140]["p"][3] == r)]
        elif title.startswith("Port 1 Light Gun"):
            out += [("the trigger released: SWCHA bit 4 low", s[300]["swcha"][3] == "0"),
                    ("controller 1 A: the trigger (SWCHA bit 4) high", s[360]["swcha"][3] == "1"),
                    ("controller 2 right and up: port 2's joystick lines R and U low", s[420]["swcha"][4:] == "0110"),
                    ("controller 2 A: port 2's fire (INPT5) low", s[480]["inpt5"] == "0")]
        elif title.startswith("Port 1 Joystick"):
            out += [("at rest: every line high but the port 2 trigger's (bit 0)", s[300]["swcha"] == "11111110"),
                    ("controller 1 left and down: port 1's lines L and D low", s[360]["swcha"][:4] == "1001"),
                    ("controller 1 A: port 1's fire (INPT4) low", s[420]["inpt4"] == "0"),
                    ("controller 2 A: the trigger (SWCHA bit 0) high", s[480]["swcha"][7] == "1")]
        elif title.startswith("Port 1 Dual Stick"):
            out += [("at rest: every line high", s[300]["swcha"] == "11111111"),
                    ("controller 1 right: port 1's R low", s[360]["swcha"] == "01111111"),
                    ("controller 1 A: port 2's R low", s[420]["swcha"] == "11110111"),
                    ("controller 1 B: port 2's D low", s[480]["swcha"] == "11111101"),
                    ("controller 1 X: port 2's U low", s[540]["swcha"] == "11111110"),
                    ("controller 1 Y: port 2's L low", s[600]["swcha"] == "11111011")]
        elif title.startswith("Port 1 Booster Grip"):
            out += [("at rest: INPT0 and INPT1 never charged (192)", s[300]["p"][:2] == [192, 192]),
                    ("controller 1 B (the trigger): INPT1 high from the start (0), INPT0 not", s[420]["p"][:2] == [192, 0]),
                    ("released: INPT1 192 again", s[540]["p"][:2] == [192, 192]),
                    ("controller 1 X (the booster): INPT0 high from the start (0), INPT1 not", s[660]["p"][:2] == [0, 192]),
                    ("controller 1 A: fire (INPT4) low", s[720]["inpt4"] == "0"),
                    ("released: INPT0 192 again", s[840]["p"][:2] == [192, 192])]
    except (KeyError, IndexError) as e:
        out.append((f"an INPUT line is missing ({e})", False))
    return out


def inputs_check(secs, bad, notes):
    cs = cases(section(secs, "-- Port Input"))
    for title, types in INPUT_TYPES.items():
        hit = [c for c in cs if c[0].startswith(title)]
        if len(hit) != 1:
            bad.append(f"Inputs '{title}': {len(hit)} found")
            continue
        got, shows, drives = input_events(hit[0][1])
        if got != types:
            bad.append(f"Inputs '{title}': port types '{got}', expected '{types}'")
        rules = input_rules(title, shows, drives)
        for what, ok in rules:
            if not ok:
                bad.append(f"Inputs '{title}': {what}: not so")
        if got == types and rules and all(ok for _, ok in rules):
            notes.append(f"Inputs: {title}: types and {len(rules)} readings as expected")


def main():
    p = argparse.ArgumentParser(description="extra_tests.sh log checker")
    p.add_argument("log")
    p.add_argument("--ref")
    p.add_argument("--ar-tape", action="store_true")
    a = p.parse_args()
    bad, notes = check(a)
    print(f"extra_tests_check {a.log}")
    for n in notes:
        print("  note: " + n)
    for b in bad:
        print("  FAIL: " + b)
    print("EXTRA_TESTS " + ("pass" if not bad else f"FAIL ({len(bad)} finding(s))"))
    sys.exit(0 if not bad else 1)


if __name__ == "__main__":
    main()
