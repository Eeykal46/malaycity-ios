// mc_peta.cpp - Pelaksanaan pencari alamat mudah alih.
//
// Lihat mc_peta.h untuk sebab reka bentuk ini.
//
// Nota penting: kita TIDAK cache hasil dlsym secara global tanpa kunci.
// Kalau perlu laju (dipanggil beribu kali), tambah cache + pthread_mutex.
// Buat masa ini: panggilan jarang (masa init), jadi dlsym terus cukup.
#include <dlfcn.h>
#include <string.h>

#include "mc_peta.h"
#include "mc_simbol.h"

extern "C" {

static const McSimbol* cari(uintptr_t offset) {
    // jadual kecil (199) - carian linear lebih cepat drpd hash untuk saiz ini
    for (int i = 0; i < MC_SIMBOL_JUMLAH; i++) {
        if (MC_SIMBOL[i].alamat == offset) {
            return &MC_SIMBOL[i];
        }
    }
    return NULL;
}

uintptr_t mc_alamat(const char* libNama, uintptr_t offset) {
    const McSimbol* e = cari(offset);
    if (!e) return 0;               // alamat tak ada dlm jadual
    if (!e->simbol) return 0;       // 33 alamat tanpa simbol - pemanggil mesti semak

    void* h = dlopen(libNama, RTLD_LAZY);
    if (!h) return 0;
    void* sym = dlsym(h, e->simbol);
    // JANGAN dlclose: lib enjin mesti kekal dimuatkan.
    if (!sym) return 0;
    return (uintptr_t)sym + e->offset;
}

int mc_alamat_berjaya(void) { return MC_SIMBOL_BERJAYA; }
int mc_alamat_jumlah(void)  { return MC_SIMBOL_JUMLAH; }

const char* mc_alamat_simbol(uintptr_t offset) {
    const McSimbol* e = cari(offset);
    return e ? e->simbol : NULL;
}

} // extern "C"
