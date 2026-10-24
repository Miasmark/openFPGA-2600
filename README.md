# Atari 2600 for Analogue Pocket

To be clear and upfront, this port was assisted by Claude. I wanted it to exist and tested
functionality as best I could.

An Atari 2600 (VCS) core for the Analogue Pocket (openFPGA). Its TIA, RIOT,
6507 and cartridge mappers come from the
[MiSTer Atari7800 core](https://github.com/MiSTer-unstable-nightlies/Atari7800_MiSTer)
by **Jamie Blanks (Kitrinx)** and its contributors, through the Pocket port
[openFPGA-7800](https://github.com/Miasmark/openFPGA-7800).

Version 1.0.1 is openFPGA-7800 2.2.4's 2600 mode on its own. The 7800-only
hardware is gone: MARIA's video and DMA, the 7800 cartridge, POKEY, YM2151
and the other 7800 sound chips, the 7800 BIOS, the high score cart and the
BupChip's music. What is left behaves as 2.2.4 does in 2600 mode: in
simulation the 2600 tests give the same frames, with one explained
exception (see *Verification*).

## Why a separate core

- **Room.** The core uses 10,782 of the FPGA's 18,480 ALMs (58%), against
  14,639 (79%) for the 7800 core, and the menu has room for settings the
  7800 core had no room for:
  - **a Mapper setting**, which the 7800 core had wired but not shown. It
    also reaches the multicart schemes, which auto-detection misses;
  - **both difficulty switches and the TV Type switch** as settings of
    their own.
- **The Pocket's library.** The core uses the platform `2600`, as
  Spiritualized's 2600 core does, with the same platform files. Games in
  `/Assets/2600/common/` work with both cores.

## Features

- **2600 cartridges** (`.a26`, `.bin`) with MiSTer's bankswitch
  auto-detection, from the image's size and code signatures:
  - the standard schemes: 2K, 4K, F8 (8K), F6 (16K), F4 (32K) and F0 (64K).
    4K, F8, F6 and F4 come with or without Superchip RAM; 2K and F0 never
    get it;
  - FA (CBS RAM+), FE (Activision), E0 (Parker Bros.), E7 (M Network),
    3F (Tigervision), 3E, CV (Commavid), UA (UA Ltd.), EF, SB, WD (Pink
    Panther), JANE (Tarzan), CTY (Chetiry), 0840, FC (Power Play), DF and BF
    (EF, DF and BF also in their Superchip forms: EFSC, DFSC, BFSC);
  - DPC (Pitfall II), FA2 (Star Castle Arcade, with its flash saves), AR
    (the Starpath Supercharger), and the ARM schemes DPC+, CDF, CDFJ and
    CDFJ+ (next item).
  - The multicart schemes MC2K, MC4K and MC8K are reached through the
    *Mapper (more)* setting only. So is 32-in-1 for a real 32-in-1 image:
    it is 64 KB, and detection takes a 64 KB image as F0 (or EF). It picks
    32-in-1 only for an image between 32 and 64 KB long.
- **2600 ARM cartridges**: DPC+ and the CDF family (CDF, CDFJ and CDFJ+),
  the Harmony and Melody games such as the Champ Games releases. MiSTer runs
  them on a soft ARM7TDMI that doesn't fit the Pocket; this core runs them on
  **DARIA**, openFPGA-7800's own ARM-compatible CPU with Thumb, at 38.18 MHz,
  with its own front end for the cartridge's 6507 side
  ([docs/DARIA_CORE.md](docs/DARIA_CORE.md)). In simulation every tested
  game runs the same ARM code as on MiSTer, call for call, and every call is
  on time, including Spiders' 16 calls before its first level loads, which
  MiSTer's core is late on. Images up to 512 KB (CDFJ+'s largest) load; the
  largest game tested is 128 KB (Turbo). The first 64 KB of an image are in
  block RAM and the rest is read through a cache over the Pocket's PSRAM.
  ARM code beyond the first 64 KB, or an LDM from there, halts the CPU; in
  every tested image the code ends below $B30A, about 45 KB in
  ([open item 5](docs/DARIA_CORE.md#open-items)). The ARM chip's peripherals
  beyond its timer and memory accelerator, such as a Melody board's
  optional EEPROM, read as zero
  ([open item 19](docs/DARIA_CORE.md#open-items)).
- **Starpath Supercharger** games (`.bin` tape images, 8,448 bytes a load;
  images of one to four loads, and 6 KiB ROM images, are detected). With the
  Supercharger BIOS as a file (`supercharger.bin`) they load as from tape,
  loading screen and all, in about 20 seconds a load. Without it the core's
  own loader loads them in about 0.1 s
  ([docs/SUPERCHARGER_FASTLOAD.md](docs/SUPERCHARGER_FASTLOAD.md)). A
  multiload game loads its next part by itself, when it asks for it. The
  tape keeps its place through a reset, so a compilation tape (Party Mix)
  loads its next game after one. There is no tape audio (`.wav`) input and
  no menu item to skip to the next load.
- **SaveKey** (24LC256 EEPROM on controller port 2), in one shared
  `savekey.sav` for all games, like the real device. A new file starts blank
  ($FF), as a real SaveKey does. *SaveKey (port 2)* is Off by default: turn
  it On for games that save to a SaveKey or speak through an AtariVox. With
  it On, port 2's LEFT (also the button of the second paddle on port 2,
  controller 4) reads the SaveKey instead, so a two-player or four-paddle
  game loses it. A 2600 image has no header to ask for a SaveKey, so there
  is no Auto setting.
- **AtariVox voice** (the SpeakJet speech chip on port 2). The voice is
  there whenever the SaveKey is On, and *AtariVox Voice* sets its level in
  the mix (Off, Quiet, Normal, Loud: x4, x8 and x16; Normal is the default,
  about level with the game's sound). With the voice on, port 2's DOWN also
  reads the AtariVox's "buffer half full" line, as on the real device. The
  SpeakJet's sound tables are not published, so the voice is openFPGA-7800's
  own speech engine, built from recordings of the real chip
  ([docs/ATARIVOX.md](docs/ATARIVOX.md)). It reads the same codes, at the
  same lengths, pitches and speeds; the timbre is an approximation.
- **FA2 saves** (Star Castle Arcade's high scores): the 256 bytes an FA2
  cartridge keeps in its flash go in **one shared file**, `fa2.sav`. A new
  file starts blank ($FF), as an erased flash. Every FA2 game shares it, so
  two FA2 games overwrite each other's saves; Star Castle Arcade is the only
  one known.
- **Paddles, driving controllers, the light gun, dual stick and the Booster
  Grip**, played with the D-pad (or, docked, a controller's left stick). See
  *Controls*. A 2600 image says nothing about its controllers, so set
  *Port 1 Input* / *Port 2 Input* for each game (Paddles for Breakout,
  Kaboom!, Warlords; Driving for Indy 500). Four paddles, and a second
  player, need the dock: in handheld mode the Pocket is controller 1 only.
- **PAL games** at the real PAL master clock, 14.18758 MHz instead of NTSC's
  14.31818 MHz, so they run at 50 Hz and play at the right pitch. On *Region*
  Auto the core measures the game's frame length; when it finds a PAL game
  it retunes the PLL, which holds the core in reset for a moment, and the
  game restarts once. PAL frames show 288 lines, NTSC ones 240, and the
  Pocket's scaler mode follows (160x288 or 160x240).
- **PAL60 games** (PAL releases that draw 262-line, 60 Hz frames, such as
  Stay Frosty 2's PAL build) look like NTSC games to *Region* Auto, so they
  run with the NTSC clock and NTSC colours. *Region* PAL gives them the PAL
  clock and colours, but the scaler mode (160x288) for a 262-line picture.
- **Video**: *Palette* (warm, cool or hot: the MiSTer 7800 core's palettes,
  by Robert Tuccitto, which the TIA's colours index), *2600 Video* (Flicker
  Blend, and De-comb, which smooths the comb pattern some games draw by
  alternating lines between frames), and the Pocket's display modes (CRT
  and LCD looks, under *Display Mode* in the Pocket's video settings).
- **Audio**: Stereo TIA (the TIA's two channels left and right), and a
  blend of the two (25%, 50% or full mono) for headphones.
- **A78 images are refused.** A file with an A78 header ("ATARI" in bytes
  1 to 5) gets the core's unsupported-cartridge screen, and nothing is saved
  for it. The cartridge slot lists only `.a26` and `.bin`, so an `.a78`
  arrives only renamed. A 7800 image without a header is taken as a 2600
  game, and shows garbage. Use openFPGA-7800 for 7800 games.

### Not included

| Feature | Why |
|---|---|
| BUS and ELF cartridges | The core shows its unsupported-cartridge screen for them. No released game uses BUS. ELF targets a Cortex-M0+ cartridge, which needs another CPU than DARIA ([docs/DARIA_CORE.md](docs/DARIA_CORE.md), decision 6) |
| 3E+, 3EX, 4A50, X07, TVBOY, MDM, 0FA0, 03E0, WF8 | Not in MiSTer's mapper set. X07 is a candidate for a later release |
| CompuMate, GameLine, MovieCart | Not in MiSTer's core |
| Keypad, keyboard, trackball, Mindlink | These need input the Pocket doesn't have |
| SECAM | No SECAM palette or timing. A candidate for a later release |
| Supercharger demo-unit images (67,584 bytes) | Not detected |
| Save states | Planned for a later release |

## Settings

The Pocket shows at most 16 settings; this core uses all 16.

| Setting | Options | What it does |
|---|---|---|
| *Reset* | | Resets the console |
| *Left Difficulty*, *Right Difficulty* | A, B (default A) | The console's difficulty switches |
| *TV Type* | Colour, B&W | The console's TV Type switch. It takes this value when you change it and at every cartridge load; L toggles it in between |
| *Swap Controllers* | on, off | Swaps ports 1 and 2 |
| *Port 1 Input* | Joystick, Paddles, Driving, Light Gun, Dual Stick, Booster Grip | The controller on port 1 (see *Controls*) |
| *Port 2 Input* | Joystick, Paddles, Driving, Light Gun | The controller on port 2 |
| *Turbo (X/Y)* | Off, Fast, Medium, Slow | X repeats fire while held; Y's half does nothing in this core (see *Controls*) |
| *Region* | Auto, NTSC, PAL | Auto follows the game's frame length (see *PAL games*) |
| *Palette* | Warm, Cool, Hot | |
| *SaveKey (port 2)* | Off, On (default Off) | The SaveKey and the AtariVox; On takes port 2's LEFT |
| *AtariVox Voice* | Off, Quiet, Normal, Loud (default Normal) | The voice's level, while the SaveKey is On |
| *Audio* | Mono TIA, Stereo TIA, Stereo, 25% Blend, Stereo, 50% Blend, Full Mono | |
| *2600 Video* | Normal, Flicker Blend, De-comb, Blend + De-comb | |
| *Mapper* | Auto, 2K, F8, F6, F4, F0, FA, FE, E0, E7, 3F, 3E, CV, UA, EF, SB | Forces a scheme for the cartridge you load next |
| *Mapper (more)* | Auto, AR, DPC, DPC+, CDF / CDFJ / CDFJ+, FA2, WD, JANE, CTY, 0840, FC, DF / BF, Multicart 2K, 4K and 8K, 32-in-1 | The same, for the other schemes; *Mapper* wins when both are set |

The two Mapper settings are not saved: they are back on Auto each time the
core starts. A forced scheme stays forced for every cartridge loaded until
you set it back to Auto. BUS cannot be forced (it would get the
unsupported-cartridge screen), and neither can ELF.

## Controls

| Pocket | Atari |
|---|---|
| D-pad | Joystick |
| A / X | Fire; X repeats with *Turbo (X/Y)* on |
| B / Y | Nothing: the 2600 joystick has one button. B is the button of the other controllers (below) |
| L | Colour / B&W (toggles *TV Type*) |
| Select | Select |
| Start | Reset |

Paddles, driving controllers and the light gun (*Port 1 Input* /
*Port 2 Input*):

| Pocket | Paddles | Driving controller | Light gun |
|---|---|---|---|
| D-pad left / right | Turn the knob | Turn the wheel | Move the crosshair |
| D-pad up / down | | | Move the crosshair |
| A or B | Paddle button | Fire | Trigger |
| X (held) | Turn slowly, for fine aim | Turn slowly | Move slowly |
| Y (held) | Turn fast | Turn fast | Move fast |

Movement starts slowly and speeds up the longer the D-pad is held, so a tap
moves a little and a hold crosses the whole range in about half a second
(a quarter of a second with Y).
Docked, a controller's left stick also works: a paddle or the crosshair
follows the stick's position, and a driving controller turns at a speed set
by how far the stick is pushed. The next D-pad press takes over again.

*Port 1 Input* also offers:

- **Dual Stick**, for twin-stick games: controller 1 drives both joystick
  ports. The D-pad (or left stick) moves; the face buttons fire in their
  direction on the diamond (X up, B down, Y left, A right), or, docked, the
  right stick. Two diagonal buttons fire diagonally; of two opposite ones
  (X and B, or Y and A) the one pressed last wins, since a real joystick
  can't point both ways.
- **Booster Grip** (Omega Race, Thrust+): A fires, B is the grip's trigger
  and X its booster button. X also fires, as on a joystick.

*Turbo (X/Y)* makes X repeat A's fire while held, at 15, 10 or 7.5
presses a second (Fast / Medium / Slow; 12.5, 8.3 and 6.25 in PAL games).
A stays a single press, and with *Turbo* Off X fires as A does. Y's half
of the setting has no effect: it repeats B on the joystick's
second-button line, which no mode of this core reads. The paddles,
driving controller, light gun and Booster Grip take B (and A) directly,
and in those modes Y moves fast (above); on the Dual Stick Y fires left.

Some paddle games read the second paddle of the pair for player 1 (Demons
to Diamonds, for one; Stella keeps a "swap paddles" list for them). If a
paddle game ignores the D-pad, turn on *Swap Controllers*.

Paddles come in pairs: the two paddles on port 1 are controllers 1 and 2,
the two on port 2 are controllers 3 and 4 (docked). A joystick, driving
controller or light gun on port 1 is controller 1, on port 2 controller 2.
The light gun draws a red crosshair; aim off the top or bottom of the
picture to shoot off-screen (to reload in some games).

## Installing

Copy the contents of a release zip (`M_Atari2600_Pocket_1.0.1.zip`) to the
root of the SD card. Cartridges go in `/Assets/2600/common/`.

The zip holds `Platforms/2600.json` and `Platforms/_images/2600.bin`. Both
are byte for byte the files of Spiritualized's 2600 core, so copying them
over an existing install changes nothing for that core.

### Firmware

The core includes no console or peripheral firmware. One optional file goes
in `/Assets/2600/common/`:

| File | What it is | Size | Without it |
|---|---|---|---|
| `supercharger.bin` | Starpath Supercharger BIOS | 2 KiB | Supercharger games load through the core's own loader, without the tape loading screen |

The core loads it when it starts. To change it, replace the file and
restart the core.

### Saves

Two files, each shared by every game, in the Pocket's save folder for the
2600 (under `/Saves/2600/`):

| File | What it holds | Size |
|---|---|---|
| `savekey.sav` | The SaveKey's EEPROM (with *SaveKey (port 2)* On) | 32 KiB |
| `fa2.sav` | An FA2 cartridge's flash (Star Castle Arcade's high scores) | 256 bytes |

Played these games on the 7800 core? Its saves stay in its own folder,
under `/Saves/7800/`. Copy `savekey.sav` and `fa2.sav` from there to the
same place under `/Saves/2600/` to keep them.

## Verification

openFPGA-2600 was made from openFPGA-7800 in steps, one commit each
([docs/PROVENANCE.md](docs/PROVENANCE.md)). After every step that changed
the hardware, the simulation compared the core with 2.2.4 frame by frame:
frame length, RIOT RAM, picture, audio, the CPU's bus and the reset times
(`sim/check/frame_gate.py --strict`).

| Check | Result |
|---|---|
| The import, unchanged | Every `sim/run_sim.sh` case gives 2.2.4's fingerprints byte for byte: 32 cases with DARIA, 29 in the build without it |
| `sim/run_sim.sh` after the cuts | Every 2600 case, in both builds, gives 2.2.4's fingerprints in every column. The cases that differ test 7800 features this core no longer has (7800 mode, the BIOS, A78 images, the BupChip, POKEY). In one case, a 2600 image loaded after an A78, the frames after the load end 4 clocks earlier than in 2.2.4, and the RIOT RAM column, sampled at that moment, differs with them: in 2.2.4 the first image ran in 7800 mode and left MARIA's processor clock divider elsewhere. With a 2600-only history the two cores agree on every column |
| 2600 cartridge RAM | The matrix of cartridge-RAM cases and its s19 sweep: 21 fingerprints in each build, byte for byte 2.2.4's |
| 2600 ARM cartridges | The 15 Champ Games demos and Stratovox, 1,500 frames each (frames 1-1,499 compared): frame length, RIOT RAM, picture and audio on every frame, and every ARM call's timing and instruction count, identical to 2.2.4 |
| TIA pitch | Pure tone, AUDF 0 / 14: 15,700.0 / 1,045 Hz against the TIA's 15,699.8 / 1,046.7 Hz, as in 2.2.4 (the same fingerprints) |
| A78 refusal | An A78 image gets the unsupported-cartridge screen, writes no SaveKey or FA2 save, and its header's region byte never reaches the PLL; four planted faults are caught |
| The Pocket files | `sim/check/apf_json_check.py`: every JSON file within the limits of Analogue's documentation, and every menu option checked against the RTL. `sim/run_core_top.sh`: 133 menu writes, the 17 setting ports after each, the data slots and the save bridges, through `core_top.v`. 12 planted faults in the core and its files, and 10 more for the checker alone, are all caught |

The test benches and gates are in `sim/` ([docs/DEVELOPING.md](docs/DEVELOPING.md)).

### Build figures

The release build (Quartus Prime Lite 21.1, fitter seed 2, DARIA's CPU
clock at 38.18 MHz) meets timing on all four corners. Worst setup slack at
the worse slow corner: +3.159 ns on clk_sdram (against a release gate of
+1.5 ns), +2.449 ns on DARIA's CPU clock (gate +0.5 ns), and +2.844 ns on
the one path of DARIA's front end that is timed on its own (its phase
detector, bounded at 8.0 / 0.5 ns), whose hold slack is +0.313 ns. Worst
hold slack +0.125 ns. Seeds 1 and 3 pass every check too, with +2.525 and
+3.025 ns on clk_sdram (seed 1 on the tree just before `329a08b`, the
crossing-table update); seed 2 has the most clk_sdram margin, which decides,
as for 2.2.4. The debug build (with DARIA's status overlay) passes on seeds
1, 2 and 3.

It uses 10,782 of 18,480 ALMs (58%), 187 of 308 M10K blocks (61%) and 10
DSP blocks, against 14,639 ALMs (79%), 216 M10K blocks and 13 DSP blocks for
openFPGA-7800 2.2.4. 16 of the M10K blocks are the BupChip's firmware ROM,
which the 2600 core never fills; synthesis keeps it, as its write port is
driven from DARIA's image capture path.

The SaveKey's read byte has a hold exception in the timing constraints
(`sram_ctrl` to the EEPROM's data, behind a toggle handshake). One of
openFPGA-7800 2.2.4's debug fits missed hold on that path by 0.504 ns.

### Hardware testing

The 1.0.1 build is still to be tested on a Pocket before its release. As
openFPGA-7800's 2600 mode, the same hardware was tested there, in builds up
to 2.2.4:
Solaris, Adventure, Pitfall II (DPC), Crystal Castles and Omega Race;
Supercharger games with and without `supercharger.bin` (Fireball, Frogger,
Dragonstomper, and Party Mix and Sweat after a reset); paddles (Kaboom!,
Demons to Diamonds), driving (Indy 500) and the Booster Grip; the Champ
Games library on DARIA, Spiders with no screen shift at 38.18 MHz, and
Turbo, which reads beyond DARIA's 64 KB window; Star Castle Arcade's high
score kept in `fa2.sav`; Stratovox speech; a PAL 50 Hz test image (one
restart, then PAL).

## Building

The FPGA project is `src/fpga/ap_core.qpf`, for Quartus Prime Lite (built
with 21.1). The GitHub workflow builds it in the `raetro/quartus:21.1`
container and uploads a ready-to-copy zip, and a second job checks that no
game data is in the tree (`sim/check/game_data.py`). By hand:

```sh
cd src/fpga && quartus_sh --flow compile ap_core
cd ../.. && tools/package.sh      # -> release/M_Atari2600_Pocket_<version>.zip
```

`sim/run_sim.sh` (Verilator 5.040; 5.020 is too old for the upstream
sources) runs the whole core at the Pocket's clocks.

[docs/DEVELOPING.md](docs/DEVELOPING.md) covers the layout, tools, recipes
and known pitfalls. It comes from openFPGA-7800 and is not yet rewritten:
its parts on the 7800-only hardware describe the 7800 core.

## Layout

```
src/fpga/apf/          Analogue's APF framework (unchanged, from the core template)
src/fpga/core/         Pocket glue: core_top.v, atari2600_pocket.sv, PLL, audio
                       filter, DARIA (bupchip/), the AtariVox voice (atarivox/)
src/fpga/mister/rtl/   MiSTer Atari7800 sources (vendored; see POCKET_CHANGES.md)
src/fpga/pocket_utils/ Data loader / I2S / PSRAM helpers by Adam Gastineau (agg23)
dist/                  Pocket SD card files (core, platform, JSON definitions)
sim/                   Verilator simulation and checks
tools/                 Packaging
docs/                  Design notes
```

In `docs/`, [DARIA_CORE.md](docs/DARIA_CORE.md),
[HARMONY_MODEL.md](docs/HARMONY_MODEL.md),
[SUPERCHARGER_FASTLOAD.md](docs/SUPERCHARGER_FASTLOAD.md),
[ATARIVOX.md](docs/ATARIVOX.md), [SRAM_TIMING.md](docs/SRAM_TIMING.md) and
[DEVELOPING.md](docs/DEVELOPING.md) describe parts this core uses, and
[PROVENANCE.md](docs/PROVENANCE.md) how it was made. The other files there
(`AGENT_RUNS.md`, `BUPCHIP.md`, `BUPCHIP_CORE.md`, `ENVIRONMENT.md`,
`IMPROVEMENTS.md`, `SRAM_TIMING_REVIEW.md`, `daria_fe/`, `daria_step7/`,
`daria_step10/`) are openFPGA-7800's working notes, kept as they were for
the history and the line references between them.

## Credits

**The MiSTer Atari7800 core.** Nearly all of this core is its work.

- **Jamie Blanks (Kitrinx)**, author of the MiSTer Atari7800 core: TIA,
  RIOT, the 6502 ("Sally"), the cartridge mappers and their detection, 2600
  support, and the system as a whole.
- Contributors to the MiSTer core: **Robert Tuccitto (trebor68)** for the
  palettes, **Bruno Freitas (bootsector)**, **Sorgelig**, **José Manuel
  Barroso Galindo (theypsilon)**, **bobRetro**, **Gyorgy Szombathelyi
  (gyurco)**, **Roberto Garcia-Lago**, **TheJesusFish**, **Roberto Lari**,
  **PhantombrainM**, **Niclas Carlsson**, **Flandango** and **David
  Gillies**.
- People the MiSTer core thanks for its accuracy: **Mike Saarna** for his
  system knowledge, **Robert Tuccitto** for the palette research,
  **Remowilliams** for hardware testing, and **Alan Steremberg** for
  documentation access.

**openFPGA-7800**, the Pocket port this core is cut from: the Pocket
wrapper, DARIA and ARIA, the AtariVox voice, the Supercharger loader, the
SRAM controller and the tests.

**Third-party components**

- **SDRAM controller** by **Sorgelig**, GPL-3.0.
- **24LC0x EEPROM** (the SaveKey) by **GreyRogue**, from NES_MiSTer,
  GPL-3.0.
- **Light gun** module (`lightgun.sv`), the one **Sorgelig**'s MiSTer cores
  share; this core drives it from the D-pad.
- **CRC-32 function** by **Easics**, in the cartridge detection.

**Pocket side**

- **Analogue**: the openFPGA APF framework and core template.
- **Adam Gastineau (agg23)**: `data_loader`, `sound_i2s`, `sync_fifo` and
  the PSRAM controller `psram` from
  [analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)
  (MIT).
- **Spiritualized**: the first Pocket 2600 core. The platform image
  (`Platforms/_images/2600.bin`) and `Platforms/2600.json` are
  Spiritualized's, from the Pocket 2600 core Spiritualized.2600 1.0.0
  ([release](https://github.com/spiritualized1997/openFPGA-2600/releases/tag/1.0.0),
  [repository](https://github.com/spiritualized1997/openFPGA-2600)), used
  unchanged with thanks so both 2600 cores share one platform entry and
  picture in the Pocket's library. That release states no license; the
  files are used for consistency with the library.

**References and tools**

- **Stella**, the 2600 emulator: the cartridge detection that MiSTer's
  follows (`detect2600.sv` quotes its functions in comments), the driving
  controller's gray code, the per-game "swap paddles" practice, and much of
  the 2600 behaviour the MiSTer core follows.
- **Analogue's openFPGA developer docs**, and **agg23's openFPGA cores**
  (the SNES core's display-mode list was the model for ours).
- **Verilator** and **Intel Quartus Prime Lite**, for simulation and
  builds.
- MiSTer's **ARM7TDMI core** (**Robert Peip** and the GBA_MiSTer
  contributors, GPL-2.0): the simulation reference DARIA was checked
  against. None of it is in the bitstream.

## License

Each part keeps its own license. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
lists every component, its license, and whether it is built into the
bitstream.

- This project's own code (`src/fpga/core/` apart from the two template
  files, `sim/`, `tools/`) is MIT: see [LICENSE](LICENSE).
- The MiSTer core in `src/fpga/mister/` is MIT (© Jamie Blanks), apart from
  the third-party files below.
- The SDRAM controller and the SaveKey EEPROM are GPL-3.0. The full text is
  in [LICENSES/GPL-3.0.txt](LICENSES/GPL-3.0.txt), and the complete source
  for the bitstream is in this repository.
- `detect2600.sv` quotes Stella's detection functions in comments, under
  Stella's GPL-2.0-or-later. The ARM7TDMI core, kept for simulation and not
  built, is GPL-2.0-only. The text is in
  [LICENSES/GPL-2.0.txt](LICENSES/GPL-2.0.txt).
- The CRC-32 function at the end of `detect2600.sv` is Easics NV's, under
  its own notice; THIRD_PARTY_NOTICES.md quotes the notice and its
  disclaimer in full.
- `src/fpga/apf/`, `core_top.v` and `core_bridge_cmd.v` are Analogue's
  framework and template, under Analogue's terms.
- The platform files in `dist/Platforms/` are Spiritualized's (above).
- No console or peripheral firmware is included: the Supercharger BIOS is
  user-supplied.
- Any remainder should be considered MIT licensed.
