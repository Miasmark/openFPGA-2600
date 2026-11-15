#!/usr/bin/env python3
"""The save-state benches (docs/SAVESTATE.md 7): RTL against RTL.

The oracle is the core's own straight run. Each case runs the whole core
(tb_load, built with SS_BENCH=1: sim/run_sim.sh) on one image:

  R  a straight run, with tb_load's machine fingerprint (+ssfp: per machine
     frame, counted on the clocks the machine is not held: its clocks, RIOT
     RAM, picture, sound and CPU bus hashes);
  S  the same run with saves asked for at seeded random moments: every frame
     must equal R's (a save may not change the machine at all), and every
     blob must pass tools/savestate/savestate.py verify with the image's
     CRC32, length and mapper;
  L  each case's first blob loaded into a core that has run on its own for a
     while (it booted and played elsewhere, so a bit left out of the state
     cannot hide behind a fresh core's reset value), and its last blob into
     one that has run long past the saved point: every frame after the saved
     one must equal R's;
  F  (refusal cases) a blob of another image, and blobs made bad one way
     each (a payload byte, the header CRC, the version, the chain
     signature, a reserved word, the gap with its CRC made right, a word
     written past the live part): err, and the run goes on exactly as R;
  X  (refused schemes: DPC+, the Supercharger, an A78) a save: err at once,
     and the run goes on exactly as R;
  M  the menu open twice with Pause in Menu (frames as R, the machine held
     while it is open) and once without (frames as R, never held);
  W  wake: a load asked for while the host holds the console in reset,
     applied at the reset's exit: frames after the saved one as R.

  ss_bench.py run --work DIR [--build] [--only CASE,...] [--games DIR]
                  [--jobs N] [--seed N] [--vtb PATH]
      every case (--only: those). --games DIR: the owner's game files,
      copied into WORK (a bench may delete its files; the library is never
      a bench's path), for the cases marked game; without it those are
      skipped (reported, not a pass). Each simulation runs in a slot of
      ~/daria_work/bin/simslot when it exists (SIMSLOT=cmd overrides), at
      most --jobs at once (default 2).
  ss_bench.py list
      the cases.
Prints one "SSBENCH" line per check and "SSBENCH pass" or "SSBENCH FAIL";
exit 0 on pass.
SPDX-License-Identifier: MIT
"""
import argparse
import concurrent.futures as cf
import os
import random
import re
import shutil
import struct
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
SSPY = os.path.join(ROOT, "tools", "savestate", "savestate.py")
sys.path.insert(0, os.path.join(ROOT, "tools", "savestate"))
import savestate as SS  # noqa: E402

# case: name -> dict(img=(how), args=[plusargs], ms=run length, saves=n, kind)
#   img: ("py", script, args...) our generators; ("game", file name); ("file", path)
GEN_MAP = ["f8", "f6", "f4", "f0", "ef", "df", "sb", "ua", "jane", "0840"]
GEN_RAM = ["f8sc", "f4sc", "fa", "cv", "e7", "3e", "wd", "cty"]
CASES = {}
CASES["probe"] = dict(img=("py", "ssprobe_test.py"), ms=700, saves=3, kind="rt", F=True, M=True, W=True)
for m in GEN_MAP:
    CASES["map_" + m] = dict(img=("py", "ss_mapper_test.py", m), bs=True, ms=600, saves=2, kind="rt")
for m in GEN_RAM:
    CASES["ram_" + m] = dict(img=("py", "cartram2600_test.py", m), bs=True, ms=600, saves=2, kind="rt")
CASES["fa2"] = dict(img=("py", "fa2_test.py", "image"), ms=700, saves=2, kind="rt")
CASES["paddles"] = dict(img=("py", "input_test.py"), ms=900, saves=3, kind="rt",
                        args=["+port1=2", "+port2=2", "+joyscript=@paddles"])
# the SaveKey round trip runs in the first frames: saves inside it (2-40 ms)
CASES["savekey"] = dict(img=("py", "console_test.py", "savekey"), ms=600, saves=3, kind="rt", win=(2, 40),
                        args=["+sk_on"])
# a multicart: the game moves on at each console reset (mapper_MC's game register)
CASES["mc4k"] = dict(img=("py", "console_test.py", "mc", "4", "4"), bsn=30, ms=700, saves=3, kind="rt",
                     args=["+joyscript=@mc"])
CASES["gun"] = dict(img=("py", "input_test.py"), ms=700, saves=2, kind="rt",
                    args=["+port1=4", "+joyscript=@gun"])
CASES["driving"] = dict(img=("py", "input_test.py"), ms=700, saves=2, kind="rt",
                        args=["+port1=3", "+joyscript=@driving"])
CASES["refuse_dpcp"] = dict(img=("py", "bupchip/daria/fe_dir/mkimg.py", "smoke_dpc"), ms=300, kind="refuse")
CASES["refuse_ar"] = dict(img=("py", "ar_test.py", "full"), ms=300, kind="refuse")
CASES["refuse_a78"] = dict(img=("py", "make_a78.py", "7"), ms=300, kind="refuse")
# the owner's games (--games): one or more of each family
GAMES = {
    "g_2k": "Combat (USA).a26", "g_4k": "Adventure (USA).a26", "g_f8": "Asteroids (USA).a26",
    "g_f6": "Millipede (USA).a26", "g_f6sc": "Crystal Castles (USA).a26", "g_f4sc": "Fatal Run (USA).a26",
    "g_fe": "Robot Tank (USA).a26", "g_e0": "Montezuma's Revenge Featuring Panama Joe (USA).a26",
    "g_3f": "Miner 2049er Starring Bounty Bob (USA).a26", "g_e7": "BurgerTime (USA).a26",
    "g_fa": "Mountain King (USA).a26", "g_dpc": "Pitfall II - Lost Caverns (USA).a26",
    "g_paddle": "Kaboom! (USA).a26", "g_paddle4": "Warlords (USA).a26",
}
for k, f in GAMES.items():
    a = ["+joyscript=@game"]
    if k.startswith("g_paddle"):
        a = ["+port1=2", "+port2=2", "+joyscript=@paddlegame"]
    CASES[k] = dict(img=("game", f), ms=1200, saves=2, kind="rt", args=a)

SCRIPTS = {
    "paddles": ["0 types", "100 joy0=1", "300 joy0=0", "320 joy1=2", "500 joy1=0", "520 joy2=801", "700 joy2=0",
                "720 joy3=1002", "880 joy3=0"],
    "gun": ["0 types", "100 joy0=6", "300 joy0=200", "360 joy0=0", "400 joy0=9", "600 joy0=0"],
    "driving": ["0 types", "100 joy0=1", "350 joy0=0", "400 joy0=2", "650 joy0=0"],
    "mc": ["80 reset", "160 reset", "240 reset", "320 reset", "400 reset"],
    "game": ["100 joy0=100", "150 joy0=0", "200 joy0=10", "260 joy0=0", "300 joy0=1", "600 joy0=0", "620 joy0=12",
             "800 joy0=2", "1000 joy0=0", "1050 joy0=10", "1100 joy0=0"],
    "paddlegame": ["100 joy0=100", "150 joy0=0", "200 joy0=200", "260 joy0=0", "300 joy0=1", "600 joy0=0",
                   "620 joy1=2", "800 joy1=0", "820 joy2=1", "900 joy2=0", "920 joy3=2", "1000 joy3=0",
                   "1050 joy0=200", "1100 joy0=0"],
}


class Bench:
    def __init__(self, a):
        self.a = a
        self.work = os.path.abspath(a.work)
        self.vtb = a.vtb or os.path.join(self.work, "obj_load", "vtb")
        slot = os.environ.get("SIMSLOT", os.path.expanduser("~/daria_work/bin/simslot"))
        self.slot = [slot] if slot and os.path.exists(slot) else []
        self.lines = []
        self.bad = 0
        self.rng = random.Random(a.seed)

    def say(self, s, ok=True):
        print("SSBENCH " + s + ("" if ok else "  <-- FAIL"), flush=True)
        if not ok:
            self.bad += 1

    def build(self):
        env = dict(os.environ, SS_BENCH="1", BUILD_TOP="tb_load", WORK=self.work)
        r = subprocess.run(["bash", os.path.join(HERE, "run_sim.sh")], env=env, capture_output=True, text=True)
        print(r.stdout[-400:])
        if r.returncode:
            print(r.stderr[-2000:])
            sys.exit(1)

    def image(self, name, c):
        d = os.path.join(self.work, "cases", name)
        os.makedirs(d, exist_ok=True)
        rtl = os.path.join(d, "rtl")
        if not os.path.exists(rtl):
            os.symlink(os.path.join(self.work, "rtl"), rtl)
        img = os.path.join(d, "image.bin")
        kind = c["img"][0]
        bs = None
        if kind == "py":
            script = os.path.join(HERE, c["img"][1])
            if c["img"][1].endswith("mkimg.py"):
                subprocess.run([sys.executable, script, os.path.join(d, "mk"), c["img"][2]], check=True,
                               capture_output=True)
                shutil.copy(os.path.join(d, "mk", c["img"][2] + ".bin"), img)
            else:
                r = subprocess.run([sys.executable, script] + list(c["img"][2:]), check=True, capture_output=True)
                open(img, "wb").write(r.stdout)
                if c.get("bs"):
                    bs = int(r.stderr.decode().strip().split()[-1])
        elif kind == "game":
            if not self.a.games:
                return None, None, d
            src = os.path.join(self.a.games, c["img"][1])
            if not os.path.exists(src):
                return None, None, d
            shutil.copy(src, img)
        for a in c.get("args", []):
            if a.startswith("+joyscript=@"):
                open(os.path.join(d, a[12:] + ".txt"), "w").write("\n".join(SCRIPTS[a[12:]]) + "\n")
        return img, bs, d

    def sim(self, d, args, log):
        cmd = self.slot + [self.vtb] + args
        with open(os.path.join(d, log), "w") as o:
            r = subprocess.run(cmd, cwd=d, stdout=o, stderr=subprocess.STDOUT)
        return r.returncode, open(os.path.join(d, log), "rb").read().decode("utf-8", "replace")

    @staticmethod
    def frames(path):
        out = {}
        if not os.path.exists(path):
            return out
        for l in open(path).read().splitlines()[1:]:
            f = l.split(",")
            out[int(f[0])] = f[1:]
        return out

    def base_args(self, c, img, bs):
        a = ["+image=image.bin", "+wav=%d" % c["ms"]]
        if bs or c.get("bsn"):
            a.append("+bs=%d" % (bs or c["bsn"]))
        for x in c.get("args", []):
            a.append("+joyscript=" + x[12:] + ".txt" if x.startswith("+joyscript=@") else x)
        return a

    def compare(self, R, X, after, what):
        keys = [k for k in sorted(X) if k > after and k in R]
        diff = [k for k in keys if X[k] != R[k]]
        ok = bool(keys) and not diff
        self.say("%s: frames %s-%s, %d compared, %d differ%s" % (
            what, keys[0] if keys else "-", keys[-1] if keys else "-", len(keys), len(diff),
            (", first %d" % diff[0]) if diff else ""), ok)
        return ok

    def blob_info(self, img, d):
        data = open(img, "rb").read()
        return zlib.crc32(data), len(data)

    def run_case(self, name):
        c = CASES[name]
        img, bs, d = self.image(name, c)
        if img is None:
            self.say("%s: skipped (no game file; --games)" % name)
            return
        base = self.base_args(c, img, bs)
        if c["kind"] == "refuse":
            _, rlog = self.sim(d, base + ["+ssfp=R.csv"], "R.log")
            _, xlog = self.sim(d, base + ["+ssfp=X.csv", "+ss_save=100"], "X.log")
            m = re.search(r"SS save 1 at \d+ ms: +(ok|err), (\d+) clk_sys, frozen in machine frame (\d+) at machine clock (\d+)", xlog)
            self.say("%s X: save %s, frozen at clock %s" % (name, m.group(1) if m else "none", m.group(4) if m else "-"),
                     bool(m) and m.group(1) == "err" and m.group(4) == "0")
            self.compare(self.frames(os.path.join(d, "R.csv")), self.frames(os.path.join(d, "X.csv")), 0,
                         "%s X: the run after the refusal as R" % name)
            return
        # R and S in parallel
        lo, hi = c.get("win", (60, c["ms"] // 2))
        times = sorted(self.rng.sample(range(lo, hi), c["saves"]))
        with cf.ThreadPoolExecutor(2) as ex:
            fr = ex.submit(self.sim, d, base + ["+ssfp=R.csv"], "R.log")
            fs = ex.submit(self.sim, d, base + ["+ssfp=S.csv", "+ss_save=" + ",".join(map(str, times))], "S.log")
            rr, rlog = fr.result()
            sr, slog = fs.result()
        R = self.frames(os.path.join(d, "R.csv"))
        S = self.frames(os.path.join(d, "S.csv"))
        saves = re.findall(r"SS save (\d+) at (\d+) ms: +(ok|err), (\d+) clk_sys, frozen in machine frame (\d+)", slog)
        mts = {}
        for s_ in saves:
            t = os.path.join(d, "ss_save_%s.txt" % s_[0])
            if os.path.exists(t):
                mts[s_[0]] = int(open(t).read().split()[3])
        self.say("%s R: %d frames%s" % (name, len(R), "" if rr == 0 else ", exit %d" % rr), rr == 0 and len(R) > 5)
        self.say("%s S: saves at %s ms: %s" % (name, ",".join(map(str, times)),
                 " ".join("%s(frame %s, %s clk)" % (s[2], s[4], s[3]) for s in saves)),
                 len(saves) == len(times) and all(s[2] == "ok" for s in saves))
        self.compare(R, S, 0, "%s S: every frame as R" % name)
        crc, ln = self.blob_info(img, d)
        blobs = []
        for s in saves:
            b = os.path.join(d, "ss_save_%s.bin" % s[0])
            if not os.path.exists(b):
                continue
            v = subprocess.run([sys.executable, "-I", SSPY, "verify", b, "--cart-crc", str(crc), "--cart-len", str(ln)],
                               capture_output=True, text=True)
            self.say("%s blob %s: %s" % (name, s[0], v.stdout.strip().splitlines()[-1] if v.stdout else "no output"),
                     v.returncode == 0)
            blobs.append((b, int(s[4]), mts.get(s[0], -1)))
        if not blobs:
            return
        # L: the first blob into a core that ran 60 ms; the last into one that ran long past it
        loads = [("L1", blobs[0], 60), ("L2", blobs[-1], max(c["ms"] // 2 + 100, 300))]
        with cf.ThreadPoolExecutor(2) as ex:
            futs = []
            for tag, (b, f0, mt), at in loads:
                futs.append((tag, b, f0, at, ex.submit(self.sim, d, base[:1] + ["+wav=%d" % (c["ms"] + at)] + base[2:] + [
                    "+ssfp=%s.csv" % tag, "+ss_load=%s" % os.path.basename(b), "+ss_load_at=%d" % at,
                    "+ss_load_frame=%d" % f0, "+ss_load_mclk=%d" % mt], "%s.log" % tag)))
            for tag, b, f0, at, fu in futs:
                lr, llog = fu.result()
                m = re.search(r"SS load \S+ at \d+ ms: +(ok|err)", llog)
                self.say("%s %s: %s loaded at %d ms: %s" % (name, tag, os.path.basename(b), at, m.group(1) if m else "none"),
                         bool(m) and m.group(1) == "ok")
                self.compare(R, self.frames(os.path.join(d, "%s.csv" % tag)), f0,
                             "%s %s: frames after the saved one (%d) as R" % (name, tag, f0))
        if c.get("F"):
            self.bad_blobs(name, d, base, blobs[0][0], R)
        if c.get("M"):
            self.menu(name, d, base, R)
        if c.get("W"):
            self.wake(name, d, base, blobs[0], R)

    def bad_blobs(self, name, d, base, good, R):
        blob = bytearray(open(good, "rb").read())
        w = lambda i: struct.unpack(">I", blob[4 * i:4 * i + 4])[0]

        def put(b, i, v):
            b[4 * i:4 * i + 4] = struct.pack(">I", v & 0xFFFFFFFF)

        def fixcrc(b):
            put(b, SS.H["crc"], zlib.crc32(bytes(b[64:SS.W_END * 4])))
        bads = {}
        b = bytearray(blob); b[100] ^= 0x10; bads["payload"] = b
        b = bytearray(blob); put(b, SS.H["crc"], w(SS.H["crc"]) ^ 1); bads["hdrcrc"] = b
        b = bytearray(blob); put(b, SS.H["version"], 2); bads["version"] = b
        b = bytearray(blob); put(b, SS.H["chain_sig"], w(SS.H["chain_sig"]) ^ 0x100); bads["chainsig"] = b
        b = bytearray(blob); put(b, 14, 1); bads["reserved"] = b
        b = bytearray(blob); put(b, SS.W_GAP + 5, 0x55); fixcrc(b); bads["gap"] = b
        b = bytearray(blob); b[SS.W_END * 4 + 8] = 0x77; bads["pastlive"] = b
        b = bytearray(blob); put(b, SS.H["cart_crc"], w(SS.H["cart_crc"]) ^ 0x80000000); bads["foreign"] = b
        b = bytearray(blob); put(b, SS.H["flags"], w(SS.H["flags"]) ^ 1); bads["pal"] = b
        jobs = []
        with cf.ThreadPoolExecutor(2) as ex:
            for k, b in bads.items():
                p = os.path.join(d, "bad_%s.bin" % k)
                open(p, "wb").write(bytes(b))
                jobs.append((k, ex.submit(self.sim, d, base + ["+ssfp=F_%s.csv" % k, "+ss_load=bad_%s.bin" % k,
                                                               "+ss_load_at=80"], "F_%s.log" % k)))
            for k, fu in jobs:
                _, log = fu.result()
                m = re.search(r"SS load \S+ at \d+ ms: +(ok|err)", log)
                self.say("%s F %s: %s" % (name, k, m.group(1) if m else "none"), bool(m) and m.group(1) == "err")
                self.compare(R, self.frames(os.path.join(d, "F_%s.csv" % k)), 0,
                             "%s F %s: the run untouched (every frame as R)" % (name, k))

    def menu(self, name, d, base, R):
        with cf.ThreadPoolExecutor(2) as ex:
            f1 = ex.submit(self.sim, d, base + ["+ssfp=M.csv", "+ss_menu=150:60,400:30"], "M.log")
            f2 = ex.submit(self.sim, d, base + ["+ssfp=M0.csv", "+ss_menu=150:60", "+ss_nopause"], "M0.log")
            _, m1 = f1.result()
            _, m0 = f2.result()
        for tag, log, want in (("M", m1, True), ("M0", m0, False)):
            o = re.findall(r"SS menu open at (\d+) ms \(machine clock (\d+)", log)
            cl = re.findall(r"SS menu closed at (\d+) ms \(machine clock (\d+)", log)
            held = [int(c[1]) - int(o_[1]) for o_, c in zip(o, cl)]
            # held: the machine's clocks while the menu was open (about 0 when it paused)
            ok = bool(held) and all((h < 300000) if want else (h > 400000) for h in held)
            self.say("%s %s: machine clocks while the menu was open %s (%s)" % (
                name, tag, held, "paused" if want else "running"), ok)
            self.compare(R, self.frames(os.path.join(d, "%s.csv" % tag)), 0, "%s %s: every frame as R" % (name, tag))

    def wake(self, name, d, base, blob, R):
        b, f0, mt = blob
        _, log = self.sim(d, base[:1] + ["+wav=900"] + base[2:] + [
            "+ssfp=W.csv", "+ss_load=%s" % os.path.basename(b), "+ss_load_at=60", "+ss_load_reset=0",
            "+ss_load_frame=%d" % f0, "+ss_load_mclk=%d" % mt], "W.log")
        m = re.search(r"SS load in reset: (ok|err)", log)
        a = re.search(r"SS load \S+ (applied|not applied) after the reset's exit", log)
        self.say("%s W: load in reset %s, %s" % (name, m.group(1) if m else "none", a.group(1) if a else "none"),
                 bool(m) and m.group(1) == "ok" and bool(a) and a.group(1) == "applied")
        self.compare(R, self.frames(os.path.join(d, "W.csv")), f0, "%s W: frames after the saved one (%d) as R" % (name, f0))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--work", required=True)
    r.add_argument("--build", action="store_true")
    r.add_argument("--only")
    r.add_argument("--games")
    r.add_argument("--jobs", type=int, default=2)
    r.add_argument("--seed", type=int, default=2600)
    r.add_argument("--vtb")
    sub.add_parser("list")
    a = ap.parse_args()
    if a.cmd == "list":
        for k, c in CASES.items():
            print(k, c["kind"], c["img"])
        return 0
    b = Bench(a)
    os.makedirs(b.work, exist_ok=True)
    if a.build:
        b.build()
    names = a.only.split(",") if a.only else list(CASES)
    with cf.ThreadPoolExecutor(max(1, a.jobs // 2)) as ex:
        list(ex.map(b.run_case, names))
    print("SSBENCH %s (%d failed checks)" % ("pass" if not b.bad else "FAIL", b.bad))
    return 1 if b.bad else 0


if __name__ == "__main__":
    sys.exit(main())
