#!/usr/bin/env python3
"""Save-state probe (step 0 of docs SAVESTATE_SCOPE.md): thread a serial scan
chain through every clocked always block of the listed modules.

Mechanical transformation, per module that holds state (directly, or through
an instance of another chained module):

  * four ports at the head of the ANSI port list:
        input logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so
  * chain nodes ss_c0 .. ss_cN (wires); ss_c0 = ss_si, ss_so = ss_cN.
  * every `always @(posedge clk)` / `always_ff @(posedge clk)` statement S whose
    non-blocking left-hand sides are L = {l1, l2, ...} (base names, in order of
    first assignment) becomes

        begin
            if (ss_en)        {l1, l2, ...} <= {ss_cK, l1, l2, ...} >> 1;
            else if (!ss_frz) S
        end
        assign ss_cK+1 = {l1, l2, ...};      // implicit truncation: the LSB

    i.e. while ss_en is high the block's flops are one shift register (data
    enters at the MSB of l1, leaves at the LSB of the last name), while ss_frz
    is high (and ss_en low) every flop holds, otherwise the block is as before.
  * every instance of a chained module gets
        .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_cK), .ss_so(ss_cK+1),
    so instances and blocks are chained in source order.

A full rotation (ss_so fed back to ss_si for exactly N clocks, N = the sum of
$bits of every block's L) leaves every flop as it was.

Names in EXCLUDE (module -> set of base names) stay out of the chain: they
are frozen with the rest (they sit inside S) but not shifted.

Usage: scan_insert.py SRC_RTL DST_RTL [--report FILE]
SRC_RTL is a pristine copy of src/fpga/mister/rtl (e.g. `git show` of the
base); DST_RTL is written in place. Prints the chain map (module, block,
names) on stdout.
"""
import argparse
import os
import re
import sys

FILES = [
    "TIA.sv",
    "RIOT/M6532.sv",
    "Maria/maria.sv",
    "6502/mos6502_ctl.sv",
    "6502/mos6502_dp.sv",
    "6502/mos6502.sv",
    "6502/sally.sv",
    "top.sv",
]
# Modules that are not machine state: left out of the chain entirely (and not
# given ports). Atari7800 instantiates them; they keep running while frozen.
SKIP_MODULES = set()
# Base names left out of the chain per module (constant registers, etc).
EXCLUDE = {}
# The hold rule's hand-written part (SAVESTATE_SCOPE.md 3.6): what the chained
# machine drives into logic that is not chained must not act while main is
# frozen or shifting, or the shift's arbitrary bus patterns reach it. Text
# replacements in the pristine file (exactly one match each), applied before
# the chain is inserted; ss_en and ss_frz are the module's new ports.
HOLD = {
    "RIOT/M6532.sv": [
        # the RIOT RAM's CPU write port (the M10K is not chained)
        ("wire       ram_cpu_wr = res_n && ce && (CS1 & ~CS2_n) && ~RS_n && ~RW_n;",
         "wire       ram_cpu_wr = res_n && ce && (CS1 & ~CS2_n) && ~RS_n && ~RW_n && !(ss_en || ss_frz);  // ssprobe hold"),
        # its power-up walk port: ram_init is main's effective_reset, which a
        # shifting reset_hold raises
        ("\t.wren_b_i  (ram_init),", "\t.wren_b_i  (ram_init && !(ss_en || ss_frz)),  // ssprobe hold"),
    ],
    "top.sv": [
        # cart2600 (every mapper, not chained in the probe) sees no bus cycle
        ("\t\t.ce             (cart_ce_2600),\n\t\t.phi1           (pclk1),",
         "\t\t.ce             (cart_ce_2600 && !(ss_en || ss_frz)),   // ssprobe hold\n\t\t.phi1           (pclk1 && !(ss_en || ss_frz)),"),
        ("\t\t.phi2           (mapper_phi2),",
         "\t\t.phi2           (mapper_phi2 && !(ss_en || ss_frz)),"),
        ("\t\t.reset          (effective_reset),\n\t\t.clk            (clk_sys),",
         "\t\t.reset          (effective_reset && !(ss_en || ss_frz)),   // ssprobe hold\n\t\t.clk            (clk_sys),"),
        # DARIA's front end in the wrapper snoops the same bus
        ("\tassign daria_access_o = mapper_phi2 && tia_en;\n\tassign daria_reset_o  = effective_reset;",
         "\tassign daria_access_o = mapper_phi2 && tia_en && !(ss_en || ss_frz);   // ssprobe hold\n"
         "\tassign daria_reset_o  = effective_reset && !(ss_en || ss_frz);"),
    ],
}

KW_TYPES = r"(?:logic|reg|bit|wire|int|integer|byte|shortint|longint|clock_t|ctl_t|dec_t|\w+_t)"


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
        elif c == "<" and m[i + 1] == "=" and depth == 0:
            # walk back over the LHS
            j = i - 1
            while m[j].isspace():
                j -= 1
            if m[j] == "}":
                # concatenation LHS
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
                # strip [..] selects and .field
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
                        continue  # w was a field; keep walking to the base
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


def unpacked(m, mod, name):
    """True when `name` is declared with an unpacked dimension in the module."""
    seg = m[mod["start"]:mod["end"]]
    return re.search(r"\b(?:logic|reg|bit|wire|" + KW_TYPES + r")\b[^;=()]*?\b" + re.escape(name) + r"\s*\[", seg) is not None


def sel_key(name):
    """Sort key for bit selects: numeric indices, MSB first when reversed."""
    return [int(x) if x.isdigit() else x for x in re.split(r"[\[\]]+", name)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--exclude", help="file of 'module name' lines left out of the chain")
    ap.add_argument("--keep", help="Quartus post-map register names (one per line): chain only these bits")
    args = ap.parse_args()
    keep = None
    if args.keep:
        keep = {}
        for line in open(args.keep):
            line = line.strip()
            if "Atari7800:main|" not in line or "altsyncram" in line:
                continue
            segs = line.split("Atari7800:main|", 1)[1].split("|")
            mod = segs[-2].split(":")[0] if len(segs) > 1 else "Atari7800"
            keep.setdefault(mod, set()).add(segs[-1])
    if args.exclude:
        for line in open(args.exclude):
            line = line.split("#")[0].split()
            if len(line) == 2:
                EXCLUDE.setdefault(line[0], set()).add(line[1])

    texts = {f: open(os.path.join(args.src, f)).read() for f in FILES}
    for f, reps in HOLD.items():
        for a, b in reps:
            assert texts[f].count(a) == 1, (f, a)
            texts[f] = texts[f].replace(a, b)
    used = set()
    info = {}  # module -> dict(file, blocks, insts)
    for f, t in texts.items():
        m, mods = modules_of(t)
        for mod in mods:
            blocks = []
            for ab in re.finditer(r"\balways(?:_ff)?\s*@\s*\(\s*posedge\s+(\w+)\s*\)", m[mod["body"]:mod["end"]]):
                a = mod["body"] + ab.end()
                b = parse_stmt(m, a)
                names = lhs_names(m, a, b)
                bad = [n for n in names if unpacked(m, mod, n)]
                assert keep is not None or not bad, (mod["name"], "unpacked LHS", bad)
                ex = EXCLUDE.get(mod["name"], set())
                kept, dropped = [], []
                for n in names:
                    if n in ex:
                        dropped.append(n)
                        continue
                    if keep is None:
                        kept.append(n)
                        continue
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
                blocks.append(dict(a=a, b=b, names=kept, excluded=dropped, clk=ab.group(1)))
            info[mod["name"]] = dict(file=f, mod=mod, blocks=blocks, mask=m)
    # instances (after every module is known)
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
            insts.append(dict(mod=im.group(1), inst=iw, popen=j))
        d["insts"] = insts
    # which modules carry state
    stateful = set(n for n, d in info.items() if any(b["names"] for b in d["blocks"]))
    changed = True
    while changed:
        changed = False
        for n, d in info.items():
            if n not in stateful and any(x["mod"] in stateful for x in d["insts"]):
                stateful.add(n)
                changed = True
    stateful -= SKIP_MODULES

    # edits per file: list of (pos, kind, payload); applied from the end
    edits = {f: [] for f in FILES}
    report = []
    for name, d in info.items():
        if name not in stateful:
            continue
        f, mod, m = d["file"], d["mod"], d["mask"]
        items = [("blk", b["a"], b) for b in d["blocks"] if b["names"]]
        items += [("inst", x["popen"], x) for x in d["insts"] if x["mod"] in stateful]
        items.sort(key=lambda x: x[1])
        n = len(items)
        edits[f].append((mod["popen"] + 1, 0,
                         "\n\tinput logic ss_en, input logic ss_frz, input logic ss_si, output logic ss_so,"))
        nodes = ", ".join("ss_c%d" % k for k in range(n + 1))
        edits[f].append((mod["body"], 0,
                         "\n\t// save-state probe: scan chain (tools/ssprobe/scan_insert.py)\n"
                         "\twire %s;\n\tassign ss_c0 = ss_si;\n\tassign ss_so = ss_c%d;\n" % (nodes, n)))
        for k, (kind, pos, x) in enumerate(items):
            if kind == "blk":
                L = ", ".join(x["names"])
                body = d["mask"]  # unused
                edits[f].append((x["a"], 1, (x["b"], k, L)))
                report.append("%s\tblock@%d\t%s\t%s%s" % (
                    name, texts[f].count("\n", 0, x["a"]) + 1, x["clk"], L,
                    ("\tnot chained: " + ",".join(x["excluded"])) if x["excluded"] else ""))
            else:
                if m[skip_ws(m, x["popen"] + 1)] == ".":
                    conn = " .ss_en(ss_en), .ss_frz(ss_frz), .ss_si(ss_c%d), .ss_so(ss_c%d)," % (k, k + 1)
                else:   # positional: the four ports head the module's list
                    conn = "ss_en, ss_frz, ss_c%d, ss_c%d, " % (k, k + 1)
                edits[f].append((x["popen"] + 1, 0, conn))
                report.append("%s\tinst\t%s %s" % (name, x["mod"], x["inst"]))
    for f in FILES:
        t = texts[f]
        es = sorted(edits[f], key=lambda e: e[0], reverse=True)
        for pos, kind, pay in es:
            if kind == 0:
                t = t[:pos] + pay + t[pos:]
            else:
                b, k, L = pay
                stmt = t[pos:b]
                new = (" begin\n\t\tif (ss_en) {%s} <= {ss_c%d, %s} >> 1;\n"
                       "\t\telse if (!ss_frz)%s\n\tend\n\tassign ss_c%d = {%s};" % (L, k, L, stmt, k + 1, L))
                t = t[:pos] + new + t[b:]
        os.makedirs(os.path.dirname(os.path.join(args.dst, f)) or ".", exist_ok=True)
        open(os.path.join(args.dst, f), "w").write(t)
    if keep is not None:
        for mod, ks in sorted(keep.items()):
            if mod not in info:
                continue
            for k in sorted(ks):
                if (mod, k) not in used:
                    print("# UNMATCHED kept register: %s %s" % (mod, k))
    print("# chain map: module, item, clock, names (source order)")
    for r in report:
        print(r)
    print("# stateful modules:", " ".join(sorted(stateful)))


if __name__ == "__main__":
    main()
