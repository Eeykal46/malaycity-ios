// McLauncher-Bridging-Header.h - Dedahkan API C Husk kepada Swift.
//
// Tanpa fail ini, Swift tidak nampak husk_tl_* dan mc_husk_semak_api() ->
// "cannot find 'husk_tl_scan' in scope".
//
// Diset dalam project.yml: SWIFT_OBJC_BRIDGING_HEADER
#ifndef MC_BRIDGING_HEADER_H
#define MC_BRIDGING_HEADER_H

#include "husk-tl.h"

// mc_husk_bridge.c: paksa linker kekalkan simbol Husk (rujukan langsung)
int mc_husk_semak_api(void);
int mc_husk_tersedia(void);

#endif // MC_BRIDGING_HEADER_H
