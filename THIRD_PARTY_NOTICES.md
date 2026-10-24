# Third-party components and licenses

This core combines code from several authors under several licenses. The
tables list every third-party part in the repository, its license, and
whether it goes into the bitstream (`atari2600.rbf_r`) that releases ship.
"Built" means synthesised into the bitstream; "repo only" means the file is
vendored with the upstream source but the Pocket build leaves it out.

The complete source for every built part is in this repository, which is
also where the source for a release is published:
https://github.com/Miasmark/openFPGA-2600

## Code

| Component | Path | Author | License | In bitstream |
|---|---|---|---|---|
| Atari 2600 system from the MiSTer Atari7800 core (TIA, RIOT, Sally 6507, 2600 mappers and their detection, MARIA's clock and 2600 decode, video and palette mux, paddles, the ARM mapper sources) | `src/fpga/mister/rtl/` | Jamie Blanks and contributors | MIT (`src/fpga/mister/LICENSE`) | Built |
| Comments quoting Stella's cartridge detection (`CartDetector::isProbably*`, kept as upstream has them) | `src/fpga/mister/rtl/detect2600.sv` | Bradford W. Mott, Stephen Anthony and the Stella Team | GPL-2.0-or-later (`LICENSES/GPL-2.0.txt`) | Comments only: no logic |
| CRC-32 function (`nextCRC32_D8`, used by the cartridge detection) | `src/fpga/mister/rtl/detect2600.sv`, end of file | Easics NV | Easics' notice in the file: use and distribution without restriction, keeping the notice and its disclaimer | Built |
| SDRAM controller | `src/fpga/mister/rtl/sdram.sv` | Sorgelig | GPL-3.0-or-later (`LICENSES/GPL-3.0.txt`) | Built |
| 24LC0x EEPROM (SaveKey) | `src/fpga/mister/rtl/EEPROM_24LC256.sv` | GreyRogue, from NES_MiSTer; adapted upstream | GPL-3.0 (NES_MiSTer's license, `LICENSES/GPL-3.0.txt`) | Built |
| Paddle timing, light gun | `src/fpga/mister/rtl/paddles.sv`, `lightgun.sv` | Jamie Blanks (`paddles.sv`); `lightgun.sv` has no header and matches the light-gun module in Sorgelig's MiSTer cores | MIT with the rest of the MiSTer 7800 repository; `lightgun.sv` may also be under those cores' GPL (`LICENSES/GPL-3.0.txt`) | Built |
| `data_loader`, `sound_i2s`, `sync_fifo`; `psram` (asynchronous PSRAM controller, vendored unmodified from https://github.com/agg23/analogue-pocket-utils `ip/mem/psram.sv`: last changed upstream in `56391c11` of 2022-09-09, identical at `78482d1b` of 2023-08-10, git blob `2f7797f3`) | `src/fpga/pocket_utils/` | Adam Gastineau (agg23) | MIT (`src/fpga/pocket_utils/LICENSE`) | Built (`psram` drives PSRAM `cram0` for DARIA's image cache) |
| APF framework | `src/fpga/apf/` | Analogue | Analogue's APF Software License Agreement (file headers); `mf_*.v` also carry the Intel Program License | Built |
| PLL and PLL reconfiguration IP (generated) | `src/fpga/core/pll/` | Intel | Intel Program License (file headers): for use with Intel devices | Built |
| Core template glue (`core_top.v`, `core_bridge_cmd.v`) | `src/fpga/core/` | Analogue, modified for this port | Analogue's APF terms | Built |
| Pocket wrapper, audio filter, PLL setup, ARIA and DARIA (`src/fpga/core/bupchip/`), the AtariVox voice (`src/fpga/core/atarivox/`), the Supercharger loader (`ar_stub`), sim, tools | `src/fpga/core/`, `sim/`, `tools/` | openFPGA-7800 and this project | MIT (`LICENSE`) | Built (HDL) |
| MiSTer's PLL (generated) | `src/fpga/mister/rtl/pll.v`, `pll/` | Intel | Intel Program License (file headers) | Repo only |
| Video mixer | `src/fpga/mister/rtl/video_mixer_plus.sv` | Alexey Melnikov (Sorgelig) | GPL | Repo only |
| ARM7TDMI core | `src/fpga/mister/rtl/arm7tdmi/arm7tdmi_core.sv` | Robert Peip and the GBA_MiSTer contributors | GPL-2.0-only (`LICENSES/GPL-2.0.txt`) | Repo only (the simulation reference DARIA was checked against) |
| T65 | `src/fpga/mister/rtl/t65/` | Daniel Wallner, Mike Johnson, Wolfgang Scherr, Morten Leikvoll | BSD-style (file headers) | Repo only |

The bitstream is MIT and GPL-3.0 code with Analogue's and Intel's parts.
Stella's code appears only as comments in `detect2600.sv`; GPL-2.0-or-later
code may be combined with the GPL-3.0 parts.

## Embedded ROM images

The bitstream contains these memory images:

| Image | Path | What it is | License |
|---|---|---|---|
| `ooo.mif` | `src/fpga/mister/rtl/` | The MiSTer core's "unsupported cartridge" screen, shown for BUS, ELF and refused A78 images | MIT (MiSTer core) |
| `NWARM`, `NCOOL`, `NHOT`, `PWARM`, `PCOOL`, `PHOT` `.mif` | `src/fpga/mister/rtl/palettes/` | The MiSTer 7800 core's colour palettes (Robert Tuccitto's), which the TIA's colours index | MIT (MiSTer core) |
| `ar_stub.mif` | `src/fpga/core/` | The core's own Supercharger loader, assembled from `ar_stub.asm` | MIT (`LICENSE`) |
| `vox_irom.mif`, `vox_drom.mif` | `src/fpga/core/atarivox/` | The AtariVox speech engine's program and tables ([docs/ATARIVOX.md](docs/ATARIVOX.md)) | MIT (`LICENSE`) |
| `build_id.mif` | `src/fpga/apf/` | The build date and ID, written at build time by `apf/build_id_gen.tcl` | Analogue's APF terms |

`src/fpga/mister/rtl/mem0.mif` (the MiSTer core's "no cartridge" screen) is
in the repository but not in the bitstream: the Pocket build
(`POCKET_SRAM`) leaves it out.

No console or peripheral firmware is included. The Starpath Supercharger
BIOS is the user's own file (`supercharger.bin`). The BupChip's ROM, carried
over from openFPGA-7800 with DARIA's CPU, has no contents: its firmware slot
is gone, and the 2600 core never fills it.

## Platform files

| File | Source | Note |
|---|---|---|
| `dist/Platforms/_images/2600.bin` | The platform image of Spiritualized's Pocket 2600 core, release 1.0.0 (https://github.com/spiritualized1997/openFPGA-2600/releases/tag/1.0.0, `Spiritualized_2600_1.0.0_2022_11_08.zip`, `Platforms/_images/2600.bin`, MD5 `151911282233b7f35a2ce650400b5a1c`), unchanged | Used, with credit to Spiritualized, so that the two 2600 cores show the same picture in the Pocket's library; the release states no license |
| `dist/Platforms/2600.json` | The same release's `Platforms/2600.json`, byte for byte (MD5 `8e6c9cee02fa7569100e5fee57c0d4c8`) | The platform "2600" is shared with that core, so the file is kept identical |
| `dist/Cores/Miasmark.2600/icon.bin` | The placeholder from Analogue's core template | as in openFPGA-7800 |

The platform image and `Platforms/2600.json` are Spiritualized's, from the
Pocket 2600 core Spiritualized.2600 1.0.0
(https://github.com/spiritualized1997/openFPGA-2600), used unchanged with
thanks so both 2600 cores share one platform entry and picture in the
Pocket's library.

## Notices shipped with releases

`tools/package.sh` puts these in `Cores/Miasmark.2600/licenses/` in every
release zip: this project's `LICENSE`, this file, every text in `LICENSES/`
(`GPL-2.0.txt`, `GPL-3.0.txt`), the MiSTer core's `LICENSE`,
analogue-pocket-utils' `LICENSE`, and Analogue's APF Software License
Agreement (`Analogue-APF-Software-License.txt`), copied word for word from
its source header.

## History

The repository's first commit after the empty root imports openFPGA-7800's
whole tree ([docs/PROVENANCE.md](docs/PROVENANCE.md)). The parts only the
7800 core uses were removed in later commits but remain in the git history,
each under its own license as openFPGA-7800's THIRD_PARTY_NOTICES.md lists
it. Among them is Mark Watson's POKEY (`src/fpga/mister/rtl/PokeyWatson/`),
free for non-commercial use only; it was never built into this core.

## References

No code from these is included, apart from the Stella comments above, but
the port's behaviour follows them: Stella (2600 cartridge detection, the
driving controller's gray code, paddle swapping), Analogue's openFPGA
documentation, and agg23's openFPGA cores (the `video.json` display-mode
list).
