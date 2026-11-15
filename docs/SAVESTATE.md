# Save states

The Pocket's save states (Memories), sleep and a menu pause for the 2600
core. This page is how the core does it as built. The design study
(`SAVESTATE_SCOPE.md`, outside the repository) chose the approach and the
owner approved its recommendations: a scan chain through every state
flip-flop, a freeze at a frame boundary, block-RAM staging, and the
Intellivision core's protocol, header and benches (openFPGA-Intellivision
`docs/SAVESTATE.md`, our own MIT code).

| Part | File |
|---|---|
| The controller (ss_ctl) and the substitute raster | `src/fpga/core/ss_ctl.sv` |
| The blob's layout, written down once | `tools/savestate/savestate.py`, which generates `src/fpga/core/ss_pkg.sv` and the tables below |
| The scan chain in the vendored files | `tools/savestate/scan_insert.py`, run by `tools/savestate/apply.sh` |
| The chain in our own modules | `paddle_timer4.sv`, `virtual_axis5.sv`, `atarivox/*.sv`, `atari2600_pocket.sv` (by hand) |
| The hookup, the hold rule, the cartridge CRC | `atari2600_pocket.sv` ("SAVE STATES" and the `ss hold` lines), `core_top.v` |
| The Pocket's side in the benches | `sim/tb_load.sv` (`+ss_*`) |

## 1 The Pocket's side

| Command | What the core does |
|---|---|
| 0x00A0 save (bit 0 of the parameter: start; else a query) | freeze at the next frame boundary, write the blob into its staging RAM, answer ok, resume; the host then reads 131,072 bytes from 0x50000000 |
| 0x00A4 load | the host has already written the blob to 0x50000000; freeze, check it, write it into the machine (or refuse it), answer ok or err, resume |
| 0x00B0 menu open / closed | with Pause in Menu on (the default), the machine is frozen while the menu is open |
| sleep (`sleep_supported: true` in core.json) | a save before sleep and a load on wake |

- **The result codes** come from the template's `core_bridge_cmd.v`: 0 idle,
  1 busy, 2 ok, 3 error. ok and err stay up until the next save or load
  starts. ss_ctl changes its status bits one at a time, 4 clk_sys apart, in
  the Intellivision core's order (busy rises, then ok and err clear, then
  ack; at the end ok or err rises, then busy drops), so the host never reads
  a wrong code through the clock crossing.
- **The blob over the bridge.** Reads are one word behind (the template's
  rule): a read's word is on `bridge_rd_data` from the clock after its
  `bridge_rd` until the next read. The staging RAM has a port on each
  clock, so the bridge reads and writes it directly on clk_74a; no access
  waits for the machine.
- **Pause in Menu** is bit 1 of the Controllers item (0x10000260; bit 0 is
  Swap Controllers): Normal, Swapped, and the same with "no menu pause".
  The menu has room for 16 items and had 16, so the setting shares an item;
  Normal (0) is Pause in Menu on, as the owner chose, and a Pocket that kept
  the old Swap Controllers value (0 or 1) keeps its swap and gets the pause.
- **Wake.** Analogue's documents do not say in what order the Pocket sends
  the load and releases the core's reset on wake. A load asked for while the
  console is held in reset is checked at once, without a freeze, and
  answered ok or err; an ok one is staged and applied at the first frame
  boundary after the reset's exit (checked once more, with no status
  change). A load asked for after the reset's exit is the ordinary one.

## 2 Freezing

### 2.1 The freeze point

The scan chain captures every flip-flop of the machine, so the machine's
state would be complete at any clk_sys. What it cannot capture is outside
it: an SRAM or SDRAM access in flight, a SaveKey RAM request, an FA2 flash
copy, a phrase the AtariVox is speaking. ss_ctl freezes (`frz`, the chain's
`ss_frz`) on the first clock with all of:

- the console out of reset, a cartridge loaded (its CRC32 known);
- **a frame boundary:** the first CPU cycle (the 6507's phi1 enable,
  `cpu_ce`) after the machine's VSync rose. With no VSync for 4 periods of
  2^18 clk_sys (about 73 ms: a program that never writes VSYNC) the next CPU
  cycle will do;
- **quiet peripherals:** no SaveKey RAM access pending (`sk_pend`, the
  EEPROM's request lines), no FA2 flash copy (no request for 8 clocks), and
  the AtariVox silent (`atarivox.sv`'s `quiet`: nothing coming in or waiting
  and the voice's sample 0 for 0.25 s).

A save or load that finds no such clock in 128 periods (2.3 s: the AtariVox
speaking all that time) ends with err and leaves the machine untouched.

### 2.2 While frozen

- **The picture.** The Pocket's sync comes straight from the TIA, so a
  frozen machine would stop it. `ss_raster` (in `ss_ctl.sv`) learns the
  picture's raster while the machine runs (line length, HSync and HBlank,
  frame length, VSync and VBlank, the pixel strobe's phase) and continues it
  while frozen, with a black picture. The machine resumes on the clock the
  substitute raster comes back to the position where the picture stopped
  (`resume_ok`), so the Pocket sees regular frames throughout, and a load
  resumes into a frame of about the usual length (both are taken at a frame
  boundary).
- **The sound** holds its last sample and goes on from it.
- **The hold rule.** While frozen or shifting (`ss_hold`) every flip-flop of
  the chain holds or shifts, and what the machine drives into logic outside
  the chain is gated: the cartridge's bus enables and reset in `top.sv` (so
  no mapper, the unchained Supercharger included, sees a bus cycle), the
  RIOT RAM's and the FA2 work RAM's write ports, the SDRAM read request
  (only while the chain shifts: the machine's pending read is served again
  before it resumes), the SRAM cartridge port (the same, or ss_ctl's while
  it copies the cartridge RAM), the Flicker Blend frame's writes, the
  SaveKey's and the FA2 flash's requests, DARIA's bus snoop, reset and
  pause, the region logic (`tia_pal_seen`, `region_pll`: no PLL retune), the
  TV Type toggle, the turbo counter, and the scaler slot (`video_pal_o`).
- **Block RAM read registers.** A block RAM's output register is not in the
  chain: it reloads on every clock from its address. After a load ss_ctl
  keeps the machine frozen 32 clocks more, with its ports released, so
  every RAM reads at the machine's own (restored) address before it runs.
  The AtariVox engine's RAMs change address on every clock, so the engine
  keeps the address of the last clock it ran (`a_irom`, `a_drom`, `a_rfa`,
  `a_rfb`, in the chain) and its RAMs read there while it is held: their
  output registers hold exactly what they held, after a load too.

### 2.3 Save and load

- **Save:** freeze; settle 8 clk_sys; the chain shifted out word by word
  with its output fed back to its input (after `SS_CHAIN_BITS` clocks every
  flip-flop holds what it held), then the RIOT RAM, the FA2 work RAM and the
  AtariVox register file through their state ports (`ss_ram`: the RIOT
  RAM's port B, which only the power-up walk used; the FA2 work RAM's and the
  register file's only port, muxed while frozen), then the cartridge RAM
  through the SRAM's cartridge port (6 clk_sys a byte), each word into the
  staging RAM with the payload's CRC32; then the header. About 20 ms.
- **Load:** freeze; check the header and the payload (section 4); then the
  chain shifted in, the RAMs and the cartridge RAM written. A refused blob
  ends with err and the machine resumes untouched. About 30 ms.

## 3 The blob

131,072 bytes, 32-bit words, big-endian (the bridge's byte order). The live
part (bytes 0-36,863) is staged in block RAM (9,216 words); the rest reads
0. CRC32s are zlib's.

<!-- BEGIN GENERATED by tools/savestate/savestate.py gen: do not edit -->

Header (bytes 0-63, 32-bit words, big-endian):

| Word | Byte | Field | Value |
|---|---|---|---|
| 0 | 0 | magic | $41323653 "A26S" |
| 1 | 4 | version | format version (1) |
| 2 | 8 | size | blob size in bytes (131072) |
| 3 | 12 | length | payload bytes from byte 64 (36800) |
| 4 | 16 | cart_crc | the cartridge image's CRC32 (zlib's, over every byte the loader took) |
| 5 | 20 | cart_len | the image's length in bytes |
| 6 | 24 | mapper | bits 5-0 the scheme the core runs (run_bs), 8 Superchip, 14-12 detect2600's revision |
| 7 | 28 | flags | bit 0 PAL (checked), 1 SaveKey on, 2 AtariVox on, 6-4 Port 1 Input, 10-8 Port 2 Input, 16 the Mapper menu forced the scheme (not checked) |
| 8 | 32 | crc | CRC32 of the payload (bytes 64 .. 36863) |
| 9 | 36 | chain_bits | the scan chain's length in bits |
| 10 | 40 | chain_sig | the chain signature (savestate.py sig): a blob of another chain is refused |
| 11 | 44 | cram_bytes | cartridge RAM bytes in the blob (32768) |
| 12 | 48 | ar_crc | the Supercharger BIOS's CRC32 (0: v1 refuses the Supercharger) |
| 13 | 52 | daria | DARIA's scheme and RAM size (0: v1 refuses the ARM cartridges) |
| 14 | 56 | reserved | 0 |
| 15 | 60 | reserved | 0 |

Payload:

| Bytes | Words | Part |
|---|---|---|
| 64-447 | 16-111 | the scan chain: 3053 bits (signature $1B18D91B), 96 words, the first bit out in bit 31 of word 16; the last word's bits past the chain 0 |
| 448-2047 | 112-511 | 0 |
| 2048-2175 | 512-543 | RIOT RAM, 128 bytes, four a word (the first in bits 31-24) |
| 2176-2431 | 544-607 | FA2 work RAM, 256 bytes, as the RIOT RAM |
| 2432-3455 | 608-863 | AtariVox register file, 256 words |
| 3456-4095 | 864-1023 | 0 |
| 4096-36863 | 1024-9215 | cartridge RAM: the SRAM's cartridge area, bytes 0-32767, as the RIOT RAM |
| 36864-131071 | | not stored: read as 0, and a load refuses a blob with anything else written there |

The chain's hand-made segments, after the machine's (in chain order):

| Module | Bits | Registers |
|---|---|---|
| paddle_timer4 | 696 | {cc, old_clear, pv}, then per paddle {high_count, lowest, highest, difference, m, read_count, chg, cleared, lgh, pend} |
| virtual_axis5 | 245 | slot, per axis {pos16, vel, analog_on, rest, rest_valid}, axes 0-1 phase |
| lightgun |  | (generated: lightgun.sv) |
| EEPROM_24LC0X |  | (generated: EEPROM_24LC256.sv, the SaveKey's bus state) |
| atarivox | 235 | div; avox_rx {sync, cnt, bitn, sh, got, got_byte}, {abort_set, ready_set, scp, esc}, {wp, rp, count}; avox_engine's 130 bits and its RAMs' 38 address bits |
| atari2600_pocket | 15 | {ms_div, ms_tick}: the virtual axes' 1 kHz tick |

<!-- END GENERATED -->

## 4 Loading: what is checked

Nothing is written into the machine until all of this holds; otherwise the
answer is err and the machine resumes where it was, untouched:

1. the header: magic, version, size, payload length, the cartridge image's
   CRC32 and length (a state of another game is refused), the mapper word
   (the scheme the core runs, the Superchip, detect2600's revision), the PAL
   flag (a retune would reset the console), the chain's length and
   signature (a blob of a build with another chain is refused), the
   cartridge RAM size, and the words that must be 0 (the Supercharger's and
   DARIA's, the reserved ones);
2. the payload's CRC32 (bytes 64-36,863);
3. the unused areas 0 (the chain area past the chain, the last chain word's
   bits past the chain, the gap before the cartridge RAM), and nothing but 0
   written past the live part.

The other flags (SaveKey and AtariVox on, the port types, a forced mapper)
are kept for information and not checked: a state loads with other
settings. `python3 tools/savestate/savestate.py verify BLOB --cart-crc X
--cart-len N --mapper W --flags W` makes the same checks on a file.

## 5 The chain

### 5.1 How it is made

`tools/savestate/apply.sh` rewrites the vendored machine files (TIA, RIOT,
the 6507, MARIA's clock block, `top.sv`, `cart2600.sv` and its mappers,
`mapper_fa2.sv`, the light gun, the SaveKey EEPROM, `video_mux.sv`) from
their pristine copies at the commit before the chain (`BASE`), with
`tools/savestate/scan_insert.py`:

- every module that holds state gets `ss_en`, `ss_frz`, `ss_si` and
  `ss_so` at the head of its port list; its clocked blocks and its chained
  instances are chained in source order;
- each clocked block becomes `if (ss_en) {L} <= {in, L} >> 1; else if
  (!ss_frz) <the block>`: while `ss_en` is high its chained flip-flops are
  one shift register, while `ss_frz` is high the whole block holds;
- `L` is exactly the flip-flops Quartus keeps in the base build (its
  post-map register names, `tools/savestate/keep.txt`, from a `quartus_map`
  of the base) and the ones it merged into them (map.rpt's "Merged with"):
  once chained, a merged copy is no longer one, and a load must give it its
  own value. Flip-flops Quartus removed as constant or without fanout stay
  out (`not chained:` in `chain_map.txt`); they still hold while frozen;
- an item compiled out by `ifdef` gets a pass-through in that branch;
  block-local declarations (`lightgun.sv`) move in front of the block;
- the hold rule's gates and the RAM state ports are text replacements in
  `scan_insert.py` (`HOLD`, `RAMS`, `PORTS`), one match each.

No line of a generated file is edited by hand. To change one of these files:
check out its pristine version (`git show BASE:path`), make the change on a
new pristine commit, set `BASE` to it, run `apply.sh`, then
`sim/run_sschain.sh` (which measures the chain and writes
`tools/savestate/chain_bits.txt`), then `savestate.py gen`. A changed chain
changes the signature, so older blobs are refused (the owner's decision D7).
The same edits apply to openFPGA-7800's copies of the shared files (D8).

Our own modules are chained by hand (the table in section 3). The shared
paddle engine (`paddle_timer4.sv`) and the virtual axes are saved whole, so
a paddle or driving game resumes with its knob where it was, and the
paddles' learned calibration with it (D9).

### 5.2 Not in the state

- the Pocket's controllers and their conditioning (the dual-stick last-wins
  latches, the analog sticks' direction filter, the turbo counter, the TV
  Type toggle): read again after a load;
- the cartridge image (the header's CRC ties the state to it), the
  SaveKey's 32 KiB (its own save file; D5) and the FA2 flash (`fa2.sav`);
- the display path after `video_mux.sv` (the composite decoder, the
  Flicker Blend frame in the SRAM) and the audio filter: at most a frame or a
  few samples look or sound different after a load;
- the SRAM and SDRAM controllers (idle at the freeze, and serving the
  machine's pending request again before it resumes).

## 6 Refused in v1

| Scheme | Why |
|---|---|
| DPC+, CDF, CDFJ, CDFJ+ (bss 21, 23: DARIA) | the ARM's RAM, registers and clock crossing: a second step |
| the Supercharger (bss 15) | its tape machine, 6 KB RAM and BIOS: a later step |
| BUS (24), the bad game screen (32: ELF, a refused A78), no cartridge | nothing to save |
| the AtariVox speaking for 2.3 s | a save waits for silence |

A refusal answers err (result code 3) and leaves the machine untouched; the
Pocket shows its own failure message.

## 7 Verification

See `sim/tb_load.sv`'s `+ss_*` options and the save-state benches.
