#!/usr/bin/env python3
"""Save states (docs/SAVESTATE.md 2): thread the serial scan chain through
every clocked always block of the vendored machine modules.

Started as the probe's tool (SAVESTATE_SCOPE.md step 0, branch ss-probe);
this is the feature's. Mechanical transformation, per module that holds
state (directly, or through an instance of another chained module):

  * four ports at the head of the ANSI port list:
        input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so
  * chain nodes ss_c0 .. ss_cN (wires); ss_c0 = ss_si, ss_so = ss_cN.
  * every `always @(posedge clk)` / `always_ff @(posedge clk)` statement S whose
    chained non-blocking left-hand sides are L = {l1, l2, ...} (in order of
    first assignment) becomes

        begin
            if (ss_en)        {l1, l2, ...} <= {ss_cK, l1, l2, ...} >> 1;
            else if (!ss_frz) S
        end
        assign ss_cK+1 = {l1, l2, ...};      // implicit truncation: the LSB

    while ss_en is high the block's chained flops are one shift register (in
    at the MSB of l1, out at the LSB of the last name); while ss_en or ss_frz
    is high every flop of the block holds (chained or not); otherwise the
    block is as before. A block with no chained name still gets the hold:
        if (!(ss_en || ss_frz)) S
  * every instance of a chained module gets
        .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_cK), .ss_so(ss_cK+1),
    so instances and blocks are chained in source order.
  * an item inside `ifdef / `ifndef / `else / `elsif regions gets a pass
    (assign ss_cK+1 = ss_cK) in every branch where it is compiled out.
  * declarations at the head of a block's outer begin (block-local regs,
    lightgun.sv) are moved in front of the always, so the chain can name
    them.

Which flops are chained (--keep, --removed): exactly the ones Quartus keeps
in the base build (its post-map register names, tools/savestate/keep.txt),
plus every register Quartus merged into one it keeps (map.rpt's "Registers
Removed During Synthesis", "Merged with ..."): once chained, a merged copy
no longer is one, and a load must give it the saved value too. Registers
Quartus removed as constant or without fanout stay out: they never change,
or nothing reads them. A full rotation (ss_so to ss_si for exactly N clocks,
N the sum of $bits of every block's L) leaves every flop as it was.

The hold rule's hand-written part (SAVESTATE.md 2.3) is HOLD below: text
replacements in the pristine files, applied before the chain is inserted.

Usage: scan_insert.py SRC DST --keep KEEP [--removed MAP_RPT]
SRC is a pristine copy of src/fpga (git show of the base, apply.sh);
DST is written in place (the same relative paths). Prints the chain map on
stdout.
SPDX-License-Identifier: MIT
"""
import argparse
import os
import re
import sys

# The files transformed, relative to src/fpga, in no particular order.
FILES = [
    "mister/rtl/TIA.sv",
    "mister/rtl/RIOT/M6532.sv",
    "mister/rtl/Maria/maria.sv",
    "mister/rtl/6502/mos6502_ctl.sv",
    "mister/rtl/6502/mos6502_dp.sv",
    "mister/rtl/6502/mos6502.sv",
    "mister/rtl/6502/sally.sv",
    "mister/rtl/top.sv",
    "mister/rtl/cart2600.sv",
    "mister/rtl/banks2600.sv",
    "mister/rtl/mapper_fa2.sv",
    "mister/rtl/lightgun.sv",
    "mister/rtl/EEPROM_24LC256.sv",
    # the picture's last stage (its sync goes to the Pocket): chained so the
    # picture after a resume or a load is exactly the machine's
    "mister/rtl/video_mux.sv",
]
# The register path below which the keep list's names are taken.
ROOT = "atari2600_pocket:atari|"
# Modules that are not chained (no ports, no hold): the Supercharger is
# refused in v1 (cart2600's ce, phi1, phi2 and reset are held, so it sees no
# bus cycle while the machine is frozen or shifting, below).
SKIP_MODULES = {"mapper_AR"}
# The hold rule's hand-written part (SAVESTATE.md 2.3): what the chained
# machine drives into logic that is not chained must not act while it is
# frozen or shifting, or the shift's arbitrary bus patterns reach it. Text
# replacements in the pristine file (exactly one match each); ss_en and
# ss_frz are the module's new ports, ss_* below the wrapper's.
HOLD = {
    "mister/rtl/RIOT/M6532.sv": [
        # the RIOT RAM's CPU write port (the M10K is not chained)
        ("wire       ram_cpu_wr = res_n && ce && (CS1 & ~CS2_n) && ~RS_n && ~RW_n;",
         "wire       ram_cpu_wr = res_n && ce && (CS1 & ~CS2_n) && ~RS_n && ~RW_n && !(ss_en || ss_frz);  // ss hold"),
    ],
    "mister/rtl/top.sv": [
        # cart2600 (every mapper; the Supercharger is not chained) sees no bus cycle
        ("\t\t.ce             (cart_ce_2600),\n\t\t.phi1           (pclk1),",
         "\t\t.ce             (cart_ce_2600 && !(ss_en || ss_frz)),   // ss hold\n\t\t.phi1           (pclk1 && !(ss_en || ss_frz)),"),
        ("\t\t.phi2           (mapper_phi2),",
         "\t\t.phi2           (mapper_phi2 && !(ss_en || ss_frz)),"),
        ("\t\t.reset          (effective_reset),\n\t\t.clk            (clk_sys),",
         "\t\t.reset          (effective_reset && !(ss_en || ss_frz)),   // ss hold\n\t\t.clk            (clk_sys),"),
    ],
}
# The RAM ports (SAVESTATE.md 2.4): text replacements that give the
# controller a block RAM's port while the machine is frozen. They are applied
# with HOLD and are as mechanical; RAMS lists them, PORTS the ports they add
# (inserted after the four chain ports).
RAMS = {
    "mister/rtl/RIOT/M6532.sv": [
        # the RIOT RAM's port B (the power-up walk, whose read data was
        # unconnected): the state port's while ss_ram is high
        ("\t.addr_b_i  (init_addr),\n\t.wren_b_i  (ram_init),\n\t.wdata_b_i (ram_init_d),\n\t.q_b_o     ()",
         "\t.addr_b_i  (ss_ram ? ss_ra : init_addr),   // ss port\n"
         "\t.wren_b_i  (ss_ram ? ss_rwe : (ram_init && !(ss_en || ss_frz))),\n"
         "\t.wdata_b_i (ss_ram ? ss_rd : ram_init_d),\n\t.q_b_o     (ss_rq)"),
    ],
    "mister/rtl/mapper_fa2.sv": [
        # the work RAM's only port: the state port's while ss_ram is high
        ("\t\t.address (ram_addr),\n\t\t.data    (ram_wdata),\n\t\t.wren    (ram_wren),",
         "\t\t.address (ss_ram ? ss_ra : ram_addr),   // ss port\n\t\t.data    (ss_ram ? ss_rd : ram_wdata),\n"
         "\t\t.wren    (ss_ram ? ss_rwe : (ram_wren && !(ss_en || ss_frz))),"),
        ("\tspram #(\n\t\t.addr_width (8),", "\tassign ss_rq = ram_q;   // ss port\n\tspram #(\n\t\t.addr_width (8),"),
    ],
    "mister/rtl/cart2600.sv": [
        ("\t\t.nvram_dirty   (fa2_nvram_dirty_raw)",
         "\t\t.ss_ram(ss_ram), .ss_ra(ss_ra), .ss_rwe(ss_rwe), .ss_rd(ss_rd), .ss_rq(ss_rq),   // ss port\n"
         "\t\t.nvram_dirty   (fa2_nvram_dirty_raw)"),
    ],
    "mister/rtl/top.sv": [
        ("\t\t.ram_init_7800(~tia_mode),",
         "\t\t.ram_init_7800(~tia_mode),\n"
         "\t\t.ss_ram(ss_ram && !ss_rsel), .ss_ra(ss_ra[6:0]), .ss_rwe(ss_rwe), .ss_rd(ss_rd), .ss_rq(ss_rq_riot),   // ss port"),
        ("\t\t.pal            (PAL),",
         "\t\t.pal            (PAL),\n"
         "\t\t.ss_ram(ss_ram && ss_rsel), .ss_ra(ss_ra), .ss_rwe(ss_rwe), .ss_rd(ss_rd), .ss_rq(ss_rq_fa2),   // ss port"),
        ("\tM6532 riot_inst\n",
         "\t// save states: the RIOT RAM's and the FA2 work RAM's state port (ss_rsel 0 and 1)\n"
         "\twire [7:0] ss_rq_riot, ss_rq_fa2;\n\tassign ss_rq = ss_rsel ? ss_rq_fa2 : ss_rq_riot;\n\n\tM6532 riot_inst\n"),
    ],
}
# The ports RAMS needs, after the four chain ports of each module.
PORTS = {
    "M6532": "\n\tinput logic ss_ram, input logic [6:0] ss_ra, input logic ss_rwe, input logic [7:0] ss_rd, output logic [7:0] ss_rq,",
    "mapper_fa2": "\n\tinput logic ss_ram, input logic [7:0] ss_ra, input logic ss_rwe, input logic [7:0] ss_rd, output logic [7:0] ss_rq,",
    "cart2600": "\n\tinput logic ss_ram, input logic [7:0] ss_ra, input logic ss_rwe, input logic [7:0] ss_rd, output logic [7:0] ss_rq,",
    "Atari7800": "\n\tinput logic ss_ram, input logic ss_rsel, input logic [7:0] ss_ra, input logic ss_rwe, input logic [7:0] ss_rd,"
                 " output logic [7:0] ss_rq,",
}

KW_TYPES = r"(?:logic|reg|bit|wire|int|integer|byte|shortint|longint|clock_t|ctl_t|dec_t|\w+_t)"
DECL = re.compile(r"\s*(?:reg|logic|bit|integer|int)\b[^;]*;")


def mask(text):
    """Comments and strings replaced by spaces (newlines kept), same length."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            for k in range(i, min(j + 1, n)):
                out[k] = " "
            i = j + 1
        else:
            i += 1
    return "".join(out)


def skip_ws(m, i):
    while i < len(m) and m[i].isspace():
        i += 1
    return i


def named_conn(m, popen):
    """True when an instance's connection list (from its open paren) is by
    name: the first character that is not blank or on a preprocessor line."""
    i = popen + 1
    while True:
        i = skip_ws(m, i)
        if m[i] == "`":
            i = m.index("\n", i)
            continue
        return m[i] == "."


def match_group(m, i, o, c):
    """m[i] == o; return index after the matching c."""
    assert m[i] == o, (m[i:i + 40], o)
    d = 0
    while True:
        if m[i] == o:
            d += 1
        elif m[i] == c:
            d -= 1
            if d == 0:
                return i + 1
        i += 1


WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")


def word_at(m, i):
    w = WORD.match(m, i)
    return w.group(0) if w else None


def parse_stmt(m, i):
    """Return end index of the statement starting at (or after ws) i."""
    i = skip_ws(m, i)
    w = word_at(m, i)
    if w == "begin":
        d = 0
        j = i
        while True:
            w2 = WORD.search(m, j)
            assert w2, "unterminated begin"
            if w2.group(0) == "begin":
                d += 1
            elif w2.group(0) == "end":
                d -= 1
                if d == 0:
                    return w2.end()
            j = w2.end()
    if w in ("if",):
        j = skip_ws(m, i + 2)
        j = match_group(m, j, "(", ")")
        j = parse_stmt(m, j)
        k = skip_ws(m, j)
        if word_at(m, k) == "else":
            return parse_stmt(m, k + 4)
        return j
    if w in ("case", "unique", "priority", "casez", "casex"):
        j = m.find("endcase", i)
        return j + len("endcase")
    if w == "for":
        j = skip_ws(m, i + 3)
        j = match_group(m, j, "(", ")")
        return parse_stmt(m, j)
    j = m.find(";", i)
    return j + 1


def lhs_names(m, a, b):
    """Base names on the left of every non-blocking assignment in m[a:b]."""
    names = []
    depth = 0
    i = a
    while i < b:
        c = m[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif c == "<" and m[i + 1] == "=" and depth == 0 and m[i - 1] not in "<>=!":
            j = i - 1
            while m[j].isspace():
                j -= 1
            if m[j] == "}":
                d = 0
                k = j
                while True:
                    if m[k] == "}":
                        d += 1
                    elif m[k] == "{":
                        d -= 1
                        if d == 0:
                            break
                    k -= 1
                d2 = 0
                for q in range(k + 1, j):
                    if m[q] == "[":
                        d2 += 1
                    elif m[q] == "]":
                        d2 -= 1
                    elif d2 == 0 and (m[q].isalpha() or m[q] == "_") and not (m[q - 1].isalnum() or m[q - 1] in "_$."):
                        names.append(WORD.match(m, q).group(0))
            else:
                while True:
                    while m[j].isspace():
                        j -= 1
                    if m[j] == "]":
                        d = 0
                        while True:
                            if m[j] == "]":
                                d += 1
                            elif m[j] == "[":
                                d -= 1
                                if d == 0:
                                    break
                            j -= 1
                        j -= 1
                        continue
                    e = j + 1
                    while m[j].isalnum() or m[j] in "_$":
                        j -= 1
                    w = m[j + 1:e]
                    if m[j] == ".":
                        j -= 1
                        continue
                    names.append(w)
                    break
            i += 2
            continue
        i += 1
    seen = []
    for n in names:
        if n not in seen:
            seen.append(n)
    return seen


def find_header_end(m, start):
    """start at 'module'; return (ports_open_idx, body_start_idx, name)."""
    mm = re.compile(r"module\s+(\w+)\s*").match(m, start)
    name = mm.group(1)
    i = mm.end()
    i = skip_ws(m, i)
    while m.startswith("import", i):
        i = skip_ws(m, m.index(";", i) + 1)
    if m[i] == "#":
        i = skip_ws(m, i + 1)
        i = match_group(m, i, "(", ")")
        i = skip_ws(m, i)
    assert m[i] == "(", (name, m[i:i + 30])
    popen = i
    i = match_group(m, i, "(", ")")
    i = skip_ws(m, i)
    assert m[i] == ";", name
    return popen, i + 1, name


def modules_of(text):
    m = mask(text)
    mods = []
    for mo in re.finditer(r"\bmodule\b", m):
        s = mo.start()
        e = m.find("endmodule", s)
        popen, body, name = find_header_end(m, s)
        mods.append(dict(name=name, start=s, popen=popen, body=body, end=e))
    return m, mods


def conditions(m):
    """For every position: the preprocessor conditions it is under, as a
    list of (macro, defined) pairs that must all hold. A level keeps its
    heads (`ifdef X: (X, True); `ifndef X: (X, False); each `elsif Y:
    (Y, True)) and its branch: branch i needs heads 0..i-1 false and head i
    true; `else needs every head false. Returns a function of a position."""
    events = []
    levels = []      # [heads, branch index or -1 for else]

    def flat():
        out = []
        for heads, br in levels:
            n = len(heads) if br < 0 else br
            out += [(x, not w) for x, w in heads[:n]]
            if br >= 0:
                out.append(heads[br])
        return out
    for d in re.finditer(r"`(ifdef|ifndef|elsif|else|endif)\b[ \t]*(\w*)", m):
        kind, arg = d.group(1), d.group(2)
        if kind in ("ifdef", "ifndef"):
            levels.append([[(arg, kind == "ifdef")], 0])
        elif kind == "elsif":
            levels[-1][0].append((arg, True))
            levels[-1][1] = len(levels[-1][0]) - 1
        elif kind == "else":
            levels[-1][1] = -1
        else:
            levels.pop()
        events.append((d.start(), flat()))

    def at(pos):
        cur = []
        for p, st in events:
            if p > pos:
                break
            cur = st
        return cur
    return at


def pass_through(conds, k):
    """Verilog text that makes ss_c(k+1) = ss_ck wherever an item under
    conds (all must hold for it to be compiled) is compiled out."""
    out = []
    for i in range(len(conds)):
        lines = []
        for x, w in conds[:i]:
            lines.append("`%s %s" % ("ifdef" if w else "ifndef", x))
        x, w = conds[i]
        lines.append("`%s %s" % ("ifndef" if w else "ifdef", x))
        lines.append("\tassign ss_c%d = ss_c%d;   // the item above is compiled out" % (k + 1, k))
        lines += ["`endif"] * (i + 1)
        out.append("\n".join(lines))
    return "\n" + "\n".join(out) + "\n"


def unpacked(m, mod, name):
    seg = m[mod["start"]:mod["end"]]
    return re.search(r"\b(?:logic|reg|bit|wire|" + KW_TYPES + r")\b[^;=()]*?\b" + re.escape(name) + r"\s*\[", seg) is not None


def sel_key(name):
    return [int(x) if x.isdigit() else x for x in re.split(r"[\[\]]+", name)]


def expand_range(name):
    """error_code[1..7] -> error_code[1] .. error_code[7] (map.rpt's ranges)."""
    mo = re.search(r"\[(\d+)\.\.(\d+)\]", name)
    if not mo:
        return [name]
    a, b = int(mo.group(1)), int(mo.group(2))
    out = []
    for v in range(min(a, b), max(a, b) + 1):
        out += expand_range(name[:mo.start()] + "[%d]" % v + name[mo.end():])
    return out


def reg_key(path):
    """(module, name) of a register path below ROOT, or None."""
    if ROOT not in path or "altsyncram" in path or "altdpram" in path or "~" in path:
        return None
    segs = path.split(ROOT, 1)[1].split("|")
    mod = segs[-2].split(":")[0] if len(segs) > 1 else "atari2600_pocket"
    return mod, segs[-1]


def read_keep(keep_file):
    """keep.txt: 'module<TAB>register' lines (make_keep's output)."""
    keep = {}
    for line in open(keep_file):
        if line.startswith("#") or not line.strip():
            continue
        mod, name = line.rstrip("\n").split("\t")
        keep.setdefault(mod, set()).add(name)
    return keep


def load_keep(keep_file, removed_file):
    keep = {}
    for line in open(keep_file):
        k = reg_key(line.strip())
        if k:
            keep.setdefault(k[0], set()).add(k[1])
    merged = 0
    if removed_file:
        txt = open(removed_file, errors="replace").read()
        s = txt.find("; Registers Removed During Synthesis")
        e = txt.find("\n+-", txt.find("\n+-", txt.find("\n+-", s) + 1) + 1)
        for row in txt[s:].split("\n"):
            if row.startswith("+") and row.count("-") > 40 and merged and "Merged with" not in row:
                pass
            cells = [c.strip() for c in row.split(";")]
            if len(cells) < 3 or not cells[2].startswith("Merged with"):
                if row.startswith("; Total Number of Removed Registers"):
                    break
                continue
            for path in expand_range(cells[1]):
                k = reg_key(path)
                if k:
                    keep.setdefault(k[0], set()).add(k[1])
                    merged += 1
    return keep, merged


def hoist_decls(t, m, a):
    """If the block statement at a starts with `begin` (optionally named)
    followed by declarations, return (start, end) of those declarations."""
    i = skip_ws(m, a)
    if word_at(m, i) != "begin":
        return None
    j = i + len("begin")
    k = skip_ws(m, j)
    if m[k] == ":":
        k = skip_ws(m, k + 1)
        k = skip_ws(m, k + len(word_at(m, k)))
    s = k
    e = k
    while True:
        mo = DECL.match(m, e)
        if not mo:
            break
        e = mo.end()
    return (s, e) if e > s else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--keep", required=True, help="tools/savestate/keep.txt (from --make-keep)")
    ap.add_argument("--make-keep", nargs=2, metavar=("REGS", "MAP_RPT"),
                    help="write keep.txt from a quartus_map run's post-map register dump and map.rpt to --keep, then stop")
    args = ap.parse_args()
    if args.make_keep:
        keep, merged = load_keep(*args.make_keep)
        mods = set()
        for f in FILES:
            mods |= {mo["name"] for mo in modules_of(open(os.path.join(args.src, f)).read())[1]}
        with open(args.keep, "w") as o:
            o.write("# tools/savestate/scan_insert.py --make-keep: the registers Quartus keeps in the\n"
                    "# base build (post-map), and those it merged into them (%d), of the chained files' modules\n" % merged)
            for mod in sorted(keep):
                if mod in mods:
                    for k in sorted(keep[mod], key=sel_key):
                        o.write("%s\t%s\n" % (mod, k))
        return
    keep = read_keep(args.keep)
    merged = sum(1 for _ in open(args.keep)) - 2

    texts = {}
    for f in FILES:
        texts[f] = open(os.path.join(args.src, f)).read()
    for table in (HOLD, RAMS):
        for f, reps in table.items():
            for a, b in reps:
                assert texts[f].count(a) == 1, (f, a)
                texts[f] = texts[f].replace(a, b)
    used = set()
    info = {}
    for f in FILES:
        t = texts[f]
        m, mods = modules_of(t)
        cond_at = conditions(m)
        for mod in mods:
            if mod["name"] in SKIP_MODULES:
                continue
            blocks = []
            for ab in re.finditer(r"\balways(?:_ff)?\s*@\s*\(\s*posedge\s+(\w+)\s*\)", m[mod["body"]:mod["end"]]):
                a = mod["body"] + ab.end()
                b = parse_stmt(m, a)
                names = lhs_names(m, a, b)
                kept, dropped = [], []
                for n in names:
                    items = sorted((k for k in keep.get(mod["name"], ()) if re.match(re.escape(n) + r"($|\[|\.)", k)),
                                   key=sel_key, reverse=True)
                    if not items:
                        dropped.append(n)
                    elif any(re.match(re.escape(n) + r"\.[A-Z][A-Z0-9_]*$", k) for k in items) or items == [n]:
                        kept.append(n)          # an enum state (one-hot in the netlist) or a whole scalar
                    else:
                        kept.extend(items)
                    for k in items:
                        used.add((mod["name"], k))
                blocks.append(dict(start=mod["body"] + ab.start(), a=a, b=b, names=kept, excluded=dropped,
                                   clk=ab.group(1), conds=cond_at(a), decl=hoist_decls(t, m, a)))
            info[mod["name"]] = dict(file=f, mod=mod, blocks=blocks, mask=m, cond_at=cond_at)
    names_re = "|".join(sorted(info, key=len, reverse=True))
    for name, d in info.items():
        m, mod = d["mask"], d["mod"]
        insts = []
        for im in re.finditer(r"(?<![\w.$])(" + names_re + r")\b\s*(#\s*\()?", m[mod["body"]:mod["end"]]):
            i = mod["body"] + im.end()
            if im.group(2):
                i = match_group(m, i - 1, "(", ")")
            i = skip_ws(m, i)
            iw = word_at(m, i)
            if not iw:
                continue
            j = skip_ws(m, i + len(iw))
            if m[j] != "(":
                continue
            insts.append(dict(mod=im.group(1), inst=iw, popen=j, close=match_group(m, j, "(", ")"),
                              conds=d["cond_at"](j)))
        d["insts"] = insts
    stateful = set(n for n, d in info.items() if any(b["names"] for b in d["blocks"]))
    changed = True
    while changed:
        changed = False
        for n, d in info.items():
            if n not in stateful and any(x["mod"] in stateful for x in d["insts"]):
                stateful.add(n)
                changed = True

    edits = {f: [] for f in FILES}
    report = []
    for name, d in info.items():
        f, mod, m = d["file"], d["mod"], d["mask"]
        t = texts[f]
        # every clocked block of a chained file's module holds while frozen,
        # chained or not (a block of a module without chained flops too)
        if name not in stateful:
            if not d["blocks"]:
                continue
            edits[f].append((mod["popen"] + 1, 0, "\n\tinput logic ss_en, input logic ss_frz,"))
            for x in d["blocks"]:
                edits[f].append((x["a"], 2, x["b"]))
            report.append("%s\thold only (%d blocks)" % (name, len(d["blocks"])))
            d["hold_only"] = True
            continue
        items = [("blk", b["a"], b) for b in d["blocks"] if b["names"]]
        items += [("inst", x["popen"], x) for x in d["insts"] if x["mod"] in stateful]
        items.sort(key=lambda x: x[1])
        n = len(items)
        extra = PORTS.get(name, "")
        edits[f].append((mod["popen"] + 1, 0,
                         "\n\tinput logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so," + extra))
        nodes = ", ".join("ss_c%d" % k for k in range(n + 1))
        edits[f].append((mod["body"], 0,
                         "\n\t// save states: scan chain (tools/savestate/scan_insert.py)\n"
                         "\twire %s;\n\tassign ss_c0 = ss_si;\n\tassign ss_so = ss_c%d;\n" % (nodes, n)))
        for x in d["blocks"]:
            if not x["names"]:
                edits[f].append((x["a"], 2, x["b"]))
        for k, (kind, pos, x) in enumerate(items):
            line = t.count("\n", 0, pos) + 1
            cond = " [%s]" % " ".join(("" if w else "!") + c for c, w in x["conds"]) if x["conds"] else ""
            if kind == "blk":
                L = ", ".join(x["names"])
                if x["decl"]:
                    s, e = x["decl"]
                    edits[f].append((x["start"], 0, t[s:e].strip() + "   // (moved out of the block: chained)\n"))
                    edits[f].append((s, 3, e))
                edits[f].append((x["a"], 1, (x["b"], k, L)))
                after = x["b"]
                report.append("%s\tblock@%d\t%s\t%s%s%s" % (
                    name, line, x["clk"], L, cond,
                    ("\tnot chained: " + ",".join(x["excluded"])) if x["excluded"] else ""))
            else:
                if named_conn(m, x["popen"]):
                    conn = " .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c%d), .ss_so(ss_c%d)," % (k, k + 1)
                else:
                    conn = "ss_en, ss_frz, ss_c%d, ss_c%d, " % (k, k + 1)
                edits[f].append((x["popen"] + 1, 0, conn))
                after = m.index(";", x["close"]) + 1
                report.append("%s\tinst\t%s %s%s" % (name, x["mod"], x["inst"], cond))
            if x["conds"]:
                edits[f].append((after, 0, pass_through(x["conds"], k)))
    # hold-only modules' instances get the two hold ports
    for name, d in info.items():
        for x in d.get("insts", []):
            if info.get(x["mod"], {}).get("hold_only"):
                m = d["mask"]
                named = named_conn(m, x["popen"])
                edits[d["file"]].append((x["popen"] + 1, 0, " .ss_en(ss_en), .ss_frz(ss_frz)," if named else "ss_en, ss_frz, "))
    for f in FILES:
        t = texts[f]
        es = sorted(edits[f], key=lambda e: (e[0], -e[1]), reverse=True)
        for pos, kind, pay in es:
            if kind == 0:
                t = t[:pos] + pay + t[pos:]
            elif kind == 1:
                b, k, L = pay
                stmt = t[pos:b]
                new = (" begin\n\t\t/* verilator lint_off WIDTHTRUNC */\n"
                       "\t\tif (ss_en) {%s} <= {ss_c%d, %s} >> 1;\n"
                       "\t\t/* verilator lint_on WIDTHTRUNC */\n"
                       "\t\telse if (!ss_frz)%s\n\tend\n"
                       "\t/* verilator lint_off WIDTHTRUNC */\n"
                       "\tassign ss_c%d = {%s};   // the LSB\n"
                       "\t/* verilator lint_on WIDTHTRUNC */" % (L, k, L, stmt, k + 1, L))
                t = t[:pos] + new + t[b:]
            elif kind == 2:
                stmt = t[pos:pay]
                t = t[:pos] + "\n\t\tif (!(ss_en || ss_frz))  // ss hold\n" + stmt + t[pay:]
            elif kind == 3:   # blank, same length: positions stay
                t = t[:pos] + re.sub(r"[^\n]", " ", t[pos:pay]) + t[pay:]
        os.makedirs(os.path.dirname(os.path.join(args.dst, f)) or ".", exist_ok=True)
        open(os.path.join(args.dst, f), "w").write(t)
    for mod, ks in sorted(keep.items()):
        if mod not in info:
            continue
        for k in sorted(ks):
            if (mod, k) not in used:
                print("# UNMATCHED kept register: %s %s" % (mod, k))
    print("# chain map (tools/savestate/scan_insert.py): module, item, clock, names in")
    print("# source order [preprocessor conditions]; keep list %d registers" % merged)
    for r in report:
        print(r)
    print("# stateful modules:", " ".join(sorted(stateful)))


if __name__ == "__main__":
    main()
