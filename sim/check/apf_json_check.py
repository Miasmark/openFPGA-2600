#!/usr/bin/env python3
"""Check the APF package files (dist/) against each other and against core_top.v.

  apf_json_check.py [--root DIR] [--vectors FILE] [--plusargs FILE]

Checks (each prints a line; the last line is APF_JSON pass or APF_JSON FAIL):
- every JSON file in dist/ parses; the core files carry "APF_VER_1";
- every field of every file is one Analogue's APF pages document, within the
  documented limits (LIMITS: lengths, counts, ranges, allowed values);
- core.json: names, version, url, description <= 63 characters, the
  bitstream name that tools/package.sh writes;
- Platforms/2600.json and _images/2600.bin are the files of Spiritualized's
  2600 core 1.0.0 (byte for byte: the platform is shared with that core);
- no 7800 package file is left;
- interact.json: the Pocket's menu limits (16 entries, 20 with the reloadable
  data slots, 16 options a list, 23 characters a name), every address decoded
  by core_top.v, option values inside the item's mask, defaults among the
  options, writeonly on every setting and persist on all but the Mapper
  lists (each forcible bss_type once, names matching detect2600.sv's enum,
  BUS left out, not persisted), SaveKey Off/On;
- the menu options against the RTL that acts on them: Port Input (the
  wrapper's menu_port_type, the menu value alone, and the code that uses each
  port type), with a planted Paddles/Driving swap that must be caught;
  Palette (video_mux), Turbo, AtariVox Voice, Region (wrapper), Audio and
  2600 Video (core_top's split and stmix arms), Mapper (bss_type as is);
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
# Port Input names and their menu values. What each value does is read from
# atari2600_pocket.sv (check_options_rtl), not taken from this table.
PORT_NAMES = {"Joystick": 0, "Paddles": 2, "Driving": 3, "Light Gun": 4,
              "Dual Stick": 5, "Booster Grip": 6}

# Wrapper setting ports the bench reads (tb_core_top.sv, PORTS), in order
PORTS = ["bs_override", "diff_left_b", "diff_right_b", "bw_setting", "savekey_setting",
         "swap_joysticks", "region_setting", "palette_temp", "port1_input", "port2_input",
         "turbo", "atarivox_setting", "stereo_tia", "stmix", "decomb", "flicker_blend",
         "menu_reset"]

# Analogue's documented fields and limits, from the APF developer pages
# https://www.analogue.co/developer/docs/core-definition-files/<file>-json
# (core, data, input, interact, video, audio, variants) and
# https://www.analogue.co/developer/docs/platform-metadata, read 2026-10-24.
# Every field present in a file must have a row (an undocumented field
# fails), and every rule of its row must hold. Paths are dotted keys, []
# meaning each element of an array. Rules:
#   ("len", n)    string of at most n characters
#   ("count", n)  array of at most n elements
#   "u16", "u32"  integer or "0x" hex string, unsigned 16 / 32 bit
#   "s32"         integer or hex string, signed 32 bit
#   "int", "bool", "str", "obj", "arr"   the JSON type
#   ("eq", v), ("in", values), ("re", pattern)
PLATFORM_ID = ("re", r"[a-z0-9][a-z0-9_]{0,14}")   # platform-metadata: a-z 0-9 _, 15, no leading _
INPUT_KEYS = ("pad_btn_a", "pad_btn_b", "pad_btn_x", "pad_btn_y", "pad_trig_l", "pad_trig_r",
              "pad_btn_start", "pad_btn_select")
DISPLAY_MODES = ("0x10", "0x20", "0x21", "0x22", "0x23", "0x30", "0x31", "0x32", "0x40", "0x41", "0x42",
                 "0x51", "0x52", "0x61", "0x62", "0x63", "0x71", "0x72", "0x81", "0x82", "0xE0", "0xE1")
SETTING = ("persist", "writeonly", "defaultval", "value", "value_off", "mask", "group")
LIMITS = {
    "core.json": {
        "core": ["obj"], "core.magic": [("eq", "APF_VER_1")], "core.metadata": ["obj"],
        "core.metadata.platform_ids": ["arr", ("count", 4)],
        "core.metadata.platform_ids[]": ["str", PLATFORM_ID],
        "core.metadata.shortname": ["str", ("len", 31)],
        "core.metadata.description": ["str", ("len", 63)],
        "core.metadata.author": ["str", ("len", 31)],
        "core.metadata.url": ["str", ("len", 63)],
        "core.metadata.version": ["str", ("len", 31)],
        "core.metadata.date_release": ["str", ("len", 10), ("re", r"\d{4}-\d{2}-\d{2}")],
        "core.framework": ["obj"],
        "core.framework.target_product": [("eq", "Analogue Pocket")],
        "core.framework.version_required": ["str", ("re", r"\d+\.\d+")],
        "core.framework.sleep_supported": ["bool"],
        "core.framework.chip32_vm": ["str", ("len", 15)],
        "core.framework.dock": ["obj"],
        "core.framework.dock.supported": [("eq", True)],          # "Must be true"
        "core.framework.dock.analog_output": ["bool"],
        "core.framework.hardware": ["obj"],
        "core.framework.hardware.link_port": ["bool"],
        "core.framework.hardware.cartridge_adapter": ["s32"],
        "core.cores": ["arr", ("count", 8)], "core.cores[]": ["obj"],
        "core.cores[].name": ["str", ("len", 15)],
        "core.cores[].id": ["u32"],
        "core.cores[].filename": ["str", ("len", 15)],
    },
    "data.json": {
        "data": ["obj"], "data.magic": [("eq", "APF_VER_1")],
        "data.data_slots": ["arr", ("count", 32)], "data.data_slots[]": ["obj"],
        "data.data_slots[].name": ["str", ("len", 15)],
        "data.data_slots[].id": ["u16"],
        "data.data_slots[].required": ["bool"],
        "data.data_slots[].parameters": ["u32"],
        "data.data_slots[].nonvolatile": ["bool"],
        "data.data_slots[].deferload": ["bool"],
        "data.data_slots[].secondary": ["bool"],
        "data.data_slots[].filename": ["str", ("len", 31)],
        "data.data_slots[].extensions": ["arr", ("count", 4)],
        "data.data_slots[].extensions[]": ["str", ("len", 7)],
        "data.data_slots[].size_exact": ["u32"],
        "data.data_slots[].size_maximum": ["u32"],
        "data.data_slots[].address": ["u32"],
    },
    "input.json": {
        "input": ["obj"], "input.magic": [("eq", "APF_VER_1")],
        "input.controllers": ["arr", ("count", 4)], "input.controllers[]": ["obj"],
        "input.controllers[].type": [("eq", "default")],
        "input.controllers[].mappings": ["arr", ("count", 8)], "input.controllers[].mappings[]": ["obj"],
        "input.controllers[].mappings[].id": ["u16"],
        "input.controllers[].mappings[].name": ["str", ("len", 19)],
        "input.controllers[].mappings[].key": [("in", INPUT_KEYS)],
    },
    "interact.json": {
        "interact": ["obj"], "interact.magic": [("eq", "APF_VER_1")],
        "interact.variables": ["arr", ("count", 16)], "interact.variables[]": ["obj"],
        "interact.variables[].name": ["str", ("len", 23)],
        "interact.variables[].id": ["u16"],
        "interact.variables[].type": [("in", ("radio", "check", "slider_u32", "list", "number_u32", "action"))],
        "interact.variables[].enabled": ["bool"],
        "interact.variables[].address": ["u32"],
        "interact.variables[].group": ["u32"],
        "interact.variables[].persist": ["bool"],
        "interact.variables[].writeonly": ["bool"],
        "interact.variables[].defaultval": ["s32"],
        "interact.variables[].value": ["s32"],
        "interact.variables[].value_off": ["s32"],
        "interact.variables[].mask": ["u32"],
        "interact.variables[].graphical": ["obj"],
        "interact.variables[].graphical.signed": ["bool"],
        "interact.variables[].graphical.min": ["s32"],
        "interact.variables[].graphical.max": ["s32"],
        "interact.variables[].graphical.adjust_small": ["s32"],
        "interact.variables[].graphical.adjust_large": ["s32"],
        "interact.variables[].options": ["arr", ("count", 16)], "interact.variables[].options[]": ["obj"],
        "interact.variables[].options[].value": ["s32"],
        "interact.variables[].options[].name": ["str", ("len", 23)],
        # Not on the interact.json page; the 7800 core has shipped it empty
        "interact.messages": [("eq", [])],
    },
    "video.json": {
        "video": ["obj"], "video.magic": [("eq", "APF_VER_1")],
        "video.scaler_modes": ["arr", ("count", 8)], "video.scaler_modes[]": ["obj"],
        "video.scaler_modes[].width": ["int"], "video.scaler_modes[].height": ["int"],
        "video.scaler_modes[].aspect_w": ["int"], "video.scaler_modes[].aspect_h": ["int"],
        "video.scaler_modes[].dock_aspect_w": ["int"], "video.scaler_modes[].dock_aspect_h": ["int"],
        "video.scaler_modes[].rotation": [("in", (0, 90, 180, 270))],
        "video.scaler_modes[].mirror": [("in", (0, 1, 2, 3))],
        "video.display_modes": ["arr", ("count", 16)], "video.display_modes[]": ["obj"],
        "video.display_modes[].id": [("in", DISPLAY_MODES)],
        "video.defaults": ["obj"], "video.defaults.sharpness": [("in", (0, 1, 2, 3))],
    },
    "audio.json": {"audio": ["obj"], "audio.magic": [("eq", "APF_VER_1")]},
    "variants.json": {
        "variants": ["obj"], "variants.magic": [("eq", "APF_VER_1")],
        "variants.variant_list": ["arr", ("count", 8)], "variants.variant_list[]": ["obj"],
        "variants.variant_list[].name": ["str", ("len", 15)],
        "variants.variant_list[].id": ["u16"],
        "variants.variant_list[].core_select": ["obj"],
        "variants.variant_list[].core_select.core_id": ["u32"],
        "variants.variant_list[].data_override": ["arr", ("count", 8)],
        "variants.variant_list[].data_override[]": ["obj"],
        "variants.variant_list[].data_override[].data_id_to": ["u16"],
        "variants.variant_list[].data_override[].data_id_from": ["u16"],
        "variants.variant_list[].memory_writes": ["arr", ("count", 16)],
        "variants.variant_list[].memory_writes[]": ["obj"],
        "variants.variant_list[].memory_writes[].address": ["u32"],
        "variants.variant_list[].memory_writes[].data": ["u32"],
    },
    "platform": {
        "platform": ["obj"],
        "platform.category": ["str", ("len", 31)],
        "platform.name": ["str", ("len", 31)],
        "platform.manufacturer": ["str", ("len", 31)],
        "platform.year": ["int"],
    },
}

fails = []


def num(v):
    """An "integer / hex string" field's value, or None."""
    if isinstance(v, bool):
        return None
    if isinstance(v, int):
        return v
    if isinstance(v, str) and re.fullmatch(r"0[xX][0-9A-Fa-f]+", v):
        return int(v, 16)
    return None


def rule_ok(rule, v):
    if rule == "obj":
        return isinstance(v, dict)
    if rule == "arr":
        return isinstance(v, list)
    if rule == "str":
        return isinstance(v, str)
    if rule == "bool":
        return isinstance(v, bool)
    if rule == "int":
        return isinstance(v, int) and not isinstance(v, bool)
    if rule in ("u16", "u32", "s32"):
        n = num(v)
        lo, hi = {"u16": (0, 0xFFFF), "u32": (0, 0xFFFFFFFF), "s32": (-2**31, 2**31 - 1)}[rule]
        if rule == "s32" and isinstance(v, str) and n is not None and n <= 0xFFFFFFFF:
            return True     # a hex string is the 32-bit pattern
        return n is not None and lo <= n <= hi
    kind, arg = rule
    if kind == "len":
        return isinstance(v, str) and len(v) <= arg
    if kind == "count":
        return isinstance(v, list) and len(v) <= arg
    if kind == "eq":
        return v == arg and type(v) is type(arg)
    if kind == "in":
        return any(v == x and type(v) is type(x) for x in arg)
    if kind == "re":
        return isinstance(v, str) and re.fullmatch(arg, v) is not None
    raise ValueError(rule)


def check_limits(fname, obj, table):
    """Every field of obj against table; one check line per (field, rule)
    that has values, so a long array still prints one line."""
    seen = {}

    def walk(v, path, where):
        if path:
            seen.setdefault(path, []).append((where, v))
        if isinstance(v, dict):
            for k, x in v.items():
                walk(x, f"{path}.{k}" if path else k, f"{where}.{k}" if where else k)
        elif isinstance(v, list):
            for i, x in enumerate(v):
                walk(x, path + "[]", f"{where}[{i}]")
    walk(obj, "", "")
    n_ok = n_vals = 0
    for path, vals in seen.items():
        rules = table.get(path)
        if rules is None:
            check(False, f"{fname}: {path} is not a documented field")
            continue
        for r in rules:
            for w, v in vals:
                n_vals += 1
                if rule_ok(r, v):
                    n_ok += 1
                else:
                    what = r if isinstance(r, str) else f"{r[0]} {r[1]!r}"
                    check(False, f"{fname}: {w} = {v!r} breaks the documented limit {what}")
    lens = sorted({f"{p.rsplit('.', 1)[-1]} {r[1]}" for p in seen for r in table.get(p, []) if r[0] == "len"})
    check(n_ok == n_vals and all(p in table for p in seen),
          f"{fname}: {sum(p in table for p in seen)}/{len(seen)} fields documented, "
          f"{n_ok}/{n_vals} rule checks within limits"
          + (f" (lengths: {', '.join(lens)})" if lens else ""))


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
    wrap = open(os.path.join(root, "src/fpga/core/atari2600_pocket.sv")).read()
    vmux = open(os.path.join(root, "src/fpga/mister/rtl/video_mux.sv")).read()
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

    print("-- Analogue's documented fields and limits (LIMITS)")
    for rel, (obj, _) in sorted(js.items()):
        base = os.path.basename(rel)
        table = LIMITS["platform"] if rel.startswith("Platforms/") else LIMITS.get(base)
        if check(table is not None, f"{rel}: a file the APF pages document"):
            check_limits(rel, obj, table)

    print("-- core.json")
    core = js["Cores/Miasmark.2600/core.json"][0]["core"]
    md = core["metadata"]
    check(md["platform_ids"] == ["2600"], "platform_ids [\"2600\"]")
    check(md["shortname"] == "2600", "shortname 2600")
    check(md["author"] == "Miasmark", "author Miasmark")
    check(md["version"] == "1.0.1", "version 1.0.1")
    check(md["url"] == "https://github.com/Miasmark/openFPGA-2600", "url")
    check(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}", md["date_release"])), "date_release is a date")
    check(len(md["description"]) <= 63, f"description {len(md['description'])} characters (limit 63)")
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
    check(names == ["Cartridge", "Supercharger", "SaveKey", "FA2 flash"], f"slot order {names}")
    ids = [int(s["id"], 16) for s in slots]
    check(len(set(ids)) == len(ids), "slot ids unique")
    cart, arfw, sk, fa2 = slots
    check(cart["extensions"] == ["a26", "bin"] and cart.get("required") is True, "cartridge: a26/bin, required")
    check(int(cart["parameters"], 16) & 1 == 1, "cartridge slot user-reloadable")
    check(arfw.get("filename") == "supercharger.bin" and arfw.get("required") is False
          and int(arfw["parameters"], 16) & 2 == 0,
          "Supercharger: supercharger.bin, optional, not core-specific (/Assets/2600/common/)")
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
        if v["type"] != "action":
            # core_top's 0x10 settings are write-only registers: the host must
            # not read them back, and a setting keeps its value across runs
            # (the Mapper items aside, checked below)
            check(v.get("writeonly") is True, f"{v['name']}: writeonly true")
            if v["name"] not in ("Mapper", "Mapper (more)"):
                check(v.get("persist") is True, f"{v['name']}: persist true")
        else:
            check(all(k not in v for k in ("writeonly", "persist", "defaultval")),
                  f"{v['name']}: action, no setting fields")
        if v["type"] == "list":
            opts = v["options"]
            mask = int(v["mask"], 16)
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
              and v["defaultval"] == 0, f"{nm}: Joystick (0, default) and the other names by PORT_NAMES")
    for nm in ("Left Difficulty", "Right Difficulty"):
        check([(o["value"], o["name"]) for o in by_addr[nm]["options"]] == [(0, "A"), (1, "B")], f"{nm}: A = 0, B = 1 (diff_*_b)")
    check([(o["value"], o["name"]) for o in by_addr["TV Type"]["options"]] == [(0, "Colour"), (1, "B&W")], "TV Type: Colour 0, B&W 1")
    check([(o["value"], o["name"]) for o in by_addr["Region"]["options"]] == [(0, "Auto"), (1, "NTSC"), (2, "PAL")],
          "Region: Auto 0, NTSC 1, PAL 2")

    print("-- menu options against the RTL (what each option makes the core do)")
    check_options_rtl(by_addr, wrap, core_top, vmux)

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
    check("Kitrinx" in info and "openFPGA-7800" in info,
          "info.txt credits the MiSTer core (Kitrinx) and the openFPGA-7800 port")

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


def rtl_find(pattern, text, what, flags=0):
    m = re.search(pattern, text, flags)
    if not m:
        raise LookupError(what)
    return m


def port_types(wrap):
    """The Port Input menu value -> MiSTer port type, as atari2600_pocket.sv
    computes it: menu_port_type's case arms, and its default (a constant: a
    2600 image names no controller, so no header byte takes part)."""
    body = rtl_find(r"function \[7:0\] menu_port_type\(input \[2:0\] m\);(.*?)endfunction", wrap,
                    "menu_port_type(m), the menu value alone", re.S).group(1)
    menu = {int(k): int(t) for k, t in re.findall(r"\d+'d(\d+):\s*menu_port_type\s*=\s*8'd(\d+);", body)}
    dflt = int(rtl_find(r"default:\s*menu_port_type\s*=\s*8'd(\d+);", body, "menu_port_type default (a constant)").group(1))
    if not re.search(r"porta_type = menu_port_type\(port1_input\);", wrap) or \
       not re.search(r"portb_type = menu_port_type\(port2_input\);", wrap):
        raise LookupError("porta_type / portb_type from menu_port_type(portN_input)")
    return [lambda v: menu.get(v, dflt)] * 2, menu


def port_meanings(wrap):
    """MiSTer port type -> what the wrapper does with it, per port, read from
    the code that uses porta_type / portb_type (not from a comment)."""
    out = []
    for side, half, j, drv in (("a", "7:4", "a", "drive_a"), ("b", "3:0", "b", "drive_b")):
        q = re.escape(half)
        m = {}
        m["none"] = rtl_find(rf"8'd(\d+): begin pa_in_r\[{q}\] = 4'b1111; ilatch\[\d\] = 1'b1;", wrap, f"port {side} off")
        m["Paddles"] = rtl_find(rf"\(port{side}_type == 8'd(\d+)\) \? 2'b11 : 2'b00", wrap, f"port {side} paddle_en")
        m["Driving"] = rtl_find(rf"8'd(\d+): begin pa_in_r\[{q}\] = [^\n]*\b{drv}\b", wrap, f"port {side} driving")
        m["Booster Grip"] = rtl_find(rf"8'd(\d+): idump\[\d:\d\] = \{{joy{j}\[10\], joy{j}\[11\]\}};", wrap, f"port {side} Booster Grip")
        if side == "a":
            m["Light Gun"] = rtl_find(r"gun_en\s*=\s*\(porta_type == 8'd(\d+)\)", wrap, "port a light gun")
        else:
            m["Light Gun"] = rtl_find(r"gun_port\s*=\s*\(portb_type == 8'd(\d+)\)", wrap, "port b light gun")
        m["Dual Stick"] = rtl_find(rf"dual_stick = [^\n]*\(port{side}_type == 8'd(\d+)\)", wrap, f"port {side} dual stick")
        types = {}
        for k, mt in m.items():
            t = int(mt.group(1))
            if t in types:
                raise LookupError(f"port {side}: type {t} is both {types[t]} and {k}")
            types[t] = k
        out.append(types)
    return out


def port_check(by_addr, wrap, quiet=False):
    """Mismatches between each Port Input option's name and what the wrapper
    makes of its value. A type with none of the special uses is a plain
    joystick (the joystick lines, fire on INPT4/5)."""
    evals, _ = port_types(wrap)
    means = port_meanings(wrap)
    bad = []
    for i, nm in enumerate(("Port 1 Input", "Port 2 Input")):
        for o in by_addr[nm]["options"]:
            t = evals[i](o["value"])
            got = means[i].get(t, "Joystick")
            ok = got == o["name"]
            if not ok:
                bad.append(f"{nm} {o['name']} ({o['value']}) gives type {t}: {got}")
            if not quiet:
                check(ok, f"{nm}: {o['name']} = {o['value']} -> menu_port_type {t} -> {got}")
    return bad


def check_options_rtl(by_addr, wrap, core_top, vmux):
    """The option -> behaviour tables, read from the RTL that implements them."""
    try:
        port_check(by_addr, wrap)
        # Planted fault: swap the paddle and driving arms of menu_port_type;
        # the check above must then fail.
        means = port_meanings(wrap)[0]
        pt = {k: t for t, k in means.items()}
        body = rtl_find(r"function \[7:0\] menu_port_type\(.*?endfunction", wrap, "menu_port_type", re.S).group(0)
        a = rtl_find(rf"(\d+'d\d+:\s*menu_port_type\s*=\s*)8'd{pt['Paddles']};", body, "paddle arm")
        b = rtl_find(rf"(\d+'d\d+:\s*menu_port_type\s*=\s*)8'd{pt['Driving']};", body, "driving arm")
        planted = body.replace(a.group(0), a.group(1) + "8'dPP;").replace(b.group(0), b.group(1) + f"8'd{pt['Paddles']};")
        planted = planted.replace("8'dPP;", f"8'd{pt['Driving']};")
        bad = port_check(by_addr, wrap.replace(body, planted), quiet=True)
        check(len(bad) >= 2, f"planted fault: Paddles/Driving swapped in menu_port_type is caught ({'; '.join(bad)})")
    except LookupError as e:
        check(False, f"Port Input: cannot read {e} from atari2600_pocket.sv")

    # Palette: video_mux's case ({is_PAL, pal_temp}), NTSC half
    arms = dict((int(k), c) for k, c in re.findall(r"\n\s*(\d): out_color = n(\w+)_color;", vmux))
    opts = by_addr["Palette"]["options"]
    check(all(arms.get(o["value"]) == o["name"].lower() for o in opts) and len(arms) == len(opts),
          f"Palette: {[(o['value'], o['name']) for o in opts]} = video_mux out_color {arms}")

    # Turbo: 0 never gates fire; else fire toggles every value+1 frames
    tv = {o["name"]: o["value"] for o in by_addr["Turbo (X/Y)"]["options"]}
    ok = bool(re.search(r"turbo_gate = \(turbo == 2'd0\) \| turbo_on;", wrap)
              and re.search(r"if \(turbo_cnt >= turbo\) begin\s*turbo_cnt <= 2'd0;\s*turbo_on\s*<= ~turbo_on;", wrap))
    check(ok and tv.get("Off") == 0 and 0 < tv.get("Fast", 0) < tv.get("Medium", 0) < tv.get("Slow", 0),
          f"Turbo: Off = 0 (turbo_gate open), Fast < Medium < Slow by the period turbo+1 frames {tv}")

    # AtariVox: 0 mutes (vox_on), the gain shift grows with the value
    av = {o["name"]: o["value"] for o in by_addr["AtariVox Voice"]["options"]}
    off = re.search(r"vox_on = use_sk && \(atarivox_setting != 2'd0\);", wrap)
    g = re.search(r"vox_gain = \(atarivox_setting == 2'd(\d)\) \? \(20'\(vox_sample\) <<< (\d+)\) :\s*"
                  r"\(atarivox_setting == 2'd(\d)\) \? \(20'\(vox_sample\) <<< (\d+)\) : \(20'\(vox_sample\) <<< (\d+)\);", wrap)
    if off and g:
        sh = {int(g.group(1)): int(g.group(2)), int(g.group(3)): int(g.group(4))}
        sh.update({v: int(g.group(5)) for v in (1, 2, 3) if v not in sh})
        ok = av.get("Off") == 0 and sh[av["Quiet"]] < sh[av["Normal"]] < sh[av["Loud"]]
    else:
        ok, sh = False, None
    check(ok, f"AtariVox Voice: Off = 0 (vox_on), Quiet < Normal < Loud by vox_gain's shift {sh} {av}")

    # Region: 0 automatic, the value region_select compares with is PAL, the other NTSC
    rv = {o["name"]: o["value"] for o in by_addr["Region"]["options"]}
    r = re.search(r"region_select = \(region_setting == 2'd(\d)\) \?\s*\([^;]*\) : \(region_setting == 2'd(\d)\);", wrap)
    check(r is not None and rv.get("Auto") == int(r.group(1)) and rv.get("PAL") == int(r.group(2))
          and rv.get("NTSC") not in (int(r.group(1)), int(r.group(2))),
          f"Region: Auto / PAL by region_select {r and r.groups()}, NTSC the other {rv}")

    # Audio: core_top splits the value {stereo, stmix}; stmix's arms in core_top
    split = re.search(r"12'h2B8: \{set_stereo, set_stmix\}\s*<= bridge_wr_data\[2:0\];", core_top)
    mix = {}
    body = re.search(r"case \(stmix\)(.*?)endcase", core_top, re.S)
    for k, arm in re.findall(r"2'd(\d): begin(.*?)end", body.group(1) if body else "", re.S):
        mix[int(k)] = ("none" if re.search(r"mix_l <= audio_l; mix_r <= audio_r;", arm) else
                       "1/8" if "audio_r >> 3" in arm else "1/4" if "audio_r >> 2" in arm else "?")
    if body and re.search(r"default: begin\s*mix_l <= \(audio_l >> 1\) \+ \(audio_r >> 1\);\s*"
                          r"mix_r <= \(audio_l >> 1\) \+ \(audio_r >> 1\);", body.group(1)):
        mix[3] = "mono"
    # MiSTer's names: a 25% blend takes 1/8 of the other side, 50% a quarter
    want = {"Mono TIA": (0, "none"), "Stereo TIA": (1, "none"), "Stereo, 25% Blend": (1, "1/8"),
            "Stereo, 50% Blend": (1, "1/4"), "Full Mono": (None, "mono")}
    for o in by_addr["Audio"]["options"]:
        w = want.get(o["name"])
        st, mx = o["value"] >> 2 & 1, mix.get(o["value"] & 3)
        check(split is not None and w is not None and (w[0] is None or w[0] == st) and w[1] == mx,
              f"Audio: {o['name']} = {o['value']}: stereo_tia {st}, stmix arm {o['value'] & 3} {mx}")

    # 2600 Video: {decomb, blend}, to the wrapper's decomb / flicker_blend
    split = re.search(r"12'h2BC: \{set_decomb, set_blend\}\s*<= bridge_wr_data\[1:0\];", core_top)
    ports = re.search(r"\.decomb\s*\(decomb\)", wrap) and re.search(r"\.blend\s*\(flicker_blend\)", wrap)
    for o in by_addr["2600 Video"]["options"]:
        n = o["name"]
        check(bool(split and ports) and bool(o["value"] & 1) == ("Blend" in n) and bool(o["value"] & 2) == ("De-comb" in n),
              f"2600 Video: {n} = {o['value']}: blend bit 0, de-comb bit 1")

    # Mapper: a non-zero value is the bss_type itself
    check(re.search(r"\(\|bs_override \? \{1'b0, bs_override\} : force_bs\)", wrap) is not None,
          "Mapper: the wrapper runs bss_type = bs_override when it is not 0 (values are detect2600's enum)")


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
