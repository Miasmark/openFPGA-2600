# Provenance

openFPGA-2600 starts from the Atari 7800 core for the Analogue Pocket,
[openFPGA-7800](https://github.com/Miasmark/openFPGA-7800), so that its
history shows where the 2600 core comes from.

## The import

- Source: `https://github.com/Miasmark/openFPGA-7800`, branch `DARIA-dev`,
  commit `3c7041c` (`3c7041c368cb42a3020792bb1f58b5330ba58eff`).
- `src/` of that commit is the same tree as the 2.2.4 release, commit
  `ba3af23` (tag `2.2.4`): tree `0b1a4d66906c838b3df67ea12b9f0050e1214c0d` in both. The commits
  between them change only simulation scripts, checks and documents.
- The import commit holds every tracked file of `3c7041c` at its own path
  (644 files, taken with `git archive`), unchanged except the 8 files
  below, plus this file.
- Files that only the 7800 core uses are removed in later commits, one
  step at a time; shared files keep their paths so that fixes can be
  compared and carried between the two repositories.
- `src/fpga/mister/UPSTREAM_COMMIT` still names the MiSTer Atari7800
  commit the shared MiSTer sources come from.
- No game images, BIOS images or firmware are in the import, as in
  openFPGA-7800 (`.gitignore`).

## Files edited at the import

These files differ from openFPGA-7800's. Apart from `.gitignore`, each
change removes a finding of the repository's hygiene check
(`sim/check/hygiene.sh`: a name from the private list, or an absolute
temporary-directory path):

| File | Change |
|---|---|
| `.gitignore` | the 2600 lines added at the end (the package's paths, `.sav` files); openFPGA-7800's lines unchanged |
| `README.md` | a listed name in line 3 (who assisted the port) replaced by a generic phrase |
| `docs/DEVELOPING.md` | the PLL regeneration command uses paths relative to the container's working directory instead of absolute temporary-directory paths (same files) |
| `docs/ENVIRONMENT.md` | listed names in lines 3 and 459 replaced by generic wording |
| `sim/bupchip/daria/fe_unit/tb_fe_arb_probe.v` | comment only: the usage line no longer names an absolute lock file path |
| `sim/bupchip/daria/fe_unit/tb_fe_audio_probe.v` | comment only: the usage line no longer names an absolute lock file path |
| `sim/bupchip/daria/thumb/yosys_cells.sh` | yosys's Cyclone V cell-name prefix matches a listed name: the script now spells it in two pieces (`P`); same output |
| `sim/bupchip/model/study/area/run_area.sh` | the same cell-name prefix change as yosys_cells.sh; same output |

## Hygiene of the import

The whole tree, checked from the root commit, has these findings in
files kept as openFPGA-7800 has them; they are allowed by path
(`--allow`) in the import's check:

| Path | Finding |
|---|---|
| `dist/Cores/Miasmark.7800/icon.bin` | the 7800 package's icon (binary, `.bin`) |
| `dist/Platforms/_images/7800.bin` | the 7800 platform image (binary, `.bin`) |
| `src/fpga/mister/rtl/arm7tdmi/.DS_Store` | a binary file carried in the MiSTer sources |
| `src/fpga/mister/rtl/t65/T65.vhd` | the MiSTer T65 source's own comment uses the word the scratch-directory rule looks for |
| `sim/savekey_test.asm` | a comment calls a RAM variable a scratch pad (no path) |
| `docs/BUPCHIP.md` | a document whose name matches the rule for the BupChip firmware file |
| `docs/ENVIRONMENT.md` | process notes: the VM's Quartus lock file path |
| `docs/daria_fe/` | process notes: the Quartus lock file path and the session's scratch files (README.md, lanes/A_core.md, B_audio.md, C_call_copy.md, D_arb_guard.md, G_step7_resets.md, spec/audio.md, bus.md, cdf.md, glue.md) |

A second run without any `--allow` shows that these are the only
findings: none of them is a name from the private list.

## After the import

- **README line 3.** The import replaced it (above). `b7e5405` put the
  owner's own sentence back, byte for byte as in openFPGA-7800, and taught
  `sim/check/hygiene.sh` to let that one exact line through
  (`--allow-line`; the entry is in `sim/check/hygiene_allow_lines.txt`).
  It reached `dev` in the merge `aa4bc2f`.
- **The cuts**, one commit each. Every commit that changed what the
  simulated RTL does was checked against 2.2.4's fingerprints: the cuts
  `271becf` to `73fd755` each in its own step, the packaging (`015de7f`,
  `564985b`) at its merge `4e5be35`, and `79de061` in the identity gate of
  the branch `step6-tests`. The other commits change only comments, timing
  constraints, the crossing tables, where a declaration sits, the tests or
  the documents:

| Commit | What it does |
|---|---|
| `271becf` | renames the wrapper `atari7800_pocket.sv` to `atari2600_pocket.sv`, instance names kept |
| `3291616` | ties off the wrapper's 7800 parts (7800 BIOS, high score cart, BupChip firmware slot, Souper profile), refuses A78 images, and makes the menu (Mapper and Mapper (more), Left and Right Difficulty, TV Type, SaveKey Off/On) |
| `6e3b6b3` | removes the 7800 cartridge (`cart.sv`), its RAM and BIOS path, and the 7800 sound chips (`jt51/`, `SN76489/`, `Minnie/`, `souper.v`, `ps2_to_pokey.v`) |
| `3fd7f17` | replaces INPTCTRL with one register |
| `73fd755` | reduces MARIA to its clock and 2600 decode (`DMA.sv`, `control.sv`, `line_ram.sv`, `video_sync.sv` removed) |
| `015de7f`, `564985b` | package the core as `Miasmark.2600` (2600 platform, scaler modes, the APF file checks); merged in `4e5be35` |
| `01fb35b` | comments and the DARIA crossing tables after the cuts |
| `21a5d5d`, `834596d`, `329a08b` | the SaveKey read byte's hold exception, a declaration fix and the crossing tables for the first 2600 fits |
| `79de061`, `c14802f`, `0799f8f`, `12f41eb` | (branch `step6-tests`) `79de061` maps Port Input 0 straight to the joystick; the tests ported to the 2600 core; `0799f8f` removes the 7800-only tests, `Pokey/`, `PokeyWatson/` and `pokey_adapter_watson.sv` |

- **The documents** (branch `step8-docs`): the README, THIRD_PARTY_NOTICES
  and this section written for the 2600 core, `LICENSES/GPL-2.0.txt` added,
  `tools/fix_hsc_save.py` (a 7800 high score cart tool) removed, and the
  CI's game-data check (`sim/check/game_data.py`) added.

The files removed by these commits stay in the history, from the import on.

## Imported files

Each file's path in openFPGA-7800 (the same path here) and its blob at `3c7041c`;
a second blob is the file as imported, for the files edited above.

```
9fbcce8c2aa7f0416ec17bc2be3c32252825cd72 .github/workflows/build.yml
b217b1ddad3400482932c1e72c900e88f1c1721b .gitignore  (imported as e87952400aa81d959d444bcf0c455a8895d587e5)
5707d80bf1812823218c4ba469203564dc024c9a LICENSE
f288702d2fa16d3cdf0035b15a9fcbc552cd88e7 LICENSES/GPL-3.0.txt
e683cd7d68e1bc5cce32d55d7d2ade8443392fc0 README.md  (imported as b5165a4ef56e841d8693b909aed6936f57f00c71)
b12f6d95d92dc680325abfd467ef8fc4129768bb THIRD_PARTY_NOTICES.md
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 dist/Assets/7800/common/.keep
20cf7f2d94a1e88b026cd2fa982d1a7394ef1a58 dist/Cores/Miasmark.7800/audio.json
2f993737e0152fb6746d9a48af2036e9d7cb81cf dist/Cores/Miasmark.7800/core.json
5c82b6985cbdc98e6665654e6119322fe859efd2 dist/Cores/Miasmark.7800/data.json
7e6007c43cef75ca6b4bb78c01011fdd8cb38fbc dist/Cores/Miasmark.7800/icon.bin
9b24cb5ffcbf3b0901b7924df144549b0249fa70 dist/Cores/Miasmark.7800/info.txt
b67ffdfa251a1d175c2bd4360004b2298e13f061 dist/Cores/Miasmark.7800/input.json
6f38cc979d50ce53a005b8b72edc786f5000e69f dist/Cores/Miasmark.7800/interact.json
2341ee9d611b072123c1e8afa8ba45629bfe7428 dist/Cores/Miasmark.7800/variants.json
477c6d15077b7ea9e05165fd8140a09428cc9962 dist/Cores/Miasmark.7800/video.json
22506de73aff845b78c36adbcfa7faa35d916ab8 dist/Platforms/7800.json
c6323ab2948eff3ca21abefa2a6595d03ac92710 dist/Platforms/_images/7800.bin
20537d6da8a2426dd294577afc375756f348b6d4 docs/AGENT_RUNS.md
780a0d0ea885ba8f6d3f3cb505c5d74435f8b270 docs/ATARIVOX.md
899fa68a2967accd6b1770c51526de1d23c0be2e docs/BUPCHIP.md
ebb42dad242ff865d58633efecef957d503e974e docs/BUPCHIP_CORE.md
579ac07e96b3aa218cc03b4ff2c66a6ad3233f1d docs/DARIA_CORE.md
56ac7b38b4628b2a5e28b79af0b04d0ff6e12650 docs/DEVELOPING.md  (imported as a37ddc22349cae0584f733198e65d3840ec26748)
a9e8cacacbd4e5c2d1c80f67b13e20909f1ff0b7 docs/ENVIRONMENT.md  (imported as 5bc616af75008b12a0405b8918f4fb985d2c37ac)
61069384c78718b0b47d94b3811fce79c06b11f7 docs/HARMONY_MODEL.md
21224a50a6302be08c2a0a483fae79f0ab8e5980 docs/IMPROVEMENTS.md
9da9e91b272bdd468fac5c1b7edc7f6d19231502 docs/SRAM_TIMING.md
1bf301072662411278b6bd5b94291cac55097c3c docs/SRAM_TIMING_REVIEW.md
8ba5acf2db0274436f5afea5f2b07487e4e8fee8 docs/SUPERCHARGER_FASTLOAD.md
5f3e528034737f1fb9725e841426c967e27d06a8 docs/daria_fe/README.md
87ae814f36de79c924d6fb5ea7cb9a36315c296d docs/daria_fe/alternatives/exact.md
1843623769ff7aa82f4485dc460e7f16d94557da docs/daria_fe/alternatives/lean.md
97d8d2840f20a61ad95741f02c8a546656c56183 docs/daria_fe/alternatives/simple.md
27e07a6985313b0ab30e1dea89af84fe68193602 docs/daria_fe/bench_stage0.md
05b636be3e9a1e90ba1a914df3b28e040622789e docs/daria_fe/design.md
c51e8cc98bc0020633a799364e3fbf90f8381c52 docs/daria_fe/interfaces.md
74f42ab892ebc377c1d4316f3b2d51aa43e73ca7 docs/daria_fe/lanes/A_core.md
ce41c37fc85279eb5c8a94a41a798390a9d8e140 docs/daria_fe/lanes/B_audio.md
d1ce766fe383eaa5a33679f2c1d340bdc0881aab docs/daria_fe/lanes/C_call_copy.md
d004a6e84506f78939d66b405f518c70708d2edb docs/daria_fe/lanes/D_arb_guard.md
b6e2b2744d3da5ceb36402766a7e458800e28882 docs/daria_fe/lanes/E1_shadow.md
afd688ee829d7517a76953b41223d5372099026b docs/daria_fe/lanes/E2_directed.md
19afe4de237de8eb1dcfdc73a72de2bc6caaa37f docs/daria_fe/lanes/E3_random.md
0fc8d268fb9298798880261b188928b48950c89b docs/daria_fe/lanes/E3_rtl_issues.md
34908c2ec05f754c8b2997dbedc8f5d2ad1daf80 docs/daria_fe/lanes/F1_fixes.md
d0cef1d21e55d18dd8a617487653a25834f61a4d docs/daria_fe/lanes/F1_pause_lane_mister.patch
dee1517e21d00c966f3fe492a1274145d69ceee6 docs/daria_fe/lanes/G_modeB.md
76cb518c7fa2aa4aa415d5bfa2a6aad9fc27407d docs/daria_fe/lanes/G_step7_resets.md
73c7a84be727d6493211be2742019d33842ac834 docs/daria_fe/reviews/judge_exactness.md
3ef03ea44b1d2f74b1b85d82f265099e89faf748 docs/daria_fe/reviews/judge_hardware.md
6d9829c7175c23feda8a1066c92978bb1835d3a1 docs/daria_fe/reviews/judge_risk.md
98868dcee7545ecc795d9bb233b36e2ab8fb4fd7 docs/daria_fe/spec/audio.md
a25ae3bbbedb498f98216132436b7399fad5be01 docs/daria_fe/spec/bench.md
bb05453aeca96ce3f1fbaf9092496243fab42fb6 docs/daria_fe/spec/bus.md
3e191ebfe07d3d4dbc6c021a0dced8d113321f2a docs/daria_fe/spec/cdf.md
e85f963959a7175006ce086236ef7e2bf5e5506b docs/daria_fe/spec/critic.md
b1a97ae241620effe7d4af2a4691f789a48983a9 docs/daria_fe/spec/design_inputs.md
7c7e4d76d6cb052a2943cdbc157776f0292eb425 docs/daria_fe/spec/dpcplus.md
eab8db5a542909d12f25406de82cd8e52ca25086 docs/daria_fe/spec/glue.md
fe661d7c4ef0002d03b1164274695a82ee8434d2 docs/daria_step10/plan.md
9018b891c88f9e32b2b89d262175b1bb4c0c3102 docs/daria_step10/rev0_record.md
98fa6f7c457bf758abfdcc5690a4b2b126afeac5 docs/daria_step7/plan.md
db5aebf3693faa20db77f8be65039e60c7c89d41 docs/daria_step7/progress.md
61d5df040dac00b85da6857849f62e5929ba32fd docs/daria_step7/record.md
afb806b4c4d86b4a29d7eb20932f133bf28e6a76 sim/ar_test.py
7e772c92dfca4354c3950258f383e569dbbe47b6 sim/atarivox/allophones.txt
7d5c72ce49a4bb1be28fff974de96fd51f93f667 sim/atarivox/effects.txt
cab6c5273ed13553ff54822d1fc23ffc764233e6 sim/atarivox/hello.txt
69aed6f92705868fffb01095203ff6cfe19aa8e5 sim/atarivox/juno.txt
268f73ad2c5f730a970d0945979368ab260f4638 sim/atarivox/run.sh
8a68205bc0e6b871d1dc111b319add5fd717eec8 sim/atarivox/scp.txt
d2ab369eb711da89b336349d8185afb69e862ec5 sim/atarivox/speedbend.txt
be9f31bdf571e7843e2eaadeb1ee50ba3982d0d7 sim/atarivox/starraiders.txt
d39f82f3d7d892f8bc7ed831272f7e9c249eadc9 sim/atarivox/tb_avox.sv
c7b5db5a29f7bc46dcc22d4bef20b488f208d8a2 sim/bupchip/baseline-2.0.21.txt
f17c340670cbbb33e535886197e7d0e2e7a5eaca sim/bupchip/daria/call/build_call.sh
15f56e6e78e398cf1e9daf5bf3b8e0be7796b2aa sim/bupchip/daria/call/run_call.py
78b9d651d7f17386042d44c411044901d0bdb0cf sim/bupchip/daria/call/run_mutants.py
0db8f25e0f496ef96570131d95527ca2c546f3a4 sim/bupchip/daria/call/tb_call.sv
fe1d84916e08b99c435293aad5906ea678314a2c sim/bupchip/daria/capture/run_capture.sh
0884dd2af7bfb671b0165129bbe8f528cafefd4f sim/bupchip/daria/capture/tb_capture.sv
beabf9659476e498072d0a426f4afd2515282eba sim/bupchip/daria/daria_scan.py
ae2d3aba65419bcb2afe92d25357cd3c31bfd0a6 sim/bupchip/daria/daria_shadow.svh
09cbb4bd4e4a33278ca813cf2478c1e36b72fbc5 sim/bupchip/daria/dynamic_tables.py
c882fd1e9a1d84968bac655d617a63dec43289ec sim/bupchip/daria/fe_dir/armenc.py
af11b5f07ca1ef3275aa194fb7315e518d7487c2 sim/bupchip/daria/fe_dir/asm6502.py
0cbc6175583a80c71efa292a68c18a3d060b6260 sim/bupchip/daria/fe_dir/dircheck.py
176ed281c4ccc81261b2206925ab144cb69291d0 sim/bupchip/daria/fe_dir/fe_dir_mon.sv
69586b5c4344956d7d7491939f17a6df298fb5b4 sim/bupchip/daria/fe_dir/mkimg.py
14cd3e05412e58327aa8b9cff60fa9103bedbfe8 sim/bupchip/daria/fe_dir/mut.sh
8658b48f159af96246f62db4b8d975ee8834fbd8 sim/bupchip/daria/fe_dir/run_dir.sh
bfa453011eccfdb1d74546ecd224fc4de231b0fd sim/bupchip/daria/fe_dir/summary.py
851caed927d487f782c688a1d875be381ed3c0c2 sim/bupchip/daria/fe_dir/tests.py
dbf450f1341fdfccb9f55c6f74052322b17ddbf2 sim/bupchip/daria/fe_dir/vwrap.sh
56522c2dc3af1e512c0574b11a9d7c83d249d207 sim/bupchip/daria/fe_rand/campaign.sh
667e1c2e627bd1c0119a43ef4e8f9821cb04064e sim/bupchip/daria/fe_rand/fe_rand_up.sv
45e0cb7a532da092f47b55bd3eab7b971bbe1849 sim/bupchip/daria/fe_rand/mut_rand.sh
ff981db83ac39d0ca79f2620c08f9b529cb742fa sim/bupchip/daria/fe_rand/run_rand.sh
27a228f21e0859d9d507e29c4a2dfc6be40d1947 sim/bupchip/daria/fe_rand/tb_fe_rand.sv
65ca6c2ebb0e3335f18b586c288d9c94b66f32da sim/bupchip/daria/fe_shadow.svh
e241650fc0a2504f08eef60c03e623636dfec117 sim/bupchip/daria/fe_taps.svh
c1430db938b09aa5c1b92a2c33433f49657c00cb sim/bupchip/daria/fe_unit/phase_gen.svh
d995b3ad804effd47874600f2de662a5aebe959c sim/bupchip/daria/fe_unit/run_unit.sh
762ee5f84e1ff5606d4e3a5633a6ac31ba70b937 sim/bupchip/daria/fe_unit/tb_fe_arb.f
a84551be840ca9a475e2879707b329ce29a79a51 sim/bupchip/daria/fe_unit/tb_fe_arb.sv
5f0c077571c5be0a3680cc6dd3596e0bdb1b4c39 sim/bupchip/daria/fe_unit/tb_fe_arb_mut.sh
39353869d1c64daa404ab031f0fcc597a5d033c9 sim/bupchip/daria/fe_unit/tb_fe_arb_probe.v  (imported as 7a1534115068bca175e1fefb2b2dc4de232471e7)
5505e4e78cb2c81242fa8edb821b10e5892274f7 sim/bupchip/daria/fe_unit/tb_fe_audio.f
4e42fa5ddd3ff5b0cb76b40119267949f88a52d2 sim/bupchip/daria/fe_unit/tb_fe_audio.sv
e3da9570ddf1c10ac8ce8344d7471a5479524ac3 sim/bupchip/daria/fe_unit/tb_fe_audio_mut.py
de35f0fadb539686ff8e77c571aa690f26dce155 sim/bupchip/daria/fe_unit/tb_fe_audio_probe.v  (imported as e42ab2ba0ff19ee7a703027fe1c0929682a58f55)
9a98da17fe3f6b9e024ef6f8ef85f87b2519e2ca sim/bupchip/daria/fe_unit/tb_fe_call.f
4713df7a156994ce258e660e4f05fbf319d230f8 sim/bupchip/daria/fe_unit/tb_fe_call.sv
8b2d171caba169383d5bad3f310ebc01378833f4 sim/bupchip/daria/fe_unit/tb_fe_call_mut.sh
9867ec866481fa61a6adeacd06d3ad6878972441 sim/bupchip/daria/fe_unit/tb_fe_call_suite.sh
4b069320337e1d6a420a41552ff6763a4c99b53c sim/bupchip/daria/fe_unit/tb_fe_copy.f
72bc5734b70c3379840558726fa005051c7e963b sim/bupchip/daria/fe_unit/tb_fe_copy.sv
e48b9b52910ec0e475817719e870cb1eba9a595d sim/bupchip/daria/fe_unit/tb_fe_core.f
a0a3fb0cd7d055a0f221f31003492fe66afb540d sim/bupchip/daria/fe_unit/tb_fe_core.sv
aa8c62a14de9827a0dcaffa801ecb928eeb03bd9 sim/bupchip/daria/fe_unit/tb_fe_core_mut.sh
68d49785809a1a320bec38900f12f32d3f4dd382 sim/bupchip/daria/fe_unit/tb_fe_guard.f
2126bd8185aa49c736cc2969ad91dd24c0942dad sim/bupchip/daria/fe_unit/tb_fe_guard.sv
7f7dade939ded687a85c07d1527b7fde2de26b0f sim/bupchip/daria/fe_unit/tb_fe_phasegen.f
eba6c3efac09f8aaee652a32f79361a9d388982f sim/bupchip/daria/fe_unit/tb_fe_phasegen.sv
19697a91f320a5ec432d51c6ce74d80cbf067711 sim/bupchip/daria/fe_unit/tb_fe_rampoison.f
d3b0dbcce422b870197063bcd28e5401f1984e75 sim/bupchip/daria/fe_unit/tb_fe_rampoison.sv
fb0a0df7b9e989d15ccacc1cc692f7ba7624470a sim/bupchip/daria/fe_unit/tb_fe_seq.f
582d4ccabe9dbe51ad6f22bf4509957774c090b7 sim/bupchip/daria/fe_unit/tb_fe_seq.sv
ac0a01844ecdcdf8c8c8303c770e92f80067154a sim/bupchip/daria/fe_unit/tb_fe_stub.f
9cc4b17a0498cc9008629cfb9b66ac55fc9b0260 sim/bupchip/daria/fe_unit/tb_fe_stub.sv
a3bc3ec247ab865ae115af8486f0f8528cde95cb sim/bupchip/daria/fp_compare.py
59fe27699f31d18e49d3eaf20fda19453d4d4b05 sim/bupchip/daria/frontend_study/README.md
d40344319d417d53c99d4712f8babe80a733ce32 sim/bupchip/daria/frontend_study/daria_fe3.sv
c6c2a5d2708908a50f7b867bb25edffb38bbef03 sim/bupchip/daria/frontend_study/gen.py
ebccda6dbb0780062652b233992df8c2d067b796 sim/bupchip/daria/frontend_study/run_study.sh
dd0495b1790db5c13fbe864da845ad2514e87b46 sim/bupchip/daria/frontend_study/variants.py
c8c5afcef3dc051ffebfde9055a367c6c13d134f sim/bupchip/daria/mam/README.md
54114d9f241ba3038586bc5e2528e140ea4ba830 sim/bupchip/daria/mam/acceptance.py
7aaf573e4155363c9c323a468a35a2906e4cba41 sim/bupchip/daria/mam/dircheck.py
9c00877bf6c78021f13491b6d0f2a0947d0c2bd9 sim/bupchip/daria/mam/dirtests.py
1ac2400a56b35b4b41232a18a61f30082a348630 sim/bupchip/daria/mam/mam_analyze.py
418cc982925a4fdfac64283647bbacb2813a9799 sim/bupchip/daria/mam/mam_check.py
d94d339d6269921217ca8f79e6996ff3dc818cbe sim/bupchip/daria/mam/mam_model.py
5669d7853cc9e2a49892c96d333575cfab8157b5 sim/bupchip/daria/mam/mymam.py
6a4cd867b99e83ff8627b82332a2cf882d43626f sim/bupchip/daria/mam/mymam_check.py
371b7bdde176451906a6538cc93bfd45aa402a11 sim/bupchip/daria/mam/run_dir.sh
c35ee34ca19f7492d2dec2917d21d1ed43e32fab sim/bupchip/daria/mam/variants.py
9237d3529fc2c5ab1abbd3b146a114a0641fb1df sim/bupchip/daria/mmio/run_mmio.sh
e00f2daf580a5998e6c76968da1d45c7f065c9be sim/bupchip/daria/mmio/tb_mmio.sv
9fa5c80554b4b633797eee1558450d83c270534c sim/bupchip/daria/modes/modes.S
e7117a343fe34e780a5be78252cfabfc66cba711 sim/bupchip/daria/modes/run_modes.sh
3090f051c07d9997976ff0761a9585057f706167 sim/bupchip/daria/ppm2png.py
7965341153b9122bf6fb6fe7fc4f57cfca374031 sim/bupchip/daria/run_all.sh
4ffdaeef88e9a724ab2156b4f35ca60fdd419437 sim/bupchip/daria/run_daria.sh
7c5fae193ba7b9f5b39bc26af49125c80324f6cd sim/bupchip/daria/smp/run_smp.sh
5bfe94573588998b0b71950c24587694d28fa2d7 sim/bupchip/daria/smp/tb_daria_smp.sv
8c9412e55129d2cc127feb08528643b30ae07163 sim/bupchip/daria/summarize.py
bb733b7b588295b507a2954f65277383829eeafa sim/bupchip/daria/tb_daria.sv
177ab03d4f57e9d8ffae2ff1da97ee00e82af250 sim/bupchip/daria/thumb/README.md
0de3a49b1654d12551fe08c6c3323f2e1ddc0904 sim/bupchip/daria/thumb/aria_equiv.sh
706a0ad5aec1f0c6e360cce01f6cafdd5f0bf5e2 sim/bupchip/daria/thumb/build_tb.sh
3d4690a757d67c2a50fe47a2b95e368af61e8e1d sim/bupchip/daria/thumb/directed/alu_imm.S
d4265cd7ec74bc111d10e39e71ec64bf8833d336 sim/bupchip/daria/thumb/directed/alu_reg.S
6dc8a878c2ff5d68899e285f41ecfcbc0eb96fc1 sim/bupchip/daria/thumb/directed/bl.S
131f90a08c41ddfc46daa851da2543741a46e96e sim/bupchip/daria/thumb/directed/branch.S
5cfbf738f049120c073e7244b33a0ded6585ba7a sim/bupchip/daria/thumb/directed/bx.S
a9f7c02a16ff2c0a2584aa2880cf712a83acd919 sim/bupchip/daria/thumb/directed/common.inc
4d06acc030b0c6ffa3bd8fd7cc0f49c21e794f59 sim/bupchip/daria/thumb/directed/hireg.S
9d10a2c928d26c941049a1f88f3023fb5f27f372 sim/bupchip/daria/thumb/directed/interwork.S
626df193d3107c3078a1e9886c69a9d806cc9950 sim/bupchip/daria/thumb/directed/l1f.S
1583f394b9379390dbd5da9ba6b7e5918b768b78 sim/bupchip/daria/thumb/directed/ldm.S
e8c3b54b52daf71ac67159fd10677b98198568fb sim/bupchip/daria/thumb/directed/ldst.S
4e311f65d750672b068325d3e318efbd7b884319 sim/bupchip/daria/thumb/directed/mul.S
2242f86076115c341a65a94a410ba1d29903758f sim/bupchip/daria/thumb/directed/spmix.S
d945034bda8e475237840dc027cf5b6d37ae2f17 sim/bupchip/daria/thumb/directed/wordend.S
0414d2cef046547e7a9b2593376bd334a3f8dc72 sim/bupchip/daria/thumb/gen_thumb.py
25bdd919ae8827e967c887ef4400b557f121b281 sim/bupchip/daria/thumb/halt_thumb.py
486ce69f4b626c5e572e2cfc48566c1f369790ae sim/bupchip/daria/thumb/index_depth.sh
7dae18acd29061091c6e20a1ad4dfc24ecbfe724 sim/bupchip/daria/thumb/mutants.py
d1dada5be626ddf221ab4a90f375b0aa3e2c47fa sim/bupchip/daria/thumb/run_decode.sh
55a3d8db69c131e8eb2fed155f46b756fd4df14c sim/bupchip/daria/thumb/run_directed.sh
dc1c3570927802f8a07aab66a5d48b6ec8132fb0 sim/bupchip/daria/thumb/run_fuzz.sh
50c22759f59baa1e46ed9e12e3ec09baaa65558d sim/bupchip/daria/thumb/run_halts.sh
f6b285943a58701a26e67b67310064500b769be0 sim/bupchip/daria/thumb/run_mutants.sh
dc799b8a01e919736a843a118ce3c178dbe67643 sim/bupchip/daria/thumb/run_random.sh
780849f870de95dd143415d55fa4a0ff3c0c580e sim/bupchip/daria/thumb/tb_tdec.sv
7c98a97dc22a8bd8c7e4d9a863e8bbe51c25fb6e sim/bupchip/daria/thumb/tb_thumb.sv
03e9ce65906f96374a1ed599704ec5fc81fc1c9b sim/bupchip/daria/thumb/tdec_check.py
bdb56ee54e2ca529697558a276b9ce54a6c8e7af sim/bupchip/daria/thumb/tfuzz.py
7069cc36a44b5e2f4b816c802d82bb26e5714bec sim/bupchip/daria/thumb/tfuzz_run.py
716295a03c2d4dfe350f2840eaf2acf0ef8f81bd sim/bupchip/daria/thumb/thumb_iss.py
3091afacf5037883c673f5bc2d873af56bd12a5c sim/bupchip/daria/thumb/yosys_cells.sh  (imported as 0c305ec25d94e3c02b49f2788e5797037a0a504a)
6a2cd16de859b35cfe01b9783ef0037d5f69f785 sim/bupchip/daria/thumb_expand.py
ef8d0f03a5294bd9b379b085d6fbdfc11d51fcac sim/bupchip/daria/wire/run_wire.sh
e8106674550062a141474bb2fd2f6fc78c41570b sim/bupchip/daria/wire/tb_wire.sv
35ebd51fc65038ded2bb838f2cd6e7fbe65be56e sim/bupchip/daria/wire/wire.py
c908069607eb5240e6e32332a22658c740253442 sim/bupchip/dbgsnap/run_dbgsnap.sh
1282ce70dbb2ad0d134b79893b9e6b5ae574d0ef sim/bupchip/dbgsnap/tb_dbg_snap.sv
aec02d28e2eb8e603c6fab447c00c1a4ba387353 sim/bupchip/dstat/run_dstat.sh
8e365657285dea498e0f1ad9ae1d79f9d40f2db1 sim/bupchip/dstat/run_ovl.sh
1734cedd14f023f9ac1e58808c1309b91e5c3942 sim/bupchip/dstat/tb_dstat.sv
b60971c3d3ef259ab16d3733cbe752ae7a62002f sim/bupchip/jukebox.py
55517a8e72ff75058808a07389da12c6c44a5a12 sim/bupchip/make_arsc.py
c18dd8d83ceed1806b50b0aaa46beb7e335fff13 sim/bupchip/model/.gitignore
a489545110c174605e61f7fb3e43e4bd32ad7314 sim/bupchip/model/README.md
a9386294879bc01eb7bddb7c4b97556b976ea62d sim/bupchip/model/armdec.py
8aee880afa799076eec316bc3dd346f7037f8ddd sim/bupchip/model/armemu.py
2e636eeaa9160f0250e2842ef565e69e4b588163 sim/bupchip/model/check.sh
a9274c290f8881dafe85325246af8673d7536dca sim/bupchip/model/coverage.py
91868372e7416d531be6fd0b941a7ca6476ca0b9 sim/bupchip/model/cycles.py
16abe5415db7149ea28beac6f8e4fe51cd112ac2 sim/bupchip/model/inventory.py
5832bbb1634982174a910ff1dfe5a0743d34366a sim/bupchip/model/study/README.md
d412e85db0e5a9de033376d8430c0b1d4cbd23bb sim/bupchip/model/study/area/bup_core_sketch.sv
157f5e8d1c8c59a3343b178bf4ef73ac56f77cf1 sim/bupchip/model/study/area/parts.sv
bd9e87c70b58303ac601aecc06c341b1af60621e sim/bupchip/model/study/area/run_area.sh  (imported as 6543d490f48fc8ecf74feaca233975b3f7603dd7)
dbbfb9dc60531fa83da59d8d7e4fe73960dc8254 sim/bupchip/model/study/fifo/run_fifo.sh
be775ad8afdaa4559868e260d9555771d14ce885 sim/bupchip/model/study/fifo/tb_fifo.sv
ed05625cee1446279fd79f3fd56f6d04cac6b4be sim/bupchip/model/study/psram/run_psram.sh
070ae14865e29e3d6302ae055feb6fc879b3172a sim/bupchip/model/study/psram/tb_psram.sv
6f2ebc99f1f35ca7abe00c516afd852972fb0b87 sim/bupchip/model/study/sketch/bup_asset.sv
36c6669d9d86adb27fa5a5381a8bd22313581e8e sim/bupchip/model/study/sketch/bup_asset_v1.sv
f453d29171a3d8adb3f569a736502d3971b66326 sim/bupchip/model/study/sketch/bup_capture.sv
207ec6b3d923a90a2ff96b50bd437bf7c856ecd6 sim/bupchip/model/study/sketch/bup_cpu.sv
4a6821066b18885e7b1e171208263a98b278c55e sim/bupchip/model/study/sketch/bup_pocket.sv
b25aac887a91c7d1cc0784bb13577e2a0c634072 sim/bupchip/model/study/sketch/bup_psram.sv
5cb123bb972e5ebe399858e9293722c345696230 sim/bupchip/model/study/sketch/cmp_ref.py
2593fbbecc841ff3ee222deac28f48cf8baf3b3b sim/bupchip/model/study/sketch/run_sketch.sh
f1bb1daac6265adf05b1b78c1ce4e92aeb3f05e5 sim/bupchip/model/study/sketch/tb_cpu.sv
692b74a5837193d00c8bd5a08b8f14e787e1f390 sim/bupchip/model/sweep.py
0fb3b08a01c90f296e48687fc5143d997281f026 sim/bupchip/model/synth_arsc.py
d7035acf1575a28c8bdb9251ee873c11905c7838 sim/bupchip/quartus_probe/README.md
358c22bea3ff76afa5f00920bd3033cfeb794844 sim/bupchip/quartus_probe/bup_probe.qip
9a3a03197f5e8dafa0ceef2912b10db2cca6ec64 sim/bupchip/quartus_probe/bup_probe.qsf
a5ebcd57d015902f1a22dcc389080bb3aa0dc1b9 sim/bupchip/quartus_probe/bup_probe.sdc
bdf93b1c2bfae40d59fd4b099abcac1250196851 sim/bupchip/quartus_probe/bup_probe_top.sv
98965c989514ab06867763cb962c82a14cb433ec sim/bupchip/quartus_probe/daria_fe_map.sh
3dc3567ed39c5dee2059e2eee441499b094d85ee sim/bupchip/quartus_probe/daria_fe_probe.v
ff7dcb1847a9afcb987683f191c348b83b3dbb69 sim/bupchip/quartus_probe/daria_wrap_map.sh
3ac2d07f9368455178e40ecefb7846b62b5e5810 sim/bupchip/quartus_probe/full/daria_probe.py
14e79f47d5e2e545b10c04736414061b356e92f3 sim/bupchip/quartus_probe/full/full_report.tcl
d3b18b1bd1724d6296f0d82edf091b1d8e53567d sim/bupchip/quartus_probe/full/full_summary.py
8d55c48ca6cb33c98eaa50012ccc1e0fe8de939b sim/bupchip/quartus_probe/full/run_full.sh
118cdf5f2c1868fe29bf791fbb4efa4466ad6285 sim/bupchip/quartus_probe/probe_report.py
04d17864f4fac6b019d97a63a23c300bfac5241a sim/bupchip/quartus_probe/run_probe.sh
2f290d83a5d1c2fb8ad39eb3ae865085878e17d3 sim/bupchip/quartus_probe/step7/f3_crossings.txt
ea976c820a9b3df6d45ae5424132084ec4074360 sim/bupchip/quartus_probe/step7/run_step7.sh
494542a3713d79de51ec959450185ff529573636 sim/bupchip/quartus_probe/step7/selftest.sh
760a6cc52404f32e3507f6688ba0807eb83f4dc4 sim/bupchip/quartus_probe/step7/smoke/run_smoke.sh
0222fd672cb8a2a22e1fd2e957309fb6fdec1e63 sim/bupchip/quartus_probe/step7/smoke/smoke.sv
8949585089309f2d62d9494742e655fd24870df6 sim/bupchip/quartus_probe/step7/step7_checks.py
e88a142a905932f56bfbb72c36def1a68c7d64be sim/bupchip/quartus_probe/step7/step7_lock.sh
7ebe196f6895e7aedb23e6e4fa6f60c831894bfd sim/bupchip/quartus_probe/step7/step7_prep.py
2d6d0f5ef3e821ecfcd28051928c5705f1bc053a sim/bupchip/quartus_probe/step7/step7_report.tcl
2dab54ed002b6f44fd75ff05de6346992aeb8d4d sim/bupchip/quartus_probe/upstream_arm_map.sh
48a05091eaef497aedab88de643cfcd19196b604 sim/bupchip/run_bupchip.sh
9e30feb6635476c01672292bced80c2a7f832826 sim/bupchip/run_jukebox.sh
91902fe453e7486930502571043f1d9e7c9fc5b2 sim/bupchip/s1/README.md
b9194cab68975455e2e7ca7ca23f0d46b8530c80 sim/bupchip/s1/build_s1.sh
4b17986a05623ce5163e27f1dbd2255acd46fcc1 sim/bupchip/s1/check.sh
1e2e49e3fecbefc97e6d0b4550b52bc7977053ca sim/bupchip/s1/directed/align.S
0b1b38da8624989b8d37cabdf28877fb1b56f83b sim/bupchip/s1/directed/common.inc
09db03224091c555557d76d0e01aa5a87c70d5ce sim/bupchip/s1/directed/condfail.S
ad0dff71070a2cda9ef8ec5b79e60ac3b8e8c4b5 sim/bupchip/s1/directed/deps.S
7d83f65e7c195ccf841b1423c867d36665ab63e1 sim/bupchip/s1/directed/flags.S
8d7bff93e8aacc804cbfb4a0d4222a993adad15d sim/bupchip/s1/directed/ldmstm.S
d3e22f1cd398506b5715478141c6dbf7474faad9 sim/bupchip/s1/directed/ldrpc.S
19f2c86be5e7905dd6990f6d7861ec7357944a6d sim/bupchip/s1/directed/mmio.S
4b23b809934c681d5ef1249f77dc1609618c9eeb sim/bupchip/s1/directed/mul.S
258d820f6dcf3014d738d7570614a85f8ad7f82e sim/bupchip/s1/directed/psr.S
e5767ce0b9edadc513d91b4a9ca42d0b0776bdd2 sim/bupchip/s1/directed/regzero.S
b7a3f6ca07749a3381e0c96c8c23c9834408fc0c sim/bupchip/s1/directed/sbz.S
5bc3b35f3e297b53f4a0ad2c319a839e71966045 sim/bupchip/s1/directed/shifts.S
9b16a74ff0ec70609d2846b07c74e94122830754 sim/bupchip/s1/directed/writeback.S
3d7fec85c24ed8f7d25e8222c1d090ec33a496e4 sim/bupchip/s1/halt_tests.py
3a28e887b3b89576a26e3b43a986fc363d183638 sim/bupchip/s1/pcm_check.py
fa47497f145f8a6707ac9a92570ce15211611442 sim/bupchip/s1/run_directed.sh
a7821cf7789fee2fd625a3b03a689c1387b11407 sim/bupchip/s1/run_s1.sh
7b5f4c4e93e1dd29b758e1f89f1bbec2db954016 sim/bupchip/s1/tb_s1.sv
2ddcfada4787990da92c5ccb449e633b4e16b8eb sim/bupchip/s4/README.md
76e2d33ed48b3dc609440440f86d909b056b073e sim/bupchip/s4/build_s4.sh
c78bc8d42c31993c1d0305d0efd6678800a5e210 sim/bupchip/s4/check.sh
baf7ae373a5386497aab08e32618d96292eeab92 sim/bupchip/s4/psram_model.sv
162d3bfa2ade17bc47e9d332e77979386a96ddde sim/bupchip/s4/psram_standin.sv
98c1729ce8669724749ba63c2d2892fd54b87942 sim/bupchip/s4/run_cache.sh
fcbe0c09e7be51f451e06057f4f562c0c7edb557 sim/bupchip/s4/run_psram_ctl.sh
d03a64f0557f72e065b2b81d95259be1df15d563 sim/bupchip/s4/run_s4.sh
e83349e34469af133d62a8d738e07faf9b708443 sim/bupchip/s4/stress/README.md
43f7c62d5d18670a48e5d3dc22878b2bf33889c4 sim/bupchip/s4/stress/cache_ram_poison.v
44eb30916782c434919071800e27fdc8c7f8c4ea sim/bupchip/s4/stress/fw_bounds.S
68d6da2f7bccad3e18b92eed28bb11f4164c58a9 sim/bupchip/s4/stress/fw_pophead.S
1601f8c36b5f49304ae30de05daaef162f4eb47f sim/bupchip/s4/stress/fw_xing.S
883284290d8ab23ef15e3b5dd4e891db75e0c574 sim/bupchip/s4/stress/psram_var.sv
31768cd68c13e2987dcbc2b41d5aeec1b7cc3157 sim/bupchip/s4/stress/run_all.sh
9c800bda0858d2c682d9ab5aa0b6bda8f5a000ed sim/bupchip/s4/stress/run_bounds.sh
c1b040cf36ea090aa79cd20cd121cdcddf22d750 sim/bupchip/s4/stress/run_capstress.sh
b11f8376818e2bcad75f6643ce7319b013e81b2b sim/bupchip/s4/stress/run_cstress.sh
1d999f053f7ec3fc7e968d621a37d6c4ac5a0bff sim/bupchip/s4/stress/run_pophead.sh
5420e9d07ab031c19439d7009ae645aef2be2913 sim/bupchip/s4/stress/run_reload.sh
e4e6911d73aba7144bc81cfe733c5fb66abde910 sim/bupchip/s4/stress/run_slotswitch.sh
8e55dafd41aa0f74ce478f187813ef26152b27d6 sim/bupchip/s4/stress/run_tick.sh
34701a7a65d20dd8edc57fa79ebe164c2295e7ac sim/bupchip/s4/stress/run_xing.sh
b6c8336da2d05c2b8f0266074a9d30cfde73dc0a sim/bupchip/s4/stress/tb_capstress.sv
01494f9f83d087c9d4270fc77b084537ee2d22af sim/bupchip/s4/stress/tb_cstress.sv
8868f540fcbccf32736b68d3dc28e0bc764502eb sim/bupchip/s4/stress/tb_slotswitch.sv
8203a29aa8188d8003ce2ed9cd6761b7bb07bbdb sim/bupchip/s4/stress/tb_tick.sv
15584582968907c7e9716615d655ac3dbee73365 sim/bupchip/s4/stress/tb_xing.sv
34d725e479791c18af142d6e5217351de41e097d sim/bupchip/s4/tb_cache.sv
79f25376b29be5197f67414e8eff16c091a578a2 sim/bupchip/s4/tb_psram_ctl.sv
3cdb89e0950cd67b1fb413388339a21e8569944c sim/bupchip/s4/tb_psram_model.sv
f8454e7f50658b5891238cde1c0e251bdd7f82a9 sim/bupchip/s4/tb_s4.sv
a997ab52e8624219430ea328ca718c1e44d2c894 sim/bupchip/setup_dev.sh
0a5f20e8fc5d184a445999923618dac0cdfcfd26 sim/bupchip/tb_bupchip.sv
9ca5019afec397321844081aeff39480a4d11d7a sim/bupchip/verif/README.md
80dd1984cc34161d2a9621d3df0f91f2f77cb700 sim/bupchip/verif/build.sh
850218649d98d661dbd2628a4f6b4a8dc3b5cb81 sim/bupchip/verif/directed/README.md
dab2fc7d1f52d0764cd62267c21d6cbe2cbc3e37 sim/bupchip/verif/directed/blk15.S
50153cf2572f9efebc72d6dc6451f4f43b9ff548 sim/bupchip/verif/directed/carry.S
fd7dad4f2113622239c94738f308ae1e555c4e7a sim/bupchip/verif/directed/fuzz.py
83f36c3b4c5bdecb41006a8feb9a22425bf9d4cc sim/bupchip/verif/directed/fuzz_run.py
9b6ee5bf476e0418d2a36de697db492b91ad6d11 sim/bupchip/verif/directed/pcops.S
ae4282450e2242ed36884b2eca29bab5fbb15b1a sim/bupchip/verif/directed/romend.S
48b89734f30c8837f50faa1e52403e5b09bd6e1c sim/bupchip/verif/directed/rsamt.S
702c8eb3811ecdb54c00a9b42680b137602f61e6 sim/bupchip/verif/directed/run.sh
a8c7b2adf2eac9beeedda3a44ef73e12c313656c sim/bupchip/verif/directed/run_vfy.sh
2e33e7a670c33aabd2c45db0eb66cde40866880d sim/bupchip/verif/directed/run_vrand.sh
ac40cdf93e8b26f4729cc8798304be6a03409bbb sim/bupchip/verif/directed/tb_vdec.sv
c7dcb8e9c5d8b46bf34092d1370dec357cda4da8 sim/bupchip/verif/directed/unpred.S
401e24bd9803aae0b8f4681f03533b87722e6963 sim/bupchip/verif/directed/vgen.py
b8a8567da386e7762ebef31e61e141bd0d53aff0 sim/bupchip/verif/directed/vhalt.py
333097d3ceef41ff4e772cef12db7bdc7d0ee52c sim/bupchip/verif/directed/vrand.py
3d5f7eb11e590258a5e812ca676a445bff4dabfc sim/bupchip/verif/directed/vshift_all.S
ef09d98243d5322a7acc080cc3209459b46bb595 sim/bupchip/verif/isa/bin2hex.py
103f43ec6ac205f90e8203ed0bf1ddb55e527964 sim/bupchip/verif/isa/gen_random.py
27501b400e9812f453c33c6976e6eb0aadb5a29f sim/bupchip/verif/isa/iss_run.py
0efff3efb1b8e6e9af48292097c10fdbf8cf0def sim/bupchip/verif/isa/link.ld
ac4b599f1ac8d07176afbad5107f42ad5ec1f4c0 sim/bupchip/verif/isa/run_isa.sh
ce201a2f182e72411be167063d371e4bf7eca643 sim/bupchip/verif/isa/sample.S
45b87af9d2a0f4f52d65a44dddd79f2e2fa86ceb sim/bupchip/verif/isa/seeds.txt
97be458ab69c789b462560dea1099802e0be858a sim/bupchip/verif/iss_fw_replay.py
b57e713b9002c667818d7d742652f66fe3621e9a sim/bupchip/verif/kernel/harness.S
86f54d4642ed1c9e9b2fb85360cdd824eed38c43 sim/bupchip/verif/lockstep_dut_bup.sv
1e36d6137e591adcd498f01c48082141c7280979 sim/bupchip/verif/lockstep_dut_ref.sv
b8ce61170d4ca9a5dfd12ebf7cdf8cd5cfeb2b61 sim/bupchip/verif/make_kernel.py
00fd7d7c7873e5dd8012dee03430e1c5ddf7024d sim/bupchip/verif/make_synth_arsc.py
d4cb44ff0813cec2fcecc77c22e70237bbf7cc0d sim/bupchip/verif/ref_system.svh
50d269a0dd45ba9f59d4b6afae79c964c58a8702 sim/bupchip/verif/run_all.sh
de6f073f5f34c30d8790a92099b7557b84552b4b sim/bupchip/verif/run_kernel.sh
a177965398b28d7f308680464994bc9bec144d41 sim/bupchip/verif/run_lockstep.sh
732854a14e226e7c5e0415ed61a269542cff9b72 sim/bupchip/verif/run_songs.sh
ee92b94943d2fc37280d907780c320474b2481f6 sim/bupchip/verif/run_synth.sh
db5a1d61caf1b4bf8cdc54c7cd79b902ed5c015c sim/bupchip/verif/tb_lockstep.sv
9606c98261768988d9bdca5232734bbad4afb02f sim/bupchip/verif/tb_ref_trace.sv
f2d35b167efe4bb9fed1801579a69c5bd443e153 sim/cartram2600_test.py
c7999363d8fbe8b175e3bea54e179a85e282a895 sim/check/div_check.py
bec1dccc8a19bda044e5de6b0a1deba21d5c405e sim/check/extra_tests_check.py
3948e026e8e4920db1975e2326dbb6dbdfff4b73 sim/check/frame_gate.py
95314d93863da80708384d0f7add107f7f47c121 sim/check/hygiene.sh
4e2b0e2624e762b7775c6d944f745ce74e05c164 sim/check/multisprite_check.py
f4bfd62bf43c7e5fdd13463e69802570cc3b3b22 sim/check/run_sim_check.py
66974ec38ab372a34416518f0df84ce3e1274630 sim/check/selftest.py
756d14f40ec71ce4b7aa1b3586ef91e11ab21c59 sim/dli_pokey_test.asm
d5913f40ba52afe74047ae182cdcc256e353e342 sim/extra_tests.sh
d90f8b76be81476301bb951a5d2279cebf377838 sim/fa2_test.py
40d1fbac6312e41b8b8d9eeca455c8e8105c49cb sim/input_test.py
66ffbcb4b3d9e2800422a0553e60ae13faa72de8 sim/lint_step7.sh
ccd6c44021075dfa8e2bec0bfe64de29cabeb485 sim/make_a78.py
80bc608cca7173c32055168ffc13abc890b2ae7c sim/pokey_compare.py
7d52d6db576dd27bc45224555ce61ca75f31a187 sim/pokey_model.py
e083719f38e4a8296eb7da5bf04fee2dddce2fb5 sim/pokey_read_test.py
b3862150482332dca0e2babeff15868f34121d5f sim/pokey_shadow_compare.py
77b89defb6ba9d1c84312485fd258b8d0c605443 sim/region_unit.py
76068644756e5a5eb7f0b80935add9cd6b0e0398 sim/run_frames.sh
d4ee2c22bcf08aec1959f83d9eb80fffb4d82205 sim/run_pokey_shadow.sh
67b9ca766af931b78f5c24651def57ba7237003e sim/run_region.sh
a80262456f23c0b0b1800e9d396e6eb67a3e380c sim/run_sim.sh
f92a623039ce026e18931b91690da393f64845bd sim/run_vaxis5.sh
a53d142443066f3032d4196748d48c51178d1d95 sim/savekey_test.asm
930d68c1050f532332680c668d79db2f50f96620 sim/sim_stubs.sv
e0ebda1d0288067b9e1686ff8161e29d72c5f3c4 sim/souper_test.py
fdc918978de28b1ecb02a91adeab0ee42e6e3a6b sim/step7_gates.sh
18943a522a9989f9147eab5dcec51a667ffb32dc sim/tb_audio_filter.sv
c5765167f2b6204fb168b2f1161394559db90338 sim/tb_cartram.sv
4b82cd9d68d23d9135f70d9a0c7411bc42e5ad02 sim/tb_frames.sv
2284c9f7e1e5684e7ecb0504a5c4b1bd6d7248bc sim/tb_load.sv
83bcd0876b05faabd31e7ae82c71bd7ae672847e sim/tb_pll_region.sv
9551650a5c488962be7fdf5eaa6fdf0809eb2fe1 sim/tb_pokey.sv
ff380bda97bdbf8cba288d0c4f843f7a6a9d88fc sim/tb_pokey_init.sv
4480ce83f765bb61212126cdb701e047a26d5d94 sim/tb_pokey_replay.sv
5ace9194facc569a9e58f9ac6e56d27dddc6ca84 sim/tb_region.sv
5823d6adb6ee613fcc8bed2d8f7b503fa759e680 sim/tb_system.sv
74d98f33efae908ed795ad044acc056a2fe6acf8 sim/tb_vaxis5.sv
01f8ae9b0e18917b789f05b907f2987bfbf06274 sim/tb_virtual_axis.sv
95dc7231ee9be0928b5bcbba33991905044fbcae sim/tone_test.py
fb5149c1a08084957bc966e47f3411bbf88423cb sim/tools/pp_equiv.py
028a1efb12f24d4cdce7b3d7a7faff1f7b43f650 sim/tools/pp_guards.py
9a86df18890471b2d1e7a3d30152c925862a4c46 sim/vox_test.py
9d946bfc127426a1e924b386df3a0a6075eda32a src/fpga/.gitignore
dce59fc103fa6b6f8c2ba9682550e5658c4ebd6d src/fpga/ap_core.qpf
b179da5e32941123532c7dcc88c428ead8ab3b68 src/fpga/ap_core.qsf
f6786a86b2ad44ad99407bfbd7fc86d69fa7a29b src/fpga/apf/apf.qip
048ddcf02a4d656c9a583689faa7b969d2f9db83 src/fpga/apf/apf_constraints.sdc
f0deb04de19ad06494111cafa307b796574ac7fc src/fpga/apf/apf_top.v
2f3bfc57bf88d9e4496818d8219d11743b0dcaa1 src/fpga/apf/build_id.mif
eb598fdc509409a4479df50863b84fb0460ff1bf src/fpga/apf/build_id_gen.tcl
64817889459da66c75e79b0277f6c5c91a97c96d src/fpga/apf/common.v
eda3bb04cc28154b1641a95827baa7e2c1cbadf6 src/fpga/apf/io_bridge_peripheral.v
d14b33cee1ebf8c01739f46a38d8d27f9f970ea9 src/fpga/apf/io_pad_controller.v
66ff6a6cfa94ddee6f00558f7c2024ac434dbc4b src/fpga/apf/mf_datatable.qip
c285fd9ea65c8f4c9f64d5096272a4e801d5dada src/fpga/apf/mf_datatable.v
18ae54d6dd36626e831832d7524330539b41b774 src/fpga/apf/mf_ddio_bidir_12.qip
6851f86f5e05479b948733b202ed5b38a1ec9832 src/fpga/apf/mf_ddio_bidir_12.v
a0223a519e27e54eeee1597e81d36a5b09833d2d src/fpga/core/ar_stub.asm
c9510cefba489a97d1065d2d24840342b3fe2215 src/fpga/core/ar_stub.hex
9afdc1fffc9a04a9a450eae5ad5f428480dde7be src/fpga/core/ar_stub.mif
ef9dd5b4253681b1fa09fb788ac86112f3137d9e src/fpga/core/atari7800_pocket.sv
0918154813f4bf9cb0442cf96e1b9712cfb8997e src/fpga/core/atarivox/atarivox.sv
121f9d2725a228a8bc63a501348e7dd36deb0b07 src/fpga/core/atarivox/avox_engine.sv
d4c4918d6ed21e20214b5382959bc466e77c7304 src/fpga/core/atarivox/avox_rx.sv
233791809e46f4d9898443ee451108b57b3bc138 src/fpga/core/atarivox/vox_drom.hex
654781759b6ea643f2ef87ce99b0a3c3be7933f0 src/fpga/core/atarivox/vox_drom.mif
63fbcc1bc409372b2e93eccf41a6ce013b6be6bc src/fpga/core/atarivox/vox_irom.hex
55809ff325179336b0ea3e37a8e7603b1cf15d2d src/fpga/core/atarivox/vox_irom.mif
1cc81a34bf906fcaa5797afa373452d505adb57f src/fpga/core/audio_filter.sv
bdcec53db76acbc12256960ab5e85ba1ca2384a1 src/fpga/core/bupchip/bup_asset_cache.sv
94d158713b56b6958ae78f5fbb78638d038a1c3a src/fpga/core/bupchip/bup_asset_wr.sv
e540b143a9009c6259f083467732e9a55a2d53af src/fpga/core/bupchip/bup_capture.sv
efaab4600d1a2437a1f08b6f98b31697f723c649 src/fpga/core/bupchip/bup_cpu.sv
41b854fd8f86d646f049a5455ffc549d5f21a5cb src/fpga/core/bupchip/bup_dbg_snap.sv
a1aa0b0739517461b5141ede925de58d0c1b1fad src/fpga/core/bupchip/bup_load_probe.sv
aea94c0aafd97203ce257ae7b6d1ad1b59eb9846 src/fpga/core/bupchip/bup_status_osd.sv
281e2a706ec9261687c89c589d210b9cd0449c10 src/fpga/core/bupchip/bup_tick48k.sv
1b84dd5736500f0db8fb94a6553f321de1b4370f src/fpga/core/bupchip/bupchip_pocket.sv
4256984e5c9ffdfc08aeed17e9722862a5839187 src/fpga/core/bupchip/daria_call.sv
b4a5e16f95c84b2c280f6c6fd8dada7d1d3ccd8c src/fpga/core/bupchip/daria_fe.sv
1c72b3c748bf7ddc54f146b8ffca45ba55a55638 src/fpga/core/bupchip/daria_fe_arb.sv
4c5901668056e23081efcde2e32cb273c0fb7f70 src/fpga/core/bupchip/daria_fe_audio.sv
b72645910c9796767a6924c63d57f3fb49d93157 src/fpga/core/bupchip/daria_fe_call.sv
04a4f7babfb98bf5a052eed1bc878a1bad65a2ea src/fpga/core/bupchip/daria_fe_copy.sv
123416012ffbacf001d830a111cd86f61b171841 src/fpga/core/bupchip/daria_fe_core.sv
2594b4b2a38b221b0ca853033a94a6bf7c855e33 src/fpga/core/bupchip/daria_fe_dec.sv
53f3d43f76ffc13f537641b60aea261b594aece6 src/fpga/core/bupchip/daria_fe_guard.sv
7e0ceb01bf315a784a715a978676a9103740d723 src/fpga/core/bupchip/daria_fe_pkg.sv
ffce46b75f519d8922ba244d708d7eea17c4fe05 src/fpga/core/bupchip/daria_fe_seq.sv
b93ca05020397568c655ba0813e84e73a224c03d src/fpga/core/bupchip/daria_mem.sv
e30d7e76383a0dad07228bd814848bd6897d8c94 src/fpga/core/bupchip/daria_mmio.sv
9aeaac991b2d207023be0e2150262a66bf4ff5fa src/fpga/core/bupchip/daria_smp.sv
afaf797982600652d7bd5bfefc5c0727f6ed92e0 src/fpga/core/core.qip
7858a62443d7f4dc103ec15fcc66c2675a1b03a9 src/fpga/core/core_bridge_cmd.v
0b367bf03fb11d9ba388602c427178fb40ada750 src/fpga/core/core_constraints.sdc
f277e8be0b7539e9d23d60c7fb4268cf527c35f3 src/fpga/core/core_top.v
7e7a50ba2f1dc30037b3b77ff22c4a2b623657e5 src/fpga/core/daria.qip
2ee3335bbbad3a4eedc7e41f02dd9e305d365fc0 src/fpga/core/daria_constraints.sdc
13b25624dfd1f3b3c4a2a97d41e3501ebd9e1f2f src/fpga/core/daria_sync.tcl
01f9dd2145d98de670ab87902e9c62f97dfc8a1e src/fpga/core/pll/pll_cfg/altera_pll_reconfig_core.v
2cf9ce5680fd744118dc3d45bb04ab466fabaf0a src/fpga/core/pll/pll_cfg/altera_pll_reconfig_top.v
47135c2bb11f1c0ad8b8d69c11a97aed58b9287f src/fpga/core/pll/pll_cfg/altera_std_synchronizer.v
68fd2a335c30e4956eaec99cb9995dca11260a8b src/fpga/core/pll/pll_cfg/pll_cfg.v
2537a95a1502781753cd1e30e15e8196fb3e98ab src/fpga/core/pll/pll_core.qip
8f8db5cb6f3e369699bb7358740effbd07643341 src/fpga/core/pll/pll_core.v
b7062fecbdd9e8c979bf149e15fd90423ace211e src/fpga/core/pll_region.v
e5b7102463dc1aebd039a75de24a33f0ca2ae331 src/fpga/core/pokey_adapter_watson.sv
d8eade9ef65ed9495a64cb1eda5c4bc4e506e351 src/fpga/core/sram_ctrl.sv
97a7af8f58280e3ecb0816c481881a02b9acc17b src/fpga/core/stick_dirs.sv
51a93b96abc3aa413974a2643211342c4617ee91 src/fpga/core/virtual_axis.sv
806ad97d387c1502790f79d0462b219912bbfd3b src/fpga/core/virtual_axis5.sv
10563a739b4a8a76c07ff7e6a16ea99bff3a66d9 src/fpga/mister/LICENSE
47dd7bfba71ebecbafeffa54af5215c9fb75fa62 src/fpga/mister/POCKET_CHANGES.md
8608e04001a11608397aeeb4235d4da960e6dd9d src/fpga/mister/UPSTREAM_COMMIT
f6790dbecae2685ef9d46fed7ef8dbf475b1f4c0 src/fpga/mister/rtl/6502/mos6502.qip
eb3b0874b5aed3aa6a50bf62d555d9bfe2573189 src/fpga/mister/rtl/6502/mos6502.sv
ff3dbda117e96772b2be7b9c8fc1a32b4772664a src/fpga/mister/rtl/6502/mos6502_alu.sv
c21765d180b6e75069d56d89ed67af35f89b927f src/fpga/mister/rtl/6502/mos6502_ctl.sv
54fdb2a64688d82b3ecd921a938efff511d832cc src/fpga/mister/rtl/6502/mos6502_decode.sv
82015fb51f0ae4daf6b876f4682ac13f6646a04f src/fpga/mister/rtl/6502/mos6502_dp.sv
dc2e887613b6735028acbccf001cd0a0aec35664 src/fpga/mister/rtl/6502/mos6502_pkg.sv
777899e3f1fa694482af027e006b6c350409709b src/fpga/mister/rtl/6502/sally.sv
b23c35bc97452d0761677a927854485bb80526e5 src/fpga/mister/rtl/EEPROM_24LC256.sv
d094a6a2c829e0e84c61c2b2830a09d5b50acf7b src/fpga/mister/rtl/Maria/DMA.sv
b357eb63425ce60aa5bfc6f1ce9dfb1e0ffd49fb src/fpga/mister/rtl/Maria/control.sv
c5f4f71ebc093c748c616deda8a09e241f8d8c06 src/fpga/mister/rtl/Maria/line_ram.sv
c81a45c53db4f23b296c28fce05ee0687f094803 src/fpga/mister/rtl/Maria/maria.qip
c753f01f4bc5eeffb9ce9744640c3b646aaae853 src/fpga/mister/rtl/Maria/maria.sv
a30b2eb3add3a5b2ee65de413715e4d29e69dacb src/fpga/mister/rtl/Maria/video_sync.sv
8cc9b9456001f1efd786d3608ea9c57620c00156 src/fpga/mister/rtl/Minnie/Minnie.qip
54b85534d26c9f91cbd9ef81d26fa278c178aeec src/fpga/mister/rtl/Minnie/minnie-programmers-guide.md
33b38fe2248a8c95b68a8c42d07032d5381b27fe src/fpga/mister/rtl/Minnie/minnie.sv
cda27fb95cf16da2c04f7aaf249fd56f27ed3294 src/fpga/mister/rtl/Minnie/minnie_datapath.sv
099e685efa65b82fca678bd99ff2eb8144c6c0b5 src/fpga/mister/rtl/Minnie/minnie_out.sv
191aec3127f9abd66aeb83965683d30f44651779 src/fpga/mister/rtl/Minnie/minnie_poly.sv
91c255a00e8ceb6ac3505d9bc7bcba487403e7d9 src/fpga/mister/rtl/Minnie/minnie_regs.sv
0aa9ba523a6db1be46c8f9162519fc564ab9373d src/fpga/mister/rtl/Minnie/minnie_seq.sv
3669f8aab206e47f624975a6857ce98cd553ddf1 src/fpga/mister/rtl/Minnie/minnie_wave.hex
a5b782ae804ac7aee34089d1fe2599fa752b005d src/fpga/mister/rtl/Minnie/minnie_wave.mif
4f2340645d4ff5dae35f84508d05a1c34ae6defe src/fpga/mister/rtl/Minnie/minnie_wave.sv
bda7ac79c9d9d0a4a477746a94d059879c4f7119 src/fpga/mister/rtl/Pokey/Pokey.qip
ebacc6f5453c6a28196fb66ede3b556cb33394b4 src/fpga/mister/rtl/Pokey/pokey.sv
5718824551648227fb7b0c29c251f6c4b143e959 src/fpga/mister/rtl/Pokey/pokey_adapter.sv
3cfd0fac587c51ea10b1e0beb18538350b4c4db8 src/fpga/mister/rtl/Pokey/pokey_audio.sv
f5488d750c12285070a04c9f90e7907d9d00174a src/fpga/mister/rtl/Pokey/pokey_bus.sv
8dfc0a2a18906e00fe42b8d9832c43d07465563d src/fpga/mister/rtl/Pokey/pokey_cells.sv
4a2b4d228ba86dbf84b143281a71c5c344f2713e src/fpga/mister/rtl/Pokey/pokey_chan.sv
313c3080c03de9f2443a991477315383e194b406 src/fpga/mister/rtl/Pokey/pokey_clkdiv.sv
6836c46a17f55aa76712103f18eefd64a78361b8 src/fpga/mister/rtl/Pokey/pokey_clkgen.sv
ef4b989623a6058ed71647ed88c4c77af638ae31 src/fpga/mister/rtl/Pokey/pokey_irq.sv
47b48acb7cc977f4569a207e206a2626ebf4aecc src/fpga/mister/rtl/Pokey/pokey_kbd.sv
292ca462cbb48fa5f5ee219fd738f0db8fcbe53c src/fpga/mister/rtl/Pokey/pokey_mixer.sv
c5fcc20bea039c4697801d52c3b147c67591e247 src/fpga/mister/rtl/Pokey/pokey_poly.sv
825ad795874c1fb49e5397c5585a5c05c9d30faa src/fpga/mister/rtl/Pokey/pokey_pots.sv
374cc3201b25db540627c3d5d3a94ac47fd59fa4 src/fpga/mister/rtl/Pokey/pokey_serial.sv
e7a18b3126c03806dd762181a7bd9dd83b4b2e45 src/fpga/mister/rtl/PokeyWatson/complete_address_decoder.vhdl
c67ada0d6b3c95c006e7aa0ae7d6c3c7c25c8694 src/fpga/mister/rtl/PokeyWatson/delay_line.vhdl
296a6c4ab30567b6cbffb81c235785b56bac069f src/fpga/mister/rtl/PokeyWatson/latch_delay_line.vhdl
1dd6e4bf68bfa0b632ec1fb51a998d3329f511a2 src/fpga/mister/rtl/PokeyWatson/pokey.vhdl
fd7c1dc3920e1f94c850fe87a397fbd52eb0bdf2 src/fpga/mister/rtl/PokeyWatson/pokey_countdown_timer.vhdl
5ce97b135c135574a95f18956a9d731e2c939902 src/fpga/mister/rtl/PokeyWatson/pokey_keyboard_scanner.vhdl
9c00918c99a8b0bc630534474e6b26e140846d36 src/fpga/mister/rtl/PokeyWatson/pokey_noise_filter.vhdl
964168fffed0b6963af6de660ca0ea4d2137c773 src/fpga/mister/rtl/PokeyWatson/pokey_poly_17_9.vhdl
76ff2b1907e14e2d27d4a440d2dff89a7173e0d7 src/fpga/mister/rtl/PokeyWatson/pokey_poly_4.vhdl
e64b9324b36a4b74e31664bcf32543497c2638ec src/fpga/mister/rtl/PokeyWatson/pokey_poly_5.vhdl
e84b5360d81047dfa1cf2e0d12e788778395761a src/fpga/mister/rtl/PokeyWatson/synchronizer.vhdl
998e8958c842056a50a271dfef8e786b2ffe4426 src/fpga/mister/rtl/PokeyWatson/syncreset_enable_divider.vhd
7d36cab41213ddaa12bb67d0e01431ae77c866ca src/fpga/mister/rtl/RIOT/M6532.sv
35810c524c250969ffbdeb0f03ac54df93e76ad0 src/fpga/mister/rtl/SN76489/SN76489.qip
d88aa9d3b7189a5c62a0f3ef97cd9e01e064c465 src/fpga/mister/rtl/SN76489/sn76489.sv
43a845b3d79799f86675a38c97c98351c8b9f4da src/fpga/mister/rtl/TIA.sv
54c37da2b82669f2f63293462437a6b87d896aed src/fpga/mister/rtl/a78_cart_extent.sv
5008ddfcf53c02e82d7eee2e57c38e5672ef89f6 src/fpga/mister/rtl/arm7tdmi/.DS_Store
a84124ab29e899be23a21f452a1c20ede9e55a28 src/fpga/mister/rtl/arm7tdmi/arm7tdmi.sdc
d9de756e4cc33929159a4a5e859e41c13a47dfb6 src/fpga/mister/rtl/arm7tdmi/arm7tdmi_core.sv
feaf8f2f5ae91b94e8c86ea970a96c11776f26db src/fpga/mister/rtl/arm7tdmi/arm7tdmi_pin_wrapper.sv
cf9fbb70e2bbfb7ca8592b9cad6fd03060f9b987 src/fpga/mister/rtl/arm7tdmi/arm7tdmi_pkg.sv
d26bb45477960b25eb64e5fed56918f06dbc3a11 src/fpga/mister/rtl/arm_host.sv
97928c549c707e38985ebbc5c9c0ad6101a2cd70 src/fpga/mister/rtl/arm_mapper_audio.sv
24e0d99c9820abc537ecc4b3d87eb61995a27a3c src/fpga/mister/rtl/arm_mapper_controller.sv
75d6f8cef0dcb5c536ddad627223bbf03fd348a0 src/fpga/mister/rtl/arm_mapper_memory.sv
207d6da943d72fec2b1da0e9f6956a90d6723977 src/fpga/mister/rtl/arm_mapper_ram_init.sv
2b074a627290a4856cda2e67fd609f019ffb41d2 src/fpga/mister/rtl/arm_mapper_subsystem.sv
56554d917d5fa646a4c9d9fed3840da2e81ba6a9 src/fpga/mister/rtl/arm_mapper_tables.sv
2fafab7ca293da0852d6b6aeebe1d42d169b2053 src/fpga/mister/rtl/arm_mapper_writeback.sv
babbfeddd17a1ceac681ad4b90b24dab21d9e800 src/fpga/mister/rtl/banks2600.sv
488e3c7f685e2431f18290827e41f945a066a328 src/fpga/mister/rtl/bram.v
2b12960a83dbc43d9532119cff86272d960a6d6e src/fpga/mister/rtl/bupchip_asset_ddr.sv
8d230f44653c09ff83d5f4cbeb9534192b55157a src/fpga/mister/rtl/bupchip_memory.sv
cf4f89487d7e6067261b22233e0dc73a6e1fe09a src/fpga/mister/rtl/bupchip_peripheral.sv
073b8ea40dd72e43ff0037fa92b13a0d4450acd9 src/fpga/mister/rtl/bupchip_subsystem.sv
5e8fca494e70b4504815a42db752d980648585a6 src/fpga/mister/rtl/cache_ram.v
3a2ee3a770765d3124a310441b9e7b47a4857d38 src/fpga/mister/rtl/cart.sv
0b948946bc35a9643feba1e9aaab913d158e5cb9 src/fpga/mister/rtl/cart2600.sv
b7f963f118e14d42ffada9f5bf8cabd5c71e57af src/fpga/mister/rtl/cart_ram_tdp.sv
2e785265d514b526704fbb41e0c9e9b0e7eee74c src/fpga/mister/rtl/cdf_fastjump_table.sv
8a11d9a7cef18780654c377ced6851b2b3ebaf36 src/fpga/mister/rtl/cofi.sv
65c41cd99ccf33387d7c62d89e70a876e52121c3 src/fpga/mister/rtl/composite_decoder.sv
7bbcba510105a8047f4ce6d5faf1324b0514eea7 src/fpga/mister/rtl/composite_out.sv
1d424d0355715b352620e931268bc59b97e2c58b src/fpga/mister/rtl/ddram.sv
a9eb90c8394f41f1dcd2fa129fe6403d2ef11f96 src/fpga/mister/rtl/detect2600.sv
69d4c5fb04e14279eebfe5423e45edb7cc7d4636 src/fpga/mister/rtl/dpram.vhd
1fc5309becb91aa57e5a7b0ba30fc342a2e5504d src/fpga/mister/rtl/fa2_nvram_bridge.sv
3154491436ff39c884dbad8c24a7e93d0b8d63ad src/fpga/mister/rtl/jt51/deprecated/jt51_sh2.v
99069d29730aacadcfbda1dce7123bd9cef69d5c src/fpga/mister/rtl/jt51/filter/jt51_dac2.v
c0b6c1bba5ca7f6479230d8921c199fdb77416ba src/fpga/mister/rtl/jt51/filter/jt51_fir.v
b343f4d5933061c9b7e88e84e66339cf853b090d src/fpga/mister/rtl/jt51/filter/jt51_fir4.v
256cf052c275db5b0f4c61110f6e2bd5182b3b29 src/fpga/mister/rtl/jt51/filter/jt51_fir8.v
377321ecc0e26212a322151a101b8af9838f6359 src/fpga/mister/rtl/jt51/filter/jt51_fir_ram.v
d9d2980994ccc9baf29ff587a0262176650a7ce4 src/fpga/mister/rtl/jt51/filter/jt51_interpol.v
f1fea5b767614bfe84ff3b9af321d5868ec40d89 src/fpga/mister/rtl/jt51/filter/jt51_sincf.v
53387d7a6c654428c42224b60ac3d2d66b87ab90 src/fpga/mister/rtl/jt51/jt51.qip
f0e92d469588cf3d4afa049bd3d4058993194b10 src/fpga/mister/rtl/jt51/jt51.v
3b601d4f3b1350b2ce553988e754ee47aa977e60 src/fpga/mister/rtl/jt51/jt51_acc.v
a4f38009ab84509c231f3207652257efb7336898 src/fpga/mister/rtl/jt51/jt51_csr_ch.v
013681224d4b5ec35e1fd8f2eb8a8b01514cd25a src/fpga/mister/rtl/jt51/jt51_csr_op.v
bfa44e7520495d08c77cdae29b74c5813e714a99 src/fpga/mister/rtl/jt51/jt51_eg.v
39f559dd0fd2282d9ac9c4a4d26ea74d05b3822d src/fpga/mister/rtl/jt51/jt51_exp2lin.v
f3742b594c8bc655b640593979dd0d9bc415ad21 src/fpga/mister/rtl/jt51/jt51_exprom.v
b9865d27fa74cb808f78c323e0fd7dc63da4d22c src/fpga/mister/rtl/jt51/jt51_kon.v
b48bc416f9e0116c88805433b7eca712f40d671d src/fpga/mister/rtl/jt51/jt51_lfo.v
75d408ed1112727c20d81059229a919c435a7558 src/fpga/mister/rtl/jt51/jt51_lin2exp.v
ca53f14a899318c2b29be9b365f9c7fe04be565a src/fpga/mister/rtl/jt51/jt51_mmr.v
a7346ba877a0d6041b4071ed4b50e6012371cde6 src/fpga/mister/rtl/jt51/jt51_mod.v
1f7d78f6359c1fc6aea536a50739816d3a409f2b src/fpga/mister/rtl/jt51/jt51_noise.v
4b6a47f569f129dff930b522b48238894e463669 src/fpga/mister/rtl/jt51/jt51_noise_lfsr.v
2995a055826fb9a2f1a4fa175c31e3b70412f974 src/fpga/mister/rtl/jt51/jt51_op.v
d73d4109273e0c426eee8e03f20f0bf8f5819df0 src/fpga/mister/rtl/jt51/jt51_pg.v
d9ebc972d1ceba1800561f8db99b5b7dbc76d4b9 src/fpga/mister/rtl/jt51/jt51_phinc_rom.v
802f9743cb8e8a793743c98ddf3f70ae7675b284 src/fpga/mister/rtl/jt51/jt51_phrom.v
150d633c6f1d927d775800b010b5e4940d404aae src/fpga/mister/rtl/jt51/jt51_pm.v
3dd627ca9edc7b1b5454c39c59b6692a743f090f src/fpga/mister/rtl/jt51/jt51_reg.v
8b2335a5b3f1b8ba833f0df0ab3f8e9c44ce5f7d src/fpga/mister/rtl/jt51/jt51_sh.v
4da103ca6abf097c379bed834414fc367ecc81c2 src/fpga/mister/rtl/jt51/jt51_timers.v
2814da6cb9cb8d1c615f5f49d9c7534de5b972d5 src/fpga/mister/rtl/lightgun.sv
060f409009ed7099ba69ff4f2c3ea8c4c8dd52ec src/fpga/mister/rtl/mapper_bus.sv
b4ef4bbfa3e34ea84dbd4561ec3abb37cab21503 src/fpga/mister/rtl/mapper_cdf.sv
a2bd8d1f06312e5ff199b2f4614a0ec1b2e784cc src/fpga/mister/rtl/mapper_dpcplus.sv
e37e87f4108a979a2cd5bb9fd276edb496b1cc13 src/fpga/mister/rtl/mapper_fa2.sv
85ba67e9f6dbc3f9fe70ea7c3165eeb0353c27dd src/fpga/mister/rtl/mem0.hex
bd728e5bb741f3456aea03b1e2b862d18182bf5e src/fpga/mister/rtl/mem0.mif
7234ee1d4dcc8f8afea43c06a000965931a13699 src/fpga/mister/rtl/mouse_st.sv
301aa28d4fa677942c863e4b97b2336d4d9bf19f src/fpga/mister/rtl/ooo.hex
a63bd2b95ae279605378c20dd068001c323b23b7 src/fpga/mister/rtl/ooo.mif
31a420bc714ed0cc6b9f830b62c8face18e2d603 src/fpga/mister/rtl/paddles.sv
57a239da144b902e8f15c1bf476b9ce14c1878e6 src/fpga/mister/rtl/palettes/NCOOL.hex
ac7e8d56bd3d21708e52134851ee3e486957eb0a src/fpga/mister/rtl/palettes/NCOOL.mif
25dfa4cd574f8b5760e0cf0f2a3176813980a2bf src/fpga/mister/rtl/palettes/NHOT.hex
37145fc6513e8dac4d3cc07310f068c4ce9e6cb4 src/fpga/mister/rtl/palettes/NHOT.mif
f090a832f47e24b6778758b10e45e27a99fab7ef src/fpga/mister/rtl/palettes/NWARM.hex
385bc2d2778d679d1a01863673c1778065e1d6e6 src/fpga/mister/rtl/palettes/NWARM.mif
d1996b6fe7a921a9667f9f02a27ebf9d17914baa src/fpga/mister/rtl/palettes/PCOOL.hex
1e5d874ab466d7539c85a7fb8f5162d39a777469 src/fpga/mister/rtl/palettes/PCOOL.mif
3ab71b9194d0648974e63ecb5ff123418b37d968 src/fpga/mister/rtl/palettes/PHOT.hex
08fd4a9cab0a827b87fed8ec16f926fb21fc2563 src/fpga/mister/rtl/palettes/PHOT.mif
cc12eb4c9398253586202537de4d3d43139230d5 src/fpga/mister/rtl/palettes/PWARM.hex
60a66bb9dceef93d276400d73d0685c096e701ef src/fpga/mister/rtl/palettes/PWARM.mif
aeb93857e06b3a9bd9816871764e63f8c24262cc src/fpga/mister/rtl/pll.qip
6369ef440cf4eeeea81cd72912c2358ac57ae0c0 src/fpga/mister/rtl/pll.v
9f8ded1ff64443c344932befaaffa2162591714d src/fpga/mister/rtl/pll/pll_0002.qip
c06fb429ab92d1aefc87607b0438fdae5022198e src/fpga/mister/rtl/pll/pll_0002.v
a1c8958b32c32aee81f24fef50522a6fdae454ef src/fpga/mister/rtl/ps2_to_pokey.v
7bc10dc3775bdc7d87e5a933ab1026e881e3c700 src/fpga/mister/rtl/sdram.sv
17d243a4569399741bc39153d2370d40d8435c52 src/fpga/mister/rtl/souper.v
20555f6160b6c8e73f2601f2a086b9a7ae7296c7 src/fpga/mister/rtl/t65/T65.vhd
2b67ea46c11f30b192adc0a8f104197729bbf36c src/fpga/mister/rtl/t65/T65_ALU.vhd
f55641486c6d44c09fb7cfb912027dbfdf86fba4 src/fpga/mister/rtl/t65/T65_MCode.vhd
63b119b4acb5a12980a5d1d98d9806e232d51264 src/fpga/mister/rtl/t65/T65_Pack.vhd
b165455fbfa9bc07059bcefaeb003a882889b59e src/fpga/mister/rtl/t65/t65.qip
5426606ee7eded30b027a66419e23dff1bbcc35b src/fpga/mister/rtl/top.sv
dc6513d41b131d4789f3a5518a57812ef3872ae5 src/fpga/mister/rtl/video_mixer_plus.sv
e5dc41351ca3af0f503278651a8a51e688b049ce src/fpga/mister/rtl/video_mux.sv
b38fd20e6bc7143de4ebe38a5c8a4fb3103ad7b1 src/fpga/pocket_utils/LICENSE
5c1947e7dcdf7b614ec5fe5eb6a9aea3949ecc3f src/fpga/pocket_utils/data_loader.sv
2f7797f332826d811699eb5df947a212b2f9a4af src/fpga/pocket_utils/psram.sv
fee9988f970f1fc96be9066d466a5c328977a83d src/fpga/pocket_utils/sound_i2s.sv
895e72eaa8a8609c8fc0e67e17c3e10e024eaa7b src/fpga/pocket_utils/sync_fifo.sv
ccf17bffe88b3ddd5f74eaa5bf9eec392087712c tools/atarivox/sjhw.py
ee38fd4d342aa818e30328459586839de428a1d5 tools/atarivox/sjsynth.py
f4dc4da679753c88cf25a94300918ef6b5d5bfce tools/atarivox/stella_voxlog.py
e67ce795fd3a60f53aff5fb0877f0c206f667755 tools/atarivox/vox_check.py
1a74d25bc11b93e6a25bab8f0109d949a895aad7 tools/atarivox/vox_rom.py
e04c3769c065dfb292b000da61d56323fc8b3220 tools/atarivox/voxeng.py
165d75e57bf89a5def81c87a188896bcbaa8943e tools/atarivox/voxprog.py
1bcedd00573d4e1e924ea2cda2b78d0679ab0c05 tools/bin2mem.py
c26341209271eb95051f4b9da36d27f3857c43c2 tools/fix_hsc_save.py
3ba993e6c3eef7d9a551a94c1d28268c16c1d4bc tools/hex2bin.py
3ca1f0c8e5eaa192f5944b4ffd9af67047086d22 tools/package.sh
43b123ebe0167f0381fdfb4b6b2d6350b523a154 tools/reverse_bits.py
```
