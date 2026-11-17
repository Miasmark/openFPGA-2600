#!/usr/bin/env python3
"""Save-state test images for the bank-switching schemes whose 4 KiB window
switches whole (our own program, no game data), to stdout:

  ss_mapper_test.py SCHEME > image.bin      (prints its +bs= index on stderr)

SCHEME: f8 f6 f4 f0 ef df sb ua jane 0840. Every bank holds the same program
(sim/ssprobe_test.py's frame: all five objects moving, sound, colours, the
collision latches into RAM) and its own data at $FE00-$FE1F: an id byte and
a 16-byte playfield table. Each frame the program selects a bank from the
frame counter by the scheme's hotspot (twice: in VBLANK and on the middle
line), stores the bank's id in RAM ($85, $86), and draws the bank's table
as the playfield, so the picture, RAM and bus show which bank is in at
every moment and a bank register lost or corrupted by a save or load shows
within a frame. Used by sim/ss_bench.py (docs/SAVESTATE.md 7).
"""
import sys

T = dict(VSYNC=0x00, VBLANK=0x01, WSYNC=0x02, NUSIZ0=0x04, NUSIZ1=0x05,
         COLUP0=0x06, COLUP1=0x07, COLUPF=0x08, COLUBK=0x09, CTRLPF=0x0A,
         REFP0=0x0B, REFP1=0x0C, PF0=0x0D, PF1=0x0E, PF2=0x0F, RESP0=0x10,
         RESP1=0x11, RESM0=0x12, RESM1=0x13, RESBL=0x14, AUDC0=0x15,
         AUDC1=0x16, AUDF0=0x17, AUDF1=0x18, AUDV0=0x19, AUDV1=0x1A,
         GRP0=0x1B, GRP1=0x1C, ENAM0=0x1D, ENAM1=0x1E, ENABL=0x1F, HMP0=0x20,
         HMP1=0x21, HMM0=0x22, HMM1=0x23, HMBL=0x24, VDELP0=0x25, HMOVE=0x2A,
         CXCLR=0x2C, CXM0P=0x00, CXP0FB=0x02, CXPPMM=0x07)
INTIM, TIM64T = 0x284, 0x296
FRM, CX1, CX2, CX3, RND, ID1, ID2 = 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86

# scheme: (banks, bss_type index, how a bank is selected)
#   ("idx", base): LDA base,X with X = the bank (contiguous hotspots)
#   ("inc", hot):  LDA hot steps to the next bank (F0)
#   ("ua",):       $0220 bank 0, $0240 bank 1
#   ("x40",):      LDA $0800,X with X = bank * $40 (0840)
#   ("jane",):     $FFF0, $FFF1, $FFF8, $FFF9
SCHEMES = {
    "f8":   (2, 1, ("idx", 0xFFF8)),
    "f6":   (4, 2, ("idx", 0xFFF6)),
    "f4":   (8, 6, ("idx", 0xFFF4)),
    "f0":   (16, 13, ("inc", 0xFFF0)),
    "ef":   (16, 19, ("idx", 0xFFE0)),
    "df":   (32, 28, ("idx", 0xFFC0)),
    "sb":   (16, 17, ("idx", 0x0800)),
    "ua":   (2, 11, ("ua",)),
    "jane": (4, 20, ("jane",)),
    "0840": (2, 26, ("x40",)),
}


def build(scheme):
    nb, bs, how = SCHEMES[scheme]
    prog = []

    def op(*b): prog.extend(b)
    def lda_i(v): op(0xA9, v)
    def lda_z(a): op(0xA5, a)
    def sta_z(a): op(0x85, a)
    def sta_a(a): op(0x8D, a & 0xFF, a >> 8)
    def lda_a(a): op(0xAD, a & 0xFF, a >> 8)
    def lda_ax(a): op(0xBD, a & 0xFF, a >> 8)
    def label(n): prog.append(("label", n))
    def bne(n): prog.extend([0xD0, ("rel", n)])
    def bcc(n): prog.extend([0x90, ("rel", n)])
    def jmp(n): prog.extend([0x4C, ("abs", n)])
    NOP, TXA, TAX, LSR, ASL, ROL, CLC, DEX, PHA, PLA = 0xEA, 0x8A, 0xAA, 0x4A, 0x0A, 0x2A, 0x18, 0xCA, 0x48, 0x68
    cnt = [0]

    def select(src):
        """select a bank from A (src: the value, masked to the bank count)"""
        cnt[0] += 1
        k = cnt[0]
        op(0x29, nb - 1)                               # AND #banks-1
        if how[0] == "idx":
            op(TAX); lda_ax(how[1])
        elif how[0] == "inc":
            lda_a(how[1])
        elif how[0] == "ua":
            # X = 0: LDA $0220; X = 1: LDA $0221 (no hotspot), then LDA $023F,X reads $0240
            op(TAX); lda_ax(0x0220)
            op(0xE0, 0x00); prog.extend([0xF0, ("rel", "ua%d" % k)])
            lda_ax(0x023F)
            label("ua%d" % k)
        elif how[0] == "x40":
            op(LSR, 0x6A, 0x6A)                        # LSR ROR ROR: bit 0 -> bit 6
            op(TAX); lda_ax(0x0800)
        elif how[0] == "jane":
            op(0xC9, 0x02)                             # CMP #2
            op(TAX)
            bcc("jlo%d" % k)
            lda_ax(0xFFF6)                             # X = 2, 3: $FFF8, $FFF9
            jmp("jdone%d" % k)
            label("jlo%d" % k)
            lda_ax(0xFFF0)                             # X = 0, 1
            label("jdone%d" % k)

    label("start")
    op(0x78, 0xD8, 0xA2, 0xFF, 0x9A, 0xA9, 0x00)
    label("clr")
    op(0x95, 0x00, DEX)
    bne("clr")
    sta_z(T["WSYNC"])
    op(NOP, NOP, NOP, NOP, NOP)
    sta_z(T["RESP0"]); op(NOP, NOP, NOP)
    sta_z(T["RESM0"]); op(NOP)
    sta_z(T["RESP1"]); op(NOP, NOP)
    sta_z(T["RESM1"]); sta_z(T["RESBL"])
    lda_i(0x21); sta_z(T["CTRLPF"])
    lda_i(0x25); sta_z(T["NUSIZ0"])
    lda_i(0x37); sta_z(RND)

    label("frame")
    lda_i(2); sta_z(T["WSYNC"]); sta_z(T["VSYNC"])
    sta_z(T["WSYNC"]); sta_z(T["WSYNC"]); sta_z(T["WSYNC"])
    lda_i(0); sta_z(T["VSYNC"])
    lda_i(43); sta_a(TIM64T)
    op(0xE6, FRM)
    lda_z(FRM); select("frame")                        # the frame's bank
    lda_a(0xFE00); sta_z(ID1); sta_z(T["COLUPF"])
    lda_z(FRM); op(0x29, 0x1F); sta_z(T["AUDF0"])
    lda_z(FRM); op(LSR, LSR, LSR, LSR, 0x29, 0x0F); sta_z(T["AUDC0"])
    lda_i(0x0A); sta_z(T["AUDV0"])
    lda_z(ID1); op(LSR); sta_z(T["AUDF1"])
    lda_i(8); sta_z(T["AUDC1"]); lda_i(5); sta_z(T["AUDV1"])
    lda_z(FRM); sta_z(T["COLUP0"]); op(ASL); sta_z(T["COLUP1"])
    lda_z(FRM); op(LSR, LSR, 0x29, 0x0E); sta_z(T["COLUBK"])
    lda_z(FRM); op(0x29, 0x07); sta_z(T["NUSIZ1"])
    lda_i(0x10); sta_z(T["HMP0"]); lda_i(0xF0); sta_z(T["HMP1"])
    lda_i(0x20); sta_z(T["HMM0"]); lda_i(0xE0); sta_z(T["HMM1"])
    lda_i(0x30); sta_z(T["HMBL"])
    sta_z(T["WSYNC"]); sta_z(T["HMOVE"])
    lda_z(T["CXP0FB"]); sta_z(CX1)
    lda_z(T["CXPPMM"]); sta_z(CX2)
    lda_z(T["CXM0P"]); op(0x45, CX1); sta_z(CX3)
    sta_z(T["CXCLR"])
    lda_z(RND); op(ASL, ASL, CLC, 0x65, RND, 0x69, 0x01); sta_z(RND)
    label("w1")
    lda_a(INTIM)
    bne("w1")
    sta_z(T["WSYNC"]); lda_i(0); sta_z(T["VBLANK"])
    op(0xA2, 192)
    label("line")
    sta_z(T["WSYNC"])
    op(TXA, 0x45, FRM); sta_z(T["GRP0"])
    op(TXA, 0x65, RND); sta_z(T["GRP1"])
    # the bank's playfield table: PF2 = table[X & 15]
    op(TXA, 0x29, 0x0F, 0xA8)                          # TXA AND #15 TAY
    op(0xB9, 0x10, 0xFE); sta_z(T["PF2"])              # LDA $FE10,Y
    op(TXA, 0x45, RND); sta_z(T["PF1"])
    op(0xE0, 96)                                       # CPX #96: mid-frame, another bank
    bne("nomid")
    op(TXA, PHA)
    lda_z(RND); select("mid")
    lda_a(0xFE00); sta_z(ID2)
    op(PLA, TAX)
    label("nomid")
    op(DEX)
    bne("line")
    lda_i(2); sta_z(T["VBLANK"])
    lda_i(35); sta_a(TIM64T)
    label("w2")
    lda_a(INTIM)
    bne("w2")
    jmp("frame")

    ORG = 0xF000
    labels, pc = {}, ORG
    for it in prog:
        if isinstance(it, tuple) and it[0] == "label":
            labels[it[1]] = pc
        else:
            pc += 2 if isinstance(it, tuple) and it[0] == "abs" else 1
    out, pc = [], ORG
    for it in prog:
        if isinstance(it, int):
            out.append(it); pc += 1
        elif it[0] == "label":
            continue
        elif it[0] == "abs":
            a = labels[it[1]]; out += [a & 0xFF, a >> 8]; pc += 2
        elif it[0] == "rel":
            d = labels[it[1]] - (pc + 1)
            assert -128 <= d <= 127, it
            out.append(d & 0xFF); pc += 1
    assert len(out) < 0xE00, len(out)
    img = bytearray()
    for b in range(nb):
        bank = bytearray([0xEA] * 4096)
        bank[:len(out)] = bytes(out)
        bank[0xE00] = (b * 17 + 3) & 0xFF
        for i in range(16):
            bank[0xE10 + i] = ((b + 1) * (i * 37 + 11)) & 0xFF
        start = labels["start"]
        for v in (0xFFFA, 0xFFFC, 0xFFFE):
            bank[v - ORG] = start & 0xFF
            bank[v - ORG + 1] = start >> 8
        img += bank
    return bytes(img), bs


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in SCHEMES:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    img, bs = build(sys.argv[1])
    sys.stdout.buffer.write(img)
    print(bs, file=sys.stderr)


if __name__ == "__main__":
    main()
