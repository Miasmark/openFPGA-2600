#!/usr/bin/env python3
"""Check the APF package files (dist/) against each other and against core_top.v.

  apf_json_check.py [--root DIR] [--vectors FILE] [--plusargs FILE]

Checks (each prints a line; the last line is APF_JSON pass or APF_JSON FAIL):
- every JSON file in dist/ parses; the core files carry "APF_VER_1";
- core.json: names, version, url, the bitstream name that tools/package.sh writes;
- Platforms/2600.json and _images/2600.bin are the files of Spiritualized's
  2600 core 1.0.0 (byte for byte: the platform is shared with that core);
- no 7800 package file is left;
- interact.json: the Pocket's menu limits (16 entries, 20 with the reloadable
  data slots, 16 options a list, 23 characters a name), every address decoded
  by core_top.v, option values inside the item's mask, defaults among the
  options, the Mapper lists (each forcible bss_type once, names matching
  detect2600.sv's enum, BUS left out, not persisted), SaveKey Off/On;
- data.json: the slot order and files, ids and bridge addresses as core_top.v
  decodes them, and the save sizes core_top.v writes into the data table, by
  slot index;
- video.json: the two 2600 scaler modes, with the heights run_sim_check.py
  expects of the TIA's NTSC and PAL frames, and the display-mode list.

--vectors writes the stimulus for sim/tb_core_top.sv: the menu writes, and
after each the value every wrapper setting port must hold (a model of
core_top.v's decode as the menu items mean it, not a copy of it).
--plusargs writes the bench's other expectations (slot ids, addresses, data
table entries, scaler slot indices) as Verilator plusargs.
"""
import argparse
import hashlib
import json
import os
import re
import sys

SPIRIT_PLATFORM_MD5 = "8e6c9cee02fa7569100e5fee57c0d4c8"   # Spiritualized 2600 1.0.0, Platforms/2600.json
SPIRIT_IMAGE_MD5 = "151911282233b7f35a2ce650400b5a1c"      # same release, Platforms/_images/2600.bin
SPIRIT_IMAGE_SIZE = 171930

# The Mapper items' option names and the bss_type each must force
MAPPER_NAMES = {
    "2K": "BANK2K", "F8 (8K)": "BANKF8", "F6 (16K)": "BANKF6", "F4 (32K)": "BANKF4",
    "F0 (64K)": "BANKF0", "FA (CBS RAM+)": "BANKFA", "FE (Activision)": "BANKFE",
    "E0 (Parker Bros.)": "BANKE0", "E7 (M Network)": "BANKE7", "3F (Tigervision)": "BANK3F",
    "3E": "BANK3E", "CV (Commavid)": "BANKCV", "UA (UA Ltd.)": "BANKUA", "EF": "BANKEF",
    "SB": "BANKSB", "AR (Supercharger)": "BANKAR", "DPC (Pitfall II)": "BANKP2",
    "DPC+": "BANKDPCP", "CDF / CDFJ / CDFJ+": "BANKCDF", "FA2": "BANKFA2",
    "WD (Pink Panther)": "BANKWD", "JANE (Tarzan)": "BANKJANE", "CTY (Chetiry)": "BANKCTY",
    "0840": "BANK0840", "FC (Power Play)": "BANKFC", "DF / BF": "BANKDF",
    "Multicart 2K": "BANKMC2K", "Multicart 4K": "BANKMC4K", "Multicart 8K": "BANKMC8K",
    "32-in-1": "BANK32",
}
# Port Input names and the wrapper's port_input values (atari2600_pocket.sv,
# menu_port_type: 0 is the header's type, which is a joystick for every image)
PORT_NAMES = {"Joystick": 0, "Paddles": 2, "Driving": 3, "Light Gun": 4,
              "Dual Stick": 5, "Booster Grip": 6}

# Wrapper setting ports the bench reads (tb_core_top.sv, PORTS), in order
PORTS = ["bs_override", "diff_left_b", "diff_right_b", "bw_setting", "savekey_setting",
         "swap_joysticks", "region_setting", "palette_temp", "port1_input", "port2_input",
         "turbo", "atarivox_setting", "stereo_tia", "stmix", "decomb", "flicker_blend",
         "menu_reset"]

fails = []


def check(ok, what):
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok:
        fails.append(what)
    return ok


def load(path):
    with open(path, "rb") as f:
        raw = f.read()
    try:
        return json.loads(raw.decode("utf-8")), raw
    except Exception as e:  # noqa: BLE001
        check(False, f"{path}: does not parse ({e})")
        return None, raw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    ap.add_argument("--vectors")
    ap.add_argument("--plusargs")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    dist = os.path.join(root, "dist")
    core_dir = os.path.join(dist, "Cores", "Miasmark.2600")
    core_top = open(os.path.join(root, "src/fpga/core/core_top.v")).read()
    detect = open(os.path.join(root, "src/fpga/mister/rtl/detect2600.sv")).read()
    package = open(os.path.join(root, "tools/package.sh")).read()

    print("-- JSON files")
    js = {}
    for d, _, files in os.walk(dist):
        for f in sorted(files):
            if f.endswith(".json"):
                p = os.path.join(d, f)
                obj, raw = load(p)
                rel = os.path.relpath(p, dist)
                check(obj is not None, f"{rel} parses")
                js[rel] = (obj, raw)
    for n in ("core", "data", "input", "interact", "video", "audio", "variants"):
        rel = f"Cores/Miasmark.2600/{n}.json"
        obj = js.get(rel, (None,))[0]
        check(obj is not None and obj.get(n, {}).get("magic") == "APF_VER_1", f"{rel}: {n}.magic APF_VER_1")

    print("-- core.json")
    core = js["Cores/Miasmark.2600/core.json"][0]["core"]
    md = core["metadata"]
    check(md["platform_ids"] == ["2600"], "platform_ids [\"2600\"]")
    check(md["shortname"] == "2600", "shortname 2600")
    check(md["author"] == "Miasmark", "author Miasmark")
    check(md["version"] == "1.0.1", "version 1.0.1")
    check(md["url"] == "https://github.com/Miasmark/openFPGA-2600", "url")
    check(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", md["date_release"])), "date_release is a date")
    check("Kitrinx" in md["description"] and "openFPGA-7800" in md["description"],
          "description credits the MiSTer core (Kitrinx) and openFPGA-7800")
    check(core["framework"]["sleep_supported"] is False, "sleep_supported false")
    check(core["framework"]["dock"]["supported"] is True, "dock supported")
    rbf = core["cores"][0]["filename"]
    check(rbf == "atari2600.rbf_r", "bitstream atari2600.rbf_r")
    check(f'"$CORE/{rbf}"' in package and "Miasmark.2600" in package,
          "tools/package.sh writes that bitstream into Cores/Miasmark.2600")

    print("-- platform")
    praw = js.get("Platforms/2600.json", (None, b""))[1]
    check(hashlib.md5(praw).hexdigest() == SPIRIT_PLATFORM_MD5,
          "Platforms/2600.json is byte for byte Spiritualized 2600 1.0.0's")
    pl = js["Platforms/2600.json"][0]["platform"]
    check(pl == {"category": "Console", "name": "Atari VCS (2600)", "year": 1977, "manufacturer": "Atari, Inc."},
          "Platforms/2600.json fields")
    img = os.path.join(dist, "Platforms/_images/2600.bin")
    ib = open(img, "rb").read() if os.path.exists(img) else b""
    check(len(ib) == SPIRIT_IMAGE_SIZE and hashlib.md5(ib).hexdigest() == SPIRIT_IMAGE_MD5,
          "Platforms/_images/2600.bin is Spiritualized 2600 1.0.0's")
    for gone in ("Platforms/7800.json", "Platforms/_images/7800.bin", "Cores/Miasmark.7800", "Assets/7800"):
        check(not os.path.exists(os.path.join(dist, gone)), f"no dist/{gone}")
    check(os.path.exists(os.path.join(dist, "Assets/2600/common/.keep")), "dist/Assets/2600/common/.keep")
    check(os.path.exists(os.path.join(core_dir, "icon.bin")), "icon.bin")

    print("-- data.json")
    slots = js["Cores/Miasmark.2600/data.json"][0]["data"]["data_slots"]
    names = [s["name"] for s in slots]
    check(names == ["Cartridge", "Supercharger BIOS", "SaveKey", "FA2 flash"], f"slot order {names}")
    ids = [int(s["id"], 16) for s in slots]
    check(len(set(ids)) == len(ids), "slot ids unique")
    cart, arfw, sk, fa2 = slots
    check(cart["extensions"] == ["a26", "bin"] and cart.get("required") is True, "cartridge: a26/bin, required")
    check(int(cart["parameters"], 16) & 1 == 1, "cartridge slot user-reloadable")
    check(arfw.get("filename") == "supercharger.bin" and arfw.get("required") is False
          and int(arfw["parameters"], 16) & 2 == 0,
          "Supercharger BIOS: supercharger.bin, optional, not core-specific (/Assets/2600/common/)")
    for s, fn, size in ((sk, "savekey.sav", 0x8000), (fa2, "fa2.sav", 0x100)):
        check(s.get("filename") == fn and s.get("nonvolatile") is True and int(s["size_maximum"], 16) == size
              and s.get("required") is False and int(s["parameters"], 16) & 2 == 0,
              f"{s['name']}: {fn}, nonvolatile, {size} bytes, not core-specific")
    reload = sum(1 for s in slots if int(s["parameters"], 16) & 1)
    m = dict(re.findall(r"localparam \[15:0\] (SLOT_\w+)\s*=\s*16'h([0-9A-Fa-f]+);", core_top))
    check(int(m.get("SLOT_CART", "-1"), 16) == ids[0], f"core_top SLOT_CART = data.json slot 0 id {cart['id']}")
    check(int(m.get("SLOT_ARFW", "-1"), 16) == ids[1], f"core_top SLOT_ARFW = data.json slot 1 id {arfw['id']}")
    sk_hi = re.search(r"wire sk_sel = bridge_addr\[31:24\] == 8'h([0-9A-Fa-f]+);", core_top)
    fa_hi = re.search(r"wire fa2_sel = bridge_addr\[31:24\] == 8'h([0-9A-Fa-f]+);", core_top)
    check(sk_hi and int(sk["address"], 16) >> 24 == int(sk_hi.group(1), 16), f"SaveKey address {sk['address']} = core_top sk_sel")
    check(fa_hi and int(fa2["address"], 16) >> 24 == int(fa_hi.group(1), 16), f"FA2 address {fa2['address']} = core_top fa2_sel")
    loader_mask = re.search(r"\.ADDRESS_MASK_UPPER_4\s*\(\s*4'h([0-9A-Fa-f])\s*\)", core_top)
    for s in (cart, arfw):
        check(loader_mask and int(s["address"], 16) >> 28 == int(loader_mask.group(1), 16),
              f"{s['name']} address {s['address']} reaches the data loader (ADDRESS_MASK_UPPER_4)")
    dt = re.findall(r"datatable_addr <= 10'd(\d+) \* 2 \+ 1;[^\n]*\n\s*datatable_data <= 32'd(\d+);", core_top)
    dt = {int(i): int(v) for i, v in dt}
    want = {slots.index(sk): int(sk["size_maximum"], 16), slots.index(fa2): int(fa2["size_maximum"], 16)}
    check(dt == want, f"core_top data table writes {dt} = data.json save slots by index {want}")

    print("-- interact.json")
    var = js["Cores/Miasmark.2600/interact.json"][0]["interact"]["variables"]
    check(len(var) <= 16, f"{len(var)} entries (limit 16)")
    check(len(var) + reload <= 20, f"{len(var)} entries + {reload} reloadable slots (limit 20)")
    check(len({v['id'] for v in var}) == len(var), "entry ids unique")
    blk = core_top.split("bridge_addr[31:24] == 8'h10", 1)[1].split("endcase", 1)[0]
    decoded = {int(x, 16) for x in re.findall(r"12'h([0-9A-Fa-f]{3}):", blk)}
    by_addr = {}
    for v in var:
        addr = int(v["address"], 16)
        by_addr[v["name"]] = v
        check(addr >> 24 == 0x10 and (addr & 0xFFF) in decoded and (addr & 0x00FFF000) == 0,
              f"{v['name']}: {v['address']} decoded by core_top")
        check(len(v["name"]) <= 23, f"{v['name']}: name <= 23 characters")
        if v["type"] == "list":
            opts = v["options"]
            mask = int(v["mask"], 16)
            check(len(opts) <= 16, f"{v['name']}: {len(opts)} options (limit 16)")
            check(all(len(o["name"]) <= 23 for o in opts), f"{v['name']}: option names <= 23 characters")
            check(all(o["value"] & mask == 0 for o in opts), f"{v['name']}: option values inside mask {v['mask']}")
            check(len({o["value"] for o in opts}) == len(opts), f"{v['name']}: option values unique")
            check(v["defaultval"] in [o["value"] for o in opts], f"{v['name']}: default among the options")
    enum = re.search(r"typedef enum bit\[5:0\] \{(.*?)\} bss_type", detect, re.S).group(1)
    enum = [t.strip() for t in enum.replace("\n", " ").split(",") if t.strip()]
    seen = []
    for nm in ("Mapper", "Mapper (more)"):
        v = by_addr[nm]
        check(v.get("persist") is False and v["defaultval"] == 0, f"{nm}: not persisted, default Auto")
        opts = v["options"]
        check(opts[0] == {"value": 0, "name": "Auto"}, f"{nm}: first option Auto = 0")
        for o in opts[1:]:
            tok = MAPPER_NAMES.get(o["name"])
            check(tok is not None and enum.index(tok) == o["value"],
                  f"{nm}: {o['name']} = {o['value']} = {tok}")
            seen.append(o["value"])
    forcible = set(range(1, 32)) - {enum.index("BANKBUS")}
    check(sorted(seen) == sorted(forcible), "the two Mapper lists force each of bss_type 1-31 but BUS exactly once")
    skv = by_addr["SaveKey (port 2)"]
    check([(o["value"], o["name"]) for o in skv["options"]] == [(0, "Off"), (1, "On")] and skv["defaultval"] == 0,
          "SaveKey: Off/On, default Off (no Auto)")
    for nm in ("Port 1 Input", "Port 2 Input"):
        v = by_addr[nm]
        check(all(PORT_NAMES.get(o["name"]) == o["value"] for o in v["options"]) and v["options"][0]["name"] == "Joystick"
              and v["defaultval"] == 0, f"{nm}: Joystick (0, default) and the wrapper's port types by name")
    for nm in ("Left Difficulty", "Right Difficulty"):
        check([(o["value"], o["name"]) for o in by_addr[nm]["options"]] == [(0, "A"), (1, "B")], f"{nm}: A = 0, B = 1 (diff_*_b)")
    check([(o["value"], o["name"]) for o in by_addr["TV Type"]["options"]] == [(0, "Colour"), (1, "B&W")], "TV Type: Colour 0, B&W 1")
    check([(o["value"], o["name"]) for o in by_addr["Region"]["options"]] == [(0, "Auto"), (1, "NTSC"), (2, "PAL")],
          "Region: Auto 0, NTSC 1, PAL 2")

    print("-- video.json")
    vj = js["Cores/Miasmark.2600/video.json"][0]["video"]
    modes = [(s["width"], s["height"], s["aspect_w"], s["aspect_h"]) for s in vj["scaler_modes"]]
    check(modes == [(160, 240, 56, 45), (160, 288, 83, 66)], f"scaler modes {modes}")
    check([d["id"] for d in vj.get("display_modes", [])] == ["0x10", "0x20", "0x30", "0x40"],
          "display_modes 0x10-0x40, as the 7800 core's (plan O11)")
    rsc = open(os.path.join(root, "sim/check/run_sim_check.py")).read()
    ntsc_l = re.search(r"active lines (\d+), active pixels/line (160), video PAL 0", rsc)
    pal_l = re.search(r"active lines (\d+), active pixels/line (160), video PAL 1", rsc)
    ntsc_slot = [i for i, m_ in enumerate(modes) if ntsc_l and (m_[1], m_[0]) == (int(ntsc_l.group(1)), int(ntsc_l.group(2)))]
    pal_slot = [i for i, m_ in enumerate(modes) if pal_l and (m_[1], m_[0]) == (int(pal_l.group(1)), int(pal_l.group(2)))]
    check(len(ntsc_slot) == 1 and len(pal_slot) == 1,
          f"run_sim_check.py's 2600 frames (NTSC {ntsc_l and ntsc_l.groups()}, PAL {pal_l and pal_l.groups()}) "
          f"each have one scaler mode: NTSC slot {ntsc_slot}, PAL slot {pal_slot}")

    print("-- input.json, info.txt")
    keys = {"pad_btn_a", "pad_btn_b", "pad_btn_x", "pad_btn_y", "pad_trig_l", "pad_trig_r", "pad_btn_start", "pad_btn_select"}
    mp = js["Cores/Miasmark.2600/input.json"][0]["input"]["controllers"][0]["mappings"]
    check(all(x["key"] in keys and x["name"] for x in mp) and len({x["id"] for x in mp}) == len(mp),
          "input.json: known keys, unique ids, every button named")
    info = open(os.path.join(core_dir, "info.txt")).read()
    check(all(w in info for w in ("savekey.sav", "fa2.sav", "supercharger.bin", "/Assets/2600/common/", "openFPGA-2600")),
          "info.txt names the files, the asset folder and the source")

    if a.vectors:
        write_vectors(a.vectors, var, by_addr)
    if a.plusargs:
        with open(a.plusargs, "w") as f:
            f.write(" ".join([
                f"+cart_id={ids[0]:x}", f"+cart_addr={int(cart['address'], 16):x}",
                f"+arfw_id={ids[1]:x}", f"+arfw_addr={int(arfw['address'], 16):x}",
                f"+sk_addr={int(sk['address'], 16):x}", f"+fa2_addr={int(fa2['address'], 16):x}",
                f"+sk_idx={slots.index(sk)}", f"+sk_size={int(sk['size_maximum'], 16)}",
                f"+fa2_idx={slots.index(fa2)}", f"+fa2_size={int(fa2['size_maximum'], 16)}",
                f"+ntsc_slot={ntsc_slot[0] if ntsc_slot else 7}", f"+pal_slot={pal_slot[0] if pal_slot else 7}",
            ]) + "\n")

    print("APF_JSON " + ("pass" if not fails else f"FAIL ({len(fails)})"))
    return 0 if not fails else 1


def write_vectors(path, var, by_addr):
    """Menu writes and the wrapper port values each must give.

    The model is what the items mean (names checked above), not core_top's
    case statement: Left/Right Difficulty and TV Type and SaveKey are one bit;
    Audio's value is {stereo, mix[1:0]}, 2600 Video's {de-comb, blend};
    Mapper wins over Mapper (more) when both are set."""
    st = {p: 0 for p in PORTS}
    bs = {"Mapper": 0, "Mapper (more)": 0}
    lines = []

    def apply(name, val):
        if name == "Reset":
            return
        f = {"Left Difficulty": ["diff_left_b"], "Right Difficulty": ["diff_right_b"], "TV Type": ["bw_setting"],
             "SaveKey (port 2)": ["savekey_setting"], "Swap Controllers": ["swap_joysticks"],
             "Region": ["region_setting"], "Palette": ["palette_temp"], "Port 1 Input": ["port1_input"],
             "Port 2 Input": ["port2_input"], "Turbo (X/Y)": ["turbo"], "AtariVox Voice": ["atarivox_setting"]}
        if name in f:
            st[f[name][0]] = val
        elif name == "Audio":
            st["stereo_tia"], st["stmix"] = val >> 2 & 1, val & 3
        elif name == "2600 Video":
            st["decomb"], st["flicker_blend"] = val >> 1 & 1, val & 1
        elif name in bs:
            bs[name] = val
            st["bs_override"] = bs["Mapper"] if bs["Mapper"] else bs["Mapper (more)"]
        else:
            raise SystemExit(f"no model for {name}")

    def write(name, val, check_all=True, wait=0x140):
        addr = int(by_addr[name]["address"], 16)
        lines.append(f"1 {addr:08x} {val:08x} {wait:x}  // {name} = {val}")
        apply(name, val)
        if check_all:
            for i, p in enumerate(PORTS):
                lines.append(f"2 {i:x} {st[p]:x} 0")

    # The Pocket writes every setting at start: the defaults, unchecked
    for v in var:
        if v["type"] != "action":
            write(v["name"], v["defaultval"], check_all=False)
    for i, p in enumerate(PORTS):
        lines.append(f"2 {i:x} {st[p]:x} 0")
    default_state = dict(st)
    # Each option of each item, every port checked after each write
    for v in var:
        if v["type"] == "action":
            lines.append(f"1 {int(v['address'], 16):08x} {v['value']:08x} 28  // {v['name']}")
            lines.append(f"2 {PORTS.index('menu_reset'):x} 1 0")
            lines.append(f"3 0 0 140")      # wait for the reset count to run out
            for i, p in enumerate(PORTS):
                lines.append(f"2 {i:x} {st[p]:x} 0")
            continue
        vals = [o["value"] for o in v["options"]] if v["type"] == "list" else [v["value"], 0]
        for x in vals + [v["defaultval"]]:
            write(v["name"], x)
    # Mapper priority: Mapper wins over Mapper (more), either way round
    m1 = [o["value"] for o in by_addr["Mapper"]["options"][1:]]
    m2 = [o["value"] for o in by_addr["Mapper (more)"]["options"][1:]]
    for a_, b_ in ((m1[0], m2[0]), (m1[-1], m2[-1])):
        write("Mapper (more)", b_)
        write("Mapper", a_)
        write("Mapper", 0)
        write("Mapper", a_)
        write("Mapper (more)", 0)
        write("Mapper", 0)
    for v in var:
        if v["type"] != "action":
            write(v["name"], v["defaultval"])
    assert st == default_state
    lines.append("0 0 0 0")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
