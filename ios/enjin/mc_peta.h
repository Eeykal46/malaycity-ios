// mc_peta.h - Pencari alamat mudah alih (Android + iOS).
//
// MASALAH: client SA-MP menyentuh enjin melalui `g_libGTASA + 0x2BD618`.
// Alamat itu sah untuk SATU binari sahaja. Binari iOS berlainan.
//
// PENYELESAIAN: setiap alamat dipetakan ke (nama simbol, offset) oleh
// ios/alat/jana_simbol.py. Di sini kita cari simbol itu melalui dlsym dan
// tambah offset. Hasilnya kod client TIDAK perlu diubah antara platform.
//
// Guna:
//     uintptr_t p = mc_alamat("libGTASA.so", 0x2BD618);
//     if (!p) { log("simbol tiada"); return; }
//
// 83% alamat (166/199) boleh dipetakan. Baki 33 tiada simbol - untuk itu
// mc_alamat() pulangkan 0, dan pemanggil MESTI semak. Jangan sekali-kali
// guna alamat tegar untuk baki itu di iOS.
#ifndef MC_PETA_H
#define MC_PETA_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Cari alamat sebenar bagi `offset` dlm lib yg dimuatkan.
// Pulangkan 0 jika:
//   - simbol tidak wujud dlm jadual (33 alamat tanpa simbol)
//   - dlsym gagal (simbol tiada dlm binari semasa)
uintptr_t mc_alamat(const char* libNama, uintptr_t offset);

// Berapa banyak alamat dalam jadual boleh dipetakan (untuk log/diagnostik).
int mc_alamat_berjaya(void);

// Jumlah alamat dalam jadual.
int mc_alamat_jumlah(void);

// Nama simbol bagi satu offset (NULL jika tiada). Untuk log.
const char* mc_alamat_simbol(uintptr_t offset);

#ifdef __cplusplus
}
#endif

#endif // MC_PETA_H
