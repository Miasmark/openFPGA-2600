#!/usr/bin/env python3
"""Synthetic 2600 test cartridges for openFPGA-2600's console tests (no game data).

  console_test.py savekey          4 KiB: the SaveKey round trip on port 2
  console_test.py switches         4 KiB: SWCHB copied to COLUBK, forever
  console_test.py mc SLICE GAMES   a multicart of GAMES games of SLICE KiB
                                   (2, 4 or 8: the MC2K, MC4K and MC8K schemes)
  console_test.py mc-expect SLICE GAMES   the colour and AUDF0 each game sets

savekey: writes 8 bytes ($A5 $5A $01 $02 $80 $7F $FF $00) to the SaveKey's
EEPROM at $1234 over I2C (SDA on PA2, SCL on PA3: port 2, as the wrapper
wires the 24LC256), waits out the write cycle by polling for an acknowledge,
reads them back and plays a TIA tone: AUDF0 = 7 (about 1962 Hz) if all 8
match, AUDF0 = 31 (about 490 Hz) if not, or if the EEPROM never acknowledges
(SaveKey Off). The lines are driven open-drain, as on the real port: SWCHA's
bits stay 0 and SWACNT (the direction register) pulls a line low or lets it
go. Our own routines, written for this test (MIT, as the rest of sim/).

switches: LDA SWCHB / STA COLUBK in a loop, so tb_load's +arprobe prints
every change of the console switches (bit 7 right difficulty, 1 = A; bit 6
left difficulty; bit 3 TV type, 1 = colour; bits 1 and 0 select and reset,
low while pressed) as a COLUBK line.

mc: mapper_MC (banks2600.sv) runs one game of the image at a time and moves
to the next one at each console reset after the first after the load: MC2K
maps game N's 2 KiB at $1000-$17FF and its mirror, MC4K game N's 4 KiB at
$1000-$1FFF, MC8K game N's two 4 KiB banks, bank 1 after a reset and bank 0
after a read of $1FF8 ($1FF9: bank 1). Each game sets its own COLUBK
($12 + $20 * N) and AUDF0 (3 + 4 * N), with a tone, and loops. In MC8K
the game starts in bank 1, whose first instruction reads $1FF8, and runs on
in bank 0; bank 1's own code after that read sets COLUBK $0E and AUDF0 31 (a
bank switch that did not happen).
SPDX-License-Identifier: MIT
"""
import re
import sys

SWCHA, SWACNT, SWCHB = 0x280, 0x281, 0x282
COLUBK, AUDC0, AUDF0, AUDV0 = 0x09, 0x15, 0x17, 0x19

# the instructions these programs use: mnemonic -> {mode: opcode}
OPS = {
    "lda": {"imm": 0xA9, "zp": 0xA5, "abs": 0xAD, "absy": 0xB9},
    "sta": {"zp": 0x85, "abs": 0x8D, "absy": 0x99},
    "ldx": {"imm": 0xA2, "zp": 0xA6}, "stx": {"zp": 0x86}, "ldy": {"imm": 0xA0},
    "cmp": {"imm": 0xC9, "absy": 0xD9}, "cpy": {"imm": 0xC0},
    "and": {"imm": 0x29}, "ora": {"imm": 0x09},
    "asl": {"zp": 0x06}, "rol": {"zp": 0x26}, "dec": {"zp": 0xC6},
    "jsr": {"abs": 0x20}, "jmp": {"abs": 0x4C},
    "bne": {"rel": 0xD0}, "beq": {"rel": 0xF0}, "bcc": {"rel": 0x90}, "bcs": {"rel": 0xB0},
    "bpl": {"rel": 0x10}, "bmi": {"rel": 0x30},
    "rts": {"imp": 0x60}, "sei": {"imp": 0x78}, "cld": {"imp": 0xD8}, "txs": {"imp": 0x9A},
    "inx": {"imp": 0xE8}, "dex": {"imp": 0xCA}, "iny": {"imp": 0xC8}, "dey": {"imp": 0x88},
}
SIZE = {"imm": 2, "zp": 2, "abs": 3, "absy": 3, "rel": 2, "imp": 1}


def assemble(org, src, syms=None):
    """A two-pass assembler for the subset above. One statement per line:
    "label:" (alone or before a statement), "op", "op #n", "op addr",
    "op addr,y", ".byte n,n...";
    numbers are $hex or decimal, addresses may be labels or syms' names;
    ; starts a comment. Zero-page form for numeric addresses below $100."""
    syms = dict(syms or {})
    stmts = []
    for raw in src.strip().splitlines():
        line = raw.split(";")[0].strip()
        if not line:
            continue
        m = re.match(r"(\w+):\s*", line)
        if m:
            stmts.append(("label", m.group(1)))
            line = line[m.end():]
            if not line:
                continue
        if line.startswith(".byte"):
            stmts.append(("byte", [x.strip() for x in line[5:].split(",")]))
            continue
        op, _, arg = line.partition(" ")
        stmts.append(("op", op.lower(), arg.strip()))

    def val(s, labels):
        s = s.strip()
        if s.startswith("$"):
            return int(s[1:], 16)
        if s.isdigit():
            return int(s)
        if s in syms:
            return syms[s]
        return labels[s]

    def mode(op, arg):
        if not arg:
            return "imp"
        if "rel" in OPS[op]:
            return "rel"
        if arg.startswith("#"):
            return "imm"
        if arg.lower().endswith(",y"):
            return "absy"
        a = arg.strip()
        if (a.startswith("$") and int(a[1:], 16) < 0x100 or a.isdigit() and int(a) < 0x100 or
                a in syms and syms[a] < 0x100) and "zp" in OPS[op]:
            return "zp"
        return "abs"

    labels, out = {}, bytearray()
    for pass_ in (0, 1):
        pc, out = org, bytearray()
        for s in stmts:
            if s[0] == "label":
                labels[s[1]] = pc
            elif s[0] == "byte":
                b = [val(x, labels) for x in s[1]] if pass_ else [0] * len(s[1])
                out += bytes(b)
                pc += len(s[1])
            else:
                op, arg = s[1], s[2]
                md = mode(op, arg)
                code = OPS[op][md]
                if pass_:
                    out.append(code)
                    if md == "imm":
                        out.append(val(arg[1:], labels) & 0xFF)
                    elif md == "zp":
                        out.append(val(arg, labels))
                    elif md in ("abs", "absy"):
                        a = val(arg[:-2] if md == "absy" else arg, labels)
                        out += bytes([a & 0xFF, a >> 8])
                    elif md == "rel":
                        off = val(arg, labels) - (pc + 2)
                        assert -128 <= off < 128, f"branch to {arg} out of range ({off})"
                        out.append(off & 0xFF)
                pc += SIZE[md]
    return bytes(out), labels


def image(size, org, code, entry=None):
    """code at the start of a size-byte slice that the CPU sees at org; every
    vector points to entry (default org)."""
    img = bytearray([0xFF] * size)
    img[:len(code)] = code
    e = org if entry is None else entry
    for v in (size - 6, size - 4, size - 2):
        img[v], img[v + 1] = e & 0xFF, e >> 8
    return img


SAVEKEY = """
reset:  sei
        cld
        ldx #$FF
        txs
        lda #0
        sta SWCHA               ; the two lines read 0 whenever driven
        sta SWACNT              ; both released: the bus idle
        sta AUDV0
; write the 8 bytes at $1234
        jsr start
        lda #$A0                ; device 0, write
        jsr tx
        bcc w1
        jmp fail                ; no acknowledge: no SaveKey
w1:     lda #$12
        jsr tx
        lda #$34
        jsr tx
        ldy #0
wr:     lda pattern,y
        jsr tx
        iny
        cpy #8
        bne wr
        jsr stop
; the write cycle: the EEPROM acknowledges again once it is done
        lda #0
        sta $82
poll:   jsr start
        lda #$A0
        jsr tx
        bcc ready
        jsr stop
        dec $82
        bne poll
        jmp fail
; read them back: the address, a repeated start, then 8 bytes
ready:  lda #$12
        jsr tx
        lda #$34
        jsr tx
        jsr start
        lda #$A1                ; device 0, read
        jsr tx
        bcc r0
        jmp fail
r0:     ldy #0
rd:     ldx #0
        cpy #7
        bne r1
        inx                     ; the last byte: no acknowledge
r1:     stx $83
        jsr rx
        sta $90,y
        iny
        cpy #8
        bne rd
        jsr stop
        ldy #7
cmp:    lda $90,y
        cmp pattern,y
        bne fail
        dey
        bpl cmp
        lda #7                  ; pass: 1962 Hz
        bne tone
fail:   lda #31                 ; fail: 490 Hz
tone:   sta AUDF0
        lda #4
        sta AUDC0
        lda #15
        sta AUDV0
idle:   jmp idle

; SWACNT: bit 3 pulls SCL low, bit 2 pulls SDA low
start:  lda #$08                ; SCL low, SDA released
        sta SWACNT
        lda #$00                ; SCL high
        sta SWACNT
        lda #$04                ; SDA falls while SCL is high: START
        sta SWACNT
        lda #$0C                ; SCL low
        sta SWACNT
        rts
stop:   lda #$0C                ; SCL low, SDA low
        sta SWACNT
        lda #$04                ; SCL high
        sta SWACNT
        lda #$00                ; SDA rises while SCL is high: STOP
        sta SWACNT
        rts
; tx: send A, MSB first; carry = the receiver's NACK
tx:     sta $80
        ldx #8
txb:    asl $80
        lda #$0C                ; a 0: SDA low
        bcc txd
        lda #$08                ; a 1: SDA released
txd:    sta SWACNT              ; data with SCL low
        and #$04
        sta SWACNT              ; SCL high
        ora #$08
        sta SWACNT              ; SCL low
        dex
        bne txb
        lda #$08                ; release SDA for the acknowledge
        sta SWACNT
        lda #$00
        sta SWACNT              ; SCL high
        lda SWCHA
        and #$04
        cmp #$04                ; carry set: SDA high, no acknowledge
        lda #$08
        sta SWACNT              ; SCL low
        rts
; rx: receive a byte into A; $83 = 0 acknowledges it, 1 does not
rx:     lda #$08                ; SDA released, SCL low
        sta SWACNT
        ldx #8
rxb:    lda #$00
        sta SWACNT              ; SCL high
        lda SWCHA
        and #$04
        cmp #$04                ; carry = SDA
        rol $80
        lda #$08
        sta SWACNT              ; SCL low
        dex
        bne rxb
        lda #$0C                ; acknowledge: SDA low
        ldx $83
        beq rxa
        lda #$08                ; no acknowledge: SDA released
rxa:    sta SWACNT
        and #$04
        sta SWACNT              ; SCL high
        ora #$08
        sta SWACNT              ; SCL low
        lda #$08
        sta SWACNT              ; SDA released
        lda $80
        rts
pattern:
        .byte $A5, $5A, $01, $02, $80, $7F, $FF, $00
"""

SWITCHES = """
reset:  sei
        cld
        ldx #$FF
        txs
loop:   lda SWCHB
        sta COLUBK
        jmp loop
"""

SYMS = {"SWCHA": SWCHA, "SWACNT": SWACNT, "SWCHB": SWCHB, "COLUBK": COLUBK,
        "AUDC0": AUDC0, "AUDF0": AUDF0, "AUDV0": AUDV0}


def game(n):
    """What game n sets: its COLUBK and AUDF0."""
    return 0x12 + 0x20 * n, 3 + 4 * n


def game_src(n, prefix=""):
    c, f = game(n)
    return f"""
        lda #${c:02X}
        sta COLUBK
        lda #{f}
        sta AUDF0
        lda #4
        sta AUDC0
        lda #15
        sta AUDV0
{prefix}spin:   jmp {prefix}spin
"""


def multicart(slice_kb, games):
    out = bytearray()
    for n in range(games):
        if slice_kb in (2, 4):
            size = slice_kb * 1024
            code, _ = assemble(0xF000, "reset: sei\n cld\n ldx #$FF\n txs\n" + game_src(n), SYMS)
            out += image(size, 0xF000, code)
        else:
            # bank 1 (the slice's upper 4 KiB) after a reset: read $1FF8, so
            # bank 0 runs on from the next instruction; bank 1's own code
            # after that read marks a switch that did not happen
            head = "reset: sei\n cld\n ldx #$FF\n txs\n lda $FFF8\n"
            b0, _ = assemble(0xF000, head + game_src(n), SYMS)
            b1, _ = assemble(0xF000, head + """
        lda #$0E
        sta COLUBK
        lda #31
        sta AUDF0
        lda #4
        sta AUDC0
        lda #15
        sta AUDV0
spin:   jmp spin
""", SYMS)
            out += image(4096, 0xF000, b0) + image(4096, 0xF000, b1)
    return bytes(out)


def main():
    a = sys.argv[1:]
    if a == ["savekey"]:
        code, _ = assemble(0xF000, SAVEKEY, SYMS)
        sys.stdout.buffer.write(image(4096, 0xF000, code))
    elif a == ["switches"]:
        code, _ = assemble(0xF000, SWITCHES, SYMS)
        sys.stdout.buffer.write(image(4096, 0xF000, code))
    elif len(a) == 3 and a[0] == "mc" and a[1] in ("2", "4", "8"):
        sys.stdout.buffer.write(multicart(int(a[1]), int(a[2])))
    elif len(a) == 3 and a[0] == "mc-expect":
        for n in range(int(a[2])):
            c, f = game(n)
            print(f"game {n}: COLUBK ${c:02x} AUDF0 {f}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
