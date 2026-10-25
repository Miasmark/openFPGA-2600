#!/usr/bin/env python3
"""No game data in the repository: a check of every tracked file at HEAD.

This is the CI half of the repository's hygiene (plan D17). It checks what
sim/check/hygiene.sh checks, apart from the private names list, which stays
local and never goes to CI:
  - no file with a cartridge, save, firmware or release extension (.a26,
    .a78, .bin, .rom, .sav, .rbf, .rbf_r, .zip, .wav), no image or frame
    dump (.png, .ppm, .bmp, .gif, .jpg, .jpeg), nothing under sim/work;
  - no user firmware by name (bupchip, 7800bios, highscor, supercharger,
    with any extension);
  - no binary file and no file over LIMIT bytes (default 262144);
  - no absolute path into the temporary directory (under the root, var or
    private) or a scratch directory in a text file, by hygiene.sh's rule.
A path in sim/check/game_data_allow.txt (PATH # reason) is let through all
of these. An allowed path that is no longer tracked is reported, not failed.

  sim/check/game_data.py [--repo DIR] [--limit BYTES] [--allow-file FILE]
Exit status 0 when nothing is found, 1 otherwise, 2 on a usage error.
SPDX-License-Identifier: MIT
"""
import argparse, os, re, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("--repo", default=os.path.dirname(os.path.abspath(__file__)))
ap.add_argument("--limit", type=int, default=262144)
ap.add_argument("--allow-file")
a = ap.parse_args()
try:
    repo = subprocess.run(["git", "-C", a.repo, "rev-parse", "--show-toplevel"], capture_output=True,
                          text=True, check=True).stdout.strip()
except (subprocess.CalledProcessError, FileNotFoundError):
    print(f"game_data.py: {a.repo} is not a git checkout", file=sys.stderr)
    sys.exit(2)
allow_file = a.allow_file or os.path.join(repo, "sim", "check", "game_data_allow.txt")
allow = set()
if os.path.exists(allow_file):
    for l in open(allow_file, encoding="utf-8"):
        l = l.split("#", 1)[0].strip()
        if l:
            allow.add(l)

# hygiene.sh's rule for temporary-directory paths, spelled in pieces so that
# this file does not match it.
T = "tmp/"
TMP_AT = re.compile(r"/(?:var/|private/)?" + T)
FILE_URL = re.compile(r"file:/{2}[^/\s\"'`]*$", re.I)
SCRATCH = "scratch" + "pad"


def abs_tmp(text):
    text = text.replace("\\/", "/")
    for m in TMP_AT.finditer(text):
        i = m.start()
        if m.group(0) != "/" + T:
            return True
        if FILE_URL.search(text[:i]):
            return True
        j = i - 1
        while j >= 0 and text[j] == "/":
            j -= 1
        c = text[j] if j >= 0 else ""
        if c == "" or not re.match(r"[\w.~$})*%]", c):
            return True
        if re.search(r"(?:^|[\s\"'`=(:,\[{|>])-[A-Za-z]$", text[:i]):
            return True
    return SCRATCH in text.lower()


files = subprocess.run(["git", "-C", repo, "ls-files", "-z"], capture_output=True, check=True).stdout
files = [f.decode("utf-8", "replace") for f in files.split(b"\0") if f]
bad = []
for f in files:
    if f in allow:
        continue
    low, name = f.lower(), os.path.basename(f).lower()
    if re.search(r"\.(a26|a78|bin|rom|sav|rbf|rbf_r|zip|wav)$", low):
        bad.append(f"cartridge, save, firmware or release extension: {f}")
    if re.search(r"\.(png|ppm|bmp|gif|jpe?g)$", low):
        bad.append(f"image file: {f}")
    if f.startswith("sim/work"):
        bad.append(f"under sim/work: {f}")
    if re.fullmatch(r"(bupchip|7800bios|highscor|supercharger)\.[^/]*", name):
        bad.append(f"user firmware by name: {f}")
    path = os.path.join(repo, f)
    if os.path.islink(path) or not os.path.isfile(path):
        continue
    size = os.path.getsize(path)
    data = open(path, "rb").read()
    if b"\0" in data[:8000]:
        bad.append(f"binary file: {f} ({size} bytes)")
        continue
    if size > a.limit:
        bad.append(f"over {a.limit} bytes: {f} ({size} bytes)")
    for n, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
        if abs_tmp(line):
            bad.append(f"absolute path into the temporary directory or a scratch directory: {f}:{n}: {line.strip()[:120]}")

tracked = set(files)
for p in sorted(allow - tracked):
    print(f"  note: allowed path not tracked: {p}")
print(f"game data {repo}: {len(files)} tracked files, {len(allow & tracked)} allowed")
for b in bad:
    print("  FAIL: " + b)
print("GAME_DATA " + ("pass" if not bad else f"FAIL ({len(bad)} finding(s))"))
sys.exit(0 if not bad else 1)
