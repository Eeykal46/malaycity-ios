// McLauncher-Bridging-Header.h - Dedahkan API C Husk kepada Swift.
//
// Husk 3.1: driver GTA SA ada dalam husk-tl-gtasa.c:
//   tl_gta_start(&cfg)  - muat libGame.so + siapkan Java oswrapper
//   tl_gta_run()        - thread enjin (frame loop)
//   tl_gta_touch(...)   - sentuh
#ifndef MC_BRIDGING_HEADER_H
#define MC_BRIDGING_HEADER_H

// Konfigurasi + API GameActivity/GTA SA
#include "husk-tl-gameactivity.h"
#include "husk-tl-gtasa.h"

// JIT arena (tl_jit_reserve_bottom) + audio (tl_audio_install)
#include "husk-jit-arena.h"
#include "husk-tl-audio.h"

// mc_husk_bridge.c: paksa linker kekalkan simbol (rujukan langsung)
int mc_husk_semak_api(void);

#endif // MC_BRIDGING_HEADER_H
