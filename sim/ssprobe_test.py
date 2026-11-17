#!/usr/bin/env python3
"""Emit the save-state probe's 2600 test image (4 KiB binary, to stdout):
our own program, no game data. Every frame changes as much machine state as
it can cheaply, so that a scan-chain bit lost or corrupted shows in the
picture, the sound, the RIOT RAM or the CPU's bus within a few frames:
  - an NTSC frame (3 VSYNC, VBLANK by TIM64T, 192 visible, overscan by TIM64T);
  - the frame counter ($80) drives AUDF0/AUDC0 (tone and poly modes), AUDF1
    with the noise mode, all four colours, NUSIZ1, VDELP0, REFP1;
  - all five objects move every frame (HMxx + HMOVE), their graphics and the
    playfield change per line from the line counter, the frame counter and a
    pseudo-random byte ($84, x5+1 per frame);
  - the collision latches are read into RAM ($81-$83) and cleared each frame.
The 6507 runs the visible lines from WSYNC, so the RDY halt is exercised on
every line. Used by sim/tb_ssprobe.sv (tools/ssprobe).
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
FRM, CX1, CX2, CX3, RND = 0x80, 0x81, 0x82, 0x83, 0x84

prog = []


def op(*b):
    prog.extend(b)


def lda_i(v): op(0xA9, v)
def lda_z(a): op(0xA5, a)
def sta_z(a): op(0x85, a)
def sta_a(a): op(0x8D, a & 0xFF, a >> 8)
def lda_a(a): op(0xAD, a & 0xFF, a >> 8)
def label(n): prog.append(("label", n))
def bne(n): prog.extend([0xD0, ("rel", n)])
def jmp(n): prog.extend([0x4C, ("abs", n)])


NOP, TXA, LSR, ASL, ROL, CLC, DEX = 0xEA, 0x8A, 0x4A, 0x0A, 0x2A, 0x18, 0xCA

label("start")
op(0x78, 0xD8, 0xA2, 0xFF, 0x9A, 0xA9, 0x00)        # SEI CLD LDX #$FF TXS LDA #0
label("clr")
op(0x95, 0x00, DEX)                                  # STA $00,X DEX
bne("clr")
sta_z(T["WSYNC"])
op(NOP, NOP, NOP, NOP, NOP)
sta_z(T["RESP0"]); op(NOP, NOP, NOP)
sta_z(T["RESM0"]); op(NOP)
sta_z(T["RESP1"]); op(NOP, NOP)
sta_z(T["RESM1"]); sta_z(T["RESBL"])
lda_i(0x21); sta_z(T["CTRLPF"])                      # ball 4 wide, reflected playfield
lda_i(0x25); sta_z(T["NUSIZ0"])                      # missile 4 wide, player quad
lda_i(0x37); sta_z(RND)

label("frame")
lda_i(2); sta_z(T["WSYNC"]); sta_z(T["VSYNC"])
sta_z(T["WSYNC"]); sta_z(T["WSYNC"]); sta_z(T["WSYNC"])
lda_i(0); sta_z(T["VSYNC"])
lda_i(43); sta_a(TIM64T)
op(0xE6, FRM)                                        # INC frame
lda_z(FRM); op(0x29, 0x1F); sta_z(T["AUDF0"])
lda_z(FRM); op(LSR, LSR, LSR, LSR, 0x29, 0x0F); sta_z(T["AUDC0"])
lda_i(0x0A); sta_z(T["AUDV0"])
lda_z(FRM); op(LSR); sta_z(T["AUDF1"])
lda_i(8); sta_z(T["AUDC1"]); lda_i(5); sta_z(T["AUDV1"])
lda_z(FRM); sta_z(T["COLUP0"]); op(ASL); sta_z(T["COLUP1"])
op(0x49, 0x5A); sta_z(T["COLUPF"])
lda_z(FRM); op(LSR, LSR, 0x29, 0x0E); sta_z(T["COLUBK"])
lda_z(FRM); op(0x29, 0x07); sta_z(T["NUSIZ1"])
lda_z(FRM); op(LSR, LSR, LSR); sta_z(T["VDELP0"])
lda_z(FRM); sta_z(T["REFP1"])
lda_i(0x10); sta_z(T["HMP0"]); lda_i(0xF0); sta_z(T["HMP1"])
lda_i(0x20); sta_z(T["HMM0"]); lda_i(0xE0); sta_z(T["HMM1"])
lda_i(0x30); sta_z(T["HMBL"])
sta_z(T["WSYNC"]); sta_z(T["HMOVE"])
lda_z(T["CXP0FB"]); sta_z(CX1)
lda_z(T["CXPPMM"]); sta_z(CX2)
lda_z(T["CXM0P"]); op(0x45, CX1); sta_z(CX3)       # EOR $81
sta_z(T["CXCLR"])
lda_z(RND); op(ASL, ASL, CLC, 0x65, RND, 0x69, 0x01); sta_z(RND)   # RND = RND*5+1
label("w1")
lda_a(INTIM)
bne("w1")
sta_z(T["WSYNC"]); lda_i(0); sta_z(T["VBLANK"])
op(0xA2, 192)                                        # LDX #192
label("line")
sta_z(T["WSYNC"])
op(TXA, 0x45, FRM); sta_z(T["GRP0"])                 # TXA EOR frame
op(TXA, 0x65, RND); sta_z(T["GRP1"])                 # TXA ADC rnd
op(TXA, LSR); sta_z(T["ENAM0"]); op(LSR); sta_z(T["ENAM1"]); sta_z(T["ENABL"])
op(TXA, 0x45, RND); sta_z(T["PF1"]); sta_z(T["PF2"]); op(ROL); sta_z(T["PF0"])
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
    elif it[0] == "abs":
        a = labels[it[1]]; out += [a & 0xFF, a >> 8]; pc += 2
    elif it[0] == "rel":
        d = labels[it[1]] - (pc + 1)
        assert -128 <= d <= 127, it
        out.append(d & 0xFF); pc += 1
img = bytearray([0xEA] * 4096)
img[:len(out)] = bytes(out)
start = labels["start"]
for v in (0xFFFA, 0xFFFC, 0xFFFE):
    img[v - ORG] = start & 0xFF
    img[v - ORG + 1] = start >> 8
sys.stdout.buffer.write(bytes(img))
